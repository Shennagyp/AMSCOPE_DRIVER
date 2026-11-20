import XCTest
import GenTLABI
@testable import GenTLAPI

final class GenTLFeatureAccessContractTests: XCTestCase {
    func testFeatureValueReportsItsSemanticKind() {
        XCTAssertEqual(GenTLFeatureValue.boolean(true).kind, .boolean)
        XCTAssertEqual(GenTLFeatureValue.integer(12).kind, .integer)
        XCTAssertEqual(GenTLFeatureValue.floatingPoint(1.25).kind, .floatingPoint)
        XCTAssertEqual(GenTLFeatureValue.string("camera").kind, .string)
        XCTAssertEqual(GenTLFeatureValue.enumeration("Continuous").kind, .enumeration)
    }

    func testNumericRangeRejectsInvalidBoundsAndIncrement() {
        XCTAssertNotNil(GenTLFeatureNumericRange(minimum: 1, maximum: 10))
        XCTAssertNotNil(GenTLFeatureNumericRange(minimum: 1, maximum: 10, increment: 0.5))
        XCTAssertNil(GenTLFeatureNumericRange(minimum: 10, maximum: 1))
        XCTAssertNil(GenTLFeatureNumericRange(minimum: .infinity, maximum: 10))
        XCTAssertNil(GenTLFeatureNumericRange(minimum: 1, maximum: .nan))
        XCTAssertNil(GenTLFeatureNumericRange(minimum: 1, maximum: 10, increment: 0))
        XCTAssertNil(GenTLFeatureNumericRange(minimum: 1, maximum: 10, increment: -.infinity))
    }

    func testDescriptorPreservesAccessAndModelAvailability() {
        let descriptor = GenTLFeatureDescriptor(
            name: "ExposureTime",
            displayName: "Exposure Time",
            kind: .floatingPoint,
            unit: "us",
            isAvailable: true,
            isReadable: true,
            isWritable: false,
            numericRange: GenTLFeatureNumericRange(minimum: 10, maximum: 1_000_000)
        )

        XCTAssertEqual(descriptor.id, "ExposureTime")
        XCTAssertEqual(descriptor.kind, .floatingPoint)
        XCTAssertEqual(descriptor.unit, "us")
        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertTrue(descriptor.isReadable)
        XCTAssertFalse(descriptor.isWritable)
        XCTAssertEqual(descriptor.numericRange?.minimum, 10)
        XCTAssertEqual(descriptor.numericRange?.maximum, 1_000_000)
    }

    func testVendorFeatureCanBeRepresentedWithoutClaimingSFNCSemantics() {
        let descriptor = GenTLFeatureDescriptor(
            name: "AmcamAnalogGainPercent",
            displayName: "Analog Gain",
            kind: .integer,
            unit: "%",
            isAvailable: true,
            isReadable: true,
            isWritable: true,
            numericRange: GenTLFeatureNumericRange(minimum: 100, maximum: 1_000)
        )

        XCTAssertEqual(descriptor.name, "AmcamAnalogGainPercent")
        XCTAssertEqual(descriptor.unit, "%")
    }
}
