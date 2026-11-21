import CryptoKit
import Darwin
import Foundation
import AmcamCameraProbeSupport
@_spi(BackendConvenience) import GenTLAPI
@_spi(BackendFactory) import AmcamGenTL

private struct Options {
    let sdkURL: URL
    let deviceIndex: Int
    let frameCount: Int
    let timeoutMilliseconds: UInt64
    let outputURL: URL?
    let jsonOutput: Bool

    static func parse(_ arguments: [String]) throws -> Options {
        var sdkPath: String?
        var deviceIndex = 0
        var frameCount = 10
        var timeoutMilliseconds: UInt64 = 5_000
        var outputPath: String?
        var jsonOutput = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--json" {
                jsonOutput = true
                index += 1
                continue
            }
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
            outputURL: outputPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
            jsonOutput: jsonOutput
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
      --json              Write a versioned diagnostic report as JSON to stdout
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
    case cameraErrorEvent
    case unknownBuffer(UInt)
    case unexpectedUserPointer(UInt)
    case incompleteFrame
    case invalidFrameLayout
    case invalidPixelFormat(UInt64)
    case invalidFramePointer


    var diagnosticStage: AmcamProbeStage? {
        switch self {
        case .usage:
            return .argumentParsing
        case .sdkNotFound:
            return .sdkLibraryValidation
        case .noInterface:
            return .interfaceDiscovery
        case .noDevices, .invalidDeviceIndex:
            return .deviceDiscovery
        case .noDataStream:
            return .dataStreamOpen
        case .cameraErrorEvent:
            return .frameRead
        case .invalidEventPayload, .unknownBuffer, .unexpectedUserPointer,
             .incompleteFrame, .invalidFrameLayout, .invalidPixelFormat,
             .invalidFramePointer:
            return .frameValidation
        case .invalidInfo:
            return nil
        }
    }

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
        case .invalidEventPayload: return "The New Buffer event payload does not match the backend's two-word buffer-handle/user-pointer layout."
        case .cameraErrorEvent: return "The Amcam SDK reported a camera error or disconnection during acquisition."
        case .unknownBuffer(let actual):
            return "The New Buffer event returned an unannounced buffer handle: \(actual)."
        case .unexpectedUserPointer(let actual):
            return "The New Buffer event returned unexpected user pointer \(actual); the probe announced buffers with nil user pointers."
        case .incompleteFrame: return "The camera delivered an incomplete or undersized frame."
        case .invalidFrameLayout: return "The reported RGB24 frame layout is invalid, exceeds the announced buffer, or overflows."
        case .invalidPixelFormat(let value):
            return "The camera returned unsupported PFNC pixel format 0x\(String(value, radix: 16)). The probe requires RGB8 packed (0x02180014)."
        case .invalidFramePointer: return "The SDK returned a null frame-buffer pointer."
        }
    }
}

private final class ProbeRunContext {
    var report = AmcamCameraProbeReport()
    var currentStage: AmcamProbeStage = .argumentParsing
}

@main
struct AmcamCameraProbe {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let wantsJSON = arguments.contains("--json")
        if arguments.contains("--help") {
            print(Options.usage)
            return
        }

        let context = ProbeRunContext()
        do {
            let options = try Options.parse(arguments)
            context.report.sdk = AmcamProbeSDKInfo(path: options.sdkURL.path)
            try run(options, context: context)
        } catch {
            if context.report.failure == nil {
                let stage = (error as? ProbeError)?.diagnosticStage ?? context.currentStage
                context.report.failure = AmcamProbeFailure(
                    stage: stage,
                    message: error.localizedDescription
                )
            }
        }

        if !context.report.cleanupErrors.isEmpty, context.report.failure == nil {
            context.report.failure = AmcamProbeFailure(
                stage: .cleanup,
                message: "One or more native resources could not be released."
            )
        }
        context.report.status = context.report.failure == nil ? .success : .failure

        if wantsJSON {
            do {
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(context.report)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([0x0A]))
            } catch {
                fputs("ERROR: Could not encode diagnostic report: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        } else {
            if let failure = context.report.failure {
                fputs("ERROR [\(failure.stage.rawValue)]: \(failure.message)\n", stderr)
            }
            for cleanupError in context.report.cleanupErrors {
                fputs("CLEANUP ERROR: \(cleanupError)\n", stderr)
            }
        }

        if context.report.status == .failure {
            exit(EXIT_FAILURE)
        }
    }

    private static func emit(_ message: String, options: Options) {
        guard !options.jsonOutput else { return }
        print(message)
    }

    private static func run(
        _ options: Options,
        context: ProbeRunContext
    ) throws {
        context.report.sdk = AmcamProbeSDKInfo(path: options.sdkURL.path)
        let backend = AmcamGenTLImplementation(sdkLibraryURL: options.sdkURL)

        var initialized = false
        var system: TL_HANDLE?
        var interface: IF_HANDLE?
        var device: DEV_HANDLE?
        var stream: DS_HANDLE?
        var eventRegistered = false
        var errorEventRegistered = false
        var acquisitionStarted = false
        var bufferHandlesByRawValue: [UInt: BUFFER_HANDLE] = [:]

        defer {
            context.currentStage = .cleanup
            var cleanupFailures: [String] = []
            func attemptCleanup(_ operation: String, _ action: () throws -> Void) {
                do {
                    try action()
                } catch {
                    cleanupFailures.append("\(operation): \(error.localizedDescription)")
                }
            }

            if let stream {
                if acquisitionStarted {
                    attemptCleanup("DSStopAcquisition") {
                        try backend.DSStopAcquisition(
                            stream,
                            flags: GenTLAcquisitionStopFlag.normal.rawValue
                        )
                    }
                }
                if errorEventRegistered {
                    attemptCleanup("GCUnregisterEvent(error)") {
                        try backend.GCUnregisterEvent(
                            .dataStream(stream),
                            eventType: GenTLEventType.error.rawValue
                        )
                    }
                }
                if eventRegistered {
                    attemptCleanup("GCUnregisterEvent(new-buffer)") {
                        try backend.GCUnregisterEvent(
                            .dataStream(stream),
                            eventType: GenTLEventType.newBuffer.rawValue
                        )
                    }
                }
                attemptCleanup("DSClose") { try backend.DSClose(stream) }
            }
            if let device {
                attemptCleanup("DevClose") { try backend.DevClose(device) }
            }
            if let interface {
                attemptCleanup("IFClose") { try backend.IFClose(interface) }
            }
            if let system {
                attemptCleanup("TLClose") { try backend.TLClose(system) }
            }
            if initialized {
                attemptCleanup("GCCloseLib") { try backend.swiftGCCloseLib() }
            }

            context.report.cleanupErrors.append(contentsOf: cleanupFailures)
        }

        context.currentStage = .libraryInitialization
        try backend.swiftGCInitLib()
        initialized = true
        context.currentStage = .sdkVersionRead
        let sdkVersion = try readString(backend.GCGetInfo(command: GenTLInfoCommand.TransportLayer.version.rawValue))
        context.report.sdk?.version = sdkVersion
        emit("SDK version: \(sdkVersion)", options: options)
        context.currentStage = .transportLayerOpen
        let systemHandle = try backend.TLOpen()
        system = systemHandle

        context.currentStage = .interfaceDiscovery
        let interfaceCount = try backend.TLGetNumInterfaces(systemHandle)
        guard interfaceCount > 0 else { throw ProbeError.noInterface }
        let interfaceID = try backend.TLGetInterfaceID(systemHandle, index: 0)
        context.report.interfaceIdentifier = interfaceID
        let interfaceHandle = try backend.TLOpenInterface(systemHandle, interfaceID: interfaceID)
        interface = interfaceHandle

        context.currentStage = .deviceDiscovery
        _ = try backend.IFUpdateDeviceList(interfaceHandle, timeout: options.timeoutMilliseconds)
        let deviceCount = Int(try backend.IFGetNumDevices(interfaceHandle))
        guard deviceCount > 0 else { throw ProbeError.noDevices }
        guard options.deviceIndex < deviceCount else {
            throw ProbeError.invalidDeviceIndex(options.deviceIndex, count: deviceCount)
        }

        context.report.device = AmcamProbeDeviceInfo(discoveredCount: deviceCount)
        emit("SDK: \(options.sdkURL.path)", options: options)
        emit("Interface: \(interfaceID)", options: options)
        emit("Discovered devices: \(deviceCount)", options: options)
        for index in 0..<deviceCount {
            let identifier = try backend.IFGetDeviceID(interfaceHandle, index: UInt32(index))
            emit("  [\(index)] \(identifier)", options: options)
        }

        context.currentStage = .deviceDiscovery
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
        context.report.device = AmcamProbeDeviceInfo(
            index: options.deviceIndex,
            identifier: deviceID,
            modelName: modelName,
            displayName: displayName,
            discoveredCount: deviceCount
        )
        emit("Selected camera: \(displayName) (\(modelName))", options: options)
        context.currentStage = .deviceOpen
        let deviceHandle = try backend.IFOpenDevice(
            interfaceHandle,
            deviceID: deviceID,
            accessFlags: GenTLDeviceAccess.exclusive.rawValue
        )
        device = deviceHandle
        emit("Opened device: \(deviceID)", options: options)

        context.currentStage = .dataStreamOpen
        let streamCount = try backend.DevGetNumDataStreams(deviceHandle)
        guard streamCount > 0 else { throw ProbeError.noDataStream }
        let streamID = try backend.DevGetDataStreamID(deviceHandle, index: 0)
        let streamHandle = try backend.DevOpenDataStream(deviceHandle, dataStreamID: streamID)
        stream = streamHandle

        context.currentStage = .bufferPreparation
        let payloadSize = try readSize(
            backend,
            stream: streamHandle,
            buffer: nil,
            command: GenTLInfoCommand.Stream.payloadSize.rawValue
        )
        guard payloadSize > 0, payloadSize <= 512 * 1024 * 1024 else {
            throw ProbeError.invalidInfo(
                "stream payload size \(payloadSize) is outside the supported range (1...536870912)"
            )
        }

        context.report.stream = AmcamProbeStreamInfo(identifier: streamID, payloadSize: payloadSize)
        context.currentStage = .bufferPreparation
        let eventHandle = try backend.GCRegisterEvent(
            .dataStream(streamHandle),
            eventType: GenTLEventType.newBuffer.rawValue
        )
        eventRegistered = true
        let errorEventHandle = try backend.GCRegisterEvent(
            .dataStream(streamHandle),
            eventType: GenTLEventType.error.rawValue
        )
        errorEventRegistered = true

        let allocationLimit = 512 * 1024 * 1024
        let bufferCount = min(4, max(1, allocationLimit / payloadSize))
        for _ in 0..<bufferCount {
            let bufferHandle = try backend.DSAllocAndAnnounceBuffer(
                streamHandle,
                size: payloadSize,
                privateData: nil
            )
            bufferHandlesByRawValue[bufferHandle.rawValue] = bufferHandle
            try backend.DSQueueBuffer(streamHandle, buffer: bufferHandle)
        }

        context.report.stream?.announcedBufferCount = bufferCount
        context.report.acquisition = AmcamProbeAcquisitionInfo(requestedFrameCount: options.frameCount)
        emit("Data stream: \(streamID)", options: options)
        emit(
            "Announced buffers: \(bufferCount) x \(payloadSize) bytes " +
            "(\(bufferCount * payloadSize) bytes total)",
            options: options
        )
        emit("Acquiring \(options.frameCount) frame(s)...", options: options)

        let startTime = ProcessInfo.processInfo.systemUptime
        context.currentStage = .acquisitionStart
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
            context.currentStage = .frameRead
            if (try? backend.EventGetData(errorEventHandle, timeout: 0)) != nil {
                throw ProbeError.cameraErrorEvent
            }

            let eventData: Data
            do {
                eventData = try backend.EventGetData(
                    eventHandle,
                    timeout: options.timeoutMilliseconds
                )
            } catch {
                if (try? backend.EventGetData(errorEventHandle, timeout: 0)) != nil {
                    throw ProbeError.cameraErrorEvent
                }
                throw error
            }
            guard eventData.count == 2 * MemoryLayout<UInt>.size else {
                throw ProbeError.invalidEventPayload
            }
            let (deliveredHandle, deliveredUserPointer) = eventData.withUnsafeBytes {
                (
                    $0.loadUnaligned(as: UInt.self),
                    $0.loadUnaligned(
                        fromByteOffset: MemoryLayout<UInt>.size,
                        as: UInt.self
                    )
                )
            }
            guard let bufferHandle = bufferHandlesByRawValue[deliveredHandle] else {
                throw ProbeError.unknownBuffer(deliveredHandle)
            }
            guard deliveredUserPointer == 0 else {
                throw ProbeError.unexpectedUserPointer(deliveredUserPointer)
            }

            context.currentStage = .frameValidation
            let width = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.width.rawValue
            )
            let height = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.height.rawValue
            )
            let announcedBufferSize = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.size.rawValue
            )
            let sizeFilled = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.sizeFilled.rawValue
            )
            let dataSize = try readSize(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.dataSize.rawValue
            )
            let pixelFormat = try readUInt64(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.pixelFormat.rawValue
            )
            let pixelFormatNamespace = try readUInt64(
                backend, stream: streamHandle, buffer: bufferHandle,
                command: GenTLInfoCommand.Buffer.pixelFormatNamespace.rawValue
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
                context.report.acquisition?.completeFrameCount = completeFrames
                context.report.acquisition?.incompleteFrameCount = incompleteFrames
                emit("Frame \(frameIndex + 1): INCOMPLETE", options: options)
                if frameIndex + 1 < options.frameCount {
                    try backend.DSQueueBuffer(streamHandle, buffer: bufferHandle)
                }
                continue
            }

            if timestamp > 0 {
                if firstDeviceTimestamp == nil { firstDeviceTimestamp = timestamp }
                lastDeviceTimestamp = timestamp
            }

            guard pixelFormat == 0x02180014, pixelFormatNamespace == 4 else {
                throw ProbeError.invalidPixelFormat(pixelFormat)
            }

            let (packedRowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 3)
            let (bytesPerRow, strideOverflow) = packedRowBytes.addingReportingOverflow(rowPadding)
            let (requiredBytes, payloadOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
            guard width > 0, height > 0, rowPadding >= 0,
                  !rowOverflow, !strideOverflow, !payloadOverflow,
                  announcedBufferSize == payloadSize,
                  sizeFilled >= requiredBytes,
                  sizeFilled <= announcedBufferSize,
                  dataSize == requiredBytes,
                  requiredBytes > 0 else {
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
            context.report.image = AmcamProbeImageInfo(
                width: width,
                height: height,
                pixelFormatCode: pixelFormat,
                pixelFormatNamespace: pixelFormatNamespace,
                bytesPerRow: bytesPerRow,
                rowPaddingBytes: rowPadding,
                sizeFilled: sizeFilled,
                dataSize: dataSize
            )
            context.report.acquisition?.completeFrameCount = completeFrames
            context.report.acquisition?.incompleteFrameCount = incompleteFrames
            if context.report.acquisition?.firstSequence == nil {
                context.report.acquisition?.firstSequence = sequence
            }
            context.report.acquisition?.lastSequence = sequence
            if context.report.acquisition?.firstDeviceTimestampMicroseconds == nil, timestamp > 0 {
                context.report.acquisition?.firstDeviceTimestampMicroseconds = timestamp
            }
            if timestamp > 0 {
                context.report.acquisition?.lastDeviceTimestampMicroseconds = timestamp
            }
            context.report.acquisition?.lastFrameSHA256 = digest
            emit(
                "Frame \(frameIndex + 1): \(width)x\(height), " +
                "\(sizeFilled) bytes, stride \(bytesPerRow), " +
                "sequence \(sequence), timestamp \(timestamp) us, " +
                "SHA-256 \(digest)",
                options: options
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
                context.currentStage = .bufferQueue
                try backend.DSQueueBuffer(streamHandle, buffer: bufferHandle)
            }
        }

        let elapsed = max(ProcessInfo.processInfo.systemUptime - startTime, 0.000_001)
        context.report.acquisition?.completeFrameCount = completeFrames
        context.report.acquisition?.incompleteFrameCount = incompleteFrames
        context.report.acquisition?.elapsedSeconds = elapsed
        context.report.acquisition?.hostLoopFramesPerSecond = Double(completeFrames) / elapsed
        context.currentStage = .acquisitionStop
        try backend.DSStopAcquisition(
            streamHandle,
            flags: GenTLAcquisitionStopFlag.normal.rawValue
        )
        acquisitionStarted = false

        if let outputURL = options.outputURL, let lastPPM {
            context.currentStage = .outputWrite
            try lastPPM.write(to: outputURL, options: .atomic)
            context.report.outputImagePath = outputURL.path
            emit("Last complete frame written: \(outputURL.path)", options: options)
        }

        emit(
            "Result: \(completeFrames) complete, \(incompleteFrames) incomplete, " +
            String(format: "%.2f", Double(completeFrames) / elapsed) + " host-loop FPS, " +
            String(format: "%.3f", elapsed) + " seconds",
            options: options
        )
        if let firstDeviceTimestamp, let lastDeviceTimestamp,
           lastDeviceTimestamp > firstDeviceTimestamp, completeFrames > 1 {
            let deviceElapsedMicroseconds = lastDeviceTimestamp - firstDeviceTimestamp
            let deviceFPS = Double(completeFrames - 1) * 1_000_000.0 /
                Double(deviceElapsedMicroseconds)
            context.report.acquisition?.cameraTimestampFramesPerSecond = deviceFPS
            emit("Camera timestamp rate: \(String(format: "%.2f", deviceFPS)) FPS", options: options)
        } else {
            emit("Camera timestamp rate: unavailable", options: options)
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
