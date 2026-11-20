import Foundation
@_spi(BackendConvenience) import GenTLAPI

private final class AmcamOpenDeviceRecord: @unchecked Sendable {
    let device: AmcamDevice
    let session: AmcamCameraSession
    let portHandle: PORT_HANDLE

    var dataStreamHandle: DS_HANDLE?

    init(device: AmcamDevice, session: AmcamCameraSession, portHandle: PORT_HANDLE) {
        self.device = device
        self.session = session
        self.portHandle = portHandle
    }
}

/// Amcam-backed implementation of the Swift GenTLAPI contract.
///
/// This is not a GenTL Producer and does not create a .cti file. It maps the
/// GenTL Consumer function model to Amcam SDK operations where corresponding
/// behavior exists. Unsupported register/GenApi operations are not fabricated.
@_spi(BackendConvenience)
public final class AmcamGenTLImplementation: GenTLBackendConvenience, @unchecked Sendable {
    private let sdkLibraryURL: URL
    private let lock = NSRecursiveLock()

    private var driver: AmcamCameraDriver?
    private var initialized = false
    private var systemOpen = false
    private var interfaceOpen = false
    private var discoveredDevices: [AmcamDevice] = []

    private var openDevices: [UInt: AmcamOpenDeviceRecord] = [:]
    private var portOwners: [UInt: DEV_HANDLE] = [:]
    private var dataStreams: [UInt: AmcamDataStreamRecord] = [:]
    private var events: [UInt: AmcamEventRecord] = [:]
    private var bufferHandlesByStream: [UInt: Set<UInt>] = [:]
    private let eventReadCondition = NSCondition()
    private var activeRawEventReads = Set<UInt>()
    private var eventKillGeneration: [UInt: UInt64] = [:]
    private var pendingRawEventData: [UInt: Data] = [:

    // Each C-facing void* handle is backed by a unique allocation. Retired
    // tokens stay allocated until backend destruction so stale handles cannot
    // be recycled into a later object identity.
    private var activeHandleTokens: [UInt: UnsafeMutableRawPointer] = [:]
    private var retiredHandleTokens: [UnsafeMutableRawPointer] = []

    private let lastErrorThreadKey = "AmcamGenTLImplementation.lastError.\(UUID().uuidString)"

    private let systemToken: UnsafeMutableRawPointer
    private let interfaceToken: UnsafeMutableRawPointer
    private let systemHandle: TL_HANDLE
    private let interfaceHandle: IF_HANDLE

    public init(sdkLibraryURL: URL) {
        let systemToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        let interfaceToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        self.sdkLibraryURL = sdkLibraryURL.standardizedFileURL
        self.systemToken = systemToken
        self.interfaceToken = interfaceToken
        self.systemHandle = TL_HANDLE(rawValue: UInt(bitPattern: systemToken))
        self.interfaceHandle = IF_HANDLE(rawValue: UInt(bitPattern: interfaceToken))
    }

    deinit {
        lock.lock()
        eventReadCondition.lock()
        let canRelease = !initialized &&
            !systemOpen &&
            !interfaceOpen &&
            openDevices.isEmpty &&
            dataStreams.isEmpty &&
            events.isEmpty &&
            activeRawEventReads.isEmpty &&
            pendingRawEventData.isEmpty
        let active = Array(activeHandleTokens.values)
        let retired = retiredHandleTokens
        activeHandleTokens.removeAll()
        retiredHandleTokens.removeAll()
        eventReadCondition.unlock()
        lock.unlock()

        // If cleanup was not proven complete, leave tokens allocated. A leaked
        // opaque token is safer than recycling an address still held by a client.
        guard canRelease else { return }
        (active + retired).forEach { $0.deallocate() }
        systemToken.deallocate()
        interfaceToken.deallocate()
    }

    public var genTLVersion: GenTLVersion { .v1_6 }

    // MARK: Library

    public func swiftGCInitLib() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !initialized else {
            try fail(.resourceInUse, "GCInitLib was already called.")
        }

        do {
            driver = try AmcamCameraDriver(libraryURL: sdkLibraryURL)
            initialized = true
            setLastError(.success, message: "No Error")
        } catch {
            try fail(.error, error.localizedDescription)
        }
    }

    public func swiftGCCloseLib() throws {
        lock.lock()
        defer { lock.unlock() }

        try requireInitialized()
        guard !systemOpen, !interfaceOpen,
              openDevices.isEmpty, dataStreams.isEmpty, events.isEmpty else {
            try fail(.resourceInUse, "Close all Amcam systems, interfaces, devices, streams and events before GCCloseLib.")
        }

        // All module and event handles must already have been closed.
        driver = nil
        discoveredDevices.removeAll(keepingCapacity: false)
        portOwners.removeAll(keepingCapacity: false)
        interfaceOpen = false
        systemOpen = false
        initialized = false
        setLastError(.success, message: "No Error")
    }

    public func GCGetInfo(command: Int32) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        switch command {
        case 0: return .string("Amcam")
        case 1: return .string("AmScope")
        case 2: return .string("Amcam SDK GenTL API compatibility backend")
        case 3: return .string(AmcamSDK.expectedVersion)
        case 4: return .string("Custom")
        case 5: return .string(sdkLibraryURL.lastPathComponent)
        case 6: return .string(sdkLibraryURL.path)
        case 7: return .string("AmScope Amcam")
        case 8: return .int32(GenTLCharacterEncoding.utf8.rawValue)
        case 9: return .uint32(1) // TL_INFO_GENTL_VER_MAJOR
        case 10: return .uint32(6) // TL_INFO_GENTL_VER_MINOR
        default: try fail(.invalidParameter)
        }
    }

    public func GCGetLastError() -> GenTLErrorInfo {
        lock.lock()
        defer { lock.unlock() }
        return Thread.current.threadDictionary[lastErrorThreadKey] as? GenTLErrorInfo
            ?? GenTLErrorInfo(code: .success, message: "No Error")
    }

    // MARK: System

    public func TLOpen() throws -> TL_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        guard !systemOpen else { try fail(.resourceInUse, "The Amcam GenTL system is already open.") }
        systemOpen = true
        return systemHandle
    }

    public func TLClose(_ hTL: TL_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        if interfaceOpen {
            try IFClose(interfaceHandle)
        }
        discoveredDevices.removeAll(keepingCapacity: false)
        systemOpen = false
    }

    public func TLGetInfo(_ hTL: TL_HANDLE, command: Int32) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        return try GCGetInfo(command: command)
    }

    public func TLGetNumInterfaces(_ hTL: TL_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        return 1
    }

    public func TLGetInterfaceID(_ hTL: TL_HANDLE, index: UInt32) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        guard index == 0 else { try fail(.invalidIndex) }
        return "amcam-sdk-interface"
    }

    public func TLGetInterfaceInfo(
        _ hTL: TL_HANDLE,
        interfaceID: String,
        command: Int32
    ) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        guard interfaceID == "amcam-sdk-interface" else { try fail(.invalidID) }
        switch command {
        case 0: return .string(interfaceID)
        case 1: return .string("Amcam SDK managed interface")
        case 2: return .string("Custom")
        default: try fail(.invalidParameter)
        }
    }

    public func TLUpdateInterfaceList(_ hTL: TL_HANDLE, timeout: UInt64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        // The Amcam SDK exposes a single SDK-managed interface. Device changes
        // are observed by IFUpdateDeviceList.
        return false
    }

    public func TLOpenInterface(_ hTL: TL_HANDLE, interfaceID: String) throws -> IF_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        guard interfaceID == "amcam-sdk-interface" else { try fail(.invalidID) }
        guard !interfaceOpen else { try fail(.resourceInUse, "The Amcam interface is already open.") }
        interfaceOpen = true
        return interfaceHandle
    }

    // MARK: Interface

    public func IFClose(_ hIF: IF_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        // IFClose closes every Device module owned by this interface. DevClose
        // in turn closes its dependent Data Stream and unregisters its events.
        for deviceHandle in Array(openDevices.keys) {
            try DevClose(DEV_HANDLE(rawValue: deviceHandle))
        }
        discoveredDevices.removeAll(keepingCapacity: false)
        interfaceOpen = false
    }

    public func IFGetInfo(_ hIF: IF_HANDLE, command: Int32) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        switch command {
        case 0: return .string("amcam-sdk-interface")
        case 1: return .string("Amcam SDK managed interface")
        case 2: return .string("Custom")
        default: try fail(.invalidParameter)
        }
    }

    public func IFUpdateDeviceList(_ hIF: IF_HANDLE, timeout: UInt64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        guard let driver else { try fail(.notInitialized) }

        let previousIDs = discoveredDevices.map(\.identifier)
        let updated: [AmcamDevice]
        do {
            updated = try driver.discover()
        } catch {
            try fail(.error, error.localizedDescription)
        }

        let updatedIDs = updated.map(\.identifier)
        guard updated.count <= Int(UInt32.max) else {
            try fail(.resourceExhausted)
        }
        guard updatedIDs.allSatisfy({ !$0.isEmpty }),
              Set(updatedIDs).count == updatedIDs.count else {
            try fail(.invalidID, "The Amcam SDK returned an empty or duplicate device identifier.")
        }

        discoveredDevices = updated
        setLastError(.success, message: "No Error")
        return previousIDs != updatedIDs
    }

    public func IFGetNumDevices(_ hIF: IF_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        guard discoveredDevices.count <= Int(UInt32.max) else { try fail(.resourceExhausted) }
        return UInt32(discoveredDevices.count)
    }

    public func IFGetDeviceID(_ hIF: IF_HANDLE, index: UInt32) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        guard Int(index) < discoveredDevices.count else { try fail(.invalidIndex) }
        return discoveredDevices[Int(index)].identifier
    }

    public func IFGetDeviceInfo(
        _ hIF: IF_HANDLE,
        deviceID: String,
        command: Int32
    ) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        guard let device = discoveredDevices.first(where: { $0.identifier == deviceID }) else {
            try fail(.invalidID)
        }
        return try deviceInfo(device, command: command, isOpen: openDevices.values.contains { $0.device.identifier == deviceID })
    }

    public func IFOpenDevice(
        _ hIF: IF_HANDLE,
        deviceID: String,
        accessFlags: Int32
    ) throws -> DEV_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)

        // Amcam_Open exposes one read/write camera handle. It has no SDK
        // operation for GenTL read-only access or the shared CONTROL mode,
        // so accepting those requests would falsely claim stronger access
        // semantics than this backend can provide.
        guard let requestedAccess = GenTLDeviceAccess(rawValue: accessFlags) else {
            try fail(.invalidParameter, "Unsupported GenTL device access flag: \(accessFlags).")
        }
        switch requestedAccess {
        case .exclusive:
            break
        case .readOnly, .control:
            try fail(
                .accessDenied,
                "The Amcam SDK only supports exclusive read/write access; it cannot honor GenTL read-only or CONTROL access."
            )
        case .unknown, .none:
            try fail(
                .invalidParameter,
                "GenTL DEVICE_ACCESS_UNKNOWN and DEVICE_ACCESS_NONE are not valid IFOpenDevice requests."
            )
        }

        guard let device = discoveredDevices.first(where: { $0.identifier == deviceID }) else {
            try fail(.invalidID)
        }
        guard openDevices.values.allSatisfy({ $0.device.identifier != deviceID }) else {
            try fail(.resourceInUse, "The Amcam device is already open through this implementation.")
        }
        guard let driver else { try fail(.notInitialized) }

        do {
            let session = try driver.open(deviceIdentifier: deviceID)
            let deviceHandle = DEV_HANDLE(rawValue: allocateHandle())
            let portHandle = PORT_HANDLE(rawValue: allocateHandle())
            openDevices[deviceHandle.rawValue] = AmcamOpenDeviceRecord(
                device: device,
                session: session,
                portHandle: portHandle
            )
            portOwners[portHandle.rawValue] = deviceHandle
            return deviceHandle
        } catch let error as GC_ERROR {
            setLastError(error, message: String(describing: error))
            throw error
        } catch {
            try fail(.accessDenied, error.localizedDescription)
        }
    }

    public func IFGetParentTL(_ hIF: IF_HANDLE) throws -> TL_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        return systemHandle
    }

    // MARK: Device

    public func DevGetPort(_ hDevice: DEV_HANDLE) throws -> PORT_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        let record = try deviceRecord(hDevice)
        return record.portHandle
    }

    public func DevGetNumDataStreams(_ hDevice: DEV_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        _ = try deviceRecord(hDevice)
        return 1
    }

    public func DevGetDataStreamID(_ hDevice: DEV_HANDLE, index: UInt32) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        _ = try deviceRecord(hDevice)
        guard index == 0 else { try fail(.invalidIndex) }
        return "0"
    }

    public func DevOpenDataStream(_ hDevice: DEV_HANDLE, dataStreamID: String) throws -> DS_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        let record = try deviceRecord(hDevice)
        guard dataStreamID == "0" else { try fail(.invalidID) }
        guard record.dataStreamHandle == nil else { try fail(.resourceInUse) }

        let handle = DS_HANDLE(rawValue: allocateHandle())
        let stream: AmcamDataStreamRecord
        do {
            stream = try recordErrors {
                try AmcamDataStreamRecord(
                    handle: handle,
                    deviceHandle: hDevice,
                    session: record.session
                )
            }
        } catch {
            retireHandle(handle.rawValue)
            throw error
        }
        dataStreams[handle.rawValue] = stream
        bufferHandlesByStream[handle.rawValue] = []
        record.dataStreamHandle = handle
        return handle
    }

    public func DevGetInfo(_ hDevice: DEV_HANDLE, command: Int32) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        let record = try deviceRecord(hDevice)
        return try deviceInfo(record.device, command: command, isOpen: true)
    }

    public func DevGetParentIF(_ hDevice: DEV_HANDLE) throws -> IF_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        _ = try deviceRecord(hDevice)
        return interfaceHandle
    }

    public func DevClose(_ hDevice: DEV_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        let record = try deviceRecord(hDevice)
        if let streamHandle = record.dataStreamHandle {
            try DSClose(streamHandle)
        }
        do {
            try record.session.close()
        } catch {
            try fail(.error, error.localizedDescription)
        }
        openDevices.removeValue(forKey: hDevice.rawValue)
        portOwners.removeValue(forKey: record.portHandle.rawValue)
        retireHandle(hDevice.rawValue)
        retireHandle(record.portHandle.rawValue)
    }

    // MARK: Data Stream and Buffers

    public func DSAnnounceBuffer(
        _ hDS: DS_HANDLE,
        memory: GenTLBufferMemory,
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        let stream = try recordErrors { try streamRecord(hDS) }
        let handle = BUFFER_HANDLE(rawValue: allocateHandle())
        do {
            try recordErrors {
                try stream.announce(
                    handle: handle,
                    memory: memory.baseAddress,
                    size: memory.size,
                    privateData: privateData,
                    allocatedByProvider: false
                )
            }
        } catch {
            retireHandle(handle.rawValue)
            throw error
        }
        bufferHandlesByStream[hDS.rawValue, default: []].insert(handle.rawValue)
        return handle
    }

    public func DSAllocAndAnnounceBuffer(
        _ hDS: DS_HANDLE,
        size: Int,
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        let stream = try recordErrors { try streamRecord(hDS) }
        guard size > 0, size <= 1_073_741_824 else { try fail(.invalidParameter) }

        let pointer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 64)
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let handle = BUFFER_HANDLE(rawValue: allocateHandle())
        do {
            try recordErrors {
                try stream.announce(
                    handle: handle,
                    memory: pointer,
                    size: size,
                    privateData: privateData,
                    allocatedByProvider: true
                )
            }
        } catch {
            pointer.deallocate()
            retireHandle(handle.rawValue)
            throw error
        }
        bufferHandlesByStream[hDS.rawValue, default: []].insert(handle.rawValue)
        return handle
    }

    public func DSQueueBuffer(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try recordErrors { try streamRecord(hDS).queue(buffer) }
    }

    public func DSFlushQueue(_ hDS: DS_HANDLE, operation: Int32) throws {
        lock.lock()
        defer { lock.unlock() }
        try recordErrors { try streamRecord(hDS).flush(operation: operation) }
    }

    public func DSStartAcquisition(
        _ hDS: DS_HANDLE,
        flags: Int32,
        numberToAcquire: UInt64
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard flags == GenTLAcquisitionStartFlag.normal.rawValue else {
            try fail(.notImplemented)
        }
        try recordErrors { try streamRecord(hDS).start(numberToAcquire: numberToAcquire) }
    }

    public func DSStopAcquisition(_ hDS: DS_HANDLE, flags: Int32) throws {
        lock.lock()
        defer { lock.unlock() }
        // Amcam_Stop provides the SDK's orderly stop operation. It does not
        // expose a distinct immediate-kill semantic.
        guard flags == GenTLAcquisitionStopFlag.normal.rawValue else {
            try fail(.notImplemented)
        }
        try recordErrors { try streamRecord(hDS).stop() }
    }

    public func DSGetInfo(_ hDS: DS_HANDLE, command: Int32) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        return try recordErrors { try streamRecord(hDS).info(command: command) }
    }

    public func DSGetBufferID(_ hDS: DS_HANDLE, index: UInt32) throws -> BUFFER_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        return try recordErrors { try streamRecord(hDS).bufferID(index: index) }
    }

    public func DSGetBufferInfo(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        command: Int32
    ) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        return try recordErrors { try streamRecord(hDS).bufferInfo(buffer, command: command) }
    }

    public func DSRevokeBuffer(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE
    ) throws -> GenTLRevokedBuffer {
        lock.lock()
        defer { lock.unlock() }
        let revoked = try recordErrors { try streamRecord(hDS).revoke(buffer) }
        bufferHandlesByStream[hDS.rawValue]?.remove(buffer.rawValue)
        retireHandle(buffer.rawValue)
        return revoked
    }

    public func DSGetParentDev(_ hDS: DS_HANDLE) throws -> DEV_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        return try recordErrors { try streamRecord(hDS).deviceHandle }
    }

    public func DSClose(_ hDS: DS_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        let stream = try recordErrors { try streamRecord(hDS) }

        let streamEvents = events.filter { _, record in
            record.source == .dataStream(hDS)
        }
        for (eventHandle, record) in streamEvents {
            eventReadCondition.lock()
            eventKillGeneration[eventHandle, default: 0] &+= 1
            eventReadCondition.broadcast()
            eventReadCondition.unlock()
            stream.unregisterEvent(record)
            events.removeValue(forKey: eventHandle)
            eventReadCondition.lock()
            pendingRawEventData.removeValue(forKey: eventHandle)
            eventReadCondition.broadcast()
            eventReadCondition.unlock()
            retireHandle(eventHandle)
        }

        try recordErrors { try stream.close() }
        dataStreams.removeValue(forKey: hDS.rawValue)
        for bufferHandle in bufferHandlesByStream.removeValue(forKey: hDS.rawValue) ?? [] {
            retireHandle(bufferHandle)
        }
        retireHandle(hDS.rawValue)
        if let record = openDevices[stream.deviceHandle.rawValue] {
            record.dataStreamHandle = nil
        }
    }

    // MARK: GenTL 1.5 / 1.6 multipart, chunk and flow metadata

    public func DSGetBufferChunkData(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE
    ) throws -> [GenTLChunkData] {
        lock.lock()
        defer { lock.unlock() }
        let stream = try streamRecord(hDS)
        _ = try recordErrors { try stream.buffer(buffer) }
        // The Amcam pull API returns a plain RGB image buffer; no chunk payload
        // is exposed by the SDK wrapper.
        try fail(.notAvailable)
    }

    public func DSGetNumBufferParts(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE
    ) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        return try recordErrors { try streamRecord(hDS).numberOfBufferParts(buffer) }
    }

    public func DSGetBufferPartInfo(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        partIndex: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        guard partIndex == 0 else { try fail(.invalidIndex) }
        return try recordErrors { try streamRecord(hDS).bufferPartInfo(buffer, command: command) }
    }

    public func DSAnnounceCompositeBuffer(
        _ hDS: DS_HANDLE,
        segments: [GenTLCompositeBufferSegment],
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        _ = try streamRecord(hDS)
        // Amcam_PullImageV2 produces one contiguous RGB frame. It has no
        // segmented transport payload to announce as a composite buffer.
        try fail(.notImplemented)
    }

    public func DSGetBufferInfoStacked(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        commands: [Int32]
    ) throws -> [Result<GenTLInfoValue, GC_ERROR>] {
        lock.lock()
        defer { lock.unlock() }
        return try recordErrors { try streamRecord(hDS).bufferInfoStacked(buffer, commands: commands) }
    }

    public func DSGetBufferPartInfoStacked(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        requests: [GenTLBufferPartInfoStackedRequest]
    ) throws -> [Result<GenTLInfoValue, GC_ERROR>] {
        lock.lock()
        defer { lock.unlock() }
        return try recordErrors { try streamRecord(hDS).bufferPartInfoStacked(buffer, requests: requests) }
    }

    public func DSGetNumFlows(_ hDS: DS_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        _ = try streamRecord(hDS)
        return 0
    }

    public func DSGetFlowInfo(
        _ hDS: DS_HANDLE,
        flowIndex: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        _ = try streamRecord(hDS)
        try fail(.invalidIndex)
    }

    public func DSGetNumBufferSegments(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE
    ) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        return try recordErrors { try streamRecord(hDS).bufferSegmentCount(buffer) }
    }

    public func DSGetBufferSegmentInfo(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        segmentIndex: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        guard segmentIndex == 0 else { try fail(.invalidIndex) }
        return try recordErrors { try streamRecord(hDS).bufferSegmentInfo(buffer, command: command) }
    }

    // MARK: Signaling

    public func GCRegisterEvent(
        _ source: EVENTSRC_HANDLE,
        eventType: Int32
    ) throws -> EVENT_HANDLE {
        lock.lock()
        defer { lock.unlock() }

        let type = eventType
        guard GenTLEventType(rawValue: type) != nil else {
            try fail(.invalidParameter)
        }
        guard type == GenTLEventType.newBuffer.rawValue ||
              type == GenTLEventType.error.rawValue else {
            try fail(.notImplemented)
        }

        guard case .dataStream(let streamHandle) = source else {
            try fail(.notImplemented)
        }
        guard !events.values.contains(where: {
            $0.source == source && $0.eventType == type
        }) else {
            try fail(.resourceInUse)
        }

        let stream = try streamRecord(streamHandle)
        let eventHandle = EVENT_HANDLE(rawValue: allocateHandle())
        let event = AmcamEventRecord(handle: eventHandle, eventType: type, source: source)
        events[eventHandle.rawValue] = event
        stream.addEvent(event)
        return eventHandle
    }

    public func GCUnregisterEvent(
        _ source: EVENTSRC_HANDLE,
        eventType: Int32
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let type = eventType
        guard GenTLEventType(rawValue: type) != nil else {
            try fail(.invalidParameter)
        }

        guard let match = events.first(where: {
            $0.value.source == source && $0.value.eventType == type
        }) else {
            try fail(.invalidHandle)
        }

        guard case .dataStream(let streamHandle) = source,
              let stream = dataStreams[streamHandle.rawValue] else {
            try fail(.invalidHandle)
        }
        eventReadCondition.lock()
        eventKillGeneration[match.key, default: 0] &+= 1
        eventReadCondition.broadcast()
        eventReadCondition.unlock()
        stream.unregisterEvent(match.value)
        events.removeValue(forKey: match.key)
        eventReadCondition.lock()
        pendingRawEventData.removeValue(forKey: match.key)
        eventReadCondition.broadcast()
        eventReadCondition.unlock()
        retireHandle(match.key)
    }

    public func EventGetData(_ event: EVENT_HANDLE, timeout: UInt64) throws -> Data {
        lock.lock()
        let record = events[event.rawValue]
        let stream: AmcamDataStreamRecord?
        if let record, case .dataStream(let streamHandle) = record.source {
            stream = dataStreams[streamHandle.rawValue]
        } else {
            stream = nil
        }
        lock.unlock()

        guard let record, let stream else { try fail(.invalidHandle) }
        return try recordErrors { try stream.nextEventData(record, timeoutMilliseconds: timeout) }
    }

    public func EventGetDataInfo(
        _ event: EVENT_HANDLE,
        inputData: Data,
        command: Int32
    ) throws -> GenTLInfoValue {
        lock.lock()
        let isRegistered = events[event.rawValue] != nil
        lock.unlock()
        guard isRegistered else { try fail(.invalidHandle) }

        // The Amcam callback API does not define GenTL event IDs or a stable
        // transport-specific EventGetDataInfo schema. Do not synthesize one.
        _ = inputData
        guard GenTLInfoCommand.EventData(rawValue: command) != nil else {
            try fail(.invalidParameter)
        }
        try fail(.notImplemented)
    }

    public func EventGetInfo(_ event: EVENT_HANDLE, command: Int32) throws -> GenTLInfoValue {
        lock.lock()
        let record = events[event.rawValue]
        let stream: AmcamDataStreamRecord?
        if let record, case .dataStream(let streamHandle) = record.source {
            stream = dataStreams[streamHandle.rawValue]
        } else {
            stream = nil
        }
        lock.unlock()

        guard let record, let stream else { try fail(.invalidHandle) }
        return try recordErrors { try stream.eventInfo(record, command: command) }
    }

    public func EventFlush(_ event: EVENT_HANDLE) throws {
        lock.lock()
        let record = events[event.rawValue]
        let stream: AmcamDataStreamRecord?
        if let record, case .dataStream(let streamHandle) = record.source {
            stream = dataStreams[streamHandle.rawValue]
        } else {
            stream = nil
        }
        lock.unlock()

        guard let record, let stream else { try fail(.invalidHandle) }
        try recordErrors { try stream.flushEvent(record) }
    }

    public func EventKill(_ event: EVENT_HANDLE) throws {
        lock.lock()
        let record = events[event.rawValue]
        let stream: AmcamDataStreamRecord?
        if let record, case .dataStream(let streamHandle) = record.source {
            stream = dataStreams[streamHandle.rawValue]
        } else {
            stream = nil
        }
        lock.unlock()

        guard let record, let stream else { try fail(.invalidHandle) }
        try recordErrors { try stream.abortOneEventRead(record) }
    }

    // MARK: Port

    public func GCReadPort(_ hPort: PORT_HANDLE, address: UInt64, size: Int) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        _ = try requirePort(hPort)
        _ = address
        guard size >= 0 else { try fail(.invalidParameter) }
        try fail(.notImplemented)
    }

    public func GCWritePort(_ hPort: PORT_HANDLE, address: UInt64, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        _ = try requirePort(hPort)
        _ = address
        _ = data
        try fail(.notImplemented)
    }

    public func GCGetPortURL(_ hPort: PORT_HANDLE) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        _ = try requirePort(hPort)
        // Amcam does not provide a GenApi XML URL through this SDK.
        try fail(.notAvailable)
    }

    public func GCGetNumPortURLs(_ hPort: PORT_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        _ = try requirePort(hPort)
        return 0
    }

    public func GCGetPortURLInfo(
        _ hPort: PORT_HANDLE,
        index: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        _ = try requirePort(hPort)
        guard index == 0 else { try fail(.invalidIndex) }
        _ = command
        try fail(.invalidIndex)
    }

    public func GCGetPortInfo(_ hPort: PORT_HANDLE, command: Int32) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        _ = try requirePort(hPort)
        guard GenTLInfoCommand.Port(rawValue: command) != nil else {
            try fail(.invalidParameter)
        }
        try fail(.notImplemented)
    }

    public func GCReadPortStacked(
        _ hPort: PORT_HANDLE,
        requests: [GenTLPortReadRequest]
    ) throws -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        _ = try requirePort(hPort)
        _ = requests
        try fail(.notImplemented)
    }

    public func GCWritePortStacked(
        _ hPort: PORT_HANDLE,
        requests: [GenTLPortWriteRequest]
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        _ = try requirePort(hPort)
        _ = requests
        try fail(.notImplemented)
    }

    // Amcam exposes feature getters/setters through its SDK, not a documented
    // remote register map or GenApi XML port. Register access is intentionally
    // NOT_IMPLEMENTED until a verified virtual register map is introduced.

    // MARK: Internal validation and metadata

    private func deviceInfo(
        _ device: AmcamDevice,
        command: Int32,
        isOpen: Bool
    ) throws -> GenTLInfoValue {
        switch command {
        case 0: return .string(device.identifier)
        case 1: return .string("AmScope")
        case 2: return .string(device.modelName ?? "Unknown Amcam camera")
        case 3: return .string("Custom")
        case 4: return .string(device.displayName)
        // The Amcam SDK does not expose a non-invasive access-status query.
        // Report UNKNOWN until this backend owns the camera; do not claim it is
        // available for read/write merely because it was discoverable.
        case 5:
            return .int32(
                isOpen
                    ? GenTLDeviceAccessStatus.openReadWrite.rawValue
                    : GenTLDeviceAccessStatus.unknown.rawValue
            )
        case 6: try fail(.notAvailable)
        case 7: try fail(.notAvailable) // SDK ID is opaque, not a verified serial number.
        case 8: try fail(.notAvailable) // SDK does not expose a camera firmware version.
        case 9: return .uint64(1_000_000) // Amcam FrameInfoV2 timestamps are microseconds.
        default: try fail(.invalidParameter)
        }
    }

    private func allocateHandle() -> UInt {
        let token = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        let value = UInt(bitPattern: token)
        activeHandleTokens[value] = token
        return value
    }

    private func retireHandle(_ value: UInt) {
        guard let token = activeHandleTokens.removeValue(forKey: value) else { return }
        retiredHandleTokens.append(token)
    }

    private func rawHandle<Tag: Hashable & Sendable>(_ handle: GenTLHandle<Tag>) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: handle.rawValue)
    }

    private func typedHandle<Tag: Hashable & Sendable>(
        _ pointer: UnsafeMutableRawPointer?,
        as type: Tag.Type
    ) throws -> GenTLHandle<Tag> {
        guard let pointer else { try fail(.invalidHandle) }
        return GenTLHandle<Tag>(rawValue: UInt(bitPattern: pointer))
    }

    private func requireInitialized() throws {
        guard initialized, driver != nil else { try fail(.notInitialized) }
    }

    private func requireSystem(_ handle: TL_HANDLE) throws {
        try requireInitialized()
        guard systemOpen, handle == systemHandle else { try fail(.invalidHandle) }
    }

    private func requireInterface(_ handle: IF_HANDLE) throws {
        try requireSystem(systemHandle)
        guard interfaceOpen, handle == interfaceHandle else { try fail(.invalidHandle) }
    }

    private func deviceRecord(_ handle: DEV_HANDLE) throws -> AmcamOpenDeviceRecord {
        try requireInterface(interfaceHandle)
        guard let record = openDevices[handle.rawValue] else { try fail(.invalidHandle) }
        return record
    }

    private func streamRecord(_ handle: DS_HANDLE) throws -> AmcamDataStreamRecord {
        try requireInterface(interfaceHandle)
        guard let record = dataStreams[handle.rawValue] else { try fail(.invalidHandle) }
        return record
    }

    private func requirePort(_ handle: PORT_HANDLE) throws -> AmcamOpenDeviceRecord {
        try requireInterface(interfaceHandle)
        guard let deviceHandle = portOwners[handle.rawValue],
              let record = openDevices[deviceHandle.rawValue] else {
            try fail(.invalidHandle)
        }
        return record
    }

    private func setLastError(_ code: GC_ERROR, message: String) {
        Thread.current.threadDictionary[lastErrorThreadKey] = GenTLErrorInfo(
            code: code,
            message: message
        )
    }

    private func fail(
        _ code: GC_ERROR,
        _ message: String? = nil
    ) throws -> Never {
        setLastError(code, message: message ?? String(describing: code))
        throw code
    }

    /// Records errors propagated from the stream/session runtime at the public
    /// GenTL API boundary, preserving the returned GenTL error code.
    private func recordErrors<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let code as GC_ERROR {
            setLastError(code, message: String(describing: code))
            throw code
        } catch {
            setLastError(.error, message: error.localizedDescription)
            throw GC_ERROR.error
        }
    }
}


extension AmcamGenTLImplementation: GenTLAPI {
    // MARK: GenTL C-boundary conversion

    private func rawError(_ error: Error) -> GenTLABI.GC_ERROR {
        if let code = error as? GC_ERROR {
            setLastError(code, message: String(describing: code))
            return code.rawValue
        }
        setLastError(.error, message: error.localizedDescription)
        return GenTLABI.GC_ERR_ERROR
    }

    private func rawStatus(_ operation: () throws -> Void) -> GenTLABI.GC_ERROR {
        do {
            try operation()
            return GenTLABI.GC_ERR_SUCCESS
        } catch {
            return rawError(error)
        }
    }

    private func rawHandle<Tag: Hashable & Sendable>(
        _ handle: GenTLHandle<Tag>
    ) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: handle.rawValue)
    }

    private func typedHandle<Tag: Hashable & Sendable>(
        _ pointer: UnsafeMutableRawPointer?,
        as type: Tag.Type
    ) throws -> GenTLHandle<Tag> {
        guard let pointer else { try fail(.invalidHandle) }
        let rawValue = UInt(bitPattern: pointer)
        lock.lock()
        let isKnown = rawValue == UInt(bitPattern: systemToken) ||
            rawValue == UInt(bitPattern: interfaceToken) ||
            activeHandleTokens[rawValue] != nil
        lock.unlock()
        guard isKnown else { try fail(.invalidHandle) }
        return GenTLHandle<Tag>(rawValue: rawValue)
    }

    private func readCString(_ pointer: UnsafePointer<CChar>?) throws -> String {
        guard let pointer else { try fail(.invalidParameter) }
        return String(cString: pointer)
    }

    private func dataBytes<T>(of value: T) -> Data {
        var copy = value
        return withUnsafeBytes(of: &copy) { Data($0) }
    }

    private func infoBytes(_ value: GenTLInfoValue) -> (GenTLABI.INFO_DATATYPE, Data) {
        switch value {
        case .string(let string):
            return (GenTLABI.INFO_DATATYPE_STRING, Data(string.utf8CString.map { UInt8(bitPattern: $0) }))
        case .stringList(let strings):
            var bytes: [UInt8] = []
            for string in strings {
                bytes.append(contentsOf: string.utf8)
                bytes.append(0)
            }
            bytes.append(0)
            return (GenTLABI.INFO_DATATYPE_STRINGLIST, Data(bytes))
        case .int16(let value): return (GenTLABI.INFO_DATATYPE_INT16, dataBytes(of: value))
        case .uint16(let value): return (GenTLABI.INFO_DATATYPE_UINT16, dataBytes(of: value))
        case .int32(let value): return (GenTLABI.INFO_DATATYPE_INT32, dataBytes(of: value))
        case .uint32(let value): return (GenTLABI.INFO_DATATYPE_UINT32, dataBytes(of: value))
        case .int64(let value): return (GenTLABI.INFO_DATATYPE_INT64, dataBytes(of: value))
        case .uint64(let value): return (GenTLABI.INFO_DATATYPE_UINT64, dataBytes(of: value))
        case .float64(let value): return (GenTLABI.INFO_DATATYPE_FLOAT64, dataBytes(of: value))
        case .pointer(let value): return (GenTLABI.INFO_DATATYPE_PTR, dataBytes(of: value))
        case .bool8(let value): return (GenTLABI.INFO_DATATYPE_BOOL8, dataBytes(of: UInt8(value ? 1 : 0)))
        case .size(let value): return (GenTLABI.INFO_DATATYPE_SIZET, dataBytes(of: UInt(value)))
        case .raw(let data): return (GenTLABI.INFO_DATATYPE_BUFFER, data)
        case .opaque(let dataType, let data): return (dataType, data)
        case .pointerDifference(let value): return (GenTLABI.INFO_DATATYPE_PTRDIFF, dataBytes(of: value))
        }
    }

    private func writeData(
        _ data: Data,
        output: UnsafeMutableRawPointer?,
        size: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let size else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        let capacity = size.pointee
        guard capacity >= 0 else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        size.pointee = data.count
        guard !data.isEmpty else { return GenTLABI.GC_ERR_SUCCESS }
        guard let output, capacity >= data.count else {
            return GenTLABI.GC_ERR_BUFFER_TOO_SMALL
        }
        data.withUnsafeBytes { source in
            if let base = source.baseAddress {
                output.copyMemory(from: base, byteCount: source.count)
            }
        }
        return GenTLABI.GC_ERR_SUCCESS
    }

    private func writeCString(
        _ string: String,
        output: UnsafeMutablePointer<CChar>?,
        size: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        let bytes = Data(string.utf8CString.map { UInt8(bitPattern: $0) })
        return writeData(bytes, output: output.map { UnsafeMutableRawPointer($0) }, size: size)
    }

    private func writeInfo(
        _ value: GenTLInfoValue,
        type: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        output: UnsafeMutableRawPointer?,
        size: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        let (kind, bytes) = infoBytes(value)
        type?.pointee = kind
        return writeData(bytes, output: output, size: size)
    }

    private func eventSource(_ pointer: GenTLABI.EVENTSRC_HANDLE) throws -> EVENTSRC_HANDLE {
        guard let pointer else { try fail(.invalidHandle) }
        let rawValue = UInt(bitPattern: pointer)
        lock.lock()
        let isKnown = activeHandleTokens[rawValue] != nil
        let isDataStream = dataStreams[rawValue] != nil
        lock.unlock()
        guard isKnown else { try fail(.invalidHandle) }
        guard isDataStream else { try fail(.notImplemented) }
        return .dataStream(DS_HANDLE(rawValue: rawValue))
    }

    private func validBuffer(_ pointer: GenTLABI.BUFFER_HANDLE, in stream: DS_HANDLE) -> BUFFER_HANDLE? {
        guard let pointer else { return nil }
        let rawValue = UInt(bitPattern: pointer)
        lock.lock()
        let isValid = bufferHandlesByStream[stream.rawValue]?.contains(rawValue) == true
        lock.unlock()
        guard isValid else { return nil }
        return BUFFER_HANDLE(rawValue: rawValue)
    }

    private func writeStackedInfo(
        _ value: GenTLInfoValue,
        entry: inout GenTLABI.DS_BUFFER_INFO_STACKED
    ) -> GenTLABI.GC_ERROR {
        let (kind, bytes) = infoBytes(value)
        let capacity = entry.iSize
        entry.iType = kind
        entry.iSize = bytes.count
        guard capacity >= 0 else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        guard !bytes.isEmpty else { return GenTLABI.GC_ERR_SUCCESS }
        guard let output = entry.pBuffer, capacity >= bytes.count else {
            return GenTLABI.GC_ERR_BUFFER_TOO_SMALL
        }
        bytes.withUnsafeBytes { source in
            if let base = source.baseAddress {
                output.copyMemory(from: base, byteCount: source.count)
            }
        }
        return GenTLABI.GC_ERR_SUCCESS
    }

    private func writeStackedPartInfo(
        _ value: GenTLInfoValue,
        entry: inout GenTLABI.DS_BUFFER_PART_INFO_STACKED
    ) -> GenTLABI.GC_ERROR {
        let (kind, bytes) = infoBytes(value)
        let capacity = entry.iSize
        entry.iType = kind
        entry.iSize = bytes.count
        guard capacity >= 0 else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        guard !bytes.isEmpty else { return GenTLABI.GC_ERR_SUCCESS }
        guard let output = entry.pBuffer, capacity >= bytes.count else {
            return GenTLABI.GC_ERR_BUFFER_TOO_SMALL
        }
        bytes.withUnsafeBytes { source in
            if let base = source.baseAddress {
                output.copyMemory(from: base, byteCount: source.count)
            }
        }
        return GenTLABI.GC_ERR_SUCCESS
    }

    // MARK: Library

    public func GCInitLib() -> GenTLABI.GC_ERROR {
        rawStatus { try swiftGCInitLib() }
    }

    public func GCCloseLib() -> GenTLABI.GC_ERROR {
        rawStatus { try swiftGCCloseLib() }
    }

    public func GCGetInfo(
        _ iInfoCmd: GenTLABI.TL_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            return writeInfo(
                try GCGetInfo(command: iInfoCmd),
                type: piType,
                output: pBuffer,
                size: piSize
            )
        } catch {
            return rawError(error)
        }
    }

    public func GCGetLastError(
        _ piErrorCode: UnsafeMutablePointer<GenTLABI.GC_ERROR>?,
        _ sErrText: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        let value = GCGetLastError()
        piErrorCode?.pointee = value.code.rawValue
        return writeCString(value.message, output: sErrText, size: piSize)
    }

    // MARK: Port

    public func GCReadPort(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iAddress: UInt64,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let pBuffer, let piSize else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let data = try GCReadPort(typedHandle(hPort, as: PORTModule.self), address: iAddress, size: piSize.pointee)
            return writeData(data, output: pBuffer, size: piSize)
        } catch {
            return rawError(error)
        }
    }

    public func GCWritePort(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iAddress: UInt64,
        _ pBuffer: UnsafeRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let pBuffer, let piSize, piSize.pointee >= 0 else {
            return GenTLABI.GC_ERR_INVALID_PARAMETER
        }
        let bytes = Data(bytes: pBuffer, count: piSize.pointee)
        return rawStatus {
            try GCWritePort(typedHandle(hPort, as: PORTModule.self), address: iAddress, data: bytes)
        }
    }

    public func GCGetPortURL(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ sURL: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            return writeCString(
                try GCGetPortURL(typedHandle(hPort, as: PORTModule.self)),
                output: sURL,
                size: piSize
            )
        } catch {
            return rawError(error)
        }
    }

    public func GCGetPortInfo(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iInfoCmd: GenTLABI.PORT_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try GCGetPortInfo(typedHandle(hPort, as: PORTModule.self), command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch {
            return rawError(error)
        }
    }

    public func GCGetNumPortURLs(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ piNumURLs: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        guard let piNumURLs else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            piNumURLs.pointee = try GCGetNumPortURLs(typedHandle(hPort, as: PORTModule.self))
            return GenTLABI.GC_ERR_SUCCESS
        } catch {
            return rawError(error)
        }
    }

    public func GCGetPortURLInfo(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iURLIndex: UInt32,
        _ iInfoCmd: GenTLABI.URL_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try GCGetPortURLInfo(
                typedHandle(hPort, as: PORTModule.self),
                index: iURLIndex,
                command: iInfoCmd
            )
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch {
            return rawError(error)
        }
    }

    public func GCReadPortStacked(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ pEntries: UnsafeMutablePointer<GenTLABI.PORT_REGISTER_STACK_ENTRY>?,
        _ piNumEntries: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let pEntries, let piNumEntries, piNumEntries.pointee >= 0 else {
            return GenTLABI.GC_ERR_INVALID_PARAMETER
        }
        do {
            let port = try typedHandle(hPort, as: PORTModule.self)
            let count = piNumEntries.pointee
            for index in 0..<count {
                let entry = pEntries[index]
                guard entry.Size >= 0, let buffer = entry.pBuffer else {
                    return GenTLABI.GC_ERR_INVALID_PARAMETER
                }
                let bytes = try GCReadPort(port, address: entry.Address, size: entry.Size)
                guard bytes.count == entry.Size else { return GenTLABI.GC_ERR_INVALID_VALUE }
                bytes.withUnsafeBytes { source in
                    if let base = source.baseAddress {
                        buffer.copyMemory(from: base, byteCount: source.count)
                    }
                }
            }
            return GenTLABI.GC_ERR_SUCCESS
        } catch {
            return rawError(error)
        }
    }

    public func GCWritePortStacked(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ pEntries: UnsafeMutablePointer<GenTLABI.PORT_REGISTER_STACK_ENTRY>?,
        _ piNumEntries: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let pEntries, let piNumEntries, piNumEntries.pointee >= 0 else {
            return GenTLABI.GC_ERR_INVALID_PARAMETER
        }
        do {
            let port = try typedHandle(hPort, as: PORTModule.self)
            for index in 0..<piNumEntries.pointee {
                let entry = pEntries[index]
                guard entry.Size >= 0, let buffer = entry.pBuffer else {
                    return GenTLABI.GC_ERR_INVALID_PARAMETER
                }
                try GCWritePort(port, address: entry.Address, data: Data(bytes: buffer, count: entry.Size))
            }
            return GenTLABI.GC_ERR_SUCCESS
        } catch {
            return rawError(error)
        }
    }

    // MARK: System

    public func TLOpen(_ phTL: UnsafeMutablePointer<GenTLABI.TL_HANDLE>?) -> GenTLABI.GC_ERROR {
        guard let phTL else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phTL.pointee = rawHandle(try TLOpen())
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func TLClose(_ hTL: GenTLABI.TL_HANDLE) -> GenTLABI.GC_ERROR {
        rawStatus { try TLClose(try typedHandle(hTL, as: TLModule.self)) }
    }

    public func TLGetInfo(
        _ hTL: GenTLABI.TL_HANDLE, _ iInfoCmd: GenTLABI.TL_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try TLGetInfo(typedHandle(hTL, as: TLModule.self), command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func TLGetNumInterfaces(_ hTL: GenTLABI.TL_HANDLE, _ piNumIfaces: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR {
        guard let piNumIfaces else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            piNumIfaces.pointee = try TLGetNumInterfaces(typedHandle(hTL, as: TLModule.self))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func TLGetInterfaceID(
        _ hTL: GenTLABI.TL_HANDLE, _ iIndex: UInt32,
        _ sID: UnsafeMutablePointer<CChar>?, _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try TLGetInterfaceID(typedHandle(hTL, as: TLModule.self), index: iIndex)
            return writeCString(value, output: sID, size: piSize)
        } catch { return rawError(error) }
    }

    public func TLGetInterfaceInfo(
        _ hTL: GenTLABI.TL_HANDLE, _ sIfaceID: UnsafePointer<CChar>?,
        _ iInfoCmd: GenTLABI.INTERFACE_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try TLGetInterfaceInfo(
                typedHandle(hTL, as: TLModule.self),
                interfaceID: readCString(sIfaceID),
                command: iInfoCmd
            )
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func TLOpenInterface(
        _ hTL: GenTLABI.TL_HANDLE, _ sIfaceID: UnsafePointer<CChar>?,
        _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard let phIface else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phIface.pointee = rawHandle(try TLOpenInterface(
                typedHandle(hTL, as: TLModule.self),
                interfaceID: readCString(sIfaceID)
            ))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func TLUpdateInterfaceList(
        _ hTL: GenTLABI.TL_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        do {
            let changed = try TLUpdateInterfaceList(typedHandle(hTL, as: TLModule.self), timeout: iTimeout)
            guard let pbChanged else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
            pbChanged.pointee = changed ? 1 : 0
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    // MARK: Interface

    public func IFClose(_ hIface: GenTLABI.IF_HANDLE) -> GenTLABI.GC_ERROR {
        rawStatus { try IFClose(try typedHandle(hIface, as: IFModule.self)) }
    }

    public func IFGetInfo(
        _ hIface: GenTLABI.IF_HANDLE, _ iInfoCmd: GenTLABI.INTERFACE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try IFGetInfo(typedHandle(hIface, as: IFModule.self), command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func IFGetNumDevices(_ hIface: GenTLABI.IF_HANDLE, _ piNumDevices: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR {
        guard let piNumDevices else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            piNumDevices.pointee = try IFGetNumDevices(typedHandle(hIface, as: IFModule.self))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func IFGetDeviceID(
        _ hIface: GenTLABI.IF_HANDLE, _ iIndex: UInt32,
        _ sDeviceID: UnsafeMutablePointer<CChar>?, _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try IFGetDeviceID(typedHandle(hIface, as: IFModule.self), index: iIndex)
            return writeCString(value, output: sDeviceID, size: piSize)
        } catch { return rawError(error) }
    }

    public func IFUpdateDeviceList(
        _ hIface: GenTLABI.IF_HANDLE, _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        do {
            let changed = try IFUpdateDeviceList(typedHandle(hIface, as: IFModule.self), timeout: iTimeout)
            guard let pbChanged else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
            pbChanged.pointee = changed ? 1 : 0
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func IFGetDeviceInfo(
        _ hIface: GenTLABI.IF_HANDLE, _ sDeviceID: UnsafePointer<CChar>?,
        _ iInfoCmd: GenTLABI.DEVICE_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try IFGetDeviceInfo(
                typedHandle(hIface, as: IFModule.self),
                deviceID: readCString(sDeviceID),
                command: iInfoCmd
            )
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func IFOpenDevice(
        _ hIface: GenTLABI.IF_HANDLE, _ sDeviceID: UnsafePointer<CChar>?,
        _ iOpenFlag: GenTLABI.DEVICE_ACCESS_FLAGS, _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard let phDevice else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phDevice.pointee = rawHandle(try IFOpenDevice(
                typedHandle(hIface, as: IFModule.self),
                deviceID: readCString(sDeviceID),
                accessFlags: iOpenFlag
            ))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    // MARK: Device

    public func DevGetPort(_ hDevice: GenTLABI.DEV_HANDLE, _ phRemoteDevice: UnsafeMutablePointer<GenTLABI.PORT_HANDLE>?) -> GenTLABI.GC_ERROR {
        guard let phRemoteDevice else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phRemoteDevice.pointee = rawHandle(try DevGetPort(typedHandle(hDevice, as: DEVModule.self)))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DevGetNumDataStreams(_ hDevice: GenTLABI.DEV_HANDLE, _ piNumDataStreams: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR {
        guard let piNumDataStreams else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            piNumDataStreams.pointee = try DevGetNumDataStreams(typedHandle(hDevice, as: DEVModule.self))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DevGetDataStreamID(
        _ hDevice: GenTLABI.DEV_HANDLE, _ iIndex: UInt32,
        _ sDataStreamID: UnsafeMutablePointer<CChar>?, _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            return writeCString(
                try DevGetDataStreamID(typedHandle(hDevice, as: DEVModule.self), index: iIndex),
                output: sDataStreamID,
                size: piSize
            )
        } catch { return rawError(error) }
    }

    public func DevOpenDataStream(
        _ hDevice: GenTLABI.DEV_HANDLE, _ sDataStreamID: UnsafePointer<CChar>?,
        _ phDataStream: UnsafeMutablePointer<GenTLABI.DS_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard let phDataStream else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phDataStream.pointee = rawHandle(try DevOpenDataStream(
                typedHandle(hDevice, as: DEVModule.self),
                dataStreamID: readCString(sDataStreamID)
            ))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DevGetInfo(
        _ hDevice: GenTLABI.DEV_HANDLE, _ iInfoCmd: GenTLABI.DEVICE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try DevGetInfo(typedHandle(hDevice, as: DEVModule.self), command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func DevClose(_ hDevice: GenTLABI.DEV_HANDLE) -> GenTLABI.GC_ERROR {
        rawStatus { try DevClose(try typedHandle(hDevice, as: DEVModule.self)) }
    }

    // MARK: Data Stream / Buffer

    public func DSAnnounceBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE, _ pBuffer: UnsafeMutableRawPointer?, _ iSize: Int,
        _ pPrivate: UnsafeMutableRawPointer?, _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard let pBuffer, let phBuffer, iSize > 0 else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let handle = try DSAnnounceBuffer(
                typedHandle(hDataStream, as: DSModule.self),
                memory: GenTLBufferMemory(baseAddress: pBuffer, size: iSize),
                privateData: pPrivate
            )
            phBuffer.pointee = rawHandle(handle)
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSAllocAndAnnounceBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE, _ iSize: Int, _ pPrivate: UnsafeMutableRawPointer?,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard let phBuffer else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let handle = try DSAllocAndAnnounceBuffer(
                typedHandle(hDataStream, as: DSModule.self), size: iSize, privateData: pPrivate
            )
            phBuffer.pointee = rawHandle(handle)
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSFlushQueue(_ hDataStream: GenTLABI.DS_HANDLE, _ iOperation: GenTLABI.ACQ_QUEUE_TYPE) -> GenTLABI.GC_ERROR {
        rawStatus { try DSFlushQueue(typedHandle(hDataStream, as: DSModule.self), operation: iOperation) }
    }

    public func DSStartAcquisition(
        _ hDataStream: GenTLABI.DS_HANDLE, _ iStartFlags: GenTLABI.ACQ_START_FLAGS, _ iNumToAcquire: UInt64
    ) -> GenTLABI.GC_ERROR {
        rawStatus { try DSStartAcquisition(typedHandle(hDataStream, as: DSModule.self), flags: iStartFlags, numberToAcquire: iNumToAcquire) }
    }

    public func DSStopAcquisition(_ hDataStream: GenTLABI.DS_HANDLE, _ iStopFlags: GenTLABI.ACQ_STOP_FLAGS) -> GenTLABI.GC_ERROR {
        rawStatus { try DSStopAcquisition(typedHandle(hDataStream, as: DSModule.self), flags: iStopFlags) }
    }

    public func DSGetInfo(
        _ hDataStream: GenTLABI.DS_HANDLE, _ iInfoCmd: GenTLABI.STREAM_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try DSGetInfo(typedHandle(hDataStream, as: DSModule.self), command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func DSGetBufferID(
        _ hDataStream: GenTLABI.DS_HANDLE, _ iIndex: UInt32,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard let phBuffer else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phBuffer.pointee = rawHandle(try DSGetBufferID(typedHandle(hDataStream, as: DSModule.self), index: iIndex))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSClose(_ hDataStream: GenTLABI.DS_HANDLE) -> GenTLABI.GC_ERROR {
        rawStatus { try DSClose(typedHandle(hDataStream, as: DSModule.self)) }
    }

    public func DSRevokeBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ ppBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
        _ ppPrivate: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> GenTLABI.GC_ERROR {
        guard let ppBuffer, let ppPrivate else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            let revoked = try DSRevokeBuffer(stream, buffer: buffer)
            ppBuffer.pointee = revoked.baseAddress
            ppPrivate.pointee = revoked.privateData
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSQueueBuffer(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE) -> GenTLABI.GC_ERROR {
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            try DSQueueBuffer(stream, buffer: buffer)
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSGetBufferInfo(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ iInfoCmd: GenTLABI.BUFFER_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            let value = try DSGetBufferInfo(stream, buffer: buffer, command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    // MARK: GenTL extensions

    public func DSGetBufferChunkData(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pChunkData: UnsafeMutablePointer<GenTLABI.SINGLE_CHUNK_DATA>?, _ piNumChunks: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let piNumChunks else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            let chunks = try DSGetBufferChunkData(stream, buffer: buffer)
            let capacity = piNumChunks.pointee
            piNumChunks.pointee = chunks.count
            guard capacity >= chunks.count else { return GenTLABI.GC_ERR_BUFFER_TOO_SMALL }
            guard chunks.isEmpty || pChunkData != nil else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
            for index in chunks.indices {
                pChunkData![index].ChunkID = chunks[index].chunkID
                pChunkData![index].ChunkOffset = Int(chunks[index].offset)
                pChunkData![index].ChunkLength = chunks[index].length
            }
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func IFGetParentTL(_ hIface: GenTLABI.IF_HANDLE, _ phSystem: UnsafeMutablePointer<GenTLABI.TL_HANDLE>?) -> GenTLABI.GC_ERROR {
        guard let phSystem else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phSystem.pointee = rawHandle(try IFGetParentTL(typedHandle(hIface, as: IFModule.self)))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DevGetParentIF(_ hDevice: GenTLABI.DEV_HANDLE, _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE>?) -> GenTLABI.GC_ERROR {
        guard let phIface else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phIface.pointee = rawHandle(try DevGetParentIF(typedHandle(hDevice, as: DEVModule.self)))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSGetParentDev(_ hDataStream: GenTLABI.DS_HANDLE, _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE>?) -> GenTLABI.GC_ERROR {
        guard let phDevice else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            phDevice.pointee = rawHandle(try DSGetParentDev(typedHandle(hDataStream, as: DSModule.self)))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSGetNumBufferParts(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ piNumParts: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        guard let piNumParts else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            piNumParts.pointee = try DSGetNumBufferParts(stream, buffer: buffer)
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSGetBufferPartInfo(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ iPartIndex: UInt32,
        _ iInfoCmd: GenTLABI.BUFFER_PART_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            let value = try DSGetBufferPartInfo(stream, buffer: buffer, partIndex: iPartIndex, command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func DSAnnounceCompositeBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE, _ iNumSegments: Int,
        _ ppSegments: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ piSizes: UnsafeMutablePointer<Int>?,
        _ pPrivate: UnsafeMutableRawPointer?, _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        GenTLABI.GC_ERR_NOT_IMPLEMENTED
    }

    public func DSGetBufferInfoStacked(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pInfoStacked: UnsafeMutablePointer<GenTLABI.DS_BUFFER_INFO_STACKED>?, _ iNumInfos: Int
    ) -> GenTLABI.GC_ERROR {
        guard iNumInfos >= 0, iNumInfos == 0 || pInfoStacked != nil else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            let commands = (0..<iNumInfos).map { pInfoStacked![$0].iInfoCmd }
            let values = try DSGetBufferInfoStacked(stream, buffer: buffer, commands: commands)
            var aggregate: GenTLABI.GC_ERROR = GenTLABI.GC_ERR_SUCCESS
            for index in values.indices {
                switch values[index] {
                case .success(let value):
                    let status = writeStackedInfo(value, entry: &pInfoStacked![index])
                    pInfoStacked![index].iResult = status
                    if status != GenTLABI.GC_ERR_SUCCESS { aggregate = status }
                case .failure(let error):
                    pInfoStacked![index].iResult = error.rawValue
                    if aggregate == GenTLABI.GC_ERR_SUCCESS { aggregate = error.rawValue }
                }
            }
            return aggregate == GenTLABI.GC_ERR_BUFFER_TOO_SMALL ? GenTLABI.GC_ERR_SUCCESS : aggregate
        } catch { return rawError(error) }
    }

    public func DSGetBufferPartInfoStacked(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pInfoStacked: UnsafeMutablePointer<GenTLABI.DS_BUFFER_PART_INFO_STACKED>?, _ iNumInfos: Int
    ) -> GenTLABI.GC_ERROR {
        guard iNumInfos >= 0, iNumInfos == 0 || pInfoStacked != nil else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            let requests = (0..<iNumInfos).map {
                GenTLBufferPartInfoStackedRequest(partIndex: pInfoStacked![$0].iPartIndex, command: pInfoStacked![$0].iInfoCmd)
            }
            let values = try DSGetBufferPartInfoStacked(stream, buffer: buffer, requests: requests)
            var aggregate: GenTLABI.GC_ERROR = GenTLABI.GC_ERR_SUCCESS
            for index in values.indices {
                switch values[index] {
                case .success(let value):
                    let status = writeStackedPartInfo(value, entry: &pInfoStacked![index])
                    pInfoStacked![index].iResult = status
                    if status != GenTLABI.GC_ERR_SUCCESS { aggregate = status }
                case .failure(let error):
                    pInfoStacked![index].iResult = error.rawValue
                    if aggregate == GenTLABI.GC_ERR_SUCCESS { aggregate = error.rawValue }
                }
            }
            return aggregate == GenTLABI.GC_ERR_BUFFER_TOO_SMALL ? GenTLABI.GC_ERR_SUCCESS : aggregate
        } catch { return rawError(error) }
    }

    public func DSGetNumFlows(_ hDataStream: GenTLABI.DS_HANDLE, _ piNumFlows: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR {
        guard let piNumFlows else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            piNumFlows.pointee = try DSGetNumFlows(typedHandle(hDataStream, as: DSModule.self))
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSGetFlowInfo(
        _ hDataStream: GenTLABI.DS_HANDLE, _ iFlowIndex: UInt32, _ iInfoCmd: GenTLABI.FLOW_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let value = try DSGetFlowInfo(typedHandle(hDataStream, as: DSModule.self), flowIndex: iFlowIndex, command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func DSGetNumBufferSegments(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ piNumSegments: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        guard let piNumSegments else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            piNumSegments.pointee = try DSGetNumBufferSegments(stream, buffer: buffer)
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func DSGetBufferSegmentInfo(
        _ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ iSegmentIndex: UInt32,
        _ iInfoCmd: GenTLABI.SEGMENT_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        do {
            let stream = try typedHandle(hDataStream, as: DSModule.self)
            guard let buffer = validBuffer(hBuffer, in: stream) else { try fail(.invalidBuffer) }
            let value = try DSGetBufferSegmentInfo(stream, buffer: buffer, segmentIndex: iSegmentIndex, command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    // MARK: Events

    public func GCRegisterEvent(
        _ hEventSrc: GenTLABI.EVENTSRC_HANDLE, _ iEventID: GenTLABI.EVENT_TYPE,
        _ phEvent: UnsafeMutablePointer<GenTLABI.EVENT_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard let phEvent else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        do {
            let source = try eventSource(hEventSrc)
            let event = try GCRegisterEvent(source, eventType: iEventID)
            phEvent.pointee = rawHandle(event)
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func GCUnregisterEvent(
        _ hEventSrc: GenTLABI.EVENTSRC_HANDLE, _ iEventID: GenTLABI.EVENT_TYPE
    ) -> GenTLABI.GC_ERROR {
        do {
            try GCUnregisterEvent(eventSource(hEventSrc), eventType: iEventID)
            return GenTLABI.GC_ERR_SUCCESS
        } catch { return rawError(error) }
    }

    public func EventGetData(
        _ hEvent: GenTLABI.EVENT_HANDLE, _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?, _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        guard let piSize, let hEvent else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        let key = UInt(bitPattern: hEvent)
        let capacity = piSize.pointee
        guard capacity >= 0 else { return GenTLABI.GC_ERR_INVALID_PARAMETER }

        // Serialize retrieval per event so an undersized destination can retain
        // the dequeued payload for the caller's retry instead of losing it.
        eventReadCondition.lock()
        let startingGeneration = eventKillGeneration[key, default: 0]
        while activeRawEventReads.contains(key) {
            eventReadCondition.wait()
        }
        guard eventKillGeneration[key, default: 0] == startingGeneration else {
            eventReadCondition.unlock()
            return GenTLABI.GC_ERR_ABORT
        }
        activeRawEventReads.insert(key)
        let pending = pendingRawEventData.removeValue(forKey: key)
        eventReadCondition.unlock()

        defer {
            eventReadCondition.lock()
            activeRawEventReads.remove(key)
            eventReadCondition.broadcast()
            eventReadCondition.unlock()
        }

        let event = EVENT_HANDLE(rawValue: key)
        do {
            let data: Data
            if let pending {
                data = pending
            } else {
                data = try EventGetData(event, timeout: iTimeout)
            }
            piSize.pointee = data.count

            // A NULL data pointer discards the queued event payload.
            guard let pBuffer else { return GenTLABI.GC_ERR_SUCCESS }

            guard capacity >= data.count else {
                eventReadCondition.lock()
                pendingRawEventData[key] = data
                eventReadCondition.unlock()
                return GenTLABI.GC_ERR_BUFFER_TOO_SMALL
            }

            if !data.isEmpty {
                data.withUnsafeBytes { source in
                    if let base = source.baseAddress {
                        pBuffer.copyMemory(from: base, byteCount: source.count)
                    }
                }
            }
            return GenTLABI.GC_ERR_SUCCESS
        } catch {
            return rawError(error)
        }
    }

    public func EventGetDataInfo(
        _ hEvent: GenTLABI.EVENT_HANDLE, _ pInBuffer: UnsafeRawPointer?, _ iInSize: Int,
        _ iInfoCmd: GenTLABI.EVENT_DATA_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pOutBuffer: UnsafeMutableRawPointer?, _ piOutSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let hEvent, iInSize >= 0, (iInSize == 0 || pInBuffer != nil) else {
            return GenTLABI.GC_ERR_INVALID_PARAMETER
        }
        let event = EVENT_HANDLE(rawValue: UInt(bitPattern: hEvent))
        let input = pInBuffer.map { Data(bytes: $0, count: iInSize) } ?? Data()
        do {
            let value = try EventGetDataInfo(event, inputData: input, command: iInfoCmd)
            return writeInfo(value, type: piType, output: pOutBuffer, size: piOutSize)
        } catch { return rawError(error) }
    }

    public func EventGetInfo(
        _ hEvent: GenTLABI.EVENT_HANDLE, _ iInfoCmd: GenTLABI.EVENT_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let hEvent else { return GenTLABI.GC_ERR_INVALID_HANDLE }
        do {
            let value = try EventGetInfo(EVENT_HANDLE(rawValue: UInt(bitPattern: hEvent)), command: iInfoCmd)
            return writeInfo(value, type: piType, output: pBuffer, size: piSize)
        } catch { return rawError(error) }
    }

    public func EventFlush(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR {
        guard let hEvent else { return GenTLABI.GC_ERR_INVALID_HANDLE }
        let key = UInt(bitPattern: hEvent)
        let status = rawStatus { try EventFlush(EVENT_HANDLE(rawValue: key)) }
        if status == GenTLABI.GC_ERR_SUCCESS {
            eventReadCondition.lock()
            pendingRawEventData.removeValue(forKey: key)
            eventReadCondition.unlock()
        }
        return status
    }

    public func EventKill(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR {
        guard let hEvent else { return GenTLABI.GC_ERR_INVALID_HANDLE }
        let key = UInt(bitPattern: hEvent)
        eventReadCondition.lock()
        eventKillGeneration[key, default: 0] &+= 1
        eventReadCondition.broadcast()
        eventReadCondition.unlock()
        return rawStatus { try EventKill(EVENT_HANDLE(rawValue: key)) }
    }
}
