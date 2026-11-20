import Foundation

public struct AmcamResolution: Hashable, Sendable {
    public let index: Int
    public let width: Int
    public let height: Int

    public init(index: Int, width: Int, height: Int) {
        self.index = index
        self.width = width
        self.height = height
    }
}

public struct AmcamDevice: Hashable, Sendable, Identifiable {
    public var id: String { identifier }
    public let identifier: String
    public let displayName: String
    public let modelName: String?
    public var modelCode: String { modelName ?? "Unknown" }
    public let modelFlags: UInt64?
    public let maximumSpeedLevel: Int?
    public let sensorPixelSizeMicrometers: (x: Double, y: Double)?
    public let previewResolutions: [AmcamResolution]

    static func == (lhs: AmcamDevice, rhs: AmcamDevice) -> Bool { lhs.identifier == rhs.identifier }
    func hash(into hasher: inout Hasher) { hasher.combine(identifier) }

    public init(identifier: String, displayName: String, modelName: String?, modelFlags: UInt64?, maximumSpeedLevel: Int?, sensorPixelSizeMicrometers: (x: Double, y: Double)?, previewResolutions: [AmcamResolution]) {
        self.identifier = identifier
        self.displayName = displayName
        self.modelName = modelName
        self.modelFlags = modelFlags
        self.maximumSpeedLevel = maximumSpeedLevel
        self.sensorPixelSizeMicrometers = sensorPixelSizeMicrometers
        self.previewResolutions = previewResolutions
    }
}


public enum AmcamAutoExposureMode: Int, Codable, CaseIterable, Sendable {
    case manual = 0
    case continuous = 1
    case once = 2

    public var isAutomatic: Bool { self != .manual }
}

public struct AmcamExposureControl: Equatable, Sendable {
    public let autoMode: AmcamAutoExposureMode
    public var automaticEnabled: Bool { autoMode.isAutomatic }
    public let readbackMicroseconds: UInt32
    public let minimumMicroseconds: UInt32
    public let maximumMicroseconds: UInt32
    public let defaultMicroseconds: UInt32
    public let requestedMicroseconds: UInt32?

    public init(autoMode: AmcamAutoExposureMode, readbackMicroseconds: UInt32, minimumMicroseconds: UInt32, maximumMicroseconds: UInt32, defaultMicroseconds: UInt32, requestedMicroseconds: UInt32? = nil) {
        self.autoMode = autoMode
        self.readbackMicroseconds = readbackMicroseconds
        self.minimumMicroseconds = minimumMicroseconds
        self.maximumMicroseconds = maximumMicroseconds
        self.defaultMicroseconds = defaultMicroseconds
        self.requestedMicroseconds = requestedMicroseconds
    }
}

public struct AmcamGainControl: Equatable, Sendable {
    public let readbackPercent: UInt16
    public let minimumPercent: UInt16
    public let maximumPercent: UInt16
    public let defaultPercent: UInt16
    public let requestedPercent: UInt16?

    public init(readbackPercent: UInt16, minimumPercent: UInt16, maximumPercent: UInt16,
                defaultPercent: UInt16, requestedPercent: UInt16? = nil) {
        self.readbackPercent = readbackPercent
        self.minimumPercent = minimumPercent
        self.maximumPercent = maximumPercent
        self.defaultPercent = defaultPercent
        self.requestedPercent = requestedPercent
    }
}

public struct AmcamFrameRateControl: Equatable, Sendable {
    /// Recent camera-side frame-rate sample from the SDK's rolling measurement window.
    public let deviceMeasuredFramesPerSecond: Double?
    public let deviceMeasuredFrameCount: UInt32?
    public let deviceMeasurementWindowMilliseconds: UInt32?
    public let deviceTotalFrameCount: UInt32?
    public let supported: Bool
    public let minimumFramesPerSecond: Double?
    public let maximumFramesPerSecond: Double?
    public let readbackFramesPerSecond: Double?
    public let requestedFramesPerSecond: Double?
    public let unsupportedReason: String?
    public let speedLevelSupported: Bool
    public let currentSpeedLevel: Int?
    public let requestedSpeedLevel: Int?
    public let maximumSpeedLevel: Int?

    public init(supported: Bool, minimumFramesPerSecond: Double? = nil, maximumFramesPerSecond: Double? = nil, readbackFramesPerSecond: Double? = nil, requestedFramesPerSecond: Double? = nil, unsupportedReason: String? = nil, speedLevelSupported: Bool = false, currentSpeedLevel: Int? = nil, requestedSpeedLevel: Int? = nil, maximumSpeedLevel: Int? = nil, deviceMeasuredFramesPerSecond: Double? = nil, deviceMeasuredFrameCount: UInt32? = nil, deviceMeasurementWindowMilliseconds: UInt32? = nil, deviceTotalFrameCount: UInt32? = nil) {
        self.supported = supported
        self.minimumFramesPerSecond = minimumFramesPerSecond
        self.maximumFramesPerSecond = maximumFramesPerSecond
        self.readbackFramesPerSecond = readbackFramesPerSecond
        self.requestedFramesPerSecond = requestedFramesPerSecond
        self.unsupportedReason = unsupportedReason
        self.speedLevelSupported = speedLevelSupported
        self.currentSpeedLevel = currentSpeedLevel
        self.requestedSpeedLevel = requestedSpeedLevel
        self.maximumSpeedLevel = maximumSpeedLevel
        self.deviceMeasuredFramesPerSecond = deviceMeasuredFramesPerSecond
        self.deviceMeasuredFrameCount = deviceMeasuredFrameCount
        self.deviceMeasurementWindowMilliseconds = deviceMeasurementWindowMilliseconds
        self.deviceTotalFrameCount = deviceTotalFrameCount
    }
}

public struct AmcamControlSnapshot: Equatable, Sendable {
    public let exposure: AmcamExposureControl
    public let gain: AmcamGainControl?
    public let frameRate: AmcamFrameRateControl

    public init(exposure: AmcamExposureControl, gain: AmcamGainControl? = nil,
                frameRate: AmcamFrameRateControl) {
        self.exposure = exposure
        self.gain = gain
        self.frameRate = frameRate
    }
}

/// Byte layout returned by Amcam_PullImageV2 for 24-bit RGB output.
/// The SDK's default row pitch is DWORD aligned, so rows may include up to
/// three padding bytes even though each pixel occupies exactly three bytes.
struct AmcamRGB24Layout: Equatable, Sendable {
    let bytesPerRow: Int
    let rowPaddingBytes: Int
    let payloadSize: Int

    init?(width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }

        let (packedRowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 3)
        guard !rowOverflow else { return nil }

        let (roundedRowBytes, paddingOverflow) = packedRowBytes.addingReportingOverflow(3)
        guard !paddingOverflow else { return nil }
        let alignedRowBytes = roundedRowBytes & ~3

        let (totalBytes, payloadOverflow) =
            alignedRowBytes.multipliedReportingOverflow(by: height)
        guard !payloadOverflow, totalBytes > 0 else { return nil }

        self.bytesPerRow = alignedRowBytes
        self.rowPaddingBytes = alignedRowBytes - packedRowBytes
        self.payloadSize = totalBytes
    }
}

public enum AmcamPixelFormat: String, Sendable { case rgb24 }

public struct AmcamFrame: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixelFormat: AmcamPixelFormat
    public let bytes: Data
    public let sequence: UInt32?
    public let deviceTimestampMicroseconds: UInt64?

    public init(width: Int, height: Int, bytesPerRow: Int, pixelFormat: AmcamPixelFormat, bytes: Data, sequence: UInt32?, deviceTimestampMicroseconds: UInt64?) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixelFormat = pixelFormat
        self.bytes = bytes
        self.sequence = sequence
        self.deviceTimestampMicroseconds = deviceTimestampMicroseconds
    }
}
