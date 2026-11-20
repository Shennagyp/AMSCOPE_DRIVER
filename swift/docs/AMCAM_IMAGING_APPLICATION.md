# Amcam Imaging — macOS application

## Objective

A native macOS camera application built on the Amcam SDK backend in this repository. The main window is a full-screen-capable live image surface. A hardware dock provides camera selection, refresh, start, stop, settings, SDK selection, and full-screen controls. Camera settings are presented in a popup sheet.

The application is a client of the Amcam camera API. It does not implement another camera driver and does not use the GenTL native CTI route.

## Architecture

- **AmcamGenTL** owns SDK loading, camera enumeration, session lifecycle, frame acquisition, control readback, and model capability discovery.
- **AmcamCameraProfileRegistry** resolves per-camera policy using the SDK model descriptor name, model flags, safe read-only runtime probes, and the set of controls implemented by this application.
- **AmcamImagingApp** owns the macOS SwiftUI interface and translates frames to display images.
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
| Hardware ROI | 0x00000008 |
| Monochrome sensor | 0x00000010 |
| Binning / skipping | 0x00000020 |
| TEC present | 0x00000080 |
| Sensor temperature | 0x00000400 |
| Cooling fan | 0x00010000 |
| TEC on/off and target control | 0x00020000 |
| Software trigger | 0x00080000 |
| External trigger | 0x00100000 |
| Black level | 0x00400000 |
| Auto focus | 0x00800000 |
| Conversion gain | 0x04000000 |
| Focus motor | 0x0000002000000000 |
| Precise frame rate | 0x0000004000000000 |
| Anti-fog heat | 0x0000008000000000 |
| Low-noise mode | 0x0000010000000000 |
| Hardware level range | 0x0000020000000000 |
| Embedded light source | 0x0000080000000000 |
| Filter wheel | 0x0000100000000000 |
| Self trigger | 0x0040000000000000 |

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
