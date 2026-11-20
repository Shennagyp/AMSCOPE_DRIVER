import Foundation

struct AmcamResolution: Hashable, Sendable {
    let index: Int
    let width: Int
    let height: Int

    init(index: Int, width: Int, height: Int) {
        self.index = index
        self.width = width
        self.height = height
    }
}

struct AmcamDevice: Hashable, Sendable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let displayName: String
    let modelName: String?
    let modelFlags: UInt64?
    let maximumSpeedLevel: Int?
    let sensorPixelSizeMicrometers: (x: Double, y: Double)?
    let previewResolutions: [AmcamResolution]

    static func == (lhs: AmcamDevice, rhs: AmcamDevice) -> Bool { lhs.identifier == rhs.identifier }
    func hash(into hasher: inout Hasher) { hasher.combine(identifier) }

    init(identifier: String, displayName: String, modelName: String?, modelFlags: UInt64?, maximumSpeedLevel: Int?, sensorPixelSizeMicrometers: (x: Double, y: Double)?, previewResolutions: [AmcamResolution]) {
        self.identifier = identifier
        self.displayName = displayName
        self.modelName = modelName
        self.modelFlags = modelFlags
        self.maximumSpeedLevel = maximumSpeedLevel
        self.sensorPixelSizeMicrometers = sensorPixelSizeMicrometers
        self.previewResolutions = previewResolutions
    }
}


struct AmcamExposureControl: Equatable, Sendable {
    let automaticEnabled: Bool
    let readbackMicroseconds: UInt32
    let minimumMicroseconds: UInt32
    let maximumMicroseconds: UInt32
    let defaultMicroseconds: UInt32
    let requestedMicroseconds: UInt32?

    init(automaticEnabled: Bool, readbackMicroseconds: UInt32, minimumMicroseconds: UInt32, maximumMicroseconds: UInt32, defaultMicroseconds: UInt32, requestedMicroseconds: UInt32? = nil) {
        self.automaticEnabled = automaticEnabled
        self.readbackMicroseconds = readbackMicroseconds
        self.minimumMicroseconds = minimumMicroseconds
        self.maximumMicroseconds = maximumMicroseconds
        self.defaultMicroseconds = defaultMicroseconds
        self.requestedMicroseconds = requestedMicroseconds
    }
}

struct AmcamFrameRateControl: Equatable, Sendable {
    /// Recent camera-side frame-rate sample from the SDK's rolling measurement window.
    let deviceMeasuredFramesPerSecond: Double?
    let deviceMeasuredFrameCount: UInt32?
    let deviceMeasurementWindowMilliseconds: UInt32?
    let deviceTotalFrameCount: UInt32?
    let supported: Bool
    let minimumFramesPerSecond: Double?
    let maximumFramesPerSecond: Double?
    let readbackFramesPerSecond: Double?
    let requestedFramesPerSecond: Double?
    let unsupportedReason: String?
    let speedLevelSupported: Bool
    let currentSpeedLevel: Int?
    let requestedSpeedLevel: Int?
    let maximumSpeedLevel: Int?

    init(supported: Bool, minimumFramesPerSecond: Double? = nil, maximumFramesPerSecond: Double? = nil, readbackFramesPerSecond: Double? = nil, requestedFramesPerSecond: Double? = nil, unsupportedReason: String? = nil, speedLevelSupported: Bool = false, currentSpeedLevel: Int? = nil, requestedSpeedLevel: Int? = nil, maximumSpeedLevel: Int? = nil, deviceMeasuredFramesPerSecond: Double? = nil, deviceMeasuredFrameCount: UInt32? = nil, deviceMeasurementWindowMilliseconds: UInt32? = nil, deviceTotalFrameCount: UInt32? = nil) {
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

struct AmcamControlSnapshot: Equatable, Sendable {
    let exposure: AmcamExposureControl
    let frameRate: AmcamFrameRateControl

    init(exposure: AmcamExposureControl, frameRate: AmcamFrameRateControl) {
        self.exposure = exposure
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

enum AmcamPixelFormat: String, Sendable { case rgb24 }

struct AmcamFrame: Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixelFormat: AmcamPixelFormat
    let bytes: Data
    let sequence: UInt32?
    let deviceTimestampMicroseconds: UInt64?

    init(width: Int, height: Int, bytesPerRow: Int, pixelFormat: AmcamPixelFormat, bytes: Data, sequence: UInt32?, deviceTimestampMicroseconds: UInt64?) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixelFormat = pixelFormat
        self.bytes = bytes
        self.sequence = sequence
        self.deviceTimestampMicroseconds = deviceTimestampMicroseconds
    }
}
