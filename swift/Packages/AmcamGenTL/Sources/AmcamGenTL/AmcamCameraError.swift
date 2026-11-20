import Foundation

public enum AmcamCameraError: Error, LocalizedError, Sendable {
    case libraryNotFound(String)
    case libraryLoadFailed(String)
    case missingSymbol(String)
    case incompatibleSDK(expected: String, actual: String)
    case unsupportedABI
    case enumerationFailed(String)
    case invalidDeviceIdentifier
    case deviceOpenFailed
    case cameraReadbackFailed(operation: String, code: Int32)
    case cameraControlFailed(operation: String, code: Int32)
    case invalidExposureRange(minimum: UInt32, maximum: UInt32, current: UInt32)
    case deviceNotFound(String)
    case unsupportedControl(String)
    case automaticExposureMustBeDisabled
    case exposureOutOfRange(requested: UInt32, minimum: UInt32, maximum: UInt32)
    case invalidFrameRate(Double)
    case frameRateOutOfRange(requested: Double, minimum: Double, maximum: Double)
    case invalidSpeedLevel(Int)
    case speedLevelOutOfRange(requested: Int, minimum: Int, maximum: Int)
    case unsupportedResolution(Int)
    case resolutionChangeRequiresStoppedStream
    case resolutionReadbackMismatch(requested: String, actual: String)
    case controlReadbackMismatch(control: String, requested: String, actual: String)
    case invalidFrameDimensions
    case frameBufferTooLarge
    case alreadyStreaming
    case notStreaming
    case sessionClosed
    case transitionInProgress
    case streamStartFailed(Int32)
    case streamStopFailed(Int32)
    case cameraDisconnected
    case cameraEventFailure(UInt32)

    var errorDescription: String? {
        switch self {
        case .libraryNotFound(let path): return "Amcam SDK library not found at: \(path)"
        case .libraryLoadFailed(let message): return "Unable to load Amcam SDK: \(message)"
        case .missingSymbol(let name): return "Amcam SDK is missing required symbol \(name)."
        case .incompatibleSDK(let expected, let actual): return "Unsupported Amcam SDK version. Expected \(expected), received \(actual)."
        case .unsupportedABI: return "The compiled Amcam ABI layout does not match the verified 64-bit macOS SDK 58 layout."
        case .enumerationFailed(let message): return "Amcam device enumeration failed: \(message)"
        case .invalidDeviceIdentifier: return "The Amcam device identifier is not a valid ASCII identifier."
        case .deviceOpenFailed: return "Amcam_Open returned a null camera handle."
        case .cameraReadbackFailed(let operation, let code): return "\(operation) failed with Amcam result \(code)."
        case .cameraControlFailed(let operation, let code): return "\(operation) failed with Amcam result \(code)."
        case .invalidExposureRange(let minimum, let maximum, let current): return "Amcam returned an invalid exposure range (\(minimum)…\(maximum) µs) or current exposure (\(current) µs)."
        case .deviceNotFound(let identifier): return "Amcam device is no longer available: \(identifier)"
        case .unsupportedControl(let message): return message
        case .automaticExposureMustBeDisabled: return "Disable automatic exposure before setting a fixed exposure time."
        case .exposureOutOfRange(let requested, let minimum, let maximum): return "Requested exposure \(requested) µs is outside the camera range \(minimum)…\(maximum) µs."
        case .invalidFrameRate(let value): return "Requested frame rate must be finite, positive and aligned to the SDK's 0.1 FPS increments; received \(value)."
        case .frameRateOutOfRange(let requested, let minimum, let maximum): return "Requested frame rate \(requested) FPS is outside the camera range \(minimum)…\(maximum) FPS."
        case .invalidSpeedLevel(let value): return "Camera speed level must be a non-negative integer; received \(value)."
        case .speedLevelOutOfRange(let requested, let minimum, let maximum): return "Requested camera speed level \(requested) is outside the supported range \(minimum)…\(maximum)."
        case .unsupportedResolution(let index): return "Camera resolution index \(index) is not supported."
        case .resolutionChangeRequiresStoppedStream: return "Stop the camera stream before changing resolution."
        case .resolutionReadbackMismatch(let requested, let actual): return "Camera resolution readback mismatch. Requested: \(requested); read back: \(actual)."
        case .controlReadbackMismatch(let control, let requested, let actual): return "Camera did not confirm the requested \(control). Requested: \(requested); read back: \(actual)."
        case .invalidFrameDimensions: return "Amcam returned invalid or unexpected frame dimensions."
        case .frameBufferTooLarge: return "The requested frame buffer size exceeds the supported allocation limit."
        case .alreadyStreaming: return "The Amcam camera session is already streaming."
        case .notStreaming: return "The Amcam camera session is not streaming."
        case .sessionClosed: return "The Amcam camera session is closed."
        case .transitionInProgress: return "The Amcam camera session is changing state; retry after the transition completes."
        case .streamStartFailed(let code): return "Amcam_StartPullModeWithCallback failed with result \(code)."
        case .streamStopFailed(let code): return "Amcam_Stop failed with result \(code)."
        case .cameraDisconnected: return "The Amcam camera disconnected."
        case .cameraEventFailure(let event): return "Amcam reported camera event 0x\(String(event, radix: 16))."
        }
    }
}
