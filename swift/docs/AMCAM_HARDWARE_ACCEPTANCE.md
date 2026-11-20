# Amcam physical-camera acceptance — macOS Apple Silicon

## Purpose

Validate the Amcam Swift implementation and the packaged imaging application against the physical AmScope MU503. CI tests use a deterministic C mock SDK. They do not establish physical camera compatibility.

The user does not need Xcode, Swift, a compiler, or a development toolchain on the Mac. The application and diagnostic probe are built on GitHub Actions macOS runners.

## Required files

From the same successful GitHub Actions run, download:

- \`amcam-imaging-macos-arm64\`: packaged \`AmScope Imaging.app\` ZIP and quick-start note.
- \`amcam-camera-probe-macos-arm64\`: arm64 diagnostic probe and probe instructions.

The vendor SDK is intentionally not bundled. The user must select their existing compatible \`libamcam.dylib\` from the SDK installation or vendor package.

## Test sequence

### A. Establish library and device identity

1. Connect the MU503 directly to the Mac, using a known-good USB cable and power arrangement.
2. Launch AmScope Imaging.
3. Use **SDK…** to select the vendor \`libamcam.dylib\` if automatic discovery did not find it.
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

Run the probe after closing the imaging application:

\`\`\`bash
chmod +x ./amcam-camera-probe

./amcam-camera-probe \
  --sdk "/absolute/path/to/libamcam.dylib" \
  --frames 10 \
  --output "$HOME/Desktop/mu503-test.ppm"
\`\`\`

Preserve the full terminal output and the generated PPM image. Do not use \`sudo\`.

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
- Full probe terminal output and PPM file.

## Acceptance criteria

The macOS first-pass acceptance is successful only when:

- the real MU503 is discovered and opened through the Swift backend;
- the GUI displays actual live frames for five minutes without a crash or unexplained stop;
- start/stop/restart and disconnect handling are clean;
- each exposed control produces verified SDK readback;
- no unsupported feature is offered as an editable control;
- the diagnostic probe independently validates frame metadata, payload layout, and cleanup.

A successful CI job is not physical-camera acceptance. A successful probe alone is not full GUI acceptance.
