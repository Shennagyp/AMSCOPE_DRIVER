import XCTest
@testable import AmcamImagingRuntime

private actor FeaturelessRuntimeSession: CameraRuntimeSession {
    func makeAcquisition() async throws -> any CameraRuntimeAcquisition {
        throw CameraFeatureAccessError.unsupported
    }
    func close() async throws {}
}

final class CameraFeatureContractTests: XCTestCase {
    func testFeatureValueReportsItsSemanticKind() {
        XCTAssertEqual(CameraFeatureValue.boolean(true).kind, .boolean)
        XCTAssertEqual(CameraFeatureValue.integer(12).kind, .integer)
        XCTAssertEqual(CameraFeatureValue.integerVector([1, 2, 3]).kind, .integerVector)
        XCTAssertEqual(CameraFeatureValue.floatingPoint(1.5).kind, .floatingPoint)
        XCTAssertEqual(CameraFeatureValue.string("mode").kind, .string)
        XCTAssertEqual(CameraFeatureValue.enumeration("Continuous").kind, .enumeration)
    }

    func testNumericRangeRejectsInvalidBoundsAndIncrement() {
        XCTAssertNil(CameraFeatureNumericRange(minimum: 2, maximum: 1))
        XCTAssertNil(CameraFeatureNumericRange(minimum: 0, maximum: 10, increment: 0))
        XCTAssertNil(CameraFeatureNumericRange(minimum: 0, maximum: .infinity))
        XCTAssertNotNil(CameraFeatureNumericRange(minimum: 0, maximum: 10, increment: 0.5))
    }

    func testDescriptorPreservesFeatureAccessMetadata() {
        let descriptor = CameraFeatureDescriptor(
            name: "ExposureTime",
            displayName: "Exposure Time",
            kind: .integer,
            unit: "us",
            isAvailable: true,
            isReadable: true,
            isWritable: false,
            numericRange: CameraFeatureNumericRange(minimum: 10, maximum: 100_000, increment: 1)
        )
        XCTAssertEqual(descriptor.id, "ExposureTime")
        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertTrue(descriptor.isReadable)
        XCTAssertFalse(descriptor.isWritable)
        XCTAssertEqual(descriptor.unit, "us")
        XCTAssertEqual(descriptor.numericRange?.maximum, 100_000)
    }
    func testFeatureAccessErrorsRemainBackendNeutral() {
        XCTAssertEqual(
            CameraFeatureAccessError.featureNotWritable("ExposureTime").errorDescription,
            "Camera feature 'ExposureTime' is not writable."
        )
        XCTAssertEqual(
            CameraFeatureAccessError.valueTypeMismatch(feature: "Gain", expected: .integer, actual: .string).errorDescription,
            "Camera feature 'Gain' expects integer, received string."
        )
    }
    func testFeaturelessBackendUsesExplicitUnsupportedContract() async {
        let session = FeaturelessRuntimeSession()
        XCTAssertFalse(await session.supportsAcquisition())

        do {
            _ = try await session.featureDescriptors()
            XCTFail("A backend without feature access must not return fabricated descriptors.")
        } catch {
            XCTAssertEqual(error as? CameraFeatureAccessError, .unsupported)
        }
    }
}
