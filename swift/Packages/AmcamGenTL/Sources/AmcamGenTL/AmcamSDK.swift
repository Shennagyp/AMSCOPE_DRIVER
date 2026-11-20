import AmcamABI
import Darwin
import Foundation

private typealias VersionFunction = @convention(c) () -> UnsafePointer<CChar>?
private typealias EnumerateFunction = @convention(c) (UnsafeMutablePointer<AmcamDeviceV2>?) -> UInt32
private typealias OpenFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
private typealias CloseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias GetSizeFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Int32
private typealias PutResolutionFunction = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Int32
private typealias GetResolutionIndexFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?) -> Int32
private typealias StartPullFunction = @convention(c) (UnsafeMutableRawPointer?, AmcamEventCallback?, UnsafeMutableRawPointer?) -> Int32
private typealias PullImageFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, UnsafeMutablePointer<AmcamFrameInfoV2>?) -> Int32
private typealias StopFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias GetAutoExposureFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> Int32
private typealias SetAutoExposureFunction = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
private typealias GetExposureTimeFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?) -> Int32
private typealias SetExposureTimeFunction = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Int32
private typealias GetExposureRangeFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
private typealias GetOptionFunction = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<Int32>?) -> Int32
private typealias SetOptionFunction = @convention(c) (UnsafeMutableRawPointer?, UInt32, Int32) -> Int32
private typealias GetSpeedFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt16>?) -> Int32
private typealias SetSpeedFunction = @convention(c) (UnsafeMutableRawPointer?, UInt16) -> Int32
private typealias GetFrameRateFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
private typealias GetExposureGainFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt16>?) -> Int32
private typealias SetExposureGainFunction = @convention(c) (UnsafeMutableRawPointer?, UInt16) -> Int32
private typealias GetExposureGainRangeFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt16>?) -> Int32
private typealias GetTemperatureTintFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Int32
private typealias SetTemperatureTintFunction = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32) -> Int32
private typealias GetWhiteBalanceGainFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> Int32
typealias AmcamEventCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Void

/// Keeps an Amcam SDK loaded when a camera handle could not be closed safely.
private final class AmcamSDKRetainer: @unchecked Sendable {
    static let shared = AmcamSDKRetainer()

    private let lock = NSLock()
    private var retainedSDKs: [AmcamSDK] = []

    func retain(_ sdk: AmcamSDK) {
        lock.lock()
        defer { lock.unlock() }
        retainedSDKs.append(sdk)
    }
}

final class AmcamSDK: @unchecked Sendable {
    static let expectedVersion = "58.28273.20250415"
    static let maximumDevices = 128
    static let imageEvent: UInt32 = 0x0004
    static let errorEvent: UInt32 = 0x0080
    static let disconnectedEvent: UInt32 = 0x0081
    static let frameSequenceFlag: UInt32 = 0x0001
    static let frameTimestampFlag: UInt32 = 0x0002
    static let requestedPullBits: Int32 = 24
    static let preciseFrameRateFlag: UInt64 = 0x0000004000000000
    static let optionMaximumPreciseFrameRate: UInt32 = 0x2c
    static let optionPreciseFrameRate: UInt32 = 0x2d
    static let optionMinimumPreciseFrameRate: UInt32 = 0x32
    static let optionColorMatrix: UInt32 = 0x0d
    static let optionWhiteBalanceGain: UInt32 = 0x0e
    static let optionPixelFormat: UInt32 = 0x1a
    static let temperatureMinimum: Int32 = 2_000
    static let temperatureMaximum: Int32 = 15_000
    static let tintMinimum: Int32 = 200
    static let tintMaximum: Int32 = 2_500

    private struct API {
        let version: VersionFunction
        let enumerate: EnumerateFunction
        let open: OpenFunction
        let close: CloseFunction
        let getSize: GetSizeFunction
        let putResolution: PutResolutionFunction?
        let getResolutionIndex: GetResolutionIndexFunction?
        let startPull: StartPullFunction
        let pullImage: PullImageFunction
        let stop: StopFunction
        let getAutoExposure: GetAutoExposureFunction
        let setAutoExposure: SetAutoExposureFunction
        let getExposureTime: GetExposureTimeFunction
        let setExposureTime: SetExposureTimeFunction
        let getExposureRange: GetExposureRangeFunction
        let getOption: GetOptionFunction
        let setOption: SetOptionFunction
        let getSpeed: GetSpeedFunction?
        let setSpeed: SetSpeedFunction?
        let getFrameRate: GetFrameRateFunction?
        let getExposureGain: GetExposureGainFunction?
        let setExposureGain: SetExposureGainFunction?
        let getExposureGainRange: GetExposureGainRangeFunction?
        let getTemperatureTint: GetTemperatureTintFunction?
        let setTemperatureTint: SetTemperatureTintFunction?
        let getWhiteBalanceGain: GetWhiteBalanceGainFunction?
    }

    private let library: UnsafeMutableRawPointer
    private let api: API

    init(libraryURL: URL) throws {
        let expectedVersion = Self.expectedVersion
        let path = libraryURL.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else { throw AmcamCameraError.libraryNotFound(path) }
        guard amcam_abi_layout_valid() == 1 else { throw AmcamCameraError.unsupportedABI }
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw AmcamCameraError.libraryLoadFailed(dlerror().map { String(cString: $0) } ?? "Unknown loader error")
        }

        do {
            func load<T>(_ name: String, as type: T.Type) throws -> T {
                guard let symbol = dlsym(handle, name) else { throw AmcamCameraError.missingSymbol(name) }
                return unsafeBitCast(symbol, to: type)
            }
            let resolved = API(
                version: try load("Amcam_Version", as: VersionFunction.self),
                enumerate: try load("Amcam_EnumV2", as: EnumerateFunction.self),
                open: try load("Amcam_Open", as: OpenFunction.self),
                close: try load("Amcam_Close", as: CloseFunction.self),
                getSize: try load("Amcam_get_Size", as: GetSizeFunction.self),
                putResolution: try? load("Amcam_put_eSize", as: PutResolutionFunction.self),
                getResolutionIndex: try? load("Amcam_get_eSize", as: GetResolutionIndexFunction.self),
                startPull: try load("Amcam_StartPullModeWithCallback", as: StartPullFunction.self),
                pullImage: try load("Amcam_PullImageV2", as: PullImageFunction.self),
                stop: try load("Amcam_Stop", as: StopFunction.self),
                getAutoExposure: try load("Amcam_get_AutoExpoEnable", as: GetAutoExposureFunction.self),
                setAutoExposure: try load("Amcam_put_AutoExpoEnable", as: SetAutoExposureFunction.self),
                getExposureTime: try load("Amcam_get_ExpoTime", as: GetExposureTimeFunction.self),
                setExposureTime: try load("Amcam_put_ExpoTime", as: SetExposureTimeFunction.self),
                getExposureRange: try load("Amcam_get_ExpTimeRange", as: GetExposureRangeFunction.self),
                getOption: try load("Amcam_get_Option", as: GetOptionFunction.self),
                setOption: try load("Amcam_put_Option", as: SetOptionFunction.self),
                getSpeed: try? load("Amcam_get_Speed", as: GetSpeedFunction.self),
                setSpeed: try? load("Amcam_put_Speed", as: SetSpeedFunction.self),
                getFrameRate: try? load("Amcam_get_FrameRate", as: GetFrameRateFunction.self),
                getExposureGain: try? load("Amcam_get_ExpoAGain", as: GetExposureGainFunction.self),
                setExposureGain: try? load("Amcam_put_ExpoAGain", as: SetExposureGainFunction.self),
                getExposureGainRange: try? load("Amcam_get_ExpoAGainRange", as: GetExposureGainRangeFunction.self),
                getTemperatureTint: try? load("Amcam_get_TempTint", as: GetTemperatureTintFunction.self),
                setTemperatureTint: try? load("Amcam_put_TempTint", as: SetTemperatureTintFunction.self),
                getWhiteBalanceGain: try? load("Amcam_get_WhiteBalanceGain", as: GetWhiteBalanceGainFunction.self)
            )
            guard let versionPointer = resolved.version() else {
                throw AmcamCameraError.incompatibleSDK(expected: expectedVersion, actual: "null")
            }
            let actualVersion = String(cString: versionPointer)
            guard actualVersion == expectedVersion else {
                throw AmcamCameraError.incompatibleSDK(expected: expectedVersion, actual: actualVersion)
            }
            self.library = handle
            self.api = resolved
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit { dlclose(library) }

    /// Called only if final camera-session cleanup fails. Unloading this dynamic
    /// library could invalidate callbacks or handles still owned by the SDK.
    func retainForProcessLifetimeAfterCleanupFailure() {
        AmcamSDKRetainer.shared.retain(self)
    }

    var resolutionChangeAvailable: Bool {
        api.putResolution != nil
    }


    func enumerate() throws -> [AmcamDevice] {
        let allocationSize = MemoryLayout<AmcamDeviceV2>.stride * Self.maximumDevices
        let rawStorage = UnsafeMutableRawPointer.allocate(
            byteCount: allocationSize,
            alignment: MemoryLayout<AmcamDeviceV2>.alignment
        )
        rawStorage.initializeMemory(as: UInt8.self, repeating: 0, count: allocationSize)
        let devices = rawStorage.bindMemory(to: AmcamDeviceV2.self, capacity: Self.maximumDevices)
        defer { rawStorage.deallocate() }
        let count = Int(api.enumerate(devices))
        guard count <= Self.maximumDevices else {
            throw AmcamCameraError.enumerationFailed("SDK reported \(count) devices; maximum is \(Self.maximumDevices)")
        }
        var result: [AmcamDevice] = []
        result.reserveCapacity(count)

        for index in 0..<count {
            let pointer = devices.advanced(by: index)
            var identifierBuffer = [CChar](repeating: 0, count: 65)
            var displayNameBuffer = [CChar](repeating: 0, count: 65)

            let identifierIsValid = identifierBuffer.withUnsafeMutableBufferPointer {
                amcam_device_copy_identifier(pointer, $0.baseAddress, $0.count)
            }
            guard identifierIsValid == 1 else {
                throw AmcamCameraError.enumerationFailed(
                    "Device entry \(index) has an unterminated or invalid 64-byte identifier field."
                )
            }

            let displayNameIsValid = displayNameBuffer.withUnsafeMutableBufferPointer {
                amcam_device_copy_display_name(pointer, $0.baseAddress, $0.count)
            }
            guard displayNameIsValid == 1 else {
                throw AmcamCameraError.enumerationFailed(
                    "Device entry \(index) has an unterminated or invalid 64-byte display-name field."
                )
            }

            let identifier = String(cString: identifierBuffer)
            guard !identifier.isEmpty else {
                throw AmcamCameraError.enumerationFailed(
                    "Device entry \(index) has an empty identifier."
                )
            }

            let rawDisplayName = String(cString: displayNameBuffer)
            let displayName = rawDisplayName.isEmpty ? identifier : rawDisplayName

            guard let model = pointer.pointee.model else {
                result.append(
                    AmcamDevice(
                        identifier: identifier,
                        displayName: displayName,
                        modelName: nil,
                        modelFlags: nil,
                        maximumSpeedLevel: nil,
                        sensorPixelSizeMicrometers: nil,
                        previewResolutions: []
                    )
                )
                continue
            }

            let value = model.pointee
            let modelName = value.name.map { String(cString: $0) }
            let resolutions = (0..<min(Int(value.preview), 16)).compactMap { resolutionIndex -> AmcamResolution? in
                var width: UInt32 = 0
                var height: UInt32 = 0
                guard amcam_model_resolution(
                    model,
                    UInt32(resolutionIndex),
                    &width,
                    &height
                ) == 1, width > 0, height > 0 else {
                    return nil
                }
                return AmcamResolution(
                    index: resolutionIndex,
                    width: Int(width),
                    height: Int(height)
                )
            }

            result.append(
                AmcamDevice(
                    identifier: identifier,
                    displayName: displayName,
                    modelName: modelName,
                    modelFlags: value.flag,
                    maximumSpeedLevel: Int(value.maxspeed),
                    sensorPixelSizeMicrometers: (Double(value.xpixsz), Double(value.ypixsz)),
                    previewResolutions: resolutions
                )
            )
        }

        return result
    }

    func open(identifier: String) throws -> (handle: UnsafeMutableRawPointer, width: Int, height: Int, modelName: String?, modelFlags: UInt64?, maximumSpeedLevel: Int?, resolutions: [AmcamResolution], currentResolutionIndex: Int?) {
        guard identifier.utf8.allSatisfy({ $0 < 0x80 }) else { throw AmcamCameraError.invalidDeviceIdentifier }
        guard let descriptor = try enumerate().first(where: { $0.identifier == identifier }) else {
            throw AmcamCameraError.deviceNotFound(identifier)
        }
        guard let handle = identifier.withCString({ api.open($0) }) else { throw AmcamCameraError.deviceOpenFailed }
        var width: Int32 = 0
        var height: Int32 = 0
        let result = api.getSize(handle, &width, &height)
        guard result >= 0, width > 0, height > 0 else {
            api.close(handle)
            throw AmcamCameraError.cameraReadbackFailed(operation: "Amcam_get_Size", code: result)
        }
        let currentWidth = Int(width)
        let currentHeight = Int(height)
        var reportedResolutionIndex: UInt32 = 0
        let indexResult = api.getResolutionIndex?(handle, &reportedResolutionIndex) ?? -1
        let currentIndex = indexResult >= 0
            ? Int(reportedResolutionIndex)
            : descriptor.previewResolutions.first {
                $0.width == currentWidth && $0.height == currentHeight
            }?.index
        return (
            handle,
            currentWidth,
            currentHeight,
            descriptor.modelName,
            descriptor.modelFlags,
            descriptor.maximumSpeedLevel,
            descriptor.previewResolutions,
            currentIndex
        )
    }

    func setResolution(
        _ handle: UnsafeMutableRawPointer,
        index: Int,
        supportedResolutions: [AmcamResolution]
    ) throws -> AmcamResolution {
        guard let resolution = supportedResolutions.first(where: { $0.index == index }),
              index >= 0,
              index <= Int(UInt32.max) else {
            throw AmcamCameraError.unsupportedResolution(index)
        }
        guard let putResolution = api.putResolution else {
            throw AmcamCameraError.unsupportedControl(
                "The loaded Amcam SDK does not expose Amcam_put_eSize; resolution calibration is unavailable."
            )
        }
        let result = putResolution(handle, UInt32(index))
        try checkControlResult("Amcam_put_eSize", result)

        var width: Int32 = 0
        var height: Int32 = 0
        let readbackResult = api.getSize(handle, &width, &height)
        try checkControlResult("Amcam_get_Size", readbackResult)
        guard Int(width) == resolution.width, Int(height) == resolution.height else {
            throw AmcamCameraError.resolutionReadbackMismatch(
                requested: "\(resolution.width)x\(resolution.height)",
                actual: "\(width)x\(height)"
            )
        }
        if let getResolutionIndex = api.getResolutionIndex {
            var actualIndex: UInt32 = 0
            let indexReadbackResult = getResolutionIndex(handle, &actualIndex)
            try checkControlResult("Amcam_get_eSize", indexReadbackResult)
            guard Int(actualIndex) == index else {
                throw AmcamCameraError.resolutionReadbackMismatch(
                    requested: "index \(index) (\(resolution.width)x\(resolution.height))",
                    actual: "index \(actualIndex) (\(width)x\(height))"
                )
            }
        }
        return resolution
    }

    func readAutoExposureMode(_ handle: UnsafeMutableRawPointer) throws -> AmcamAutoExposureMode {
        var value: Int32 = 0
        let result = api.getAutoExposure(handle, &value)
        try checkControlResult("Amcam_get_AutoExpoEnable", result)
        guard let mode = AmcamAutoExposureMode(rawValue: value) else {
            throw AmcamCameraError.unsupportedControl("The camera returned unknown auto-exposure mode \\(value).")
        }
        return mode
    }

    func setAutoExposureMode(_ handle: UnsafeMutableRawPointer, mode: AmcamAutoExposureMode) throws {
        let result = api.setAutoExposure(handle, Int32(mode.rawValue))
        try checkControlResult("Amcam_put_AutoExpoEnable", result)
    }

    func readExposureTime(_ handle: UnsafeMutableRawPointer) throws -> (current: UInt32, minimum: UInt32, maximum: UInt32, defaultValue: UInt32) {
        var current: UInt32 = 0
        var minimum: UInt32 = 0
        var maximum: UInt32 = 0
        var defaultValue: UInt32 = 0
        let currentResult = api.getExposureTime(handle, &current)
        try checkControlResult("Amcam_get_ExpoTime", currentResult)
        let rangeResult = api.getExposureRange(handle, &minimum, &maximum, &defaultValue)
        try checkControlResult("Amcam_get_ExpTimeRange", rangeResult)
        guard minimum > 0, maximum >= minimum, current >= minimum, current <= maximum else {
            throw AmcamCameraError.invalidExposureRange(minimum: minimum, maximum: maximum, current: current)
        }
        return (current, minimum, maximum, defaultValue)
    }

    func setExposureTime(_ handle: UnsafeMutableRawPointer, microseconds: UInt32) throws {
        let result = api.setExposureTime(handle, microseconds)
        try checkControlResult("Amcam_put_ExpoTime", result)
    }

    var exposureGainControlAvailable: Bool {
        api.getExposureGain != nil && api.setExposureGain != nil && api.getExposureGainRange != nil
    }

    func readExposureGain(_ handle: UnsafeMutableRawPointer) throws -> (current: UInt16, minimum: UInt16, maximum: UInt16, defaultValue: UInt16) {
        guard let getGain = api.getExposureGain,
              let getRange = api.getExposureGainRange else {
            throw AmcamCameraError.unsupportedControl("The loaded Amcam SDK does not expose exposure analog-gain queries.")
        }
        var current: UInt16 = 0
        var minimum: UInt16 = 0
        var maximum: UInt16 = 0
        var defaultValue: UInt16 = 0
        try checkControlResult("Amcam_get_ExpoAGain", getGain(handle, &current))
        try checkControlResult("Amcam_get_ExpoAGainRange", getRange(handle, &minimum, &maximum, &defaultValue))
        guard minimum <= maximum, current >= minimum, current <= maximum else {
            throw AmcamCameraError.unsupportedControl("The camera returned an invalid analog-gain range or readback.")
        }
        return (current, minimum, maximum, defaultValue)
    }

    func setExposureGain(_ handle: UnsafeMutableRawPointer, percent: UInt16) throws {
        guard let setGain = api.setExposureGain else {
            throw AmcamCameraError.unsupportedControl("The loaded Amcam SDK does not expose exposure analog-gain control.")
        }
        try checkControlResult("Amcam_put_ExpoAGain", setGain(handle, percent))
    }

    var whiteBalanceControlAvailable: Bool {
        api.getTemperatureTint != nil && api.setTemperatureTint != nil
    }

    func readTemperatureTint(_ handle: UnsafeMutableRawPointer) throws -> (temperature: Int32, tint: Int32) {
        guard let getter = api.getTemperatureTint else {
            throw AmcamCameraError.unsupportedControl("The loaded Amcam SDK does not expose temperature/tint white-balance readback.")
        }
        var temperature: Int32 = 0
        var tint: Int32 = 0
        try checkControlResult("Amcam_get_TempTint", getter(handle, &temperature, &tint))
        return (temperature, tint)
    }

    func setTemperatureTint(_ handle: UnsafeMutableRawPointer, temperature: Int32, tint: Int32) throws {
        guard let setter = api.setTemperatureTint else {
            throw AmcamCameraError.unsupportedControl("The loaded Amcam SDK does not expose temperature/tint white-balance control.")
        }
        try checkControlResult("Amcam_put_TempTint", setter(handle, temperature, tint))
    }

    func readWhiteBalanceGain(_ handle: UnsafeMutableRawPointer) throws -> [Int32] {
        guard let getter = api.getWhiteBalanceGain else {
            throw AmcamCameraError.unsupportedControl("The loaded Amcam SDK does not expose RGB white-balance gain readback.")
        }
        var values = [Int32](repeating: 0, count: 3)
        let result = values.withUnsafeMutableBufferPointer { buffer in
            getter(handle, buffer.baseAddress)
        }
        try checkControlResult("Amcam_get_WhiteBalanceGain", result)
        return values
    }

    func readOption(_ handle: UnsafeMutableRawPointer, option: UInt32) throws -> Int32 {
        var value: Int32 = 0
        let result = api.getOption(handle, option, &value)
        try checkControlResult("Amcam_get_Option(0x\(String(option, radix: 16)))", result)
        return value
    }

    func setOption(_ handle: UnsafeMutableRawPointer, option: UInt32, value: Int32) throws {
        let result = api.setOption(handle, option, value)
        try checkControlResult("Amcam_put_Option(0x\(String(option, radix: 16)))", result)
    }

    func readRecentFrameRate(_ handle: UnsafeMutableRawPointer) -> (framesPerSecond: Double, frameCount: UInt32, windowMilliseconds: UInt32, totalFrameCount: UInt32)? {
        guard let getFrameRate = api.getFrameRate else { return nil }
        var frameCount: UInt32 = 0
        var windowMilliseconds: UInt32 = 0
        var totalFrameCount: UInt32 = 0
        let result = getFrameRate(handle, &frameCount, &windowMilliseconds, &totalFrameCount)
        guard result >= 0, frameCount > 0, windowMilliseconds > 0 else { return nil }
        let value = Double(frameCount) * 1_000.0 / Double(windowMilliseconds)
        guard value.isFinite, value > 0 else { return nil }
        return (value, frameCount, windowMilliseconds, totalFrameCount)
    }

    var speedControlAvailable: Bool {
        api.getSpeed != nil && api.setSpeed != nil
    }

    func readSpeedLevel(_ handle: UnsafeMutableRawPointer) throws -> Int {
        guard let getSpeed = api.getSpeed else {
            throw AmcamCameraError.unsupportedControl("The loaded Amcam SDK does not expose get_Speed.")
        }
        var value: UInt16 = 0
        let result = getSpeed(handle, &value)
        try checkControlResult("Amcam_get_Speed", result)
        return Int(value)
    }

    func setSpeedLevel(_ handle: UnsafeMutableRawPointer, level: Int) throws {
        guard level >= 0, level <= Int(UInt16.max) else {
            throw AmcamCameraError.invalidSpeedLevel(level)
        }
        guard let setSpeed = api.setSpeed else {
            throw AmcamCameraError.unsupportedControl("The loaded Amcam SDK does not expose put_Speed.")
        }
        let result = setSpeed(handle, UInt16(level))
        try checkControlResult("Amcam_put_Speed", result)
    }

    private func checkControlResult(_ operation: String, _ result: Int32) throws {
        guard result >= 0 else {
            throw AmcamCameraError.cameraControlFailed(operation: operation, code: result)
        }
    }

    func close(_ handle: UnsafeMutableRawPointer) { api.close(handle) }
    func startPull(_ handle: UnsafeMutableRawPointer, callback: AmcamEventCallback, context: UnsafeMutableRawPointer) -> Int32 { api.startPull(handle, callback, context) }
    func pullImage(_ handle: UnsafeMutableRawPointer, buffer: UnsafeMutableRawPointer, frameInfo: UnsafeMutablePointer<AmcamFrameInfoV2>) -> Int32 {
        api.pullImage(handle, buffer, Self.requestedPullBits, frameInfo)
    }
    func stop(_ handle: UnsafeMutableRawPointer) -> Int32 { api.stop(handle) }
}
