import Foundation

/// Byte layout for 24-bit RGB output. V2's default pitch is DWORD aligned;
/// row-pitch-aware V2/V3/V4 calls can request tightly packed rows.
struct AmcamRGB24Layout: Equatable, Sendable {
    let bytesPerRow: Int
    let rowPaddingBytes: Int
    let payloadSize: Int

    init?(width: Int, height: Int, tightlyPackedRows: Bool = false) {
        guard width > 0, height > 0 else { return nil }

        let (packedRowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 3)
        guard !rowOverflow else { return nil }

        let rowBytes: Int
        if tightlyPackedRows {
            rowBytes = packedRowBytes
        } else {
            let (roundedRowBytes, paddingOverflow) = packedRowBytes.addingReportingOverflow(3)
            guard !paddingOverflow else { return nil }
            rowBytes = roundedRowBytes & ~3
        }

        let (totalBytes, payloadOverflow) =
            rowBytes.multipliedReportingOverflow(by: height)
        guard !payloadOverflow, totalBytes > 0 else { return nil }

        self.bytesPerRow = rowBytes
        self.rowPaddingBytes = rowBytes - packedRowBytes
        self.payloadSize = totalBytes
    }
}
