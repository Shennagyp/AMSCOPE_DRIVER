import CryptoKit
import Darwin
import Foundation
@_spi(BackendConvenience) import GenTLAPI
@_spi(BackendFactory) import AmcamGenTL

private struct Options {
    let sdkURL: URL
    let deviceIndex: Int
    let frameCount: Int
    let timeoutMilliseconds: UInt64
    let outputURL: URL?

    static func parse(_ arguments: [String]) throws -> Options {
        var sdkPath: String?
        var deviceIndex = 0
        var frameCount = 10
        var timeoutMilliseconds: UInt64 = 5_000
        var outputPath: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard index + 1 < arguments.count else {
                throw ProbeError.usage("Missing value after \(argument).")
            }
            let value = arguments[index + 1]
            switch argument {
            case "--sdk":
                sdkPath = value
            case "--device-index":
                guard let parsed = Int(value), parsed >= 0 else {
                    throw ProbeError.usage("--device-index must be a non-negative integer.")
                }
                deviceIndex = parsed
            case "--frames":
                guard let parsed = Int(value), (1...10_000).contains(parsed) else {
                    throw ProbeError.usage("--frames must be between 1 and 10000.")
                }
                frameCount = parsed
            case "--timeout-ms":
                guard let parsed = UInt64(value), parsed > 0 else {
                    throw ProbeError.usage("--timeout-ms must be a positive integer.")
                }
                timeoutMilliseconds = parsed
            case "--output":
                outputPath = value
            default:
                throw ProbeError.usage("Unknown option: \(argument).")
            }
            index += 2
        }

        guard let sdkPath, !sdkPath.isEmpty else {
            throw ProbeError.usage("Provide the Amcam SDK library with --sdk /path/to/libamcam.dylib.")
        }
        let sdkURL = URL(fileURLWithPath: sdkPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: sdkURL.path) else {
            throw ProbeError.sdkNotFound(sdkURL.path)
        }

        return Options(
            sdkURL: sdkURL,
            deviceIndex: deviceIndex,
            frameCount: frameCount,
            timeoutMilliseconds: timeoutMilliseconds,
            outputURL: outputPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        )
    }

    static let usage = """
    amcam-camera-probe — macOS AmScope camera hardware smoke test

    Usage:
      amcam-camera-probe --sdk /path/to/libamcam.dylib [options]

    Options:
      --sdk PATH          Vendor Amcam SDK dynamic library (required)
      --device-index N   Device index from SDK enumeration (default: 0)
      --frames N         Number of frames to acquire (default: 10; max: 10000)
      --timeout-ms N     Per-frame event timeout (default: 5000)
      --output PATH      Write the last complete frame as an RGB PPM image
      --help              Show this help

    The probe reports device discovery, dimensions, frame payload, sequence,
    timestamp, SHA-256 and observed acquisition rate. It does not alter exposure,
    gain, or camera frame-rate settings.
    """
}

private enum ProbeError: Error, LocalizedError {
    case usage(String)
    case sdkNotFound(String)
    case noInterface
    case noDevices
    case invalidDeviceIndex(Int, count: Int)
    case noDataStream
    case invalidInfo(String)
    case invalidEventPayload
    case unexpectedBuffer(UInt, expected: UInt)
    case incompleteFrame
    case invalidFrameLayout
    case invalidFramePointer

    var errorDescription: String? {
        switch self {
        case .usage(let message): return "\(message)\n\n\(Options.usage)"
        case .sdkNotFound(let path): return "Amcam SDK library not found: \(path)"
        case .noInterface: return "The Amcam SDK exposed no GenTL-compatible interface."
        case .noDevices: return "The Amcam SDK did not enumerate a camera."
        case .invalidDeviceIndex(let index, let count):
            return "Device index \(index) is outside the enumerated device range (0..<\(count))."
        case .noDataStream: return "The opened camera exposes no data stream."
        case .invalidInfo(let message): return "Unexpected GenTL information value: \(message)"
        case .invalidEventPayload: return "The New Buffer event payload is shorter than an opaque handle."
        case .unexpectedBuffer(let actual, let expected):
            return "The New Buffer event returned handle \(actual), expected \(expected)."
        case .incompleteFrame: return "The camera delivered an incomplete or undersized frame."
        case .invalidFrameLayout: return "The reported RGB24 frame layout is invalid or overflows."
        case .invalidFramePointer: return "The SDK returned a null frame-buffer pointer."
        }
    }
}

@main
struct AmcamCameraProbe {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--help") {
            print(Options.usage)
            return
        }

        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            try run(options)
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ options: Options) throws {
        let backend = AmcamGenTLImplementation(sdkLibraryURL: options.sdkURL)

        var initialized = false
        var system: TL_HANDLE?
        var interface: IF_HANDLE?
        var device: DEV_HANDLE?
        var stream: DS_HANDLE?
        var eventRegistered = false
        var acquisitionStarted = false

        defer {
            if let stream {
                if acquisitionStarted {
                    try? backend.DSStopAcquisition(
                        stream,
                        flags: GenTLAcquisitionStopFlag.normal.rawValue
                    )
                }
                if eventRegistered {
                    try? backend.GCUnregisterEvent(
                        .dataStream(stream),
                        eventType: GenTLEventType.newBuffer.rawValue
                    )
                }
                try? backend.DSClose(stream)
            }
            if let device { try? backend.DevClose(device) }
            if let interface { try? backend.IFClose(interface) }
            if let system { try? backend.TLClose(system) }
            if initialized { try? backend.swiftGCCloseLib() }
        }

        try backend.swiftGCInitLib()
        initialized = true
        let sdkVersion = try readString(backend.GCGetInfo(command: GenTLInfoCommand.TransportLayer.version.rawValue))
        print("SDK version: \(sdkVersion)")
        let systemHandle = try backend.TLOpen()
        system = systemHandle

        let interfaceCount = try backend.TLGetNumInterfaces(systemHandle)
        guard interfaceCount > 0 else { throw ProbeError.noInterface }
        let interfaceID = try backend.TLGetInterfaceID(systemHandle, index: 0)
        let interfaceHandle = try backend.TLOpenInterface(systemHandle, interfaceID: interfaceID)
        interface = interfaceHandle

        _ = try backend.IFUpdateDeviceList(interfaceHandle, timeout: options.timeoutMilliseconds)
        let deviceCount = Int(try backend.IFGetNumDevices(interfaceHandle))
        guard deviceCount > 0 else { throw ProbeError.noDevices }
        guard options.deviceIndex < deviceCount else {
            throw ProbeError.invalidDeviceIndex(options.deviceIndex, count: deviceCount)
        }

        print("SDK: \(options.sdkURL.path)")
        print("Interface: \(interfaceID)")
        print("Discovered devices: \(deviceCount)")
        for index in 0..<deviceCount {
            let identifier = try backend.IFGetDeviceID(interfaceHandle, index: UInt32(index))
            print("  [\(index)] \(identifier)")
        }

        let deviceID = try backend.IFGetDeviceID(
            interfaceHandle,
            index: UInt32(options.deviceIndex)
        )
        let modelName = try readString(
            backend.IFGetDeviceInfo(
                interfaceHandle,
                deviceID: deviceID,
                command: GenTLInfoCommand.Device.model.rawValue
            )
        )
        let displayName = try readString(
            backend.IFGetDeviceInfo(
                interfaceHandle,
                deviceID: deviceID,
                command: GenTLInfoCommand.Device.displayName.rawValue
            )
        )
        print("Selected camera: \(displayName) (\(modelName))")
        let deviceHandle = try backend.IFOpenDevice(
            interfaceHandle,
            deviceID: deviceID,
            accessFlags: GenTLDeviceAccess.exclusive.rawValue
        )
        device = deviceHandle
        print("Opened device: \(deviceID)")

        let streamCount = try backend.DevGetNumDataStreams(deviceHandle)
        guard streamCount > 0 else { throw ProbeError.noDataStream }
        let streamID = try backend.DevGetDataStreamID(deviceHandle, index: 0)
        let streamHandle = try backend.DevOpenDataStream(deviceHandle, dataStreamID: streamID)
        stream = streamHandle

        let payloadSize = try readSize(
            backend,
            stream: streamHandle,
            buffer: nil,
            command: GenTLInfoCommand.Stream.payloadSize.rawValue
        )
        guard payloadSize > 0 else {
            throw ProbeError.invalidInfo("stream payload size \(payloadSize)")
        }

        let eventHandle = try backend.GCRegisterEvent(
            .dataStream(streamHandle),
            eventType: GenTLEventType.newBuffer.rawValue
        )
        eventRegistered = true

        let bufferHandle = try backend.DSAllocAndAnnounceBuffer(
            streamHandle,
            size: payloadSize,
            privateData: nil
        )
        try backend.DSQueueBuffer(streamHandle, buffer: bufferHandle)

        print("Data stream: \(streamID)")
        print("Announced buffer: \(payloadSize) bytes")
        print("Acquiring \(options.frameCount) frame(s)...")

        let startTime = Date()
        try backend.DSStartAcquisition(
            streamHandle,
            flags: GenTLAcquisitionStartFlag.normal.rawValue,
            numberToAcquire: UInt64(options.frameCount)
        )
        acquisitionStarted = true

        var completeFrames = 0
        var incompleteFrames = 0
        var firstDeviceTimestamp: UInt64?
        var lastDeviceTimestamp: UInt64?
        var lastPPM: Data?

        for frameIndex in 0..<options.frameCount {
            let eventData = try backend.EventGetData(
                eventHandle,
                timeout: options.timeoutMilliseconds
            )
            guard eventData.count >= MemoryLayout<UInt>.size else {
                throw ProbeError.invalidEventPayload
            }
            let deliveredHandle = eventData.withUnsafeBytes {
                $0.loadUnaligned(as: UInt.self)
            }
            guard deliveredHandle == bufferHandle.rawValue else {
                throw ProbeError.unexpectedBuffer(
                    deliveredHandle,
                    expected: bufferHandle.rawValue
                )
            }

            let width = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.width.rawValue
            )
            let height = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.height.rawValue
            )
            let sizeFilled = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.sizeFilled.rawValue
            )
            let rowPadding = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.xPadding.rawValue
            )
            let isIncomplete = try readBool(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.isIncomplete.rawValue
            )
            let sequence = try readUInt64(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.frameID.rawValue
            )
            let timestamp = try readUInt64(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.timestamp.rawValue
            )
            guard !isIncomplete else {
                incompleteFrames += 1
                print("Frame \(frameIndex + 1): INCOMPLETE")
                if frameIndex + 1 < options.frameCount {
                    try backend.DSQueueBuffer(streamHandle, buffer: bufferHandle)
                }
                continue
            }

            if timestamp > 0 {
                if firstDeviceTimestamp == nil { firstDeviceTimestamp = timestamp }
                lastDeviceTimestamp = timestamp
            }

            let (packedRowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 3)
            let (bytesPerRow, strideOverflow) = packedRowBytes.addingReportingOverflow(rowPadding)
            let (requiredBytes, payloadOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
            guard width > 0, height > 0, rowPadding >= 0,
                  !rowOverflow, !strideOverflow, !payloadOverflow,
                  sizeFilled >= requiredBytes, requiredBytes > 0 else {
                throw ProbeError.invalidFrameLayout
            }

            guard case .pointer(let rawPointer) = try backend.DSGetBufferInfo(
                streamHandle,
                buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.base.rawValue
            ), let pointer = UnsafeRawPointer(bitPattern: rawPointer) else {
                throw ProbeError.invalidFramePointer
            }
            let frameData = Data(bytes: pointer, count: sizeFilled)
            let digest = SHA256.hash(data: frameData)
                .map { String(format: "%02x", $0) }
                .joined()
            completeFrames += 1
            print(
                "Frame \(frameIndex + 1): \(width)x\(height), " +
                "\(sizeFilled) bytes, stride \(bytesPerRow), " +
                "sequence \(sequence), timestamp \(timestamp) us, " +
                "SHA-256 \(digest)"
            )

            if options.outputURL != nil {
                var pixels = Data()
                pixels.reserveCapacity(packedRowBytes * height)
                for row in 0..<height {
                    let start = row * bytesPerRow
                    pixels.append(contentsOf: frameData[start..<(start + packedRowBytes)])
                }
                var ppm = Data("P6\n\(width) \(height)\n255\n".utf8)
                ppm.append(pixels)
                lastPPM = ppm
            }

            if frameIndex + 1 < options.frameCount {
                try backend.DSQueueBuffer(streamHandle, buffer: bufferHandle)
            }
        }

        let elapsed = max(Date().timeIntervalSince(startTime), 0.000_001)
        try backend.DSStopAcquisition(
            streamHandle,
            flags: GenTLAcquisitionStopFlag.normal.rawValue
        )
        acquisitionStarted = false

        if let outputURL = options.outputURL, let lastPPM {
            try lastPPM.write(to: outputURL, options: .atomic)
            print("Last complete frame written: \(outputURL.path)")
        }

        print(
            "Result: \(completeFrames) complete, \(incompleteFrames) incomplete, " +
            String(format: "%.2f", Double(completeFrames) / elapsed) + " host-loop FPS, " +
            String(format: "%.3f", elapsed) + " seconds"
        )
        if let firstDeviceTimestamp, let lastDeviceTimestamp,
           lastDeviceTimestamp > firstDeviceTimestamp, completeFrames > 1 {
            let deviceElapsedMicroseconds = lastDeviceTimestamp - firstDeviceTimestamp
            let deviceFPS = Double(completeFrames - 1) * 1_000_000.0 /
                Double(deviceElapsedMicroseconds)
            print("Camera timestamp rate: \(String(format: "%.2f", deviceFPS)) FPS")
        } else {
            print("Camera timestamp rate: unavailable")
        }
        if incompleteFrames > 0 {
            throw ProbeError.incompleteFrame
        }
    }

    private static func readString(_ value: GenTLInfoValue) throws -> String {
        guard case .string(let string) = value else {
            throw ProbeError.invalidInfo("expected string, got \(value)")
        }
        return string
    }

    private static func readSize(
        _ backend: AmcamGenTLImplementation,
        stream: DS_HANDLE,
        buffer: BUFFER_HANDLE?,
        command: Int32
    ) throws -> Int {
        let value: GenTLInfoValue
        if let buffer {
            value = try backend.DSGetBufferInfo(stream, buffer: buffer, command: command)
        } else {
            value = try backend.DSGetInfo(stream, command: command)
        }
        guard case .size(let size) = value else {
            throw ProbeError.invalidInfo("expected size for command \(command), got \(value)")
        }
        return size
    }

    private static func readBool(
        _ backend: AmcamGenTLImplementation,
        stream: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        command: Int32
    ) throws -> Bool {
        guard case .bool8(let value) = try backend.DSGetBufferInfo(
            stream, buffer: buffer, command: command
        ) else {
            throw ProbeError.invalidInfo("expected bool8 for command \(command)")
        }
        return value
    }

    private static func readUInt64(
        _ backend: AmcamGenTLImplementation,
        stream: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        command: Int32
    ) throws -> UInt64 {
        guard case .uint64(let value) = try backend.DSGetBufferInfo(
            stream, buffer: buffer, command: command
        ) else {
            throw ProbeError.invalidInfo("expected uint64 for command \(command)")
        }
        return value
    }
}
