# AmScope camera acquisition profiles

The application keeps acquisition compatibility policy separate from camera-control
capability profiles.

On macOS, the application reads:

`~/Library/Application Support/AmcamImaging/camera-profiles.json`

for feature allow/deny policy, and:

`~/Library/Application Support/AmcamImaging/camera-acquisition-profiles.json`

for native acquisition API selection.

## MU503 vendor sample

The MU503-supplied Python sample uses:

```python
PullImageV4(buffer, 0, 24, 0, None)
```

This requests a live RGB24 frame, with the SDK's default row pitch, and does not
request frame metadata. The Swift implementation follows the same V4 arguments
(`still = 0`, `bits = 24`, `rowPitch = 0`) but supplies an
`AmcamFrameInfoV4` output structure because the runtime uses the returned
dimensions, sequence, timestamp, and optional metadata.

The default `automatic` policy already tries V4 first. It proceeds to another
API generation only when the current API explicitly returns `E_NOTIMPL`.
The vendor sample demonstrates V4; it does not establish that V2 is unsupported.
A V2 override should therefore be used only when the exact camera/model behavior
has been verified to require it.

## Explicit model policy

An exact model descriptor can pin the legacy pull API without changing camera
feature availability:

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

- `automatic`: prefer V4, then V3, row-pitch V2, and plain V2. Move to the
  next API only when the current API returns `E_NOTIMPL`.
- `v2`: use only `Amcam_PullImageV2`; do not fall back to V3, V4, or the
  row-pitch V2 entry point.

Plain `PullImageV2` uses the existing DWORD-aligned RGB24 row layout. The
profile changes API selection only; it does not change pixel format, row pitch,
buffer capacity, or camera-control availability.

After editing the file, restart the application so the profile registry is
reloaded. A successful mock/CI test validates policy dispatch, not physical
camera compatibility; confirm continuous frames and stop/restart on the actual
camera before treating the hardware path as verified.
