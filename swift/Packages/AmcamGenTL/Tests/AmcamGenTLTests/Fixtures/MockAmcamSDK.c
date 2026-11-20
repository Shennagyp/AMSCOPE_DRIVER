#include "AmcamABI.h"
#include <stdint.h>
#include <string.h>

typedef void (*AmcamEventCallback)(uint32_t event, void *context);

static AmcamModelV2 model = {
    .name = "Mock AmScope Camera",
    .flag = 0x0000004000000000ULL,
    .maxspeed = 4,
    .preview = 3,
    .still = 0,
    .maxfanspeed = 0,
    .ioctrol = 0,
    .xpixsz = 2.4f,
    .ypixsz = 2.4f,
    .res = {{2560, 1922}, {1280, 960}, {640, 480}}
};

static AmcamEventCallback active_callback;
static void *active_context;
static uint32_t current_resolution_index = 2;
static const uint32_t resolution_widths[] = {2560, 1280, 640};
static const uint32_t resolution_heights[] = {1922, 960, 480};
static uint32_t close_count;
static uint32_t stop_count;
static uint32_t pull_count;
static int32_t auto_exposure = 1;
static int exposure_unavailable = 0;
static uint32_t exposure_time = 10000;
static int ignore_exposure_write = 0;
static uint16_t exposure_gain = 100;
static int ignore_exposure_gain_write = 0;
static int32_t white_balance_temperature = 6503;
static int32_t white_balance_tint = 1000;
static int32_t white_balance_rgb[3] = {100, 100, 100};
static int32_t precise_frame_rate_tenths = 150;

const char *Amcam_Version(void) { return "58.28273.20250415"; }

uint32_t Amcam_EnumV2(AmcamDeviceV2 *devices) {
    if (!devices) return 1;
    memset(devices, 0, sizeof(*devices));
    strcpy(devices[0].displayname, "Mock AmScope Camera");
    strcpy(devices[0].id, "MOCK-AMSCOP-001");
    devices[0].model = &model;
    return 1;
}

void *Amcam_Open(const char *identifier) {
    if (!identifier || strcmp(identifier, "MOCK-AMSCOP-001") != 0) return 0;
    return (void *)(uintptr_t)0x1234;
}

void Amcam_Close(void *handle) {
    if (handle) close_count++;
    active_callback = 0;
    active_context = 0;
}

int32_t Amcam_get_Size(void *handle, int32_t *width, int32_t *height) {
    if (!handle || !width || !height) return -1;
    *width = (int32_t)resolution_widths[current_resolution_index];
    *height = (int32_t)resolution_heights[current_resolution_index];
    return 0;
}

int32_t Amcam_put_eSize(void *handle, uint32_t index) {
    if (!handle || index >= 3) return -1;
    current_resolution_index = index;
    return 0;
}

int32_t Amcam_get_eSize(void *handle, uint32_t *index) {
    if (!handle || !index) return -1;
    *index = current_resolution_index;
    return 0;
}

int32_t Amcam_StartPullModeWithCallback(void *handle, AmcamEventCallback callback, void *context) {
    if (!handle || !callback || !context) return -1;
    active_callback = callback;
    active_context = context;
    callback(0x0004, context); /* Deliberately synchronous: validates start reentrancy. */
    return 0;
}

int32_t Amcam_PullImageV2(void *handle, void *buffer, int32_t bits, AmcamFrameInfoV2 *info) {
    if (!handle || !buffer || !info || bits != 24) return -1;
    const uint32_t width = resolution_widths[current_resolution_index];
    const uint32_t height = resolution_heights[current_resolution_index];
    const size_t size = (size_t)width * (size_t)height * 3u;
    memset(buffer, 0x5a, size);
    info->width = width;
    info->height = height;
    info->flag = 0x0003;
    info->seq = ++pull_count;
    info->timestamp = (int64_t)(123456789u + pull_count);
    return 0;
}

int32_t Amcam_Stop(void *handle) {
    if (!handle) return -1;
    stop_count++;
    active_callback = 0;
    active_context = 0;
    return 0;
}

void MockAmcam_SetExposureUnavailable(int32_t unavailable) {
    exposure_unavailable = unavailable != 0;
}
int32_t Amcam_get_AutoExpoEnable(void *handle, int32_t *value) {
    if (!handle || !value || exposure_unavailable) return -1;
    *value = auto_exposure;
    return 0;
}
int32_t Amcam_put_AutoExpoEnable(void *handle, int32_t value) {
    if (!handle || exposure_unavailable) return -1;
    if (value < 0 || value > 2) return -1;\n    auto_exposure = value;
    return 0;
}
int32_t Amcam_get_ExpoTime(void *handle, uint32_t *value) {
    if (!handle || !value || exposure_unavailable) return -1;
    *value = exposure_time;
    return 0;
}
int32_t Amcam_put_ExpoTime(void *handle, uint32_t value) {
    if (!handle || exposure_unavailable) return -1;
    if (!ignore_exposure_write) exposure_time = value;
    return 0;
}
int32_t Amcam_get_ExpTimeRange(void *handle, uint32_t *minimum, uint32_t *maximum, uint32_t *default_value) {
    if (!handle || !minimum || !maximum || !default_value || exposure_unavailable) return -1;
    *minimum = 100;
    *maximum = 1000000;
    *default_value = 10000;
    return 0;
}
int32_t Amcam_get_TempTint(void *handle, int32_t *temperature, int32_t *tint) {
    if (!handle || !temperature || !tint) return -1;
    *temperature = white_balance_temperature;
    *tint = white_balance_tint;
    return 0;
}
int32_t Amcam_put_TempTint(void *handle, int32_t temperature, int32_t tint) {
    if (!handle || temperature < 2000 || temperature > 15000 || tint < 200 || tint > 2500) return -1;
    white_balance_temperature = temperature;
    white_balance_tint = tint;
    return 0;
}
int32_t Amcam_get_WhiteBalanceGain(void *handle, int32_t *values) {
    if (!handle || !values) return -1;
    values[0] = white_balance_rgb[0];
    values[1] = white_balance_rgb[1];
    values[2] = white_balance_rgb[2];
    return 0;
}
int32_t Amcam_put_WhiteBalanceGain(void *handle, const int32_t *values) {
    if (!handle || !values) return -1;
    white_balance_rgb[0] = values[0];
    white_balance_rgb[1] = values[1];
    white_balance_rgb[2] = values[2];
    return 0;
}
int32_t Amcam_get_ExpoAGain(void *handle, uint16_t *value) {
    if (!handle || !value) return -1;
    *value = exposure_gain;
    return 0;
}
int32_t Amcam_put_ExpoAGain(void *handle, uint16_t value) {
    if (!handle) return -1;
    if (value < 100 || value > 800) return -1;
    if (!ignore_exposure_gain_write) exposure_gain = value;
    return 0;
}
void MockAmcam_SetIgnoreExposureGainWrite(int32_t enabled) {
    ignore_exposure_gain_write = enabled != 0;
}
int32_t Amcam_get_ExpoAGainRange(void *handle, uint16_t *minimum, uint16_t *maximum, uint16_t *default_value) {
    if (!handle || !minimum || !maximum || !default_value) return -1;
    *minimum = 100;
    *maximum = 800;
    *default_value = 100;
    return 0;
}

int32_t Amcam_get_Option(void *handle, uint32_t option, int32_t *value) {
    if (!handle || !value) return -1;
    if (option == 0x0d) *value = 1;
    else if (option == 0x1a) *value = 0;
    else if (option == 0x32) *value = 1;
    else if (option == 0x2c) *value = 300;
    else if (option == 0x2d) *value = precise_frame_rate_tenths;
    else return -1;
    return 0;
}
int32_t Amcam_put_Option(void *handle, uint32_t option, int32_t value) {
    if (!handle) return -1;
    if (option == 0x2d && value >= 1 && value <= 300) {
        precise_frame_rate_tenths = value;
        return 0;
    }
    return -1;
}

void MockAmcam_Reset(void) {
    close_count = 0;
    stop_count = 0;
    pull_count = 0;
    current_resolution_index = 2;
    active_callback = 0;
    active_context = 0;
    auto_exposure = 1;
    exposure_time = 10000;
    ignore_exposure_write = 0;
    precise_frame_rate_tenths = 150;
}
void MockAmcam_SetIgnoreExposureWrite(int32_t enabled) {
    ignore_exposure_write = enabled != 0;
}
uint32_t MockAmcam_CloseCount(void) { return close_count; }
uint32_t MockAmcam_StopCount(void) { return stop_count; }
uint32_t MockAmcam_PullCount(void) { return pull_count; }
void MockAmcam_EmitEvent(uint32_t event) {
    if (active_callback) active_callback(event, active_context);
}
