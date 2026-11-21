import AmcamABI
import AmcamCameraModel
import Darwin
import Dispatch
import Foundation
import XCTest
@_spi(BackendConvenience) import GenTLAPI
@testable import AmcamGenTL
@_spi(BackendFactory) import AmcamGenTL

private final class FrameCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFrame: AmcamFrame?

    func store(_ frame: AmcamFrame) {
        lock.lock()
        storedFrame = frame
        lock.unlock()
    }

    func load() -> AmcamFrame? {
        lock.lock()
        defer { lock.unlock() }
        return storedFrame
    }
}

private final class FailureCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedMessage: String?

    func store(_ error: Error) {
        lock.lock()
        storedMessage = error.localizedDescription
        lock.unlock()
    }

    func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedMessage
    }
}

final class AmcamSDKIntegrationTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AmcamSDKIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testDiscoveryOpenSynchronousFrameCallbackAndRepeatedStopClose() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)

        let devices = try driver.discover()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].identifier, "MOCK-AMSCOP-001")
        XCTAssertEqual(devices[0].displayName, "Mock AmScope Camera")
        XCTAssertEqual(devices[0].modelName, "Mock AmScope Camera")
        XCTAssertEqual(devices[0].previewResolutions, [
            AmcamResolution(index: 0, width: 2560, height: 1922),
            AmcamResolution(index: 1, width: 1280, height: 960),
            AmcamResolution(index: 2, width: 640, height: 480)
        ])

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer { if let fixtureHandle { dlclose(fixtureHandle) } }
        guard let flushCountSymbol = dlsym(fixtureHandle, "MockAmcam_FlushCount") else {
            XCTFail("Mock SDK is missing MockAmcam_FlushCount")
            return
        }
        let flushCount = unsafeBitCast(flushCountSymbol, to: (@convention(c) () -> UInt32).self)

        let session = try driver.open(deviceIdentifier: devices[0].identifier)
        XCTAssertEqual(session.currentDimensions().width, 640)
        XCTAssertEqual(session.currentDimensions().height, 480)
        XCTAssertEqual(session.currentResolution(), AmcamResolution(index: 2, width: 640, height: 480))

        for expectedSequence in UInt32(1)...UInt32(3) {
            let frameReceived = expectation(description: "frame \(expectedSequence)")
            let receivedFrame = FrameCapture()
            try session.start { result in
                if case .success(let frame) = result {
                    receivedFrame.store(frame)
                    frameReceived.fulfill()
                } else if case .failure(let error) = result {
                    XCTFail("Unexpected frame failure: \(error)")
                }
            }

            wait(for: [frameReceived], timeout: 2)
            let frame = try XCTUnwrap(receivedFrame.load())
            XCTAssertEqual(frame.width, 640)
            XCTAssertEqual(frame.height, 480)
            XCTAssertEqual(frame.bytesPerRow, 1920)
            XCTAssertEqual(frame.pixelFormat, .rgb24)
            XCTAssertEqual(frame.bytes.count, 640 * 480 * 3)
            XCTAssertEqual(frame.bytes.first, 0x5a)
            XCTAssertEqual(frame.sequence, expectedSequence)
            XCTAssertEqual(frame.deviceTimestampMicroseconds, 123456789 + UInt64(expectedSequence))
            XCTAssertEqual(frame.metadata?.apiVersion, .v4)
            XCTAssertEqual(frame.metadata?.exposureTimeMicroseconds, 10_000)
            XCTAssertEqual(frame.metadata?.exposureGain, 125)
            XCTAssertEqual(frame.metadata?.blackLevel, 16)
            XCTAssertEqual(frame.metadata?.shutterSequence, 7)
            XCTAssertEqual(frame.metadata?.luminance, 123)
            XCTAssertEqual(frame.metadata?.focusValue, 0x1_0000_0001)
            XCTAssertEqual(frame.metadata?.timeCount, 0x2_0000_0002)
            XCTAssertEqual(frame.metadata?.frameCount, 12)
            XCTAssertEqual(frame.metadata?.triggerCount, 13)
            XCTAssertEqual(frame.metadata?.gps?.longitudeMicrodegrees, 31_200_000)
            XCTAssertEqual(frame.metadata?.gps?.latitudeMicrodegrees, 30_000_000)
            XCTAssertEqual(frame.metadata?.gps?.altitudeMillimetres, 45_600)
            XCTAssertEqual(frame.metadata?.gps?.satelliteCount, 8)

            try session.stop()
            XCTAssertEqual(
                flushCount(),
                expectedSequence,
                "Each successful Amcam_Stop must flush the camera and SDK frame caches before another Start."
            )
        }

        // A fatal disconnect event must notify the consumer but retain the SDK
        // callback registration until Amcam_Stop has completed.
        let disconnected = expectation(description: "camera disconnected")
        try session.start { result in
            if case .failure(.cameraDisconnected) = result {
                disconnected.fulfill()
            }
        }
        let emitterHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(emitterHandle)
        defer { if let emitterHandle { dlclose(emitterHandle) } }
        guard let symbol = dlsym(emitterHandle, "MockAmcam_EmitEvent") else {
            XCTFail("Mock SDK is missing MockAmcam_EmitEvent")
            return
        }
        let emitEvent = unsafeBitCast(symbol, to: (@convention(c) (UInt32) -> Void).self)
        emitEvent(0x0081)
        wait(for: [disconnected], timeout: 2)
        try session.stop()
        XCTAssertEqual(flushCount(), 4, "Stopping after a disconnect must also flush retained SDK frame caches.")
        try session.close()
    }



    func testRepeatedImageEventsProduceMultipleFramesWithinOneSession() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)
        defer { try? session.close() }

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer { if let fixtureHandle { dlclose(fixtureHandle) } }
        guard let emitterSymbol = dlsym(fixtureHandle, "MockAmcam_EmitEvent"),
              let pullCountSymbol = dlsym(fixtureHandle, "MockAmcam_PullCount"),
              let pullContextSymbol = dlsym(fixtureHandle, "MockAmcam_PullInsideCallbackCount") else {
            XCTFail("Mock SDK is missing repeated-frame or callback-boundary test hooks")
            return
        }
        let emitEvent = unsafeBitCast(emitterSymbol, to: (@convention(c) (UInt32) -> Void).self)
        let pullCount = unsafeBitCast(pullCountSymbol, to: (@convention(c) () -> UInt32).self)
        let pullInsideCallbackCount = unsafeBitCast(
            pullContextSymbol,
            to: (@convention(c) () -> UInt32).self
        )

        let framesDelivered = expectation(description: "all image events become frames")
        framesDelivered.expectedFulfillmentCount = 9
        try session.start { result in
            switch result {
            case .success:
                framesDelivered.fulfill()
            case .failure(let error):
                XCTFail("A repeated image event stopped pull mode: \(error)")
            }
        }

        // Start produces the first synchronous mock callback; the remaining
        // events model later frames in the same uninterrupted live acquisition.
        for _ in 0..<8 {
            emitEvent(AmcamSDK.imageEvent)
        }

        wait(for: [framesDelivered], timeout: 2)
        XCTAssertEqual(pullCount(), 9, "Every image event must be pulled exactly once.")
        XCTAssertEqual(
            pullInsideCallbackCount(),
            0,
            "PullImage must run after the SDK callback returns, on the dedicated acquisition queue."
        )
        XCTAssertTrue(session.isStreaming, "Multiple frames must not end the acquisition.")
        try session.stop()
    }


    func testAsynchronousAmcamCallbacksRecycleOneGenTLBufferContinuously() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)

        let streamHandle = DS_HANDLE(rawValue: 0x101)
        let deviceHandle = DEV_HANDLE(rawValue: 0x102)
        let bufferHandle = BUFFER_HANDLE(rawValue: 0x103)
        let event = AmcamEventRecord(
            handle: EVENT_HANDLE(rawValue: 0x104),
            eventType: GenTLEventType.newBuffer.rawValue,
            source: .dataStream(streamHandle)
        )
        let stream = try AmcamDataStreamRecord(
            handle: streamHandle,
            deviceHandle: deviceHandle,
            session: session
        )
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: stream.payloadSize,
            alignment: 64
        )
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: stream.payloadSize)
        defer {
            try? stream.close()
            try? session.close()
            memory.deallocate()
        }

        try stream.announce(
            handle: bufferHandle,
            memory: memory,
            size: stream.payloadSize,
            privateData: nil,
            allocatedByProvider: false
        )
        try stream.queue(bufferHandle)
        stream.addEvent(event)

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer { if let fixtureHandle { dlclose(fixtureHandle) } }
        guard let intervalSymbol = dlsym(fixtureHandle, "MockAmcam_SetAutomaticFrameInterval"),
              let callbackCountSymbol = dlsym(fixtureHandle, "MockAmcam_AsynchronousCallbackCount") else {
            XCTFail("Mock SDK is missing asynchronous callback test hooks")
            return
        }
        let setInterval = unsafeBitCast(
            intervalSymbol,
            to: (@convention(c) (UInt32) -> Void).self
        )
        let asynchronousCallbackCount = unsafeBitCast(
            callbackCountSymbol,
            to: (@convention(c) () -> UInt32).self
        )
        setInterval(40)

        try stream.start(numberToAcquire: GenTLConstants.infiniteCount)

        var deliveredSequences: [UInt64] = []
        for expected in UInt64(1)...UInt64(10) {
            let payload = try stream.nextEventData(event, timeoutMilliseconds: 2_000)
            let deliveredHandle = payload.withUnsafeBytes {
                $0.loadUnaligned(as: UInt.self)
            }
            XCTAssertEqual(deliveredHandle, bufferHandle.rawValue)

            if expected == 1 {
                // Both GenTL buffer metadata surfaces must describe the delivered
                // Amcam RGB24 payload as the same PFNC RGB8 identity. Part metadata
                // is queried only after this buffer contains a completed frame.
                let bufferPixelFormat = try stream.bufferInfo(bufferHandle, command: 20)
                let bufferPixelNamespace = try stream.bufferInfo(bufferHandle, command: 21)
                let partPixelFormat = try stream.bufferPartInfo(bufferHandle, command: 3)
                let partPixelNamespace = try stream.bufferPartInfo(bufferHandle, command: 4)
                XCTAssertEqual(bufferPixelFormat, .uint64(0x02180014))
                XCTAssertEqual(partPixelFormat, bufferPixelFormat)
                XCTAssertEqual(bufferPixelNamespace, .uint64(UInt64(GenTLPixelFormatNamespace.pfnc32Bit.rawValue)))
                XCTAssertEqual(partPixelNamespace, bufferPixelNamespace)
            }

            let sequenceValue = try stream.bufferInfo(bufferHandle, command: 16)
            guard case .uint64(let sequence) = sequenceValue else {
                XCTFail("GenTL buffer sequence was not returned as UINT64: \\(sequenceValue)")
                return
            }
            XCTAssertEqual(sequence, expected)
            XCTAssertEqual(memory.load(as: UInt8.self), 0x5a)
            deliveredSequences.append(sequence)

            // The consumer returns the exact same announced buffer only after
            // EventGetData has transferred it out of the output queue.
            try stream.queue(bufferHandle)
        }

        XCTAssertEqual(deliveredSequences, Array(UInt64(1)...UInt64(10)))
        XCTAssertEqual(stream.numDelivered, 10)
        XCTAssertEqual(stream.numUnderrun, 0)
        XCTAssertGreaterThanOrEqual(
            asynchronousCallbackCount(),
            9,
            "The fixture must deliver later image callbacks on its worker thread."
        )

        try stream.stop()
        let callbackCountAfterStop = asynchronousCallbackCount()
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(
            asynchronousCallbackCount(),
            callbackCountAfterStop,
            "Amcam_Stop must join callback delivery before the retained context is released."
        )
        try stream.close()
        try session.close()
    }

    func testCallbackPullIsSerializedWithControlReadsDuringLiveAcquisition() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)
        defer { try? session.close() }

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer { if let fixtureHandle { dlclose(fixtureHandle) } }
        guard let emitterSymbol = dlsym(fixtureHandle, "MockAmcam_EmitEvent"),
              let delaysSymbol = dlsym(fixtureHandle, "MockAmcam_SetCallDelays"),
              let activeCallsSymbol = dlsym(fixtureHandle, "MockAmcam_ActiveSDKCallCount"),
              let concurrentCallsSymbol = dlsym(fixtureHandle, "MockAmcam_ConcurrentSDKCallCount") else {
            XCTFail("Mock SDK is missing SDK-call serialization test hooks")
            return
        }
        let emitEvent = unsafeBitCast(emitterSymbol, to: (@convention(c) (UInt32) -> Void).self)
        let setCallDelays = unsafeBitCast(
            delaysSymbol,
            to: (@convention(c) (UInt32, UInt32) -> Void).self
        )
        let activeCallCount = unsafeBitCast(
            activeCallsSymbol,
            to: (@convention(c) () -> UInt32).self
        )
        let concurrentCallCount = unsafeBitCast(
            concurrentCallsSymbol,
            to: (@convention(c) () -> UInt32).self
        )

        let framesDelivered = expectation(description: "initial and concurrent image callbacks")
        framesDelivered.expectedFulfillmentCount = 2
        try session.start { result in
            switch result {
            case .success:
                framesDelivered.fulfill()
            case .failure(let error):
                XCTFail("Unexpected callback failure during the control-read race: \(error)")
            }
        }

        // Hold a control getter inside the mock vendor SDK. A concurrent image
        // callback must wait for that call to finish instead of entering the same
        // camera handle concurrently.
        setCallDelays(40, 250)
        let controlFinished = DispatchSemaphore(value: 0)
        let controlFailure = FailureCapture()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try session.readControls()
            } catch {
                controlFailure.store(error)
            }
            controlFinished.signal()
        }

        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while activeCallCount() == 0,
              ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertEqual(activeCallCount(), 1, "The mock control read did not enter the SDK.")

        let callbackFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            emitEvent(AmcamSDK.imageEvent)
            callbackFinished.signal()
        }

        XCTAssertEqual(
            controlFinished.wait(timeout: .now() + 3),
            .success,
            "The control read did not finish."
        )
        XCTAssertEqual(
            callbackFinished.wait(timeout: .now() + 3),
            .success,
            "The image callback did not finish after the control read."
        )
        wait(for: [framesDelivered], timeout: 2)
        XCTAssertNil(controlFailure.load())
        XCTAssertEqual(
            concurrentCallCount(),
            0,
            "PullImageV4 and camera feature reads must never enter the same SDK handle concurrently."
        )
        try session.stop()
    }

    func testFailedPostStopFlushIsRetriedBeforePullModeRestart() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer {
            if let fixtureHandle { dlclose(fixtureHandle) }
            try? session.close()
        }
        guard let failureSymbol = dlsym(fixtureHandle, "MockAmcam_SetFlushFailures"),
              let flushCountSymbol = dlsym(fixtureHandle, "MockAmcam_FlushCount") else {
            XCTFail("Mock SDK is missing frame-cache flush test hooks")
            return
        }
        let setFlushFailures = unsafeBitCast(
            failureSymbol,
            to: (@convention(c) (UInt32) -> Void).self
        )
        let flushCount = unsafeBitCast(
            flushCountSymbol,
            to: (@convention(c) () -> UInt32).self
        )

        let firstFrameReceived = expectation(description: "first acquisition frame")
        try session.start { result in
            if case .success = result {
                firstFrameReceived.fulfill()
            }
        }
        wait(for: [firstFrameReceived], timeout: 2)

        setFlushFailures(1)
        XCTAssertThrowsError(try session.stop(), "A failed cache flush must not report a reusable stopped session.")
        XCTAssertEqual(flushCount(), 0)

        let restartedFrameReceived = expectation(description: "frame after pending flush retry")
        do {
            try session.start { result in
                switch result {
                case .success:
                    restartedFrameReceived.fulfill()
                case .failure(let error):
                    XCTFail("Restarted pull mode delivered an unexpected frame error: \(error)")
                }
            }
        } catch {
            XCTFail("Start must retry the outstanding cache flush before registering a new callback: \(error)")
        }
        wait(for: [restartedFrameReceived], timeout: 2)
        XCTAssertEqual(flushCount(), 1)

        try session.stop()
        XCTAssertEqual(flushCount(), 2)
        try session.close()
    }

    func testAcquisitionPrefersV4AndPreservesAllValidFrameMetadata() throws {
        let libraryURL = try buildMockSDK()
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        let bufferSize = 640 * 480 * 3
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 64)
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)
        defer {
            buffer.deallocate()
            sdk.close(opened.handle)
        }

        XCTAssertEqual(sdk.pullImageOperationName, "Amcam_PullImageV4")
        var frameInfo = AmcamFrameInfoV2()
        var metadata: AmcamFrameMetadata?
        var operationName: String?
        var tightlyPackedRows = false
        XCTAssertGreaterThanOrEqual(
            sdk.pullImage(
                opened.handle,
                buffer: buffer,
                frameInfo: &frameInfo,
                metadata: &metadata,
                operationName: &operationName,
                tightlyPackedRows: &tightlyPackedRows
            ),
            0
        )
        XCTAssertEqual(operationName, "Amcam_PullImageV4")
        XCTAssertFalse(tightlyPackedRows, "V4 must follow the vendor sample's default DWORD-aligned row layout.")
        XCTAssertEqual(frameInfo.width, 640)
        XCTAssertEqual(frameInfo.height, 480)
        XCTAssertEqual(frameInfo.seq, 1)
        XCTAssertEqual(buffer.load(as: UInt8.self), 0x5a)

        let frame = try XCTUnwrap(metadata)
        XCTAssertEqual(frame.apiVersion, .v4)
        XCTAssertEqual(frame.validityFlags, 0x0001_03ff)
        XCTAssertEqual(frame.shutterSequence, 7)
        XCTAssertEqual(frame.exposureTimeMicroseconds, 10_000)
        XCTAssertEqual(frame.exposureGain, 125)
        XCTAssertEqual(frame.blackLevel, 16)
        XCTAssertEqual(frame.luminance, 123)
        XCTAssertEqual(frame.focusValue, 0x1_0000_0001)
        XCTAssertEqual(frame.timeCount, 0x2_0000_0002)
        XCTAssertEqual(frame.frameCount, 12)
        XCTAssertEqual(frame.triggerCount, 13)
        XCTAssertEqual(frame.mechanicalShutterClosed, true)
        XCTAssertEqual(frame.conversionGainHigh, true)
        XCTAssertEqual(frame.gps?.exposureStartUnixNanoseconds, 1_700_000_000_000_000_000)
        XCTAssertEqual(frame.gps?.exposureEndUnixNanoseconds, 1_700_000_000_001_000_000)
        XCTAssertEqual(frame.gps?.longitudeMicrodegrees, 31_200_000)
        XCTAssertEqual(frame.gps?.latitudeMicrodegrees, 30_000_000)
        XCTAssertEqual(frame.gps?.altitudeMillimetres, 45_600)
        XCTAssertEqual(frame.gps?.satelliteCount, 8)

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let versionSymbol = dlsym(mockLibrary, "MockAmcam_PullAPIVersion") else {
            XCTFail("Mock SDK is missing MockAmcam_PullAPIVersion")
            return
        }
        let reportedVersion = unsafeBitCast(versionSymbol, to: (@convention(c) () -> UInt32).self)
        XCTAssertEqual(reportedVersion(), 4, "The SDK must actually dispatch through PullImageV4.")
    }

    func testNoFrameAndNoPacketTimeoutEventsStopAcquisitionWithSpecificErrors() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)
        defer { try? session.close() }

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let emitterSymbol = dlsym(mockLibrary, "MockAmcam_EmitEvent") else {
            XCTFail("Mock SDK is missing MockAmcam_EmitEvent")
            return
        }
        let emitEvent = unsafeBitCast(
            emitterSymbol,
            to: (@convention(c) (UInt32) -> Void).self
        )

        for eventCode in [
            AmcamSDK.noFrameTimeoutEvent,
            AmcamSDK.noPacketTimeoutEvent
        ] {
            let eventReceived = expectation(description: "camera timeout event 0x\(String(eventCode, radix: 16))")
            try session.start { result in
                if case .failure(.cameraEventFailure(let actualCode)) = result {
                    XCTAssertEqual(actualCode, eventCode)
                    eventReceived.fulfill()
                }
            }

            emitEvent(eventCode)
            wait(for: [eventReceived], timeout: 2)
            XCTAssertTrue(
                session.isStreaming,
                "Callback ownership is retained after the event until Amcam_Stop succeeds."
            )
            // The timeout event stops frame delivery, but native callback ownership
            // remains until Amcam_Stop succeeds. The same session must then restart.
            try session.stop()
            XCTAssertFalse(session.isStreaming)
        }
    }

    func testPendingImagePullDoesNotStopTheSession() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)
        defer { try? session.close() }

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let pendingCountSymbol = dlsym(mockLibrary, "MockAmcam_SetPendingPullCount"),
              let emitEventSymbol = dlsym(mockLibrary, "MockAmcam_EmitEvent") else {
            XCTFail("Mock SDK is missing pending-pull or event controls")
            return
        }
        let setPendingPullCount = unsafeBitCast(
            pendingCountSymbol,
            to: (@convention(c) (UInt32) -> Void).self
        )
        let emitEvent = unsafeBitCast(
            emitEventSymbol,
            to: (@convention(c) (UInt32) -> Void).self
        )
        setPendingPullCount(1)

        let frameReceived = expectation(description: "frame after transient pending pull")
        let receivedFrame = FrameCapture()
        try session.start { result in
            switch result {
            case .success(let frame):
                receivedFrame.store(frame)
                frameReceived.fulfill()
            case .failure(let error):
                XCTFail("A transient E_PENDING result must not fail acquisition: \(error)")
            }
        }

        // The mock sends a synchronous first image event from StartPullMode. Its
        // PullImageV4 call returns E_PENDING once; the next event must still pull.
        XCTAssertTrue(session.isStreaming)
        emitEvent(AmcamSDK.imageEvent)
        wait(for: [frameReceived], timeout: 2)

        XCTAssertTrue(session.isStreaming)
        XCTAssertEqual(receivedFrame.load()?.metadata?.apiVersion, .v4)
        try session.stop()
    }

    func testModelProfilePinsPullImageV2WhenNewerSymbolsAreExported() throws {
        let libraryURL = try buildMockSDK()
        let registry = AmcamCameraProfileRegistry(
            acquisitionProfiles: [
                AmcamCameraAcquisitionProfile(
                    modelCode: "Mock AmScope Camera",
                    pullImageAPIPolicy: .v2
                )
            ]
        )
        let driver = try AmcamCameraDriver(
            libraryURL: libraryURL,
            profileRegistry: registry
        )
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)
        defer { try? session.close() }

        let frameReceived = expectation(description: "V2 frame delivered")
        let receivedFrame = FrameCapture()
        try session.start { result in
            if case .success(let frame) = result {
                receivedFrame.store(frame)
                frameReceived.fulfill()
            } else if case .failure(let error) = result {
                XCTFail("Unexpected V2 frame failure: \(error)")
            }
        }

        wait(for: [frameReceived], timeout: 2)
        let frame = try XCTUnwrap(receivedFrame.load())
        XCTAssertEqual(frame.width, 640)
        XCTAssertEqual(frame.height, 480)
        XCTAssertEqual(frame.bytesPerRow, 1920)
        XCTAssertEqual(frame.bytes.first, 0x5a)
        XCTAssertEqual(frame.metadata?.apiVersion, .v2)

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let versionSymbol = dlsym(mockLibrary, "MockAmcam_PullAPIVersion") else {
            XCTFail("Mock SDK is missing MockAmcam_PullAPIVersion")
            return
        }
        let reportedVersion = unsafeBitCast(versionSymbol, to: (@convention(c) () -> UInt32).self)
        XCTAssertEqual(reportedVersion(), 1, "The model profile must select PullImageV2 despite newer exported symbols.")

        try session.stop()
    }

    func testV4MetadataDoesNotExposeValuesWithoutValidityFlags() throws {
        let libraryURL = try buildMockSDK()
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        defer { sdk.close(opened.handle) }

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let setterSymbol = dlsym(mockLibrary, "MockAmcam_SetV4FrameFlags") else {
            XCTFail("Mock SDK is missing MockAmcam_SetV4FrameFlags")
            return
        }
        let setFlags = unsafeBitCast(setterSymbol, to: (@convention(c) (UInt32) -> Void).self)
        setFlags(0x0000_0003)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 640 * 480 * 3, alignment: 64)
        defer { buffer.deallocate() }
        var info = AmcamFrameInfoV2()
        var metadata: AmcamFrameMetadata?
        XCTAssertGreaterThanOrEqual(
            sdk.pullImage(opened.handle, buffer: buffer, frameInfo: &info, metadata: &metadata),
            0
        )
        let frame = try XCTUnwrap(metadata)
        XCTAssertEqual(frame.validityFlags, 0x0000_0003)
        XCTAssertNil(frame.shutterSequence)
        XCTAssertNil(frame.exposureTimeMicroseconds)
        XCTAssertNil(frame.exposureGain)
        XCTAssertNil(frame.blackLevel)
        XCTAssertNil(frame.luminance)
        XCTAssertNil(frame.focusValue)
        XCTAssertNil(frame.timeCount)
        XCTAssertNil(frame.frameCount)
        XCTAssertNil(frame.triggerCount)
        XCTAssertNil(frame.gps)
        XCTAssertNil(frame.mechanicalShutterClosed)
        XCTAssertNil(frame.conversionGainHigh)
    }

    func testAcquisitionFallsBackPerCameraWhenV4ReturnsNotImplemented() throws {
        let libraryURL = try buildMockSDK()
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        defer { sdk.close(opened.handle) }

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let setterSymbol = dlsym(mockLibrary, "MockAmcam_SetUnsupportedPullAPIVersion"),
              let versionSymbol = dlsym(mockLibrary, "MockAmcam_PullAPIVersion") else {
            XCTFail("Mock SDK is missing pull API capability controls")
            return
        }
        let setUnsupported = unsafeBitCast(setterSymbol, to: (@convention(c) (UInt32) -> Void).self)
        let reportedVersion = unsafeBitCast(versionSymbol, to: (@convention(c) () -> UInt32).self)
        setUnsupported(4)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 640 * 480 * 3, alignment: 64)
        defer { buffer.deallocate() }
        var info = AmcamFrameInfoV2()
        var metadata: AmcamFrameMetadata?
        var operationName: String?
        var tightlyPackedRows = false
        XCTAssertEqual(
            sdk.pullImage(opened.handle, buffer: buffer, frameInfo: &info, metadata: &metadata, operationName: &operationName, tightlyPackedRows: &tightlyPackedRows),
            0
        )
        XCTAssertEqual(operationName, "Amcam_PullImageV3")
        XCTAssertTrue(tightlyPackedRows)
        XCTAssertEqual(reportedVersion(), 3)
        XCTAssertEqual(metadata?.apiVersion, .v3)
    }

    func testPullFailureClearsOptionalOutputParameters() throws {
        let libraryURL = try buildMockSDK()
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        defer { sdk.close(opened.handle) }

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let setterSymbol = dlsym(mockLibrary, "MockAmcam_SetPullFailure") else {
            XCTFail("Mock SDK is missing MockAmcam_SetPullFailure")
            return
        }
        let setFailure = unsafeBitCast(setterSymbol, to: (@convention(c) (Int32) -> Void).self)
        setFailure(-1)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 640 * 480 * 3, alignment: 64)
        defer { buffer.deallocate() }
        var info = AmcamFrameInfoV2()
        var metadata: AmcamFrameMetadata? = AmcamFrameMetadata(
            apiVersion: .v4,
            validityFlags: .max,
            exposureTimeMicroseconds: 123
        )
        var operationName: String? = "stale operation"
        var tightlyPackedRows = true

        XCTAssertEqual(
            sdk.pullImage(
                opened.handle,
                buffer: buffer,
                frameInfo: &info,
                metadata: &metadata,
                operationName: &operationName,
                tightlyPackedRows: &tightlyPackedRows
            ),
            -1
        )
        XCTAssertNil(metadata)
        XCTAssertEqual(operationName, "Amcam_PullImageV4")
        XCTAssertFalse(tightlyPackedRows)
    }

    func testAcquisitionDoesNotFallbackForHardwareErrors() throws {
        let libraryURL = try buildMockSDK()
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        defer { sdk.close(opened.handle) }

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let setterSymbol = dlsym(mockLibrary, "MockAmcam_SetPullFailure") else {
            XCTFail("Mock SDK is missing MockAmcam_SetPullFailure")
            return
        }
        let setFailure = unsafeBitCast(setterSymbol, to: (@convention(c) (Int32) -> Void).self)
        setFailure(-1)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 640 * 480 * 3, alignment: 64)
        defer { buffer.deallocate() }
        var info = AmcamFrameInfoV2()
        var operationName: String?
        var tightlyPackedRows = true
        XCTAssertEqual(
            sdk.pullImage(opened.handle, buffer: buffer, frameInfo: &info, operationName: &operationName, tightlyPackedRows: &tightlyPackedRows),
            -1
        )
        XCTAssertEqual(operationName, "Amcam_PullImageV4")
    }

    func testCameraFallsBackAcrossUnsupportedPullAPIsToPlainV2() throws {
        let libraryURL = try buildMockSDK()
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        defer { sdk.close(opened.handle) }

        let mockLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(mockLibrary)
        defer { if let mockLibrary { dlclose(mockLibrary) } }
        guard let setterSymbol = dlsym(mockLibrary, "MockAmcam_SetUnsupportedPullAPIMask"),
              let versionSymbol = dlsym(mockLibrary, "MockAmcam_PullAPIVersion") else {
            XCTFail("Mock SDK is missing pull API capability controls")
            return
        }
        let setMask = unsafeBitCast(setterSymbol, to: (@convention(c) (UInt32) -> Void).self)
        let reportedVersion = unsafeBitCast(versionSymbol, to: (@convention(c) () -> UInt32).self)
        // Bit positions identify API generations: V2=1, row-pitch V2=2, V3=3, V4=4.
        setMask((1 << 4) | (1 << 3) | (1 << 2))

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 640 * 480 * 3, alignment: 64)
        defer { buffer.deallocate() }
        var info = AmcamFrameInfoV2()
        var metadata: AmcamFrameMetadata?
        var operationName: String?
        var tightlyPackedRows = true
        XCTAssertEqual(
            sdk.pullImage(opened.handle, buffer: buffer, frameInfo: &info, metadata: &metadata, operationName: &operationName, tightlyPackedRows: &tightlyPackedRows),
            0
        )
        XCTAssertEqual(operationName, "Amcam_PullImageV2")
        XCTAssertEqual(reportedVersion(), 1)
        XCTAssertFalse(tightlyPackedRows)
        XCTAssertEqual(metadata?.apiVersion, .v2)
    }

    func testAcquisitionFallsBackToV3WhenV4IsNotExported() throws {
        let libraryURL = try buildMockSDK(disableV4: true)
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        defer { sdk.close(opened.handle) }

        XCTAssertEqual(sdk.pullImageOperationName, "Amcam_PullImageV3")
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 640 * 480 * 3, alignment: 64)
        defer { buffer.deallocate() }
        var info = AmcamFrameInfoV2()
        var metadata: AmcamFrameMetadata?
        XCTAssertEqual(sdk.pullImage(opened.handle, buffer: buffer, frameInfo: &info, metadata: &metadata), 0)
        XCTAssertEqual(metadata?.apiVersion, .v3)
        XCTAssertEqual(metadata?.exposureTimeMicroseconds, 10_000)
        XCTAssertEqual(metadata?.exposureGain, 100)
        XCTAssertEqual(metadata?.blackLevel, 0)
    }

    func testAcquisitionFallsBackToRowPitchV2WhenV3AndV4AreNotExported() throws {
        let libraryURL = try buildMockSDK(disableV4: true, disableV3: true)
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        defer { sdk.close(opened.handle) }

        XCTAssertEqual(sdk.pullImageOperationName, "Amcam_PullImageWithRowPitchV2")
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 640 * 480 * 3, alignment: 64)
        defer { buffer.deallocate() }
        var info = AmcamFrameInfoV2()
        var metadata: AmcamFrameMetadata?
        var tightlyPackedRows = false
        XCTAssertEqual(sdk.pullImage(opened.handle, buffer: buffer, frameInfo: &info, metadata: &metadata, tightlyPackedRows: &tightlyPackedRows), 0)
        XCTAssertTrue(tightlyPackedRows)
        XCTAssertEqual(metadata?.apiVersion, .v2)
        XCTAssertEqual(info.width, 640)
        XCTAssertEqual(info.height, 480)
    }

    func testAcquisitionFallsBackToV2WhenNoRowPitchOrNewerPullAPIExists() throws {
        let libraryURL = try buildMockSDK(disableV4: true, disableV3: true, disableRowPitchV2: true)
        let sdk = try AmcamSDK(libraryURL: libraryURL)
        let device = try XCTUnwrap(sdk.enumerate().first)
        let opened = try sdk.open(identifier: device.identifier)
        defer { sdk.close(opened.handle) }

        XCTAssertEqual(sdk.pullImageOperationName, "Amcam_PullImageV2")
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 640 * 480 * 3, alignment: 64)
        defer { buffer.deallocate() }
        var info = AmcamFrameInfoV2()
        var metadata: AmcamFrameMetadata?
        var tightlyPackedRows = true
        XCTAssertEqual(sdk.pullImage(opened.handle, buffer: buffer, frameInfo: &info, metadata: &metadata, tightlyPackedRows: &tightlyPackedRows), 0)
        XCTAssertFalse(tightlyPackedRows)
        XCTAssertEqual(metadata?.apiVersion, .v2)
        XCTAssertEqual(info.width, 640)
        XCTAssertEqual(info.height, 480)
    }

    func testExposureControlsAndResolutionReadback() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)
        defer { try? session.close() }

        XCTAssertTrue(session.supportsResolutionChange())
        let capabilities = try session.cameraCapabilities()
        XCTAssertTrue(capabilities.availability(of: .whiteBalance).isUsable)
        XCTAssertTrue(capabilities.availability(of: .colorCorrection).available)
        XCTAssertTrue(capabilities.availability(of: .pixelFormatSelection).isUsable)
        var controls = try session.readControls()
        XCTAssertEqual(controls.image?.colorMatrixEnabled, true)
        XCTAssertEqual(controls.image?.pixelFormatCode, 8)
        XCTAssertEqual(controls.image?.supportedPixelFormats, [0, 8])
        controls = try session.setColorMatrixEnabled(false)
        XCTAssertEqual(controls.image?.colorMatrixEnabled, false)
        controls = try session.setPixelFormat(code: 0)
        XCTAssertEqual(controls.image?.pixelFormatCode, 0)
        XCTAssertThrowsError(try session.setPixelFormat(code: 99))
        XCTAssertEqual(controls.whiteBalance?.temperature, 6503)
        XCTAssertEqual(controls.whiteBalance?.tint, 1000)
        XCTAssertEqual(controls.whiteBalance?.rgbGain, [100, 100, 100])
        controls = try session.setWhiteBalanceRGBGain([125, 130, 140])
        XCTAssertEqual(controls.whiteBalance?.rgbGain, [125, 130, 140])
        XCTAssertTrue(controls.exposure?.automaticEnabled ?? false)
        XCTAssertEqual(controls.exposure?.readbackMicroseconds, 10_000)
        XCTAssertEqual(controls.exposure?.minimumMicroseconds, 100)
        XCTAssertEqual(controls.exposure?.maximumMicroseconds, 1_000_000)
        XCTAssertEqual(controls.gain?.readbackPercent, 100)
        XCTAssertEqual(controls.gain?.minimumPercent, 100)
        XCTAssertEqual(controls.gain?.maximumPercent, 800)
        XCTAssertTrue(controls.frameRate.supported)
        controls = try session.setWhiteBalanceTemperatureTint(temperature: 7200, tint: 1250)
        XCTAssertEqual(controls.whiteBalance?.temperature, 7200)
        XCTAssertEqual(controls.whiteBalance?.tint, 1250)
        XCTAssertThrowsError(try session.setWhiteBalanceTemperatureTint(temperature: 16000, tint: 1250))
        XCTAssertEqual(controls.frameRate.minimumFramesPerSecond, 0.1)
        XCTAssertEqual(controls.frameRate.maximumFramesPerSecond, 30.0)
        XCTAssertEqual(controls.frameRate.readbackFramesPerSecond, 15.0)

        controls = try session.setFixedFrameRate(framesPerSecond: 12.3)
        XCTAssertEqual(controls.frameRate.readbackFramesPerSecond, 12.3)
        XCTAssertEqual(controls.frameRate.requestedFramesPerSecond, 12.3)
        XCTAssertThrowsError(try session.setFixedFrameRate(framesPerSecond: 30.1))
        XCTAssertThrowsError(try session.setFixedFrameRate(framesPerSecond: 12.34))
        XCTAssertThrowsError(try session.setFrameRateSpeedLevel(2))

        XCTAssertThrowsError(try session.setExposureTime(microseconds: 20_000))
        controls = try session.setAutomaticExposure(enabled: false)
        XCTAssertFalse(controls.exposure?.automaticEnabled ?? false)

        controls = try session.setExposureTime(microseconds: 20_000)
        XCTAssertEqual(controls.exposure?.readbackMicroseconds, 20_000)
        XCTAssertEqual(controls.exposure?.requestedMicroseconds, 20_000)

        controls = try session.setExposureGain(percent: 250)
        XCTAssertEqual(controls.gain?.readbackPercent, 250)
        XCTAssertThrowsError(try session.setExposureGain(percent: 801))

        let gainFixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(gainFixtureHandle)
        defer { if let gainFixtureHandle { dlclose(gainFixtureHandle) } }
        guard let ignoreGainSymbol = dlsym(gainFixtureHandle, "MockAmcam_SetIgnoreExposureGainWrite") else {
            XCTFail("Mock SDK is missing MockAmcam_SetIgnoreExposureGainWrite")
            return
        }
        let setIgnoreGainWrite = unsafeBitCast(
            ignoreGainSymbol,
            to: (@convention(c) (Int32) -> Void).self
        )
        setIgnoreGainWrite(1)
        defer { setIgnoreGainWrite(0) }
        XCTAssertThrowsError(try session.setExposureGain(percent: 300)) { error in
            guard let cameraError = error as? AmcamCameraError,
                  case .controlReadbackMismatch(
                    control: "analog gain",
                    requested: "300%",
                    actual: "250%"
                  ) = cameraError else {
                XCTFail("Expected analog gain readback mismatch, got: \(error)")
                return
            }
        }

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer { if let fixtureHandle { dlclose(fixtureHandle) } }
        guard let ignoreSymbol = dlsym(fixtureHandle, "MockAmcam_SetIgnoreExposureWrite") else {
            XCTFail("Mock SDK is missing MockAmcam_SetIgnoreExposureWrite")
            return
        }
        let setIgnoreExposureWrite = unsafeBitCast(
            ignoreSymbol,
            to: (@convention(c) (Int32) -> Void).self
        )
        setIgnoreExposureWrite(1)
        defer { setIgnoreExposureWrite(0) }

        XCTAssertThrowsError(try session.setExposureTime(microseconds: 30_000)) { error in
            guard let cameraError = error as? AmcamCameraError,
                  case .controlReadbackMismatch(
                    control: "exposure time",
                    requested: "30000 µs",
                    actual: "20000 µs"
                  ) = cameraError else {
                XCTFail("Expected exposure readback mismatch, got: \(error)")
                return
            }
        }
        XCTAssertEqual(try session.readControls().exposure?.readbackMicroseconds, 20_000)

        XCTAssertThrowsError(try session.setExposureTime(microseconds: 1_000_001))

        controls = try session.setAutoExposureMode(.once)
        XCTAssertEqual(controls.exposure?.autoMode, .once)
        XCTAssertTrue(controls.exposure?.automaticEnabled ?? false)

        controls = try session.setAutoExposureMode(.manual)
        XCTAssertEqual(controls.exposure?.autoMode, .manual)
        XCTAssertFalse(controls.exposure?.automaticEnabled ?? false)

        controls = try session.setAutomaticExposure(enabled: true)
        XCTAssertEqual(controls.exposure?.autoMode, .continuous)
        XCTAssertTrue(controls.exposure?.automaticEnabled ?? false)

        let changed = try session.setResolution(index: 1)
        XCTAssertEqual(changed, AmcamResolution(index: 1, width: 1280, height: 960))
        XCTAssertEqual(session.currentDimensions().width, 1280)
        XCTAssertEqual(session.currentDimensions().height, 960)
        XCTAssertEqual(session.currentResolution(), changed)

        let frameReceived = expectation(description: "frame at changed resolution")
        let receivedFrame = FrameCapture()
        try session.start { result in
            if case .success(let frame) = result {
                receivedFrame.store(frame)
                frameReceived.fulfill()
            } else if case .failure(let error) = result {
                XCTFail("Unexpected frame failure: \(error)")
            }
        }
        wait(for: [frameReceived], timeout: 2)
        let frame = try XCTUnwrap(receivedFrame.load())
        XCTAssertEqual(frame.width, 1280)
        XCTAssertEqual(frame.height, 960)
        XCTAssertEqual(frame.bytesPerRow, 3840)
        XCTAssertEqual(frame.bytes.count, 1280 * 960 * 3)
        XCTAssertThrowsError(try session.setResolution(index: 0))

        try session.stop()
        let restored = try session.setResolution(index: 2)
        XCTAssertEqual(restored, AmcamResolution(index: 2, width: 640, height: 480))
        XCTAssertEqual(session.currentDimensions().width, 640)
        XCTAssertEqual(session.currentDimensions().height, 480)
    }

    func testAutoExposureModeRemainsAvailableWithoutManualExposureRange() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)
        defer { try? session.close() }

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer { if let fixtureHandle { dlclose(fixtureHandle) } }
        guard let symbol = dlsym(fixtureHandle, "MockAmcam_SetExposureRangeUnavailable") else {
            XCTFail("Mock SDK is missing MockAmcam_SetExposureRangeUnavailable")
            return
        }
        let setRangeUnavailable = unsafeBitCast(
            symbol,
            to: (@convention(c) (Int32) -> Void).self
        )
        setRangeUnavailable(1)
        defer { setRangeUnavailable(0) }

        let capabilities = try session.cameraCapabilities()
        XCTAssertTrue(capabilities.availability(of: .exposureAuto).isUsable)
        XCTAssertFalse(capabilities.availability(of: .exposureManual).available)

        var controls = try session.readControls()
        XCTAssertEqual(controls.exposure?.autoMode, .continuous)
        XCTAssertNil(controls.exposure?.readbackMicroseconds)

        controls = try session.setAutoExposureMode(.manual)
        XCTAssertEqual(controls.exposure?.autoMode, .manual)
        XCTAssertNil(controls.exposure?.readbackMicroseconds)

        controls = try session.setAutoExposureMode(.once)
        XCTAssertEqual(controls.exposure?.autoMode, .once)
        XCTAssertThrowsError(try session.setExposureTime(microseconds: 20_000))
    }

    func testUnsupportedExposureDoesNotDisableFrameRateOrStreamingControls() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)
        defer { try? session.close() }

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer { if let fixtureHandle { dlclose(fixtureHandle) } }
        guard let symbol = dlsym(fixtureHandle, "MockAmcam_SetExposureUnavailable") else {
            XCTFail("Mock SDK is missing MockAmcam_SetExposureUnavailable")
            return
        }
        let setExposureUnavailable = unsafeBitCast(
            symbol,
            to: (@convention(c) (Int32) -> Void).self
        )
        setExposureUnavailable(1)
        defer { setExposureUnavailable(0) }

        let capabilities = try session.cameraCapabilities()
        XCTAssertFalse(capabilities.availability(of: .exposureAuto).available)
        XCTAssertFalse(capabilities.availability(of: .exposureManual).available)
        XCTAssertTrue(capabilities.availability(of: .preciseFrameRate).isUsable)
        XCTAssertTrue(capabilities.availability(of: .analogGain).isUsable)

        let controls = try session.readControls()
        XCTAssertNil(controls.exposure)
        XCTAssertTrue(controls.frameRate.supported)
        XCTAssertEqual(controls.frameRate.readbackFramesPerSecond, 15.0)
        XCTAssertEqual(controls.gain?.readbackPercent, 100)

        let updated = try session.setFixedFrameRate(framesPerSecond: 12.5)
        XCTAssertNil(updated.exposure)
        XCTAssertEqual(updated.frameRate.readbackFramesPerSecond, 12.5)
    }

    func testDataStreamQueuesAndDeliversACompleteRGBFrame() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)

        let streamHandle = DS_HANDLE(rawValue: 0x101)
        let deviceHandle = DEV_HANDLE(rawValue: 0x102)
        let firstBufferHandle = BUFFER_HANDLE(rawValue: 0x103)
        let secondBufferHandle = BUFFER_HANDLE(rawValue: 0x105)
        let eventHandle = EVENT_HANDLE(rawValue: 0x104)
        let stream = try AmcamDataStreamRecord(
            handle: streamHandle,
            deviceHandle: deviceHandle,
            session: session
        )
        let event = AmcamEventRecord(
            handle: eventHandle,
            eventType: GenTLEventType.newBuffer.rawValue,
            source: .dataStream(streamHandle)
        )
        stream.addEvent(event)

        let payloadSize = try XCTUnwrap(
            AmcamRGB24Layout(width: 640, height: 480)
        ).payloadSize
        let firstMemory = UnsafeMutableRawPointer.allocate(
            byteCount: payloadSize,
            alignment: 64
        )
        let secondMemory = UnsafeMutableRawPointer.allocate(
            byteCount: payloadSize,
            alignment: 64
        )
        firstMemory.initializeMemory(as: UInt8.self, repeating: 0, count: payloadSize)
        secondMemory.initializeMemory(as: UInt8.self, repeating: 0, count: payloadSize)
        var cleanupCompleted = false
        defer {
            if !cleanupCompleted {
                try? stream.stop()
                try? stream.close()
                try? session.close()
            }
            firstMemory.deallocate()
            secondMemory.deallocate()
        }

        try stream.announce(
            handle: firstBufferHandle,
            memory: firstMemory,
            size: payloadSize,
            privateData: nil,
            allocatedByProvider: false
        )
        try stream.announce(
            handle: secondBufferHandle,
            memory: secondMemory,
            size: payloadSize,
            privateData: nil,
            allocatedByProvider: false
        )

        let emitterHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(emitterHandle)
        defer { if let emitterHandle { dlclose(emitterHandle) } }
        guard let symbol = dlsym(emitterHandle, "MockAmcam_EmitEvent") else {
            XCTFail("Mock SDK is missing MockAmcam_EmitEvent")
            return
        }
        let emitEvent = unsafeBitCast(symbol, to: (@convention(c) (UInt32) -> Void).self)

        try stream.queue(firstBufferHandle)
        try stream.queue(secondBufferHandle)
        try stream.start(numberToAcquire: 3)

        let expectedHandles = [
            firstBufferHandle.rawValue,
            secondBufferHandle.rawValue,
            firstBufferHandle.rawValue
        ]

        for (index, expectedSequence) in (UInt64(1)...UInt64(3)).enumerated() {
            let eventData = try stream.nextEventData(event, timeoutMilliseconds: 2_000)
            XCTAssertEqual(eventData.count, 2 * MemoryLayout<UInt>.size)
            let (deliveredHandle, deliveredUserPointer) = eventData.withUnsafeBytes {
                (
                    $0.loadUnaligned(as: UInt.self),
                    $0.loadUnaligned(
                        fromByteOffset: MemoryLayout<UInt>.size,
                        as: UInt.self
                    )
                )
            }
            XCTAssertEqual(deliveredHandle, expectedHandles[index])
            XCTAssertEqual(deliveredUserPointer, 0)

            let deliveredBuffer = BUFFER_HANDLE(rawValue: deliveredHandle)
            let deliveredMemory = deliveredHandle == firstBufferHandle.rawValue
                ? firstMemory
                : secondMemory
            XCTAssertEqual(deliveredMemory.load(as: UInt8.self), 0x5a)
            XCTAssertEqual(
                try stream.bufferInfo(deliveredBuffer, command: 1),
                .size(payloadSize)
            )
            XCTAssertEqual(
                try stream.bufferInfo(deliveredBuffer, command: 9),
                .size(payloadSize)
            )
            XCTAssertEqual(
                try stream.bufferInfo(deliveredBuffer, command: 10),
                .size(640)
            )
            XCTAssertEqual(
                try stream.bufferInfo(deliveredBuffer, command: 11),
                .size(480)
            )
            XCTAssertEqual(
                try stream.bufferInfo(deliveredBuffer, command: 16),
                .uint64(expectedSequence)
            )
            XCTAssertEqual(
                try stream.bufferInfo(deliveredBuffer, command: 4),
                .bool8(true)
            )
            XCTAssertEqual(
                try stream.bufferInfo(deliveredBuffer, command: 5),
                .bool8(false)
            )

            if expectedSequence < 3 {
                try stream.queue(deliveredBuffer)
                emitEvent(0x0004)
            }
        }

        // The final delivery schedules an asynchronous SDK stop. DSStop waits
        // for it and must still complete the GenTL acquisition lifecycle.
        try stream.stop()
        XCTAssertEqual(try stream.info(command: 8), .bool8(false))

        // Reuse the same GenTL stream, event and announced buffers after stop.
        // StartPullModeWithCallback emits a synchronous first image event, so
        // this also verifies that a completed stop released the prior callback.
        try stream.flush(operation: 2)
        try stream.start(numberToAcquire: 1)
        let restartedEventData = try stream.nextEventData(
            event,
            timeoutMilliseconds: 2_000
        )
        XCTAssertEqual(restartedEventData.count, 2 * MemoryLayout<UInt>.size)
        let restartedBufferHandle = restartedEventData.withUnsafeBytes {
            $0.loadUnaligned(as: UInt.self)
        }
        XCTAssertTrue(
            restartedBufferHandle == firstBufferHandle.rawValue ||
            restartedBufferHandle == secondBufferHandle.rawValue
        )
        try stream.stop()
        XCTAssertEqual(try stream.info(command: 8), .bool8(false))

        try stream.close()
        try session.close()
        cleanupCompleted = true
    }

    func testDisconnectPublishesDataStreamErrorEventAndCanBeStopped() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)

        let streamHandle = DS_HANDLE(rawValue: 0x301)
        let deviceHandle = DEV_HANDLE(rawValue: 0x302)
        let bufferHandle = BUFFER_HANDLE(rawValue: 0x303)
        let errorEventHandle = EVENT_HANDLE(rawValue: 0x304)
        let stream = try AmcamDataStreamRecord(
            handle: streamHandle,
            deviceHandle: deviceHandle,
            session: session
        )
        let errorEvent = AmcamEventRecord(
            handle: errorEventHandle,
            eventType: GenTLEventType.error.rawValue,
            source: .dataStream(streamHandle)
        )
        stream.addEvent(errorEvent)

        let payloadSize = try XCTUnwrap(
            AmcamRGB24Layout(width: 640, height: 480)
        ).payloadSize
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: payloadSize,
            alignment: 64
        )
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: payloadSize)
        var cleanupCompleted = false
        defer {
            if !cleanupCompleted {
                try? stream.stop()
                try? stream.close()
                try? session.close()
            }
            memory.deallocate()
        }

        try stream.announce(
            handle: bufferHandle,
            memory: memory,
            size: payloadSize,
            privateData: nil,
            allocatedByProvider: false
        )
        try stream.queue(bufferHandle)

        let emitterHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(emitterHandle)
        defer { if let emitterHandle { dlclose(emitterHandle) } }
        guard let symbol = dlsym(emitterHandle, "MockAmcam_EmitEvent") else {
            XCTFail("Mock SDK is missing MockAmcam_EmitEvent")
            return
        }
        let emitEvent = unsafeBitCast(symbol, to: (@convention(c) (UInt32) -> Void).self)

        try stream.start(numberToAcquire: GenTLConstants.infiniteCount)
        emitEvent(0x0081)

        let errorPayload = try stream.nextEventData(
            errorEvent,
            timeoutMilliseconds: 2_000
        )
        XCTAssertTrue(errorPayload.isEmpty)
        XCTAssertEqual(try stream.eventInfo(errorEvent, command: 2), .uint64(1))

        try stream.stop()
        XCTAssertEqual(try stream.info(command: 8), .bool8(false))
        try stream.close()
        try session.close()
        cleanupCompleted = true
    }

    func testTerminalStreamCloseUsesAmcamCloseWhenStopFailsAfterDisconnect() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)

        let streamHandle = DS_HANDLE(rawValue: 0x311)
        let deviceHandle = DEV_HANDLE(rawValue: 0x312)
        let bufferHandle = BUFFER_HANDLE(rawValue: 0x313)
        let errorEventHandle = EVENT_HANDLE(rawValue: 0x314)
        let stream = try AmcamDataStreamRecord(
            handle: streamHandle,
            deviceHandle: deviceHandle,
            session: session
        )
        let errorEvent = AmcamEventRecord(
            handle: errorEventHandle,
            eventType: GenTLEventType.error.rawValue,
            source: .dataStream(streamHandle)
        )
        stream.addEvent(errorEvent)

        let payloadSize = try XCTUnwrap(
            AmcamRGB24Layout(width: 640, height: 480)
        ).payloadSize
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: payloadSize,
            alignment: 64
        )
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: payloadSize)
        var cleanupCompleted = false
        defer {
            if !cleanupCompleted {
                try? stream.stop()
                try? stream.close()
                try? session.close()
            }
            memory.deallocate()
        }

        try stream.announce(
            handle: bufferHandle,
            memory: memory,
            size: payloadSize,
            privateData: nil,
            allocatedByProvider: false
        )
        try stream.queue(bufferHandle)

        let fixtureHandle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
        XCTAssertNotNil(fixtureHandle)
        defer { if let fixtureHandle { dlclose(fixtureHandle) } }

        guard let emitSymbol = dlsym(fixtureHandle, "MockAmcam_EmitEvent"),
              let setStopFailureSymbol = dlsym(fixtureHandle, "MockAmcam_SetStopFailure"),
              let setFrameIntervalSymbol = dlsym(fixtureHandle, "MockAmcam_SetAutomaticFrameInterval"),
              let callbackCountSymbol = dlsym(fixtureHandle, "MockAmcam_AsynchronousCallbackCount"),
              let stopCountSymbol = dlsym(fixtureHandle, "MockAmcam_StopCount"),
              let closeCountSymbol = dlsym(fixtureHandle, "MockAmcam_CloseCount") else {
            XCTFail("Mock SDK is missing terminal-close regression hooks")
            return
        }

        let emitEvent = unsafeBitCast(emitSymbol, to: (@convention(c) (UInt32) -> Void).self)
        let setStopFailure = unsafeBitCast(
            setStopFailureSymbol,
            to: (@convention(c) (Int32) -> Void).self
        )
        let setFrameInterval = unsafeBitCast(
            setFrameIntervalSymbol,
            to: (@convention(c) (UInt32) -> Void).self
        )
        let callbackCount = unsafeBitCast(
            callbackCountSymbol,
            to: (@convention(c) () -> UInt32).self
        )
        let stopCount = unsafeBitCast(
            stopCountSymbol,
            to: (@convention(c) () -> UInt32).self
        )
        let closeCount = unsafeBitCast(
            closeCountSymbol,
            to: (@convention(c) () -> UInt32).self
        )

        setFrameInterval(10)
        try stream.start(numberToAcquire: GenTLConstants.infiniteCount)
        for _ in 0..<20 where callbackCount() == 0 {
            usleep(10_000)
        }
        XCTAssertGreaterThan(callbackCount(), 0, "The mock SDK must own an active asynchronous callback.")

        emitEvent(0x0081)
        let errorPayload = try stream.nextEventData(
            errorEvent,
            timeoutMilliseconds: 2_000
        )
        XCTAssertTrue(errorPayload.isEmpty)

        // A disconnected camera rejects Stop but still requires Amcam_Close to
        // terminate callback delivery and release the retained callback context.
        setStopFailure(1)
        try stream.close()
        XCTAssertEqual(stopCount(), 1)
        XCTAssertEqual(closeCount(), 1)
        XCTAssertFalse(session.isStreaming)

        let callbacksAfterClose = callbackCount()
        usleep(50_000)
        XCTAssertEqual(
            callbackCount(),
            callbacksAfterClose,
            "Amcam_Close must join callback delivery before the callback context is released."
        )

        try session.close()
        XCTAssertEqual(closeCount(), 1, "Terminal close must be idempotent.")
        cleanupCompleted = true
    }

    func testUndersizedBufferIsReportedWithoutMemoryOverwrite() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)

        let streamHandle = DS_HANDLE(rawValue: 0x201)
        let deviceHandle = DEV_HANDLE(rawValue: 0x202)
        let bufferHandle = BUFFER_HANDLE(rawValue: 0x203)
        let eventHandle = EVENT_HANDLE(rawValue: 0x204)
        let stream = try AmcamDataStreamRecord(
            handle: streamHandle,
            deviceHandle: deviceHandle,
            session: session
        )
        let event = AmcamEventRecord(
            handle: eventHandle,
            eventType: GenTLEventType.newBuffer.rawValue,
            source: .dataStream(streamHandle)
        )
        stream.addEvent(event)

        let undersizedCapacity = 1_024
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: undersizedCapacity,
            alignment: 64
        )
        memory.initializeMemory(as: UInt8.self, repeating: 0xa5, count: undersizedCapacity)
        var cleanupCompleted = false
        defer {
            if !cleanupCompleted {
                try? stream.stop()
                try? stream.close()
                try? session.close()
            }
            memory.deallocate()
        }

        try stream.announce(
            handle: bufferHandle,
            memory: memory,
            size: undersizedCapacity,
            privateData: nil,
            allocatedByProvider: false
        )
        try stream.queue(bufferHandle)
        try stream.start(numberToAcquire: 1)
        _ = try stream.nextEventData(event, timeoutMilliseconds: 2_000)

        let expectedPayload = try XCTUnwrap(
            AmcamRGB24Layout(width: 640, height: 480)
        ).payloadSize
        XCTAssertEqual(memory.load(as: UInt8.self), 0xa5)
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 7), .bool8(true))
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 9), .size(0))
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 27), .size(expectedPayload))
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 29), .bool8(true))

        try stream.stop()
        try stream.close()
        try session.close()
        cleanupCompleted = true
    }


    func testDataStreamPreservesActualRowStrideForV4AndV2AtOddWidth() throws {
        for forcePlainV2 in [false, true] {
            let libraryURL = try buildMockSDK()
            let fixtureLibrary = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL)
            XCTAssertNotNil(fixtureLibrary)
            defer { if let fixtureLibrary { dlclose(fixtureLibrary) } }

            guard let enableSymbol = dlsym(fixtureLibrary, "MockAmcam_EnableOddResolution"),
                  let versionSymbol = dlsym(fixtureLibrary, "MockAmcam_PullAPIVersion") else {
                XCTFail("Mock SDK is missing odd-resolution or pull-version controls")
                return
            }
            let enableOddResolution = unsafeBitCast(enableSymbol, to: (@convention(c) () -> Void).self)
            let reportedVersion = unsafeBitCast(versionSymbol, to: (@convention(c) () -> UInt32).self)
            enableOddResolution()

            if forcePlainV2 {
                guard let maskSymbol = dlsym(fixtureLibrary, "MockAmcam_SetUnsupportedPullAPIMask") else {
                    XCTFail("Mock SDK is missing pull API capability controls")
                    return
                }
                let setMask = unsafeBitCast(maskSymbol, to: (@convention(c) (UInt32) -> Void).self)
                setMask((1 << 4) | (1 << 3) | (1 << 2))
            }

            let driver = try AmcamCameraDriver(libraryURL: libraryURL)
            let device = try XCTUnwrap(driver.discover().first)
            XCTAssertEqual(device.previewResolutions.last, AmcamResolution(index: 3, width: 641, height: 480))
            let session = try driver.open(deviceIdentifier: device.identifier)
            try session.setResolution(index: 3)

            let streamHandle = DS_HANDLE(rawValue: 0x201)
            let deviceHandle = DEV_HANDLE(rawValue: 0x202)
            let bufferHandle = BUFFER_HANDLE(rawValue: 0x203)
            let event = AmcamEventRecord(
                handle: EVENT_HANDLE(rawValue: 0x204),
                eventType: GenTLEventType.newBuffer.rawValue,
                source: .dataStream(streamHandle)
            )
            let stream = try AmcamDataStreamRecord(
                handle: streamHandle,
                deviceHandle: deviceHandle,
                session: session
            )
            stream.addEvent(event)

            let packedBytes = 641 * 480 * 3
            let announcedCapacity = try XCTUnwrap(
                AmcamRGB24Layout(width: 641, height: 480)
            ).payloadSize
            XCTAssertEqual(announcedCapacity, packedBytes + 480)
            // Both the vendor sample's V4 call (rowPitch: 0) and plain V2
            // use the SDK's default DWORD-aligned DIB row layout.
            let expectedFilledBytes = announcedCapacity
            let expectedPaddingBytes = 1
            let memory = UnsafeMutableRawPointer.allocate(byteCount: announcedCapacity, alignment: 64)
            memory.initializeMemory(as: UInt8.self, repeating: 0, count: announcedCapacity)
            var cleanupCompleted = false
            defer {
                if !cleanupCompleted {
                    try? stream.stop()
                    try? stream.close()
                    try? session.close()
                }
                memory.deallocate()
            }

            try stream.announce(
                handle: bufferHandle,
                memory: memory,
                size: announcedCapacity,
                privateData: nil,
                allocatedByProvider: false
            )
            try stream.queue(bufferHandle)
            try stream.start(numberToAcquire: 1)

            _ = try stream.nextEventData(event, timeoutMilliseconds: 2_000)
            XCTAssertEqual(reportedVersion(), forcePlainV2 ? 1 : 4)
            XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 7), .bool8(false))
            XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 9), .size(expectedFilledBytes))
            XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 10), .size(641))
            XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 11), .size(480))
            XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 14), .size(expectedPaddingBytes))
            XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 27), .size(expectedFilledBytes))
            XCTAssertEqual(try stream.bufferPartInfo(bufferHandle, command: 1), .size(expectedFilledBytes))
            XCTAssertEqual(try stream.bufferPartInfo(bufferHandle, command: 9), .size(expectedPaddingBytes))
            XCTAssertEqual(memory.load(as: UInt8.self), 0x5a)

            try stream.stop()
            try stream.close()
            try session.close()
            cleanupCompleted = true
        }
    }

    func testTypedFeatureAccessUsesSDKControlsAndVerifiedReadback() throws {
        let libraryURL = try buildMockSDK()
        let implementation = AmcamGenTLImplementation(sdkLibraryURL: libraryURL)
        try implementation.swiftGCInitLib()
        let system = try implementation.TLOpen()
        let interface = try implementation.TLOpenInterface(
            system,
            interfaceID: try implementation.TLGetInterfaceID(system, index: 0)
        )
        _ = try implementation.IFUpdateDeviceList(interface, timeout: 0)
        let deviceID = try implementation.IFGetDeviceID(interface, index: 0)
        let device = try implementation.IFOpenDevice(
            interface,
            deviceID: deviceID,
            accessFlags: GenTLDeviceAccess.exclusive.rawValue
        )
        defer {
            try? implementation.DevClose(device)
            try? implementation.IFClose(interface)
            try? implementation.TLClose(system)
            try? implementation.swiftGCCloseLib()
        }

        let descriptors = try implementation.featureDescriptors(for: GenTLFeatureDeviceHandle(rawValue: device.rawValue))
        let byName = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.name, $0) })
        let auto = try XCTUnwrap(byName["ExposureAuto"])
        let exposure = try XCTUnwrap(byName["ExposureTime"])
        let gain = try XCTUnwrap(byName["AmcamAnalogGainPercent"])

        XCTAssertEqual(auto.kind, .enumeration)
        XCTAssertEqual(auto.enumerationValues, ["Off", "Once", "Continuous"])
        XCTAssertTrue(auto.isAvailable)
        XCTAssertTrue(auto.isWritable)

        XCTAssertEqual(exposure.kind, .integer)
        XCTAssertEqual(exposure.unit, "us")
        XCTAssertEqual(exposure.numericRange?.minimum, 100)
        XCTAssertEqual(exposure.numericRange?.maximum, 1_000_000)
        XCTAssertTrue(exposure.isAvailable)
        XCTAssertFalse(exposure.isWritable, "Manual exposure must remain read-only while auto exposure is active.")

        XCTAssertEqual(gain.kind, .integer)
        XCTAssertEqual(gain.unit, "%")
        XCTAssertEqual(gain.numericRange?.minimum, 100)
        XCTAssertEqual(gain.numericRange?.maximum, 800)
        XCTAssertTrue(gain.isAvailable)

        XCTAssertEqual(
            try implementation.readFeature("ExposureAuto", from: GenTLFeatureDeviceHandle(rawValue: device.rawValue)),
            .enumeration("Continuous")
        )
        try implementation.writeFeature(.enumeration("Off"), named: "ExposureAuto", to: GenTLFeatureDeviceHandle(rawValue: device.rawValue))
        let manualExposure = try XCTUnwrap(
            try implementation.featureDescriptors(for: GenTLFeatureDeviceHandle(rawValue: device.rawValue))
                .first { $0.name == "ExposureTime" }
        )
        XCTAssertTrue(manualExposure.isWritable)

        XCTAssertThrowsError(
            try implementation.writeFeature(.floatingPoint(12_000), named: "ExposureTime", to: GenTLFeatureDeviceHandle(rawValue: device.rawValue))
        ) { error in
            XCTAssertEqual(
                error as? GenTLFeatureAccessError,
                .valueTypeMismatch(feature: "ExposureTime", expected: .integer, actual: .floatingPoint)
            )
        }
        XCTAssertThrowsError(
            try implementation.writeFeature(.enumeration("Automatic"), named: "ExposureAuto", to: GenTLFeatureDeviceHandle(rawValue: device.rawValue))
        ) { error in
            XCTAssertEqual(
                error as? GenTLFeatureAccessError,
                .invalidValue("ExposureAuto accepts Off, Once, or Continuous.")
            )
        }

        try implementation.writeFeature(.integer(12_000), named: "ExposureTime", to: GenTLFeatureDeviceHandle(rawValue: device.rawValue))
        try implementation.writeFeature(.integer(200), named: "AmcamAnalogGainPercent", to: GenTLFeatureDeviceHandle(rawValue: device.rawValue))

        XCTAssertEqual(try implementation.readFeature("ExposureTime", from: GenTLFeatureDeviceHandle(rawValue: device.rawValue)), .integer(12_000))
        XCTAssertEqual(try implementation.readFeature("AmcamAnalogGainPercent", from: GenTLFeatureDeviceHandle(rawValue: device.rawValue)), .integer(200))
    }

    func testFeatureWritabilityTracksAcquisitionState() throws {
        let libraryURL = try buildMockSDK()
        let implementation = AmcamGenTLImplementation(sdkLibraryURL: libraryURL)
        try implementation.swiftGCInitLib()
        let system = try implementation.TLOpen()
        let interface = try implementation.TLOpenInterface(
            system,
            interfaceID: try implementation.TLGetInterfaceID(system, index: 0)
        )
        _ = try implementation.IFUpdateDeviceList(interface, timeout: 0)
        let deviceID = try implementation.IFGetDeviceID(interface, index: 0)
        let device = try implementation.IFOpenDevice(
            interface,
            deviceID: deviceID,
            accessFlags: GenTLDeviceAccess.exclusive.rawValue
        )
        let featureHandle = GenTLFeatureDeviceHandle(rawValue: device.rawValue)
        var stream: DS_HANDLE?
        defer {
            if let stream {
                try? implementation.DSStopAcquisition(
                    stream,
                    flags: GenTLAcquisitionStopFlag.normal.rawValue
                )
                try? implementation.DSClose(stream)
            }
            try? implementation.DevClose(device)
            try? implementation.IFClose(interface)
            try? implementation.TLClose(system)
            try? implementation.swiftGCCloseLib()
        }

        let initial = try implementation.featureDescriptors(for: featureHandle)
        let initialByName = Dictionary(uniqueKeysWithValues: initial.map { ($0.name, $0) })
        XCTAssertTrue(initialByName["AmcamResolutionIndex"]?.isWritable == true)
        XCTAssertTrue(initialByName["AmcamPixelFormat"]?.isWritable == true)

        let streamID = try implementation.DevGetDataStreamID(device, index: 0)
        let openedStream = try implementation.DevOpenDataStream(device, dataStreamID: streamID)
        stream = openedStream
        _ = try implementation.DSAllocAndAnnounceBuffer(
            openedStream,
            size: 640 * 480 * 3,
            privateData: nil
        )
        let buffer = try implementation.DSGetBufferID(openedStream, index: 0)
        try implementation.DSQueueBuffer(openedStream, buffer: buffer)
        try implementation.DSStartAcquisition(
            openedStream,
            flags: GenTLAcquisitionStartFlag.normal.rawValue,
            numberToAcquire: GenTLConstants.infiniteCount
        )

        let streaming = try implementation.featureDescriptors(for: featureHandle)
        let streamingByName = Dictionary(uniqueKeysWithValues: streaming.map { ($0.name, $0) })
        XCTAssertFalse(streamingByName["AmcamResolutionIndex"]?.isWritable ?? true)
        XCTAssertFalse(streamingByName["AmcamPixelFormat"]?.isWritable ?? true)

        try implementation.DSStopAcquisition(
            openedStream,
            flags: GenTLAcquisitionStopFlag.normal.rawValue
        )
        let stopped = try implementation.featureDescriptors(for: featureHandle)
        let stoppedByName = Dictionary(uniqueKeysWithValues: stopped.map { ($0.name, $0) })
        XCTAssertTrue(stoppedByName["AmcamResolutionIndex"]?.isWritable == true)
        XCTAssertTrue(stoppedByName["AmcamPixelFormat"]?.isWritable == true)

        try implementation.DSClose(openedStream)
        stream = nil
    }

    func testAllDiscardFlushMakesQueuedProviderBuffersRevocable() throws {
        let libraryURL = try buildMockSDK()
        let implementation = AmcamGenTLImplementation(sdkLibraryURL: libraryURL)
        try implementation.swiftGCInitLib()
        let system = try implementation.TLOpen()
        let interface = try implementation.TLOpenInterface(
            system,
            interfaceID: try implementation.TLGetInterfaceID(system, index: 0)
        )
        _ = try implementation.IFUpdateDeviceList(interface, timeout: 0)
        let deviceID = try implementation.IFGetDeviceID(interface, index: 0)
        let device = try implementation.IFOpenDevice(
            interface,
            deviceID: deviceID,
            accessFlags: GenTLDeviceAccess.exclusive.rawValue
        )
        var stream: DS_HANDLE?
        defer {
            if let stream {
                try? implementation.DSFlushQueue(
                    stream,
                    operation: GenTLQueueOperation.allDiscard.rawValue
                )
                try? implementation.DSClose(stream)
            }
            try? implementation.DevClose(device)
            try? implementation.IFClose(interface)
            try? implementation.TLClose(system)
            try? implementation.swiftGCCloseLib()
        }

        let streamID = try implementation.DevGetDataStreamID(device, index: 0)
        let openedStream = try implementation.DevOpenDataStream(device, dataStreamID: streamID)
        stream = openedStream

        _ = try implementation.DSAllocAndAnnounceBuffer(
            openedStream,
            size: 640 * 480 * 3,
            privateData: nil
        )
        let buffer = try implementation.DSGetBufferID(openedStream, index: 0)
        try implementation.DSQueueBuffer(openedStream, buffer: buffer)

        // ALL_TO_INPUT leaves the buffer referenced by the input pool, so it
        // must not yet be revocable.
        try implementation.DSFlushQueue(
            openedStream,
            operation: GenTLQueueOperation.allToInput.rawValue
        )
        XCTAssertThrowsError(try implementation.DSRevokeBuffer(openedStream, buffer: buffer))

        // ALL_DISCARD clears both input and output pools and enables revocation.
        try implementation.DSFlushQueue(
            openedStream,
            operation: GenTLQueueOperation.allDiscard.rawValue
        )

        // GenTL allows either output pointer to be NULL. This is the exact
        // raw-ABI call issued by GenTLAcquisitionSession.close().
        let rawStream = UnsafeMutableRawPointer(bitPattern: openedStream.rawValue)
        let rawBuffer = UnsafeMutableRawPointer(bitPattern: buffer.rawValue)
        let revokeStatus = implementation.DSRevokeBuffer(
            rawStream,
            rawBuffer,
            nil,
            nil
        )
        XCTAssertEqual(
            revokeStatus,
            GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS),
            "DSRevokeBuffer must accept NULL ppBuffer and ppPrivate outputs."
        )

        try implementation.DSClose(openedStream)
        stream = nil
    }

    func testTypedFeatureAccessExposesOnlyProbedCameraControlsAndVerifiesWrites() throws {
        let libraryURL = try buildMockSDK()
        let implementation = AmcamGenTLImplementation(sdkLibraryURL: libraryURL)
        try implementation.swiftGCInitLib()
        let system = try implementation.TLOpen()
        let interface = try implementation.TLOpenInterface(
            system,
            interfaceID: try implementation.TLGetInterfaceID(system, index: 0)
        )
        _ = try implementation.IFUpdateDeviceList(interface, timeout: 0)
        let deviceID = try implementation.IFGetDeviceID(interface, index: 0)
        let device = try implementation.IFOpenDevice(
            interface,
            deviceID: deviceID,
            accessFlags: GenTLDeviceAccess.exclusive.rawValue
        )
        let handle = GenTLFeatureDeviceHandle(rawValue: device.rawValue)
        defer {
            try? implementation.DevClose(device)
            try? implementation.IFClose(interface)
            try? implementation.TLClose(system)
            try? implementation.swiftGCCloseLib()
        }

        let descriptors = try implementation.featureDescriptors(for: handle)
        let byName = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.name, $0) })
        let colorMatrix = try XCTUnwrap(byName["AmcamColorMatrixEnabled"])
        let pixelFormat = try XCTUnwrap(byName["AmcamPixelFormat"])
        let temperature = try XCTUnwrap(byName["AmcamWhiteBalanceTemperature"])
        let tint = try XCTUnwrap(byName["AmcamWhiteBalanceTint"])
        let fixedRate = try XCTUnwrap(byName["AmcamFixedFrameRate"])
        let speedLevel = try XCTUnwrap(byName["AmcamFrameSpeedLevel"])
        let resolution = try XCTUnwrap(byName["AmcamResolutionIndex"])
        let rgbGain = try XCTUnwrap(byName["AmcamWhiteBalanceRGBGain"])

        XCTAssertEqual(colorMatrix.kind, .boolean)
        XCTAssertTrue(colorMatrix.isAvailable)
        XCTAssertTrue(colorMatrix.isReadable)
        XCTAssertTrue(colorMatrix.isWritable)

        XCTAssertEqual(pixelFormat.kind, .enumeration)
        XCTAssertEqual(pixelFormat.enumerationValues, ["0", "8"])
        XCTAssertTrue(pixelFormat.isAvailable)
        XCTAssertTrue(pixelFormat.isWritable)

        XCTAssertEqual(temperature.kind, .integer)
        XCTAssertEqual(temperature.unit, "K")
        XCTAssertEqual(temperature.numericRange?.minimum, 2_000)
        XCTAssertEqual(temperature.numericRange?.maximum, 15_000)
        XCTAssertTrue(temperature.isAvailable)

        XCTAssertEqual(tint.kind, .integer)
        XCTAssertEqual(tint.numericRange?.minimum, 200)
        XCTAssertEqual(tint.numericRange?.maximum, 2_500)
        XCTAssertTrue(tint.isAvailable)

        XCTAssertEqual(rgbGain.kind, .integerVector)
        XCTAssertEqual(rgbGain.elementCount, 3)
        XCTAssertTrue(rgbGain.isAvailable)
        XCTAssertEqual(
            try implementation.readFeature("AmcamWhiteBalanceRGBGain", from: handle),
            .integerVector([100, 100, 100])
        )

        XCTAssertEqual(fixedRate.kind, .floatingPoint)
        XCTAssertEqual(fixedRate.unit, "fps")
        XCTAssertEqual(fixedRate.numericRange?.minimum, 0.1)
        XCTAssertEqual(fixedRate.numericRange?.maximum, 30.0)
        XCTAssertEqual(fixedRate.numericRange?.increment, 0.1)
        XCTAssertTrue(fixedRate.isAvailable)

        XCTAssertFalse(speedLevel.isAvailable, "The mock camera does not advertise a usable speed-level control.")
        XCTAssertEqual(resolution.kind, .enumeration)
        XCTAssertEqual(
            resolution.enumerationValues,
            ["0:2560x1922", "1:1280x960", "2:640x480"]
        )
        XCTAssertEqual(
            try implementation.readFeature("AmcamResolutionIndex", from: handle),
            .enumeration("2:640x480")
        )

        try implementation.writeFeature(.boolean(false), named: "AmcamColorMatrixEnabled", to: handle)
        try implementation.writeFeature(.enumeration("0"), named: "AmcamPixelFormat", to: handle)
        try implementation.writeFeature(.integer(7_200), named: "AmcamWhiteBalanceTemperature", to: handle)
        try implementation.writeFeature(.integer(1_250), named: "AmcamWhiteBalanceTint", to: handle)
        try implementation.writeFeature(.integerVector([125, 130, 140]), named: "AmcamWhiteBalanceRGBGain", to: handle)
        try implementation.writeFeature(.floatingPoint(12.3), named: "AmcamFixedFrameRate", to: handle)
        try implementation.writeFeature(.enumeration("1:1280x960"), named: "AmcamResolutionIndex", to: handle)

        XCTAssertEqual(try implementation.readFeature("AmcamColorMatrixEnabled", from: handle), .boolean(false))
        XCTAssertEqual(try implementation.readFeature("AmcamPixelFormat", from: handle), .enumeration("0"))
        XCTAssertEqual(try implementation.readFeature("AmcamWhiteBalanceTemperature", from: handle), .integer(7_200))
        XCTAssertEqual(try implementation.readFeature("AmcamWhiteBalanceTint", from: handle), .integer(1_250))
        XCTAssertEqual(try implementation.readFeature("AmcamWhiteBalanceRGBGain", from: handle), .integerVector([125, 130, 140]))
        XCTAssertEqual(try implementation.readFeature("AmcamFixedFrameRate", from: handle), .floatingPoint(12.3))
        XCTAssertEqual(
            try implementation.readFeature("AmcamResolutionIndex", from: handle),
            .enumeration("1:1280x960")
        )

        XCTAssertThrowsError(
            try implementation.writeFeature(.enumeration("99"), named: "AmcamPixelFormat", to: handle)
        )
        XCTAssertThrowsError(
            try implementation.writeFeature(.integer(16_000), named: "AmcamWhiteBalanceTemperature", to: handle)
        )
    }

    private func buildMockSDK(disableV4: Bool = false, disableV3: Bool = false, disableRowPitchV2: Bool = false) throws -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = packageRoot
            .appendingPathComponent("Tests/AmcamGenTLTests/Fixtures/MockAmcamSDK.c")
        let includeDirectory = packageRoot.appendingPathComponent("Sources/AmcamABI/include")
        let output = temporaryDirectory.appendingPathComponent("libMockAmcam.dylib")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        var compilerArguments = [
            "-dynamiclib",
            "-fPIC",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-I", includeDirectory.path
        ]
        if disableV4 { compilerArguments.append("-DMOCK_DISABLE_V4") }
        if disableV3 { compilerArguments.append("-DMOCK_DISABLE_V3") }
        if disableRowPitchV2 { compilerArguments.append("-DMOCK_DISABLE_ROW_PITCH_V2") }
        compilerArguments += [source.path, "-o", output.path]
        process.arguments = compilerArguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let diagnostics = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "Mock SDK compilation failed:\n\(diagnostics)")
        return output
    }
}
