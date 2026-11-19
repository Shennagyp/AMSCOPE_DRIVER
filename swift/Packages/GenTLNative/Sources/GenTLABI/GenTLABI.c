#include "GenTLABI.h"

#include <stddef.h>

_Static_assert(sizeof(PORT_REGISTER_STACK_ENTRY) == 24, "GenTL PORT_REGISTER_STACK_ENTRY ABI mismatch");
_Static_assert(offsetof(PORT_REGISTER_STACK_ENTRY, Address) == 0, "GenTL stack Address offset mismatch");
_Static_assert(offsetof(PORT_REGISTER_STACK_ENTRY, pBuffer) == 8, "GenTL stack pBuffer offset mismatch");
_Static_assert(offsetof(PORT_REGISTER_STACK_ENTRY, Size) == 16, "GenTL stack Size offset mismatch");

_Static_assert(sizeof(SINGLE_CHUNK_DATA) == 24, "GenTL SINGLE_CHUNK_DATA ABI mismatch");
_Static_assert(sizeof(DS_BUFFER_INFO_STACKED) == 28, "GenTL DS_BUFFER_INFO_STACKED ABI mismatch");
_Static_assert(sizeof(DS_BUFFER_PART_INFO_STACKED) == 32, "GenTL DS_BUFFER_PART_INFO_STACKED ABI mismatch");

uint32_t GenTLABI_HeaderVersion(void) {
    return ((uint32_t)GenTLMajorVersion << 24) |
           ((uint32_t)GenTLMinorVersion << 16) |
           (uint32_t)GenTLSubMinorVersion;
}

int GenTLABI_LayoutValid(void) {
    return sizeof(void *) == 8 &&
           sizeof(PORT_REGISTER_STACK_ENTRY) == 24 &&
           sizeof(SINGLE_CHUNK_DATA) == 24 &&
           sizeof(DS_BUFFER_INFO_STACKED) == 28 &&
           sizeof(DS_BUFFER_PART_INFO_STACKED) == 32;
}
