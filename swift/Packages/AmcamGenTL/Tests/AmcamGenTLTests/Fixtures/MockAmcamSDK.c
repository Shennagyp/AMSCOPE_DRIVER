#define _POSIX_C_SOURCE 200809L
#include "AmcamABI.h"
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <pthread.h>

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
    .res = {{2560, 1922}, {1280, 960}, {640, 480}, {0, 0}}
};

static AmcamEventCallback active_callback;
static void *active_context;
static pthread_mutex_t callback_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_t callback_worker;
static int callback_worker_started;
static int callback_worker_stop;
static uint32_t automatic_frame_interval_milliseconds;
static uint32_t asynchronous_callback_count;
static uint32_t current_resolution_index = 2;
static const uint32_t resolution_widths[] = {2560, 1280, 640, 641};
static const uint32_t resolution_heights[] = {1922, 960, 480, 480};
static uint32_t close_count;
static uint32_t active_sdk_call_count;
static uint32_t concurrent_sdk_call_count;
static uint32_t pull_delay_milliseconds;
static uint32_t control_delay_milliseconds;
static uint32_t stop_count;
static uint32_t frame_cache_flush_count;
static uint32_t frame_cache_flush_failures_remaining;
static int frame_cache_flush_required;
static uint32_t pull_count;
static uint32_t pull_api_version;
static uint32_t unsupported_pull_api_mask;
static int32_t pull_api_failure;
static uint32_t pending_pull_count;
static uint32_t mock_v4_frame_flags = UINT32_C(0x000103ff);
static int32_t auto_exposure = 1;
static int exposure_unavailable = 0;
static int exposure_range_unavailable = 0;
static uint32_t exposure_time = 10000;
static int ignore_exposure_write = 0;
static uint16_t exposure_gain = 100;
static int ignore_exposure_gain_write = 0;
static int32_t white_balance_temperature = 6503;
static int32_t white_balance_tint = 1000;
static int32_t white_balance_rgb[3] = {100, 100, 100};
static int32_t precise_frame_rate_tenths = 150;
static int32_t color_matrix_enabled = 1;
static int32_t pixel_format_code = 8;

static void mock_begin_sdk_call(void) {
    uint32_t active = __atomic_add_fetch(&active_sdk_call_count, 1, __ATOMIC_SEQ_CST);
    if (active > 1) {
        __atomic_add_fetch(&concurrent_sdk_call_count, 1, __ATOMIC_SEQ_CST);
    }
}

static void mock_end_sdk_call(void) {
    __atomic_sub_fetch(&active_sdk_call_count, 1, __ATOMIC_SEQ_CST);
}

static void mock_delay(uint32_t milliseconds) {
    if (milliseconds == 0) return;
    struct timespec delay = {
        .tv_sec = (time_t)(milliseconds / 1000),
        .tv_nsec = (long)(milliseconds % 1000) * 1000000L
    };
    (void)nanosleep(&delay, NULL);
}

static void *mock_callback_worker_main(void *unused) {
    (void)unused;
    for (;;) {
        pthread_mutex_lock(&callback_mutex);
        int should_stop = callback_worker_stop;
        AmcamEventCallback callback = active_callback;
        void *context = active_context;
        uint32_t interval = __atomic_load_n(
            &automatic_frame_interval_milliseconds,
            __ATOMIC_SEQ_CST
        );
        pthread_mutex_unlock(&callback_mutex);

        if (should_stop || !callback || interval == 0) break;
        mock_delay(interval);

        pthread_mutex_lock(&callback_mutex);
        should_stop = callback_worker_stop;
        callback = active_callback;
        context = active_context;
        pthread_mutex_unlock(&callback_mutex);

        if (should_stop || !callback) break;
        callback(0x0004, context);
        __atomic_add_fetch(&asynchronous_callback_count, 1, __ATOMIC_SEQ_CST);
    }
    return NULL;
}

static void mock_stop_callback_worker(void) {
    pthread_mutex_lock(&callback_mutex);
    int join_worker = callback_worker_started;
    callback_worker_stop = 1;
    pthread_mutex_unlock(&callback_mutex);

    if (join_worker && !pthread_equal(pthread_self(), callback_worker)) {
        (void)pthread_join(callback_worker, NULL);
    }

    pthread_mutex_lock(&callback_mutex);
    callback_worker_started = 0;
    active_callback = NULL;
    active_context = NULL;
    pthread_mutex_unlock(&callback_mutex);
}

void MockAmcam_EnableOddResolution(void) {
    model.preview = 4;
    model.res[3].width = 641;
    model.res[3].height = 480;
}

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
    mock_stop_callback_worker();
}

int32_t Amcam_get_Size(void *handle, int32_t *width, int32_t *height) {
    if (!handle || !width || !height) return -1;
    *width = (int32_t)resolution_widths[current_resolution_index];
    *height = (int32_t)resolution_heights[current_resolution_index];
    return 0;
}

int32_t Amcam_put_eSize(void *handle, uint32_t index) {
    if (!handle || index >= 4) return -1;
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
    /* Model the vendor's retained DDR/DLL frame queue after Amcam_Stop. */
    if (frame_cache_flush_required) return (int32_t)UINT32_C(0x80004005);

    pthread_mutex_lock(&callback_mutex);
    if (callback_worker_started) {
        pthread_mutex_unlock(&callback_mutex);
        return -1;
    }
    callback_worker_stop = 0;
    active_callback = callback;
    active_context = context;
    pthread_mutex_unlock(&callback_mutex);

    callback(0x0004, context); /* Deliberately synchronous: validates start reentrancy. */

    uint32_t interval = __atomic_load_n(
        &automatic_frame_interval_milliseconds,
        __ATOMIC_SEQ_CST
    );
    if (interval > 0) {
        pthread_mutex_lock(&callback_mutex);
        int create_result = pthread_create(
            &callback_worker,
            NULL,
            mock_callback_worker_main,
            NULL
        );
        if (create_result == 0) {
            callback_worker_started = 1;
        } else {
            active_callback = NULL;
            active_context = NULL;
            callback_worker_stop = 1;
        }
        pthread_mutex_unlock(&callback_mutex);
        if (create_result != 0) return -1;
    }
    return 0;
}

int32_t Amcam_PullImageV2(void *handle, void *buffer, int32_t bits, AmcamFrameInfoV2 *info) {
    if ((unsupported_pull_api_mask & (UINT32_C(1) << 1)) != 0) return (int32_t)UINT32_C(0x80004001);
    if (!handle || !buffer || !info || bits != 24) return -1;
    const uint32_t width = resolution_widths[current_resolution_index];
    const uint32_t height = resolution_heights[current_resolution_index];
    const size_t packed_row_bytes = (size_t)width * 3u;
    const size_t default_row_bytes = (packed_row_bytes + 3u) & ~(size_t)3u;
    const size_t size = default_row_bytes * (size_t)height;
    memset(buffer, 0x5a, size);
    info->width = width;
    info->height = height;
    info->flag = 0x0003;
    info->seq = ++pull_count;
    info->timestamp = (int64_t)(123456789u + pull_count);
    pull_api_version = 1;
    return 0;
}

#if !defined(MOCK_DISABLE_ROW_PITCH_V2)
int32_t Amcam_PullImageWithRowPitchV2(void *handle, void *buffer, int32_t bits, int32_t row_pitch, AmcamFrameInfoV2 *info) {
    if ((unsupported_pull_api_mask & (UINT32_C(1) << 2)) != 0) return (int32_t)UINT32_C(0x80004001);
    if (!handle || !buffer || !info || bits != 24 || row_pitch != -1) return -1;
    const uint32_t width = resolution_widths[current_resolution_index];
    const uint32_t height = resolution_heights[current_resolution_index];
    memset(buffer, 0x5a, (size_t)width * (size_t)height * 3u);
    info->width = width;
    info->height = height;
    info->flag = 0x0003;
    info->seq = ++pull_count;
    info->timestamp = (int64_t)(123456789u + pull_count);
    pull_api_version = 2;
    return 0;
}
#endif

#if !defined(MOCK_DISABLE_V3)
int32_t Amcam_PullImageV3(void *handle, void *buffer, int32_t still, int32_t bits, int32_t row_pitch, AmcamFrameInfoV3 *info) {
    if ((unsupported_pull_api_mask & (UINT32_C(1) << 3)) != 0) return (int32_t)UINT32_C(0x80004001);
    if (!handle || !buffer || !info || still != 0 || bits != 24 || row_pitch != -1) return -1;
    const uint32_t width = resolution_widths[current_resolution_index];
    const uint32_t height = resolution_heights[current_resolution_index];
    memset(buffer, 0x5a, (size_t)width * (size_t)height * 3u);
    info->width = width;
    info->height = height;
    info->flag = 0x003f;
    info->seq = ++pull_count;
    info->timestamp = (int64_t)(123456789u + pull_count);
    info->shutterseq = 7;
    info->expotime = 10000;
    info->expogain = 100;
    info->blacklevel = 0;
    pull_api_version = 3;
    return 0;
}

#endif

#if !defined(MOCK_DISABLE_V4)
int32_t Amcam_PullImageV4(void *handle, void *buffer, int32_t still, int32_t bits, int32_t row_pitch, AmcamFrameInfoV4 *info) {
    if (pull_api_failure != 0) return pull_api_failure;
    if ((unsupported_pull_api_mask & (UINT32_C(1) << 4)) != 0) return (int32_t)UINT32_C(0x80004001);
    if (!handle || !buffer || !info || still != 0 || bits != 24 || row_pitch != 0) return -1;
    mock_begin_sdk_call();
    mock_delay(__atomic_load_n(&pull_delay_milliseconds, __ATOMIC_SEQ_CST));
    if (pending_pull_count > 0) {
        pending_pull_count--;
        mock_end_sdk_call();
        return (int32_t)UINT32_C(0x8000000a);
    }
    const uint32_t width = resolution_widths[current_resolution_index];
    const uint32_t height = resolution_heights[current_resolution_index];
    const size_t packed_row_bytes = (size_t)width * 3u;
    const size_t default_row_bytes = (packed_row_bytes + 3u) & ~(size_t)3u;
    memset(buffer, 0x5a, default_row_bytes * (size_t)height);
    info->v3.width = width;
    info->v3.height = height;
    info->v3.flag = mock_v4_frame_flags;
    info->v3.seq = ++pull_count;
    info->v3.timestamp = (int64_t)(123456789u + pull_count);
    info->v3.shutterseq = 7;
    info->v3.expotime = 10000;
    info->v3.expogain = 125;
    info->v3.blacklevel = 16;
    info->uLum = 123;
    info->uFV = INT64_C(0x100000001);
    info->timecount = INT64_C(0x200000002);
    info->framecount = 12;
    info->tricount = 13;
    info->gps.utcstart = INT64_C(1700000000000000000);
    info->gps.utcend = INT64_C(1700000000001000000);
    info->gps.longitude = 31200000;
    info->gps.latitude = 30000000;
    info->gps.altitude = 45600;
    info->gps.satellite = 8;
    pull_api_version = 4;
    mock_end_sdk_call();
    return 0;
}
#endif

uint32_t MockAmcam_PullAPIVersion(void) { return pull_api_version; }
void MockAmcam_SetUnsupportedPullAPIVersion(uint32_t version) { unsupported_pull_api_mask = version <= 4 ? (UINT32_C(1) << version) : 0; }
void MockAmcam_SetUnsupportedPullAPIMask(uint32_t mask) { unsupported_pull_api_mask = mask; }
void MockAmcam_SetPullFailure(int32_t result) { pull_api_failure = result; }
void MockAmcam_SetPendingPullCount(uint32_t count) { pending_pull_count = count; }
void MockAmcam_SetV4FrameFlags(uint32_t flags) { mock_v4_frame_flags = flags; }

int32_t Amcam_Stop(void *handle) {
    if (!handle) return -1;
    stop_count++;
    frame_cache_flush_required = 1;
    mock_stop_callback_worker();
    return 0;
}

void MockAmcam_SetExposureUnavailable(int32_t unavailable) {
    exposure_unavailable = unavailable != 0;
}
int32_t Amcam_get_AutoExpoEnable(void *handle, int32_t *value) {
    if (!handle || !value || exposure_unavailable) return -1;
    mock_begin_sdk_call();
    mock_delay(__atomic_load_n(&control_delay_milliseconds, __ATOMIC_SEQ_CST));
    *value = auto_exposure;
    mock_end_sdk_call();
    return 0;
}
int32_t Amcam_put_AutoExpoEnable(void *handle, int32_t value) {
    if (!handle || exposure_unavailable) return -1;
    if (value < 0 || value > 2) return -1;
    auto_exposure = value;
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
void MockAmcam_SetExposureRangeUnavailable(int32_t unavailable) {
    exposure_range_unavailable = unavailable != 0;
}
int32_t Amcam_get_ExpTimeRange(void *handle, uint32_t *minimum, uint32_t *maximum, uint32_t *default_value) {
    if (!handle || !minimum || !maximum || !default_value || exposure_unavailable || exposure_range_unavailable) return -1;
    *minimum = 100;
    *maximum = 1000000;
    *default_value = 10000;
    return 0;
}
int32_t Amcam_get_PixelFormatSupport(void *handle, uint32_t index, int32_t *value) {
    if (!handle || !value) return -1;
    if (index == 0xff) *value = 2;
    else if (index == 0) *value = 0;
    else if (index == 1) *value = 8;
    else return -1;
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
    if (option == 0x0d) *value = color_matrix_enabled;
    else if (option == 0x1a) *value = pixel_format_code;
    else if (option == 0x32) *value = 1;
    else if (option == 0x2c) *value = 300;
    else if (option == 0x2d) *value = precise_frame_rate_tenths;
    else return -1;
    return 0;
}
int32_t Amcam_put_Option(void *handle, uint32_t option, int32_t value) {
    if (!handle) return -1;
    if (option == 0x3d && value == 3) {
        if (frame_cache_flush_failures_remaining > 0) {
            frame_cache_flush_failures_remaining--;
            return -1;
        }
        frame_cache_flush_required = 0;
        frame_cache_flush_count++;
        return 0;
    }
    if (option == 0x0d && (value == 0 || value == 1)) {
        color_matrix_enabled = value;
        return 0;
    }
    if (option == 0x1a && (value == 8 || value == 0)) {
        pixel_format_code = value;
        return 0;
    }
    if (option == 0x2d && value >= 1 && value <= 300) {
        precise_frame_rate_tenths = value;
        return 0;
    }
    return -1;
}

void MockAmcam_Reset(void) {
    close_count = 0;
    __atomic_store_n(&active_sdk_call_count, 0, __ATOMIC_SEQ_CST);
    __atomic_store_n(&concurrent_sdk_call_count, 0, __ATOMIC_SEQ_CST);
    __atomic_store_n(&pull_delay_milliseconds, 0, __ATOMIC_SEQ_CST);
    __atomic_store_n(&control_delay_milliseconds, 0, __ATOMIC_SEQ_CST);
    stop_count = 0;
    frame_cache_flush_count = 0;
    frame_cache_flush_failures_remaining = 0;
    frame_cache_flush_required = 0;
    pull_count = 0;
    pull_api_version = 0;
    unsupported_pull_api_mask = 0;
    pull_api_failure = 0;
    pending_pull_count = 0;
    mock_v4_frame_flags = UINT32_C(0x000103ff);
    current_resolution_index = 2;
    mock_stop_callback_worker();
    __atomic_store_n(&automatic_frame_interval_milliseconds, 0, __ATOMIC_SEQ_CST);
    __atomic_store_n(&asynchronous_callback_count, 0, __ATOMIC_SEQ_CST);
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
uint32_t MockAmcam_FlushCount(void) { return frame_cache_flush_count; }
void MockAmcam_SetFlushFailures(uint32_t count) { frame_cache_flush_failures_remaining = count; }
uint32_t MockAmcam_PullCount(void) { return pull_count; }
void MockAmcam_SetCallDelays(uint32_t pullMilliseconds, uint32_t controlMilliseconds) {
    __atomic_store_n(&pull_delay_milliseconds, pullMilliseconds, __ATOMIC_SEQ_CST);
    __atomic_store_n(&control_delay_milliseconds, controlMilliseconds, __ATOMIC_SEQ_CST);
}
uint32_t MockAmcam_ActiveSDKCallCount(void) {
    return __atomic_load_n(&active_sdk_call_count, __ATOMIC_SEQ_CST);
}
uint32_t MockAmcam_ConcurrentSDKCallCount(void) {
    return __atomic_load_n(&concurrent_sdk_call_count, __ATOMIC_SEQ_CST);
}
void MockAmcam_EmitEvent(uint32_t event) {
    pthread_mutex_lock(&callback_mutex);
    AmcamEventCallback callback = active_callback;
    void *context = active_context;
    pthread_mutex_unlock(&callback_mutex);
    if (callback) callback(event, context);
}
void MockAmcam_SetAutomaticFrameInterval(uint32_t milliseconds) {
    __atomic_store_n(&automatic_frame_interval_milliseconds, milliseconds, __ATOMIC_SEQ_CST);
}
uint32_t MockAmcam_AsynchronousCallbackCount(void) {
    return __atomic_load_n(&asynchronous_callback_count, __ATOMIC_SEQ_CST);
}
