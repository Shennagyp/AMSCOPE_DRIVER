import XCTest
@testable import AmcamGenTL

final class AmcamRGB24LayoutTests: XCTestCase {
    func testRowsUseTheSDKDefaultDWORDAlignment() {
        XCTAssertEqual(AmcamRGB24Layout(width: 1, height: 3), .init(bytesPerRow: 4, payloadSize: 12))
        XCTAssertEqual(AmcamRGB24Layout(width: 2, height: 3), .init(bytesPerRow: 8, payloadSize: 24))
        XCTAssertEqual(AmcamRGB24Layout(width: 3, height: 3), .init(bytesPerRow: 12, payloadSize: 36))
        XCTAssertEqual(AmcamRGB24Layout(width: 4, height: 3), .init(bytesPerRow: 12, payloadSize: 36))
        XCTAssertEqual(AmcamRGB24Layout(width: 5, height: 2), .init(bytesPerRow: 16, payloadSize: 32))
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
        XCTAssertEqual(layout.payloadSize, 3_848)
        XCTAssertEqual(layout.bytesPerRow % 4, 0)
    }
}
