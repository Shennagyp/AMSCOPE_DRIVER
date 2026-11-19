import Darwin
import Foundation
import GenTLABI
import GenTLAPI

// MARK: GenTL 1.6 C ABI function signatures

private typealias GCInitLibFunction = @convention(c) () -> Int32
private typealias GCCloseLibFunction = @convention(c) () -> Int32
private typealias GCGetInfoFunction = @convention(c) (
    Int32, UnsafeMutablePointer<Int32>?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias GCGetLastErrorFunction = @convention(c) (
    UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?
) -> Int32

private typealias TLOpenFunction = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
private typealias TLCloseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias ModuleInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, Int32, UnsafeMutablePointer<Int32>?,
    UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias TLGetNumInterfacesFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias TLGetInterfaceIDFunction = @convention(c) (
    UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias TLUpdateInterfaceListFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, UInt64
) -> Int32
private typealias TLOpenInterfaceFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32

private typealias IFCloseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias IFUpdateDeviceListFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, UInt64
) -> Int32
private typealias IFGetNumDevicesFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias IFGetDeviceIDFunction = @convention(c) (
    UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias IFGetDeviceInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32,
    UnsafeMutablePointer<Int32>?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias IFOpenDeviceFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32,
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias IFGetParentTLFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32

private typealias DevGetPortFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DevGetNumDataStreamsFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias DevGetDataStreamIDFunction = @convention(c) (
    UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias DevOpenDataStreamFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DevGetParentIFFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DevCloseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32

private typealias DSAnnounceBufferFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DSAllocAndAnnounceBufferFunction = @convention(c) (
    UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DSQueueBufferFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
) -> Int32
private typealias DSFlushQueueFunction = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
private typealias DSStartAcquisitionFunction = @convention(c) (
    UnsafeMutableRawPointer?, Int32, UInt64
) -> Int32
private typealias DSStopAcquisitionFunction = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
private typealias DSGetBufferIDFunction = @convention(c) (
    UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DSGetBufferInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32,
    UnsafeMutablePointer<Int32>?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias DSRevokeBufferFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DSCloseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias DSGetParentDevFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32

private typealias GCReadPortFunction = @convention(c) (
    UnsafeMutableRawPointer?, UInt64, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias GCWritePortFunction = @convention(c) (
    UnsafeMutableRawPointer?, UInt64, UnsafeRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias GCGetPortURLFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias GCGetNumPortURLsFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias GCGetPortURLInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, UInt32, Int32, UnsafeMutablePointer<Int32>?,
    UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32

private typealias GCRegisterEventFunction = @convention(c) (
    UnsafeMutableRawPointer?, Int32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias GCUnregisterEventFunction = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
private typealias EventGetDataFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?, UInt64
) -> Int32
private typealias EventGetDataInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeRawPointer?, Int, Int32, UnsafeMutablePointer<Int32>?,
    UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias EventGetInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, Int32, UnsafeMutablePointer<Int32>?,
    UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias EventSimpleFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32

private typealias GCReadPortStackedFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<PORT_REGISTER_STACK_ENTRY>?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias GCWritePortStackedFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<PORT_REGISTER_STACK_ENTRY>?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias DSGetBufferChunkDataFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<SINGLE_CHUNK_DATA>?,
    UnsafeMutablePointer<Int>?
) -> Int32
private typealias DSGetNumBufferPartsFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias DSGetBufferPartInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt32, Int32,
    UnsafeMutablePointer<Int32>?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias DSAnnounceCompositeBufferFunction = @convention(c) (
    UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    UnsafeMutablePointer<Int>?, UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DSGetNumFlowsFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias DSGetFlowInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, UInt32, Int32, UnsafeMutablePointer<Int32>?,
    UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias DSGetNumBufferSegmentsFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias DSGetBufferSegmentInfoFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt32, Int32,
    UnsafeMutablePointer<Int32>?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?
) -> Int32
private typealias DSGetBufferInfoStackedFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
    UnsafeMutablePointer<DS_BUFFER_INFO_STACKED>?, Int
) -> Int32
private typealias DSGetBufferPartInfoStackedFunction = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
    UnsafeMutablePointer<DS_BUFFER_PART_INFO_STACKED>?, Int
) -> Int32

/// GenTL Consumer implementation backed by a manufacturer-supplied .cti Producer.
///
/// The implementation owns one loaded CTI library. Handles returned by the
/// Producer remain opaque and are never synthesized or reinterpreted as IDs.
public final class GenTLNativeImplementation: GenTLAPI, @unchecked Sendable {
    private struct Functions {
        let gcInitLib: GCInitLibFunction
        let gcCloseLib: GCCloseLibFunction
        let gcGetInfo: GCGetInfoFunction
        let gcGetLastError: GCGetLastErrorFunction

        let tlOpen: TLOpenFunction
        let tlClose: TLCloseFunction
        let tlGetInfo: ModuleInfoFunction
        let tlGetNumInterfaces: TLGetNumInterfacesFunction
        let tlGetInterfaceID: TLGetInterfaceIDFunction
        let tlGetInterfaceInfo: IFGetDeviceInfoFunction
        let tlUpdateInterfaceList: TLUpdateInterfaceListFunction
        let tlOpenInterface: TLOpenInterfaceFunction

        let ifClose: IFCloseFunction
        let ifGetInfo: ModuleInfoFunction
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
        let devGetInfo: ModuleInfoFunction
        let devGetParentIF: DevGetParentIFFunction?
        let devClose: DevCloseFunction

        let dsAnnounceBuffer: DSAnnounceBufferFunction
        let dsAllocAndAnnounceBuffer: DSAllocAndAnnounceBufferFunction
        let dsQueueBuffer: DSQueueBufferFunction
        let dsFlushQueue: DSFlushQueueFunction
        let dsStartAcquisition: DSStartAcquisitionFunction
        let dsStopAcquisition: DSStopAcquisitionFunction
        let dsGetInfo: ModuleInfoFunction
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
        let gcGetPortInfo: ModuleInfoFunction

        let gcRegisterEvent: GCRegisterEventFunction
        let gcUnregisterEvent: GCUnregisterEventFunction
        let eventGetData: EventGetDataFunction
        let eventGetDataInfo: EventGetDataInfoFunction
        let eventGetInfo: EventGetInfoFunction
        let eventFlush: EventSimpleFunction
        let eventKill: EventSimpleFunction

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
        let source: EVENTSRC_HANDLE
        let eventType: Int32
    }

    private var registeredEventsByHandle: [UInt: RegisteredEvent] = [:]
    private var activeEventDataReadsByHandle: [UInt: Int] = [:]
    private var activeEventDataReads = 0

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
            tlGetInfo: load("TLGetInfo", as: ModuleInfoFunction.self),
            tlGetNumInterfaces: load("TLGetNumInterfaces", as: TLGetNumInterfacesFunction.self),
            tlGetInterfaceID: load("TLGetInterfaceID", as: TLGetInterfaceIDFunction.self),
            tlGetInterfaceInfo: load("TLGetInterfaceInfo", as: IFGetDeviceInfoFunction.self),
            tlUpdateInterfaceList: load("TLUpdateInterfaceList", as: TLUpdateInterfaceListFunction.self),
            tlOpenInterface: load("TLOpenInterface", as: TLOpenInterfaceFunction.self),

            ifClose: load("IFClose", as: IFCloseFunction.self),
            ifGetInfo: load("IFGetInfo", as: ModuleInfoFunction.self),
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
            devGetInfo: load("DevGetInfo", as: ModuleInfoFunction.self),
            devGetParentIF: try? load("DevGetParentIF", as: DevGetParentIFFunction.self),
            devClose: load("DevClose", as: DevCloseFunction.self),

            dsAnnounceBuffer: load("DSAnnounceBuffer", as: DSAnnounceBufferFunction.self),
            dsAllocAndAnnounceBuffer: load("DSAllocAndAnnounceBuffer", as: DSAllocAndAnnounceBufferFunction.self),
            dsQueueBuffer: load("DSQueueBuffer", as: DSQueueBufferFunction.self),
            dsFlushQueue: load("DSFlushQueue", as: DSFlushQueueFunction.self),
            dsStartAcquisition: load("DSStartAcquisition", as: DSStartAcquisitionFunction.self),
            dsStopAcquisition: load("DSStopAcquisition", as: DSStopAcquisitionFunction.self),
            dsGetInfo: load("DSGetInfo", as: ModuleInfoFunction.self),
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
            gcGetPortInfo: load("GCGetPortInfo", as: ModuleInfoFunction.self),

            gcRegisterEvent: load("GCRegisterEvent", as: GCRegisterEventFunction.self),
            gcUnregisterEvent: load("GCUnregisterEvent", as: GCUnregisterEventFunction.self),
            eventGetData: load("EventGetData", as: EventGetDataFunction.self),
            eventGetDataInfo: load("EventGetDataInfo", as: EventGetDataInfoFunction.self),
            eventGetInfo: load("EventGetInfo", as: EventGetInfoFunction.self),
            eventFlush: load("EventFlush", as: EventSimpleFunction.self),
            eventKill: load("EventKill", as: EventSimpleFunction.self),

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

    // MARK: Library

    public func GCInitLib() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !initialized else { throw GC_ERROR.resourceInUse }
        try check(functions.gcInitLib())
        initialized = true
    }

    public func GCCloseLib() throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        guard activeEventDataReads == 0,
              registeredEventsByHandle.isEmpty else {
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
                guard !request.data.isEmpty else { throw GC_ERROR.invalidParameter }
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
            guard size >= 0, size <= 64 * 1024 * 1024 else { throw GC_ERROR.invalidParameter }
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
        try withLock {
            var event: UnsafeMutableRawPointer?
            try check(functions.gcRegisterEvent(try eventSourcePointer(source), eventType, &event))
            guard let event else { throw GC_ERROR.invalidHandle }
            let handle = EVENT_HANDLE(rawValue: UInt(bitPattern: event))
            guard registeredEventsByHandle[handle.rawValue] == nil else {
                throw GC_ERROR.resourceInUse
            }
            registeredEventsByHandle[handle.rawValue] = RegisteredEvent(
                source: source,
                eventType: eventType
            )
            return handle
        }
    }

    public func GCUnregisterEvent(
        _ source: EVENTSRC_HANDLE,
        eventType: Int32
    ) throws {
        try withLock {
            let matchingHandles = registeredEventsByHandle.compactMap { handle, record in
                record.source == source && record.eventType == eventType ? handle : nil
            }
            guard matchingHandles.allSatisfy({
                activeEventDataReadsByHandle[$0, default: 0] == 0
            }) else {
                throw GC_ERROR.resourceInUse
            }

            try check(functions.gcUnregisterEvent(try eventSourcePointer(source), eventType))
            for handle in matchingHandles {
                registeredEventsByHandle.removeValue(forKey: handle)
                activeEventDataReadsByHandle.removeValue(forKey: handle)
            }
        }
    }

    public func EventGetData(_ event: EVENT_HANDLE, timeout: UInt64) throws -> Data {
        // Do not hold the global API lock while waiting. EventKill must be able
        // to enter the producer concurrently to wake an infinite-timeout read.
        let eventPointer = try beginEventDataRead(event)
        defer { endEventDataRead(event.rawValue) }

        var size = 0
        let query = functions.eventGetData(eventPointer, nil, &size, timeout)
        try checkInfoSizeQuery(query, size: size)
        if size == 0 {
            return Data()
        }

        var data = Data(count: size)
        var actualSize = size
        let result = data.withUnsafeMutableBytes { output in
            functions.eventGetData(eventPointer, output.baseAddress, &actualSize, timeout)
        }
        try check(result)
        guard actualSize >= 0, actualSize <= size else { throw GC_ERROR.invalidValue }
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
        activeEventDataReads += 1
        activeEventDataReadsByHandle[event.rawValue, default: 0] += 1
        return eventPointer
    }

    private func endEventDataRead(_ eventHandle: UInt) {
        lock.lock()
        defer { lock.unlock() }
        activeEventDataReads = max(0, activeEventDataReads - 1)
        let current = activeEventDataReadsByHandle[eventHandle, default: 0]
        if current <= 1 {
            activeEventDataReadsByHandle.removeValue(forKey: eventHandle)
        } else {
            activeEventDataReadsByHandle[eventHandle] = current - 1
        }
    }

    private func registeredEventPointer(_ event: EVENT_HANDLE) throws -> UnsafeMutableRawPointer {
        guard registeredEventsByHandle[event.rawValue] != nil else {
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
            return .raw(data)
        }

        func value<T>(_ type: T.Type) throws -> T {
            guard data.count >= MemoryLayout<T>.size else { throw GC_ERROR.bufferTooSmall }
            return data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        }

        switch type {
        case .unknown, .buffer:
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
        case .size: return .uint64(UInt64(try value(UInt.self)))
        case .pointerDifference: return .int64(Int64(try value(Int.self)))
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
