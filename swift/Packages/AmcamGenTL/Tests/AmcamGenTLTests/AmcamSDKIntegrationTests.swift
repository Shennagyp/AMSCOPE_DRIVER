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
            AmcamResolution(index: 0, width: 640, height: 480),
            AmcamResolution(index: 1, width: 320, height: 240)
        ])

        let session = try driver.open(deviceIdentifier: devices[0].identifier)
        XCTAssertEqual(session.currentDimensions().width, 640)
        XCTAssertEqual(session.currentDimensions().height, 480)
        XCTAssertEqual(session.currentResolution(), AmcamResolution(index: 0, width: 640, height: 480))

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


    func testDataStreamQueuesAndDeliversACompleteRGBFrame() throws {
        let libraryURL = try buildMockSDK()
        let driver = try AmcamCameraDriver(libraryURL: libraryURL)
        let device = try XCTUnwrap(driver.discover().first)
        let session = try driver.open(deviceIdentifier: device.identifier)

        let streamHandle = DS_HANDLE(rawValue: 0x101)
        let deviceHandle = DEV_HANDLE(rawValue: 0x102)
        let bufferHandle = BUFFER_HANDLE(rawValue: 0x103)
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
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: payloadSize,
            alignment: 64
        )
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: payloadSize)
        defer { memory.deallocate() }

        try stream.announce(
            handle: bufferHandle,
            memory: memory,
            size: payloadSize,
            privateData: nil,
            allocatedByProvider: false
        )
        try stream.queue(bufferHandle)
        try stream.start(numberToAcquire: 1)

        let eventData = try stream.nextEventData(event, timeoutMilliseconds: 2_000)
        XCTAssertEqual(eventData.count, 2 * MemoryLayout<UInt>.size)
        let deliveredHandle = eventData.withUnsafeBytes {
            $0.loadUnaligned(as: UInt.self)
        }
        XCTAssertEqual(deliveredHandle, bufferHandle.rawValue)

        XCTAssertEqual(memory.load(as: UInt8.self), 0x5a)
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 9), .size(payloadSize))
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 10), .size(640))
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 11), .size(480))
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 16), .uint64(1))
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 4), .bool8(true))
        XCTAssertEqual(try stream.bufferInfo(bufferHandle, command: 5), .bool8(false))

        // A finite acquisition auto-stops the SDK. DSStop must still complete
        // the GenTL acquisition lifecycle and release its outstanding state.
        try stream.stop()
        try stream.close()
        try session.close()
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
