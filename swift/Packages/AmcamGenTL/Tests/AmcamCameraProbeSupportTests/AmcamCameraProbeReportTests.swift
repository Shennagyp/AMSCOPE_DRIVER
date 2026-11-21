import Foundation
import XCTest
@testable import AmcamCameraProbeSupport

final class AmcamCameraProbeReportTests: XCTestCase {
    func testReportEncodesVersionedSnakeCaseJSONAndRoundTrips() throws {
        var report = AmcamCameraProbeReport()
        report.status = .failure
        report.sdk = AmcamProbeSDKInfo(
            path: "/vendor/libamcam.dylib",
            version: "fixture-sdk-1"
        )
        report.interfaceIdentifier = "USB"
        report.device = AmcamProbeDeviceInfo(
            index: 0,
            identifier: "MU503-001",
            modelName: "MU503",
            displayName: "AmScope MU503",
            discoveredCount: 1
        )
        report.stream = AmcamProbeStreamInfo(
            identifier: "stream-0",
            payloadSize: 921600,
            announcedBufferCount: 4
        )
        report.image = AmcamProbeImageInfo(
            width: 640,
            height: 480,
            pixelFormatCode: 0x02180014,
            pixelFormatNamespace: 4,
            bytesPerRow: 1920,
            rowPaddingBytes: 0,
            sizeFilled: 921600,
            dataSize: 921600
        )
        report.acquisition = AmcamProbeAcquisitionInfo(
            requestedFrameCount: 20,
            completeFrameCount: 7,
            incompleteFrameCount: 0,
            elapsedSeconds: 1.25,
            hostLoopFramesPerSecond: 5.6,
            firstSequence: 10,
            lastSequence: 16,
            lastFrameSHA256: "abc123"
        )
        report.failure = AmcamProbeFailure(
            stage: .frameRead,
            message: "Timed out waiting for a frame."
        )
        report.cleanupErrors = ["DSClose: resource busy"]

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["backend"] as? String, "AmcamGenTL")
        XCTAssertEqual(object["status"] as? String, "failure")
        let sdk = try XCTUnwrap(object["sdk"] as? [String: Any])
        XCTAssertEqual(sdk["version"] as? String, "fixture-sdk-1")
        let device = try XCTUnwrap(object["device"] as? [String: Any])
        XCTAssertEqual(device["model_name"] as? String, "MU503")
        let image = try XCTUnwrap(object["image"] as? [String: Any])
        XCTAssertEqual(image["pixel_format_code"] as? UInt64, 0x02180014)
        XCTAssertEqual(image["bytes_per_row"] as? Int, 1920)
        let failure = try XCTUnwrap(object["failure"] as? [String: Any])
        XCTAssertEqual(failure["stage"] as? String, "frame-read")
        XCTAssertEqual(
            object["cleanup_errors"] as? [String],
            ["DSClose: resource busy"]
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertEqual(try decoder.decode(AmcamCameraProbeReport.self, from: data), report)
    }

    func testSuccessfulReportHasNoFailureAndCanRepresentPartialDiscovery() throws {
        var report = AmcamCameraProbeReport()
        report.sdk = AmcamProbeSDKInfo(path: "/vendor/libamcam.dylib")
        report.device = AmcamProbeDeviceInfo(discoveredCount: 0)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(report)) as? [String: Any]
        )

        XCTAssertEqual(object["status"] as? String, "success")
        XCTAssertNil(object["failure"])
        let device = try XCTUnwrap(object["device"] as? [String: Any])
        XCTAssertEqual(device["discovered_count"] as? Int, 0)
    }
}
