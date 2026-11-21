import AmcamCameraModel
import AmcamImagingCore
import AmcamImagingRuntime
import AmcamImagingGenTLAdapter
import AmcamImagingState
import Foundation
import Combine

@MainActor
final class CameraApplicationModel: ObservableObject {
    @Published private(set) var devices: [AmcamDevice] = []
    @Published var selectedDeviceID = ""
    @Published private(set) var latestFrame: RGB8Frame?
    @Published private(set) var isStreaming = false
    @Published private(set) var cameraCapabilities: AmcamCameraCapabilities?
    @Published private(set) var controls: AmcamControlSnapshot?
    @Published private(set) var status = "Select an AmScope camera"
    @Published var errorMessage: String?
    @Published var isSettingsPresented = false
    @Published private(set) var framesPerSecond = 0.0

    private var cameraProvider: AmcamCameraProvider?
    private var candidatesByID: [String: AmcamCameraCandidate] = [:]
    private let cameraLifecycle = CameraSessionLifecycle()
    private var frameConsumerTask: Task<Void, Never>?
    private var lifecycleEventTask: Task<Void, Never>?
    private var deviceMonitorTask: Task<Void, Never>?
    private var sessionNeedsRecreation = false
    private var featureDescriptors: [CameraFeatureDescriptor] = []
    private var hasInitialized = false
    private var cameraSelectionGeneration: UInt64 = 0
    private var profileRegistry = AmcamCameraProfileRegistry()
    private var stateResolver = AmcamCameraStateResolver()
    private var frameRateEstimator = FrameRateEstimator()

    var selectedDevice: AmcamDevice? {
        devices.first { $0.identifier == selectedDeviceID }
    }

    @Published private(set) var currentResolution: AmcamResolution?

    func isFeatureWritable(_ name: String) -> Bool {
        guard let descriptor = featureDescriptors.last(where: { $0.name == name }) else {
            return false
        }
        return descriptor.isAvailable && descriptor.isWritable
    }

    func enumerationValues(for name: String) -> [String] {
        featureDescriptors.last(where: { $0.name == name })?.enumerationValues ?? []
    }

    func numericRange(for name: String) -> CameraFeatureNumericRange? {
        featureDescriptors.last(where: { $0.name == name })?.numericRange
    }

    func normalizedNumericValue(_ value: Double, for name: String) -> Double? {
        guard let range = numericRange(for: name) else { return nil }
        return stateResolver.normalizedNumericValue(value, range: range)
    }

    func initialize() {
        guard !hasInitialized else { return }
        hasInitialized = true
        loadProfileConfiguration()
        initializeCameraProvider()
    }

    func refreshDevices() {
        let operation = beginCameraSelectionOperation()
        Task { await refreshDevicesOwned(operation: operation) }
    }

    private func refreshDevicesOwned(
        operation: UInt64,
        backgroundMonitor: Bool = false
    ) async {
        guard isCurrentCameraSelectionOperation(operation) else { return }
        guard let cameraProvider else {
            status = "AmScope camera provider is unavailable"
            return
        }
        let report = await cameraProvider.discover()
        guard isCurrentCameraSelectionOperation(operation) else { return }
        let discoveredDevices = report.devices.map(\.device)
        let discoveredCandidates = Dictionary(
            uniqueKeysWithValues: report.devices.map { ($0.id, $0) }
        )
        let previousDeviceIDs = Set(devices.map(\.identifier))
        let discoveredDeviceIDs = Set(discoveredDevices.map(\.identifier))
        let topologyChanged = previousDeviceIDs != discoveredDeviceIDs
        let selectedDeviceIsPresent = discoveredDevices.contains {
            $0.identifier == selectedDeviceID
        }

        devices = discoveredDevices
        candidatesByID = discoveredCandidates

        // The same SDK identifier can return after a USB reconnect. A previous
        // callback failure or an observed removal invalidates the old session
        // even when the identifier is present again.
        if !selectedDeviceIsPresent {
            sessionNeedsRecreation = true
        }
        if sessionNeedsRecreation {
            guard await closeSession(expectedGeneration: operation),
                  isCurrentCameraSelectionOperation(operation) else {
                if isCurrentCameraSelectionOperation(operation) {
                    status = "Camera disappeared; previous session cleanup is incomplete"
                }
                return
            }
            sessionNeedsRecreation = false
            if !selectedDeviceIsPresent {
                selectedDeviceID = discoveredDevices.first?.identifier ?? ""
                latestFrame = nil
            }
        }

        if discoveredDevices.isEmpty {
            if !backgroundMonitor || topologyChanged {
                status = report.failures.isEmpty
                    ? "No AmScope cameras detected"
                    : "GenTL camera discovery failed"
                errorMessage = report.failures
                    .map { "\($0.backendID): \($0.message)" }
                    .joined(separator: "\n")
            }
            return
        }

        if !backgroundMonitor || topologyChanged {
            status = "\(discoveredDevices.count) camera(s) detected through the AmScope camera provider"
            errorMessage = report.failures.isEmpty
                ? nil
                : report.failures.map { "\($0.backendID): \($0.message)" }.joined(separator: "\n")
        }

        if !(await cameraLifecycle.snapshot()).hasSession,
           isCurrentCameraSelectionOperation(operation),
           selectedDevice != nil {
            await prepareSelectedCamera(expectedGeneration: operation)
        }
    }

    func selectDevice(_ identifier: String) {
        guard identifier != selectedDeviceID else { return }
        let operation = beginCameraSelectionOperation()
        Task { await selectDeviceOwned(identifier, operation: operation) }
    }

    private func selectDeviceOwned(_ identifier: String, operation: UInt64) async {
        guard isCurrentCameraSelectionOperation(operation),
              await closeSession(expectedGeneration: operation),
              isCurrentCameraSelectionOperation(operation) else { return }
        selectedDeviceID = identifier
        sessionNeedsRecreation = false
        latestFrame = nil
        cameraCapabilities = nil
        controls = nil
        featureDescriptors = []
        status = selectedDevice.map { "Ready: \($0.displayName)" } ?? "No camera selected"
        await prepareSelectedCamera(expectedGeneration: operation)
    }

    /// UI command. The imaging library owns the session and acquisition lifecycle.
    func start() {
        let operation = cameraSelectionGeneration
        let deviceID = selectedDeviceID
        Task { await startOwned(expectedGeneration: operation, expectedDeviceID: deviceID) }
    }

    private func startOwned(expectedGeneration operation: UInt64, expectedDeviceID: String) async {
        guard isCurrentCameraSelectionOperation(operation),
              selectedDeviceID == expectedDeviceID else { return }
        guard (await cameraLifecycle.snapshot()).hasSession,
              isCurrentCameraSelectionOperation(operation),
              selectedDeviceID == expectedDeviceID,
              let device = selectedDevice else {
            if isCurrentCameraSelectionOperation(operation),
               selectedDeviceID == expectedDeviceID {
                errorMessage = "Open a camera before starting acquisition."
            }
            return
        }
        guard cameraCapabilities?.availability(of: .liveCapture).isUsable == true else {
            errorMessage = "This device does not currently expose a usable GenTL data stream."
            return
        }

        let events = await cameraLifecycle.events()
        guard isCurrentCameraSelectionOperation(operation),
              selectedDeviceID == expectedDeviceID else { return }
        lifecycleEventTask?.cancel()
        lifecycleEventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled,
                      let self,
                      self.isCurrentCameraSelectionOperation(operation),
                      self.selectedDeviceID == expectedDeviceID else { return }
                self.handleLifecycleEvent(event)
            }
        }

        let frames = await cameraLifecycle.frames()
        guard isCurrentCameraSelectionOperation(operation),
              selectedDeviceID == expectedDeviceID else { return }
        frameConsumerTask?.cancel()
        frameConsumerTask = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled,
                      let self,
                      self.isCurrentCameraSelectionOperation(operation),
                      self.selectedDeviceID == expectedDeviceID else { return }
                self.accept(frame)
            }
        }

        latestFrame = nil
        frameRateEstimator.reset()
        framesPerSecond = 0

        do {
            try await cameraLifecycle.start()
            guard isCurrentCameraSelectionOperation(operation),
                  selectedDeviceID == expectedDeviceID else { return }
            isStreaming = true
            status = "Live — \(device.displayName)"
            errorMessage = nil
        } catch {
            guard isCurrentCameraSelectionOperation(operation),
                  selectedDeviceID == expectedDeviceID else { return }
            frameConsumerTask?.cancel()
            frameConsumerTask = nil
            lifecycleEventTask?.cancel()
            lifecycleEventTask = nil
            isStreaming = false
            status = "Unable to start camera"
            errorMessage = error.localizedDescription
        }
    }

    private func handleLifecycleEvent(_ event: CameraSessionLifecycleEvent) {
        switch event {
        case .streamingChanged(let streaming):
            isStreaming = streaming
            if !streaming, status.hasPrefix("Live") {
                status = "Stopped — \(selectedDevice?.displayName ?? "camera")"
            }
            // Feature writability can depend on acquisition state (for example,
            // resolution and pixel format are writable only while stopped).
            refreshControls()
        case .failure(let message):
            status = "Camera stopped — acquisition error"
            errorMessage = message
            sessionNeedsRecreation = true
        case .closed:
            isStreaming = false
        }
    }

    /// UI command. Stop/reader synchronization is executed by the imaging library.
    func stop() {
        let operation = cameraSelectionGeneration
        let deviceID = selectedDeviceID
        Task { await stopOwned(expectedGeneration: operation, expectedDeviceID: deviceID) }
    }

    private func stopOwned(expectedGeneration operation: UInt64, expectedDeviceID: String) async {
        guard isCurrentCameraSelectionOperation(operation),
              selectedDeviceID == expectedDeviceID else { return }
        do {
            try await cameraLifecycle.stop()
            guard isCurrentCameraSelectionOperation(operation),
                  selectedDeviceID == expectedDeviceID else { return }
            frameConsumerTask?.cancel()
            frameConsumerTask = nil
            isStreaming = false
            status = "Stopped — \(selectedDevice?.displayName ?? "camera")"
        } catch {
            guard isCurrentCameraSelectionOperation(operation),
                  selectedDeviceID == expectedDeviceID else { return }
            errorMessage = error.localizedDescription
            status = "Camera stop failed"
        }
    }

    func shutdown() async -> Bool {
        let operation = beginCameraSelectionOperation()

        if let monitor = deviceMonitorTask {
            monitor.cancel()
            await monitor.value
        }
        deviceMonitorTask = nil

        guard await closeSession(expectedGeneration: operation) else { return false }
        guard let provider = cameraProvider else { return true }

        let failures = await provider.shutdown()
        guard isCurrentCameraSelectionOperation(operation) else { return false }
        cameraProvider = nil
        candidatesByID.removeAll()
        devices.removeAll()
        selectedDeviceID = ""
        return failures.isEmpty
    }

    func refreshControls() {
        Task { await refreshControlsOwned() }
    }

    private func refreshControlsOwned(expectedGeneration: UInt64? = nil) async {
        let operation = expectedGeneration ?? cameraSelectionGeneration
        guard isCurrentCameraSelectionOperation(operation),
              (await cameraLifecycle.snapshot()).hasSession,
              isCurrentCameraSelectionOperation(operation) else { return }

        let descriptors = (try? await cameraLifecycle.featureDescriptors()) ?? []
        guard isCurrentCameraSelectionOperation(operation) else { return }
        featureDescriptors = descriptors
        updateSelectedDeviceResolutions(from: descriptors)

        await updateCurrentResolution()
        guard isCurrentCameraSelectionOperation(operation) else { return }

        let hasDataStream = await cameraLifecycle.supportsAcquisition()
        guard isCurrentCameraSelectionOperation(operation) else { return }
        cameraCapabilities = stateResolver.capabilities(
            for: selectedDevice,
            descriptors: descriptors,
            hasDataStream: hasDataStream
        )
        await makeControlSnapshotOwned()
    }

    func setAutoExposureMode(_ mode: AmcamAutoExposureMode) {
        let symbol: String
        switch mode {
        case .manual: symbol = "Off"
        case .once: symbol = "Once"
        case .continuous: symbol = "Continuous"
        }
        submitFeatureWrite(.enumeration(symbol), named: "ExposureAuto")
    }

    func setExposureTime(_ microseconds: UInt32) {
        submitFeatureWrite(.integer(Int64(microseconds)), named: "ExposureTime")
    }

    func setExposureGain(_ percent: UInt16) {
        submitFeatureWrite(.integer(Int64(percent)), named: "AmcamAnalogGainPercent")
    }

    func setColorMatrixEnabled(_ enabled: Bool) {
        submitFeatureWrite(.boolean(enabled), named: "AmcamColorMatrixEnabled")
    }

    func setPixelFormat(_ code: Int32) {
        submitFeatureWrite(.enumeration(String(code)), named: "AmcamPixelFormat")
    }

    func setWhiteBalanceRGBGain(_ values: [Int32]) {
        guard values.count == 3 else {
            errorMessage = "White-balance RGB gain requires exactly three channel values."
            return
        }
        submitFeatureWrite(.integerVector(values.map(Int64.init)), named: "AmcamWhiteBalanceRGBGain")
    }

    func setWhiteBalanceTemperature(_ temperature: Int32) {
        submitFeatureWrite(.integer(Int64(temperature)), named: "AmcamWhiteBalanceTemperature")
    }

    func setWhiteBalanceTint(_ tint: Int32) {
        submitFeatureWrite(.integer(Int64(tint)), named: "AmcamWhiteBalanceTint")
    }

    func setFixedFrameRate(_ framesPerSecond: Double) {
        submitFeatureWrite(.floatingPoint(framesPerSecond), named: "AmcamFixedFrameRate")
    }

    func setFrameSpeedLevel(_ level: Int) {
        submitFeatureWrite(.integer(Int64(level)), named: "AmcamFrameSpeedLevel")
    }

    func setResolution(_ index: Int) {
        guard let descriptor = featureDescriptors.last(where: { $0.name == "AmcamResolutionIndex" }),
              let symbol = descriptor.enumerationValues.first(where: {
                  Int($0.split(separator: ":").first ?? "") == index
              }) else {
            errorMessage = "The selected resolution is not advertised by this camera."
            return
        }
        submitFeatureWrite(.enumeration(symbol), named: "AmcamResolutionIndex")
    }

    private func prepareSelectedCamera(expectedGeneration: UInt64) async {
        guard isCurrentCameraSelectionOperation(expectedGeneration),
              !(await cameraLifecycle.snapshot()).hasSession,
              isCurrentCameraSelectionOperation(expectedGeneration),
              let candidate = candidatesByID[selectedDeviceID],
              let device = selectedDevice else { return }

        do {
            try await cameraLifecycle.open(candidate.runtimeDevice, identifier: candidate.id)
            guard isCurrentCameraSelectionOperation(expectedGeneration) else { return }

            let descriptors = (try? await cameraLifecycle.featureDescriptors()) ?? []
            guard isCurrentCameraSelectionOperation(expectedGeneration) else { return }
            featureDescriptors = descriptors
            updateSelectedDeviceResolutions(from: descriptors)

            await updateCurrentResolution()
            guard isCurrentCameraSelectionOperation(expectedGeneration) else { return }

            let hasDataStream = await cameraLifecycle.supportsAcquisition()
            guard isCurrentCameraSelectionOperation(expectedGeneration) else { return }
            cameraCapabilities = stateResolver.capabilities(
                for: device,
                descriptors: descriptors,
                hasDataStream: hasDataStream
            )
            await makeControlSnapshotOwned()
            guard isCurrentCameraSelectionOperation(expectedGeneration) else { return }

            status = "Ready — \(device.displayName)"
            errorMessage = descriptors.isEmpty
                ? "The backend opened the device but did not expose typed feature access."
                : nil
        } catch {
            guard isCurrentCameraSelectionOperation(expectedGeneration) else { return }
            let cleanupSucceeded = await closeSession(expectedGeneration: expectedGeneration)
            guard isCurrentCameraSelectionOperation(expectedGeneration) else { return }
            // Do not replace a cleanup failure with the original open error:
            // the retained session/acquisition still requires explicit recovery.
            guard cleanupSucceeded else { return }
            status = "Unable to open camera through the AmScope camera provider"
            errorMessage = error.localizedDescription
        }
    }

    private func initializeCameraProvider() {
        let operation = beginCameraSelectionOperation()
        Task { await initializeCameraProviderOwned(operation: operation) }
    }

    private func initializeCameraProviderOwned(operation: UInt64) async {
        guard isCurrentCameraSelectionOperation(operation) else { return }
        guard await closeSession(expectedGeneration: operation),
              isCurrentCameraSelectionOperation(operation) else { return }
        cameraProvider = nil
        candidatesByID.removeAll()
        devices.removeAll()
        selectedDeviceID = ""

        do {
            cameraProvider = try AmcamCameraProvider(profileRegistry: profileRegistry)
            sessionNeedsRecreation = false
            await refreshDevicesOwned(operation: operation)
            startDeviceMonitoring()
        } catch {
            status = "AmScope camera provider is unavailable"
            errorMessage = error.localizedDescription
        }
    }


    /// Low-frequency polling provides hot-plug discovery on SDKs that do not
    /// expose a portable device-change notification. Stable topology does not
    /// overwrite the current user-visible status.
    private func startDeviceMonitoring() {
        deviceMonitorTask?.cancel()
        deviceMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let self, self.cameraProvider != nil else { return }
                let operation = self.cameraSelectionGeneration
                await self.refreshDevicesOwned(
                    operation: operation,
                    backgroundMonitor: true
                )
            }
        }
    }

    private func beginCameraSelectionOperation() -> UInt64 {
        cameraSelectionGeneration &+= 1
        return cameraSelectionGeneration
    }

    private func isCurrentCameraSelectionOperation(_ generation: UInt64) -> Bool {
        cameraSelectionGeneration == generation
    }

    @discardableResult
    private func closeSession(expectedGeneration operation: UInt64) async -> Bool {
        guard isCurrentCameraSelectionOperation(operation) else { return false }
        do {
            try await cameraLifecycle.close()
            // Actor reentrancy permits a new selection while backend cleanup is
            // suspended. A stale close must not clear the replacement selection's
            // UI state after the lifecycle operation completes.
            guard isCurrentCameraSelectionOperation(operation) else { return false }
            frameConsumerTask?.cancel()
            frameConsumerTask = nil
            lifecycleEventTask?.cancel()
            lifecycleEventTask = nil
            currentResolution = nil
            isStreaming = false
            cameraCapabilities = nil
            controls = nil
            featureDescriptors = []
            return true
        } catch {
            guard isCurrentCameraSelectionOperation(operation) else { return false }
            isStreaming = false
            status = "Camera resource cleanup failed"
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func submitFeatureWrite(_ value: CameraFeatureValue, named name: String) {
        // Capture identity and generation at the UI command boundary. Capturing
        // them only after the Task starts can retarget an old control action to
        // a newly selected camera.
        let operation = cameraSelectionGeneration
        let deviceID = selectedDeviceID
        Task {
            await writeFeature(
                value,
                named: name,
                expectedGeneration: operation,
                expectedDeviceID: deviceID
            )
        }
    }

    private func writeFeature(
        _ value: CameraFeatureValue,
        named name: String,
        expectedGeneration operation: UInt64,
        expectedDeviceID: String
    ) async {
        // A stale UI action is discarded silently; it must not write to a
        // replacement camera or overwrite that camera's current error state.
        guard isCurrentCameraSelectionOperation(operation),
              selectedDeviceID == expectedDeviceID else { return }
        guard (await cameraLifecycle.snapshot()).hasSession,
              isCurrentCameraSelectionOperation(operation),
              selectedDeviceID == expectedDeviceID else {
            if isCurrentCameraSelectionOperation(operation),
               selectedDeviceID == expectedDeviceID {
                errorMessage = "Open a camera before changing its features."
            }
            return
        }
        if let validationError = stateResolver.validateWrite(
            value,
            named: name,
            descriptors: featureDescriptors
        ) {
            errorMessage = validationError.localizedDescription
            return
        }
        if let feature = stateResolver.capabilityFeature(for: name),
           cameraCapabilities?.availability(of: feature).isUsable != true {
            errorMessage = "\(name) is not available under the selected camera's capability and model-profile policy."
            return
        }
        do {
            try await cameraLifecycle.writeFeature(value, named: name)
            guard isCurrentCameraSelectionOperation(operation) else { return }
            await refreshControlsOwned(expectedGeneration: operation)
            guard isCurrentCameraSelectionOperation(operation) else { return }
            errorMessage = nil
        } catch {
            guard isCurrentCameraSelectionOperation(operation) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func makeControlSnapshotOwned() async {
        let operation = cameraSelectionGeneration
        let descriptors = featureDescriptors
        let lifecycle = cameraLifecycle
        let snapshot = await stateResolver.controlSnapshot(descriptors: descriptors) { name in
            try await lifecycle.readFeature(name)
        }
        guard isCurrentCameraSelectionOperation(operation) else { return }
        controls = snapshot
    }

    private func updateCurrentResolution() async {
        let operation = cameraSelectionGeneration
        let device = selectedDevice
        let lifecycle = cameraLifecycle
        let descriptors = featureDescriptors
        let resolution = await stateResolver.currentResolution(
            for: device,
            descriptors: descriptors
        ) { name in
            try await lifecycle.readFeature(name)
        }
        guard isCurrentCameraSelectionOperation(operation) else { return }
        currentResolution = resolution
    }

    private func updateSelectedDeviceResolutions(from descriptors: [CameraFeatureDescriptor]) {
        guard let index = devices.firstIndex(where: { $0.identifier == selectedDeviceID }) else { return }
        let device = devices[index]
        devices[index] = AmcamDevice(
            identifier: device.identifier,
            displayName: device.displayName,
            modelName: device.modelName,
            modelFlags: device.modelFlags,
            maximumSpeedLevel: device.maximumSpeedLevel,
            sensorPixelSizeMicrometers: device.sensorPixelSizeMicrometers,
            previewResolutions: stateResolver.resolutions(from: descriptors)
        )
    }

    private func accept(_ frame: CameraFramePayload) {
        do {
            latestFrame = try RGB8Frame.decode(
                width: frame.width,
                height: frame.height,
                pixelFormat: frame.pixelFormat,
                pixelFormatNamespace: frame.pixelFormatNamespace,
                rowPaddingBytes: frame.rowPaddingBytes,
                sizeFilled: frame.sizeFilled,
                dataSize: frame.dataSize,
                sequence: frame.sequence,
                bytes: frame.bytes
            )
        } catch let error as RGB8FrameError {
            switch error {
            case .unsupportedPixelFormat(let namespace, let format):
                errorMessage = String(
                    format: "The display path currently supports PFNC RGB8 only (received format 0x%llX, namespace %llu).",
                    format,
                    namespace
                )
            case .invalidDimensionsOrStride, .inconsistentPayloadMetadata:
                errorMessage = "The GenTL frame metadata is inconsistent with its RGB8 payload."
            }
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let estimate = frameRateEstimator.record(timestamp: now) {
            framesPerSecond = estimate
        }
    }

    private func loadProfileConfiguration() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AmcamImaging", isDirectory: true)
        let file = support.appendingPathComponent("camera-profiles.json")
        let acquisitionFile = support.appendingPathComponent("camera-acquisition-profiles.json")
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                try Data("[]".utf8).write(to: file, options: .atomic)
            }
            if !FileManager.default.fileExists(atPath: acquisitionFile.path) {
                try Data("[]".utf8).write(to: acquisitionFile, options: .atomic)
            }
            let profiles = try JSONDecoder().decode(
                [AmcamCameraModelProfile].self,
                from: Data(contentsOf: file)
            )
            let acquisitionProfiles = try JSONDecoder().decode(
                [AmcamCameraAcquisitionProfile].self,
                from: Data(contentsOf: acquisitionFile)
            )
            profileRegistry = AmcamCameraProfileRegistry(
                profiles: profiles,
                acquisitionProfiles: acquisitionProfiles
            )
            stateResolver = AmcamCameraStateResolver(profileRegistry: profileRegistry)
        } catch {
            errorMessage = "Camera profile configuration could not be loaded: \(error.localizedDescription)"
        }
    }
}
