import Foundation

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
