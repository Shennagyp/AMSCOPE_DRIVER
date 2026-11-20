import Darwin
import Foundation
@_spi(BackendConvenience) import GenTLAPI

// MARK: GenTL C ABI function pointer types
//
// These aliases come directly from the PGC/P* typedefs in GenTL_v1_6.h.
// Do not restate @convention(c) signatures here: the standard header is the
// single authority for calling convention and parameter ABI.

private typealias GCInitLibFunction = PGCInitLib
private typealias GCCloseLibFunction = PGCCloseLib
private typealias GCGetInfoFunction = PGCGetInfo
private typealias GCGetLastErrorFunction = PGCGetLastError

private typealias TLOpenFunction = PTLOpen
private typealias TLCloseFunction = PTLClose
private typealias TLGetInfoFunction = PTLGetInfo
private typealias TLGetNumInterfacesFunction = PTLGetNumInterfaces
private typealias TLGetInterfaceIDFunction = PTLGetInterfaceID
private typealias TLGetInterfaceInfoFunction = PTLGetInterfaceInfo
private typealias TLUpdateInterfaceListFunction = PTLUpdateInterfaceList
private typealias TLOpenInterfaceFunction = PTLOpenInterface

private typealias IFCloseFunction = PIFClose
private typealias IFGetInfoFunction = PIFGetInfo
private typealias IFGetNumDevicesFunction = PIFGetNumDevices
private typealias IFGetDeviceIDFunction = PIFGetDeviceID
private typealias IFUpdateDeviceListFunction = PIFUpdateDeviceList
private typealias IFGetDeviceInfoFunction = PIFGetDeviceInfo
private typealias IFOpenDeviceFunction = PIFOpenDevice
private typealias IFGetParentTLFunction = PIFGetParentTL

private typealias DevGetPortFunction = PDevGetPort
private typealias DevGetNumDataStreamsFunction = PDevGetNumDataStreams
private typealias DevGetDataStreamIDFunction = PDevGetDataStreamID
private typealias DevOpenDataStreamFunction = PDevOpenDataStream
private typealias DevGetInfoFunction = PDevGetInfo
private typealias DevGetParentIFFunction = PDevGetParentIF
private typealias DevCloseFunction = PDevClose

private typealias DSAnnounceBufferFunction = PDSAnnounceBuffer
private typealias DSAllocAndAnnounceBufferFunction = PDSAllocAndAnnounceBuffer
private typealias DSQueueBufferFunction = PDSQueueBuffer
private typealias DSFlushQueueFunction = PDSFlushQueue
private typealias DSStartAcquisitionFunction = PDSStartAcquisition
private typealias DSStopAcquisitionFunction = PDSStopAcquisition
private typealias DSGetInfoFunction = PDSGetInfo
private typealias DSGetBufferIDFunction = PDSGetBufferID
private typealias DSGetBufferInfoFunction = PDSGetBufferInfo
private typealias DSRevokeBufferFunction = PDSRevokeBuffer
private typealias DSCloseFunction = PDSClose
private typealias DSGetParentDevFunction = PDSGetParentDev

private typealias GCReadPortFunction = PGCReadPort
private typealias GCWritePortFunction = PGCWritePort
private typealias GCGetPortURLFunction = PGCGetPortURL
private typealias GCGetPortInfoFunction = PGCGetPortInfo
private typealias GCGetNumPortURLsFunction = PGCGetNumPortURLs
private typealias GCGetPortURLInfoFunction = PGCGetPortURLInfo

private typealias GCRegisterEventFunction = PGCRegisterEvent
private typealias GCUnregisterEventFunction = PGCUnregisterEvent
private typealias EventGetDataFunction = PEventGetData
private typealias EventGetDataInfoFunction = PEventGetDataInfo
private typealias EventGetInfoFunction = PEventGetInfo
private typealias EventFlushFunction = PEventFlush
private typealias EventKillFunction = PEventKill

private typealias GCReadPortStackedFunction = PGCReadPortStacked
private typealias GCWritePortStackedFunction = PGCWritePortStacked
private typealias DSGetBufferChunkDataFunction = PDSGetBufferChunkData
private typealias DSGetNumBufferPartsFunction = PDSGetNumBufferParts
private typealias DSGetBufferPartInfoFunction = PDSGetBufferPartInfo
private typealias DSAnnounceCompositeBufferFunction = PDSAnnounceCompositeBuffer
private typealias DSGetNumFlowsFunction = PDSGetNumFlows
private typealias DSGetFlowInfoFunction = PDSGetFlowInfo
private typealias DSGetNumBufferSegmentsFunction = PDSGetNumBufferSegments
private typealias DSGetBufferSegmentInfoFunction = PDSGetBufferSegmentInfo
private typealias DSGetBufferInfoStackedFunction = PDSGetBufferInfoStacked
private typealias DSGetBufferPartInfoStackedFunction = PDSGetBufferPartInfoStacked

private final class GenTLProducerLibraryRetainer: @unchecked Sendable {
    static let shared = GenTLProducerLibraryRetainer()

    private let lock = NSLock()
    private var libraries: [GenTLProducerLibrary] = []

    func retain(_ library: GenTLProducerLibrary) {
        lock.lock()
        defer { lock.unlock() }
        libraries.append(library)
    }
}

/// GenTL Consumer implementation backed by a manufacturer-supplied .cti Producer.
///
/// The implementation owns one loaded CTI library. Handles returned by the
/// Producer remain opaque and are never synthesized or reinterpreted as IDs.
/// Keeps a CTI loaded if its GenTL lifecycle was not cleanly closed.
/// Unloading a Producer with open module handles would invalidate native code
/// and callback pointers still owned by that Producer.
@_spi(BackendFactory)
public final class GenTLNativeImplementation: @unchecked Sendable {
    private struct Functions {
        let gcInitLib: GCInitLibFunction
        let gcCloseLib: GCCloseLibFunction
        let gcGetInfo: GCGetInfoFunction
        let gcGetLastError: GCGetLastErrorFunction

        let tlOpen: TLOpenFunction
        let tlClose: TLCloseFunction
        let tlGetInfo: TLGetInfoFunction
        let tlGetNumInterfaces: TLGetNumInterfacesFunction
        let tlGetInterfaceID: TLGetInterfaceIDFunction
        let tlGetInterfaceInfo: TLGetInterfaceInfoFunction
        let tlUpdateInterfaceList: TLUpdateInterfaceListFunction
        let tlOpenInterface: TLOpenInterfaceFunction

        let ifClose: IFCloseFunction
        let ifGetInfo: IFGetInfoFunction
        let ifGetNumDevices: IFGetNumDevicesFunction
        let ifGetDeviceID: IFGetDeviceIDFunction
        let ifUpdateDeviceList: IFUpdateDeviceListFunction
        let ifGetDeviceInfo: IFGetDeviceInfoFunction
        let ifOpenDevice: IFOpenDeviceFunction
        let ifGetParentTL: IFGetParentTLFunction?

        let devGetPort: DevGetPortFunction
        let devGetNumDataStreams: DevGetNumDataStreamsFunction
        let devGetDataStreamID: DevGetDataStreamIDFunction
        let devOpenDataStream: DevOpenDataStreamFunction
        let devGetInfo: DevGetInfoFunction
        let devGetParentIF: DevGetParentIFFunction?
        let devClose: DevCloseFunction

        let dsAnnounceBuffer: DSAnnounceBufferFunction
        let dsAllocAndAnnounceBuffer: DSAllocAndAnnounceBufferFunction
        let dsQueueBuffer: DSQueueBufferFunction
        let dsFlushQueue: DSFlushQueueFunction
        let dsStartAcquisition: DSStartAcquisitionFunction
        let dsStopAcquisition: DSStopAcquisitionFunction
        let dsGetInfo: DSGetInfoFunction
        let dsGetBufferID: DSGetBufferIDFunction
        let dsGetBufferInfo: DSGetBufferInfoFunction
        let dsRevokeBuffer: DSRevokeBufferFunction
        let dsGetParentDev: DSGetParentDevFunction?
        let dsClose: DSCloseFunction

        let gcReadPort: GCReadPortFunction
        let gcWritePort: GCWritePortFunction
        let gcGetPortURL: GCGetPortURLFunction
        let gcGetNumPortURLs: GCGetNumPortURLsFunction?
        let gcGetPortURLInfo: GCGetPortURLInfoFunction?
        let gcGetPortInfo: GCGetPortInfoFunction

        let gcRegisterEvent: GCRegisterEventFunction
        let gcUnregisterEvent: GCUnregisterEventFunction
        let eventGetData: EventGetDataFunction
        let eventGetDataInfo: EventGetDataInfoFunction
        let eventGetInfo: EventGetInfoFunction
        let eventFlush: EventFlushFunction
        let eventKill: EventKillFunction

        let gcReadPortStacked: GCReadPortStackedFunction?
        let gcWritePortStacked: GCWritePortStackedFunction?
        let dsGetBufferChunkData: DSGetBufferChunkDataFunction?
        let dsGetNumBufferParts: DSGetNumBufferPartsFunction?
        let dsGetBufferPartInfo: DSGetBufferPartInfoFunction?
        let dsGetBufferInfoStacked: DSGetBufferInfoStackedFunction?
        let dsGetBufferPartInfoStacked: DSGetBufferPartInfoStackedFunction?
        let dsAnnounceCompositeBuffer: DSAnnounceCompositeBufferFunction?
        let dsGetNumFlows: DSGetNumFlowsFunction?
        let dsGetFlowInfo: DSGetFlowInfoFunction?
        let dsGetNumBufferSegments: DSGetNumBufferSegmentsFunction?
        let dsGetBufferSegmentInfo: DSGetBufferSegmentInfoFunction?
    }

    private let library: GenTLProducerLibrary
    private let functions: Functions
    private let lock = NSRecursiveLock()
    private var initialized = false
    /// EventGetData can block until its timeout (or indefinitely). It must not
    /// hold the API-wide lock, but GCCloseLib must not run while a read is active.
    private struct RegisteredEvent {
        let sourcePointer: UnsafeMutableRawPointer?
        let eventType: Int32
    }

    private var registeredEventsByHandle: [UInt: RegisteredEvent] = [:]
    /// Protected by lock. Prevents new event API calls after unregister begins.
    private var unregisteringEventHandles = Set<UInt>()

    /// EventGetData can block without holding lock. A separate condition tracks
    /// the lifetime of each event handle until its blocked reads have returned.
    private let eventReadCondition = NSCondition()
    private var activeEventDataReadsByHandle: [UInt: Int] = [:]

    public let genTLVersion = GenTLVersion.v1_6

    public static var compiledHeaderVersionCode: UInt32 {
        GenTLABI_HeaderVersion()
    }

    public init(ctiURL: URL) throws {
        let library = try GenTLProducerLibrary(url: ctiURL)

        func load<T>(_ name: String, as type: T.Type) throws -> T {
            let address = try library.resolveSymbol(name)
            return unsafeBitCast(address, to: type)
        }

        self.library = library
        self.functions = try Functions(
            gcInitLib: load("GCInitLib", as: GCInitLibFunction.self),
            gcCloseLib: load("GCCloseLib", as: GCCloseLibFunction.self),
            gcGetInfo: load("GCGetInfo", as: GCGetInfoFunction.self),
            gcGetLastError: load("GCGetLastError", as: GCGetLastErrorFunction.self),

            tlOpen: load("TLOpen", as: TLOpenFunction.self),
            tlClose: load("TLClose", as: TLCloseFunction.self),
            tlGetInfo: load("TLGetInfo", as: TLGetInfoFunction.self),
            tlGetNumInterfaces: load("TLGetNumInterfaces", as: TLGetNumInterfacesFunction.self),
            tlGetInterfaceID: load("TLGetInterfaceID", as: TLGetInterfaceIDFunction.self),
            tlGetInterfaceInfo: load("TLGetInterfaceInfo", as: TLGetInterfaceInfoFunction.self),
            tlUpdateInterfaceList: load("TLUpdateInterfaceList", as: TLUpdateInterfaceListFunction.self),
            tlOpenInterface: load("TLOpenInterface", as: TLOpenInterfaceFunction.self),

            ifClose: load("IFClose", as: IFCloseFunction.self),
            ifGetInfo: load("IFGetInfo", as: IFGetInfoFunction.self),
            ifGetNumDevices: load("IFGetNumDevices", as: IFGetNumDevicesFunction.self),
            ifGetDeviceID: load("IFGetDeviceID", as: IFGetDeviceIDFunction.self),
            ifUpdateDeviceList: load("IFUpdateDeviceList", as: IFUpdateDeviceListFunction.self),
            ifGetDeviceInfo: load("IFGetDeviceInfo", as: IFGetDeviceInfoFunction.self),
            ifOpenDevice: load("IFOpenDevice", as: IFOpenDeviceFunction.self),
            ifGetParentTL: try? load("IFGetParentTL", as: IFGetParentTLFunction.self),

            devGetPort: load("DevGetPort", as: DevGetPortFunction.self),
            devGetNumDataStreams: load("DevGetNumDataStreams", as: DevGetNumDataStreamsFunction.self),
            devGetDataStreamID: load("DevGetDataStreamID", as: DevGetDataStreamIDFunction.self),
            devOpenDataStream: load("DevOpenDataStream", as: DevOpenDataStreamFunction.self),
            devGetInfo: load("DevGetInfo", as: DevGetInfoFunction.self),
            devGetParentIF: try? load("DevGetParentIF", as: DevGetParentIFFunction.self),
            devClose: load("DevClose", as: DevCloseFunction.self),

            dsAnnounceBuffer: load("DSAnnounceBuffer", as: DSAnnounceBufferFunction.self),
            dsAllocAndAnnounceBuffer: load("DSAllocAndAnnounceBuffer", as: DSAllocAndAnnounceBufferFunction.self),
            dsQueueBuffer: load("DSQueueBuffer", as: DSQueueBufferFunction.self),
            dsFlushQueue: load("DSFlushQueue", as: DSFlushQueueFunction.self),
            dsStartAcquisition: load("DSStartAcquisition", as: DSStartAcquisitionFunction.self),
            dsStopAcquisition: load("DSStopAcquisition", as: DSStopAcquisitionFunction.self),
            dsGetInfo: load("DSGetInfo", as: DSGetInfoFunction.self),
            dsGetBufferID: load("DSGetBufferID", as: DSGetBufferIDFunction.self),
            dsGetBufferInfo: load("DSGetBufferInfo", as: DSGetBufferInfoFunction.self),
            dsRevokeBuffer: load("DSRevokeBuffer", as: DSRevokeBufferFunction.self),
            dsGetParentDev: try? load("DSGetParentDev", as: DSGetParentDevFunction.self),
            dsClose: load("DSClose", as: DSCloseFunction.self),

            gcReadPort: load("GCReadPort", as: GCReadPortFunction.self),
            gcWritePort: load("GCWritePort", as: GCWritePortFunction.self),
            gcGetPortURL: load("GCGetPortURL", as: GCGetPortURLFunction.self),
            gcGetNumPortURLs: try? load("GCGetNumPortURLs", as: GCGetNumPortURLsFunction.self),
            gcGetPortURLInfo: try? load("GCGetPortURLInfo", as: GCGetPortURLInfoFunction.self),
            gcGetPortInfo: load("GCGetPortInfo", as: GCGetPortInfoFunction.self),

            gcRegisterEvent: load("GCRegisterEvent", as: GCRegisterEventFunction.self),
            gcUnregisterEvent: load("GCUnregisterEvent", as: GCUnregisterEventFunction.self),
            eventGetData: load("EventGetData", as: EventGetDataFunction.self),
            eventGetDataInfo: load("EventGetDataInfo", as: EventGetDataInfoFunction.self),
            eventGetInfo: load("EventGetInfo", as: EventGetInfoFunction.self),
            eventFlush: load("EventFlush", as: EventFlushFunction.self),
            eventKill: load("EventKill", as: EventKillFunction.self),

            gcReadPortStacked: try? load("GCReadPortStacked", as: GCReadPortStackedFunction.self),
            gcWritePortStacked: try? load("GCWritePortStacked", as: GCWritePortStackedFunction.self),
            dsGetBufferChunkData: try? load("DSGetBufferChunkData", as: DSGetBufferChunkDataFunction.self),
            dsGetNumBufferParts: try? load("DSGetNumBufferParts", as: DSGetNumBufferPartsFunction.self),
            dsGetBufferPartInfo: try? load("DSGetBufferPartInfo", as: DSGetBufferPartInfoFunction.self),
            dsGetBufferInfoStacked: try? load("DSGetBufferInfoStacked", as: DSGetBufferInfoStackedFunction.self),
            dsGetBufferPartInfoStacked: try? load("DSGetBufferPartInfoStacked", as: DSGetBufferPartInfoStackedFunction.self),
            dsAnnounceCompositeBuffer: try? load("DSAnnounceCompositeBuffer", as: DSAnnounceCompositeBufferFunction.self),
            dsGetNumFlows: try? load("DSGetNumFlows", as: DSGetNumFlowsFunction.self),
            dsGetFlowInfo: try? load("DSGetFlowInfo", as: DSGetFlowInfoFunction.self),
            dsGetNumBufferSegments: try? load("DSGetNumBufferSegments", as: DSGetNumBufferSegmentsFunction.self),
            dsGetBufferSegmentInfo: try? load("DSGetBufferSegmentInfo", as: DSGetBufferSegmentInfoFunction.self)
        )
    }

    deinit {
        // This implementation intentionally does not guess which native
        // module handles a caller may still own. Only a successful
        // GCCloseLib proves the Producer has completed its lifecycle.
        if initialized || !registeredEventsByHandle.isEmpty || hasActiveEventDataReads {
            GenTLProducerLibraryRetainer.shared.retain(library)
        }
    }

    // MARK: Library

    public func swiftGCInitLib() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !initialized else { throw GC_ERROR.resourceInUse }
        try check(functions.gcInitLib())
        initialized = true
    }

    public func swiftGCCloseLib() throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        guard !hasActiveEventDataReads,
              registeredEventsByHandle.isEmpty,
              unregisteringEventHandles.isEmpty else {
            throw GC_ERROR.resourceInUse
        }
        try check(functions.gcCloseLib())
        initialized = false
    }

    public func GCGetInfo(command: Int32) throws -> GenTLInfoValue {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        return try readInfo { type, buffer, size in
            functions.gcGetInfo(command, type, buffer, size)
        }
    }

    public func GCGetLastError() -> GenTLErrorInfo {
        lock.lock()
        defer { lock.unlock() }

        var errorCode: Int32 = GC_ERROR.success.rawValue
        var size = 0
        let queryResult = functions.gcGetLastError(&errorCode, nil, &size)
        guard (queryResult == GC_ERROR.success.rawValue ||
               queryResult == GC_ERROR.bufferTooSmall.rawValue),
              size > 0, size <= 1_048_576 else {
            return GenTLErrorInfo(
                code: GC_ERROR(rawValue: errorCode),
                message: "GenTL Producer did not return a valid last-error text size."
            )
        }

        var text = [CChar](repeating: 0, count: size)
        let readResult = text.withUnsafeMutableBufferPointer {
            functions.gcGetLastError(&errorCode, $0.baseAddress, &size)
        }
        guard readResult == GC_ERROR.success.rawValue else {
            return GenTLErrorInfo(
                code: GC_ERROR(rawValue: errorCode),
                message: "GenTL Producer could not return its last-error text (status \(readResult))."
            )
        }
        return GenTLErrorInfo(code: GC_ERROR(rawValue: errorCode), message: String(cString: text))
    }

    // MARK: System

    public func TLOpen() throws -> TL_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        var handle: UnsafeMutableRawPointer?
        try check(functions.tlOpen(&handle))
        guard let handle else { throw GC_ERROR.invalidHandle }
        return TL_HANDLE(rawValue: UInt(bitPattern: handle))
    }

    public func TLClose(_ hTL: TL_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        try check(functions.tlClose(try pointer(hTL)))
    }

    public func TLGetInfo(_ hTL: TL_HANDLE, command: Int32) throws -> GenTLInfoValue {
        try withLock {
            try readInfo { type, buffer, size in
                functions.tlGetInfo(try pointer(hTL), command, type, buffer, size)
            }
        }
    }

    public func TLGetNumInterfaces(_ hTL: TL_HANDLE) throws -> UInt32 {
        try withLock {
            var count: UInt32 = 0
            try check(functions.tlGetNumInterfaces(try pointer(hTL), &count))
            return count
        }
    }

    public func TLGetInterfaceID(_ hTL: TL_HANDLE, index: UInt32) throws -> String {
        try withLock {
            try readString { buffer, size in
                functions.tlGetInterfaceID(try pointer(hTL), index, buffer, size)
            }
        }
    }

    public func TLGetInterfaceInfo(
        _ hTL: TL_HANDLE,
        interfaceID: String,
        command: Int32
    ) throws -> GenTLInfoValue {
        try withLock {
            let handle = try pointer(hTL)
            return try interfaceID.withCString { id in
                try readInfo { type, buffer, size in
                    functions.tlGetInterfaceInfo(handle, id, command, type, buffer, size)
                }
            }
        }
    }

    public func TLUpdateInterfaceList(_ hTL: TL_HANDLE, timeout: UInt64) throws -> Bool {
        try withLock {
            var changed: UInt8 = 0
            try check(functions.tlUpdateInterfaceList(try pointer(hTL), &changed, timeout))
            return changed != 0
        }
    }

    public func TLOpenInterface(_ hTL: TL_HANDLE, interfaceID: String) throws -> IF_HANDLE {
        try withLock {
            let handle = try pointer(hTL)
            var interface: UnsafeMutableRawPointer?
            try check(interfaceID.withCString { id in
                functions.tlOpenInterface(handle, id, &interface)
            })
            guard let interface else { throw GC_ERROR.invalidHandle }
            return IF_HANDLE(rawValue: UInt(bitPattern: interface))
        }
    }

    // MARK: Interface

    public func IFClose(_ hIF: IF_HANDLE) throws {
        try withLock { try check(functions.ifClose(try pointer(hIF))) }
    }

    public func IFGetInfo(_ hIF: IF_HANDLE, command: Int32) throws -> GenTLInfoValue {
        try withLock {
            try readInfo { type, buffer, size in
                functions.ifGetInfo(try pointer(hIF), command, type, buffer, size)
            }
        }
    }

    public func IFGetNumDevices(_ hIF: IF_HANDLE) throws -> UInt32 {
        try withLock {
            var count: UInt32 = 0
            try check(functions.ifGetNumDevices(try pointer(hIF), &count))
            return count
        }
    }

    public func IFGetDeviceID(_ hIF: IF_HANDLE, index: UInt32) throws -> String {
        try withLock {
            try readString { buffer, size in
                functions.ifGetDeviceID(try pointer(hIF), index, buffer, size)
            }
        }
    }

    public func IFUpdateDeviceList(_ hIF: IF_HANDLE, timeout: UInt64) throws -> Bool {
        try withLock {
            var changed: UInt8 = 0
            try check(functions.ifUpdateDeviceList(try pointer(hIF), &changed, timeout))
            return changed != 0
        }
    }

    public func IFGetDeviceInfo(
        _ hIF: IF_HANDLE,
        deviceID: String,
        command: Int32
    ) throws -> GenTLInfoValue {
        try withLock {
            let handle = try pointer(hIF)
            return try deviceID.withCString { id in
                try readInfo { type, buffer, size in
                    functions.ifGetDeviceInfo(handle, id, command, type, buffer, size)
                }
            }
        }
    }

    public func IFOpenDevice(
        _ hIF: IF_HANDLE,
        deviceID: String,
        accessFlags: Int32
    ) throws -> DEV_HANDLE {
        try withLock {
            let handle = try pointer(hIF)
            var device: UnsafeMutableRawPointer?
            try check(deviceID.withCString { id in
                functions.ifOpenDevice(handle, id, accessFlags, &device)
            })
            guard let device else { throw GC_ERROR.invalidHandle }
            return DEV_HANDLE(rawValue: UInt(bitPattern: device))
        }
    }

    public func IFGetParentTL(_ hIF: IF_HANDLE) throws -> TL_HANDLE {
        try withLock {
            guard let getParent = functions.ifGetParentTL else { throw GC_ERROR.notImplemented }
            var system: UnsafeMutableRawPointer?
            try check(getParent(try pointer(hIF), &system))
            guard let system else { throw GC_ERROR.invalidHandle }
            return TL_HANDLE(rawValue: UInt(bitPattern: system))
        }
    }

    // MARK: Device

    public func DevGetPort(_ hDevice: DEV_HANDLE) throws -> PORT_HANDLE {
        try withLock {
            var port: UnsafeMutableRawPointer?
            try check(functions.devGetPort(try pointer(hDevice), &port))
            guard let port else { throw GC_ERROR.invalidHandle }
            return PORT_HANDLE(rawValue: UInt(bitPattern: port))
        }
    }

    public func DevGetNumDataStreams(_ hDevice: DEV_HANDLE) throws -> UInt32 {
        try withLock {
            var count: UInt32 = 0
            try check(functions.devGetNumDataStreams(try pointer(hDevice), &count))
            return count
        }
    }

    public func DevGetDataStreamID(_ hDevice: DEV_HANDLE, index: UInt32) throws -> String {
        try withLock {
            try readString { buffer, size in
                functions.devGetDataStreamID(try pointer(hDevice), index, buffer, size)
            }
        }
    }

    public func DevOpenDataStream(_ hDevice: DEV_HANDLE, dataStreamID: String) throws -> DS_HANDLE {
        try withLock {
            let handle = try pointer(hDevice)
            var stream: UnsafeMutableRawPointer?
            try check(dataStreamID.withCString { id in
                functions.devOpenDataStream(handle, id, &stream)
            })
            guard let stream else { throw GC_ERROR.invalidHandle }
            return DS_HANDLE(rawValue: UInt(bitPattern: stream))
        }
    }

    public func DevGetInfo(_ hDevice: DEV_HANDLE, command: Int32) throws -> GenTLInfoValue {
        try withLock {
            try readInfo { type, buffer, size in
                functions.devGetInfo(try pointer(hDevice), command, type, buffer, size)
            }
        }
    }

    public func DevGetParentIF(_ hDevice: DEV_HANDLE) throws -> IF_HANDLE {
        try withLock {
            guard let getParent = functions.devGetParentIF else { throw GC_ERROR.notImplemented }
            var interface: UnsafeMutableRawPointer?
            try check(getParent(try pointer(hDevice), &interface))
            guard let interface else { throw GC_ERROR.invalidHandle }
            return IF_HANDLE(rawValue: UInt(bitPattern: interface))
        }
    }

    public func DevClose(_ hDevice: DEV_HANDLE) throws {
        try withLock { try check(functions.devClose(try pointer(hDevice))) }
    }

    // MARK: Data Stream / Buffer

    public func DSAnnounceBuffer(
        _ hDS: DS_HANDLE,
        memory: GenTLBufferMemory,
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE {
        try withLock {
            guard memory.size > 0 else { throw GC_ERROR.invalidParameter }
            var buffer: UnsafeMutableRawPointer?
            try check(functions.dsAnnounceBuffer(
                try pointer(hDS), memory.baseAddress, memory.size, privateData, &buffer
            ))
            guard let buffer else { throw GC_ERROR.invalidBuffer }
            return BUFFER_HANDLE(rawValue: UInt(bitPattern: buffer))
        }
    }

    public func DSAllocAndAnnounceBuffer(
        _ hDS: DS_HANDLE,
        size: Int,
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE {
        try withLock {
            guard size > 0 else { throw GC_ERROR.invalidParameter }
            var buffer: UnsafeMutableRawPointer?
            try check(functions.dsAllocAndAnnounceBuffer(try pointer(hDS), size, privateData, &buffer))
            guard let buffer else { throw GC_ERROR.invalidBuffer }
            return BUFFER_HANDLE(rawValue: UInt(bitPattern: buffer))
        }
    }

    public func DSQueueBuffer(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws {
        try withLock {
            try check(functions.dsQueueBuffer(try pointer(hDS), try pointer(buffer)))
        }
    }

    public func DSFlushQueue(_ hDS: DS_HANDLE, operation: Int32) throws {
        try withLock {
            try check(functions.dsFlushQueue(try pointer(hDS), operation))
        }
    }

    public func DSStartAcquisition(
        _ hDS: DS_HANDLE,
        flags: Int32,
        numberToAcquire: UInt64
    ) throws {
        try withLock {
            try check(functions.dsStartAcquisition(try pointer(hDS), flags, numberToAcquire))
        }
    }

    public func DSStopAcquisition(_ hDS: DS_HANDLE, flags: Int32) throws {
        try withLock {
            try check(functions.dsStopAcquisition(try pointer(hDS), flags))
        }
    }

    public func DSGetInfo(_ hDS: DS_HANDLE, command: Int32) throws -> GenTLInfoValue {
        try withLock {
            try readInfo { type, buffer, size in
                functions.dsGetInfo(try pointer(hDS), command, type, buffer, size)
            }
        }
    }

    public func DSGetBufferID(_ hDS: DS_HANDLE, index: UInt32) throws -> BUFFER_HANDLE {
        try withLock {
            var buffer: UnsafeMutableRawPointer?
            try check(functions.dsGetBufferID(try pointer(hDS), index, &buffer))
            guard let buffer else { throw GC_ERROR.invalidBuffer }
            return BUFFER_HANDLE(rawValue: UInt(bitPattern: buffer))
        }
    }

    public func DSGetBufferInfo(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        command: Int32
    ) throws -> GenTLInfoValue {
        try withLock {
            let stream = try pointer(hDS)
            let bufferHandle = try pointer(buffer)
            return try readInfo { type, output, size in
                functions.dsGetBufferInfo(stream, bufferHandle, command, type, output, size)
            }
        }
    }

    public func DSRevokeBuffer(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE
    ) throws -> GenTLRevokedBuffer {
        try withLock {
            var memory: UnsafeMutableRawPointer?
            var privateData: UnsafeMutableRawPointer?
            try check(functions.dsRevokeBuffer(try pointer(hDS), try pointer(buffer), &memory, &privateData))
            return GenTLRevokedBuffer(baseAddress: memory, privateData: privateData)
        }
    }

    public func DSGetParentDev(_ hDS: DS_HANDLE) throws -> DEV_HANDLE {
        try withLock {
            guard let getParent = functions.dsGetParentDev else { throw GC_ERROR.notImplemented }
            var device: UnsafeMutableRawPointer?
            try check(getParent(try pointer(hDS), &device))
            guard let device else { throw GC_ERROR.invalidHandle }
            return DEV_HANDLE(rawValue: UInt(bitPattern: device))
        }
    }

    public func DSClose(_ hDS: DS_HANDLE) throws {
        try withLock { try check(functions.dsClose(try pointer(hDS))) }
    }

    // MARK: GenTL 1.6 Advanced Data Functions

    public func GCReadPortStacked(
        _ hPort: PORT_HANDLE,
        requests: [GenTLPortReadRequest]
    ) throws -> [Data] {
        try withLock {
            guard !requests.isEmpty else { return [] }
            guard let readStacked = functions.gcReadPortStacked else { throw GC_ERROR.notImplemented }
            let port = try pointer(hPort)
            var allocations: [UnsafeMutableRawPointer] = []
            defer { allocations.forEach { $0.deallocate() } }

            var entries: [PORT_REGISTER_STACK_ENTRY] = []
            entries.reserveCapacity(requests.count)
            for request in requests {
                guard request.size > 0, request.size <= 64 * 1024 * 1024 else {
                    throw GC_ERROR.invalidParameter
                }
                let memory = UnsafeMutableRawPointer.allocate(byteCount: request.size, alignment: 8)
                memory.initializeMemory(as: UInt8.self, repeating: 0, count: request.size)
                allocations.append(memory)
                var entry = PORT_REGISTER_STACK_ENTRY()
                entry.Address = request.address
                entry.pBuffer = memory
                entry.Size = request.size
                entries.append(entry)
            }

            var count = entries.count
            let result = entries.withUnsafeMutableBufferPointer {
                readStacked(port, $0.baseAddress, &count)
            }
            try check(result)
            guard count == requests.count else { throw GC_ERROR.invalidValue }

            return zip(requests, allocations).map { request, memory in
                Data(bytes: memory, count: request.size)
            }
        }
    }

    public func GCWritePortStacked(
        _ hPort: PORT_HANDLE,
        requests: [GenTLPortWriteRequest]
    ) throws {
        try withLock {
            guard !requests.isEmpty else { return }
            guard let writeStacked = functions.gcWritePortStacked else { throw GC_ERROR.notImplemented }
            let port = try pointer(hPort)
            var allocations: [UnsafeMutableRawPointer] = []
            defer { allocations.forEach { $0.deallocate() } }

            var entries: [PORT_REGISTER_STACK_ENTRY] = []
            entries.reserveCapacity(requests.count)
            for request in requests {
                guard !request.data.isEmpty,
                      request.data.count <= 64 * 1024 * 1024 else {
                    throw GC_ERROR.invalidParameter
                }
                let memory = UnsafeMutableRawPointer.allocate(
                    byteCount: request.data.count,
                    alignment: 8
                )
                request.data.withUnsafeBytes { source in
                    if let base = source.baseAddress {
                        memory.copyMemory(from: base, byteCount: request.data.count)
                    }
                }
                allocations.append(memory)
                var entry = PORT_REGISTER_STACK_ENTRY()
                entry.Address = request.address
                entry.pBuffer = memory
                entry.Size = request.data.count
                entries.append(entry)
            }

            var count = entries.count
            let result = entries.withUnsafeMutableBufferPointer {
                writeStacked(port, $0.baseAddress, &count)
            }
            try check(result)
            guard count == requests.count else { throw GC_ERROR.invalidValue }
        }
    }

    public func DSGetBufferChunkData(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE
    ) throws -> [GenTLChunkData] {
        try withLock {
            guard let getChunkData = functions.dsGetBufferChunkData else { throw GC_ERROR.notImplemented }
            let stream = try pointer(hDS)
            let bufferHandle = try pointer(buffer)
            var count = 0
            let query = getChunkData(stream, bufferHandle, nil, &count)
            try checkInfoSizeQuery(query, size: count)
            guard count <= 1_000_000 else { throw GC_ERROR.invalidValue }
            guard count > 0 else { return [] }

            let memory = UnsafeMutableRawPointer.allocate(
                byteCount: MemoryLayout<SINGLE_CHUNK_DATA>.stride * count,
                alignment: MemoryLayout<SINGLE_CHUNK_DATA>.alignment
            )
            memory.initializeMemory(
                as: UInt8.self,
                repeating: 0,
                count: MemoryLayout<SINGLE_CHUNK_DATA>.stride * count
            )
            defer { memory.deallocate() }

            let chunks = memory.bindMemory(to: SINGLE_CHUNK_DATA.self, capacity: count)
            var actualCount = count
            try check(getChunkData(stream, bufferHandle, chunks, &actualCount))
            guard actualCount >= 0, actualCount <= count else { throw GC_ERROR.invalidValue }

            return (0..<actualCount).map { index in
                GenTLChunkData(
                    chunkID: chunks[index].ChunkID,
                    offset: Int64(chunks[index].ChunkOffset),
                    length: chunks[index].ChunkLength
                )
            }
        }
    }

    public func DSGetNumBufferParts(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE
    ) throws -> UInt32 {
        try withLock {
            guard let getNumParts = functions.dsGetNumBufferParts else { throw GC_ERROR.notImplemented }
            var count: UInt32 = 0
            try check(getNumParts(try pointer(hDS), try pointer(buffer), &count))
            return count
        }
    }

    public func DSGetBufferPartInfo(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        partIndex: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue {
        try withLock {
            guard let getPartInfo = functions.dsGetBufferPartInfo else { throw GC_ERROR.notImplemented }
            let stream = try pointer(hDS)
            let bufferHandle = try pointer(buffer)
            return try readInfo { type, output, size in
                getPartInfo(stream, bufferHandle, partIndex, command, type, output, size)
            }
        }
    }

    public func DSAnnounceCompositeBuffer(
        _ hDS: DS_HANDLE,
        segments: [GenTLCompositeBufferSegment],
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE {
        try withLock {
            guard !segments.isEmpty,
                  segments.allSatisfy({ $0.memory.size > 0 }) else {
                throw GC_ERROR.invalidParameter
            }
            guard let announceComposite = functions.dsAnnounceCompositeBuffer else { throw GC_ERROR.notImplemented }
            let stream = try pointer(hDS)
            var pointers = segments.map { Optional($0.memory.baseAddress) }
            var sizes = segments.map { $0.memory.size }
            var resultBuffer: UnsafeMutableRawPointer?

            let result = pointers.withUnsafeMutableBufferPointer { pointerBuffer in
                sizes.withUnsafeMutableBufferPointer { sizeBuffer in
                    announceComposite(
                        stream,
                        segments.count,
                        pointerBuffer.baseAddress,
                        sizeBuffer.baseAddress,
                        privateData,
                        &resultBuffer
                    )
                }
            }
            try check(result)
            guard let resultBuffer else { throw GC_ERROR.invalidBuffer }
            return BUFFER_HANDLE(rawValue: UInt(bitPattern: resultBuffer))
        }
    }

    public func DSGetBufferInfoStacked(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        commands: [Int32]
    ) throws -> [Result<GenTLInfoValue, GC_ERROR>] {
        try withLock {
            guard let getBufferInfoStacked = functions.dsGetBufferInfoStacked else { throw GC_ERROR.notImplemented }
            let stream = try pointer(hDS)
            let bufferHandle = try pointer(buffer)
            guard !commands.isEmpty else { return [] }

            var entries = commands.map { command -> DS_BUFFER_INFO_STACKED in
                var entry = DS_BUFFER_INFO_STACKED()
                entry.iInfoCmd = command
                entry.iType = GenTLInfoDataType.unknown.rawValue
                entry.pBuffer = nil
                entry.iSize = 0
                entry.iResult = GC_ERROR.success.rawValue
                return entry
            }

            let queryStatus = entries.withUnsafeMutableBufferPointer {
                getBufferInfoStacked(stream, bufferHandle, $0.baseAddress, $0.count)
            }
            try checkStackedInfoCall(queryStatus)

            var allocations = [UnsafeMutableRawPointer?](repeating: nil, count: entries.count)
            var capacities = [Int](repeating: 0, count: entries.count)
            var outputEntries: [DS_BUFFER_INFO_STACKED] = []
            var outputIndices: [Int] = []
            defer { allocations.compactMap { $0 }.forEach { $0.deallocate() } }

            for index in entries.indices {
                let entryStatus = GC_ERROR(rawValue: entries[index].iResult)
                guard entryStatus == .success || entryStatus == .bufferTooSmall else {
                    continue
                }

                let capacity = entries[index].iSize
                guard capacity >= 0, capacity <= 64 * 1024 * 1024 else {
                    entries[index].iResult = GC_ERROR.invalidValue.rawValue
                    continue
                }

                capacities[index] = capacity
                if capacity > 0 {
                    allocations[index] = UnsafeMutableRawPointer.allocate(
                        byteCount: capacity,
                        alignment: 8
                    )
                }

                var outputEntry = entries[index]
                outputEntry.pBuffer = allocations[index]
                outputEntry.iSize = capacity
                outputEntry.iResult = GC_ERROR.success.rawValue
                outputEntries.append(outputEntry)
                outputIndices.append(index)
            }

            if !outputEntries.isEmpty {
                let readStatus = outputEntries.withUnsafeMutableBufferPointer {
                    getBufferInfoStacked(stream, bufferHandle, $0.baseAddress, $0.count)
                }
                try checkStackedInfoCall(readStatus)

                for (outputIndex, originalIndex) in outputIndices.enumerated() {
                    entries[originalIndex] = outputEntries[outputIndex]
                }
            }

            return entries.indices.map { index in
                decodeStackedInfoResult(
                    dataType: entries[index].iType,
                    buffer: allocations[index],
                    capacity: capacities[index],
                    actualSize: entries[index].iSize,
                    result: entries[index].iResult
                )
            }
        }
    }

    public func DSGetBufferPartInfoStacked(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        requests: [GenTLBufferPartInfoStackedRequest]
    ) throws -> [Result<GenTLInfoValue, GC_ERROR>] {
        try withLock {
            guard let getBufferPartInfoStacked = functions.dsGetBufferPartInfoStacked else { throw GC_ERROR.notImplemented }
            let stream = try pointer(hDS)
            let bufferHandle = try pointer(buffer)
            guard !requests.isEmpty else { return [] }

            var entries = requests.map { request -> DS_BUFFER_PART_INFO_STACKED in
                var entry = DS_BUFFER_PART_INFO_STACKED()
                entry.iPartIndex = request.partIndex
                entry.iInfoCmd = request.command
                entry.iResult = GC_ERROR.success.rawValue
                entry.iType = GenTLInfoDataType.unknown.rawValue
                entry.pBuffer = nil
                entry.iSize = 0
                return entry
            }

            let queryStatus = entries.withUnsafeMutableBufferPointer {
                getBufferPartInfoStacked(stream, bufferHandle, $0.baseAddress, $0.count)
            }
            try checkStackedInfoCall(queryStatus)

            var allocations = [UnsafeMutableRawPointer?](repeating: nil, count: entries.count)
            var capacities = [Int](repeating: 0, count: entries.count)
            var outputEntries: [DS_BUFFER_PART_INFO_STACKED] = []
            var outputIndices: [Int] = []
            defer { allocations.compactMap { $0 }.forEach { $0.deallocate() } }

            for index in entries.indices {
                let entryStatus = GC_ERROR(rawValue: entries[index].iResult)
                guard entryStatus == .success || entryStatus == .bufferTooSmall else {
                    continue
                }

                let capacity = entries[index].iSize
                guard capacity >= 0, capacity <= 64 * 1024 * 1024 else {
                    entries[index].iResult = GC_ERROR.invalidValue.rawValue
                    continue
                }

                capacities[index] = capacity
                if capacity > 0 {
                    allocations[index] = UnsafeMutableRawPointer.allocate(
                        byteCount: capacity,
                        alignment: 8
                    )
                }

                var outputEntry = entries[index]
                outputEntry.pBuffer = allocations[index]
                outputEntry.iSize = capacity
                outputEntry.iResult = GC_ERROR.success.rawValue
                outputEntries.append(outputEntry)
                outputIndices.append(index)
            }

            if !outputEntries.isEmpty {
                let readStatus = outputEntries.withUnsafeMutableBufferPointer {
                    getBufferPartInfoStacked(stream, bufferHandle, $0.baseAddress, $0.count)
                }
                try checkStackedInfoCall(readStatus)

                for (outputIndex, originalIndex) in outputIndices.enumerated() {
                    entries[originalIndex] = outputEntries[outputIndex]
                }
            }

            return entries.indices.map { index in
                decodeStackedInfoResult(
                    dataType: entries[index].iType,
                    buffer: allocations[index],
                    capacity: capacities[index],
                    actualSize: entries[index].iSize,
                    result: entries[index].iResult
                )
            }
        }
    }

    public func DSGetNumFlows(_ hDS: DS_HANDLE) throws -> UInt32 {
        try withLock {
            guard let getNumFlows = functions.dsGetNumFlows else { throw GC_ERROR.notImplemented }
            var count: UInt32 = 0
            try check(getNumFlows(try pointer(hDS), &count))
            return count
        }
    }

    public func DSGetFlowInfo(
        _ hDS: DS_HANDLE,
        flowIndex: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue {
        try withLock {
            guard let getFlowInfo = functions.dsGetFlowInfo else { throw GC_ERROR.notImplemented }
            return try readInfo { type, output, size in
                getFlowInfo(try pointer(hDS), flowIndex, command, type, output, size)
            }
        }
    }

    public func DSGetNumBufferSegments(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE
    ) throws -> UInt32 {
        try withLock {
            guard let getNumSegments = functions.dsGetNumBufferSegments else { throw GC_ERROR.notImplemented }
            var count: UInt32 = 0
            try check(getNumSegments(try pointer(hDS), try pointer(buffer), &count))
            return count
        }
    }

    public func DSGetBufferSegmentInfo(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        segmentIndex: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue {
        try withLock {
            guard let getSegmentInfo = functions.dsGetBufferSegmentInfo else { throw GC_ERROR.notImplemented }
            let stream = try pointer(hDS)
            let bufferHandle = try pointer(buffer)
            return try readInfo { type, output, size in
                getSegmentInfo(stream, bufferHandle, segmentIndex, command, type, output, size)
            }
        }
    }

    // MARK: Port / Register Access

    public func GCReadPort(_ hPort: PORT_HANDLE, address: UInt64, size: Int) throws -> Data {
        try withLock {
            guard size > 0, size <= 64 * 1024 * 1024 else { throw GC_ERROR.invalidParameter }
            let port = try pointer(hPort)
            var data = Data(count: size)
            var actualSize = size
            let result = data.withUnsafeMutableBytes { output in
                functions.gcReadPort(port, address, output.baseAddress, &actualSize)
            }
            try check(result)
            guard actualSize >= 0, actualSize <= size else { throw GC_ERROR.invalidValue }
            data.count = actualSize
            return data
        }
    }

    public func GCWritePort(_ hPort: PORT_HANDLE, address: UInt64, data: Data) throws {
        try withLock {
            guard !data.isEmpty, data.count <= 64 * 1024 * 1024 else {
                throw GC_ERROR.invalidParameter
            }
            let port = try pointer(hPort)
            var size = data.count
            let result = data.withUnsafeBytes { input in
                functions.gcWritePort(port, address, input.baseAddress, &size)
            }
            try check(result)
            guard size == data.count else { throw GC_ERROR.error }
        }
    }

    public func GCGetPortURL(_ hPort: PORT_HANDLE) throws -> String {
        try withLock {
            try readString { buffer, size in
                functions.gcGetPortURL(try pointer(hPort), buffer, size)
            }
        }
    }

    public func GCGetNumPortURLs(_ hPort: PORT_HANDLE) throws -> UInt32 {
        try withLock {
            guard let getNumPortURLs = functions.gcGetNumPortURLs else { throw GC_ERROR.notImplemented }
            var count: UInt32 = 0
            try check(getNumPortURLs(try pointer(hPort), &count))
            return count
        }
    }

    public func GCGetPortURLInfo(
        _ hPort: PORT_HANDLE,
        index: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue {
        try withLock {
            guard let getPortURLInfo = functions.gcGetPortURLInfo else { throw GC_ERROR.notImplemented }
            return try readInfo { type, buffer, size in
                getPortURLInfo(try pointer(hPort), index, command, type, buffer, size)
            }
        }
    }

    public func GCGetPortInfo(_ hPort: PORT_HANDLE, command: Int32) throws -> GenTLInfoValue {
        try withLock {
            try readInfo { type, buffer, size in
                functions.gcGetPortInfo(try pointer(hPort), command, type, buffer, size)
            }
        }
    }

    // MARK: Signaling / Events

    public func GCRegisterEvent(
        _ source: EVENTSRC_HANDLE,
        eventType: Int32
    ) throws -> EVENT_HANDLE {
        let sourcePointer = try eventSourcePointer(source)
        return try withLock {
            guard !registeredEventsByHandle.values.contains(where: {
                $0.sourcePointer == sourcePointer && $0.eventType == eventType
            }) else {
                throw GC_ERROR.resourceInUse
            }

            var event: UnsafeMutableRawPointer?
            try check(functions.gcRegisterEvent(sourcePointer, eventType, &event))
            guard let event else { throw GC_ERROR.invalidHandle }
            let handle = EVENT_HANDLE(rawValue: UInt(bitPattern: event))
            guard registeredEventsByHandle[handle.rawValue] == nil else {
                // A Producer returning an already-live event handle violates
                // handle uniqueness. Undo the just-issued registration before
                // reporting the invalid Producer behavior.
                try? functions.gcUnregisterEvent(sourcePointer, eventType)
                throw GC_ERROR.resourceInUse
            }
            registeredEventsByHandle[handle.rawValue] = RegisteredEvent(
                sourcePointer: sourcePointer,
                eventType: eventType
            )
            return handle
        }
    }

    public func GCUnregisterEvent(
        _ source: EVENTSRC_HANDLE,
        eventType: Int32
    ) throws {
        try unregisterEvent(sourcePointer: eventSourcePointer(source), eventType: eventType)
    }

    private func unregisterEvent(
        sourcePointer: UnsafeMutableRawPointer?,
        eventType: Int32
    ) throws {
        let handles = try withLock { () throws -> [UInt] in
            let matchingHandles = registeredEventsByHandle.compactMap { handle, record in
                record.sourcePointer == sourcePointer && record.eventType == eventType ? handle : nil
            }
            guard !matchingHandles.isEmpty else { throw GC_ERROR.invalidHandle }
            guard matchingHandles.allSatisfy({
                !unregisteringEventHandles.contains($0)
            }) else {
                throw GC_ERROR.resourceInUse
            }

            let eventPointers = try matchingHandles.map {
                try pointer(EVENT_HANDLE(rawValue: $0))
            }
            unregisteringEventHandles.formUnion(matchingHandles)
            do {
                for eventPointer in eventPointers {
                    try check(functions.eventKill(eventPointer))
                }
            } catch {
                unregisteringEventHandles.subtract(matchingHandles)
                throw error
            }
            return matchingHandles
        }

        eventReadCondition.lock()
        while handles.contains(where: {
            activeEventDataReadsByHandle[$0, default: 0] > 0
        }) {
            eventReadCondition.wait()
        }
        eventReadCondition.unlock()

        do {
            try withLock {
                try check(functions.gcUnregisterEvent(sourcePointer, eventType))
                for handle in handles {
                    registeredEventsByHandle.removeValue(forKey: handle)
                    unregisteringEventHandles.remove(handle)
                }
            }
        } catch {
            lock.lock()
            unregisteringEventHandles.subtract(handles)
            lock.unlock()
            throw error
        }
    }

    public func EventGetData(_ event: EVENT_HANDLE, timeout: UInt64) throws -> Data {
        // A NULL EventGetData buffer discards queued data in the GenTL standard,
        // so first determine a safe capacity, then perform exactly one retrieval.
        // Do not hold the API lock while waiting: EventKill must be able to
        // interrupt an infinite-timeout read.
        let (maximumSize, eventType) = try withLock {
            guard let registration = registeredEventsByHandle[event.rawValue] else {
                throw GC_ERROR.invalidHandle
            }
            let registeredPointer = try registeredEventPointer(event)

            do {
                let value = try readInfo { type, buffer, size in
                    functions.eventGetInfo(
                        registeredPointer,
                        GenTLABI.EVENT_SIZE_MAX.rawValue,
                        type,
                        buffer,
                        size
                    )
                }
                guard case .size(let value) = value,
                      value >= 0, value <= 64 * 1024 * 1024 else {
                    throw GC_ERROR.invalidValue
                }
                return (value, registration.eventType)
            } catch let error as GC_ERROR
                where error == .invalidParameter || error == .notImplemented {
                // EVENT_SIZE_MAX (EventGetInfo command 3) was standardized in
                // GenTL 1.2. GenTL 1.0 defines the New Buffer event payload as
                // exactly EVENT_NEW_BUFFER_DATA: two pointers. That fixed
                // structure is safe to size without asking a 1.0 Producer for
                // an unknown command. Other 1.0 event payloads have no
                // standard fixed layout, so do not guess their capacity.
                guard registration.eventType == GenTLEventType.newBuffer.rawValue else {
                    throw GC_ERROR.notImplemented
                }
                return (MemoryLayout<EVENT_NEW_BUFFER_DATA>.size, registration.eventType)
            }
        }

        // Mark the read only after its size query succeeds, then enter the
        // blocking Producer call without another API operation in between.
        let eventPointer = try beginEventDataRead(event)
        defer { endEventDataRead(event.rawValue) }

        // Even an event type with an empty payload needs a non-NULL buffer:
        // NULL means discard, not "deliver an empty event".
        let allocationSize = max(1, maximumSize)
        var data = Data(count: allocationSize)
        var actualSize = allocationSize
        let result = data.withUnsafeMutableBytes { output in
            functions.eventGetData(eventPointer, output.baseAddress, &actualSize, timeout)
        }
        try check(result)
        guard actualSize >= 0, actualSize <= allocationSize else {
            throw GC_ERROR.invalidValue
        }
        if eventType == GenTLEventType.newBuffer.rawValue,
           actualSize != MemoryLayout<EVENT_NEW_BUFFER_DATA>.size {
            throw GC_ERROR.invalidValue
        }
        data.count = actualSize
        return data
    }

    public func EventGetDataInfo(
        _ event: EVENT_HANDLE,
        inputData: Data,
        command: Int32
    ) throws -> GenTLInfoValue {
        try withLock {
            let eventPointer = try registeredEventPointer(event)
            return try inputData.withUnsafeBytes { input in
                try readInfo { type, output, size in
                    functions.eventGetDataInfo(
                        eventPointer, input.baseAddress, inputData.count,
                        command, type, output, size
                    )
                }
            }
        }
    }

    public func EventGetInfo(_ event: EVENT_HANDLE, command: Int32) throws -> GenTLInfoValue {
        try withLock {
            let eventPointer = try registeredEventPointer(event)
            return try readInfo { type, buffer, size in
                functions.eventGetInfo(eventPointer, command, type, buffer, size)
            }
        }
    }

    public func EventFlush(_ event: EVENT_HANDLE) throws {
        try withLock {
            try check(functions.eventFlush(try registeredEventPointer(event)))
        }
    }

    public func EventKill(_ event: EVENT_HANDLE) throws {
        try withLock {
            try check(functions.eventKill(try registeredEventPointer(event)))
        }
    }

    // MARK: Helpers

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        return try operation()
    }

    private func beginEventDataRead(_ event: EVENT_HANDLE) throws -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        let eventPointer = try registeredEventPointer(event)

        eventReadCondition.lock()
        activeEventDataReadsByHandle[event.rawValue, default: 0] += 1
        eventReadCondition.unlock()
        return eventPointer
    }

    private func endEventDataRead(_ eventHandle: UInt) {
        eventReadCondition.lock()
        defer { eventReadCondition.unlock() }
        let activeCount = activeEventDataReadsByHandle[eventHandle, default: 0]
        if activeCount <= 1 {
            activeEventDataReadsByHandle.removeValue(forKey: eventHandle)
        } else {
            activeEventDataReadsByHandle[eventHandle] = activeCount - 1
        }
        eventReadCondition.broadcast()
    }

    private var hasActiveEventDataReads: Bool {
        eventReadCondition.lock()
        defer { eventReadCondition.unlock() }
        return !activeEventDataReadsByHandle.isEmpty
    }

    private func registeredEventPointer(_ event: EVENT_HANDLE) throws -> UnsafeMutableRawPointer {
        guard registeredEventsByHandle[event.rawValue] != nil,
              !unregisteringEventHandles.contains(event.rawValue) else {
            throw GC_ERROR.invalidHandle
        }
        return try pointer(event)
    }

    private func requireInitialized() throws {
        guard initialized else { throw GC_ERROR.notInitialized }
    }

    private func check(_ result: Int32) throws {
        guard result == GC_ERROR.success.rawValue else {
            throw GC_ERROR(rawValue: result)
        }
    }

    private func checkInfoSizeQuery(_ result: Int32, size: Int) throws {
        guard size >= 0, size <= 64 * 1024 * 1024 else { throw GC_ERROR.invalidValue }
        if result == GC_ERROR.success.rawValue || result == GC_ERROR.bufferTooSmall.rawValue {
            return
        }
        throw GC_ERROR(rawValue: result)
    }

    private func readString(
        _ call: (UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?) throws -> Int32
    ) throws -> String {
        var size = 0
        let query = try call(nil, &size)
        try checkInfoSizeQuery(query, size: size)
        guard size > 0 else { return "" }

        var bytes = [CChar](repeating: 0, count: size)
        let result = try bytes.withUnsafeMutableBufferPointer { buffer in
            try call(buffer.baseAddress, &size)
        }
        try check(result)
        return String(cString: bytes)
    }

    private func readInfo(
        _ call: (
            UnsafeMutablePointer<Int32>?,
            UnsafeMutableRawPointer?,
            UnsafeMutablePointer<Int>?
        ) throws -> Int32
    ) throws -> GenTLInfoValue {
        var dataType: Int32 = GenTLInfoDataType.unknown.rawValue
        var size = 0
        let query = try call(&dataType, nil, &size)
        try checkInfoSizeQuery(query, size: size)
        guard size >= 0, size <= 64 * 1024 * 1024 else { throw GC_ERROR.invalidValue }

        var data = Data(count: size)
        var actualSize = size
        let result = try data.withUnsafeMutableBytes { output in
            try call(&dataType, output.baseAddress, &actualSize)
        }
        try check(result)
        guard actualSize >= 0, actualSize <= size else { throw GC_ERROR.invalidValue }
        data.count = actualSize
        return try decodeInfo(dataType: dataType, data: data)
    }

    private func checkStackedInfoCall(_ result: Int32) throws {
        guard result == GC_ERROR.success.rawValue ||
              result == GC_ERROR.bufferTooSmall.rawValue else {
            throw GC_ERROR(rawValue: result)
        }
    }

    private func decodeStackedInfoResult(
        dataType: Int32,
        buffer: UnsafeMutableRawPointer?,
        capacity: Int,
        actualSize: Int,
        result: Int32
    ) -> Result<GenTLInfoValue, GC_ERROR> {
        let status = GC_ERROR(rawValue: result)
        guard status == .success else { return .failure(status) }
        guard actualSize >= 0, actualSize <= 64 * 1024 * 1024 else {
            return .failure(.invalidValue)
        }
        guard actualSize <= capacity else { return .failure(.bufferTooSmall) }
        if actualSize > 0 && buffer == nil {
            return .failure(.invalidBuffer)
        }

        let data = buffer.map { Data(bytes: $0, count: actualSize) } ?? Data()
        do {
            return .success(try decodeInfo(dataType: dataType, data: data))
        } catch let error as GC_ERROR {
            return .failure(error)
        } catch {
            return .failure(.error)
        }
    }

    private func decodeInfo(dataType: Int32, data: Data) throws -> GenTLInfoValue {
        guard let type = GenTLInfoDataType(rawValue: dataType) else {
            return .opaque(dataType: dataType, data: data)
        }

        func value<T>(_ type: T.Type) throws -> T {
            guard data.count >= MemoryLayout<T>.size else { throw GC_ERROR.bufferTooSmall }
            return data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        }

        switch type {
        case .unknown:
            return .opaque(dataType: dataType, data: data)
        case .buffer:
            return .raw(data)
        case .string:
            let bytes = data.prefix { $0 != 0 }
            return .string(String(decoding: bytes, as: UTF8.self))
        case .stringList:
            let strings = data.split(separator: 0, omittingEmptySubsequences: true)
                .map { String(decoding: $0, as: UTF8.self) }
            return .stringList(strings)
        case .int16: return .int16(try value(Int16.self))
        case .uint16: return .uint16(try value(UInt16.self))
        case .int32: return .int32(try value(Int32.self))
        case .uint32: return .uint32(try value(UInt32.self))
        case .int64: return .int64(try value(Int64.self))
        case .uint64: return .uint64(try value(UInt64.self))
        case .float64: return .float64(try value(Double.self))
        case .pointer: return .pointer(try value(UInt.self))
        case .bool8: return .bool8((try value(UInt8.self)) != 0)
        case .size:
            let rawSize = try value(UInt.self)
            guard rawSize <= UInt(Int.max) else { throw GC_ERROR.invalidValue }
            return .size(Int(rawSize))
        case .pointerDifference: return .pointerDifference(try value(Int.self))
        }
    }

    private func pointer<Tag: Hashable & Sendable>(
        _ handle: GenTLHandle<Tag>
    ) throws -> UnsafeMutableRawPointer {
        guard handle.isValid,
              let raw = UnsafeMutableRawPointer(bitPattern: handle.rawValue) else {
            throw GC_ERROR.invalidHandle
        }
        return raw
    }

    private func eventSourcePointer(_ source: EVENTSRC_HANDLE) throws -> UnsafeMutableRawPointer {
        switch source {
        case .system(let handle): return try pointer(handle)
        case .interface(let handle): return try pointer(handle)
        case .device(let handle): return try pointer(handle)
        case .dataStream(let handle): return try pointer(handle)
        case .buffer(let handle): return try pointer(handle)
        }
    }
}


extension GenTLNativeImplementation: GenTLAPI {
    // MARK: Raw GenTL call boundary

    private func rawLocked(
        _ operation: (Functions) -> GenTLABI.GC_ERROR
    ) -> GenTLABI.GC_ERROR {
        lock.lock()
        defer { lock.unlock() }
        return operation(functions)
    }

    private func rawError(_ error: Error) -> GenTLABI.GC_ERROR {
        if let code = error as? GenTLAPI.GC_ERROR {
            return code.rawValue
        }
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_ERROR)
    }

    private func rawEventHandle(
        _ event: GenTLABI.EVENT_HANDLE
    ) -> GenTLAPI.EVENT_HANDLE {
        GenTLAPI.EVENT_HANDLE(rawValue: UInt(bitPattern: event))
    }

    // MARK: Library

    public func GCGetInfo(
        _ iInfoCmd: GenTLABI.TL_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.gcGetInfo(iInfoCmd, piType, pBuffer, piSize) }
    }

    public func GCGetLastError(
        _ piErrorCode: UnsafeMutablePointer<GenTLABI.GC_ERROR>?,
        _ sErrText: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.gcGetLastError(piErrorCode, sErrText, piSize) }
    }

    public func GCInitLib() -> GenTLABI.GC_ERROR {
        do {
            try swiftGCInitLib()
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
        } catch {
            return rawError(error)
        }
    }

    public func GCCloseLib() -> GenTLABI.GC_ERROR {
        do {
            try swiftGCCloseLib()
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
        } catch {
            return rawError(error)
        }
    }

    // MARK: Port

    public func GCReadPort(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iAddress: UInt64,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.gcReadPort(hPort, iAddress, pBuffer, piSize) }
    }

    public func GCWritePort(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iAddress: UInt64,
        _ pBuffer: UnsafeRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.gcWritePort(hPort, iAddress, pBuffer, piSize) }
    }

    public func GCGetPortURL(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ sURL: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.gcGetPortURL(hPort, sURL, piSize) }
    }

    public func GCGetPortInfo(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iInfoCmd: GenTLABI.PORT_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.gcGetPortInfo(hPort, iInfoCmd, piType, pBuffer, piSize) }
    }

    // MARK: Signaling and Events

    public func GCRegisterEvent(
        _ hEventSrc: GenTLABI.EVENTSRC_HANDLE,
        _ iEventID: GenTLABI.EVENT_TYPE,
        _ phEvent: UnsafeMutablePointer<GenTLABI.EVENT_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        guard let phEvent else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER) }
        do {
            let event = try withLock { () throws -> UnsafeMutableRawPointer in
                guard !registeredEventsByHandle.values.contains(where: {
                    $0.sourcePointer == hEventSrc && $0.eventType == iEventID
                }) else {
                    throw GenTLAPI.GC_ERROR.resourceInUse
                }

                var event: UnsafeMutableRawPointer?
                try check(functions.gcRegisterEvent(hEventSrc, iEventID, &event))
                guard let event else { throw GenTLAPI.GC_ERROR.invalidHandle }
                let key = UInt(bitPattern: event)
                guard registeredEventsByHandle[key] == nil else {
                    try? functions.gcUnregisterEvent(hEventSrc, iEventID)
                    throw GenTLABI.GC_ERROR.resourceInUse
                }
                registeredEventsByHandle[key] = RegisteredEvent(
                    sourcePointer: hEventSrc,
                    eventType: iEventID
                )
                return event
            }
            phEvent.pointee = event
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
        } catch {
            return rawError(error)
        }
    }

    public func GCUnregisterEvent(
        _ hEventSrc: GenTLABI.EVENTSRC_HANDLE,
        _ iEventID: GenTLABI.EVENT_TYPE
    ) -> GenTLABI.GC_ERROR {
        do {
            try unregisterEvent(sourcePointer: hEventSrc, eventType: iEventID)
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
        } catch {
            return rawError(error)
        }
    }

    public func EventGetData(
        _ hEvent: GenTLABI.EVENT_HANDLE,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        let event = rawEventHandle(hEvent)
        let eventPointer: UnsafeMutableRawPointer
        do {
            eventPointer = try beginEventDataRead(event)
        } catch {
            return rawError(error)
        }
        defer { endEventDataRead(event.rawValue) }
        return functions.eventGetData(eventPointer, pBuffer, piSize, iTimeout)
    }

    public func EventGetDataInfo(
        _ hEvent: GenTLABI.EVENT_HANDLE,
        _ pInBuffer: UnsafeRawPointer?,
        _ iInSize: Int,
        _ iInfoCmd: GenTLABI.EVENT_DATA_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pOutBuffer: UnsafeMutableRawPointer?,
        _ piOutSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let event = rawEventHandle(hEvent) else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
        }
        lock.lock()
        defer { lock.unlock() }
        do {
            try requireInitialized()
            let pointer = try registeredEventPointer(event)
            return functions.eventGetDataInfo(
                pointer, pInBuffer, iInSize, iInfoCmd, piType, pOutBuffer, piOutSize
            )
        } catch {
            return rawError(error)
        }
    }

    public func EventGetInfo(
        _ hEvent: GenTLABI.EVENT_HANDLE,
        _ iInfoCmd: GenTLABI.EVENT_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let event = rawEventHandle(hEvent) else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
        }
        lock.lock()
        defer { lock.unlock() }
        do {
            try requireInitialized()
            let pointer = try registeredEventPointer(event)
            return functions.eventGetInfo(pointer, iInfoCmd, piType, pBuffer, piSize)
        } catch {
            return rawError(error)
        }
    }

    public func EventFlush(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR {
        guard let event = rawEventHandle(hEvent) else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
        }
        lock.lock()
        defer { lock.unlock() }
        do {
            try requireInitialized()
            return functions.eventFlush(try registeredEventPointer(event))
        } catch {
            return rawError(error)
        }
    }

    public func EventKill(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR {
        guard let event = rawEventHandle(hEvent) else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
        }
        lock.lock()
        defer { lock.unlock() }
        do {
            try requireInitialized()
            return functions.eventKill(try registeredEventPointer(event))
        } catch {
            return rawError(error)
        }
    }

    // MARK: System

    public func TLOpen(
        _ phTL: UnsafeMutablePointer<GenTLABI.TL_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.tlOpen(phTL) }
    }

    public func TLClose(_ hTL: GenTLABI.TL_HANDLE) -> GenTLABI.GC_ERROR {
        rawLocked { $0.tlClose(hTL) }
    }

    public func TLGetInfo(
        _ hTL: GenTLABI.TL_HANDLE,
        _ iInfoCmd: GenTLABI.TL_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.tlGetInfo(hTL, iInfoCmd, piType, pBuffer, piSize) }
    }

    public func TLGetNumInterfaces(
        _ hTL: GenTLABI.TL_HANDLE,
        _ piNumIfaces: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.tlGetNumInterfaces(hTL, piNumIfaces) }
    }

    public func TLGetInterfaceID(
        _ hTL: GenTLABI.TL_HANDLE,
        _ iIndex: UInt32,
        _ sID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.tlGetInterfaceID(hTL, iIndex, sID, piSize) }
    }

    public func TLGetInterfaceInfo(
        _ hTL: GenTLABI.TL_HANDLE,
        _ sIfaceID: UnsafePointer<CChar>?,
        _ iInfoCmd: GenTLABI.INTERFACE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.tlGetInterfaceInfo(hTL, sIfaceID, iInfoCmd, piType, pBuffer, piSize) }
    }

    public func TLOpenInterface(
        _ hTL: GenTLABI.TL_HANDLE,
        _ sIfaceID: UnsafePointer<CChar>?,
        _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.tlOpenInterface(hTL, sIfaceID, phIface) }
    }

    public func TLUpdateInterfaceList(
        _ hTL: GenTLABI.TL_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.tlUpdateInterfaceList(hTL, pbChanged, iTimeout) }
    }

    // MARK: Interface

    public func IFClose(_ hIface: GenTLABI.IF_HANDLE) -> GenTLABI.GC_ERROR {
        rawLocked { $0.ifClose(hIface) }
    }

    public func IFGetInfo(
        _ hIface: GenTLABI.IF_HANDLE,
        _ iInfoCmd: GenTLABI.INTERFACE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.ifGetInfo(hIface, iInfoCmd, piType, pBuffer, piSize) }
    }

    public func IFGetNumDevices(
        _ hIface: GenTLABI.IF_HANDLE,
        _ piNumDevices: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.ifGetNumDevices(hIface, piNumDevices) }
    }

    public func IFGetDeviceID(
        _ hIface: GenTLABI.IF_HANDLE,
        _ iIndex: UInt32,
        _ sDeviceID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.ifGetDeviceID(hIface, iIndex, sDeviceID, piSize) }
    }

    public func IFUpdateDeviceList(
        _ hIface: GenTLABI.IF_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.ifUpdateDeviceList(hIface, pbChanged, iTimeout) }
    }

    public func IFGetDeviceInfo(
        _ hIface: GenTLABI.IF_HANDLE,
        _ sDeviceID: UnsafePointer<CChar>?,
        _ iInfoCmd: GenTLABI.DEVICE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.ifGetDeviceInfo(hIface, sDeviceID, iInfoCmd, piType, pBuffer, piSize) }
    }

    public func IFOpenDevice(
        _ hIface: GenTLABI.IF_HANDLE,
        _ sDeviceID: UnsafePointer<CChar>?,
        _ iOpenFlag: GenTLABI.DEVICE_ACCESS_FLAGS,
        _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.ifOpenDevice(hIface, sDeviceID, iOpenFlag, phDevice) }
    }

    // MARK: Device

    public func DevGetPort(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ phRemoteDevice: UnsafeMutablePointer<GenTLABI.PORT_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.devGetPort(hDevice, phRemoteDevice) }
    }

    public func DevGetNumDataStreams(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ piNumDataStreams: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.devGetNumDataStreams(hDevice, piNumDataStreams) }
    }

    public func DevGetDataStreamID(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ iIndex: UInt32,
        _ sDataStreamID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.devGetDataStreamID(hDevice, iIndex, sDataStreamID, piSize) }
    }

    public func DevOpenDataStream(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ sDataStreamID: UnsafePointer<CChar>?,
        _ phDataStream: UnsafeMutablePointer<GenTLABI.DS_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.devOpenDataStream(hDevice, sDataStreamID, phDataStream) }
    }

    public func DevGetInfo(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ iInfoCmd: GenTLABI.DEVICE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.devGetInfo(hDevice, iInfoCmd, piType, pBuffer, piSize) }
    }

    public func DevClose(_ hDevice: GenTLABI.DEV_HANDLE) -> GenTLABI.GC_ERROR {
        rawLocked { $0.devClose(hDevice) }
    }

    // MARK: Data Stream and Buffers

    public func DSAnnounceBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ iSize: Int,
        _ pPrivate: UnsafeMutableRawPointer?,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsAnnounceBuffer(hDataStream, pBuffer, iSize, pPrivate, phBuffer) }
    }

    public func DSAllocAndAnnounceBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iSize: Int,
        _ pPrivate: UnsafeMutableRawPointer?,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsAllocAndAnnounceBuffer(hDataStream, iSize, pPrivate, phBuffer) }
    }

    public func DSFlushQueue(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iOperation: GenTLABI.ACQ_QUEUE_TYPE
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsFlushQueue(hDataStream, iOperation) }
    }

    public func DSStartAcquisition(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iStartFlags: GenTLABI.ACQ_START_FLAGS,
        _ iNumToAcquire: UInt64
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsStartAcquisition(hDataStream, iStartFlags, iNumToAcquire) }
    }

    public func DSStopAcquisition(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iStopFlags: GenTLABI.ACQ_STOP_FLAGS
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsStopAcquisition(hDataStream, iStopFlags) }
    }

    public func DSGetInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iInfoCmd: GenTLABI.STREAM_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsGetInfo(hDataStream, iInfoCmd, piType, pBuffer, piSize) }
    }

    public func DSGetBufferID(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iIndex: UInt32,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsGetBufferID(hDataStream, iIndex, phBuffer) }
    }

    public func DSClose(_ hDataStream: GenTLABI.DS_HANDLE) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsClose(hDataStream) }
    }

    public func DSRevokeBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ ppBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
        _ ppPrivate: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsRevokeBuffer(hDataStream, hBuffer, ppBuffer, ppPrivate) }
    }

    public func DSQueueBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsQueueBuffer(hDataStream, hBuffer) }
    }

    public func DSGetBufferInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ iInfoCmd: GenTLABI.BUFFER_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { $0.dsGetBufferInfo(hDataStream, hBuffer, iInfoCmd, piType, pBuffer, piSize) }
    }

    // MARK: GenTL 1.1 Port Extensions

    public func GCGetNumPortURLs(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ piNumURLs: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.gcGetNumPortURLs else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hPort, piNumURLs)
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
        rawLocked { functions in
            guard let function = functions.gcGetPortURLInfo else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hPort, iURLIndex, iInfoCmd, piType, pBuffer, piSize)
        }
    }

    public func GCReadPortStacked(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ pEntries: UnsafeMutablePointer<GenTLABI.PORT_REGISTER_STACK_ENTRY>?,
        _ piNumEntries: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.gcReadPortStacked else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hPort, pEntries, piNumEntries)
        }
    }

    public func GCWritePortStacked(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ pEntries: UnsafeMutablePointer<GenTLABI.PORT_REGISTER_STACK_ENTRY>?,
        _ piNumEntries: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.gcWritePortStacked else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hPort, pEntries, piNumEntries)
        }
    }

    // MARK: GenTL 1.3

    public func DSGetBufferChunkData(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pChunkData: UnsafeMutablePointer<GenTLABI.SINGLE_CHUNK_DATA>?,
        _ piNumChunks: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetBufferChunkData else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, hBuffer, pChunkData, piNumChunks)
        }
    }

    // MARK: GenTL 1.4

    public func IFGetParentTL(
        _ hIface: GenTLABI.IF_HANDLE,
        _ phSystem: UnsafeMutablePointer<GenTLABI.TL_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.ifGetParentTL else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hIface, phSystem)
        }
    }

    public func DevGetParentIF(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.devGetParentIF else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDevice, phIface)
        }
    }

    public func DSGetParentDev(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetParentDev else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, phDevice)
        }
    }

    // MARK: GenTL 1.5

    public func DSGetNumBufferParts(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ piNumParts: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetNumBufferParts else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, hBuffer, piNumParts)
        }
    }

    public func DSGetBufferPartInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ iPartIndex: UInt32,
        _ iInfoCmd: GenTLABI.BUFFER_PART_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetBufferPartInfo else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, hBuffer, iPartIndex, iInfoCmd, piType, pBuffer, piSize)
        }
    }

    // MARK: GenTL 1.6

    public func DSAnnounceCompositeBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iNumSegments: Int,
        _ ppSegments: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
        _ piSizes: UnsafeMutablePointer<Int>?,
        _ pPrivate: UnsafeMutableRawPointer?,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsAnnounceCompositeBuffer else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, iNumSegments, ppSegments, piSizes, pPrivate, phBuffer)
        }
    }

    public func DSGetBufferInfoStacked(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pInfoStacked: UnsafeMutablePointer<GenTLABI.DS_BUFFER_INFO_STACKED>?,
        _ iNumInfos: Int
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetBufferInfoStacked else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, hBuffer, pInfoStacked, iNumInfos)
        }
    }

    public func DSGetBufferPartInfoStacked(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pInfoStacked: UnsafeMutablePointer<GenTLABI.DS_BUFFER_PART_INFO_STACKED>?,
        _ iNumInfos: Int
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetBufferPartInfoStacked else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, hBuffer, pInfoStacked, iNumInfos)
        }
    }

    public func DSGetNumFlows(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ piNumFlows: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetNumFlows else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, piNumFlows)
        }
    }

    public func DSGetFlowInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iFlowIndex: UInt32,
        _ iInfoCmd: GenTLABI.FLOW_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetFlowInfo else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, iFlowIndex, iInfoCmd, piType, pBuffer, piSize)
        }
    }

    public func DSGetNumBufferSegments(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ piNumSegments: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetNumBufferSegments else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, hBuffer, piNumSegments)
        }
    }

    public func DSGetBufferSegmentInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ iSegmentIndex: UInt32,
        _ iInfoCmd: GenTLABI.SEGMENT_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        rawLocked { functions in
            guard let function = functions.dsGetBufferSegmentInfo else {
                return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_NOT_IMPLEMENTED)
            }
            return function(hDataStream, hBuffer, iSegmentIndex, iInfoCmd, piType, pBuffer, piSize)
        }
    }
}
