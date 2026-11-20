@_exported import GenTLABI

/// The GenTL Consumer API contract.
///
/// Each requirement has the same operation name, parameter order, pointer
/// semantics, and GC_ERROR result as the corresponding function declared by
/// the pinned GenTL C header. This is a Swift protocol over the imported C
/// ABI types; it is not itself a C-exporting GenTL Producer.
///
/// Implementations must preserve the C API's output-parameter behavior.
/// They must not convert GenTL errors into Swift throws or replace GenTL
/// handles with application-generated object wrappers at this boundary.
public protocol GenTLAPI: Sendable {
    // MARK: Library

    func GCGetInfo(
        _ iInfoCmd: GenTLABI.TL_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func GCGetLastError(
        _ piErrorCode: UnsafeMutablePointer<GenTLABI.GC_ERROR>?,
        _ sErrText: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func GCInitLib() -> GenTLABI.GC_ERROR
    func GCCloseLib() -> GenTLABI.GC_ERROR

    // MARK: Port

    func GCReadPort(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iAddress: UInt64,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func GCWritePort(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iAddress: UInt64,
        _ pBuffer: UnsafeRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func GCGetPortURL(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ sURL: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func GCGetPortInfo(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iInfoCmd: GenTLABI.PORT_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    // MARK: Signaling and Events

    func GCRegisterEvent(
        _ hEventSrc: GenTLABI.EVENTSRC_HANDLE,
        _ iEventID: GenTLABI.EVENT_TYPE,
        _ phEvent: UnsafeMutablePointer<GenTLABI.EVENT_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func GCUnregisterEvent(
        _ hEventSrc: GenTLABI.EVENTSRC_HANDLE,
        _ iEventID: GenTLABI.EVENT_TYPE
    ) -> GenTLABI.GC_ERROR

    func EventGetData(
        _ hEvent: GenTLABI.EVENT_HANDLE,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR

    func EventGetDataInfo(
        _ hEvent: GenTLABI.EVENT_HANDLE,
        _ pInBuffer: UnsafeRawPointer?,
        _ iInSize: Int,
        _ iInfoCmd: GenTLABI.EVENT_DATA_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pOutBuffer: UnsafeMutableRawPointer?,
        _ piOutSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func EventGetInfo(
        _ hEvent: GenTLABI.EVENT_HANDLE,
        _ iInfoCmd: GenTLABI.EVENT_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func EventFlush(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR
    func EventKill(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR

    // MARK: System

    func TLOpen(_ phTL: UnsafeMutablePointer<GenTLABI.TL_HANDLE>?) -> GenTLABI.GC_ERROR
    func TLClose(_ hTL: GenTLABI.TL_HANDLE) -> GenTLABI.GC_ERROR

    func TLGetInfo(
        _ hTL: GenTLABI.TL_HANDLE,
        _ iInfoCmd: GenTLABI.TL_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func TLGetNumInterfaces(
        _ hTL: GenTLABI.TL_HANDLE,
        _ piNumIfaces: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR

    func TLGetInterfaceID(
        _ hTL: GenTLABI.TL_HANDLE,
        _ iIndex: UInt32,
        _ sID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func TLGetInterfaceInfo(
        _ hTL: GenTLABI.TL_HANDLE,
        _ sIfaceID: UnsafePointer<CChar>?,
        _ iInfoCmd: GenTLABI.INTERFACE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func TLOpenInterface(
        _ hTL: GenTLABI.TL_HANDLE,
        _ sIfaceID: UnsafePointer<CChar>?,
        _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func TLUpdateInterfaceList(
        _ hTL: GenTLABI.TL_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR

    // MARK: Interface

    func IFClose(_ hIface: GenTLABI.IF_HANDLE) -> GenTLABI.GC_ERROR

    func IFGetInfo(
        _ hIface: GenTLABI.IF_HANDLE,
        _ iInfoCmd: GenTLABI.INTERFACE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func IFGetNumDevices(
        _ hIface: GenTLABI.IF_HANDLE,
        _ piNumDevices: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR

    func IFGetDeviceID(
        _ hIface: GenTLABI.IF_HANDLE,
        _ iIndex: UInt32,
        _ sDeviceID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func IFUpdateDeviceList(
        _ hIface: GenTLABI.IF_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR

    func IFGetDeviceInfo(
        _ hIface: GenTLABI.IF_HANDLE,
        _ sDeviceID: UnsafePointer<CChar>?,
        _ iInfoCmd: GenTLABI.DEVICE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func IFOpenDevice(
        _ hIface: GenTLABI.IF_HANDLE,
        _ sDeviceID: UnsafePointer<CChar>?,
        _ iOpenFlag: GenTLABI.DEVICE_ACCESS_FLAGS,
        _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    // MARK: Device

    func DevGetPort(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ phRemoteDevice: UnsafeMutablePointer<GenTLABI.PORT_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func DevGetNumDataStreams(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ piNumDataStreams: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR

    func DevGetDataStreamID(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ iIndex: UInt32,
        _ sDataStreamID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func DevOpenDataStream(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ sDataStreamID: UnsafePointer<CChar>?,
        _ phDataStream: UnsafeMutablePointer<GenTLABI.DS_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func DevGetInfo(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ iInfoCmd: GenTLABI.DEVICE_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func DevClose(_ hDevice: GenTLABI.DEV_HANDLE) -> GenTLABI.GC_ERROR

    // MARK: Data Stream and Buffers

    func DSAnnounceBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ iSize: Int,
        _ pPrivate: UnsafeMutableRawPointer?,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func DSAllocAndAnnounceBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iSize: Int,
        _ pPrivate: UnsafeMutableRawPointer?,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func DSFlushQueue(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iOperation: GenTLABI.ACQ_QUEUE_TYPE
    ) -> GenTLABI.GC_ERROR

    func DSStartAcquisition(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iStartFlags: GenTLABI.ACQ_START_FLAGS,
        _ iNumToAcquire: UInt64
    ) -> GenTLABI.GC_ERROR

    func DSStopAcquisition(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iStopFlags: GenTLABI.ACQ_STOP_FLAGS
    ) -> GenTLABI.GC_ERROR

    func DSGetInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iInfoCmd: GenTLABI.STREAM_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func DSGetBufferID(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iIndex: UInt32,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func DSClose(_ hDataStream: GenTLABI.DS_HANDLE) -> GenTLABI.GC_ERROR

    func DSRevokeBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ ppBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
        _ ppPrivate: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> GenTLABI.GC_ERROR

    func DSQueueBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE
    ) -> GenTLABI.GC_ERROR

    func DSGetBufferInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ iInfoCmd: GenTLABI.BUFFER_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    // MARK: GenTL 1.1 Port Extensions

    func GCGetNumPortURLs(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ piNumURLs: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR

    func GCGetPortURLInfo(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ iURLIndex: UInt32,
        _ iInfoCmd: GenTLABI.URL_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func GCReadPortStacked(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ pEntries: UnsafeMutablePointer<GenTLABI.PORT_REGISTER_STACK_ENTRY>?,
        _ piNumEntries: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func GCWritePortStacked(
        _ hPort: GenTLABI.PORT_HANDLE,
        _ pEntries: UnsafeMutablePointer<GenTLABI.PORT_REGISTER_STACK_ENTRY>?,
        _ piNumEntries: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    // MARK: GenTL 1.3

    func DSGetBufferChunkData(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pChunkData: UnsafeMutablePointer<GenTLABI.SINGLE_CHUNK_DATA>?,
        _ piNumChunks: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    // MARK: GenTL 1.4

    func IFGetParentTL(
        _ hIface: GenTLABI.IF_HANDLE,
        _ phSystem: UnsafeMutablePointer<GenTLABI.TL_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func DevGetParentIF(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func DSGetParentDev(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    // MARK: GenTL 1.5

    func DSGetNumBufferParts(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ piNumParts: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR

    func DSGetBufferPartInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ iPartIndex: UInt32,
        _ iInfoCmd: GenTLABI.BUFFER_PART_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    // MARK: GenTL 1.6

    func DSAnnounceCompositeBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iNumSegments: Int,
        _ ppSegments: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
        _ piSizes: UnsafeMutablePointer<Int>?,
        _ pPrivate: UnsafeMutableRawPointer?,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?
    ) -> GenTLABI.GC_ERROR

    func DSGetBufferInfoStacked(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pInfoStacked: UnsafeMutablePointer<GenTLABI.DS_BUFFER_INFO_STACKED>?,
        _ iNumInfos: Int
    ) -> GenTLABI.GC_ERROR

    func DSGetBufferPartInfoStacked(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ pInfoStacked: UnsafeMutablePointer<GenTLABI.DS_BUFFER_PART_INFO_STACKED>?,
        _ iNumInfos: Int
    ) -> GenTLABI.GC_ERROR

    func DSGetNumFlows(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ piNumFlows: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR

    func DSGetFlowInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iFlowIndex: UInt32,
        _ iInfoCmd: GenTLABI.FLOW_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR

    func DSGetNumBufferSegments(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ piNumSegments: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR

    func DSGetBufferSegmentInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ iSegmentIndex: UInt32,
        _ iInfoCmd: GenTLABI.SEGMENT_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR
}
