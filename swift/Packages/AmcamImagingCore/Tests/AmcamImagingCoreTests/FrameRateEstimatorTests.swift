import XCTest
@testable import AmcamImagingCore

final class FrameRateEstimatorTests: XCTestCase {
    func testRequiresTwoTimestampsAndEstimatesFramesPerSecond() {
        var estimator = FrameRateEstimator()
        XCTAssertNil(estimator.record(timestamp: 10))
        XCTAssertEqual(estimator.record(timestamp: 10.04)!, 25, accuracy: 0.0001)
        XCTAssertEqual(estimator.record(timestamp: 10.08)!, 25, accuracy: 0.0001)
    }

    func testIgnoresNonIncreasingAndNonFiniteTimestamps() {
        var estimator = FrameRateEstimator()
        XCTAssertNil(estimator.record(timestamp: 1))
        XCTAssertNil(estimator.record(timestamp: 1))
        XCTAssertNil(estimator.record(timestamp: .nan))
        XCTAssertEqual(estimator.record(timestamp: 1.5)!, 2, accuracy: 0.0001)
        XCTAssertEqual(estimator.record(timestamp: 2)!, 2, accuracy: 0.0001)
    }

    func testBoundsMovingAverageWindow() {
        var estimator = FrameRateEstimator(sampleWindow: 2)
        _ = estimator.record(timestamp: 0)
        _ = estimator.record(timestamp: 1)
        _ = estimator.record(timestamp: 2)
        XCTAssertEqual(estimator.record(timestamp: 2.5)!, 1.0 / 0.75, accuracy: 0.0001)
    }

    func testResetClearsBaselineAndSamples() {
        var estimator = FrameRateEstimator()
        _ = estimator.record(timestamp: 5)
        _ = estimator.record(timestamp: 5.5)
        estimator.reset()
        XCTAssertNil(estimator.record(timestamp: 100))
        XCTAssertEqual(estimator.record(timestamp: 100.25)!, 4, accuracy: 0.0001)
    }

    func testZeroSampleWindowIsNormalizedToOne() {
        var estimator = FrameRateEstimator(sampleWindow: 0)
        XCTAssertEqual(estimator.sampleWindow, 1)
        _ = estimator.record(timestamp: 0)
        XCTAssertEqual(estimator.record(timestamp: 1)!, 1, accuracy: 0.0001)
        XCTAssertEqual(estimator.record(timestamp: 3)!, 0.5, accuracy: 0.0001)
    }
}
