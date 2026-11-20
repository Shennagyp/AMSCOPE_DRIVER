import Foundation

/// A validated, tightly described RGB8 frame suitable for presentation by any UI.
public struct RGB8Frame: Equatable, Sendable {
    public static let pfncNamespace: UInt64 = 4
    public static let pfncRGB8: UInt64 = 0x02180014

    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let data: Data
    public let sequence: UInt64

    public init(
        width: Int,
        height: Int,
        bytesPerRow: Int,
        data: Data,
        sequence: UInt64
    ) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.data = data
        self.sequence = sequence
    }

    /// Validates GenTL frame metadata and copies only the described RGB8 image payload.
    public static func decode(
        width: Int,
        height: Int,
        pixelFormat: UInt64,
        pixelFormatNamespace: UInt64,
        rowPaddingBytes: Int,
        sizeFilled: Int,
        dataSize: Int,
        sequence: UInt64,
        bytes: Data
    ) throws -> RGB8Frame {
        guard pixelFormatNamespace == pfncNamespace, pixelFormat == pfncRGB8 else {
            throw RGB8FrameError.unsupportedPixelFormat(
                namespace: pixelFormatNamespace,
                format: pixelFormat
            )
        }

        guard width > 0, height > 0, rowPaddingBytes >= 0 else {
            throw RGB8FrameError.invalidDimensionsOrStride
        }

        let (packedRowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 3)
        let (bytesPerRow, paddingOverflow) = packedRowBytes.addingReportingOverflow(rowPaddingBytes)
        let (requiredBytes, heightOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        let (packedDataSize, packedSizeOverflow) = packedRowBytes.multipliedReportingOverflow(by: height)

        guard !rowOverflow, !paddingOverflow, !heightOverflow, !packedSizeOverflow,
              dataSize >= packedDataSize,
              sizeFilled >= requiredBytes,
              bytes.count >= requiredBytes else {
            throw RGB8FrameError.inconsistentPayloadMetadata
        }

        return RGB8Frame(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            data: Data(bytes.prefix(requiredBytes)),
            sequence: sequence
        )
    }
}

public enum RGB8FrameError: Error, Equatable, Sendable {
    case unsupportedPixelFormat(namespace: UInt64, format: UInt64)
    case invalidDimensionsOrStride
    case inconsistentPayloadMetadata
}
