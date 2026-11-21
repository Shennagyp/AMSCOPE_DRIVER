# Amcam physical-camera acceptance — macOS Apple Silicon

## Purpose

Validate the Amcam Swift implementation and the packaged imaging application against the physical AmScope MU503. CI tests use a deterministic C mock SDK. They do not establish physical camera compatibility.

The full Xcode application is not required. The Mac needs Apple's Swift compiler, macOS SDK and AppKit SDK for the source build. Hosted CI validates package tests and app compilation; the user's Mac builds and launches the app with `make run` before physical-camera acceptance.

## Required files and SDK placement

Start from a checkout of this repository on the target Mac. The vendor SDK is proprietary and is not committed. Place the compatible arm64 `libamcam.dylib` at `vendor/amcam/macos/libamcam.dylib`, or install it in one of the backend's standard per-user/system locations. The build script copies a local SDK into the app bundle and signs the copy. The backend resolves the bundled library first; the UI has no SDK file picker.

Build and launch from the repository root:

```sh
git pull
make run
```

If the SDK is absent, the app can launch but the AmScope provider remains unavailable.

## Test sequence

### A. Establish library and device identity

1. Connect the MU503 directly to the Mac, using a known-good USB cable and power arrangement.
2. Launch AmScope Imaging.
3. Confirm the SDK was found by the backend. If the provider is unavailable, check the vendor directory or standard SDK installation paths, then relaunch.
4. Refresh the camera list.
5. Confirm the device display name and exact model descriptor shown by the SDK.
6. Open Settings and record which groups and controls are shown.

Record the SDK version, macOS version, exact model descriptor, device identifier (for the test log only), and the camera's model flags.

### B. Live acquisition

1. Press Start and confirm a live image appears.
2. Confirm the image dimensions and that the displayed FPS becomes nonzero.
3. Leave acquisition running for at least five minutes.
4. Press Stop and verify the image stream stops without an error.
5. Start again and verify acquisition resumes.
6. Disconnect the camera while streaming, record the reported error, reconnect, refresh, and start again.

Do not run the diagnostic probe and GUI application against the same camera at the same time. Only one process should own the camera handle.

### C. Settings

Only test controls the application reports as available for the connected model.

1. Switch between Fixed/Manual, Auto Continuous, and Auto Once when those modes are exposed.
2. In Fixed/Manual mode, change exposure to two values well inside the camera-reported range. Record requested and read-back values.
3. Change analog gain only when its range is available. Record requested and read-back values.
4. Change resolution while acquisition is stopped. Restart and verify image dimensions.
5. Change frame rate or discrete speed only when offered by the camera.
6. Change white balance only for the mode actually exposed: Temperature/Tint or RGB Gain.
7. Change color matrix and pixel format only when those controls are exposed. Pixel format changes must be made while stopped.
8. Verify the control values remain coherent after stopping and restarting.

Do not force an unsupported setting or infer a range from another camera model.

### D. Diagnostic probe

Run the probe after closing the imaging application. From the repository root:

```sh
# Human-readable terminal report and PPM image
make run-probe PROBE_ARGS='--sdk "/absolute/path/to/libamcam.dylib" --frames 10 --output "$HOME/Desktop/mu503-test.ppm"'

# Machine-readable JSON report (build diagnostics remain on stderr)
make run-probe PROBE_ARGS='--sdk "/absolute/path/to/libamcam.dylib" --frames 10 --output "$HOME/Desktop/mu503-test.ppm" --json' > "$HOME/Desktop/mu503-probe.json"
```

Preserve the terminal output or JSON report and the generated PPM image. Do not use `sudo`. The versioned JSON schema reports `failure.stage` and a separate `cleanup_errors` array on failure; the command still returns a nonzero exit status.

If the probe reports an SDK load, version, enumeration, open, event, buffer, format, or cleanup error, preserve the exact error rather than retrying with guessed SDK arguments.

## Acceptance record

Record:

- macOS version and Mac architecture.
- SDK file path, SDK version, and SHA-256 of the vendor dylib.
- Camera display name and exact model descriptor.
- Whether device enumeration and open succeeded.
- Live stream duration, displayed FPS, observed image dimensions.
- Exposure mode transitions and requested/read-back exposure values.
- Gain and frame-rate values, when offered.
- Resolution, white balance, color matrix, and pixel-format results, when offered.
- Stop/restart, disconnect/reconnect, and cleanup results.
- Full probe terminal output or JSON report and PPM file.

### E. Relaunch and USB hot-plug recovery

1. Leave Amcam Imaging open with the MU503 selected.
2. Disconnect the MU503 and reconnect it without quitting the application.
3. Allow the background discovery monitor to complete a successful scan.
4. Verify the selected camera session is recreated and Start becomes enabled.
5. Separately, while an Amcam Imaging instance is already running, execute `make run` from the repository. Verify the old process exits cleanly and the rebuilt application opens as a new process.

`make run` requests a normal application quit before it builds and launches the replacement. It does not force-kill a process that refuses to exit; it aborts instead of allowing two app processes to contend for the camera. `make build-local` does not close a running application.

## Recorded physical result — 2026-11-21

The user confirmed that the MU503 recovery workflow above succeeded:

- `make run` completed while an earlier app instance was open; the old app exited and the replacement launched.
- The MU503 was disconnected and reconnected while the replacement app remained open.
- The application recovered the camera session and re-enabled Start without requiring another app restart.

This record is intentionally limited to process relaunch and idle USB reconnect recovery. The user did not report the SDK version, exact model descriptor, firmware, macOS build, or Mac architecture with this confirmation. Do not infer those values.

The following broader acceptance items are **not established by this result** and remain open: five-minute sustained live acquisition, repeated start/stop cycles, disconnect while actively streaming, every exposed feature's setter/readback, and independent probe validation of metadata/payload/cleanup. CI success does not close those hardware-specific checks.

## Acceptance criteria

The macOS first-pass acceptance is successful only when:

- the real MU503 is discovered and opened through the Swift backend;
- the GUI displays actual live frames for five minutes without a crash or unexplained stop;
- start/stop/restart and disconnect handling are clean;
- each exposed control produces verified SDK readback;
- no unsupported feature is offered as an editable control;
- the diagnostic probe independently validates frame metadata, payload layout, and cleanup.

A successful CI job is not physical-camera acceptance. A successful probe alone is not full GUI acceptance.
