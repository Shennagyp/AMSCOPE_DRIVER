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
        let canRelease = !initialized &&
            !systemOpen &&
            !interfaceOpen &&
            openDevices.isEmpty &&
            dataStreams.isEmpty &&
            events.isEmpty
        let active = Array(activeHandleTokens.values)
        let retired = retiredHandleTokens
        activeHandleTokens.removeAll()
        retiredHandleTokens.removeAll()
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
        let stream = try recordErrors {
            try AmcamDataStreamRecord(
                handle: handle,
                deviceHandle: hDevice,
                session: record.session
            )
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
        try recordErrors {
            try stream.announce(
                handle: handle,
                memory: memory.baseAddress,
                size: memory.size,
                privateData: privateData,
                allocatedByProvider: false
            )
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
            stream.unregisterEvent(record)
            events.removeValue(forKey: eventHandle)
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
        stream.unregisterEvent(match.value)
        events.removeValue(forKey: match.key)
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

    private func rawHandle<Tag>(_ handle: GenTLHandle<Tag>) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: handle.rawValue)
    }

    private func typedHandle<Tag>(
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
