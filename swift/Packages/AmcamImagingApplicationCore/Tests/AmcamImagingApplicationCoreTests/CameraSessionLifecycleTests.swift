import XCTest
import AmcamImagingCore
@testable import AmcamImagingApplicationCore

private enum FakeRuntimeError: Error {
    case closeFailed
    case startFailed
}

private actor FakeAcquisition: CameraRuntimeAcquisition {
    private var iterator: AsyncStream<CameraFramePayload>.Iterator
    private let continuation: AsyncStream<CameraFramePayload>.Continuation
    private var closeFailuresRemaining: Int
    private var startFailuresRemaining: Int
    private var timeoutsRemaining: Int
    private let frameOnClose: CameraFramePayload?

    private(set) var startAttempts = 0
    private(set) var stopAttempts = 0
    private(set) var closeAttempts = 0

    init(
        closeFailures: Int = 0,
        startFailures: Int = 0,
        timeoutCount: Int = 0,
        frameOnClose: CameraFramePayload? = nil
    ) {
        let stream = AsyncStream<CameraFramePayload>.makeStream()
        iterator = stream.stream.makeAsyncIterator()
        continuation = stream.continuation
        closeFailuresRemaining = closeFailures
        startFailuresRemaining = startFailures
        timeoutsRemaining = timeoutCount
        self.frameOnClose = frameOnClose
    }

    func start() async throws {
        startAttempts += 1
        if startFailuresRemaining > 0 {
            startFailuresRemaining -= 1
            throw FakeRuntimeError.startFailed
        }
    }

    func nextFrame(timeoutMilliseconds: UInt64) async throws -> CameraFramePayload {
        if timeoutsRemaining > 0 {
            timeoutsRemaining -= 1
            throw CameraAcquisitionFailure.timeout
        }
        guard let frame = await iterator.next() else {
            throw CameraAcquisitionFailure.stopped
        }
        return frame
    }

    func stop() async throws {
        stopAttempts += 1
        continuation.finish()
    }

    func close() async throws {
        closeAttempts += 1
        if closeFailuresRemaining > 0 {
            closeFailuresRemaining -= 1
            throw FakeRuntimeError.closeFailed
        }
        if let frameOnClose {
            continuation.yield(frameOnClose)
        }
        continuation.finish()
    }

    func emit(_ frame: CameraFramePayload) {
        continuation.yield(frame)
    }
}

private actor FakeSession: CameraRuntimeSession {
    private let acquisition: FakeAcquisition
    private var closeFailuresRemaining: Int

    private(set) var acquisitionRequests = 0
    private(set) var closeAttempts = 0

    init(acquisition: FakeAcquisition, closeFailures: Int = 0) {
        self.acquisition = acquisition
        closeFailuresRemaining = closeFailures
    }

    func makeAcquisition() async throws -> any CameraRuntimeAcquisition {
        acquisitionRequests += 1
        return acquisition
    }

    func close() async throws {
        closeAttempts += 1
        if closeFailuresRemaining > 0 {
            closeFailuresRemaining -= 1
            throw FakeRuntimeError.closeFailed
        }
    }
}

final class CameraSessionLifecycleTests: XCTestCase {
    private func makeFrame(sequence: UInt64 = 1) -> CameraFramePayload {
        CameraFramePayload(
            width: 1,
            height: 1,
            pixelFormat: 0x02180014,
            pixelFormatNamespace: 4,
            rowPaddingBytes: 0,
            sizeFilled: 3,
            dataSize: 3,
            sequence: sequence,
            timestamp: sequence,
            isIncomplete: false,
            bytes: Data([1, 2, 3])
        )
    }

    func testAcquisitionCloseFailureRetainsParentAndAllowsRetry() async throws {
        let acquisition = FakeAcquisition(closeFailures: 1)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.attach(session)
        try await lifecycle.start()

        do {
            try await lifecycle.close()
            XCTFail("Expected the first acquisition close to fail.")
        } catch {}

        let firstSnapshot = await lifecycle.snapshot()
        let firstAcquisitionCloses = await acquisition.closeAttempts
        let firstSessionCloses = await session.closeAttempts
        XCTAssertTrue(firstSnapshot.hasSession)
        XCTAssertTrue(firstSnapshot.hasAcquisition)
        XCTAssertFalse(firstSnapshot.isStreaming)
        XCTAssertEqual(firstAcquisitionCloses, 1)
        XCTAssertEqual(firstSessionCloses, 0, "The parent must remain open while its child close fails.")

        try await lifecycle.close()

        let finalSnapshot = await lifecycle.snapshot()
        let finalAcquisitionCloses = await acquisition.closeAttempts
        let finalSessionCloses = await session.closeAttempts
        XCTAssertFalse(finalSnapshot.hasSession)
        XCTAssertFalse(finalSnapshot.hasAcquisition)
        XCTAssertEqual(finalAcquisitionCloses, 2)
        XCTAssertEqual(finalSessionCloses, 1)
    }

    func testDeviceCloseFailureRetainsOnlyParentForRetry() async throws {
        let acquisition = FakeAcquisition()
        let session = FakeSession(acquisition: acquisition, closeFailures: 1)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.attach(session)
        try await lifecycle.start()

        do {
            try await lifecycle.close()
            XCTFail("Expected the first device close to fail.")
        } catch {}

        let firstSnapshot = await lifecycle.snapshot()
        let firstAcquisitionCloses = await acquisition.closeAttempts
        let firstSessionCloses = await session.closeAttempts
        XCTAssertTrue(firstSnapshot.hasSession)
        XCTAssertFalse(firstSnapshot.hasAcquisition)
        XCTAssertEqual(firstAcquisitionCloses, 1)

        try await lifecycle.close()

        let finalSnapshot = await lifecycle.snapshot()
        let finalAcquisitionCloses = await acquisition.closeAttempts
        let finalSessionCloses = await session.closeAttempts
        XCTAssertFalse(finalSnapshot.hasSession)
        XCTAssertEqual(finalAcquisitionCloses, 1, "A successfully closed child must not be closed twice.")
        XCTAssertEqual(finalSessionCloses, 2)
    }

    func testFramesAreDeliveredAndStopClosesCaptureLoop() async throws {
        let acquisition = FakeAcquisition()
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()
        let events = await lifecycle.events()
        var iterator = events.makeAsyncIterator()

        try await lifecycle.attach(session)
        try await lifecycle.start()
        await acquisition.emit(makeFrame(sequence: 42))

        var receivedFrame: CameraFramePayload?
        while let event = await iterator.next() {
            if case .frame(let frame) = event {
                receivedFrame = frame
                break
            }
        }

        XCTAssertEqual(receivedFrame?.sequence, 42)
        try await lifecycle.stop()

        let snapshot = await lifecycle.snapshot()
        let stopAttempts = await acquisition.stopAttempts
        XCTAssertFalse(snapshot.isStreaming)
        XCTAssertTrue(snapshot.hasSession)
        XCTAssertTrue(snapshot.hasAcquisition)
        XCTAssertEqual(stopAttempts, 1)
    }

    func testFrameArrivingDuringCloseIsRejectedByGenerationGuard() async throws {
        let frame = makeFrame(sequence: 99)
        let acquisition = FakeAcquisition(frameOnClose: frame)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()
        let events = await lifecycle.events()
        var iterator = events.makeAsyncIterator()

        try await lifecycle.attach(session)
        try await lifecycle.start()
        try await lifecycle.close()

        var receivedFrame = false
        var receivedClosed = false
        while let event = await iterator.next() {
            switch event {
            case .frame:
                receivedFrame = true
            case .closed:
                receivedClosed = true
            default:
                break
            }
            if receivedClosed { break }
        }

        XCTAssertFalse(receivedFrame, "A frame from an invalidated acquisition generation must not reach the UI.")
        XCTAssertTrue(receivedClosed)
    }


    func testStartFailureClosesPartiallyCreatedAcquisition() async throws {
        let acquisition = FakeAcquisition(startFailures: 1)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.attach(session)
        do {
            try await lifecycle.start()
            XCTFail("Expected the injected acquisition start failure.")
        } catch {}

        let snapshot = await lifecycle.snapshot()
        let acquisitionCloseAttempts = await acquisition.closeAttempts
        XCTAssertTrue(snapshot.hasSession)
        XCTAssertFalse(snapshot.hasAcquisition)
        XCTAssertFalse(snapshot.isStreaming)
        XCTAssertEqual(acquisitionCloseAttempts, 1)

        try await lifecycle.close()
        let sessionCloseAttempts = await session.closeAttempts
        XCTAssertEqual(sessionCloseAttempts, 1)
    }

    func testEventTimeoutDoesNotTerminateCaptureLoop() async throws {
        let acquisition = FakeAcquisition(timeoutCount: 1)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()
        let events = await lifecycle.events()
        var iterator = events.makeAsyncIterator()

        try await lifecycle.attach(session)
        try await lifecycle.start()
        await acquisition.emit(makeFrame(sequence: 73))

        var receivedFrame: CameraFramePayload?
        while let event = await iterator.next() {
            if case .frame(let frame) = event {
                receivedFrame = frame
                break
            }
        }

        XCTAssertEqual(receivedFrame?.sequence, 73)
        let snapshot = await lifecycle.snapshot()
        XCTAssertTrue(snapshot.isStreaming)
        try await lifecycle.stop()
        try await lifecycle.close()
    }

    func testStartRequiresAnAttachedSession() async {
        let lifecycle = CameraSessionLifecycle()
        do {
            try await lifecycle.start()
            XCTFail("Expected a missing-session error.")
        } catch {
            XCTAssertEqual(error as? CameraSessionLifecycleError, .sessionNotAttached)
        }
    }
}
