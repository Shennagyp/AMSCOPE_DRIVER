import XCTest
@testable import AmcamGenTL

final class AmcamRGB24LayoutTests: XCTestCase {
    func testRowsUseTheSDKDefaultDWORDAlignment() throws {
        let cases: [(width: Int, height: Int, rowBytes: Int, rowPadding: Int, payloadBytes: Int)] = [
            (1, 3, 4, 1, 12),
            (2, 3, 8, 2, 24),
            (3, 3, 12, 3, 36),
            (4, 3, 12, 0, 36),
            (5, 2, 16, 1, 32)
        ]

        for testCase in cases {
            let layout = try XCTUnwrap(
                AmcamRGB24Layout(width: testCase.width, height: testCase.height)
            )
            XCTAssertEqual(layout.bytesPerRow, testCase.rowBytes)
            XCTAssertEqual(layout.rowPaddingBytes, testCase.rowPadding)
            XCTAssertEqual(layout.payloadSize, testCase.payloadBytes)
        }
    }

    func testRejectsInvalidOrOverflowingDimensions() {
        XCTAssertNil(AmcamRGB24Layout(width: 0, height: 1))
        XCTAssertNil(AmcamRGB24Layout(width: 1, height: 0))
        XCTAssertNil(AmcamRGB24Layout(width: -1, height: 1))
        XCTAssertNil(AmcamRGB24Layout(width: Int.max, height: 1))
        XCTAssertNil(AmcamRGB24Layout(width: 1, height: Int.max))
    }

    func testPayloadSizeIncludesEveryAlignedRow() throws {
        let layout = try XCTUnwrap(AmcamRGB24Layout(width: 641, height: 2))
        XCTAssertEqual(layout.bytesPerRow, 1_924)
        XCTAssertEqual(layout.rowPaddingBytes, 1)
        XCTAssertEqual(layout.payloadSize, 3_848)
        XCTAssertEqual(layout.bytesPerRow % 4, 0)
    }
}
