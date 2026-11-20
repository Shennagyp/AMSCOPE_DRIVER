import AmcamCameraModel
import AmcamImagingCore
import AmcamImagingRuntime
import AmcamImagingGenTLAdapter
import Foundation
import GenTLABI
import GenTLRouter
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

    private var router = GenTLRouter()
    private var candidatesByID: [String: GenTLDeviceCandidate] = [:]
    private let cameraLifecycle = CameraSessionLifecycle()
    private var frameConsumerTask: Task<Void, Never>?
    private var lifecycleEventTask: Task<Void, Never>?
    private var featureDescriptors: [CameraFeatureDescriptor] = []
    private var hasInitialized = false
    private var profileRegistry = AmcamCameraProfileRegistry()
    private var frameRateEstimator = FrameRateEstimator()

    private let featureNamesByCameraFeature: [AmcamCameraFeature: [String]] = [
        .resolution: ["AmcamResolutionIndex"],
        .exposureAuto: ["ExposureAuto"],
        .exposureManual: ["ExposureTime"],
        .analogGain: ["AmcamAnalogGainPercent"],
        .whiteBalance: ["AmcamWhiteBalanceTemperature", "AmcamWhiteBalanceTint", "AmcamWhiteBalanceRGBGain"],
        .colorCorrection: ["AmcamColorMatrixEnabled"],
        .pixelFormatSelection: ["AmcamPixelFormat"],
        .preciseFrameRate: ["AmcamFixedFrameRate"],
        .discreteFrameSpeed: ["AmcamFrameSpeedLevel"]
    ]

    var selectedDevice: AmcamDevice? {
        devices.first { $0.identifier == selectedDeviceID }
    }

    @Published private(set) var currentResolution: AmcamResolution?

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
        let report = router.discover()
        var discoveredDevices: [AmcamDevice] = []
        var discoveredCandidates: [String: GenTLDeviceCandidate] = [:]

        for candidate in report.devices {
            let displayName = (try? readDeviceString(
                candidate,
                command: Int32(GenTLABI.DEVICE_INFO_DISPLAYNAME.rawValue)
            )).flatMap { $0.isEmpty ? nil : $0 } ?? candidate.deviceID
            let modelName = try? readDeviceString(
                candidate,
                command: Int32(GenTLABI.DEVICE_INFO_MODEL.rawValue)
            )

            discoveredDevices.append(
                AmcamDevice(
                    identifier: candidate.id,
                    displayName: displayName,
                    modelName: modelName,
                    modelFlags: nil,
                    maximumSpeedLevel: nil,
                    sensorPixelSizeMicrometers: nil,
                    previewResolutions: []
                )
            )
            discoveredCandidates[candidate.id] = candidate
        }

        devices = discoveredDevices
        candidatesByID = discoveredCandidates

        if !discoveredDevices.contains(where: { $0.identifier == selectedDeviceID }) {
            guard await closeSession() else {
                status = "Camera disappeared; previous session cleanup is incomplete"
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

        status = "\(discoveredDevices.count) camera(s) detected through GenTLRouter"
        errorMessage = report.failures.isEmpty
            ? nil
            : report.failures.map { "\($0.backendID): \($0.message)" }.joined(separator: "\n")

        if !(await cameraLifecycle.snapshot()).hasSession, selectedDevice != nil {
            await prepareSelectedCamera()
        }
    }

    func selectDevice(_ identifier: String) {
        Task { await selectDeviceOwned(identifier) }
    }

    private func selectDeviceOwned(_ identifier: String) async {
        guard identifier != selectedDeviceID else { return }
        guard await closeSession() else { return }
        selectedDeviceID = identifier
        latestFrame = nil
        cameraCapabilities = nil
        controls = nil
        featureDescriptors = []
        status = selectedDevice.map { "Ready: \($0.displayName)" } ?? "No camera selected"
        await prepareSelectedCamera()
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

    private func refreshControlsOwned() async {
        guard (await cameraLifecycle.snapshot()).hasSession else { return }
        featureDescriptors = (try? await cameraLifecycle.featureDescriptors()) ?? []
        updateSelectedDeviceResolutions(from: featureDescriptors)
        await updateCurrentResolution()
        cameraCapabilities = makeCapabilities(
            for: selectedDevice,
            descriptors: featureDescriptors,
            hasDataStream: await cameraLifecycle.supportsAcquisition()
        )
        controls = await makeControlSnapshot(descriptors: featureDescriptors)
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

    private func prepareSelectedCamera() async {
        guard !(await cameraLifecycle.snapshot()).hasSession,
              let candidate = candidatesByID[selectedDeviceID],
              let device = selectedDevice else { return }

        do {
            try await cameraLifecycle.open(GenTLRuntimeDevice(candidate: candidate))
            featureDescriptors = (try? await cameraLifecycle.featureDescriptors()) ?? []
            updateSelectedDeviceResolutions(from: featureDescriptors)
            await updateCurrentResolution()
            cameraCapabilities = makeCapabilities(
                for: device,
                descriptors: featureDescriptors,
                hasDataStream: await cameraLifecycle.supportsAcquisition()
            )
            controls = await makeControlSnapshot(descriptors: featureDescriptors)
            status = "Ready — \(device.displayName)"
            if featureDescriptors.isEmpty {
                errorMessage = "The backend opened the device but did not expose typed feature access."
            } else {
                errorMessage = nil
            }
        } catch {
            _ = await closeSession()
            status = "Unable to open camera through GenTLRouter"
            errorMessage = error.localizedDescription
        }
    }

    private func configureSDK() {
        Task { await configureSDKOwned() }
    }

    private func configureSDKOwned() async {
        guard await closeSession() else { return }
        router = GenTLRouter()
        candidatesByID.removeAll()
        devices.removeAll()
        selectedDeviceID = ""

        do {
            try router.registerAmcam(backendID: "amcam-sdk")
            await refreshDevicesOwned()
        } catch {
            status = "AmScope camera provider is unavailable"
            errorMessage = error.localizedDescription
        }
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
        guard (await cameraLifecycle.snapshot()).hasSession else {
            errorMessage = "Open a camera before changing its features."
            return
        }
        if let feature = capabilityFeature(for: name),
           cameraCapabilities?.availability(of: feature).isUsable != true {
            errorMessage = "\(name) is not available under the selected camera's capability and model-profile policy."
            return
        }
        do {
            try await cameraLifecycle.writeFeature(value, named: name)
            await refreshControlsOwned()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func capabilityFeature(for name: String) -> AmcamCameraFeature? {
        switch name {
        case "ExposureAuto": return .exposureAuto
        case "ExposureTime": return .exposureManual
        case "AmcamAnalogGainPercent": return .analogGain
        case "AmcamColorMatrixEnabled": return .colorCorrection
        case "AmcamPixelFormat": return .pixelFormatSelection
        case "AmcamWhiteBalanceTemperature", "AmcamWhiteBalanceTint", "AmcamWhiteBalanceRGBGain":
            return .whiteBalance
        case "AmcamFixedFrameRate": return .preciseFrameRate
        case "AmcamFrameSpeedLevel": return .discreteFrameSpeed
        case "AmcamResolutionIndex": return .resolution
        default: return nil
        }
    }

    private func makeCapabilities(
        for device: AmcamDevice?,
        descriptors: [CameraFeatureDescriptor],
        hasDataStream: Bool
    ) -> AmcamCameraCapabilities? {
        guard let device else { return nil }
        let descriptorsByName = Dictionary(
            descriptors.map { ($0.name, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let profile = profileRegistry.profile(for: device.modelCode)

        let features = AmcamCameraFeature.allCases.map { feature -> AmcamFeatureAvailability in
            let matchingDescriptors = (featureNamesByCameraFeature[feature] ?? [])
                .compactMap { descriptorsByName[$0] }
            let implemented = feature == .liveCapture || !matchingDescriptors.isEmpty
            let hardwareAvailable = feature == .liveCapture
                ? hasDataStream
                : matchingDescriptors.contains(where: \.isAvailable)
            let profileAllows = profile.map { $0.allowedFeatures.contains(feature) } ?? true
            let profileDenies = profile?.deniedFeatures.contains(feature) ?? false
            let available = hardwareAvailable && profileAllows && !profileDenies

            let reason: String?
            if profileDenies {
                reason = "Disabled by the explicit model profile."
            } else if !profileAllows {
                reason = "Not included in the explicit model profile allow-list."
            } else if !implemented {
                reason = "This feature is not yet exposed by the routed GenTL feature provider."
            } else if !hardwareAvailable {
                reason = feature == .liveCapture
                    ? "The opened device does not expose a data stream."
                    : "The selected camera reports this feature as unavailable."
            } else {
                reason = nil
            }

            return AmcamFeatureAvailability(
                feature: feature,
                available: available,
                implemented: implemented,
                evidence: implemented ? .implementation : nil,
                reason: reason
            )
        }

        return AmcamCameraCapabilities(
            modelCode: device.modelCode,
            modelFlags: device.modelFlags ?? 0,
            features: features
        )
    }

    private func makeControlSnapshot(
        descriptors: [CameraFeatureDescriptor]
    ) async -> AmcamControlSnapshot {
        let descriptorsByName = Dictionary(
            descriptors.map { ($0.name, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let autoMode: AmcamAutoExposureMode?
        if case .enumeration(let symbol)? = try? await cameraLifecycle.readFeature("ExposureAuto") {
            switch symbol {
            case "Off": autoMode = .manual
            case "Once": autoMode = .once
            case "Continuous": autoMode = .continuous
            default: autoMode = nil
            }
        } else {
            autoMode = nil
        }

        let exposureDescriptor = descriptorsByName["ExposureTime"]
        let exposureValue = await readIntegerFeature("ExposureTime")
        let exposure = exposureDescriptor.map { descriptor in
            AmcamExposureControl(
                autoMode: autoMode,
                readbackMicroseconds: unsigned32(exposureValue),
                minimumMicroseconds: unsigned32(descriptor.numericRange?.minimum),
                maximumMicroseconds: unsigned32(descriptor.numericRange?.maximum),
                defaultMicroseconds: nil
            )
        }

        let gainDescriptor = descriptorsByName["AmcamAnalogGainPercent"]
        let gainValue = await readIntegerFeature("AmcamAnalogGainPercent")
        let gain: AmcamGainControl?
        if let gainDescriptor,
           let current = unsigned16(gainValue),
           let minimum = unsigned16(gainDescriptor.numericRange?.minimum),
           let maximum = unsigned16(gainDescriptor.numericRange?.maximum) {
            gain = AmcamGainControl(
                readbackPercent: current,
                minimumPercent: minimum,
                maximumPercent: maximum,
                defaultPercent: minimum
            )
        } else {
            gain = nil
        }

        let whiteTemperature = await readIntegerFeature("AmcamWhiteBalanceTemperature")
            .flatMap { $0 >= Int64(Int32.min) && $0 <= Int64(Int32.max) ? Int32($0) : nil }
        let whiteTint = await readIntegerFeature("AmcamWhiteBalanceTint")
            .flatMap { $0 >= Int64(Int32.min) && $0 <= Int64(Int32.max) ? Int32($0) : nil }
        let whiteRGB = await readIntegerVectorFeature("AmcamWhiteBalanceRGBGain").flatMap { values -> [Int32]? in
            guard values.count == 3 else { return nil }
            let converted = values.compactMap { Int32(exactly: $0) }
            return converted.count == 3 ? converted : nil
        }
        let whiteBalance = (whiteTemperature != nil || whiteTint != nil || whiteRGB != nil)
            ? AmcamWhiteBalanceControl(
                temperature: whiteTemperature,
                tint: whiteTint,
                rgbGain: whiteRGB
            )
            : nil

        let colorMatrix: Bool?
        if case .boolean(let value)? = try? await cameraLifecycle.readFeature("AmcamColorMatrixEnabled") {
            colorMatrix = value
        } else {
            colorMatrix = nil
        }
        let pixelFormat = await readEnumerationFeature("AmcamPixelFormat").flatMap(Int32.init)
        let supportedPixelFormats = descriptorsByName["AmcamPixelFormat"]?.enumerationValues.compactMap(Int32.init) ?? []
        let image = (colorMatrix != nil || pixelFormat != nil || !supportedPixelFormats.isEmpty)
            ? AmcamCameraImageControls(
                colorMatrixEnabled: colorMatrix,
                pixelFormatCode: pixelFormat,
                supportedPixelFormats: supportedPixelFormats
            )
            : nil

        let fixedRateDescriptor = descriptorsByName["AmcamFixedFrameRate"]
        let speedDescriptor = descriptorsByName["AmcamFrameSpeedLevel"]
        let fixedRateReadback = await readFloatingPointFeature("AmcamFixedFrameRate")
        let currentSpeed = await readIntegerFeature("AmcamFrameSpeedLevel").flatMap(Int.init(exactly:))
        let frameRate = AmcamFrameRateControl(
            supported: fixedRateDescriptor?.isAvailable == true,
            minimumFramesPerSecond: fixedRateDescriptor?.numericRange?.minimum,
            maximumFramesPerSecond: fixedRateDescriptor?.numericRange?.maximum,
            readbackFramesPerSecond: fixedRateReadback,
            unsupportedReason: fixedRateDescriptor?.isAvailable == true
                ? nil
                : "Precise fixed frame rate is not available for this camera.",
            speedLevelSupported: speedDescriptor?.isAvailable == true,
            currentSpeedLevel: currentSpeed,
            maximumSpeedLevel: speedDescriptor?.numericRange.flatMap { Int(exactly: $0.maximum) }
        )

        return AmcamControlSnapshot(
            exposure: exposure,
            gain: gain,
            whiteBalance: whiteBalance,
            image: image,
            frameRate: frameRate
        )
    }

    private func readIntegerVectorFeature(_ name: String) async -> [Int64]? {
        guard case .integerVector(let values)? = try? await cameraLifecycle.readFeature(name) else { return nil }
        return values
    }

    private func readEnumerationFeature(_ name: String) async -> String? {
        guard case .enumeration(let value)? = try? await cameraLifecycle.readFeature(name) else { return nil }
        return value
    }

    private func readFloatingPointFeature(_ name: String) async -> Double? {
        guard case .floatingPoint(let value)? = try? await cameraLifecycle.readFeature(name), value.isFinite else {
            return nil
        }
        return value
    }

    private func updateCurrentResolution() async {
        guard case .enumeration(let symbol)? = try? await cameraLifecycle.readFeature("AmcamResolutionIndex"),
              let separator = symbol.firstIndex(of: ":"),
              let index = Int(symbol[..<separator]) else {
            currentResolution = nil
            return
        }
        currentResolution = selectedDevice?.previewResolutions.first { $0.index == index }
    }

    private func updateSelectedDeviceResolutions(from descriptors: [CameraFeatureDescriptor]) {
        guard let index = devices.firstIndex(where: { $0.identifier == selectedDeviceID }) else { return }
        let device = devices[index]
        let options = descriptors.first(where: { $0.name == "AmcamResolutionIndex" })?.enumerationValues ?? []
        let resolutions = options.compactMap { symbol -> AmcamResolution? in
            guard let separator = symbol.firstIndex(of: ":"),
                  let resolutionSeparator = symbol[symbol.index(after: separator)...].firstIndex(of: "x"),
                  let resolutionIndex = Int(symbol[..<separator]),
                  let width = Int(symbol[symbol.index(after: separator)..<resolutionSeparator]),
                  let height = Int(symbol[symbol.index(after: resolutionSeparator)...]) else {
                return nil
            }
            return AmcamResolution(index: resolutionIndex, width: width, height: height)
        }
        devices[index] = AmcamDevice(
            identifier: device.identifier,
            displayName: device.displayName,
            modelName: device.modelName,
            modelFlags: device.modelFlags,
            maximumSpeedLevel: device.maximumSpeedLevel,
            sensorPixelSizeMicrometers: device.sensorPixelSizeMicrometers,
            previewResolutions: resolutions
        )
    }

    private func readIntegerFeature(_ name: String) async -> Int64? {
        guard case .integer(let value)? = try? await cameraLifecycle.readFeature(name) else {
            return nil
        }
        return value
    }

    private func unsigned32(_ value: Int64?) -> UInt32? {
        guard let value, value >= 0, value <= Int64(UInt32.max) else { return nil }
        return UInt32(value)
    }

    private func unsigned32(_ value: Double?) -> UInt32? {
        guard let value, value.isFinite, value >= 0, value <= Double(UInt32.max) else {
            return nil
        }
        return UInt32(value.rounded(.towardZero))
    }

    private func unsigned16(_ value: Int64?) -> UInt16? {
        guard let value, value >= 0, value <= Int64(UInt16.max) else { return nil }
        return UInt16(value)
    }

    private func unsigned16(_ value: Double?) -> UInt16? {
        guard let value, value.isFinite, value >= 0, value <= Double(UInt16.max) else {
            return nil
        }
        return UInt16(value.rounded(.towardZero))
    }

    private func readDeviceString(
        _ candidate: GenTLDeviceCandidate,
        command: Int32
    ) throws -> String {
        var dataType: GenTLABI.INFO_DATATYPE = 0
        var requiredSize = 0
        let queryStatus = candidate.api.IFGetDeviceInfo(
            candidate.interfaceHandle,
            candidate.deviceID.withCString { $0 },
            command,
            &dataType,
            nil,
            &requiredSize
        )
        let success = GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
        let bufferTooSmall = GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_BUFFER_TOO_SMALL)
        guard queryStatus == success || queryStatus == bufferTooSmall else {
            throw GenTLAcquisitionError.genTLCallFailed(
                operation: "IFGetDeviceInfo(size)",
                code: Int32(queryStatus)
            )
        }
        guard requiredSize > 1, requiredSize <= 1_048_576 else {
            throw GenTLAcquisitionError.invalidDataStreamID
        }

        var bytes = [CChar](repeating: 0, count: requiredSize)
        var capacity = requiredSize
        let status = bytes.withUnsafeMutableBufferPointer { buffer in
            candidate.api.IFGetDeviceInfo(
                candidate.interfaceHandle,
                candidate.deviceID.withCString { $0 },
                command,
                &dataType,
                buffer.baseAddress,
                &capacity
            )
        }
        guard status == success else {
            throw GenTLAcquisitionError.genTLCallFailed(
                operation: "IFGetDeviceInfo",
                code: Int32(status)
            )
        }
        guard dataType == Int32(GenTLABI.INFO_DATATYPE_STRING.rawValue),
              capacity > 0, capacity <= bytes.count else {
            throw GenTLAcquisitionError.invalidDataStreamID
        }

        bytes[min(capacity, bytes.count) - 1] = 0
        return String(cString: bytes)
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
            profileRegistry = AmcamCameraProfileRegistry(profiles: profiles)
        } catch {
            errorMessage = "Camera profile configuration could not be loaded: \(error.localizedDescription)"
        }
    }
}
