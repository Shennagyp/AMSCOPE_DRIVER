#ifndef AMCAM_ABI_H
#define AMCAM_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define AMCAM_ABI_PREVIEW_RESOLUTION_COUNT 16
typedef struct { uint32_t width; uint32_t height; } AmcamResolutionV2;
typedef struct {
    const char *name;
    uint64_t flag;
    uint32_t maxspeed;
    uint32_t preview;
    uint32_t still;
    uint32_t maxfanspeed;
    uint32_t ioctrol;
    float xpixsz;
    float ypixsz;
    AmcamResolutionV2 res[AMCAM_ABI_PREVIEW_RESOLUTION_COUNT];
} AmcamModelV2;
typedef struct {
    char displayname[64];
    char id[64];
    const AmcamModelV2 *model;
} AmcamDeviceV2;
typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t flag;
    uint32_t seq;
    uint64_t timestamp;
} AmcamFrameInfoV2;
int amcam_abi_layout_valid(void);
const char *amcam_device_display_name(const AmcamDeviceV2 *device);
const char *amcam_device_identifier(const AmcamDeviceV2 *device);
int amcam_model_resolution(const AmcamModelV2 *model, uint32_t index, uint32_t *width, uint32_t *height);
#ifdef __cplusplus
}
#endif
#endif
