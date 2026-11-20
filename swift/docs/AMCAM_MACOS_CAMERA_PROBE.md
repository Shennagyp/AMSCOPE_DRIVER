# Amcam macOS camera probe

This is a hardware smoke-test executable for the Amcam SDK backend. Build it from the repository root with `make run-probe`. The full Xcode application is not required; Apple's Swift compiler and macOS SDK are required.

The probe uses the actual `AmcamGenTLImplementation` and GenTL-style acquisition path. It does not substitute a mock SDK at runtime. It does not modify exposure, gain, or frame-rate settings.

## Build the probe from source

From the repository root on macOS with Apple's Swift toolchain installed:

```sh
make run-probe PROBE_ARGS='--help'
```

The probe requires an explicit SDK path because it is a diagnostic tool. Unlike the imaging app, it does not use the app-bundle vendor locator. The app itself resolves its SDK from the bundled vendor directory and standard per-user/system installation locations.

`make run-probe` builds the executable locally from the current checkout; it does not require a downloaded Actions artifact or the full Xcode application.

## Find the vendor SDK

Supply the actual Amcam SDK dynamic library, normally named `libamcam.dylib`. Known deployment locations include:

- `vendor/amcam/macos/libamcam.dylib` in a local application checkout;
- `~/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib`;
- `/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib`;
- `/Library/Frameworks/libamcam.dylib`;
- `/usr/local/lib/libamcam.dylib`;
- `/opt/homebrew/lib/libamcam.dylib`.

Do not download or use an arbitrary third-party SDK binary. Use the SDK supplied for the camera by AmScope or its SDK vendor.

## Run a short capture

Close the official AmScope application and any other microscope application first. The probe requests exclusive camera access.

From the repository root:

```sh
make run-probe PROBE_ARGS='--sdk "/absolute/path/to/libamcam.dylib" --frames 10 --output "$HOME/Desktop/mu503-test.ppm"'
```

For a longer stability sample:

```sh
make run-probe PROBE_ARGS='--sdk "/absolute/path/to/libamcam.dylib" --frames 300 --timeout-ms 5000 --output "$HOME/Desktop/mu503-stability.ppm"'
```
## Interpretation

A successful run proves that this SDK binary can load on the Mac, enumerate and open the camera, deliver image callbacks, and pass frames through the AmcamGenTL data-stream buffer/event path. It does not by itself prove long-duration stability, color correctness, sensor timing accuracy, or maximum supported FPS.

The camera timestamp rate is calculated from SDK frame timestamps in microseconds. The host-loop rate includes event retrieval and probe processing; it is not a sensor-FPS claim.

If the SDK fails to load, record the full error and the SDK path. If no device is enumerated, record the USB VID:PID and negotiated link speed from macOS IORegistry. Do not infer usable bandwidth from the hub's advertised USB version.

The previous MU503 hardware record identified VID:PID `0547:4511` and a Mac connection operating at USB 2.0 High Speed (480 Mbit/s) through the observed hub path. A historical 101 fps result at 640×480 on a Windows USB 3 connection is a comparison target, not an expectation for this Mac connection. Record the actual result before changing the transport path.

## Safety and limitations

- The probe requests exclusive access and may fail if another application owns the camera.
- It does not set exposure, gain, white balance, resolution, or frame rate.
- It currently tests one selected device and the first data stream.
- It writes only the last complete frame, not a recording.
- The executable is an Apple Silicon macOS build. It is not a Windows or Linux binary.
- The proprietary SDK is not embedded in the probe executable.
