import XCTest
@testable import AmcamImagingCore

final class PixelFormatRegistryTests: XCTestCase {
    func testStandardPFNCRegistryRecognizesOnlyTheExactRGB8Identity() {
        let rgb8 = PixelFormatIdentifier.pfncRGB8

        let descriptor = PixelFormatRegistry.pfnc.descriptor(for: rgb8)
        XCTAssertEqual(descriptor?.name, "RGB8")
        XCTAssertEqual(descriptor?.decoder, .rgb8)

        XCTAssertNil(
            PixelFormatRegistry.pfnc.descriptor(
                for: PixelFormatIdentifier(namespace: rgb8.namespace, code: 0)
            )
        )
        XCTAssertNil(
            PixelFormatRegistry.pfnc.descriptor(
                for: PixelFormatIdentifier(namespace: rgb8.namespace + 1, code: rgb8.code)
            )
        )
    }

    func testDecodableFormatsRequireAnExactRegisteredPFNCIdentity() {
        let rgb8 = PixelFormatIdentifier.pfncRGB8
        let unknownCode = PixelFormatIdentifier(namespace: rgb8.namespace, code: 0x01080001)
        let wrongNamespace = PixelFormatIdentifier(namespace: 1, code: rgb8.code)

        let decodable = PixelFormatRegistry.pfnc.decodableFormats(
            advertised: [unknownCode, rgb8, wrongNamespace, rgb8]
        )

        XCTAssertEqual(decodable.map(\.identifier), [rgb8])
    }

    func testRegistryRejectsDuplicateFormatIdentities() {
        let descriptor = PixelFormatDescriptor(
            identifier: .pfncRGB8,
            name: "RGB8",
            decoder: .rgb8
        )

        XCTAssertThrowsError(
            try PixelFormatRegistry(descriptors: [descriptor, descriptor])
        ) { error in
            XCTAssertEqual(
                error as? PixelFormatRegistryError,
                .duplicateIdentifier(.pfncRGB8)
            )
        }
    }

    func testRegistryRejectsEmptyFormatNames() {
        let descriptor = PixelFormatDescriptor(
            identifier: .pfncRGB8,
            name: "  ",
            decoder: .rgb8
        )

        XCTAssertThrowsError(
            try PixelFormatRegistry(descriptors: [descriptor])
        ) { error in
            XCTAssertEqual(
                error as? PixelFormatRegistryError,
                .emptyName
            )
        }
    }
}
