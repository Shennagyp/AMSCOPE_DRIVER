import Foundation

/// Byte layout for RGB24 output.
///
/// Plain PullImageV2 uses DWORD-aligned rows. Row-pitch-aware V2/V3/V4 calls
/// can request tightly packed rows. The stream accepts only those two layouts.
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

        self.init(width: width, height: height, bytesPerRow: rowBytes)
    }

    /// Validates a row stride returned by the active SDK pull API.
    init?(width: Int, height: Int, bytesPerRow: Int) {
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        let (packedRowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 3)
        guard !rowOverflow else { return nil }

        let (roundedRowBytes, paddingOverflow) = packedRowBytes.addingReportingOverflow(3)
        guard !paddingOverflow else { return nil }
        let dwordAlignedRowBytes = roundedRowBytes & ~3

        guard bytesPerRow == packedRowBytes || bytesPerRow == dwordAlignedRowBytes else {
            return nil
        }

        let (totalBytes, payloadOverflow) =
            bytesPerRow.multipliedReportingOverflow(by: height)
        guard !payloadOverflow, totalBytes > 0 else { return nil }

        self.bytesPerRow = bytesPerRow
        self.rowPaddingBytes = bytesPerRow - packedRowBytes
        self.payloadSize = totalBytes
    }
}
