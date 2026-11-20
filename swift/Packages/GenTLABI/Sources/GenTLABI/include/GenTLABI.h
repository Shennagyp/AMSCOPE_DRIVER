#ifndef GENTL_ABI_H
#define GENTL_ABI_H

#include <stdint.h>
#include "GenTL_v1_6.h"

GC_ERROR GenTLABI_ErrorNotImplemented(void);
GC_ERROR GenTLABI_ErrorFromCode(enum GC_ERROR_LIST code);
uint32_t GenTLABI_HeaderVersion(void);
int GenTLABI_LayoutValid(void);

#endif
