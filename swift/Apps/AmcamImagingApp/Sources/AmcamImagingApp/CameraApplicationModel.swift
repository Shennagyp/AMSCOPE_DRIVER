import AppKit
import AmcamGenTL
import Darwin
import Foundation
import GenTLABI
import GenTLAPI
import GenTLRouter
import SwiftUI

@MainActor
final class CameraApplicationModel: ObservableObject {
    @Published private(set) var devices: [AmcamDevice] = []
    @Published var selectedDeviceID = ""
    @Published private(set) var latestImage: NSImage?
    @Published private(set) var isStreaming = false
    @Published private(set) var cameraCapabilities: AmcamCameraCapabilities?
    @Published private(set) var controls: AmcamControlSnapshot?
    @Published private(set) var status = "Select an AmScope camera"
    @Published var errorMessage: String?
    @Published var isSettingsPresented = false
    @Published private(set) var framesPerSecond = 0.0
    @Published private(set) var sdkPath: String?

    private var router = GenTLRouter()
    private var candidatesByID: [String: GenTLDeviceCandidate] = [:]
    private var deviceSession: GenTLDeviceSession?
    private var acquisition: GenTLAcquisitionSession?
    private var captureTask: Task<Void, Never>?
    private var featureDescriptors: [GenTLFeatureDescriptor] = []
    private var hasInitialized = false
    private var profileRegistry = AmcamCameraProfileRegistry()
    private var lastFrameHostTime: TimeInterval?
    private var frameIntervals: [TimeInterval] = []
    private(set) var isFullScreen = false

    private let featureNameByCameraFeature: [AmcamCameraFeature: String] = [
        .exposureAuto: "ExposureAuto",
        .exposureManual: "ExposureTime",
        .analogGain: "AmcamAnalogGainPercent"
    ]

    var selectedDevice: AmcamDevice? {
        devices.first { $0.identifier == selectedDeviceID }
    }

    /// Resolution selection is intentionally unavailable until Width/Height or
    /// a verified discrete-resolution feature is exposed through GenTLFeatureAccess.
    var currentResolution: AmcamResolution? { nil }

    func initialize() {
        guard !hasInitialized else { return }
        hasInitialized = true
        loadProfileConfiguration()
        if let url = defaultSDKURL() {
            configureSDK(at: url)
        } else {
            status = "Amcam SDK not found — choose libamcam.dylib"
        }
    }

    func chooseSDK() {
        let panel = NSOpenPanel()
        panel.title = "Select the Amcam SDK"
        panel.message = "Choose the vendor libamcam.dylib"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            configureSDK(at: url)
        }
    }

    func refreshDevices() {
        guard sdkPath != nil else {
            chooseSDK()
            return
        }

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
            closeSession()
            selectedDeviceID = discoveredDevices.first?.identifier ?? ""
            latestImage = nil
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

        if deviceSession == nil, selectedDevice != nil {
            prepareSelectedCamera()
        }
    }

    func selectDevice(_ identifier: String) {
        guard identifier != selectedDeviceID else { return }
        closeSession()
        selectedDeviceID = identifier
        latestImage = nil
        cameraCapabilities = nil
        controls = nil
        featureDescriptors = []
        status = selectedDevice.map { "Ready: \($0.displayName)" } ?? "No camera selected"
        prepareSelectedCamera()
    }

    func start() {
        guard let deviceSession, let device = selectedDevice else {
            errorMessage = "Select a camera and configure the Amcam SDK first."
            return
        }
        guard cameraCapabilities?.availability(of: .liveCapture).isUsable == true else {
            errorMessage = "This device does not currently expose a usable GenTL data stream."
            return
        }

        do {
            if let existing = acquisition {
                try existing.close()
                acquisition = nil
            }

            let newAcquisition = try GenTLAcquisitionSession(device: deviceSession)
            try newAcquisition.start()
            acquisition = newAcquisition

            latestImage = nil
            frameIntervals.removeAll(keepingCapacity: true)
            lastFrameHostTime = nil
            framesPerSecond = 0
            isStreaming = true
            status = "Live — \(device.displayName)"
            errorMessage = nil

            captureTask = Task.detached(priority: .userInitiated) { [weak self, newAcquisition] in
                while !Task.isCancelled {
                    do {
                        let frame = try newAcquisition.nextFrame(timeoutMilliseconds: 5_000)
                        guard !frame.isIncomplete else { continue }
                        await MainActor.run {
                            self?.accept(frame)
                        }
                    } catch let error as GenTLAcquisitionError {
                        if case .acquisitionStopped = error {
                            break
                        }
                        await MainActor.run {
                            self?.handleCaptureFailure(error)
                        }
                        break
                    } catch {
                        await MainActor.run {
                            self?.handleCaptureFailure(error)
                        }
                        break
                    }
                }
            }
        } catch {
            isStreaming = false
            status = "Unable to start camera"
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard let acquisition, isStreaming else { return }
        do {
            try acquisition.stop()
            captureTask?.cancel()
            captureTask = nil
            isStreaming = false
            status = "Stopped — \(selectedDevice?.displayName ?? "camera")"
        } catch {
            errorMessage = error.localizedDescription
            status = "Camera stop failed"
        }
    }

    func shutdown() {
        closeSession()
    }

    func refreshControls() {
        guard let deviceSession else { return }
        featureDescriptors = (try? deviceSession.featureDescriptors()) ?? []
        cameraCapabilities = makeCapabilities(
            for: selectedDevice,
            descriptors: featureDescriptors,
            hasDataStream: deviceHasDataStream(deviceSession)
        )
        controls = makeControlSnapshot(deviceSession, descriptors: featureDescriptors)
    }

    func setAutoExposureMode(_ mode: AmcamAutoExposureMode) {
        let symbol: String
        switch mode {
        case .manual: symbol = "Off"
        case .once: symbol = "Once"
        case .continuous: symbol = "Continuous"
        }
        writeFeature(.enumeration(symbol), named: "ExposureAuto")
    }

    func setExposureTime(_ microseconds: UInt32) {
        writeFeature(.integer(Int64(microseconds)), named: "ExposureTime")
    }

    func setExposureGain(_ percent: UInt16) {
        writeFeature(.integer(Int64(percent)), named: "AmcamAnalogGainPercent")
    }

    // These controls remain hidden unless the selected backend advertises a
    // corresponding typed feature descriptor. They never fall back to direct
    // Amcam SDK calls from the application.
    func setColorMatrixEnabled(_ enabled: Bool) {
        writeFeature(.boolean(enabled), named: "AmcamColorMatrixEnabled")
    }

    func setPixelFormat(_ code: Int32) {
        writeFeature(.integer(Int64(code)), named: "PixelFormat")
    }

    func setWhiteBalanceRGBGain(_ values: [Int32]) {
        guard values.count == 3 else {
            errorMessage = "White-balance RGB gain requires exactly three channel values."
            return
        }
        errorMessage = "RGB white-balance controls are not yet exposed by the routed feature provider."
    }

    func setWhiteBalanceTemperatureTint(temperature: Int32, tint: Int32) {
        errorMessage = "White-balance temperature/tint controls are not yet exposed by the routed feature provider."
    }

    func setFixedFrameRate(_ framesPerSecond: Double) {
        errorMessage = "Fixed frame-rate control is not yet exposed by the routed feature provider."
    }

    func setFrameSpeedLevel(_ level: Int) {
        errorMessage = "Frame-speed control is not yet exposed by the routed feature provider."
    }

    func setResolution(_ index: Int) {
        errorMessage = "Discrete resolution selection is not yet exposed by the routed feature provider."
    }

    func enterFullScreen() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            self.isFullScreen = true
        }
    }

    func toggleFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        window.toggleFullScreen(nil)
        isFullScreen.toggle()
    }

    private func prepareSelectedCamera() {
        guard deviceSession == nil,
              let candidate = candidatesByID[selectedDeviceID],
              let device = selectedDevice else { return }

        do {
            let openedSession = try candidate.open(access: .exclusive)
            deviceSession = openedSession
            featureDescriptors = (try? openedSession.featureDescriptors()) ?? []
            let hasDataStream = deviceHasDataStream(openedSession)
            cameraCapabilities = makeCapabilities(
                for: device,
                descriptors: featureDescriptors,
                hasDataStream: hasDataStream
            )
            controls = makeControlSnapshot(openedSession, descriptors: featureDescriptors)
            status = "Ready — \(device.displayName)"
            if featureDescriptors.isEmpty {
                errorMessage = "The backend opened the device but did not expose typed feature access."
            } else {
                errorMessage = nil
            }
        } catch {
            closeSession()
            status = "Unable to open camera through GenTLRouter"
            errorMessage = error.localizedDescription
        }
    }

    private func configureSDK(at url: URL) {
        closeSession()
        router = GenTLRouter()
        candidatesByID.removeAll()
        devices.removeAll()
        selectedDeviceID = ""

        do {
            try router.registerAmcam(backendID: "amcam-sdk", sdkLibraryURL: url)
            sdkPath = url.path
            refreshDevices()
        } catch {
            sdkPath = url.path
            status = "Amcam GenTL backend could not be registered"
            errorMessage = error.localizedDescription
        }
    }

    private func closeSession() {
        captureTask?.cancel()
        captureTask = nil

        if let acquisition {
            do {
                try acquisition.close()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        acquisition = nil

        if let deviceSession {
            do {
                try deviceSession.close()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        deviceSession = nil

        isStreaming = false
        cameraCapabilities = nil
        controls = nil
        featureDescriptors = []
    }

    private func writeFeature(_ value: GenTLFeatureValue, named name: String) {
        guard let deviceSession else {
            errorMessage = "Open a camera before changing its features."
            return
        }
        do {
            try deviceSession.writeFeature(value, named: name)
            refreshControls()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleCaptureFailure(_ error: Error) {
        guard isStreaming else { return }
        isStreaming = false
        status = "Camera stopped — acquisition error"
        errorMessage = error.localizedDescription
        closeSession()
    }

    private func deviceHasDataStream(_ session: GenTLDeviceSession) -> Bool {
        var count: UInt32 = 0
        let status = session.api.DevGetNumDataStreams(session.deviceHandle, &count)
        return status == GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) && count > 0
    }

    private func makeCapabilities(
        for device: AmcamDevice?,
        descriptors: [GenTLFeatureDescriptor],
        hasDataStream: Bool
    ) -> AmcamCameraCapabilities? {
        guard let device else { return nil }
        let descriptorsByName = Dictionary(
            descriptors.map { ($0.name, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let profile = profileRegistry.profile(for: device.modelCode)

        let features = AmcamCameraFeature.allCases.map { feature -> AmcamFeatureAvailability in
            let descriptor = featureNameByCameraFeature[feature].flatMap { descriptorsByName[$0] }
            let implemented = feature == .liveCapture || descriptor != nil
            let hardwareAvailable = feature == .liveCapture
                ? hasDataStream
                : (descriptor?.isAvailable ?? false)
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
        _ session: GenTLDeviceSession,
        descriptors: [GenTLFeatureDescriptor]
    ) -> AmcamControlSnapshot {
        let descriptorsByName = Dictionary(
            descriptors.map { ($0.name, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let autoMode: AmcamAutoExposureMode?
        if case .enumeration(let symbol)? = try? session.readFeature("ExposureAuto") {
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
        let exposureValue = readIntegerFeature("ExposureTime", from: session)
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
        let gainValue = readIntegerFeature("AmcamAnalogGainPercent", from: session)
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

        return AmcamControlSnapshot(
            exposure: exposure,
            gain: gain,
            whiteBalance: nil,
            image: nil,
            frameRate: AmcamFrameRateControl(
                supported: false,
                unsupportedReason: "Frame-rate features are not yet exposed by the routed feature provider."
            )
        )
    }

    private func readIntegerFeature(
        _ name: String,
        from session: GenTLDeviceSession
    ) -> Int64? {
        guard case .integer(let value)? = try? session.readFeature(name) else {
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

    private func accept(_ frame: GenTLFrame) {
        guard frame.pixelFormatNamespace == 4, frame.pixelFormat == 0x02180014 else {
            errorMessage = String(
                format: "The display path currently supports PFNC RGB8 only (received format 0x%llX, namespace %llu).",
                frame.pixelFormat,
                frame.pixelFormatNamespace
            )
            return
        }

        let (packedRowBytes, rowOverflow) = frame.width.multipliedReportingOverflow(by: 3)
        let (bytesPerRow, paddingOverflow) = packedRowBytes.addingReportingOverflow(frame.rowPaddingBytes)
        let (requiredBytes, heightOverflow) = bytesPerRow.multipliedReportingOverflow(by: frame.height)
        guard frame.width > 0, frame.height > 0,
              !rowOverflow, !paddingOverflow, !heightOverflow,
              frame.rowPaddingBytes >= 0,
              frame.dataSize >= requiredBytes,
              frame.sizeFilled >= requiredBytes,
              frame.bytes.count >= requiredBytes else {
            errorMessage = "The GenTL frame metadata is inconsistent with its RGB8 payload."
            return
        }

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: frame.width,
            pixelsHigh: frame.height,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 24
        ), let destination = representation.bitmapData else {
            errorMessage = "Unable to allocate the live-frame display buffer."
            return
        }

        frame.bytes.withUnsafeBytes { source in
            guard let baseAddress = source.baseAddress else { return }
            memcpy(destination, baseAddress, requiredBytes)
        }
        let image = NSImage(size: NSSize(width: frame.width, height: frame.height))
        image.addRepresentation(representation)
        latestImage = image

        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastFrameHostTime, now > previous {
            frameIntervals.append(now - previous)
            if frameIntervals.count > 30 {
                frameIntervals.removeFirst(frameIntervals.count - 30)
            }
            let mean = frameIntervals.reduce(0, +) / Double(frameIntervals.count)
            if mean > 0 { framesPerSecond = 1.0 / mean }
        }
        lastFrameHostTime = now
    }

    private func defaultSDKURL() -> URL? {
        let candidates = [
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("vendor/amcam/macos/libamcam.dylib"),
            URL(fileURLWithPath: "vendor/amcam/macos/libamcam.dylib"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib"),
            URL(fileURLWithPath: "/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib"),
            URL(fileURLWithPath: "/Library/Frameworks/libamcam.dylib"),
            URL(fileURLWithPath: "/usr/local/lib/libamcam.dylib"),
            URL(fileURLWithPath: "/opt/homebrew/lib/libamcam.dylib")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
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
