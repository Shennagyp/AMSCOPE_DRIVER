#include "GenTLABI.h"
#include "GenTL_v1_6.h"

uint32_t GenTLABI_HeaderVersion(void) {
    return ((uint32_t)GenTLMajorVersion << 24) |
           ((uint32_t)GenTLMinorVersion << 16) |
           (uint32_t)GenTLSubMinorVersion;
}
