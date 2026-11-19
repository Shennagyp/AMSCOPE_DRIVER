#include "AmcamABI.h"

_Static_assert(sizeof(AmcamResolutionV2) == 8, "AmcamResolutionV2 ABI mismatch");
_Static_assert(sizeof(AmcamModelV2) == 176, "AmcamModelV2 ABI mismatch");
_Static_assert(offsetof(AmcamModelV2, name) == 0, "AmcamModelV2.name offset mismatch");
_Static_assert(offsetof(AmcamModelV2, flag) == 8, "AmcamModelV2.flag offset mismatch");
_Static_assert(offsetof(AmcamModelV2, maxspeed) == 16, "AmcamModelV2.maxspeed offset mismatch");
_Static_assert(offsetof(AmcamModelV2, xpixsz) == 36, "AmcamModelV2.xpixsz offset mismatch");
_Static_assert(offsetof(AmcamModelV2, res) == 44, "AmcamModelV2.res offset mismatch");
_Static_assert(sizeof(AmcamDeviceV2) == 136, "AmcamDeviceV2 ABI mismatch");
_Static_assert(offsetof(AmcamDeviceV2, id) == 64, "AmcamDeviceV2.id offset mismatch");
_Static_assert(offsetof(AmcamDeviceV2, model) == 128, "AmcamDeviceV2.model offset mismatch");
_Static_assert(sizeof(AmcamFrameInfoV2) == 24, "AmcamFrameInfoV2 ABI mismatch");
_Static_assert(offsetof(AmcamFrameInfoV2, timestamp) == 16, "AmcamFrameInfoV2.timestamp offset mismatch");

int amcam_abi_layout_valid(void) {
    return sizeof(AmcamResolutionV2) == 8 && sizeof(AmcamModelV2) == 176 &&
           sizeof(AmcamDeviceV2) == 136 && sizeof(AmcamFrameInfoV2) == 24 &&
           offsetof(AmcamDeviceV2, model) == 128 && offsetof(AmcamFrameInfoV2, timestamp) == 16;
}
const char *amcam_device_display_name(const AmcamDeviceV2 *device) { return device ? device->displayname : NULL; }
const char *amcam_device_identifier(const AmcamDeviceV2 *device) { return device ? device->id : NULL; }
int amcam_model_resolution(const AmcamModelV2 *model, uint32_t index, uint32_t *width, uint32_t *height) {
    if (!model || !width || !height || index >= model->preview || index >= AMCAM_ABI_PREVIEW_RESOLUTION_COUNT) return 0;
    *width = model->res[index].width;
    *height = model->res[index].height;
    return 1;
}
