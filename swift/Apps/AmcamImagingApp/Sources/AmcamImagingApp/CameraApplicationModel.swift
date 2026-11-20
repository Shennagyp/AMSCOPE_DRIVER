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
    private var featureDescriptors: [CameraFeatureDescriptor] = []
    private var hasInitialized = false
    private var cameraSelectionGeneration: UInt64 = 0
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

    func initialize() {
        guard !hasInitialized else { return }
        hasInitialized = true
        loadProfileConfiguration()
        configureSDK()
    }

    func refreshDevices() {
        Task { await refreshDevicesOwned() }
    }

    private func refreshDevicesOwned() async {
        let operation = beginCameraSelectionOperation()
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

        devices = discoveredDevices
        candidatesByID = discoveredCandidates

        if !discoveredDevices.contains(where: { $0.identifier == selectedDeviceID }) {
            guard await closeSession(),
                  isCurrentCameraSelectionOperation(operation) else {
                if isCurrentCameraSelectionOperation(operation) {
                    status = "Camera disappeared; previous session cleanup is incomplete"
                }
                return
            }
            selectedDeviceID = discoveredDevices.first?.identifier ?? ""
            latestFrame = nil
        }

        if discoveredDevices.isEmpty {
            status = report.failures.isEmpty
                ? "No AmScope cameras detected"
                : "GenTL camera discovery failed"
            errorMessage = report.failures
                .map { "\($0.backendID): \($0.message)" }
                .joined(separator: "\n")
            return
        }

        status = "\(discoveredDevices.count) camera(s) detected through the AmScope camera provider"
        errorMessage = report.failures.isEmpty
            ? nil
            : report.failures.map { "\($0.backendID): \($0.message)" }.joined(separator: "\n")

        if !(await cameraLifecycle.snapshot()).hasSession,
           isCurrentCameraSelectionOperation(operation),
           selectedDevice != nil {
            await prepareSelectedCamera(expectedGeneration: operation)
        }
    }

    func selectDevice(_ identifier: String) {
        Task { await selectDeviceOwned(identifier) }
    }

    private func selectDeviceOwned(_ identifier: String) async {
        guard identifier != selectedDeviceID else { return }
        let operation = beginCameraSelectionOperation()
        guard await closeSession(),
              isCurrentCameraSelectionOperation(operation) else { return }
        selectedDeviceID = identifier
        latestFrame = nil
        cameraCapabilities = nil
        controls = nil
        featureDescriptors = []
        status = selectedDevice.map { "Ready: \($0.displayName)" } ?? "No camera selected"
        await prepareSelectedCamera(expectedGeneration: operation)
    }

    /// UI command. The imaging library owns the session and acquisition lifecycle.
    func start() {
        Task { await startOwned() }
    }

    private func startOwned() async {
        guard (await cameraLifecycle.snapshot()).hasSession, let device = selectedDevice else {
            errorMessage = "Select a camera and configure the Amcam SDK first."
            return
        }
        guard cameraCapabilities?.availability(of: .liveCapture).isUsable == true else {
            errorMessage = "This device does not currently expose a usable GenTL data stream."
            return
        }

        let events = await cameraLifecycle.events()
        lifecycleEventTask?.cancel()
        lifecycleEventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                self.handleLifecycleEvent(event)
            }
        }

        let frames = await cameraLifecycle.frames()
        frameConsumerTask?.cancel()
        frameConsumerTask = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled, let self else { return }
                self.accept(frame)
            }
        }

        latestFrame = nil
        frameRateEstimator.reset()
        framesPerSecond = 0

        do {
            try await cameraLifecycle.start()
            isStreaming = true
            status = "Live — \(device.displayName)"
            errorMessage = nil
        } catch {
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
        case .failure(let message):
            status = "Camera stopped — acquisition error"
            errorMessage = message
        case .closed:
            isStreaming = false
        }
    }

    /// UI command. Stop/reader synchronization is executed by the imaging library.
    func stop() {
        Task { await stopOwned() }
    }

    private func stopOwned() async {
        do {
            try await cameraLifecycle.stop()
            frameConsumerTask?.cancel()
            frameConsumerTask = nil
            isStreaming = false
            status = "Stopped — \(selectedDevice?.displayName ?? "camera")"
        } catch {
            errorMessage = error.localizedDescription
            status = "Camera stop failed"
        }
    }

    func shutdown() async -> Bool {
        await closeSession()
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
        Task { await writeFeature(.enumeration(symbol), named: "ExposureAuto") }
    }

    func setExposureTime(_ microseconds: UInt32) {
        Task { await writeFeature(.integer(Int64(microseconds)), named: "ExposureTime") }
    }

    func setExposureGain(_ percent: UInt16) {
        Task { await writeFeature(.integer(Int64(percent)), named: "AmcamAnalogGainPercent") }
    }

    func setColorMatrixEnabled(_ enabled: Bool) {
        Task { await writeFeature(.boolean(enabled), named: "AmcamColorMatrixEnabled") }
    }

    func setPixelFormat(_ code: Int32) {
        Task { await writeFeature(.enumeration(String(code)), named: "AmcamPixelFormat") }
    }

    func setWhiteBalanceRGBGain(_ values: [Int32]) {
        guard values.count == 3 else {
            errorMessage = "White-balance RGB gain requires exactly three channel values."
            return
        }
        Task { await writeFeature(.integerVector(values.map(Int64.init)), named: "AmcamWhiteBalanceRGBGain") }
    }

    func setWhiteBalanceTemperatureTint(temperature: Int32, tint: Int32) {
        Task {
            await writeFeature(.integer(Int64(temperature)), named: "AmcamWhiteBalanceTemperature")
            guard errorMessage == nil else { return }
            await writeFeature(.integer(Int64(tint)), named: "AmcamWhiteBalanceTint")
        }
    }

    func setFixedFrameRate(_ framesPerSecond: Double) {
        Task { await writeFeature(.floatingPoint(framesPerSecond), named: "AmcamFixedFrameRate") }
    }

    func setFrameSpeedLevel(_ level: Int) {
        Task { await writeFeature(.integer(Int64(level)), named: "AmcamFrameSpeedLevel") }
    }

    func setResolution(_ index: Int) {
        guard let descriptor = featureDescriptors.first(where: { $0.name == "AmcamResolutionIndex" }),
              let symbol = descriptor.enumerationValues.first(where: {
                  Int($0.split(separator: ":").first ?? "") == index
              }) else {
            errorMessage = "The selected resolution is not advertised by this camera."
            return
        }
        Task { await writeFeature(.enumeration(symbol), named: "AmcamResolutionIndex") }
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
            _ = await closeSession()
            guard isCurrentCameraSelectionOperation(expectedGeneration) else { return }
            status = "Unable to open camera through the AmScope camera provider"
            errorMessage = error.localizedDescription
        }
    }

    private func configureSDK() {
        Task { await configureSDKOwned() }
    }

    private func configureSDKOwned() async {
        let operation = beginCameraSelectionOperation()
        guard await closeSession(),
              isCurrentCameraSelectionOperation(operation) else { return }
        cameraProvider = nil
        candidatesByID.removeAll()
        devices.removeAll()
        selectedDeviceID = ""

        do {
            cameraProvider = try AmcamCameraProvider()
            await refreshDevicesOwned()
        } catch {
            status = "AmScope camera provider is unavailable"
            errorMessage = error.localizedDescription
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
    private func closeSession() async -> Bool {
        do {
            try await cameraLifecycle.close()
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
            isStreaming = false
            status = "Camera resource cleanup failed"
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func writeFeature(_ value: CameraFeatureValue, named name: String) async {
        let operation = cameraSelectionGeneration
        guard isCurrentCameraSelectionOperation(operation),
              (await cameraLifecycle.snapshot()).hasSession,
              isCurrentCameraSelectionOperation(operation) else {
            errorMessage = "Open a camera before changing its features."
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
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                try Data("[]".utf8).write(to: file, options: .atomic)
            }
            let profiles = try JSONDecoder().decode(
                [AmcamCameraModelProfile].self,
                from: Data(contentsOf: file)
            )
            stateResolver = AmcamCameraStateResolver(profileRegistry: AmcamCameraProfileRegistry(profiles: profiles))
        } catch {
            errorMessage = "Camera profile configuration could not be loaded: \(error.localizedDescription)"
        }
    }
}
