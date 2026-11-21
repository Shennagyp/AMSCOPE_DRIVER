# Amcam Imaging — macOS application

## Objective

A native macOS camera application built on the Amcam SDK backend in this repository. The main window is a full-screen-capable live image surface. A hardware dock provides camera selection, refresh, start, stop, settings, and full-screen controls. Vendor SDK discovery and loading are library responsibilities; the UI does not select SDK files. Camera settings are presented in a separate native window.

The application consumes backend-neutral camera models, feature contracts, lifecycle events and frame values. GenTLRouter owns generic backend registration and discovery. AmcamImagingGenTLAdapter owns AmScope provider registration, discovery mapping, and conversion between GenTL-specific sessions/features and the portable runtime contracts. AmcamImagingRuntime exclusively owns the opened device session, acquisition lifecycle, feature I/O serialization, frame delivery and cleanup. The app sends commands to that runtime and consumes its events and frames; GenTL handles never escape the runtime actor.

**Current application architecture:** CameraApplicationModel discovers candidates through AmcamCameraProvider, opens the selected opaque runtime device through CameraSessionLifecycle, and performs typed feature reads/writes through that same lifecycle. The app depends on AmcamCameraModel, AmcamImagingCore, AmcamImagingRuntime, AmcamImagingGenTLAdapter and AmcamImagingState. It does not import GenTLABI, GenTLAPI, GenTLRouter or AmcamGenTL, and it does not construct AmcamCameraDriver, AmcamCameraSession or GenTLDeviceSession. CI enforces this dependency boundary.

## Architecture

- **GenTLAPI** is the GenTL 1.6 protocol contract used by backend implementations and the router; it is not imported by the app.
- **GenTLRouter** registers backends and performs generic device discovery.
- **AmcamImagingGenTLAdapter** registers the AmScope backend with GenTLRouter, creates opaque runtime-device candidates, and adapts GenTL feature/acquisition types to backend-neutral runtime values.
- **AmcamImagingRuntime** exclusively owns device sessions and acquisition resources. Its FIFO operation gate serializes open/start/stop/close and feature reads/writes; failed cleanup retains handles for retry.
- **AmcamImagingState** builds camera control snapshots and current-resolution state from feature descriptors and typed readbacks, without GenTL or AppKit dependencies.
- **AmcamCameraModel** owns camera model values, feature groups, model profiles and hardware-evidence capability policy.
- **AmcamGenTL** owns AmScope SDK loading, symbol resolution and vendor-specific SDK behavior behind the adapter.
- **AmcamImagingApp** owns the native macOS AppKit interface and translates validated backend-neutral RGB8 frames to display images.
- **amcam-camera-probe** remains a diagnostic executable; **amcam-imaging** is the user-facing application.

Camera identity is deliberately separated:
- The SDK device identifier is transient and is used only to open the currently enumerated device.
- The model code is the model descriptor name returned by Amcam_EnumV2; it is the profile key.
- A serial number is a separate persistent camera identity and is not substituted for the model code.

## Capability resolution

A control is not exposed just because a function exists in libamcam.dylib.

1. **Model flags:** the 64-bit AmcamModelV2.flag field declares hardware features.
2. **Runtime probes:** for capabilities without a dedicated model flag, the application performs read-only SDK queries. Failed or unconfirmed probes do not become available settings.
3. **Model profile:** an exact model-code allow-list and deny-list can further restrict the result. A profile cannot enable a feature the hardware did not advertise or a read-only probe did not confirm.
4. **Implementation coverage:** the UI distinguishes camera support from whether the application backend has implemented the control. Hardware-supported but not-yet-integrated features are visible as pending, not presented as working controls.

The feature groups are Capture, Exposure & Gain, Frame Rate, Image, Trigger, Focus, Cooling & Temperature, Calibration, and Accessories.

The feature flag values below are taken from the supplied amcam.py version 58.28273.20250415:

| Feature | Model flag |
|---|---:|
| CMOS sensor | 0x00000001 |
| Progressive CCD | 0x00000002 |
| Interlaced CCD | 0x00000004 |
| Hardware ROI | 0x00000008 |
| Monochrome | 0x00000010 |
| Binning / skipping | 0x00000020 |
| USB 3 | 0x00000040 |
| TEC present | 0x00000080 |
| USB 3 camera connected through USB 2 | 0x00000100 |
| ST4 port | 0x00000200 |
| Sensor temperature | 0x00000400 |
| High full-well capacity | 0x00000800 |
| RAW 10 | 0x00001000 |
| RAW 12 | 0x00002000 |
| RAW 14 | 0x00004000 |
| RAW 16 | 0x00008000 |
| Cooling fan | 0x00010000 |
| TEC on/off and target control | 0x00020000 |
| ISP chip | 0x00040000 |
| Software trigger | 0x00080000 |
| External trigger | 0x00100000 |
| Single-trigger mode | 0x00200000 |
| Black level | 0x00400000 |
| Auto focus | 0x00800000 |
| Frame buffer | 0x01000000 |
| DDR frame buffer | 0x02000000 |
| Conversion gain (HCG/LCG) | 0x04000000 |
| YUV 411 | 0x08000000 |
| VUYY | 0x10000000 |
| YUV 444 | 0x20000000 |
| RGB 888 | 0x40000000 |
| RAW 8 | 0x80000000 |
| GMCY 8 | 0x0000000100000000 |
| GMCY 12 | 0x0000000200000000 |
| UYVY | 0x0000000400000000 |
| Conversion gain HDR | 0x0000000800000000 |
| Global shutter | 0x0000001000000000 |
| Focus motor | 0x0000002000000000 |
| Precise frame rate | 0x0000004000000000 |
| Anti-fog heat | 0x0000008000000000 |
| Low-noise mode | 0x0000010000000000 |
| Hardware level range | 0x0000020000000000 |
| Hardware events | 0x0000040000000000 |
| Embedded light source | 0x0000080000000000 |
| Filter wheel | 0x0000100000000000 |
| GigE | 0x0000200000000000 |
| 10 GigE | 0x0000400000000000 |
| 5 GigE | 0x0000800000000000 |
| 2.5 GigE | 0x0001000000000000 |
| Astro auto-focuser | 0x0002000000000000 |
| Standalone light source | 0x0004000000000000 |
| Camera Link | 0x0008000000000000 |
| CoaXPress | 0x0010000000000000 |
| RAW 12 packed | 0x0020000000000000 |
| Self trigger | 0x0040000000000000 |
| RAW 11 | 0x0080000000000000 |
| GHOPTO sensor | 0x0100000000000000 |

Exposure, analog gain, white balance, and some image controls do not have a dedicated model flag in this descriptor. They must be confirmed by successful SDK probes or feature-specific range queries. The app must not infer their support from the camera family name.

## Fixed exposure semantics

The Amcam API uses a three-state Amcam_put_AutoExpoEnable value:

- 0: manual / fixed exposure
- 1: continuous auto exposure
- 2: one-shot auto exposure

The SDK wrapper now preserves all three values instead of collapsing every nonzero value into a Boolean. Fixed exposure is available when the camera's auto-exposure mode and exposure range/readback queries succeed. The exposure-time slider is enabled only in manual mode. A setter is accepted only after the SDK confirms manual mode and the requested microsecond value is read back exactly.

This is distinct from analog gain. Gain is a separate control with its own API and range query; it must not be inferred from exposure support. The Swift implementation loads gain functions as optional symbols, requires the complete get/set/range API, probes the current camera, validates the model-reported range, and verifies exact readback after a write. The mock integration suite also injects a successful-but-ignored gain write and requires a readback-mismatch error.

White balance is also independent of exposure and gain. The app probes temperature/tint and RGB channel gains separately and exposes only descriptors confirmed available by the backend. Temperature and tint editors use the numeric ranges supplied by the active camera feature descriptors; they are not shown as editable when a writable range is unavailable. RGB gains are sent as exactly three integer values and accepted only after exact readback; the SDK does not publish a numeric range for those values, so none is invented. All settings controls are hidden until a camera snapshot is available, are filtered by current feature availability and writability, and refresh when the selected camera or descriptor state changes. Enumeration pickers are populated from the camera's advertised values rather than a fixed UI list.

## Model profile configuration

The app reads optional model profiles from:

~/Library/Application Support/AmcamImaging/camera-profiles.json

On first launch it creates an empty array. A profile uses the exact model descriptor name shown by the app, not the transient device ID:

~~~json
[
  {
    "modelCode": "EXACT MODEL NAME FROM SDK",
    "displayName": "Friendly camera name",
    "allowedFeaturesByGroup": {
      "capture": ["liveCapture", "resolution"],
      "exposureAndGain": ["exposureAuto", "exposureManual"],
      "frameRate": ["preciseFrameRate"]
    },
    "deniedFeatures": []
  }
]
~~~

The allowedFeaturesByGroup object is a deliberate allow-list. Any feature omitted from a configured model profile is hidden from that model's available feature set. deniedFeatures is an explicit deny-list that takes precedence over the allow-list.

Do not add a model profile until the exact SDK model descriptor name and the hardware feature flags have been observed. A profile is policy, not a replacement for runtime evidence.

## Current implementation boundary

The routed application currently provides:
- device discovery through AmcamCameraProvider and GenTLRouter;
- device opening, acquisition start/stop, frame delivery and ordered cleanup through CameraSessionLifecycle;
- a bounded announced-buffer pool, copy-before-requeue semantics, and ordered stop/flush/revoke/close cleanup;
- RGB8 (PFNC format 0x02180014, namespace 4) display with row-padding and payload-size validation;
- ExposureAuto (Off, Once, Continuous), ExposureTime (microseconds), and AmcamAnalogGainPercent (percentage);
- AmcamColorMatrixEnabled (boolean) and AmcamPixelFormat (enumeration from the camera's SDK-reported supported-format list);
- AmcamWhiteBalanceTemperature (K), AmcamWhiteBalanceTint, and AmcamWhiteBalanceRGBGain (three-element integer vector);
- AmcamFixedFrameRate (floating-point FPS with 0.1 FPS increments) and AmcamFrameSpeedLevel (integer discrete level);
- AmcamResolutionIndex, whose enumeration values preserve the SDK's exact resolution index and dimensions;
- model-specific availability and dynamic access state derived from model flags, non-mutating SDK probes and the selected model profile;
- SDK setter range checks and readback verification for writable controls, with writes denied when the active model profile disallows the feature.

Feature descriptors are generated for the opened camera. A feature is not considered usable merely because the SDK exports a function: model capability, runtime probe, implementation coverage and model-profile policy must all agree. Features that are unsupported by the specific camera are reported unavailable. Pixel format and resolution are writable only while acquisition is stopped. RGB white-balance uses a fixed three-element vector; the SDK wrapper verifies the complete vector by readback, but the SDK does not provide a numeric range for those three channel values, so no invented range is advertised.

The display decoder currently accepts RGB8 only. Mono, Bayer, packed RAW, YUV and other PFNC formats require format-specific decoders. The app currently registers the Amcam backend; native CTI Producer selection in the UI is not yet implemented. Native CTI feature access still requires a verified GenApi XML/port path. No synthetic register map or fake GenApi XML is used.

## Build and run

Run from the repository root on macOS 13 or later:

```sh
git pull
make run
```

The command builds all ten Swift library packages from source, builds the imaging executable, assembles and ad-hoc signs `Amcam Imaging.app`, and launches it. It does not download a release asset or depend on GitHub Actions artifacts.

The application UI uses AppKit, not SwiftUI. This avoids the `SwiftUIMacros.StateMacro` plugin dependency that caused the Command Line Tools build failure. The full Xcode application is not required; Apple's Swift compiler, macOS SDK and AppKit SDK must be available. If Swift is missing, install Command Line Tools with `xcode-select --install`.

Other commands:

- `make build-local` — build all packages and assemble the app without launching it.
- `make run-probe` — build and run the camera diagnostic from source.
- `make test-local` — run `swift test` across all ten Swift packages (including the GenTL ABI package). Hosted CI tests nine packages across Linux and macOS: the Linux job covers AmcamCameraModel, AmcamImagingCore, AmcamImagingRuntime and AmcamImagingState; five macOS matrix jobs cover the backend packages. CI separately builds the GenTL ABI package.

The vendor SDK is proprietary and is not bundled. For physical AmScope camera access, place a compatible arm64 `libamcam.dylib` under `vendor/amcam/macos/libamcam.dylib`, or install it in one of the backend's standard per-user/system locations. The build script copies a local vendor SDK into the app bundle; `AMCAM_SDK_SOURCE=/absolute/path/to/libamcam.dylib` can specify a source file at build time. The backend resolves the bundled SDK first. There is no SDK file picker in the UI. Without a compatible SDK, the app can launch but the AmScope provider is unavailable. The app is ad-hoc signed for local testing, not notarized.

## Pull-mode stop and restart

`Amcam_Stop` ends callback delivery, but the SDK can still retain frames in camera DDR and in its own DLL queue. After every successful stop, `AmcamCameraSession` therefore issues `Amcam_put_Option` with `AMCAM_OPTION_FLUSH` (`0x3d`) and value `3` to clear both caches before another pull-mode start. A stop is not reported as reusable until that flush succeeds.

The flush is part of the session lifecycle, not a UI delay or a USB reconnect workaround. If the SDK rejects it, the session retains a pending cleanup obligation; a later Stop, Close, or Start retries the flush. Start is blocked from registering a new callback until the pending flush succeeds. This preserves the device session and callback ownership while preventing a stale SDK frame queue from contaminating the next acquisition.

## Process relaunch and USB reconnect recovery

`make run` is a process restart, not just a rebuild followed by Launch Services reopening an existing app instance. Before the build/launch sequence, `scripts/build-and-run-macos.sh` checks for an existing `amcam-imaging` process and asks the running `com.amscope.imaging` application to quit normally. It waits for the process to exit before continuing. If the quit request fails or the process remains alive, the script exits with an error; it never force-kills the application or starts a second process that could contend for the camera. The `BUILD_ONLY=1` path used by `make build-local` and CI skips this shutdown behavior.

The application also runs low-frequency device discovery (every two seconds) because this SDK integration does not rely on a portable device-change notification:

- An incomplete/failed enumeration is not treated as proof that the camera has disappeared. The currently attached session is retained while discovery is inconclusive.
- If an incomplete background scan occurs while the session is idle, the session is marked for recreation. The next complete scan performs the ordered close and reopens the selected device, even if the SDK returns the same device identifier.
- A complete scan that finds the camera but an idle session still reports no usable data stream causes the application to recheck stream availability. This refreshes the Start-button capability state without rereading all camera controls.
- If the SDK reports a disconnect while acquisition is active, the camera callback reports a failure; the runtime stops the acquisition and retains native callback ownership until the SDK stop succeeds. The discovery monitor then handles reconnection and session recreation.

### MU503 recovery validation — 2026-11-21

The user confirmed that the following physical-camera workflow succeeds on the MU503:

1. Run `make run` while an earlier Amcam Imaging process is already open; the old process exits and the newly built application launches.
2. Keep that application process open, disconnect the MU503, and reconnect it.
3. The camera session recovers and the Start control becomes enabled again without manually quitting and relaunching the application.

This is a user-confirmed physical recovery result. It does not by itself establish five-minute sustained acquisition, every feature's readback, or the independent diagnostic-probe acceptance criteria. Those remain separate checks in [the hardware acceptance record](AMCAM_HARDWARE_ACCEPTANCE.md).
### First physical-camera test

Use the app first without changing the camera pixel format:

1. Confirm discovery and exclusive open of the MU503.
2. Start live acquisition and confirm a stable RGB image and a nonzero FPS display.
3. Stop and restart acquisition three times.
4. In Settings, test Exposure Auto Continuous, then Off (fixed/manual); change exposure time and confirm the readback.
5. Change analog gain and confirm its readback. Gain is represented as a percentage, not dB.
6. With the app still running, disconnect and reconnect the MU503; verify discovery/session recovery and that Start becomes enabled without restarting the app. Also run `make run` while an app instance is already open and verify the old process exits before the new build launches.

The application display path currently decodes RGB8 only. Do not use RAW, Bayer, YUV or other pixel formats as an acceptance test yet. Keep the default format for the first test. Record any error text and whether it occurred during discovery, open, start, streaming, stop or close.

The camera probe can exercise the backend without the GUI if the app reports discovery or acquisition errors. Add `--json` to `make run-probe` to emit a schema-versioned JSON report containing backend/SDK identity, camera model descriptor, stream payload, pixel-format identifier, dimensions, row stride, acquisition counters/timestamps, failure stage and cleanup errors. The JSON document is the only stdout output in this mode; SwiftPM build diagnostics remain on stderr. During cleanup, the probe stops acquisition, unregisters stream events, uses `ACQ_QUEUE_ALL_DISCARD`, revokes every announced buffer, then closes parent modules in dependency order. A cleanup failure is retained in `cleanup_errors` and prevents later parent teardown. The probe still exits nonzero when the report status is `failure`, while preserving the structured report on stdout.

## TDD assessment

The routed acquisition increment was developed test-first against a fake GenTL Producer. Regression coverage verifies New Buffer event decoding, metadata and payload copying, buffer requeue, and queue flush ordering around start/stop/close. Amcam SDK integration coverage also requires a post-`Amcam_Stop` flush before a new pull-mode callback can start, and injects a failed flush to verify that the pending operation is retried before restart.

Typed feature access is tested at three layers:
- GenTLAPI value kinds, numeric ranges, descriptor access state and integer-vector metadata;
- GenTLRouter backend-bound feature forwarding and closed-session behavior;
- Amcam mock-SDK integration for per-camera availability, exposure/gain, color matrix, pixel format, white-balance temperature/tint/RGB vector, fixed frame rate, resolution enumeration, validation and readback.

Camera model/capability policy has its own test target. The `macos-version-0.2` source baseline at commit `4f4a8ca022274eba5fe49dc2489f9e7fa766dd64` passed [GitHub Actions run 44860717992](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44860717992): all six jobs completed successfully, including the Linux core/runtime/state suite, all five macOS package jobs, the camera-probe build, dependency-boundary checks, and fixture-SDK app packaging/signing. The `macos-version-0.3` documentation commits are validated separately by their own branch workflow. The user has also confirmed the physical MU503 process-relaunch and USB reconnect recovery described above; this is a partial hardware result, not completion of the full hardware acceptance checklist. Historical development was not uniformly test-first: some earlier SDK controls predate their tests. New feature work must continue with failing tests first, implementation, full regression and refactoring.

## Package dependency boundary (2026-11-20)

Camera presentation types and model capability/profile policy are defined in the independent `AmcamCameraModel` package. The application depends on AmcamCameraModel, AmcamImagingCore, AmcamImagingRuntime, AmcamImagingGenTLAdapter and AmcamImagingState. It does not depend directly on GenTLABI, GenTLAPI, GenTLRouter or AmcamGenTL. The Amcam backend imports and re-exports AmcamCameraModel so existing clients can continue importing AmcamGenTL while accessing the same public camera model types. This is a source-compatibility bridge, not a reason for the app to reference backend implementation types.



## Resource cleanup and retry semantics

CameraSessionLifecycle owns resources in dependency order: acquisition first, parent device session second. If acquisition cleanup fails (for example, a Producer refuses to revoke an announced buffer), the runtime retains both the acquisition and device session and does not close the parent. If device close fails, the runtime retains the device session. The app receives the cleanup error and does not discard or replace the runtime-owned handle. A later close/shutdown attempt retries the retained resource. The UI never owns or manipulates GenTL handles.

GenTLRouter acquisition tests inject a buffer-revoke failure, verify that the data stream is not closed prematurely, then allow revocation and verify that a second close succeeds. Runtime lifecycle tests separately verify child-before-parent cleanup and retry behavior.


## Triggered acquisition and event timeouts

A GenTL New Buffer event timeout means only that no buffer arrived within the requested wait interval. It is not proof that the camera or acquisition has failed: a camera may be waiting for an external trigger, a software trigger, or simply a longer frame interval. GenTLRuntimeAcquisition maps this to the backend-neutral recoverable timeout; CameraSessionLifecycle continues waiting and does not close the device. A stop/close request remains distinct and terminates the capture loop through the normal lifecycle path.

A fake Producer test forces an event timeout, then delivers a valid frame without restarting the acquisition session. This verifies that timeout handling is recoverable rather than a fatal stream transition.

## Amcam pull API selection (SDK 58.28273.20250415)

The checked-in `amcam.py` identifies the vendor SDK version as `58.28273.20250415` and documents three generations of pull API:

- `Amcam_PullImageV2`: basic frame metadata, no explicit row-pitch argument.
- `Amcam_PullImageV3`: V3 metadata (exposure time/gain, shutter sequence, black level) and explicit row pitch.
- `Amcam_PullImageV4`: V4 metadata, which embeds V3 metadata and adds luminance/focus values, counters, and GPS data; explicit row pitch.
- `Amcam_PullImageWithRowPitchV2`: V2 metadata with explicit row pitch.

The Swift binding resolves these symbols independently at runtime and selects the highest available generation in this order: V4, V3, row-pitch V2, plain V2. Missing newer symbols do not prevent loading an SDK that exposes an older supported API. At least one pull API must exist. API availability is also camera-specific at runtime: the vendor defines `E_NOTIMPL` as a feature not supported by that camera model. The Swift backend therefore retries the next available API generation only when a pull function returns this exact result. It does not retry generic device, timeout, invalid-argument or buffer errors.

For the current RGB24 acquisition path, V3/V4 and row-pitch V2 are called with `rowPitch = -1`, which the vendor wrapper documents as zero-padding/tightly packed rows (`width * 3` bytes for RGB24). This makes the buffer layout explicit instead of relying on platform DIB alignment. The V2 fallback retains its documented default row layout and is only used when no row-pitch-aware function exists.

V3/V4 metadata is now retained in the public `AmcamFrame.metadata` payload. It records the API generation and raw validity flags, and only exposes individual values when the corresponding `AMCAM_FRAMEINFO_FLAG` bit marks them valid. V3 fields include shutter sequence, exposure time (microseconds), exposure gain and black level. V4 adds luminance, focus value, counters and GPS. GPS values preserve the vendor units explicitly: Unix nanoseconds, microdegrees and millimetres. No conversion or inference is applied to invalid fields.

The V4 ABI layout follows the checked-in Python ctypes definition exactly: `reserved` is at offset 40, `uLum` at 44, `uFV` and `timecount` are signed 64-bit fields at offsets 48 and 56, and GPS begins at offset 72. The structure is 104 bytes on the supported 64-bit ABI. C compile-time assertions verify the individual member offsets as well as structure sizes. The mock SDK deliberately uses values larger than 32 bits for focus and time counters so truncation is detectable.

Row layout is now tied to the function that actually succeeds for the connected camera, not merely the newest exported symbol. V3/V4 and row-pitch V2 request `rowPitch = -1` and use tightly packed rows; plain V2 uses the SDK's default DWORD-aligned RGB24 rows. This distinction matters for widths where `width * 3` is not divisible by four. The frame's `bytesPerRow` and payload length follow the selected API's actual row contract. The GenTL data-stream layer validates and publishes that same stride, data size and X-padding value; it does not reinterpret every frame as the legacy V2 layout.

Hosted tests cover V4 preference and every metadata field, invalid-field suppression when validity flags are absent, V3 fallback when V4 is absent, row-pitch V2 fallback when V3/V4 are absent, plain V2 fallback when no row-pitch-aware function exists, camera-specific `E_NOTIMPL` fallback, and preservation of non-`E_NOTIMPL` hardware errors. ABI layout assertions cover V2, V3, GPS and V4. These tests validate the mock ABI and dispatch behavior; real-camera compatibility remains a separate hardware acceptance item. The current UI still requests 24-bit RGB; this work does not claim RAW10/RAW12 or RGB48 decoding support.

