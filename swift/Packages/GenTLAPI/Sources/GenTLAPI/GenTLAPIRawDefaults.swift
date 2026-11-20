import GenTLABI

public extension GenTLAPI {
    // Unsupported operations must return the standard GenTL error rather than
    // fabricating a capability. Concrete backends override the operations they
    // implement.

    func GCGetInfo(_ iInfoCmd: GenTLABI.TL_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCGetLastError(_ piErrorCode: UnsafeMutablePointer<GenTLABI.GC_ERROR>?, _ sErrText: UnsafeMutablePointer<CChar>?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCInitLib() -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCCloseLib() -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func GCReadPort(_ hPort: GenTLABI.PORT_HANDLE, _ iAddress: UInt64, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCWritePort(_ hPort: GenTLABI.PORT_HANDLE, _ iAddress: UInt64, _ pBuffer: UnsafeRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCGetPortURL(_ hPort: GenTLABI.PORT_HANDLE, _ sURL: UnsafeMutablePointer<CChar>?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCGetPortInfo(_ hPort: GenTLABI.PORT_HANDLE, _ iInfoCmd: GenTLABI.PORT_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func GCRegisterEvent(_ hEventSrc: GenTLABI.EVENTSRC_HANDLE, _ iEventID: GenTLABI.EVENT_TYPE, _ phEvent: UnsafeMutablePointer<GenTLABI.EVENT_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCUnregisterEvent(_ hEventSrc: GenTLABI.EVENTSRC_HANDLE, _ iEventID: GenTLABI.EVENT_TYPE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func EventGetData(_ hEvent: GenTLABI.EVENT_HANDLE, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?, _ iTimeout: UInt64) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func EventGetDataInfo(_ hEvent: GenTLABI.EVENT_HANDLE, _ pInBuffer: UnsafeRawPointer?, _ iInSize: Int, _ iInfoCmd: GenTLABI.EVENT_DATA_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pOutBuffer: UnsafeMutableRawPointer?, _ piOutSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func EventGetInfo(_ hEvent: GenTLABI.EVENT_HANDLE, _ iInfoCmd: GenTLABI.EVENT_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func EventFlush(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func EventKill(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func TLOpen(_ phTL: UnsafeMutablePointer<GenTLABI.TL_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func TLClose(_ hTL: GenTLABI.TL_HANDLE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func TLGetInfo(_ hTL: GenTLABI.TL_HANDLE, _ iInfoCmd: GenTLABI.TL_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func TLGetNumInterfaces(_ hTL: GenTLABI.TL_HANDLE, _ piNumIfaces: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func TLGetInterfaceID(_ hTL: GenTLABI.TL_HANDLE, _ iIndex: UInt32, _ sID: UnsafeMutablePointer<CChar>?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func TLGetInterfaceInfo(_ hTL: GenTLABI.TL_HANDLE, _ sIfaceID: UnsafePointer<CChar>?, _ iInfoCmd: GenTLABI.INTERFACE_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func TLOpenInterface(_ hTL: GenTLABI.TL_HANDLE, _ sIfaceID: UnsafePointer<CChar>?, _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func TLUpdateInterfaceList(_ hTL: GenTLABI.TL_HANDLE, _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?, _ iTimeout: UInt64) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func IFClose(_ hIface: GenTLABI.IF_HANDLE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func IFGetInfo(_ hIface: GenTLABI.IF_HANDLE, _ iInfoCmd: GenTLABI.INTERFACE_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func IFGetNumDevices(_ hIface: GenTLABI.IF_HANDLE, _ piNumDevices: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func IFGetDeviceID(_ hIface: GenTLABI.IF_HANDLE, _ iIndex: UInt32, _ sDeviceID: UnsafeMutablePointer<CChar>?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func IFUpdateDeviceList(_ hIface: GenTLABI.IF_HANDLE, _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?, _ iTimeout: UInt64) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func IFGetDeviceInfo(_ hIface: GenTLABI.IF_HANDLE, _ sDeviceID: UnsafePointer<CChar>?, _ iInfoCmd: GenTLABI.DEVICE_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func IFOpenDevice(_ hIface: GenTLABI.IF_HANDLE, _ sDeviceID: UnsafePointer<CChar>?, _ iOpenFlag: GenTLABI.DEVICE_ACCESS_FLAGS, _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func DevGetPort(_ hDevice: GenTLABI.DEV_HANDLE, _ phRemoteDevice: UnsafeMutablePointer<GenTLABI.PORT_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DevGetNumDataStreams(_ hDevice: GenTLABI.DEV_HANDLE, _ piNumDataStreams: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DevGetDataStreamID(_ hDevice: GenTLABI.DEV_HANDLE, _ iIndex: UInt32, _ sDataStreamID: UnsafeMutablePointer<CChar>?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DevOpenDataStream(_ hDevice: GenTLABI.DEV_HANDLE, _ sDataStreamID: UnsafePointer<CChar>?, _ phDataStream: UnsafeMutablePointer<GenTLABI.DS_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DevGetInfo(_ hDevice: GenTLABI.DEV_HANDLE, _ iInfoCmd: GenTLABI.DEVICE_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DevClose(_ hDevice: GenTLABI.DEV_HANDLE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func DSAnnounceBuffer(_ hDataStream: GenTLABI.DS_HANDLE, _ pBuffer: UnsafeMutableRawPointer?, _ iSize: Int, _ pPrivate: UnsafeMutableRawPointer?, _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSAllocAndAnnounceBuffer(_ hDataStream: GenTLABI.DS_HANDLE, _ iSize: Int, _ pPrivate: UnsafeMutableRawPointer?, _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSFlushQueue(_ hDataStream: GenTLABI.DS_HANDLE, _ iOperation: GenTLABI.ACQ_QUEUE_TYPE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSStartAcquisition(_ hDataStream: GenTLABI.DS_HANDLE, _ iStartFlags: GenTLABI.ACQ_START_FLAGS, _ iNumToAcquire: UInt64) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSStopAcquisition(_ hDataStream: GenTLABI.DS_HANDLE, _ iStopFlags: GenTLABI.ACQ_STOP_FLAGS) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetInfo(_ hDataStream: GenTLABI.DS_HANDLE, _ iInfoCmd: GenTLABI.STREAM_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetBufferID(_ hDataStream: GenTLABI.DS_HANDLE, _ iIndex: UInt32, _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSClose(_ hDataStream: GenTLABI.DS_HANDLE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSRevokeBuffer(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ ppBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ ppPrivate: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSQueueBuffer(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetBufferInfo(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ iInfoCmd: GenTLABI.BUFFER_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func GCGetNumPortURLs(_ hPort: GenTLABI.PORT_HANDLE, _ piNumURLs: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCGetPortURLInfo(_ hPort: GenTLABI.PORT_HANDLE, _ iURLIndex: UInt32, _ iInfoCmd: GenTLABI.URL_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCReadPortStacked(_ hPort: GenTLABI.PORT_HANDLE, _ pEntries: UnsafeMutablePointer<GenTLABI.PORT_REGISTER_STACK_ENTRY>?, _ piNumEntries: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func GCWritePortStacked(_ hPort: GenTLABI.PORT_HANDLE, _ pEntries: UnsafeMutablePointer<GenTLABI.PORT_REGISTER_STACK_ENTRY>?, _ piNumEntries: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func DSGetBufferChunkData(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ pChunkData: UnsafeMutablePointer<GenTLABI.SINGLE_CHUNK_DATA>?, _ piNumChunks: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func IFGetParentTL(_ hIface: GenTLABI.IF_HANDLE, _ phSystem: UnsafeMutablePointer<GenTLABI.TL_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DevGetParentIF(_ hDevice: GenTLABI.DEV_HANDLE, _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetParentDev(_ hDataStream: GenTLABI.DS_HANDLE, _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func DSGetNumBufferParts(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ piNumParts: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetBufferPartInfo(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ iPartIndex: UInt32, _ iInfoCmd: GenTLABI.BUFFER_PART_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }

    func DSAnnounceCompositeBuffer(_ hDataStream: GenTLABI.DS_HANDLE, _ iNumSegments: Int, _ ppSegments: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ piSizes: UnsafeMutablePointer<Int>?, _ pPrivate: UnsafeMutableRawPointer?, _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetBufferInfoStacked(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ pInfoStacked: UnsafeMutablePointer<GenTLABI.DS_BUFFER_INFO_STACKED>?, _ iNumInfos: Int) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetBufferPartInfoStacked(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ pInfoStacked: UnsafeMutablePointer<GenTLABI.DS_BUFFER_PART_INFO_STACKED>?, _ iNumInfos: Int) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetNumFlows(_ hDataStream: GenTLABI.DS_HANDLE, _ piNumFlows: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetFlowInfo(_ hDataStream: GenTLABI.DS_HANDLE, _ iFlowIndex: UInt32, _ iInfoCmd: GenTLABI.FLOW_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetNumBufferSegments(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ piNumSegments: UnsafeMutablePointer<UInt32>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
    func DSGetBufferSegmentInfo(_ hDataStream: GenTLABI.DS_HANDLE, _ hBuffer: GenTLABI.BUFFER_HANDLE, _ iSegmentIndex: UInt32, _ iInfoCmd: GenTLABI.SEGMENT_INFO_CMD, _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?, _ pBuffer: UnsafeMutableRawPointer?, _ piSize: UnsafeMutablePointer<Int>?) -> GenTLABI.GC_ERROR { GenTLABI.GenTLABI_ErrorNotImplemented() }
}
