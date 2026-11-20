#include "GenTL_v1_6.h"
#include <string.h>

#define MOCK_STUB(name, signature) \
    GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE name signature { return GC_ERR_NOT_IMPLEMENTED; }

/* This operation has observable outputs so the Swift test can prove that
   the real C function pointer was invoked with the original output storage. */
GC_IMPORT_EXPORT GC_ERROR GC_CALLTYPE GCGetInfo(
    TL_INFO_CMD command,
    INFO_DATATYPE *type,
    void *buffer,
    size_t *size
) {
    (void)command;
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

#ifndef MOCK_OMIT_GCGETINFO
/* The special implementation above is the exported GCGetInfo. */
#else
/* Build variant intentionally omits GCGetInfo to test required-symbol rejection. */
#endif

MOCK_STUB(GCGetLastError, (GC_ERROR *piErrorCode, char *sErrText, size_t *piSize))
MOCK_STUB(GCInitLib, (void))
MOCK_STUB(GCCloseLib, (void))
MOCK_STUB(GCReadPort, (PORT_HANDLE hPort, uint64_t iAddress, void *pBuffer, size_t *piSize))
MOCK_STUB(GCWritePort, (PORT_HANDLE hPort, uint64_t iAddress, const void *pBuffer, size_t *piSize))
MOCK_STUB(GCGetPortURL, (PORT_HANDLE hPort, char *sURL, size_t *piSize))
MOCK_STUB(GCGetPortInfo, (PORT_HANDLE hPort, PORT_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))
MOCK_STUB(GCRegisterEvent, (EVENTSRC_HANDLE hEventSrc, EVENT_TYPE iEventID, EVENT_HANDLE *phEvent))
MOCK_STUB(GCUnregisterEvent, (EVENTSRC_HANDLE hEventSrc, EVENT_TYPE iEventID))
MOCK_STUB(EventGetData, (EVENT_HANDLE hEvent, void *pBuffer, size_t *piSize, uint64_t iTimeout))
MOCK_STUB(EventGetDataInfo, (EVENT_HANDLE hEvent, const void *pInBuffer, size_t iInSize, EVENT_DATA_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pOutBuffer, size_t *piOutSize))
MOCK_STUB(EventGetInfo, (EVENT_HANDLE hEvent, EVENT_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))
MOCK_STUB(EventFlush, (EVENT_HANDLE hEvent))
MOCK_STUB(EventKill, (EVENT_HANDLE hEvent))
MOCK_STUB(TLOpen, (TL_HANDLE *phTL))
MOCK_STUB(TLClose, (TL_HANDLE hTL))
MOCK_STUB(TLGetInfo, (TL_HANDLE hTL, TL_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))
MOCK_STUB(TLGetNumInterfaces, (TL_HANDLE hTL, uint32_t *piNumIfaces))
MOCK_STUB(TLGetInterfaceID, (TL_HANDLE hTL, uint32_t iIndex, char *sID, size_t *piSize))
MOCK_STUB(TLGetInterfaceInfo, (TL_HANDLE hTL, const char *sIfaceID, INTERFACE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))
MOCK_STUB(TLOpenInterface, (TL_HANDLE hTL, const char *sIfaceID, IF_HANDLE *phIface))
MOCK_STUB(TLUpdateInterfaceList, (TL_HANDLE hTL, bool8_t *pbChanged, uint64_t iTimeout))
MOCK_STUB(IFClose, (IF_HANDLE hIface))
MOCK_STUB(IFGetInfo, (IF_HANDLE hIface, INTERFACE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))
MOCK_STUB(IFGetNumDevices, (IF_HANDLE hIface, uint32_t *piNumDevices))
MOCK_STUB(IFGetDeviceID, (IF_HANDLE hIface, uint32_t iIndex, char *sIDeviceID, size_t *piSize))
MOCK_STUB(IFUpdateDeviceList, (IF_HANDLE hIface, bool8_t *pbChanged, uint64_t iTimeout))
MOCK_STUB(IFGetDeviceInfo, (IF_HANDLE hIface, const char *sDeviceID, DEVICE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))
MOCK_STUB(IFOpenDevice, (IF_HANDLE hIface, const char *sDeviceID, DEVICE_ACCESS_FLAGS iOpenFlag, DEV_HANDLE *phDevice))
MOCK_STUB(DevGetPort, (DEV_HANDLE hDevice, PORT_HANDLE *phRemoteDevice))
MOCK_STUB(DevGetNumDataStreams, (DEV_HANDLE hDevice, uint32_t *piNumDataStreams))
MOCK_STUB(DevGetDataStreamID, (DEV_HANDLE hDevice, uint32_t iIndex, char *sDataStreamID, size_t *piSize))
MOCK_STUB(DevOpenDataStream, (DEV_HANDLE hDevice, const char *sDataStreamID, DS_HANDLE *phDataStream))
MOCK_STUB(DevGetInfo, (DEV_HANDLE hDevice, DEVICE_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))
MOCK_STUB(DevClose, (DEV_HANDLE hDevice))
MOCK_STUB(DSAnnounceBuffer, (DS_HANDLE hDataStream, void *pBuffer, size_t iSize, void *pPrivate, BUFFER_HANDLE *phBuffer))
MOCK_STUB(DSAllocAndAnnounceBuffer, (DS_HANDLE hDataStream, size_t iSize, void *pPrivate, BUFFER_HANDLE *phBuffer))
MOCK_STUB(DSFlushQueue, (DS_HANDLE hDataStream, ACQ_QUEUE_TYPE iOperation))
MOCK_STUB(DSStartAcquisition, (DS_HANDLE hDataStream, ACQ_START_FLAGS iStartFlags, uint64_t iNumToAcquire))
MOCK_STUB(DSStopAcquisition, (DS_HANDLE hDataStream, ACQ_STOP_FLAGS iStopFlags))
MOCK_STUB(DSGetInfo, (DS_HANDLE hDataStream, STREAM_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))
MOCK_STUB(DSGetBufferID, (DS_HANDLE hDataStream, uint32_t iIndex, BUFFER_HANDLE *phBuffer))
MOCK_STUB(DSClose, (DS_HANDLE hDataStream))
MOCK_STUB(DSRevokeBuffer, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, void **pBuffer, void **pPrivate))
MOCK_STUB(DSQueueBuffer, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer))
MOCK_STUB(DSGetBufferInfo, (DS_HANDLE hDataStream, BUFFER_HANDLE hBuffer, BUFFER_INFO_CMD iInfoCmd, INFO_DATATYPE *piType, void *pBuffer, size_t *piSize))

#undef MOCK_STUB
