# Amcam macOS camera probe

This is a hardware smoke-test executable for the Amcam SDK backend. It is built for Apple Silicon macOS by GitHub Actions, so a local Xcode installation is not required to run the downloaded executable.

The probe uses the actual \`AmcamGenTLImplementation\` and GenTL-style acquisition path. It does not substitute a mock SDK at runtime. It does not modify exposure, gain, or frame-rate settings.

## Obtain the executable

The current source revision was verified in [workflow run 44683070601](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44683070601). Its **AmcamGenTL tests**, **Build macOS camera probe**, and **Upload macOS camera probe** steps all succeeded. Download `amcam-camera-probe-macos-arm64` from that run's **Artifacts** section.

- Artifact ID: `14605760059`
- SHA-256: `b23ee03db32c19c8def9f7c341e882f70f6741d04b453edf29dbd67e3e8adb13`
- Expiration: December 4, 2026

The artifact is an Apple Silicon arm64 executable, matching the Mac's architecture. The overall workflow remains marked failed because the separate GenTLNative and GenTLRouter jobs fail; those failures do not affect the successful Amcam package, probe build, or artifact upload. The artifact contains the executable and this instruction file. The vendor SDK is proprietary and is not included.

The original vendor Amcam SDK had already streamed successfully on this Mac. This probe is the next verification layer: it exercises the new Swift AmcamGenTL backend against the actual vendor dylib and physical camera, rather than retesting only the SDK itself.

## Find the vendor SDK

Supply the actual Amcam SDK dynamic library, normally named \`libamcam.dylib\`. Known deployment locations include:

- \`vendor/amcam/macos/libamcam.dylib\` in a local application checkout;
- \`~/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib\`;
- \`/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib\`;
- \`/Library/Frameworks/libamcam.dylib\`;
- \`/usr/local/lib/libamcam.dylib\`;
- \`/opt/homebrew/lib/libamcam.dylib\`.

Do not download or use an arbitrary third-party SDK binary. Use the SDK supplied for the camera by AmScope or its SDK vendor.

## Run a short capture

Close the official AmScope application and any other microscope application first. The probe requests exclusive camera access.

From Terminal, in the extracted artifact directory:

\`\`\`sh
chmod +x ./amcam-camera-probe
./amcam-camera-probe \\
  --sdk "/absolute/path/to/libamcam.dylib" \\
  --frames 10 \\
  --output "$HOME/Desktop/mu503-test.ppm"
\`\`\`

The tool reports:

- SDK version and discovered device identifiers;
- selected camera model and display name;
- data-stream payload size;
- each frame's dimensions, filled bytes, row stride, sequence number, device timestamp, and SHA-256;
- host-loop rate and camera timestamp-derived rate when timestamps are available;
- the last complete frame as a PPM image if \`--output\` is supplied.

For a longer stability sample:

\`\`\`sh
./amcam-camera-probe \\
  --sdk "/absolute/path/to/libamcam.dylib" \\
  --frames 300 \\
  --timeout-ms 5000 \\
  --output "$HOME/Desktop/mu503-stability.ppm"
\`\`\`

The executable announces up to four buffers, subject to a 512 MiB aggregate allocation limit, and requeues each delivered buffer while acquisition continues. This reduces probe-induced starvation compared with a single-buffer loop. It reports incomplete frames and camera Error events as failures. It does not change camera settings.

## Interpretation

A successful run proves that this SDK binary can load on the Mac, enumerate and open the camera, deliver image callbacks, and pass frames through the AmcamGenTL data-stream buffer/event path. It does not by itself prove long-duration stability, color correctness, sensor timing accuracy, or maximum supported FPS.

The camera timestamp rate is calculated from SDK frame timestamps in microseconds. The host-loop rate includes event retrieval and probe processing; it is not a sensor-FPS claim.

If the SDK fails to load, record the full error and the SDK path. If no device is enumerated, record the USB VID:PID and negotiated link speed from macOS IORegistry. Do not infer usable bandwidth from the hub's advertised USB version.

The previous MU503 hardware record identified VID:PID \`0547:4511\` and a Mac connection operating at USB 2.0 High Speed (480 Mbit/s) through the observed hub path. A historical 101 fps result at 640×480 on a Windows USB 3 connection is a comparison target, not an expectation for this Mac connection. Record the actual result before changing the transport path.

## Safety and limitations

- The probe requests exclusive access and may fail if another application owns the camera.
- It does not set exposure, gain, white balance, resolution, or frame rate.
- It currently tests one selected device and the first data stream.
- It writes only the last complete frame, not a recording.
- The executable is an Apple Silicon macOS build. It is not a Windows or Linux binary.
- The proprietary SDK is not embedded in the artifact.
