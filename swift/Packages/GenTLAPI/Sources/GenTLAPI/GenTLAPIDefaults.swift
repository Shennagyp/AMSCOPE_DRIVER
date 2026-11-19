import Foundation

/// Conservative defaults for API operations not supplied by a backend.
/// Returning NOT_IMPLEMENTED is preferable to manufacturing unsupported behavior.
public extension GenTLAPI {
    var genTLVersion: GenTLVersion { .v1_6 }

    func GCInitLib() throws { throw GC_ERROR.notImplemented }
    func GCCloseLib() throws { throw GC_ERROR.notImplemented }
    func GCGetInfo(command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func GCGetLastError() -> GenTLErrorInfo {
        GenTLErrorInfo(code: .notImplemented, message: "GCGetLastError is not implemented by this backend.")
    }

    func TLOpen() throws -> TL_HANDLE { throw GC_ERROR.notImplemented }
    func TLClose(_ hTL: TL_HANDLE) throws { throw GC_ERROR.notImplemented }
    func TLGetInfo(_ hTL: TL_HANDLE, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func TLGetNumInterfaces(_ hTL: TL_HANDLE) throws -> UInt32 { throw GC_ERROR.notImplemented }
    func TLGetInterfaceID(_ hTL: TL_HANDLE, index: UInt32) throws -> String { throw GC_ERROR.notImplemented }
    func TLGetInterfaceInfo(_ hTL: TL_HANDLE, interfaceID: String, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func TLOpenInterface(_ hTL: TL_HANDLE, interfaceID: String) throws -> IF_HANDLE { throw GC_ERROR.notImplemented }
    func TLUpdateInterfaceList(_ hTL: TL_HANDLE, timeout: UInt64) throws -> Bool { throw GC_ERROR.notImplemented }

    func IFClose(_ hIF: IF_HANDLE) throws { throw GC_ERROR.notImplemented }
    func IFGetInfo(_ hIF: IF_HANDLE, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func IFGetNumDevices(_ hIF: IF_HANDLE) throws -> UInt32 { throw GC_ERROR.notImplemented }
    func IFGetDeviceID(_ hIF: IF_HANDLE, index: UInt32) throws -> String { throw GC_ERROR.notImplemented }
    func IFUpdateDeviceList(_ hIF: IF_HANDLE, timeout: UInt64) throws -> Bool { throw GC_ERROR.notImplemented }
    func IFGetDeviceInfo(_ hIF: IF_HANDLE, deviceID: String, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func IFOpenDevice(_ hIF: IF_HANDLE, deviceID: String, accessFlags: Int32) throws -> DEV_HANDLE { throw GC_ERROR.notImplemented }
    func IFGetParentTL(_ hIF: IF_HANDLE) throws -> TL_HANDLE { throw GC_ERROR.notImplemented }

    func DevGetPort(_ hDevice: DEV_HANDLE) throws -> PORT_HANDLE { throw GC_ERROR.notImplemented }
    func DevGetNumDataStreams(_ hDevice: DEV_HANDLE) throws -> UInt32 { throw GC_ERROR.notImplemented }
    func DevGetDataStreamID(_ hDevice: DEV_HANDLE, index: UInt32) throws -> String { throw GC_ERROR.notImplemented }
    func DevOpenDataStream(_ hDevice: DEV_HANDLE, dataStreamID: String) throws -> DS_HANDLE { throw GC_ERROR.notImplemented }
    func DevGetInfo(_ hDevice: DEV_HANDLE, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func DevGetParentIF(_ hDevice: DEV_HANDLE) throws -> IF_HANDLE { throw GC_ERROR.notImplemented }
    func DevClose(_ hDevice: DEV_HANDLE) throws { throw GC_ERROR.notImplemented }

    func DSAnnounceBuffer(_ hDS: DS_HANDLE, memory: GenTLBufferMemory, privateData: UnsafeMutableRawPointer?) throws -> BUFFER_HANDLE {
        throw GC_ERROR.notImplemented
    }
    func DSAllocAndAnnounceBuffer(_ hDS: DS_HANDLE, size: Int, privateData: UnsafeMutableRawPointer?) throws -> BUFFER_HANDLE {
        throw GC_ERROR.notImplemented
    }
    func DSQueueBuffer(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws { throw GC_ERROR.notImplemented }
    func DSFlushQueue(_ hDS: DS_HANDLE, operation: Int32) throws { throw GC_ERROR.notImplemented }
    func DSStartAcquisition(_ hDS: DS_HANDLE, flags: Int32, numberToAcquire: UInt64) throws { throw GC_ERROR.notImplemented }
    func DSStopAcquisition(_ hDS: DS_HANDLE, flags: Int32) throws { throw GC_ERROR.notImplemented }
    func DSGetInfo(_ hDS: DS_HANDLE, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func DSGetBufferID(_ hDS: DS_HANDLE, index: UInt32) throws -> BUFFER_HANDLE { throw GC_ERROR.notImplemented }
    func DSGetBufferInfo(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func DSRevokeBuffer(_ hDS: DS_HANDLE, buffer: BUFFER_HANDLE) throws -> GenTLRevokedBuffer { throw GC_ERROR.notImplemented }
    func DSGetParentDev(_ hDS: DS_HANDLE) throws -> DEV_HANDLE { throw GC_ERROR.notImplemented }
    func DSClose(_ hDS: DS_HANDLE) throws { throw GC_ERROR.notImplemented }

    func GCReadPort(_ hPort: PORT_HANDLE, address: UInt64, size: Int) throws -> Data { throw GC_ERROR.notImplemented }
    func GCWritePort(_ hPort: PORT_HANDLE, address: UInt64, data: Data) throws { throw GC_ERROR.notImplemented }
    func GCGetPortURL(_ hPort: PORT_HANDLE) throws -> String { throw GC_ERROR.notImplemented }
    func GCGetNumPortURLs(_ hPort: PORT_HANDLE) throws -> UInt32 { throw GC_ERROR.notImplemented }
    func GCGetPortURLInfo(_ hPort: PORT_HANDLE, index: UInt32, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func GCGetPortInfo(_ hPort: PORT_HANDLE, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }

    func GCRegisterEvent(_ source: EVENTSRC_HANDLE, eventType: Int32) throws -> EVENT_HANDLE { throw GC_ERROR.notImplemented }
    func GCUnregisterEvent(_ source: EVENTSRC_HANDLE, eventType: Int32) throws { throw GC_ERROR.notImplemented }
    func EventGetData(_ event: EVENT_HANDLE, timeout: UInt64) throws -> Data { throw GC_ERROR.notImplemented }
    func EventGetDataInfo(_ event: EVENT_HANDLE, inputData: Data, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func EventGetInfo(_ event: EVENT_HANDLE, command: Int32) throws -> GenTLInfoValue { throw GC_ERROR.notImplemented }
    func EventFlush(_ event: EVENT_HANDLE) throws { throw GC_ERROR.notImplemented }
    func EventKill(_ event: EVENT_HANDLE) throws { throw GC_ERROR.notImplemented }
}
