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

    public static func == (lhs: AmcamDevice, rhs: AmcamDevice) -> Bool { lhs.identifier == rhs.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }

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


public enum AmcamAutoExposureMode: Int32, Codable, CaseIterable, Sendable {
    case manual = 0
    case continuous = 1
    case once = 2

    public var isAutomatic: Bool { self != .manual }
}

public struct AmcamExposureControl: Equatable, Sendable {
    public let autoMode: AmcamAutoExposureMode?
    public var automaticEnabled: Bool? { autoMode?.isAutomatic }
    public let readbackMicroseconds: UInt32?
    public let minimumMicroseconds: UInt32?
    public let maximumMicroseconds: UInt32?
    public let defaultMicroseconds: UInt32?
    public let requestedMicroseconds: UInt32?

    public init(autoMode: AmcamAutoExposureMode?, readbackMicroseconds: UInt32?, minimumMicroseconds: UInt32?, maximumMicroseconds: UInt32?, defaultMicroseconds: UInt32?, requestedMicroseconds: UInt32? = nil) {
        self.autoMode = autoMode
        self.readbackMicroseconds = readbackMicroseconds
        self.minimumMicroseconds = minimumMicroseconds
        self.maximumMicroseconds = maximumMicroseconds
        self.defaultMicroseconds = defaultMicroseconds
        self.requestedMicroseconds = requestedMicroseconds
    }
}

public struct AmcamCameraImageControls: Equatable, Sendable {
    public let colorMatrixEnabled: Bool?
    public let pixelFormatCode: Int32?
    public let supportedPixelFormats: [Int32]

    public init(colorMatrixEnabled: Bool?, pixelFormatCode: Int32?, supportedPixelFormats: [Int32]) {
        self.colorMatrixEnabled = colorMatrixEnabled
        self.pixelFormatCode = pixelFormatCode
        self.supportedPixelFormats = supportedPixelFormats
    }
}

public enum AmcamPixelFormatCode: Int32, CaseIterable, Sendable, Identifiable {
    case raw8 = 0
    case raw10 = 1
    case raw12 = 2
    case raw14 = 3
    case raw16 = 4
    case yuv411 = 5
    case vuyy = 6
    case yuv444 = 7
    case rgb888 = 8
    case gmcy8 = 9
    case gmcy12 = 10
    case uyvy = 11
    case raw12Packed = 12
    case raw11 = 13
    case hdr8HighLow = 14
    case hdr10HighLow = 15
    case hdr11HighLow = 16
    case hdr12HighLow = 17

    public var id: Int32 { rawValue }
    public var title: String {
        switch self {
        case .raw8: return "RAW 8"
        case .raw10: return "RAW 10"
        case .raw12: return "RAW 12"
        case .raw14: return "RAW 14"
        case .raw16: return "RAW 16"
        case .yuv411: return "YUV 411"
        case .vuyy: return "VUYY"
        case .yuv444: return "YUV 444"
        case .rgb888: return "RGB 888"
        case .gmcy8: return "GMCY 8"
        case .gmcy12: return "GMCY 12"
        case .uyvy: return "UYVY"
        case .raw12Packed: return "RAW 12 Packed"
        case .raw11: return "RAW 11"
        case .hdr8HighLow: return "HDR 8 (H+L)"
        case .hdr10HighLow: return "HDR 10 (H+L)"
        case .hdr11HighLow: return "HDR 11 (H+L)"
        case .hdr12HighLow: return "HDR 12 (H+L)"
        }
    }
}

public struct AmcamWhiteBalanceControl: Equatable, Sendable {
    public let temperature: Int32?
    public let tint: Int32?
    public let rgbGain: [Int32]?

    public init(temperature: Int32?, tint: Int32?, rgbGain: [Int32]? = nil) {
        self.temperature = temperature
        self.tint = tint
        self.rgbGain = rgbGain
    }
}

public struct AmcamGainControl: Equatable, Sendable {
    public let readbackPercent: UInt16
    public let minimumPercent: UInt16
    public let maximumPercent: UInt16
    public let defaultPercent: UInt16?
    public let requestedPercent: UInt16?

    public init(readbackPercent: UInt16, minimumPercent: UInt16, maximumPercent: UInt16,
                defaultPercent: UInt16?, requestedPercent: UInt16? = nil) {
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
    public let exposure: AmcamExposureControl?
    public let gain: AmcamGainControl?
    public let whiteBalance: AmcamWhiteBalanceControl?
    public let image: AmcamCameraImageControls?
    public let frameRate: AmcamFrameRateControl

    public init(exposure: AmcamExposureControl? = nil, gain: AmcamGainControl? = nil,
                whiteBalance: AmcamWhiteBalanceControl? = nil,
                image: AmcamCameraImageControls? = nil,
                frameRate: AmcamFrameRateControl) {
        self.exposure = exposure
        self.gain = gain
        self.whiteBalance = whiteBalance
        self.image = image
        self.frameRate = frameRate
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
    public let metadata: AmcamFrameMetadata?

    public init(width: Int, height: Int, bytesPerRow: Int, pixelFormat: AmcamPixelFormat, bytes: Data, sequence: UInt32?, deviceTimestampMicroseconds: UInt64?, metadata: AmcamFrameMetadata? = nil) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixelFormat = pixelFormat
        self.bytes = bytes
        self.sequence = sequence
        self.deviceTimestampMicroseconds = deviceTimestampMicroseconds
        self.metadata = metadata
    }
}
