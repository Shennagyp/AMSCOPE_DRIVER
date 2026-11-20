import Foundation

/// A copied camera image payload before pixel-format-specific decoding.
/// Timestamp units are device/producer-specific unless the backend also
/// supplies a verified timestamp frequency.
public struct CameraFramePayload: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixelFormat: UInt64
    public let pixelFormatNamespace: UInt64
    public let rowPaddingBytes: Int
    public let sizeFilled: Int
    public let dataSize: Int
    public let sequence: UInt64
    public let timestamp: UInt64
    public let isIncomplete: Bool
    public let bytes: Data

    public init(
        width: Int,
        height: Int,
        pixelFormat: UInt64,
        pixelFormatNamespace: UInt64,
        rowPaddingBytes: Int,
        sizeFilled: Int,
        dataSize: Int,
        sequence: UInt64,
        timestamp: UInt64,
        isIncomplete: Bool,
        bytes: Data
    ) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.pixelFormatNamespace = pixelFormatNamespace
        self.rowPaddingBytes = rowPaddingBytes
        self.sizeFilled = sizeFilled
        self.dataSize = dataSize
        self.sequence = sequence
        self.timestamp = timestamp
        self.isIncomplete = isIncomplete
        self.bytes = bytes
    }
}
