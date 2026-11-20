import XCTest
import GenTLRouter
@testable import AmcamImagingGenTLAdapter

final class GenTLRuntimeAdapterTests: XCTestCase {
    func testTimeoutMapsToRecoverableTimeout() {
        XCTAssertEqual(
            GenTLRuntimeAcquisition.map(.eventTimeout),
            .timeout
        )
    }

    func testStoppedAcquisitionMapsToNormalTermination() {
        XCTAssertEqual(
            GenTLRuntimeAcquisition.map(.acquisitionStopped),
            .stopped
        )
        XCTAssertEqual(
            GenTLRuntimeAcquisition.map(.sessionClosed),
            .stopped
        )
    }

    func testUnexpectedGenTLErrorMapsToFailure() {
        let error = GenTLAcquisitionError.noDataStream
        XCTAssertEqual(
            GenTLRuntimeAcquisition.map(error),
            .failed(error.localizedDescription)
        )
    }
}
