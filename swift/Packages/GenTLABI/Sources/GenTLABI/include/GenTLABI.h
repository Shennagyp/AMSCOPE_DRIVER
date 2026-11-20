#ifndef GENTL_ABI_H
#define GENTL_ABI_H

#include <stdint.h>
#include "GenTL_v1_6.h"

GC_ERROR GenTLABI_ErrorNotImplemented(void);
uint32_t GenTLABI_HeaderVersion(void);
int GenTLABI_LayoutValid(void);

#endif
