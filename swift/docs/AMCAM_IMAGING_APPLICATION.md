# Amcam Imaging — macOS application

## Objective

A native macOS camera application built on the Amcam SDK backend in this repository. The main window is a full-screen-capable live image surface. A hardware dock provides camera selection, refresh, start, stop, settings, SDK selection, and full-screen controls. Camera settings are presented in a popup sheet.

The target application is a GenTLAPI consumer. GenTLRouter owns backend selection and device-session creation; the selected backend may be a native CTI Producer or the Amcam SDK-backed GenTL implementation. The app must not instantiate AmcamCameraDriver or AmcamCameraSession directly.

**Current routed architecture on `macos-version-optimization`:** CameraApplicationModel discovers and opens devices through GenTLRouter, reads and writes advertised controls through GenTLDeviceSession, and receives frames through GenTLAcquisitionSession. The app package depends on AmcamCameraModel, GenTLABI, GenTLAPI and GenTLRouter; it does not import or depend on AmcamGenTL and does not construct AmcamCameraDriver or AmcamCameraSession. CI enforces this dependency boundary.

## Architecture

- **GenTLAPI** is the app-facing protocol contract; the app must not depend on the transitional BackendConvenience SPI.
- **GenTLRouter** registers native CTI and Amcam backends, discovers devices and returns backend-bound device sessions.
- **GenTLFeatureAccess** exposes typed controls alongside the unchanged GenTL 1.6 operation surface. Amcam maps supported controls to SDK methods; native CTI feature access requires a real GenApi XML/port path.
- **AmcamGenTL** owns SDK loading, camera enumeration, session lifecycle, frame acquisition, control readback and model capability discovery.
- **AmcamImagingApp** owns the macOS SwiftUI interface and translates backend-neutral frames to display images.
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

White balance is also independent of exposure and gain. The app probes the two modes separately: temperature/tint and RGB channel gains. It shows only the mode whose getter and setter symbols are both present and whose read-only query succeeds. Temperature and tint use the documented ranges 2000–15000 K and 200–2500. RGB gains are sent as three integer values and accepted only after exact readback; no undocumented min/max range is invented.

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
- device discovery and opening through GenTLRouter;
- live image acquisition through GenTLAcquisitionSession and the GenTL New Buffer event;
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

The app is built and packaged by hosted macOS GitHub Actions. A local Xcode installation is not required.

1. Open the latest successful [macOS workflow run](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions).
2. Download the `amcam-imaging-macos-arm64` artifact.
3. Extract `Amcam-Imaging-macos-arm64.zip`.
4. Open `Amcam Imaging.app`.
5. If the app does not find the SDK automatically, use SDK… to select the vendor `libamcam.dylib`.
6. Select the camera from the hardware dock, then start live acquisition.

The vendor SDK is proprietary and is not bundled. The app requires a compatible arm64 `libamcam.dylib` version 58.28273.20250415. The app is ad-hoc signed for local testing, not notarized. CI does not establish physical camera compatibility; MU503 acceptance remains a separate hardware test.

## Verification boundary

Swift package tests use a deterministic native C fixture. They verify ABI calls, state transitions, callbacks, feature range logic, and memory safety; they do not establish physical camera compatibility. The app's CI build proves compilation and packaging only. Physical MU503 acceptance remains a separate test.


## CI build and current runnable artifact

Latest successful hosted macOS validation: [workflow run 44703255740](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44703255740), built from commit `043b9f3448e529a1ed647963124d83c07bae7e2e`.

- All five package test jobs passed: GenTLAPI, GenTLNative, GenTLRouter, AmcamCameraModel and AmcamGenTL.
- The new integer-vector feature contract and Amcam RGB white-balance integration tests passed.
- The routed application dependency guard passed.
- Camera probe release build and artifact upload passed.
- Imaging application release build, app-bundle signature verification and arm64 Mach-O verification passed.
- The app build emitted no compiler warnings in the captured job log.

Current application artifact:
- Artifact: `amcam-imaging-macos-arm64`
- Artifact ID: `14613319868`
- Expiry: 2026-12-04 08:33 UTC.
- The artifact is ad-hoc signed for local testing, not notarized, and does not bundle the proprietary vendor SDK.

CI proves package tests, compilation and packaging. It does not prove camera discovery or physical acquisition. Physical MU503 acceptance remains outstanding.

## TDD assessment

The routed acquisition increment was developed test-first against a fake GenTL Producer. Regression coverage verifies New Buffer event decoding, metadata and payload copying, buffer requeue, and queue flush ordering around start/stop/close.

Typed feature access is tested at three layers:
- GenTLAPI value kinds, numeric ranges, descriptor access state and integer-vector metadata;
- GenTLRouter backend-bound feature forwarding and closed-session behavior;
- Amcam mock-SDK integration for per-camera availability, exposure/gain, color matrix, pixel format, white-balance temperature/tint/RGB vector, fixed frame rate, resolution enumeration, validation and readback.

Camera model/capability policy has its own test target. The complete five-package hosted macOS matrix and standalone app build passed. Historical development was not uniformly test-first: some earlier SDK controls predate their tests. New feature work must continue with failing tests first, implementation, full regression and refactoring.

## Package dependency boundary (2026-11-20)

Camera presentation types and model capability/profile policy are defined in the independent `AmcamCameraModel` package. The application depends on this model package plus GenTLABI, GenTLAPI and GenTLRouter. It does not depend directly on AmcamGenTL. The Amcam backend imports and re-exports AmcamCameraModel so existing clients can continue importing AmcamGenTL while accessing the same public camera model types. This is a source-compatibility bridge, not a reason for the app to reference backend implementation types.


## Package dependency boundary

Camera presentation types and model capability/profile policy are defined in the independent `AmcamCameraModel` package. The application depends on this model package plus GenTLABI, GenTLAPI and GenTLRouter. It does not depend directly on AmcamGenTL. The Amcam backend imports and re-exports AmcamCameraModel so existing clients can continue importing AmcamGenTL while accessing the same public camera model types. This is a source-compatibility bridge, not a reason for the app to reference backend implementation types.


## Resource cleanup and retry semantics

The application closes resources in dependency order: acquisition session first, device session second. If acquisition cleanup fails (for example, a Producer refuses to revoke an announced buffer), the application retains both the acquisition and device session handles and does not close the parent device. If device close fails, the device session remains retained. The user can retry cleanup by selecting the same camera action again or by shutting down; the app must not discard a still-owned handle and continue as if cleanup succeeded.

The GenTLRouter acquisition tests inject a buffer-revoke failure, verify that the data stream is not closed prematurely, then allow revocation and verify that a second close succeeds. The app follows the same parent/child ownership rule.


## Triggered acquisition and event timeouts

A GenTL New Buffer event timeout means only that no buffer arrived within the requested wait interval. It is not proof that the camera or acquisition has failed: a camera may be waiting for an external trigger, a software trigger, or simply a longer frame interval. GenTLAcquisitionSession reports this outcome as `eventTimeout`; the app keeps waiting and does not close the device. A stop/close request remains distinct and is reported as `acquisitionStopped`.

A fake Producer test forces an event timeout, then delivers a valid frame without restarting the acquisition session. This verifies that timeout handling is recoverable rather than a fatal stream transition.
