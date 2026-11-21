import Foundation
import XCTest
import AmcamImagingCore
@testable import AmcamImagingRuntime

private actor AsyncGate {
    private var isEntered = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        isEntered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !isEntered else { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private enum FakeRuntimeError: Error {
    case closeFailed
    case startFailed
}

/// A single-consumer stream fake. The coordinator guarantees one capture reader;
/// NSLock protects control counters while AsyncStream handles frame delivery.
private final class FakeAcquisition: CameraRuntimeAcquisition, @unchecked Sendable {
    private let lock = NSLock()
    private var iterator: AsyncStream<CameraFramePayload>.Iterator
    private let continuation: AsyncStream<CameraFramePayload>.Continuation
    private var closeFailuresRemaining: Int
    private var startFailuresRemaining: Int
    private var timeoutsRemaining: Int
    private var readFailureMessage: String?
    private var stoppedReadCount: Int
    private let frameOnClose: CameraFramePayload?
    private let closeGate: AsyncGate?

    private var startAttemptsValue = 0
    private var stopAttemptsValue = 0
    private var closeAttemptsValue = 0

    var startAttempts: Int {
        lock.lock()
        defer { lock.unlock() }
        return startAttemptsValue
    }

    var stopAttempts: Int {
        lock.lock()
        defer { lock.unlock() }
        return stopAttemptsValue
    }

    var closeAttempts: Int {
        lock.lock()
        defer { lock.unlock() }
        return closeAttemptsValue
    }

    init(
        closeFailures: Int = 0,
        startFailures: Int = 0,
        timeoutCount: Int = 0,
        readFailureMessage: String? = nil,
        stoppedReadCount: Int = 0,
        frameOnClose: CameraFramePayload? = nil,
        closeGate: AsyncGate? = nil
    ) {
        let stream = AsyncStream<CameraFramePayload>.makeStream()
        iterator = stream.stream.makeAsyncIterator()
        continuation = stream.continuation
        closeFailuresRemaining = closeFailures
        startFailuresRemaining = startFailures
        timeoutsRemaining = timeoutCount
        self.readFailureMessage = readFailureMessage
        self.stoppedReadCount = stoppedReadCount
        self.frameOnClose = frameOnClose
        self.closeGate = closeGate
    }

    func start() async throws {
        if recordStartAttemptAndShouldFail() {
            throw FakeRuntimeError.startFailed
        }
    }

    func nextFrame(timeoutMilliseconds: UInt64) async throws -> CameraFramePayload {
        if consumeUnexpectedStop() {
            throw CameraAcquisitionFailure.stopped
        }
        if let message = consumeReadFailure() {
            throw CameraAcquisitionFailure.failed(message)
        }
        if consumeTimeout() {
            throw CameraAcquisitionFailure.timeout
        }

        guard let frame = await iterator.next() else {
            throw CameraAcquisitionFailure.stopped
        }
        return frame
    }

    func stop() async throws {
        recordStopAttempt()
        continuation.finish()
    }

    func close() async throws {
        let shouldFail = recordCloseAttemptAndShouldFail()
        if let closeGate { await closeGate.pause() }
        if shouldFail {
            throw FakeRuntimeError.closeFailed
        }
        if let frameOnClose { continuation.yield(frameOnClose) }
        continuation.finish()
    }

    func emit(_ frame: CameraFramePayload) {
        continuation.yield(frame)
    }

    private func recordStartAttemptAndShouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        startAttemptsValue += 1
        let shouldFail = startFailuresRemaining > 0
        if shouldFail { startFailuresRemaining -= 1 }
        return shouldFail
    }

    private func consumeUnexpectedStop() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard stoppedReadCount > 0 else { return false }
        stoppedReadCount -= 1
        return true
    }

    private func consumeReadFailure() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let message = readFailureMessage
        readFailureMessage = nil
        return message
    }

    private func consumeTimeout() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let shouldTimeout = timeoutsRemaining > 0
        if shouldTimeout { timeoutsRemaining -= 1 }
        return shouldTimeout
    }

    private func recordStopAttempt() {
        lock.lock()
        defer { lock.unlock() }
        stopAttemptsValue += 1
    }

    private func recordCloseAttemptAndShouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        closeAttemptsValue += 1
        let shouldFail = closeFailuresRemaining > 0
        if shouldFail { closeFailuresRemaining -= 1 }
        return shouldFail
    }
}

private actor FakeDevice: CameraRuntimeDevice {
    private let session: FakeSession
    private(set) var openAttempts = 0

    init(session: FakeSession) {
        self.session = session
    }

    func open() async throws -> any CameraRuntimeSession {
        openAttempts += 1
        return session
    }
}

private actor FakeSession: CameraRuntimeSession {
    private let acquisitions: [FakeAcquisition]
    private var closeFailuresRemaining: Int
    private let featureReadGate: AsyncGate?

    private(set) var acquisitionRequests = 0
    private(set) var closeAttempts = 0

    init(
        acquisition: FakeAcquisition,
        additionalAcquisitions: [FakeAcquisition] = [],
        closeFailures: Int = 0,
        featureReadGate: AsyncGate? = nil
    ) {
        acquisitions = [acquisition] + additionalAcquisitions
        closeFailuresRemaining = closeFailures
        self.featureReadGate = featureReadGate
    }

    func supportsAcquisition() async -> Bool { true }

    func featureDescriptors() async throws -> [CameraFeatureDescriptor] { [] }

    func readFeature(_ name: String) async throws -> CameraFeatureValue {
        if let featureReadGate { await featureReadGate.pause() }
        return .integer(7)
    }

    func writeFeature(_ value: CameraFeatureValue, named name: String) async throws {}

    func makeAcquisition() async throws -> any CameraRuntimeAcquisition {
        let index = min(acquisitionRequests, acquisitions.count - 1)
        acquisitionRequests += 1
        return acquisitions[index]
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

    func testLibraryOpensAndOwnsDeviceSession() async throws {
        let acquisition = FakeAcquisition()
        let session = FakeSession(acquisition: acquisition)
        let device = FakeDevice(session: session)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.open(device)
        let snapshot = await lifecycle.snapshot()
        let openAttempts = await device.openAttempts

        XCTAssertTrue(snapshot.hasSession)
        XCTAssertEqual(openAttempts, 1)

        try await lifecycle.close()
        let finalSnapshot = await lifecycle.snapshot()
        XCTAssertFalse(finalSnapshot.hasSession)
    }



    func testOpeningSameIdentifiedDeviceIsIdempotent() async throws {
        let acquisition = FakeAcquisition()
        let session = FakeSession(acquisition: acquisition)
        let device = FakeDevice(session: session)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.open(device, identifier: "camera-1")
        try await lifecycle.open(device, identifier: "camera-1")

        let openAttempts = await device.openAttempts
        let snapshot = await lifecycle.snapshot()
        XCTAssertEqual(openAttempts, 1)
        XCTAssertTrue(snapshot.hasSession)

        do {
            try await lifecycle.open(device, identifier: "camera-2")
            XCTFail("A different camera identity must not replace an attached session.")
        } catch {
            XCTAssertEqual(error as? CameraSessionLifecycleError, .sessionAlreadyAttached)
        }

        try await lifecycle.close()
    }

    func testFeatureIOIsOwnedAndSerializedAgainstClose() async throws {
        let featureGate = AsyncGate()
        let acquisition = FakeAcquisition()
        let session = FakeSession(acquisition: acquisition, featureReadGate: featureGate)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.open(FakeDevice(session: session))
        let featureRead = Task {
            try await lifecycle.readFeature("ExposureTime")
        }
        await featureGate.waitUntilEntered()

        let closeTask = Task {
            try await lifecycle.close()
        }
        await Task.yield()

        let snapshotWhileReadIsBlocked = await lifecycle.snapshot()
        XCTAssertTrue(snapshotWhileReadIsBlocked.hasSession)

        await featureGate.release()
        let value = try await featureRead.value
        XCTAssertEqual(value, .integer(7))
        try await closeTask.value

        let closedSnapshot = await lifecycle.snapshot()
        XCTAssertFalse(closedSnapshot.hasSession)
    }

    func testAcquisitionCloseFailureRetainsParentAndAllowsRetry() async throws {
        let acquisition = FakeAcquisition(closeFailures: 1)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()

        do {
            try await lifecycle.close()
            XCTFail("Expected the first acquisition close to fail.")
        } catch {}

        let firstSnapshot = await lifecycle.snapshot()
        let firstAcquisitionCloses = acquisition.closeAttempts
        let firstSessionCloses = await session.closeAttempts
        XCTAssertTrue(firstSnapshot.hasSession)
        XCTAssertTrue(firstSnapshot.hasAcquisition)
        XCTAssertFalse(firstSnapshot.isStreaming)
        XCTAssertEqual(firstAcquisitionCloses, 1)
        XCTAssertEqual(firstSessionCloses, 0, "The parent must remain open while its child close fails.")

        try await lifecycle.close()

        let finalSnapshot = await lifecycle.snapshot()
        let finalAcquisitionCloses = acquisition.closeAttempts
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

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()

        do {
            try await lifecycle.close()
            XCTFail("Expected the first device close to fail.")
        } catch {}

        let firstSnapshot = await lifecycle.snapshot()
        let firstAcquisitionCloses = acquisition.closeAttempts
        let firstSessionCloses = await session.closeAttempts
        XCTAssertTrue(firstSnapshot.hasSession)
        XCTAssertFalse(firstSnapshot.hasAcquisition)
        XCTAssertEqual(firstAcquisitionCloses, 1)

        try await lifecycle.close()

        let finalSnapshot = await lifecycle.snapshot()
        let finalAcquisitionCloses = acquisition.closeAttempts
        let finalSessionCloses = await session.closeAttempts
        XCTAssertFalse(finalSnapshot.hasSession)
        XCTAssertEqual(finalAcquisitionCloses, 1, "A successfully closed child must not be closed twice.")
        XCTAssertEqual(finalSessionCloses, 2)
    }

    func testFramesAreDeliveredAndStopClosesCaptureLoop() async throws {
        let acquisition = FakeAcquisition()
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()
        let frames = await lifecycle.frames()
        var iterator = frames.makeAsyncIterator()

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()
        acquisition.emit(makeFrame(sequence: 42))

        let receivedFrame = await iterator.next()

        XCTAssertEqual(receivedFrame?.sequence, 42)
        try await lifecycle.stop()

        let snapshot = await lifecycle.snapshot()
        let stopAttempts = acquisition.stopAttempts
        XCTAssertFalse(snapshot.isStreaming)
        XCTAssertTrue(snapshot.hasSession)
        XCTAssertTrue(snapshot.hasAcquisition)
        XCTAssertEqual(stopAttempts, 1)
    }

    func testStopThenStartCreatesFreshAcquisitionOnExistingDeviceSession() async throws {
        let firstAcquisition = FakeAcquisition()
        let secondAcquisition = FakeAcquisition()
        let session = FakeSession(
            acquisition: firstAcquisition,
            additionalAcquisitions: [secondAcquisition]
        )
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()
        try await lifecycle.stop()

        let stoppedSnapshot = await lifecycle.snapshot()
        XCTAssertFalse(stoppedSnapshot.isStreaming)
        XCTAssertTrue(stoppedSnapshot.hasSession)
        XCTAssertTrue(stoppedSnapshot.hasAcquisition)

        // Starting again must close the old GenTL acquisition and ask the still-open
        // camera session for a fresh acquisition object.
        try await lifecycle.start()

        let restartedSnapshot = await lifecycle.snapshot()
        let acquisitionRequests = await session.acquisitionRequests
        XCTAssertTrue(restartedSnapshot.isStreaming)
        XCTAssertTrue(restartedSnapshot.hasSession)
        XCTAssertTrue(restartedSnapshot.hasAcquisition)
        XCTAssertEqual(acquisitionRequests, 2)
        XCTAssertEqual(firstAcquisition.closeAttempts, 1)
        XCTAssertEqual(secondAcquisition.startAttempts, 1)

        try await lifecycle.stop()
        try await lifecycle.close()

        let sessionCloseAttempts = await session.closeAttempts
        XCTAssertEqual(secondAcquisition.closeAttempts, 1)
        XCTAssertEqual(sessionCloseAttempts, 1)
    }

    func testFrameArrivingDuringCloseIsRejectedByGenerationGuard() async throws {
        let frame = makeFrame(sequence: 99)
        let acquisition = FakeAcquisition(frameOnClose: frame)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()
        let events = await lifecycle.events()
        var eventIterator = events.makeAsyncIterator()

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()
        try await lifecycle.close()

        var receivedClosed = false
        while let event = await eventIterator.next() {
            if case .closed = event {
                receivedClosed = true
                break
            }
        }

        let snapshot = await lifecycle.snapshot()
        XCTAssertNil(
            snapshot.lastDeliveredFrameSequence,
            "A frame from an invalidated acquisition generation must not be recorded as delivered."
        )
        XCTAssertTrue(receivedClosed)
    }


    func testStartFailureClosesPartiallyCreatedAcquisition() async throws {
        let acquisition = FakeAcquisition(startFailures: 1)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.open(FakeDevice(session: session))
        do {
            try await lifecycle.start()
            XCTFail("Expected the injected acquisition start failure.")
        } catch {}

        let snapshot = await lifecycle.snapshot()
        let acquisitionCloseAttempts = acquisition.closeAttempts
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
        let frames = await lifecycle.frames()
        var iterator = frames.makeAsyncIterator()

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()
        acquisition.emit(makeFrame(sequence: 73))

        let receivedFrame = await iterator.next()

        XCTAssertEqual(receivedFrame?.sequence, 73)
        let snapshot = await lifecycle.snapshot()
        XCTAssertTrue(snapshot.isStreaming)
        try await lifecycle.stop()
        try await lifecycle.close()
    }

    func testUnexpectedAcquisitionStopClearsStreamingState() async throws {
        let acquisition = FakeAcquisition(stoppedReadCount: 1)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()
        let events = await lifecycle.events()
        var iterator = events.makeAsyncIterator()

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()

        var reportedFailure: String?
        while let event = await iterator.next() {
            if case .failure(let message) = event {
                reportedFailure = message
                break
            }
        }

        let snapshot = await lifecycle.snapshot()
        XCTAssertEqual(reportedFailure, "The camera acquisition stopped without a stop request.")
        XCTAssertFalse(snapshot.isStreaming)
        XCTAssertTrue(snapshot.hasAcquisition)
        try await lifecycle.close()
    }

    func testFatalReadStopsAcquisitionAndReportsFailure() async throws {
        let acquisition = FakeAcquisition(readFailureMessage: "Injected frame-read failure")
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()
        let events = await lifecycle.events()
        var iterator = events.makeAsyncIterator()

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()

        var reportedFailure: String?
        while let event = await iterator.next() {
            if case .failure(let message) = event {
                reportedFailure = message
                break
            }
        }

        let snapshot = await lifecycle.snapshot()
        XCTAssertEqual(reportedFailure, "Injected frame-read failure")
        XCTAssertFalse(snapshot.isStreaming)
        XCTAssertTrue(snapshot.hasAcquisition, "The stopped acquisition remains owned until explicit close.")
        XCTAssertEqual(acquisition.stopAttempts, 1)

        try await lifecycle.close()
    }

    func testConcurrentCloseWaitsForFirstCloseWithoutDoubleClosing() async throws {
        let gate = AsyncGate()
        let acquisition = FakeAcquisition(closeGate: gate)
        let session = FakeSession(acquisition: acquisition)
        let lifecycle = CameraSessionLifecycle()

        try await lifecycle.open(FakeDevice(session: session))
        try await lifecycle.start()

        let firstClose = Task {
            try await lifecycle.close()
        }
        await gate.waitUntilEntered()

        let secondClose = Task {
            try await lifecycle.close()
        }
        await Task.yield()

        await gate.release()
        try await firstClose.value
        try await secondClose.value

        let snapshot = await lifecycle.snapshot()
        XCTAssertFalse(snapshot.hasSession)
        XCTAssertFalse(snapshot.hasAcquisition)
        XCTAssertEqual(acquisition.closeAttempts, 1)
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
