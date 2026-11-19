import Foundation

/// Library-level GenTL 1.6 functions.
public protocol GenTLLibraryFunctions: Sendable {
    func GCInitLib() throws
    func GCCloseLib() throws
    func GCGetInfo(command: Int32) throws -> GenTLInfoValue
    func GCGetLastError() -> GenTLErrorInfo
}

/// System module functions.
public protocol GenTLSystemFunctions: Sendable {
    func TLOpen() throws -> TL_HANDLE
    func TLClose(_ hTL: TL_HANDLE) throws
    func TLGetInfo(_ hTL: TL_HANDLE, command: Int32) throws -> GenTLInfoValue
    func TLGetNumInterfaces(_ hTL: TL_HANDLE) throws -> UInt32
    func TLGetInterfaceID(_ hTL: TL_HANDLE, index: UInt32) throws -> String
    func TLGetInterfaceInfo(_ hTL: TL_HANDLE, interfaceID: String, command: Int32) throws -> GenTLInfoValue
    func TLOpenInterface(_ hTL: TL_HANDLE, interfaceID: String) throws -> IF_HANDLE
    func TLUpdateInterfaceList(_ hTL: TL_HANDLE, timeout: UInt64) throws -> Bool
}

/// Interface module functions.
public protocol GenTLInterfaceFunctions: Sendable {
    func IFClose(_ hIF: IF_HANDLE) throws
    func IFGetInfo(_ hIF: IF_HANDLE, command: Int32) throws -> GenTLInfoValue
    func IFGetNumDevices(_ hIF: IF_HANDLE) throws -> UInt32
    func IFGetDeviceID(_ hIF: IF_HANDLE, index: UInt32) throws -> String
    func IFUpdateDeviceList(_ hIF: IF_HANDLE, timeout: UInt64) throws -> Bool
    func IFGetDeviceInfo(_ hIF: IF_HANDLE, deviceID: String, command: Int32) throws -> GenTLInfoValue
    func IFOpenDevice(_ hIF: IF_HANDLE, deviceID: String, accessFlags: Int32) throws -> DEV_HANDLE
    func IFGetParentTL(_ hIF: IF_HANDLE) throws -> TL_HANDLE
}

/// Device module functions.
public protocol GenTLDeviceFunctions: Sendable {
    func DevGetPort(_ hDevice: DEV_HANDLE) throws -> PORT_HANDLE
    func DevGetNumDataStreams(_ hDevice: DEV_HANDLE) throws -> UInt32
    func DevGetDataStreamID(_ hDevice: DEV_HANDLE, index: UInt32) throws -> String
    func DevOpenDataStream(_ hDevice: DEV_HANDLE, dataStreamID: String) throws -> DS_HANDLE
    func DevGetInfo(_ hDevice: DEV_HANDLE, command: Int32) throws -> GenTLInfoValue
    func DevGetParentIF(_ hDevice: DEV_HANDLE) throws -> IF_HANDLE
    func DevClose(_ hDevice: DEV_HANDLE) throws
}

/// Data Stream and Buffer module functions.
public protocol GenTLDataStreamFunctions: Sendable {
    func DSAnnounceBuffer(
        _ hDS: DS_HANDLE,
        memory: GenTLBufferMemory,
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE

    func DSAllocAndAnnounceBuffer(
        _ hDS: DS_HANDLE,
        size: Int,
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE

    func DSQueueBuffer(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws
    func DSFlushQueue(_ hDS: DS_HANDLE, operation: Int32) throws
    func DSStartAcquisition(_ hDS: DS_HANDLE, flags: Int32, numberToAcquire: UInt64) throws
    func DSStopAcquisition(_ hDS: DS_HANDLE, flags: Int32) throws
    func DSGetInfo(_ hDS: DS_HANDLE, command: Int32) throws -> GenTLInfoValue
    func DSGetBufferID(_ hDS: DS_HANDLE, index: UInt32) throws -> BUFFER_HANDLE
    func DSGetBufferInfo(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE, command: Int32) throws -> GenTLInfoValue
    func DSRevokeBuffer(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws -> GenTLRevokedBuffer
    func DSGetParentDev(_ hDS: DS_HANDLE) throws -> DEV_HANDLE
    func DSClose(_ hDS: DS_HANDLE) throws
}

/// Data Stream extensions introduced across GenTL 1.3 through 1.6.
public protocol GenTLDataStreamExtensionFunctions: Sendable {
    func DSGetBufferChunkData(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws -> [GenTLChunkData]
    func DSGetNumBufferParts(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws -> UInt32
    func DSGetBufferPartInfo(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        partIndex: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue

    func DSAnnounceCompositeBuffer(
        _ hDS: DS_HANDLE,
        segments: [GenTLCompositeBufferSegment],
        privateData: UnsafeMutableRawPointer?
    ) throws -> BUFFER_HANDLE

    /// Executes one GenTL 1.6 stacked call. Individual entry failures are returned
    /// as Result.failure; a thrown error represents failure of the stacked call itself.
    func DSGetBufferInfoStacked(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        commands: [Int32]
    ) throws -> [Result<GenTLInfoValue, GC_ERROR>]

    func DSGetBufferPartInfoStacked(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        requests: [GenTLBufferPartInfoStackedRequest]
    ) throws -> [Result<GenTLInfoValue, GC_ERROR>]

    func DSGetNumFlows(_ hDS: DS_HANDLE) throws -> UInt32
    func DSGetFlowInfo(_ hDS: DS_HANDLE, flowIndex: UInt32, command: Int32) throws -> GenTLInfoValue
    func DSGetNumBufferSegments(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws -> UInt32
    func DSGetBufferSegmentInfo(
        _ hDS: DS_HANDLE,
        buffer: BUFFER_HANDLE,
        segmentIndex: UInt32,
        command: Int32
    ) throws -> GenTLInfoValue
}

/// Port functions used for register access and XML-description discovery.
public protocol GenTLPortFunctions: Sendable {
    func GCReadPort(_ hPort: PORT_HANDLE, address: UInt64, size: Int) throws -> Data
    func GCWritePort(_ hPort: PORT_HANDLE, address: UInt64, data: Data) throws
    func GCGetPortURL(_ hPort: PORT_HANDLE) throws -> String
    func GCGetNumPortURLs(_ hPort: PORT_HANDLE) throws -> UInt32
    func GCGetPortURLInfo(_ hPort: PORT_HANDLE, index: UInt32, command: Int32) throws -> GenTLInfoValue
    func GCGetPortInfo(_ hPort: PORT_HANDLE, command: Int32) throws -> GenTLInfoValue

    /// GenTL 1.1 register-stack operations belong to the Port module.
    func GCReadPortStacked(_ hPort: PORT_HANDLE, requests: [GenTLPortReadRequest]) throws -> [Data]
    func GCWritePortStacked(_ hPort: PORT_HANDLE, requests: [GenTLPortWriteRequest]) throws
}

/// Signaling and event functions.
public protocol GenTLSignalingFunctions: Sendable {
    func GCRegisterEvent(_ source: EVENTSRC_HANDLE, eventType: Int32) throws -> EVENT_HANDLE
    func GCUnregisterEvent(_ source: EVENTSRC_HANDLE, eventType: Int32) throws
    func EventGetData(_ event: EVENT_HANDLE, timeout: UInt64) throws -> Data
    func EventGetDataInfo(_ event: EVENT_HANDLE, inputData: Data, command: Int32) throws -> GenTLInfoValue
    func EventGetInfo(_ event: EVENT_HANDLE, command: Int32) throws -> GenTLInfoValue
    func EventFlush(_ event: EVENT_HANDLE) throws
    func EventKill(_ event: EVENT_HANDLE) throws
}
