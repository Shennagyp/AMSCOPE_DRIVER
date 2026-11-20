import Darwin
import Foundation
import XCTest
@_spi(BackendConvenience) import GenTLAPI
@testable import AmcamGenTL

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

            try session.stop()
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
        try session.close()
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
        XCTAssertTrue(capabilities.availability(of: .pixelFormatSelection).available)
        var controls = try session.readControls()
        XCTAssertEqual(controls.whiteBalance?.temperature, 6503)
        XCTAssertEqual(controls.whiteBalance?.tint, 1000)
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
        XCTAssertEqual(try session.readControls().exposure.readbackMicroseconds, 20_000)

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

    private func buildMockSDK() throws -> URL {
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
        process.arguments = [
            "-dynamiclib",
            "-fPIC",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-I", includeDirectory.path,
            source.path,
            "-o", output.path
        ]
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
