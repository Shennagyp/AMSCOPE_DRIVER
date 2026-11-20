import Foundation
import GenTLABI
@_spi(BackendConvenience) import GenTLAPI

/// One complete image payload delivered by a GenTL New Buffer event.
///
/// `timestamp` is the raw device timestamp reported by BUFFER_INFO_TIMESTAMP.
/// Its unit is producer/device specific unless the device timestamp frequency
/// is also queried. The acquisition layer deliberately does not relabel it as
/// microseconds or nanoseconds.
public struct GenTLFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixelFormat: UInt64
    public let pixelFormatNamespace: UInt64
    public let rowPaddingBytes: Int
    public let sizeFilled: Int
    public let dataSize: Int
    public let sequence: UInt64
    public let timestamp: UInt64
    public let isIncomplete: Bool
    public let bytes: Data

    public init(
        width: Int,
        height: Int,
        pixelFormat: UInt64,
        pixelFormatNamespace: UInt64,
        rowPaddingBytes: Int,
        sizeFilled: Int,
        dataSize: Int,
        sequence: UInt64,
        timestamp: UInt64,
        isIncomplete: Bool,
        bytes: Data
    ) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.pixelFormatNamespace = pixelFormatNamespace
        self.rowPaddingBytes = rowPaddingBytes
        self.sizeFilled = sizeFilled
        self.dataSize = dataSize
        self.sequence = sequence
        self.timestamp = timestamp
        self.isIncomplete = isIncomplete
        self.bytes = bytes
    }
}

public enum GenTLAcquisitionError: Error, LocalizedError, Equatable, Sendable {
    case genTLCallFailed(operation: String, code: Int32)
    case noDataStream
    case invalidDataStreamID
    case invalidPayloadSize(Int)
    case bufferAllocationLimitExceeded(payloadSize: Int, limit: Int)
    case invalidBufferCount(Int)
    case invalidEventPayloadSize(Int)
    case unknownBufferHandle(UInt)
    case unexpectedUserPointer(UInt)
    case invalidBufferInfo(
        command: Int32,
        expectedDataType: Int32,
        actualDataType: Int32,
        expectedSize: Int,
        actualSize: Int
    )
    case invalidFrameMetadata
    case invalidFramePointer
    case imageNotPresent
    case acquisitionAlreadyStarted
    case acquisitionNotStarted
    case acquisitionStopped
    case eventTimeout
    case sessionClosed

    public var errorDescription: String? {
        switch self {
        case .genTLCallFailed(let operation, let code):
            return "\(operation) failed with GenTL error \(code)."
        case .noDataStream:
            return "The opened GenTL device exposes no data stream."
        case .invalidDataStreamID:
            return "The Producer returned an invalid data-stream identifier."
        case .invalidPayloadSize(let size):
            return "The Producer returned an invalid stream payload size (\(size) bytes)."
        case .bufferAllocationLimitExceeded(let payloadSize, let limit):
            return "A \(payloadSize)-byte payload exceeds the acquisition memory limit of \(limit) bytes."
        case .invalidBufferCount(let count):
            return "The acquisition buffer count must be between 1 and 16; received \(count)."
        case .invalidEventPayloadSize(let size):
            return "The New Buffer event payload has \(size) bytes; the GenTL ABI requires \(2 * MemoryLayout<UInt>.size)."
        case .unknownBufferHandle(let handle):
            return "The New Buffer event referenced unannounced buffer handle \(handle)."
        case .unexpectedUserPointer(let pointer):
            return "The New Buffer event returned unexpected user pointer \(pointer)."
        case .invalidBufferInfo(let command, let expectedType, let actualType, let expectedSize, let actualSize):
            return "Buffer info command \(command) returned type \(actualType)/\(actualSize) bytes; expected type \(expectedType)/\(expectedSize) bytes."
        case .invalidFrameMetadata:
            return "The Producer returned inconsistent image dimensions or buffer lengths."
        case .invalidFramePointer:
            return "The Producer returned a null base pointer for a non-empty image buffer."
        case .imageNotPresent:
            return "The delivered GenTL buffer does not contain an image."
        case .acquisitionAlreadyStarted:
            return "Acquisition is already running for this data stream."
        case .acquisitionNotStarted:
            return "Acquisition has not been started for this data stream."
        case .acquisitionStopped:
            return "Acquisition was stopped while waiting for a frame."
        case .eventTimeout:
            return "No new image buffer arrived before the GenTL event-read timeout."
        case .sessionClosed:
            return "The GenTL acquisition session is closed."
        }
    }
}

/// Owns a GenTL data stream, its New Buffer event and announced buffers.
///
/// The object is backend-neutral: all transport operations are issued through
/// the GenTLAPI instance and device handle retained by GenTLDeviceSession.
/// Stop interrupts a pending EventGetData call before taking the reader lock;
/// close then unregisters the event, flushes queues, revokes buffers and closes
/// the stream in dependency order.
public final class GenTLAcquisitionSession: @unchecked Sendable {
    private enum Constants {
        static let newBufferEventID: GenTLABI.EVENT_TYPE = 1
        static let acquisitionStartDefault: GenTLABI.ACQ_START_FLAGS = 0
        static let acquisitionStopDefault: GenTLABI.ACQ_STOP_FLAGS = 0
        static let queueAllToInput: GenTLABI.ACQ_QUEUE_TYPE = 2
        static let eventPayloadSize = 2 * MemoryLayout<UInt>.size
        static let maximumPayloadSize = 512 * 1024 * 1024
        static let maximumDataStreamIDSize = 1_048_576
    }

    private let deviceSession: GenTLDeviceSession
    private let api: any GenTLAPI
    private let stateLock = NSLock()
    private let readerLock = NSLock()

    private var streamHandle: GenTLABI.DS_HANDLE?
    private var eventHandle: GenTLABI.EVENT_HANDLE?
    private var buffersByRawHandle: [UInt: GenTLABI.BUFFER_HANDLE] = [:]
    private var payloadSize = 0
    private var isAcquiring = false
    private var isStopping = false
    private var isClosed = false

    public init(
        device: GenTLDeviceSession,
        bufferCount: Int = 4,
        allocationLimitBytes: Int = 512 * 1024 * 1024
    ) throws {
        guard (1...16).contains(bufferCount) else {
            throw GenTLAcquisitionError.invalidBufferCount(bufferCount)
        }
        guard allocationLimitBytes > 0 else {
            throw GenTLAcquisitionError.bufferAllocationLimitExceeded(
                payloadSize: 1,
                limit: allocationLimitBytes
            )
        }

        self.deviceSession = device
        self.api = device.api

        do {
            try openDataStream(
                bufferCount: bufferCount,
                allocationLimitBytes: min(allocationLimitBytes, Constants.maximumPayloadSize)
            )
        } catch {
            try? close()
            throw error
        }
    }

    /// Starts continuous acquisition by default. Pass a finite count for a
    /// finite GenTL acquisition. A value of UInt64.max requests continuous mode.
    public func start(numberToAcquire: UInt64 = UInt64.max) throws {
        guard numberToAcquire > 0 else {
            throw GenTLAcquisitionError.genTLCallFailed(
                operation: "DSStartAcquisition",
                code: GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
            )
        }

        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isClosed else { throw GenTLAcquisitionError.sessionClosed }
        guard !isAcquiring else { throw GenTLAcquisitionError.acquisitionAlreadyStarted }
        guard let streamHandle else { throw GenTLAcquisitionError.sessionClosed }

        try check(
            api.DSFlushQueue(streamHandle, Constants.queueAllToInput),
            operation: "DSFlushQueue(BeforeStart)"
        )
        try check(
            api.DSStartAcquisition(
                streamHandle,
                Constants.acquisitionStartDefault,
                numberToAcquire
            ),
            operation: "DSStartAcquisition"
        )
        isAcquiring = true
    }

    /// Waits for and copies one image buffer. The buffer is returned to the
    /// Producer's input queue only after its bytes and metadata have been copied.
    public func nextFrame(timeoutMilliseconds: UInt64) throws -> GenTLFrame {
        readerLock.lock()
        defer { readerLock.unlock() }

        stateLock.lock()
        guard !isClosed else {
            stateLock.unlock()
            throw GenTLAcquisitionError.sessionClosed
        }
        guard isAcquiring, !isStopping,
              let streamHandle, let eventHandle else {
            stateLock.unlock()
            throw GenTLAcquisitionError.acquisitionNotStarted
        }
        stateLock.unlock()

        var eventBytes = [UInt8](repeating: 0, count: Constants.eventPayloadSize)
        var eventSize = eventBytes.count
        let eventStatus = eventBytes.withUnsafeMutableBufferPointer { bytes in
            api.EventGetData(
                eventHandle,
                bytes.baseAddress.map { UnsafeMutableRawPointer($0) },
                &eventSize,
                timeoutMilliseconds
            )
        }

        if eventStatus != successStatus {
            stateLock.lock()
            let wasStopped = isStopping || isClosed
            stateLock.unlock()
            if wasStopped {
                throw GenTLAcquisitionError.acquisitionStopped
            }
            if eventStatus == GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_TIMEOUT) {
                throw GenTLAcquisitionError.eventTimeout
            }
            try check(eventStatus, operation: "EventGetData(NewBuffer)")
        }

        guard eventSize == Constants.eventPayloadSize else {
            throw GenTLAcquisitionError.invalidEventPayloadSize(eventSize)
        }

        let (rawBufferHandle, userPointer) = eventBytes.withUnsafeBytes { bytes in
            (
                bytes.loadUnaligned(as: UInt.self),
                bytes.loadUnaligned(
                    fromByteOffset: MemoryLayout<UInt>.size,
                    as: UInt.self
                )
            )
        }
        guard let bufferHandle = buffersByRawHandle[rawBufferHandle] else {
            throw GenTLAcquisitionError.unknownBufferHandle(rawBufferHandle)
        }
        guard userPointer == 0 else {
            stateLock.lock()
            let shouldRequeue = !isStopping && !isClosed
            stateLock.unlock()
            if shouldRequeue {
                _ = api.DSQueueBuffer(streamHandle, bufferHandle)
            }
            throw GenTLAcquisitionError.unexpectedUserPointer(userPointer)
        }

        do {
            let frame = try readFrame(
                stream: streamHandle,
                buffer: bufferHandle
            )

            stateLock.lock()
            let shouldRequeue = !isStopping && !isClosed
            stateLock.unlock()
            if shouldRequeue {
                try check(
                    api.DSQueueBuffer(streamHandle, bufferHandle),
                    operation: "DSQueueBuffer"
                )
            }
            return frame
        } catch {
            stateLock.lock()
            let shouldRequeue = !isStopping && !isClosed
            stateLock.unlock()
            if shouldRequeue {
                _ = api.DSQueueBuffer(streamHandle, bufferHandle)
            }
            throw error
        }
    }

    /// Stops acquisition and interrupts a blocked New Buffer event read.
    public func stop() throws {
        stateLock.lock()
        guard !isClosed else {
            stateLock.unlock()
            return
        }
        guard isAcquiring else {
            stateLock.unlock()
            return
        }
        isStopping = true
        let eventHandle = self.eventHandle
        stateLock.unlock()

        if let eventHandle {
            // EventKill is the GenTL mechanism for aborting a pending EventGetData.
            // The stop operation remains authoritative; a failed kill is surfaced
            // only if DSStopAcquisition also fails.
            _ = api.EventKill(eventHandle)
        }

        readerLock.lock()
        defer { readerLock.unlock() }

        stateLock.lock()
        guard let streamHandle else {
            isStopping = false
            stateLock.unlock()
            throw GenTLAcquisitionError.sessionClosed
        }
        let status = api.DSStopAcquisition(
            streamHandle,
            Constants.acquisitionStopDefault
        )
        let flushStatus: GenTLABI.GC_ERROR?
        if status == successStatus {
            isAcquiring = false
            flushStatus = api.DSFlushQueue(streamHandle, Constants.queueAllToInput)
        } else {
            flushStatus = nil
        }
        isStopping = false
        stateLock.unlock()

        try check(status, operation: "DSStopAcquisition")
        if let flushStatus {
            try check(flushStatus, operation: "DSFlushQueue(AfterStop)")
        }
    }

    /// Releases stream resources in GenTL ownership order. If any operation
    /// fails, remaining handles are retained so close can be retried safely.
    public func close() throws {
        stateLock.lock()
        let alreadyClosed = isClosed
        let acquiring = isAcquiring
        stateLock.unlock()
        if alreadyClosed { return }
        if acquiring { try stop() }

        readerLock.lock()
        defer { readerLock.unlock() }

        stateLock.lock()
        if isClosed {
            stateLock.unlock()
            return
        }
        guard let streamHandle else {
            isClosed = true
            stateLock.unlock()
            return
        }
        let eventHandle = self.eventHandle
        let bufferHandles = buffersByRawHandle.values.sorted {
            UInt(bitPattern: $0) < UInt(bitPattern: $1)
        }
        stateLock.unlock()

        if eventHandle != nil {
            try check(
                api.GCUnregisterEvent(streamHandle, Constants.newBufferEventID),
                operation: "GCUnregisterEvent(NewBuffer)"
            )
            stateLock.lock()
            self.eventHandle = nil
            stateLock.unlock()
        }

        try check(
            api.DSFlushQueue(streamHandle, Constants.queueAllToInput),
            operation: "DSFlushQueue(AllToInput)"
        )

        for bufferHandle in bufferHandles {
            try check(
                api.DSRevokeBuffer(streamHandle, bufferHandle, nil, nil),
                operation: "DSRevokeBuffer"
            )
            stateLock.lock()
            buffersByRawHandle.removeValue(forKey: UInt(bitPattern: bufferHandle))
            stateLock.unlock()
        }

        try check(api.DSClose(streamHandle), operation: "DSClose")
        stateLock.lock()
        self.streamHandle = nil
        isClosed = true
        stateLock.unlock()
    }

    deinit {
        try? close()
    }

    private var successStatus: GenTLABI.GC_ERROR {
        GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    private func openDataStream(
        bufferCount requestedBufferCount: Int,
        allocationLimitBytes: Int
    ) throws {
        var streamCount: UInt32 = 0
        try check(
            api.DevGetNumDataStreams(deviceSession.deviceHandle, &streamCount),
            operation: "DevGetNumDataStreams"
        )
        guard streamCount > 0 else {
            throw GenTLAcquisitionError.noDataStream
        }

        let streamID = try readDataStreamID(index: 0)
        var openedStream: GenTLABI.DS_HANDLE?
        let openStatus = streamID.withCString {
            api.DevOpenDataStream(deviceSession.deviceHandle, $0, &openedStream)
        }
        try check(openStatus, operation: "DevOpenDataStream")
        guard let openedStream else {
            throw GenTLAcquisitionError.genTLCallFailed(
                operation: "DevOpenDataStream",
                code: GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
            )
        }
        streamHandle = openedStream

        let queriedPayloadSize = try readStreamPayloadSize(openedStream)
        guard queriedPayloadSize > 0,
              queriedPayloadSize <= Constants.maximumPayloadSize else {
            throw GenTLAcquisitionError.invalidPayloadSize(queriedPayloadSize)
        }
        guard queriedPayloadSize <= allocationLimitBytes else {
            throw GenTLAcquisitionError.bufferAllocationLimitExceeded(
                payloadSize: queriedPayloadSize,
                limit: allocationLimitBytes
            )
        }
        payloadSize = queriedPayloadSize

        var registeredEvent: GenTLABI.EVENT_HANDLE?
        try check(
            api.GCRegisterEvent(
                openedStream,
                Constants.newBufferEventID,
                &registeredEvent
            ),
            operation: "GCRegisterEvent(NewBuffer)"
        )
        guard let registeredEvent else {
            throw GenTLAcquisitionError.genTLCallFailed(
                operation: "GCRegisterEvent(NewBuffer)",
                code: GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
            )
        }
        eventHandle = registeredEvent

        let effectiveBufferCount = min(
            requestedBufferCount,
            max(1, allocationLimitBytes / queriedPayloadSize)
        )
        for _ in 0..<effectiveBufferCount {
            var announcedBuffer: GenTLABI.BUFFER_HANDLE?
            try check(
                api.DSAllocAndAnnounceBuffer(
                    openedStream,
                    queriedPayloadSize,
                    nil,
                    &announcedBuffer
                ),
                operation: "DSAllocAndAnnounceBuffer"
            )
            guard let announcedBuffer else {
                throw GenTLAcquisitionError.genTLCallFailed(
                    operation: "DSAllocAndAnnounceBuffer",
                    code: GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
                )
            }
            buffersByRawHandle[UInt(bitPattern: announcedBuffer)] = announcedBuffer
            try check(
                api.DSQueueBuffer(openedStream, announcedBuffer),
                operation: "DSQueueBuffer(initial)"
            )
        }
    }

    private func readDataStreamID(index: UInt32) throws -> String {
        var requiredSize = 0
        let queryStatus = api.DevGetDataStreamID(
            deviceSession.deviceHandle,
            index,
            nil,
            &requiredSize
        )
        if queryStatus != successStatus &&
           queryStatus != GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_BUFFER_TOO_SMALL) {
            try check(queryStatus, operation: "DevGetDataStreamID(size)")
        }
        guard requiredSize > 1,
              requiredSize <= Constants.maximumDataStreamIDSize else {
            throw GenTLAcquisitionError.invalidDataStreamID
        }

        var bytes = [CChar](repeating: 0, count: requiredSize)
        var capacity = requiredSize
        let status = bytes.withUnsafeMutableBufferPointer { buffer in
            api.DevGetDataStreamID(
                deviceSession.deviceHandle,
                index,
                buffer.baseAddress,
                &capacity
            )
        }
        try check(status, operation: "DevGetDataStreamID")
        guard capacity > 0, capacity <= bytes.count else {
            throw GenTLAcquisitionError.invalidDataStreamID
        }
        bytes[bytes.count - 1] = 0
        guard let terminator = bytes.firstIndex(of: 0), terminator > 0 else {
            throw GenTLAcquisitionError.invalidDataStreamID
        }
        return String(decoding: bytes[..<terminator].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func readStreamPayloadSize(_ stream: GenTLABI.DS_HANDLE) throws -> Int {
        var value = 0
        var dataType: GenTLABI.INFO_DATATYPE = 0
        var size = MemoryLayout<Int>.size
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            api.DSGetInfo(
                stream,
                GenTLInfoCommand.Stream.payloadSize.rawValue,
                &dataType,
                bytes.baseAddress,
                &size
            )
        }
        try check(status, operation: "DSGetInfo(PayloadSize)")
        let expectedType = Int32(GenTLABI.INFO_DATATYPE_SIZET.rawValue)
        guard dataType == expectedType, size == MemoryLayout<Int>.size else {
            throw GenTLAcquisitionError.invalidBufferInfo(
                command: GenTLInfoCommand.Stream.payloadSize.rawValue,
                expectedDataType: expectedType,
                actualDataType: dataType,
                expectedSize: MemoryLayout<Int>.size,
                actualSize: size
            )
        }
        return value
    }

    private func readFrame(
        stream: GenTLABI.DS_HANDLE,
        buffer: GenTLABI.BUFFER_HANDLE
    ) throws -> GenTLFrame {
        let width = try readBufferSize(stream, buffer, GenTLInfoCommand.Buffer.width.rawValue)
        let height = try readBufferSize(stream, buffer, GenTLInfoCommand.Buffer.height.rawValue)
        let bufferSize = try readBufferSize(stream, buffer, GenTLInfoCommand.Buffer.size.rawValue)
        let sizeFilled = try readBufferSize(stream, buffer, GenTLInfoCommand.Buffer.sizeFilled.rawValue)
        let dataSize = try readBufferSize(stream, buffer, GenTLInfoCommand.Buffer.dataSize.rawValue)
        let rowPadding = try readBufferSize(stream, buffer, GenTLInfoCommand.Buffer.xPadding.rawValue)
        let pixelFormat = try readBufferUInt64(stream, buffer, GenTLInfoCommand.Buffer.pixelFormat.rawValue)
        let pixelFormatNamespace = try readBufferUInt64(
            stream, buffer, GenTLInfoCommand.Buffer.pixelFormatNamespace.rawValue
        )
        let sequence = try readBufferUInt64(stream, buffer, GenTLInfoCommand.Buffer.frameID.rawValue)
        let timestamp = try readBufferUInt64(stream, buffer, GenTLInfoCommand.Buffer.timestamp.rawValue)
        let isIncomplete = try readBufferBool(stream, buffer, GenTLInfoCommand.Buffer.isIncomplete.rawValue)
        let imagePresent = try readBufferBool(stream, buffer, GenTLInfoCommand.Buffer.imagePresent.rawValue)

        guard width > 0, height > 0, rowPadding >= 0,
              bufferSize == payloadSize,
              sizeFilled >= 0, sizeFilled <= bufferSize,
              dataSize >= 0, dataSize <= sizeFilled else {
            throw GenTLAcquisitionError.invalidFrameMetadata
        }
        guard isIncomplete || imagePresent else {
            throw GenTLAcquisitionError.imageNotPresent
        }

        let frameBytes: Data
        if sizeFilled == 0 {
            frameBytes = Data()
        } else {
            guard let pointer = try readBufferPointer(
                stream,
                buffer,
                GenTLInfoCommand.Buffer.base.rawValue
            ) else {
                throw GenTLAcquisitionError.invalidFramePointer
            }
            frameBytes = Data(bytes: pointer, count: sizeFilled)
        }

        return GenTLFrame(
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            pixelFormatNamespace: pixelFormatNamespace,
            rowPaddingBytes: rowPadding,
            sizeFilled: sizeFilled,
            dataSize: dataSize,
            sequence: sequence,
            timestamp: timestamp,
            isIncomplete: isIncomplete,
            bytes: frameBytes
        )
    }

    private func readBufferSize(
        _ stream: GenTLABI.DS_HANDLE,
        _ buffer: GenTLABI.BUFFER_HANDLE,
        _ command: Int32
    ) throws -> Int {
        try readBufferInfo(
            stream,
            buffer,
            command,
            expectedDataType: Int32(GenTLABI.INFO_DATATYPE_SIZET.rawValue),
            initialValue: 0
        )
    }

    private func readBufferUInt64(
        _ stream: GenTLABI.DS_HANDLE,
        _ buffer: GenTLABI.BUFFER_HANDLE,
        _ command: Int32
    ) throws -> UInt64 {
        try readBufferInfo(
            stream,
            buffer,
            command,
            expectedDataType: Int32(GenTLABI.INFO_DATATYPE_UINT64.rawValue),
            initialValue: 0
        )
    }

    private func readBufferBool(
        _ stream: GenTLABI.DS_HANDLE,
        _ buffer: GenTLABI.BUFFER_HANDLE,
        _ command: Int32
    ) throws -> Bool {
        let value: UInt8 = try readBufferInfo(
            stream,
            buffer,
            command,
            expectedDataType: Int32(GenTLABI.INFO_DATATYPE_BOOL8.rawValue),
            initialValue: 0
        )
        return value != 0
    }

    private func readBufferPointer(
        _ stream: GenTLABI.DS_HANDLE,
        _ buffer: GenTLABI.BUFFER_HANDLE,
        _ command: Int32
    ) throws -> UnsafeMutableRawPointer? {
        try readBufferInfo(
            stream,
            buffer,
            command,
            expectedDataType: Int32(GenTLABI.INFO_DATATYPE_PTR.rawValue),
            initialValue: Optional<UnsafeMutableRawPointer>.none
        )
    }

    private func readBufferInfo<T>(
        _ stream: GenTLABI.DS_HANDLE,
        _ buffer: GenTLABI.BUFFER_HANDLE,
        _ command: Int32,
        expectedDataType: Int32,
        initialValue: T
    ) throws -> T {
        var value = initialValue
        var actualDataType: GenTLABI.INFO_DATATYPE = 0
        var actualSize = MemoryLayout<T>.size
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            api.DSGetBufferInfo(
                stream,
                buffer,
                command,
                &actualDataType,
                bytes.baseAddress,
                &actualSize
            )
        }
        try check(status, operation: "DSGetBufferInfo(\(command))")
        guard actualDataType == expectedDataType,
              actualSize == MemoryLayout<T>.size else {
            throw GenTLAcquisitionError.invalidBufferInfo(
                command: command,
                expectedDataType: expectedDataType,
                actualDataType: actualDataType,
                expectedSize: MemoryLayout<T>.size,
                actualSize: actualSize
            )
        }
        return value
    }

    private func check(
        _ status: GenTLABI.GC_ERROR,
        operation: String
    ) throws {
        guard status == successStatus else {
            throw GenTLAcquisitionError.genTLCallFailed(
                operation: operation,
                code: Int32(status)
            )
        }
    }
}
