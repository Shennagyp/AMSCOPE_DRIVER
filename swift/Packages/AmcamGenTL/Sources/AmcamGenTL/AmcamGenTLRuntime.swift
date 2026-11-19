import Foundation
import GenTLAPI

final class AmcamBufferRecord: @unchecked Sendable {
    let handle: BUFFER_HANDLE
    let memory: UnsafeMutableRawPointer
    let size: Int
    let privateData: UnsafeMutableRawPointer?
    let allocatedByProvider: Bool

    var isQueued = false
    var isAcquiring = false
    var isIncomplete = false
    var newData = false
    var dataLargerThanBuffer = false
    var sizeFilled = 0
    var width: Int = 0
    var height: Int = 0
    var sequence: UInt64 = 0
    var timestampMicroseconds: UInt64 = 0

    init(
        handle: BUFFER_HANDLE,
        memory: UnsafeMutableRawPointer,
        size: Int,
        privateData: UnsafeMutableRawPointer?,
        allocatedByProvider: Bool
    ) {
        self.handle = handle
        self.memory = memory
        self.size = size
        self.privateData = privateData
        self.allocatedByProvider = allocatedByProvider
    }

    func releaseMemoryIfOwned() {
        if allocatedByProvider {
            memory.deallocate()
        }
    }
}

final class AmcamEventRecord: @unchecked Sendable {
    let handle: EVENT_HANDLE
    let eventType: Int32
    let source: EVENTSRC_HANDLE

    private let condition = NSCondition()
    private var dataQueue: [Data] = []
    private var killed = false
    private var firedCount: UInt64 = 0

    init(handle: EVENT_HANDLE, eventType: Int32, source: EVENTSRC_HANDLE) {
        self.handle = handle
        self.eventType = eventType
        self.source = source
    }

    func publish(_ data: Data) {
        condition.lock()
        defer { condition.unlock() }
        guard !killed else { return }
        dataQueue.append(data)
        firedCount &+= 1
        condition.broadcast()
    }

    func next(timeoutMilliseconds: UInt64) throws -> Data {
        condition.lock()
        defer { condition.unlock() }

        if timeoutMilliseconds == GenTLConstants.infiniteTimeout {
            while dataQueue.isEmpty && !killed {
                condition.wait()
            }
        } else {
            let deadline = Date(
                timeIntervalSinceNow: Double(timeoutMilliseconds) / 1_000.0
            )
            while dataQueue.isEmpty && !killed {
                if !condition.wait(until: deadline) {
                    throw GC_ERROR.timeout
                }
            }
        }

        guard !killed else { throw GC_ERROR.abort }
        guard !dataQueue.isEmpty else { throw GC_ERROR.noData }
        return dataQueue.removeFirst()
    }

    func flush() {
        condition.lock()
        dataQueue.removeAll(keepingCapacity: true)
        condition.broadcast()
        condition.unlock()
    }

    /// Removes New Buffer notifications for buffers no longer present in the
    /// output queue. Payloads start with the opaque BUFFER_HANDLE pointer.
    func removeBufferEvents(for handles: Set<UInt>) {
        guard !handles.isEmpty else { return }
        condition.lock()
        defer { condition.unlock() }
        dataQueue.removeAll { payload in
            guard payload.count >= MemoryLayout<UInt>.size else { return false }
            let rawHandle = payload.withUnsafeBytes {
                $0.loadUnaligned(as: UInt.self)
            }
            return handles.contains(rawHandle)
        }
        condition.broadcast()
    }

    func kill() {
        condition.lock()
        killed = true
        condition.broadcast()
        condition.unlock()
    }

    func info(command: Int32) throws -> GenTLInfoValue {
        condition.lock()
        defer { condition.unlock() }
        switch command {
        case 0: return .int32(eventType) // EVENT_EVENT_TYPE
        case 1: return .uint64(UInt64(dataQueue.count)) // EVENT_NUM_IN_QUEUE
        case 2: return .uint64(firedCount) // EVENT_NUM_FIRED
        case 3:
            let maximumSize = eventType == GenTLEventType.newBuffer.rawValue
                ? 2 * UInt64(MemoryLayout<UInt>.size)
                : 0
            return .uint64(maximumSize) // EVENT_SIZE_MAX
        case 4: return .uint64(0) // No event-specific info payload currently exposed.
        default: throw GC_ERROR.invalidParameter
        }
    }
}

final class AmcamDataStreamRecord: @unchecked Sendable {
    let handle: DS_HANDLE
    let deviceHandle: DEV_HANDLE
    let session: AmcamCameraSession

    private let condition = NSCondition()
    private var buffers: [UInt: AmcamBufferRecord] = [:]
    private var announcedOrder: [UInt] = []
    private var inputQueue: [UInt] = []
    private var outputQueue: [UInt] = []
    private var events: [Int32: [AmcamEventRecord]] = [:]

    private(set) var isGrabbing = false
    private(set) var numDelivered: UInt64 = 0
    private(set) var numUnderrun: UInt64 = 0
    private(set) var numStarted: UInt64 = 0
    private(set) var payloadSize: Int = 0
    private var finiteAcquisitionCount: UInt64?
    private var finiteStopScheduled = false

    init(handle: DS_HANDLE, deviceHandle: DEV_HANDLE, session: AmcamCameraSession) {
        self.handle = handle
        self.deviceHandle = deviceHandle
        self.session = session
        if let resolution = session.currentResolution() {
            let (pixels, overflow1) = resolution.width.multipliedReportingOverflow(by: resolution.height)
            let (bytes, overflow2) = pixels.multipliedReportingOverflow(by: 3)
            if !overflow1 && !overflow2 && bytes > 0 {
                payloadSize = bytes
            }
        }
    }

    func addEvent(_ event: AmcamEventRecord) {
        condition.lock()
        defer { condition.unlock() }
        events[event.eventType, default: []].append(event)
    }

    func removeEvent(_ event: AmcamEventRecord) {
        condition.lock()
        defer { condition.unlock() }
        events[event.eventType]?.removeAll { $0.handle == event.handle }
    }

    /// GenTL EventFlush on a New Buffer event discards its data queue and the
    /// associated DataStream output queue. Error-event flushes only clear data.
    func flushEvent(_ event: AmcamEventRecord) {
        event.flush()
        guard event.eventType == GenTLEventType.newBuffer.rawValue else { return }

        condition.lock()
        defer { condition.unlock() }
        let discardedHandles = outputQueue
        outputQueue.removeAll()
        for rawHandle in discardedHandles {
            guard let buffer = buffers[rawHandle] else { continue }
            buffer.isQueued = false
            buffer.newData = false
        }
        condition.broadcast()
    }

    func announce(
        handle: BUFFER_HANDLE,
        memory: UnsafeMutableRawPointer,
        size: Int,
        privateData: UnsafeMutableRawPointer?,
        allocatedByProvider: Bool
    ) throws {
        condition.lock()
        defer { condition.unlock() }
        guard !isGrabbing else { throw GC_ERROR.busy }
        guard size > 0 else { throw GC_ERROR.invalidParameter }
        guard buffers[handle.rawValue] == nil else { throw GC_ERROR.resourceInUse }
        buffers[handle.rawValue] = AmcamBufferRecord(
            handle: handle,
            memory: memory,
            size: size,
            privateData: privateData,
            allocatedByProvider: allocatedByProvider
        )
        announcedOrder.append(handle.rawValue)
    }

    func queue(_ handle: BUFFER_HANDLE) throws {
        condition.lock()
        defer { condition.unlock() }
        guard let buffer = buffers[handle.rawValue] else { throw GC_ERROR.invalidBuffer }
        guard !buffer.isAcquiring,
              !inputQueue.contains(handle.rawValue) else {
            throw GC_ERROR.resourceInUse
        }
        // A buffer in the output queue is still queued; DSQueueBuffer is the
        // operation that transfers it back into the input pool.
        outputQueue.removeAll { $0 == handle.rawValue }
        removeBufferEvents(for: [handle.rawValue])
        prepareForInput(buffer)
        inputQueue.append(handle.rawValue)
    }

    private func prepareForInput(_ buffer: AmcamBufferRecord) {
        buffer.isQueued = true
        buffer.isAcquiring = false
        buffer.isIncomplete = false
        buffer.newData = false
        buffer.dataLargerThanBuffer = false
        buffer.sizeFilled = 0
        buffer.width = 0
        buffer.height = 0
        buffer.sequence = 0
        buffer.timestampMicroseconds = 0
    }

    func flush(operation: Int32) throws {
        condition.lock()
        defer { condition.unlock() }

        // Flush mutates input/output ownership. The callback may be concurrently
        // consuming the input pool, so require the acquisition engine to be stopped.
        guard !isGrabbing else { throw GC_ERROR.busy }

        switch operation {
        case 0: // ACQ_QUEUE_INPUT_TO_OUTPUT
            // GenTL defines this as making input-pool buffers available on output.
            // Amcam cannot manufacture image data, so return empty buffers as incomplete.
            for raw in inputQueue {
                guard let buffer = buffers[raw] else { continue }
                buffer.isIncomplete = true
                buffer.newData = false
                buffer.sizeFilled = 0
                outputQueue.append(raw)
                publishBufferEvent(buffer)
            }
            inputQueue.removeAll()
        case 1: // ACQ_QUEUE_OUTPUT_DISCARD
            let discardedHandles = Set(outputQueue)
            removeBufferEvents(for: discardedHandles)
            for raw in outputQueue {
                if let buffer = buffers[raw] {
                    buffer.isQueued = false
                    buffer.newData = false
                }
            }
            outputQueue.removeAll()
        case 2: // ACQ_QUEUE_ALL_TO_INPUT
            let discardedOutputHandles = Set(outputQueue)
            removeBufferEvents(for: discardedOutputHandles)
            let all = announcedOrder
            inputQueue = all
            outputQueue.removeAll()
            for raw in all {
                guard let buffer = buffers[raw] else { continue }
                prepareForInput(buffer)
            }
        case 3: // ACQ_QUEUE_UNQUEUED_TO_INPUT
            let queued = Set(inputQueue + outputQueue)
            for raw in announcedOrder where !queued.contains(raw) {
                guard let buffer = buffers[raw] else { continue }
                prepareForInput(buffer)
                inputQueue.append(raw)
            }
        case 4: // ACQ_QUEUE_ALL_DISCARD
            let discardedOutputHandles = Set(outputQueue)
            removeBufferEvents(for: discardedOutputHandles)
            for raw in inputQueue + outputQueue {
                if let buffer = buffers[raw] {
                    buffer.isQueued = false
                    buffer.newData = false
                }
            }
            inputQueue.removeAll()
            outputQueue.removeAll()
        default:
            throw GC_ERROR.invalidParameter
        }
        condition.broadcast()
    }

    func start(numberToAcquire: UInt64) throws {
        condition.lock()
        guard !isGrabbing else {
            condition.unlock()
            throw GC_ERROR.resourceInUse
        }
        guard !inputQueue.isEmpty else {
            condition.unlock()
            throw GC_ERROR.invalidBuffer
        }
        isGrabbing = true
        finiteAcquisitionCount = numberToAcquire == 0 ? nil : numberToAcquire
        finiteStopScheduled = false
        numDelivered = 0
        numStarted = 0
        condition.unlock()

        do {
            try session.start { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let frame):
                    self.receive(frame)
                case .failure:
                    // The SDK session has already stopped frame delivery on a
                    // fatal callback. Mirror that state before notifying clients
                    // so DSStop/DSClose are not left believing acquisition is live.
                    self.condition.lock()
                    self.isGrabbing = false
                    self.finiteAcquisitionCount = nil
                    self.finiteStopScheduled = false
                    for raw in self.inputQueue {
                        self.buffers[raw]?.isAcquiring = false
                    }
                    self.condition.broadcast()
                    self.condition.unlock()
                    self.publishErrorEvent()
                }
            }
        } catch {
            condition.lock()
            isGrabbing = false
            finiteAcquisitionCount = nil
            condition.unlock()
            throw error
        }
    }

    func stop() throws {
        condition.lock()
        while finiteStopScheduled {
            condition.wait()
        }
        guard isGrabbing else {
            condition.unlock()
            throw GC_ERROR.notAvailable
        }
        condition.unlock()

        do {
            try session.stop()
        } catch {
            throw GC_ERROR.error
        }

        condition.lock()
        isGrabbing = false
        finiteAcquisitionCount = nil
        for raw in inputQueue {
            buffers[raw]?.isAcquiring = false
        }
        condition.broadcast()
        condition.unlock()
    }

    func close() throws {
        condition.lock()
        defer { condition.unlock() }

        guard !isGrabbing else { throw GC_ERROR.busy }
        guard events.values.allSatisfy({ $0.isEmpty }) else {
            throw GC_ERROR.resourceInUse
        }

        // GenTL DSClose revokes all remaining announced buffers. The producer
        // frees buffers it allocated; consumer-owned memory remains caller-owned.
        for buffer in buffers.values where buffer.allocatedByProvider {
            buffer.releaseMemoryIfOwned()
        }
        buffers.removeAll()
        announcedOrder.removeAll()
        inputQueue.removeAll()
        outputQueue.removeAll()
    }

    func revoke(_ handle: BUFFER_HANDLE) throws -> GenTLRevokedBuffer {
        condition.lock()
        defer { condition.unlock() }
        guard !isGrabbing else { throw GC_ERROR.busy }
        guard let buffer = buffers[handle.rawValue] else { throw GC_ERROR.invalidBuffer }
        guard !buffer.isQueued, !buffer.isAcquiring else { throw GC_ERROR.resourceInUse }

        buffers.removeValue(forKey: handle.rawValue)
        announcedOrder.removeAll { $0 == handle.rawValue }
        inputQueue.removeAll { $0 == handle.rawValue }
        outputQueue.removeAll { $0 == handle.rawValue }
        removeBufferEvents(for: [handle.rawValue])

        // GenTL transfers consumer-allocated memory back through ppBuffer.
        // Producer-allocated memory must be freed here and ppBuffer returned NULL.
        let returnedMemory: UnsafeMutableRawPointer?
        if buffer.allocatedByProvider {
            buffer.releaseMemoryIfOwned()
            returnedMemory = nil
        } else {
            returnedMemory = buffer.memory
        }

        return GenTLRevokedBuffer(
            baseAddress: returnedMemory,
            privateData: buffer.privateData
        )
    }

    func buffer(_ handle: BUFFER_HANDLE) throws -> AmcamBufferRecord {
        condition.lock()
        defer { condition.unlock() }
        guard let value = buffers[handle.rawValue] else { throw GC_ERROR.invalidBuffer }
        return value
    }

    func bufferID(index: UInt32) throws -> BUFFER_HANDLE {
        condition.lock()
        defer { condition.unlock() }
        guard Int(index) < announcedOrder.count else { throw GC_ERROR.invalidIndex }
        return BUFFER_HANDLE(rawValue: announcedOrder[Int(index)])
    }

    func info(command: Int32) throws -> GenTLInfoValue {
        condition.lock()
        defer { condition.unlock() }
        switch command {
        case 0: return .string("0") // STREAM_INFO_ID
        case 1: return .uint64(numDelivered)
        case 2: return .uint64(numUnderrun)
        case 3: return .uint64(UInt64(announcedOrder.count))
        case 4: return .uint64(UInt64(inputQueue.count))
        case 5: return .uint64(UInt64(outputQueue.count))
        case 6: return .uint64(numStarted)
        case 7: return .uint64(UInt64(payloadSize))
        case 8: return .bool8(isGrabbing)
        case 9: return .bool8(true)
        case 10: return .string("AMCAM")
        case 11: return .uint64(0) // Amcam does not expose chunk payloads.
        case 12: return .uint64(1) // Minimum announced buffers: one.
        case 13: return .uint64(1) // Byte alignment.
        default: throw GC_ERROR.notAvailable
        }
    }

    func bufferInfo(_ handle: BUFFER_HANDLE, command: Int32) throws -> GenTLInfoValue {
        condition.lock()
        defer { condition.unlock() }
        guard let buffer = buffers[handle.rawValue] else { throw GC_ERROR.invalidBuffer }

        switch command {
        case 0: return .pointer(UInt(bitPattern: buffer.memory))
        case 1: return .uint64(UInt64(buffer.size))
        case 2: return .pointer(buffer.privateData.map(UInt.init(bitPattern:)) ?? 0)
        case 3: return .uint64(buffer.timestampMicroseconds)
        case 4: return .bool8(buffer.newData)
        case 5: return .bool8(buffer.isQueued)
        case 6: return .bool8(buffer.isAcquiring)
        case 7: return .bool8(buffer.isIncomplete)
        case 8: return .string("AMCAM")
        case 9: return .uint64(UInt64(buffer.sizeFilled))
        case 10: return .uint64(UInt64(buffer.width))
        case 11: return .uint64(UInt64(buffer.height))
        case 12, 13, 14, 15: return .uint64(0)
        case 16: return .uint64(buffer.sequence)
        case 17: return .bool8(buffer.sizeFilled > 0)
        case 18: return .uint64(0)
        case 19: return .uint64(1) // IMAGE payload type
        case 20: return .uint64(0x02180014) // PFNC RGB8 packed.
        case 21: return .uint64(4) // PFNC 32-bit namespace.
        case 22: return .uint64(UInt64(buffer.height))
        case 23: return .uint64(0) // No chunk payload.
        case 24: return .uint64(0) // No chunk layout identifier.
        case 25: return .string("") // Not a file payload.
        case 26: return .int32(0) // Pixel endianness is not applicable to RGB8.
        case 27: return .uint64(UInt64(buffer.sizeFilled)) // DATA_SIZE.
        case 28:
            let (nanoseconds, overflow) = buffer.timestampMicroseconds.multipliedReportingOverflow(by: 1_000)
            return .uint64(overflow ? 0 : nanoseconds)
        case 29: return .bool8(buffer.dataLargerThanBuffer)
        case 30: return .bool8(false) // No chunk data.
        case 31: return .bool8(false) // Amcam buffers are not composite.
        default:
            throw GC_ERROR.invalidParameter
        }
    }

    func numberOfBufferParts(_ handle: BUFFER_HANDLE) throws -> UInt32 {
        condition.lock()
        defer { condition.unlock() }
        guard let buffer = buffers[handle.rawValue] else { throw GC_ERROR.invalidBuffer }
        // A frame contains one packed 2D image part. Empty/incomplete buffers
        // have no delivered image payload and therefore expose zero parts.
        return buffer.sizeFilled > 0 ? 1 : 0
    }

    func bufferPartInfo(_ handle: BUFFER_HANDLE, command: Int32) throws -> GenTLInfoValue {
        condition.lock()
        defer { condition.unlock() }
        guard let buffer = buffers[handle.rawValue] else { throw GC_ERROR.invalidBuffer }
        guard buffer.sizeFilled > 0 else { throw GC_ERROR.invalidIndex }

        switch command {
        case 0: return .pointer(UInt(bitPattern: buffer.memory)) // BASE
        case 1: return .uint64(UInt64(buffer.sizeFilled)) // DATA_SIZE
        case 2: return .uint64(1) // PART_DATATYPE_2D_IMAGE
        case 3: return .uint64(0x02180014) // PFNC RGB8 packed
        case 4: return .uint64(4) // PFNC 32-bit namespace
        case 5: return .uint64(UInt64(buffer.width))
        case 6: return .uint64(UInt64(buffer.height))
        case 7, 8, 9, 10, 12, 13: return .uint64(0)
        case 11: return .uint64(UInt64(buffer.height))
        default: throw GC_ERROR.invalidParameter
        }
    }

    func bufferSegmentCount(_ handle: BUFFER_HANDLE) throws -> UInt32 {
        condition.lock()
        defer { condition.unlock() }
        guard buffers[handle.rawValue] != nil else { throw GC_ERROR.invalidBuffer }
        return 1
    }

    func bufferSegmentInfo(_ handle: BUFFER_HANDLE, command: Int32) throws -> GenTLInfoValue {
        condition.lock()
        defer { condition.unlock() }
        guard let buffer = buffers[handle.rawValue] else { throw GC_ERROR.invalidBuffer }

        switch command {
        case 0: return .pointer(UInt(bitPattern: buffer.memory)) // BASE
        case 1: return .uint64(UInt64(buffer.size)) // SIZE
        case 2: return .bool8(buffer.isIncomplete) // IS_INCOMPLETE
        case 3: return .uint64(UInt64(buffer.sizeFilled)) // SIZE_FILLED
        case 4: return .uint64(UInt64(buffer.sizeFilled)) // DATA_SIZE
        default: throw GC_ERROR.invalidParameter
        }
    }

    func bufferInfoStacked(
        _ handle: BUFFER_HANDLE,
        commands: [Int32]
    ) throws -> [Result<GenTLInfoValue, GC_ERROR>] {
        _ = try buffer(handle)
        return commands.map { command in
            infoResult { try bufferInfo(handle, command: command) }
        }
    }

    func bufferPartInfoStacked(
        _ handle: BUFFER_HANDLE,
        requests: [GenTLBufferPartInfoStackedRequest]
    ) throws -> [Result<GenTLInfoValue, GC_ERROR>] {
        _ = try buffer(handle)
        return requests.map { request in
            infoResult {
                guard request.partIndex == 0 else { throw GC_ERROR.invalidIndex }
                return try bufferPartInfo(handle, command: request.command)
            }
        }
    }

    private func infoResult(
        _ operation: () throws -> GenTLInfoValue
    ) -> Result<GenTLInfoValue, GC_ERROR> {
        do {
            return .success(try operation())
        } catch let error as GC_ERROR {
            return .failure(error)
        } catch {
            return .failure(.error)
        }
    }

    private func receive(_ frame: AmcamFrame) {
        condition.lock()
        guard isGrabbing, !finiteStopScheduled else {
            condition.unlock()
            return
        }

        guard let raw = inputQueue.first, let buffer = buffers[raw] else {
            numUnderrun &+= 1
            condition.unlock()
            return
        }

        inputQueue.removeFirst()
        buffer.isQueued = false
        buffer.isAcquiring = true
        numStarted &+= 1

        let frameBytes = frame.bytes.count
        let (minimumBytesPerRow, rowSizeOverflow) =
            frame.width.multipliedReportingOverflow(by: 3)
        let (minimumImageBytes, imageSizeOverflow) =
            frame.bytesPerRow.multipliedReportingOverflow(by: frame.height)

        let geometryIsValid =
            frame.width > 0 &&
            frame.height > 0 &&
            !rowSizeOverflow &&
            !imageSizeOverflow &&
            frame.bytesPerRow >= minimumBytesPerRow &&
            minimumImageBytes >= 0 &&
            frameBytes >= minimumImageBytes

        buffer.dataLargerThanBuffer = frameBytes > buffer.size
        buffer.width = frame.width > 0 ? frame.width : 0
        buffer.height = frame.height > 0 ? frame.height : 0
        buffer.sequence = UInt64(
            frame.sequence ?? UInt32(truncatingIfNeeded: numDelivered &+ 1)
        )
        buffer.timestampMicroseconds = frame.deviceTimestampMicroseconds ?? 0

        guard !buffer.dataLargerThanBuffer, geometryIsValid else {
            buffer.isIncomplete = true
            buffer.newData = true
            buffer.sizeFilled = 0

            let mustStop = completeBufferDelivery(buffer, rawHandle: raw)
            condition.unlock()
            scheduleFiniteStopIfNeeded(mustStop)
            return
        }

        frame.bytes.withUnsafeBytes { source in
            if let base = source.baseAddress, frameBytes > 0 {
                buffer.memory.copyMemory(from: base, byteCount: frameBytes)
            }
        }
        buffer.sizeFilled = frameBytes
        buffer.isIncomplete = false
        buffer.newData = true

        let mustStop = completeBufferDelivery(buffer, rawHandle: raw)
        condition.unlock()
        scheduleFiniteStopIfNeeded(mustStop)
    }

    /// Must be called while the stream condition is locked.
    /// Incomplete buffers are still completed deliveries and count toward a
    /// finite acquisition request.
    private func completeBufferDelivery(
        _ buffer: AmcamBufferRecord,
        rawHandle: UInt
    ) -> Bool {
        buffer.isAcquiring = false
        buffer.isQueued = true
        outputQueue.append(rawHandle)
        numDelivered &+= 1
        publishBufferEvent(buffer)

        let mustStop = finiteAcquisitionCount.map { numDelivered >= $0 } ?? false
        if mustStop {
            finiteStopScheduled = true
        }
        return mustStop
    }

    private func scheduleFiniteStopIfNeeded(_ mustStop: Bool) {
        guard mustStop else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.stopAfterFiniteAcquisition()
        }
    }

    private func stopAfterFiniteAcquisition() {
        do {
            try session.stop()
            condition.lock()
            isGrabbing = false
            finiteAcquisitionCount = nil
            finiteStopScheduled = false
            condition.broadcast()
            condition.unlock()
        } catch {
            publishErrorEvent()
            condition.lock()
            // Keep isGrabbing true after a failed stop: the native session may
            // still own callbacks and buffers, so close must remain blocked.
            finiteAcquisitionCount = nil
            finiteStopScheduled = false
            condition.broadcast()
            condition.unlock()
        }
    }

    private func publishBufferEvent(_ buffer: AmcamBufferRecord) {
        var bufferHandle = buffer.handle.rawValue
        var userPointer = buffer.privateData.map(UInt.init(bitPattern:)) ?? 0
        var payload = Data()
        withUnsafeBytes(of: &bufferHandle) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: &userPointer) { payload.append(contentsOf: $0) }
        for event in events[GenTLEventType.newBuffer.rawValue] ?? [] {
            event.publish(payload)
        }
        condition.broadcast()
    }

    private func publishErrorEvent() {
        let payload = Data()
        condition.lock()
        let errorEvents = events[GenTLEventType.error.rawValue] ?? []
        condition.unlock()
        errorEvents.forEach { $0.publish(payload) }
    }
}
