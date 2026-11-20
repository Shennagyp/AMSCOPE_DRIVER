#include "GenTL_v1_6.h"
#include <stdint.h>
#include <string.h>

static uint32_t mock_call_counts[64];

#define MOCK_STUB_CODE(index, name, signature, code) \
    GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE name signature { \
        mock_call_counts[index]++; \
        return (GC_ERROR)(code); \
    }

#ifndef MOCK_OMIT_GCGetInfo
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCGetInfo(
    TL_INFO_CMD command,
    INFO_DATATYPE *type,
    void *buffer,
    size_t *size
) {
    mock_call_counts[0]++;
    if (command != (TL_INFO_CMD)0x1234) return (GC_ERROR)-11001;
    if (type != NULL) *type = INFO_DATATYPE_UINT32;
    if (size != NULL) {
        if (buffer != NULL && *size >= sizeof(uint32_t)) {
            const uint32_t marker = UINT32_C(0xC0FFEE01);
            memcpy(buffer, &marker, sizeof(marker));
        }
        *size = sizeof(uint32_t);
    }
    return (GC_ERROR)-11000;
}
#endif

#ifndef MOCK_OMIT_GCInitLib
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCInitLib(void) {
    mock_call_counts[2]++;
    return GC_ERR_SUCCESS;
}
#endif
#ifndef MOCK_OMIT_GCCloseLib
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCCloseLib(void) {
    mock_call_counts[3]++;
    return GC_ERR_SUCCESS;
}
#endif
#ifndef MOCK_OMIT_GCRegisterEvent
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
#endif
#ifndef MOCK_OMIT_GCUnregisterEvent
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCUnregisterEvent(
    EVENTSRC_HANDLE source, EVENT_TYPE eventType
) {
    (void)source;
    (void)eventType;
    mock_call_counts[9]++;
    return GC_ERR_SUCCESS;
}
#endif
#ifndef MOCK_OMIT_EventKill
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE EventKill(EVENT_HANDLE event) {
    (void)event;
    mock_call_counts[14]++;
    return GC_ERR_SUCCESS;
}
#endif

#ifndef MOCK_OMIT_GCGetLastError
MOCK_STUB_CODE(1, GCGetLastError, (GC_ERROR *piErrorCode, char *sErrText, size_t *piSize), -12001)
#endif
#ifndef MOCK_OMIT_GCReadPort
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCReadPort(
    PORT_HANDLE hPort, uint64_t iAddress, void *pBuffer, size_t *piSize
) {
    mock_call_counts[4]++;
    if (hPort != (PORT_HANDLE)(uintptr_t)0x1111 ||
        iAddress != UINT64_C(0x1020304050607080) ||
        pBuffer == NULL || piSize == NULL || *piSize < sizeof(uint32_t)) {
        return (GC_ERROR)-11041;
    }
    const uint32_t marker = UINT32_C(0xA1B2C3D4);
    memcpy(pBuffer, &marker, sizeof(marker));
    *piSize = sizeof(marker);
    return (GC_ERROR)-11004;
}
#endif
#ifndef MOCK_OMIT_GCWritePort
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCWritePort(
    PORT_HANDLE hPort, uint64_t iAddress, const void *pBuffer, size_t *piSize
) {
    mock_call_counts[5]++;
    const uint8_t expected[4] = {0x12, 0x34, 0x56, 0x78};
    if (hPort != (PORT_HANDLE)(uintptr_t)0x1111 ||
        iAddress != UINT64_C(0x1020304050607080) ||
        pBuffer == NULL || piSize == NULL || *piSize != sizeof(expected) ||
        memcmp(pBuffer, expected, sizeof(expected)) != 0) {
        return (GC_ERROR)-11051;
    }
    return (GC_ERROR)-11005;
}
#endif
#ifndef MOCK_OMIT_GCGetPortURL
MOCK_STUB_CODE(6, GCGetPortURL, (PORT_HANDLE hPort, char *sURL, size_t *piSize), -12006)
#endif
#ifndef MOCK_OMIT_GCGetPortInfo
MOCK_STUB_CODE(7, GCGetPortInfo, (PORT_HANDLE hPort, PORT_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12007)
#endif
#ifndef MOCK_OMIT_EventGetData
MOCK_STUB_CODE(10, EventGetData, (EVENT_HANDLE hEvent, void *pBuffer, size_t *piSize, uint64_t iTimeout), -12010)
#endif
#ifndef MOCK_OMIT_EventGetDataInfo
MOCK_STUB_CODE(11, EventGetDataInfo, (EVENT_HANDLE hEvent, const void *pInBuffer, size_t iInSize, EVENT_DATA_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pOutBuffer, size_t *piOutSize), -12011)
#endif
#ifndef MOCK_OMIT_EventGetInfo
MOCK_STUB_CODE(12, EventGetInfo, (EVENT_HANDLE hEvent, EVENT_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12012)
#endif
#ifndef MOCK_OMIT_EventFlush
MOCK_STUB_CODE(13, EventFlush, (EVENT_HANDLE hEvent), -12013)
#endif
#ifndef MOCK_OMIT_TLOpen
MOCK_STUB_CODE(15, TLOpen, (TL_HANDLE *phTL), -12015)
#endif
#ifndef MOCK_OMIT_TLClose
MOCK_STUB_CODE(16, TLClose, (TL_HANDLE hTL), -12016)
#endif
#ifndef MOCK_OMIT_TLGetInfo
MOCK_STUB_CODE(17, TLGetInfo, (TL_HANDLE hTL, TL_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12017)
#endif
#ifndef MOCK_OMIT_TLGetNumInterfaces
MOCK_STUB_CODE(18, TLGetNumInterfaces, (TL_HANDLE hTL, uint32_t *piNumIfaces), -12018)
#endif
#ifndef MOCK_OMIT_TLGetInterfaceID
MOCK_STUB_CODE(19, TLGetInterfaceID, (TL_HANDLE hTL, uint32_t iIndex,  char *sID, size_t *piSize), -12019)
#endif
#ifndef MOCK_OMIT_TLGetInterfaceInfo
MOCK_STUB_CODE(20, TLGetInterfaceInfo, (TL_HANDLE hTL, const char *sIfaceID, INTERFACE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12020)
#endif
#ifndef MOCK_OMIT_TLOpenInterface
MOCK_STUB_CODE(21, TLOpenInterface, (TL_HANDLE hTL, const char *sIfaceID, IF_HANDLE *phIface), -12021)
#endif
#ifndef MOCK_OMIT_TLUpdateInterfaceList
MOCK_STUB_CODE(22, TLUpdateInterfaceList, (TL_HANDLE hTL, bool8_t *pbChanged, uint64_t iTimeout), -12022)
#endif
#ifndef MOCK_OMIT_IFClose
MOCK_STUB_CODE(23, IFClose, (IF_HANDLE hIface), -12023)
#endif
#ifndef MOCK_OMIT_IFGetInfo
MOCK_STUB_CODE(24, IFGetInfo, (IF_HANDLE hIface, INTERFACE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12024)
#endif
#ifndef MOCK_OMIT_IFGetNumDevices
MOCK_STUB_CODE(25, IFGetNumDevices, (IF_HANDLE hIface, uint32_t *piNumDevices), -12025)
#endif
#ifndef MOCK_OMIT_IFGetDeviceID
MOCK_STUB_CODE(26, IFGetDeviceID, (IF_HANDLE hIface, uint32_t iIndex, char *sIDeviceID, size_t *piSize), -12026)
#endif
#ifndef MOCK_OMIT_IFUpdateDeviceList
MOCK_STUB_CODE(27, IFUpdateDeviceList, (IF_HANDLE hIface, bool8_t *pbChanged, uint64_t iTimeout), -12027)
#endif
#ifndef MOCK_OMIT_IFGetDeviceInfo
MOCK_STUB_CODE(28, IFGetDeviceInfo, (IF_HANDLE hIface, const char *sDeviceID, DEVICE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12028)
#endif
#ifndef MOCK_OMIT_IFOpenDevice
MOCK_STUB_CODE(29, IFOpenDevice, (IF_HANDLE hIface, const char *sDeviceID, DEVICE_ACCESS_FLAGS iOpenFlag, DEV_HANDLE *phDevice), -12029)
#endif
#ifndef MOCK_OMIT_DevGetPort
MOCK_STUB_CODE(30, DevGetPort, (DEV_HANDLE hDevice, PORT_HANDLE *phRemoteDevice), -12030)
#endif
#ifndef MOCK_OMIT_DevGetNumDataStreams
MOCK_STUB_CODE(31, DevGetNumDataStreams, (DEV_HANDLE hDevice, uint32_t *piNumDataStreams), -12031)
#endif
#ifndef MOCK_OMIT_DevGetDataStreamID
MOCK_STUB_CODE(32, DevGetDataStreamID, (DEV_HANDLE hDevice, uint32_t iIndex, char *sDataStreamID, size_t *piSize), -12032)
#endif
#ifndef MOCK_OMIT_DevOpenDataStream
MOCK_STUB_CODE(33, DevOpenDataStream, (DEV_HANDLE hDevice, const char *sDataStreamID, DS_HANDLE *phDataStream), -12033)
#endif
#ifndef MOCK_OMIT_DevGetInfo
MOCK_STUB_CODE(34, DevGetInfo, (DEV_HANDLE hDevice, DEVICE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12034)
#endif
#ifndef MOCK_OMIT_DevClose
MOCK_STUB_CODE(35, DevClose, (DEV_HANDLE hDevice), -12035)
#endif
#ifndef MOCK_OMIT_DSAnnounceBuffer
MOCK_STUB_CODE(36, DSAnnounceBuffer, (DS_HANDLE hDataStream, void *pBuffer, size_t iSize, void *pPrivate, BUFFER_HANDLE *phBuffer), -12036)
#endif
#ifndef MOCK_OMIT_DSAllocAndAnnounceBuffer
MOCK_STUB_CODE(37, DSAllocAndAnnounceBuffer, (DS_HANDLE hDataStream, size_t iSize, void *pPrivate, BUFFER_HANDLE *phBuffer), -12037)
#endif
#ifndef MOCK_OMIT_DSFlushQueue
MOCK_STUB_CODE(38, DSFlushQueue, (DS_HANDLE hDataStream, ACQ_QUEUE_TYPE iOperation), -12038)
#endif
#ifndef MOCK_OMIT_DSStartAcquisition
MOCK_STUB_CODE(39, DSStartAcquisition, (DS_HANDLE hDataStream, ACQ_START_FLAGS iStartFlags, uint64_t iNumToAcquire), -12039)
#endif
#ifndef MOCK_OMIT_DSStopAcquisition
MOCK_STUB_CODE(40, DSStopAcquisition, (DS_HANDLE hDataStream, ACQ_STOP_FLAGS iStopFlags), -12040)
#endif
#ifndef MOCK_OMIT_DSGetInfo
MOCK_STUB_CODE(41, DSGetInfo, (DS_HANDLE hDataStream, STREAM_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12041)
#endif
#ifndef MOCK_OMIT_DSGetBufferID
MOCK_STUB_CODE(42, DSGetBufferID, (DS_HANDLE hDataStream, uint32_t iIndex, BUFFER_HANDLE *phBuffer), -12042)
#endif
#ifndef MOCK_OMIT_DSClose
MOCK_STUB_CODE(43, DSClose, (DS_HANDLE hDataStream), -12043)
#endif
#ifndef MOCK_OMIT_DSRevokeBuffer
MOCK_STUB_CODE(44, DSRevokeBuffer, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, void **pBuffer, void **pPrivate), -12044)
#endif
#ifndef MOCK_OMIT_DSQueueBuffer
MOCK_STUB_CODE(45, DSQueueBuffer, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer), -12045)
#endif
#ifndef MOCK_OMIT_DSGetBufferInfo
MOCK_STUB_CODE(46, DSGetBufferInfo, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, BUFFER_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12046)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(47, GCGetNumPortURLs, (PORT_HANDLE hPort, uint32_t *piNumURLs), -12047)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(48, GCGetPortURLInfo, (PORT_HANDLE hPort, uint32_t iURLIndex, URL_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12048)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(49, GCReadPortStacked, (PORT_HANDLE hPort, PORT_REGISTER_STACK_ENTRY *pEntries, size_t *piNumEntries), -12049)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(50, GCWritePortStacked, (PORT_HANDLE hPort, PORT_REGISTER_STACK_ENTRY *pEntries, size_t *piNumEntries), -12050)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(51, DSGetBufferChunkData, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, SINGLE_CHUNK_DATA *pChunkData, size_t *piNumChunks), -12051)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(52, IFGetParentTL, (IF_HANDLE hIface, TL_HANDLE *phSystem), -12052)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(53, DevGetParentIF, (DEV_HANDLE hDevice, IF_HANDLE *phIface), -12053)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(54, DSGetParentDev, (DS_HANDLE hDataStream, DEV_HANDLE *phDevice), -12054)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(55, DSGetNumBufferParts, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, uint32_t *piNumParts), -12055)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(56, DSGetBufferPartInfo, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, uint32_t iPartIndex, BUFFER_PART_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12056)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(57, DSAnnounceCompositeBuffer, (DS_HANDLE hDataStream, size_t iNumSegments, void **ppSegments, size_t *piSizes, void *pPrivate, BUFFER_HANDLE *phBuffer), -12057)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(58, DSGetBufferInfoStacked, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, DS_BUFFER_INFO_STACKED *pInfoStacked, size_t iNumInfos), -12058)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(59, DSGetBufferPartInfoStacked, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, DS_BUFFER_PART_INFO_STACKED *pInfoStacked, size_t iNumInfos), -12059)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(60, DSGetNumFlows, (DS_HANDLE hDataStream, uint32_t *piNumFlows), -12060)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(61, DSGetFlowInfo, (DS_HANDLE hDataStream, uint32_t iFlowIndex, FLOW_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12061)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(62, DSGetNumBufferSegments, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, uint32_t *piNumSegments), -12062)
#endif
#ifndef MOCK_OMIT_OPTIONAL_EXPORTS
MOCK_STUB_CODE(63, DSGetBufferSegmentInfo, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, uint32_t iSegmentIndex, SEGMENT_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize), -12063)
#endif

/* Test-only control export. It is not part of the GenTL ABI. */
GC_IMPORT_EXPORT uint32_t MockCTI_GetCallCount(uint32_t operationIndex) {
    if (operationIndex >= 64) return UINT32_MAX;
    return mock_call_counts[operationIndex];
}

#undef MOCK_STUB_CODE
