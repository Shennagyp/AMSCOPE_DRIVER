# AmScope camera acquisition profiles

The application keeps acquisition compatibility policy separate from camera-control
capability profiles.

On macOS, the application reads:

`~/Library/Application Support/AmcamImaging/camera-profiles.json`

for feature allow/deny policy, and:

`~/Library/Application Support/AmcamImaging/camera-acquisition-profiles.json`

for native acquisition API selection.

The acquisition file is a JSON array. An exact model descriptor can pin the
legacy pull API without changing its feature availability:

```json
[
  {
    "modelCode": "EXACT DEVICE_INFO_MODEL VALUE",
    "pullImageAPIPolicy": "v2"
  }
]
```

Replace the placeholder with the exact model string reported by the Amcam SDK
for the connected camera. Do not use a display-name guess or a substring match.
If the model has no matching acquisition profile, the SDK keeps its automatic
API-generation preference and its existing `E_NOTIMPL` fallback behavior.

Supported values:

- `automatic`: use the SDK's existing newest-available API selection.
- `v2`: use only `Amcam_PullImageV2`; do not fall back to V3, V4, or the
  row-pitch V2 entry point.

Plain `PullImageV2` uses the existing DWORD-aligned RGB24 row layout. The
profile changes API selection only; it does not change pixel format, row pitch,
buffer capacity, or camera-control availability.

After editing the file, restart the application so the profile registry is
reloaded. A successful mock/CI test validates policy dispatch, not physical
camera compatibility; confirm continuous frames and stop/restart on the actual
camera before treating the hardware path as verified.
