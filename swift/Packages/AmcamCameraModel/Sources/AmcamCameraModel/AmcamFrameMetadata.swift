import Foundation

public enum AmcamFrameInfoVersion: Int, Equatable, Sendable {
    case v2 = 2
    case v3 = 3
    case v4 = 4
}

/// GPS values are retained in the units used by the Amcam ABI.
public struct AmcamFrameGPSMetadata: Equatable, Sendable {
    /// Nanoseconds since the Unix epoch, as reported by the camera.
    public let exposureStartUnixNanoseconds: Int64
    public let exposureEndUnixNanoseconds: Int64
    /// Degrees multiplied by 1,000,000.
    public let longitudeMicrodegrees: Int32
    public let latitudeMicrodegrees: Int32
    /// Millimetres.
    public let altitudeMillimetres: Int32
    public let satelliteCount: UInt16

    public init(exposureStartUnixNanoseconds: Int64, exposureEndUnixNanoseconds: Int64,
                longitudeMicrodegrees: Int32, latitudeMicrodegrees: Int32,
                altitudeMillimetres: Int32, satelliteCount: UInt16) {
        self.exposureStartUnixNanoseconds = exposureStartUnixNanoseconds
        self.exposureEndUnixNanoseconds = exposureEndUnixNanoseconds
        self.longitudeMicrodegrees = longitudeMicrodegrees
        self.latitudeMicrodegrees = latitudeMicrodegrees
        self.altitudeMillimetres = altitudeMillimetres
        self.satelliteCount = satelliteCount
    }
}

/// Optional per-frame values are populated only when the corresponding
/// AMCAM_FRAMEINFO_FLAG bit says that the SDK considers the value valid.
public struct AmcamFrameMetadata: Equatable, Sendable {
    public let apiVersion: AmcamFrameInfoVersion
    public let validityFlags: UInt32
    public let shutterSequence: UInt32?
    public let exposureTimeMicroseconds: UInt32?
    public let exposureGain: UInt16?
    public let blackLevel: UInt16?
    public let luminance: UInt32?
    public let focusValue: Int64?
    public let timeCount: Int64?
    public let frameCount: UInt32?
    public let triggerCount: UInt32?
    public let gps: AmcamFrameGPSMetadata?
    public let mechanicalShutterClosed: Bool?
    public let conversionGainHigh: Bool?

    public init(apiVersion: AmcamFrameInfoVersion, validityFlags: UInt32,
                shutterSequence: UInt32? = nil, exposureTimeMicroseconds: UInt32? = nil,
                exposureGain: UInt16? = nil, blackLevel: UInt16? = nil,
                luminance: UInt32? = nil, focusValue: Int64? = nil,
                timeCount: Int64? = nil, frameCount: UInt32? = nil,
                triggerCount: UInt32? = nil, gps: AmcamFrameGPSMetadata? = nil,
                mechanicalShutterClosed: Bool? = nil, conversionGainHigh: Bool? = nil) {
        self.apiVersion = apiVersion
        self.validityFlags = validityFlags
        self.shutterSequence = shutterSequence
        self.exposureTimeMicroseconds = exposureTimeMicroseconds
        self.exposureGain = exposureGain
        self.blackLevel = blackLevel
        self.luminance = luminance
        self.focusValue = focusValue
        self.timeCount = timeCount
        self.frameCount = frameCount
        self.triggerCount = triggerCount
        self.gps = gps
        self.mechanicalShutterClosed = mechanicalShutterClosed
        self.conversionGainHigh = conversionGainHigh
    }
}
