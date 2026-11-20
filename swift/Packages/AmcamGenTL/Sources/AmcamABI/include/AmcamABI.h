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
    int64_t timestamp;
} AmcamFrameInfoV2;
typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t flag;
    uint32_t seq;
    int64_t timestamp;
    uint32_t shutterseq;
    uint32_t expotime;
    uint16_t expogain;
    uint16_t blacklevel;
} AmcamFrameInfoV3;
typedef struct {
    int64_t utcstart;
    int64_t utcend;
    int32_t longitude;
    int32_t latitude;
    int32_t altitude;
    uint16_t satellite;
    uint16_t reserved;
} AmcamGps;
typedef struct {
    AmcamFrameInfoV3 v3;
    uint32_t reserved;
    uint32_t uLum;
    uint32_t uFV;
    uint32_t timecount;
    uint32_t framecount;
    uint32_t tricount;
    AmcamGps gps;
} AmcamFrameInfoV4;
int amcam_abi_layout_valid(void);
int amcam_device_copy_display_name(const AmcamDeviceV2 *device, char *destination, size_t capacity);
int amcam_device_copy_identifier(const AmcamDeviceV2 *device, char *destination, size_t capacity);
int amcam_model_resolution(const AmcamModelV2 *model, uint32_t index, uint32_t *width, uint32_t *height);
#ifdef __cplusplus
}
#endif
#endif
