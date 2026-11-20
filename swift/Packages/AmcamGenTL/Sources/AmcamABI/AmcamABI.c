#include "AmcamABI.h"
#include <string.h>

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
_Static_assert(sizeof(AmcamFrameInfoV3) == 40, "AmcamFrameInfoV3 ABI mismatch");
_Static_assert(offsetof(AmcamFrameInfoV3, shutterseq) == 24, "AmcamFrameInfoV3.shutterseq offset mismatch");
_Static_assert(sizeof(AmcamGps) == 32, "AmcamGps ABI mismatch");
_Static_assert(sizeof(AmcamFrameInfoV4) == 104, "AmcamFrameInfoV4 ABI mismatch");
_Static_assert(offsetof(AmcamFrameInfoV4, uFV) == 48, "AmcamFrameInfoV4.uFV offset mismatch");
_Static_assert(offsetof(AmcamFrameInfoV4, timecount) == 56, "AmcamFrameInfoV4.timecount offset mismatch");
_Static_assert(offsetof(AmcamFrameInfoV4, gps) == 72, "AmcamFrameInfoV4.gps offset mismatch");

int amcam_abi_layout_valid(void) {
    return sizeof(AmcamResolutionV2) == 8 && sizeof(AmcamModelV2) == 176 &&
           sizeof(AmcamDeviceV2) == 136 && sizeof(AmcamFrameInfoV2) == 24 &&
           sizeof(AmcamFrameInfoV3) == 40 && sizeof(AmcamGps) == 32 && sizeof(AmcamFrameInfoV4) == 104 &&
           offsetof(AmcamDeviceV2, model) == 128 && offsetof(AmcamFrameInfoV2, timestamp) == 16;
}

static int copy_fixed_string(
    const char *source,
    size_t source_capacity,
    char *destination,
    size_t destination_capacity
) {
    if (!source || !destination || destination_capacity == 0) return 0;
    const char *terminator = (const char *)memchr(source, '\0', source_capacity);
    if (!terminator) return 0;

    const size_t length = (size_t)(terminator - source);
    if (length >= destination_capacity) return 0;

    memcpy(destination, source, length);
    destination[length] = '\0';
    return 1;
}

int amcam_device_copy_display_name(
    const AmcamDeviceV2 *device,
    char *destination,
    size_t capacity
) {
    return device
        ? copy_fixed_string(device->displayname, sizeof(device->displayname), destination, capacity)
        : 0;
}

int amcam_device_copy_identifier(
    const AmcamDeviceV2 *device,
    char *destination,
    size_t capacity
) {
    return device
        ? copy_fixed_string(device->id, sizeof(device->id), destination, capacity)
        : 0;
}

int amcam_model_resolution(
    const AmcamModelV2 *model,
    uint32_t index,
    uint32_t *width,
    uint32_t *height
) {
    if (!model || !width || !height ||
        index >= model->preview ||
        index >= AMCAM_ABI_PREVIEW_RESOLUTION_COUNT) {
        return 0;
    }

    *width = model->res[index].width;
    *height = model->res[index].height;
    return 1;
}
