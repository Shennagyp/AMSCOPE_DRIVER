import Foundation
import XCTest
@testable import AmcamImagingCore

final class RGB8FrameTests: XCTestCase {
    func testDecodesPackedRGB8Frame() throws {
        let payload = Data((0..<18).map(UInt8.init))
        let frame = try RGB8Frame.decode(
            width: 3,
            height: 2,
            pixelFormat: RGB8Frame.pfncRGB8,
            pixelFormatNamespace: RGB8Frame.pfncNamespace,
            rowPaddingBytes: 0,
            sizeFilled: 18,
            dataSize: 18,
            sequence: 42,
            bytes: payload
        )

        XCTAssertEqual(frame.width, 3)
        XCTAssertEqual(frame.height, 2)
        XCTAssertEqual(frame.bytesPerRow, 9)
        XCTAssertEqual(frame.data, payload)
        XCTAssertEqual(frame.sequence, 42)
    }

    func testPreservesRowPaddingAndTrimsTrailingBufferBytes() throws {
        let payload = Data((0..<24).map(UInt8.init))
        let frame = try RGB8Frame.decode(
            width: 2,
            height: 2,
            pixelFormat: RGB8Frame.pfncRGB8,
            pixelFormatNamespace: RGB8Frame.pfncNamespace,
            rowPaddingBytes: 2,
            sizeFilled: 16,
            dataSize: 12,
            sequence: 7,
            bytes: payload
        )

        XCTAssertEqual(frame.bytesPerRow, 8)
        XCTAssertEqual(frame.data.count, 16)
        XCTAssertEqual(frame.data, Data((0..<16).map(UInt8.init)))
    }

    func testRejectsUnsupportedPixelFormat() {
        XCTAssertThrowsError(try RGB8Frame.decode(
            width: 1,
            height: 1,
            pixelFormat: 0,
            pixelFormatNamespace: RGB8Frame.pfncNamespace,
            rowPaddingBytes: 0,
            sizeFilled: 3,
            dataSize: 3,
            sequence: 1,
            bytes: Data([0, 0, 0])
        )) { error in
            XCTAssertEqual(
                error as? RGB8FrameError,
                .unsupportedPixelFormat(namespace: RGB8Frame.pfncNamespace, format: 0)
            )
        }
    }

    func testRejectsRGB8CodeInNonPFNCNamespace() {
        XCTAssertThrowsError(try RGB8Frame.decode(
            width: 1,
            height: 1,
            pixelFormat: RGB8Frame.pfncRGB8,
            pixelFormatNamespace: RGB8Frame.pfncNamespace + 1,
            rowPaddingBytes: 0,
            sizeFilled: 3,
            dataSize: 3,
            sequence: 1,
            bytes: Data([0, 0, 0])
        )) { error in
            XCTAssertEqual(
                error as? RGB8FrameError,
                .unsupportedPixelFormat(
                    namespace: RGB8Frame.pfncNamespace + 1,
                    format: RGB8Frame.pfncRGB8
                )
            )
        }
    }

    func testRejectsInvalidDimensionsAndNegativePadding() {
        for (width, height, padding) in [(0, 1, 0), (1, 0, 0), (1, 1, -1)] {
            XCTAssertThrowsError(try RGB8Frame.decode(
                width: width,
                height: height,
                pixelFormat: RGB8Frame.pfncRGB8,
                pixelFormatNamespace: RGB8Frame.pfncNamespace,
                rowPaddingBytes: padding,
                sizeFilled: 3,
                dataSize: 3,
                sequence: 1,
                bytes: Data([0, 0, 0])
            )) { error in
                XCTAssertEqual(error as? RGB8FrameError, .invalidDimensionsOrStride)
            }
        }
    }

    func testRejectsArithmeticOverflow() {
        XCTAssertThrowsError(try RGB8Frame.decode(
            width: Int.max,
            height: 1,
            pixelFormat: RGB8Frame.pfncRGB8,
            pixelFormatNamespace: RGB8Frame.pfncNamespace,
            rowPaddingBytes: 0,
            sizeFilled: Int.max,
            dataSize: Int.max,
            sequence: 1,
            bytes: Data()
        )) { error in
            XCTAssertEqual(error as? RGB8FrameError, .inconsistentPayloadMetadata)
        }
    }

    func testRejectsTruncatedPayloadAndInsufficientSizeFilled() throws {
        let base: (Int, Int, Data) throws -> Void = { sizeFilled, dataSize, bytes in
            XCTAssertThrowsError(try RGB8Frame.decode(
                width: 2,
                height: 2,
                pixelFormat: RGB8Frame.pfncRGB8,
                pixelFormatNamespace: RGB8Frame.pfncNamespace,
                rowPaddingBytes: 0,
                sizeFilled: sizeFilled,
                dataSize: dataSize,
                sequence: 1,
                bytes: bytes
            )) { error in
                XCTAssertEqual(error as? RGB8FrameError, .inconsistentPayloadMetadata)
            }
        }
        try base(11, 12, Data(repeating: 0, count: 12))
        try base(12, 11, Data(repeating: 0, count: 12))
        try base(12, 12, Data(repeating: 0, count: 11))
    }
}
