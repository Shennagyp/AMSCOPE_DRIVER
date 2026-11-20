#include "GenTLABI.h"

#include <stddef.h>

_Static_assert(sizeof(EVENT_NEW_BUFFER_DATA) == 16, "GenTL EVENT_NEW_BUFFER_DATA ABI mismatch");
_Static_assert(offsetof(EVENT_NEW_BUFFER_DATA, BufferHandle) == 0, "GenTL new-buffer handle offset mismatch");
_Static_assert(offsetof(EVENT_NEW_BUFFER_DATA, pUserPointer) == 8, "GenTL new-buffer user-pointer offset mismatch");

_Static_assert(sizeof(PORT_REGISTER_STACK_ENTRY) == 24, "GenTL PORT_REGISTER_STACK_ENTRY ABI mismatch");
_Static_assert(offsetof(PORT_REGISTER_STACK_ENTRY, Address) == 0, "GenTL stack Address offset mismatch");
_Static_assert(offsetof(PORT_REGISTER_STACK_ENTRY, pBuffer) == 8, "GenTL stack pBuffer offset mismatch");
_Static_assert(offsetof(PORT_REGISTER_STACK_ENTRY, Size) == 16, "GenTL stack Size offset mismatch");

_Static_assert(sizeof(SINGLE_CHUNK_DATA) == 24, "GenTL SINGLE_CHUNK_DATA ABI mismatch");
_Static_assert(offsetof(SINGLE_CHUNK_DATA, ChunkID) == 0, "GenTL chunk ID offset mismatch");
_Static_assert(offsetof(SINGLE_CHUNK_DATA, ChunkOffset) == 8, "GenTL chunk offset mismatch");
_Static_assert(offsetof(SINGLE_CHUNK_DATA, ChunkLength) == 16, "GenTL chunk length offset mismatch");
_Static_assert(sizeof(DS_BUFFER_INFO_STACKED) == 28, "GenTL DS_BUFFER_INFO_STACKED ABI mismatch");
_Static_assert(offsetof(DS_BUFFER_INFO_STACKED, iInfoCmd) == 0, "GenTL stacked buffer-info command offset mismatch");
_Static_assert(offsetof(DS_BUFFER_INFO_STACKED, iType) == 4, "GenTL stacked buffer-info type offset mismatch");
_Static_assert(offsetof(DS_BUFFER_INFO_STACKED, pBuffer) == 8, "GenTL stacked buffer-info pointer offset mismatch");
_Static_assert(offsetof(DS_BUFFER_INFO_STACKED, iSize) == 16, "GenTL stacked buffer-info size offset mismatch");
_Static_assert(offsetof(DS_BUFFER_INFO_STACKED, iResult) == 24, "GenTL stacked buffer-info result offset mismatch");
_Static_assert(sizeof(DS_BUFFER_PART_INFO_STACKED) == 32, "GenTL DS_BUFFER_PART_INFO_STACKED ABI mismatch");
_Static_assert(offsetof(DS_BUFFER_PART_INFO_STACKED, iPartIndex) == 0, "GenTL stacked part-info index offset mismatch");
_Static_assert(offsetof(DS_BUFFER_PART_INFO_STACKED, iInfoCmd) == 4, "GenTL stacked part-info command offset mismatch");
_Static_assert(offsetof(DS_BUFFER_PART_INFO_STACKED, iResult) == 8, "GenTL stacked part-info result offset mismatch");
_Static_assert(offsetof(DS_BUFFER_PART_INFO_STACKED, iType) == 12, "GenTL stacked part-info type offset mismatch");
_Static_assert(offsetof(DS_BUFFER_PART_INFO_STACKED, pBuffer) == 16, "GenTL stacked part-info pointer offset mismatch");
_Static_assert(offsetof(DS_BUFFER_PART_INFO_STACKED, iSize) == 24, "GenTL stacked part-info size offset mismatch");

uint32_t GenTLABI_HeaderVersion(void) {
    return ((uint32_t)GenTLMajorVersion << 24) |
           ((uint32_t)GenTLMinorVersion << 16) |
           (uint32_t)GenTLSubMinorVersion;
}

int GenTLABI_LayoutValid(void) {
    return sizeof(void *) == 8 &&
           sizeof(EVENT_NEW_BUFFER_DATA) == 16 &&
           offsetof(EVENT_NEW_BUFFER_DATA, BufferHandle) == 0 &&
           offsetof(EVENT_NEW_BUFFER_DATA, pUserPointer) == 8 &&
           sizeof(PORT_REGISTER_STACK_ENTRY) == 24 &&
           sizeof(SINGLE_CHUNK_DATA) == 24 &&
           sizeof(DS_BUFFER_INFO_STACKED) == 28 &&
           sizeof(DS_BUFFER_PART_INFO_STACKED) == 32;
}

GC_ERROR GenTLABI_ErrorNotImplemented(void) {
    return (GC_ERROR)GC_ERR_NOT_IMPLEMENTED;
}
