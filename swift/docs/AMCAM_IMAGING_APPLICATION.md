# Amcam Imaging — macOS application

## Objective

A native macOS camera application built on the Amcam SDK backend in this repository. The main window is a full-screen-capable live image surface. A hardware dock provides camera selection, refresh, start, stop, settings, SDK selection, and full-screen controls. Camera settings are presented in a popup sheet.

The target application is a GenTLAPI consumer. GenTLRouter owns backend selection and device-session creation; the selected backend may be a native CTI Producer or the Amcam SDK-backed GenTL implementation. The app must not instantiate AmcamCameraDriver or AmcamCameraSession directly.

**Migration status on `macos-version-optimization`:** the executable has been extracted into `swift/Apps/AmcamImagingApp` so it can depend on GenTLRouter without a SwiftPM package cycle. The current CameraApplicationModel still contains legacy direct Amcam driver/session calls. Those calls are transitional and must be removed by the routed-session migration; the package move alone does not mean the app is already routed.

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

The first application slice exposes:
- live RGB24 camera preview;
- device enumeration and selection;
- start/stop and session cleanup;
- resolution selection when the loaded SDK exposes resolution changes;
- manual/fixed, continuous-auto, and one-shot-auto exposure modes;
- exposure-time range and exact readback;
- analog gain range, setter, and exact readback when the SDK symbols and camera queries are available;
- temperature/tint and RGB-channel white-balance modes, each gated independently by its SDK symbols and runtime query;
- color-matrix enable/disable with readback;
- pixel-format selection from the camera's enumerated supported-format list, only while acquisition is stopped;
- precise fixed frame rate when both model flag and runtime option probes succeed;
- discrete sensor speed when model speed range and SDK get/set symbols are usable.

Color correction and pixel-format support are runtime-probed and exposed as editable controls. Pixel-format changes are constrained to the enumerated formats returned by Amcam_get_PixelFormatSupport and are rejected during acquisition. Other Amcam feature groups are capability-described from the model flags, but controls not yet wired into the Swift backend are labelled as pending. They are not falsely exposed as editable settings. The next control integrations should follow the supplied wrapper's feature semantics and add readback plus model-specific tests before UI activation.

## Build and run

The application is built on the macOS GitHub Actions runner. A local Xcode installation is not required to download and run the packaged app.

1. Open the repository's swift-gentl-api branch Actions run.
2. Download artifact amcam-imaging-macos-arm64.
3. Extract Amcam-Imaging-macos-arm64.zip.
4. Open Amcam Imaging.app.
5. If the app does not find the SDK automatically, use SDK… to select the vendor libamcam.dylib.
6. Select the camera from the hardware dock, then start live acquisition.

The vendor SDK is proprietary and is not bundled. The app requires a compatible arm64 libamcam.dylib version 58.28273.20250415. The first hardware acceptance run must verify discovery, open, live RGB image, frame rate, exposure mode transitions, manual exposure readback, resolution changes, and clean stop/close on the physical MU503.

## Verification boundary

Swift package tests use a deterministic native C fixture. They verify ABI calls, state transitions, callbacks, feature range logic, and memory safety; they do not establish physical camera compatibility. The app's CI build proves compilation and packaging only. Physical MU503 acceptance remains a separate test.


## CI build and current runnable artifact

Latest successful macOS validation:

- Workflow run: [44689152308](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44689152308)
- Source revision used by the build: `07ebaf591ac4052ef525952b026edbeec0727d8a`
- Amcam package tests: 21 XCTest cases scheduled and passed.
- Diagnostic probe: release arm64 build and upload passed.
- Imaging application: release build passed, app-bundle code signature verification passed, and Mach-O arm64 verification passed.
- App artifact ID: `14606959758`
- Artifact SHA-256: `6638aeb9d309d49e98577562d517080454d2d2b4221b5b2af66c6c86a198f903`
- Artifact expiry: December 4, 2026.

The app is ad-hoc signed for local testing, not notarized, and does not bundle the proprietary vendor SDK.

## TDD assessment

The current suite has 21 tests across ABI string-bound checks, RGB24 layout, capability/profile resolution, and native C mock-SDK integration. The latest regression for auto-exposure mode remaining usable when manual exposure range queries fail was added before the implementation change and passed in CI.

The entire development history is not strictly TDD: some earlier controls were implemented before their tests. Future feature work and the multiplatform extraction must follow the explicit failing-test → implementation → full regression → refactor sequence. A passing test alone is not proof that the entire feature was developed test-first.
