#include "GenTL_v1_6.h"
#include <stdint.h>
#include <string.h>

static uint32_t mock_call_counts[64];

#define MOCK_STUB_CODE(index, name, signature, code) \
    GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE name signature { \
        mock_call_counts[index]++; \
        return (GC_ERROR)(code); \
    }

#ifndef MOCK_OMIT_GCGETINFO
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCGetInfo(
    TL_INFO_CMD command,
    INFO_DATATYPE *type,
    void *buffer,
    size_t *size
) {
    (void)command;
    mock_call_counts[0]++;
    if (type != NULL) *type = INFO_DATATYPE_UINT32;
    if (size != NULL) {
        if (buffer != NULL && *size >= sizeof(uint32_t)) {
            const uint32_t marker = UINT32_C(0xC0FFEE01);
            memcpy(buffer, &marker, sizeof(marker));
        }
        *size = sizeof(uint32_t);
    }
    return (GC_ERROR)-4321;
}
#endif

GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCInitLib(void) {
    mock_call_counts[2]++;
    return GC_ERR_SUCCESS;
}
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCCloseLib(void) {
    mock_call_counts[3]++;
    return GC_ERR_SUCCESS;
}
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCRegisterEvent(
    EVENTSRC_HANDLE source, EVENT_TYPE eventType, EVENT_HANDLE *event
) {
    (void)source;
    (void)eventType;
    mock_call_counts[8]++;
    if (event == NULL) return GC_ERR_INVALID_PARAMETER;
    *event = (EVENT_HANDLE)(uintptr_t)0x1234;
    return GC_ERR_SUCCESS;
}
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCUnregisterEvent(
    EVENTSRC_HANDLE source, EVENT_TYPE eventType
) {
    (void)source;
    (void)eventType;
    mock_call_counts[9]++;
    return GC_ERR_SUCCESS;
}
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE EventKill(EVENT_HANDLE event) {
    (void)event;
    mock_call_counts[14]++;
    return GC_ERR_SUCCESS;
}

MOCK_STUB_CODE(1, GCGetLastError, (GC_ERROR *piErrorCode, char *sErrText, size_t *piSize), -6001)
MOCK_STUB_CODE(4, GCReadPort, (PORT_HANDLE hPort, uint64_t iAddress, void *pBuffer, size_t *piSize), -6004)
MOCK_STUB_CODE(5, GCWritePort, (PORT_HANDLE hPort, uint64_t iAddress, const void *pBuffer, size_t *piSize), -6005)
MOCK_STUB_CODE(6, GCGetPortURL, (PORT_HANDLE hPort, char *sURL, size_t *piSize), -6006)
MOCK_STUB_CODE(7, GCGetPortInfo, (PORT_HANDLE hPort, PORT_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6007)
MOCK_STUB_CODE(10, EventGetData, (EVENT_HANDLE hEvent, void *pBuffer, size_t *piSize, uint64_t iTimeout), -6010)
MOCK_STUB_CODE(11, EventGetDataInfo, (EVENT_HANDLE hEvent, const void *pInBuffer, size_t iInSize, EVENT_DATA_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pOutBuffer, size_t *piOutSize), -6011)
MOCK_STUB_CODE(12, EventGetInfo, (EVENT_HANDLE hEvent, EVENT_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6012)
MOCK_STUB_CODE(13, EventFlush, (EVENT_HANDLE hEvent), -6013)
MOCK_STUB_CODE(15, TLOpen, (TL_HANDLE *phTL), -6015)
MOCK_STUB_CODE(16, TLClose, (TL_HANDLE hTL), -6016)
MOCK_STUB_CODE(17, TLGetInfo, (TL_HANDLE hTL, TL_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6017)
MOCK_STUB_CODE(18, TLGetNumInterfaces, (TL_HANDLE hTL, uint32_t *piNumIfaces), -6018)
MOCK_STUB_CODE(19, TLGetInterfaceID, (TL_HANDLE hTL, uint32_t iIndex,  char *sID, size_t *piSize), -6019)
MOCK_STUB_CODE(20, TLGetInterfaceInfo, (TL_HANDLE hTL, const char *sIfaceID, INTERFACE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6020)
MOCK_STUB_CODE(21, TLOpenInterface, (TL_HANDLE hTL, const char *sIfaceID, IF_HANDLE *phIface), -6021)
MOCK_STUB_CODE(22, TLUpdateInterfaceList, (TL_HANDLE hTL, bool8_t *pbChanged, uint64_t iTimeout), -6022)
MOCK_STUB_CODE(23, IFClose, (IF_HANDLE hIface), -6023)
MOCK_STUB_CODE(24, IFGetInfo, (IF_HANDLE hIface, INTERFACE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6024)
MOCK_STUB_CODE(25, IFGetNumDevices, (IF_HANDLE hIface, uint32_t *piNumDevices), -6025)
MOCK_STUB_CODE(26, IFGetDeviceID, (IF_HANDLE hIface, uint32_t iIndex, char *sIDeviceID, size_t *piSize), -6026)
MOCK_STUB_CODE(27, IFUpdateDeviceList, (IF_HANDLE hIface, bool8_t *pbChanged, uint64_t iTimeout), -6027)
MOCK_STUB_CODE(28, IFGetDeviceInfo, (IF_HANDLE hIface, const char *sDeviceID, DEVICE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6028)
MOCK_STUB_CODE(29, IFOpenDevice, (IF_HANDLE hIface, const char *sDeviceID, DEVICE_ACCESS_FLAGS iOpenFlag, DEV_HANDLE *phDevice), -6029)
MOCK_STUB_CODE(30, DevGetPort, (DEV_HANDLE hDevice, PORT_HANDLE *phRemoteDevice), -6030)
MOCK_STUB_CODE(31, DevGetNumDataStreams, (DEV_HANDLE hDevice, uint32_t *piNumDataStreams), -6031)
MOCK_STUB_CODE(32, DevGetDataStreamID, (DEV_HANDLE hDevice, uint32_t iIndex, char *sDataStreamID, size_t *piSize), -6032)
MOCK_STUB_CODE(33, DevOpenDataStream, (DEV_HANDLE hDevice, const char *sDataStreamID, DS_HANDLE *phDataStream), -6033)
MOCK_STUB_CODE(34, DevGetInfo, (DEV_HANDLE hDevice, DEVICE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6034)
MOCK_STUB_CODE(35, DevClose, (DEV_HANDLE hDevice), -6035)
MOCK_STUB_CODE(36, DSAnnounceBuffer, (DS_HANDLE hDataStream, void *pBuffer, size_t iSize, void *pPrivate, BUFFER_HANDLE *phBuffer), -6036)
MOCK_STUB_CODE(37, DSAllocAndAnnounceBuffer, (DS_HANDLE hDataStream, size_t iSize, void *pPrivate, BUFFER_HANDLE *phBuffer), -6037)
MOCK_STUB_CODE(38, DSFlushQueue, (DS_HANDLE hDataStream, ACQ_QUEUE_TYPE iOperation), -6038)
MOCK_STUB_CODE(39, DSStartAcquisition, (DS_HANDLE hDataStream, ACQ_START_FLAGS iStartFlags, uint64_t iNumToAcquire), -6039)
MOCK_STUB_CODE(40, DSStopAcquisition, (DS_HANDLE hDataStream, ACQ_STOP_FLAGS iStopFlags), -6040)
MOCK_STUB_CODE(41, DSGetInfo, (DS_HANDLE hDataStream, STREAM_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6041)
MOCK_STUB_CODE(42, DSGetBufferID, (DS_HANDLE hDataStream, uint32_t iIndex, BUFFER_HANDLE *phBuffer), -6042)
MOCK_STUB_CODE(43, DSClose, (DS_HANDLE hDataStream), -6043)
MOCK_STUB_CODE(44, DSRevokeBuffer, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, void **pBuffer, void **pPrivate), -6044)
MOCK_STUB_CODE(45, DSQueueBuffer, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer), -6045)
MOCK_STUB_CODE(46, DSGetBufferInfo, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, BUFFER_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6046)
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(47, GCGetNumPortURLs, (PORT_HANDLE hPort, uint32_t *piNumURLs), -6047)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(48, GCGetPortURLInfo, (PORT_HANDLE hPort, uint32_t iURLIndex, URL_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6048)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(49, GCReadPortStacked, (PORT_HANDLE hPort, PORT_REGISTER_STACK_ENTRY *pEntries, size_t *piNumEntries), -6049)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(50, GCWritePortStacked, (PORT_HANDLE hPort, PORT_REGISTER_STACK_ENTRY *pEntries, size_t *piNumEntries), -6050)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(51, DSGetBufferChunkData, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, SINGLE_CHUNK_DATA *pChunkData, size_t *piNumChunks), -6051)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(52, IFGetParentTL, (IF_HANDLE hIface, TL_HANDLE *phSystem), -6052)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(53, DevGetParentIF, (DEV_HANDLE hDevice, IF_HANDLE *phIface), -6053)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(54, DSGetParentDev, (DS_HANDLE hDataStream, DEV_HANDLE *phDevice), -6054)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(55, DSGetNumBufferParts, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, uint32_t *piNumParts), -6055)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(56, DSGetBufferPartInfo, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, uint32_t iPartIndex, BUFFER_PART_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6056)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(57, DSAnnounceCompositeBuffer, (DS_HANDLE hDataStream, size_t iNumSegments, void **ppSegments, size_t *piSizes, void *pPrivate, BUFFER_HANDLE *phBuffer), -6057)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(58, DSGetBufferInfoStacked, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, DS_BUFFER_INFO_STACKED *pInfoStacked, size_t iNumInfos), -6058)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(59, DSGetBufferPartInfoStacked, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, DS_BUFFER_PART_INFO_STACKED *pInfoStacked, size_t iNumInfos), -6059)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(60, DSGetNumFlows, (DS_HANDLE hDataStream, uint32_t *piNumFlows), -6060)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(61, DSGetFlowInfo, (DS_HANDLE hDataStream, uint32_t iFlowIndex, FLOW_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6061)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(62, DSGetNumBufferSegments, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, uint32_t *piNumSegments), -6062)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(63, DSGetBufferSegmentInfo, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, uint32_t iSegmentIndex, SEGMENT_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -6063)
#endif

/* Test-only control export. It is not part of the GenTL ABI. */
GC_IMPORT_EXPORT uint32_t MockCTI_GetCallCount(uint32_t operationIndex) {
    if (operationIndex >= 64) return UINT32_MAX;
    return mock_call_counts[operationIndex];
}

#undef MOCK_STUB_CODE
