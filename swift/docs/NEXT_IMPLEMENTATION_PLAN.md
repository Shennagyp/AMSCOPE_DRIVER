# Next implementation plan

## 1. Delivery contract

The repository contains reusable SwiftPM libraries and two executable products:

| Product | Package | Purpose | Entry point |
|---|---|---|---|
| Imaging application | `swift/Apps/AmcamImagingApp` | User-facing camera application | `amcam-imaging` |
| Camera probe | `swift/Packages/AmcamGenTL` | Headless backend and hardware diagnostic | `amcam-camera-probe` |

The library packages are not standalone applications and must not acquire artificial `main` entry points merely to make them appear runnable. They are consumed by the executable products and tested through their own package test targets.

The repository-level Makefile is the supported command interface:

- `make run`: request an orderly quit of any existing `amcam-imaging` process, build every Swift library package, build the imaging app, assemble and ad-hoc sign its `.app` bundle, then launch it locally. If the previous process does not exit, abort rather than force-killing it or launching a competing camera owner. Build-only invocations do not request app shutdown.
- `make build-probe`: compile the Amcam camera diagnostic without running it; build output is sent to stderr.
- `make run-probe`: build and run the diagnostic; `--json` reserves stdout for a single versioned JSON report.
- `make build-local`: build every Swift library and the imaging app without launching it.
- `make run-local`: alias for `make run`.
- `make test-local`: run `swift test` across all ten Swift packages locally.

The default `make run` path is a source build on the user's Mac. It requires macOS 13 or later, Apple's Swift compiler, the macOS SDK and AppKit. The full Xcode application is not required: the app uses AppKit rather than SwiftUI, so the build does not require the SwiftUI macro plugin. No GitHub Release, Actions artifact, GitHub CLI authentication or downloaded executable is involved. Vendor SDKs are kept in `vendor/<vendor>/<platform>/`, copied into the app bundle under `Contents/Frameworks/Vendors/<vendor>/`, architecture-checked against the app executable, and signed as nested code before the app bundle is signed. The AmScope backend resolves the bundled SDK first and then standard per-user/machine installation paths; the UI never asks the user to browse for a dylib. Proprietary binaries remain local unless redistribution is licensed.

Hosted GitHub Actions run platform-neutral model/state/core/runtime tests on Linux and backend/package plus app-compilation validation on macOS. CI does not supply the local app binary and does not establish physical camera compatibility.

## 2. Package and executable boundaries

Current dependency direction:

```text
AmcamImagingApp
  ├── AmcamCameraModel
  ├── AmcamImagingCore
  ├── AmcamImagingRuntime
  ├── AmcamImagingGenTLAdapter
  └── AmcamImagingState
        ├── AmcamCameraModel
        └── AmcamImagingRuntime

AmcamImagingGenTLAdapter
  ├── AmcamCameraModel
  ├── AmcamImagingCore
  ├── AmcamImagingRuntime
  └── GenTLRouter
        ├── GenTLNative
        ├── AmcamGenTL
        │     └── GenTLAPI + GenTLABI
        └── GenTLAPI + GenTLABI

amcam-camera-probe
  ├── AmcamGenTL
  │     └── GenTLAPI + GenTLABI
  └── AmcamCameraProbeSupport (versioned diagnostic report schema)
```

Library-owned camera lifecycle and discovery boundary:

```text
AmcamImagingApp
  ├── CameraSessionLifecycle (AmcamImagingRuntime)
  │     ▲
  │     └── GenTLRuntimeDevice (AmcamImagingGenTLAdapter)
  └── AmcamCameraProvider (AmcamImagingGenTLAdapter)
        └── GenTLRouter
              └── AmcamGenTL
```

Rules:

1. The app must not import or instantiate `AmcamCameraDriver` or `AmcamCameraSession`.
2. GenTLRouter owns provider contexts and generic discovery. AmcamImagingGenTLAdapter owns AmScope SDK registration, camera metadata mapping and opaque runtime-device candidate creation; active camera session and acquisition ownership belong to AmcamImagingRuntime.
3. Camera-independent contracts remain in GenTLAPI/GenTLABI.
4. Vendor SDK behavior remains in AmcamGenTL.
5. Camera feature taxonomy, model profiles and hardware-evidence capability resolution belong in AmcamCameraModel. AmcamImagingState combines those contracts with runtime feature readbacks to produce tested camera control snapshots and resolution state; it has no AppKit or GenTL dependency. AmcamImagingApp is a presentation/command adapter and must not import GenTLABI, GenTLAPI or GenTLRouter.
6. Pixel-format validation and backend-neutral image-frame values belong in AmcamImagingCore.
7. Camera device opening, session ownership, acquisition start/stop, frame delivery and ordered cleanup belong in AmcamImagingRuntime. Camera control-state construction belongs in AmcamImagingState. GenTLRouter is bridged through AmcamImagingGenTLAdapter; the UI only sends commands and consumes events/frames.
8. Do not create fake executables for library-only packages. Add a CLI only when it provides a real diagnostic or operational use case.

## 3. Immediate implementation sequence

### Phase A — Source build and local launch

- [x] Add a root Makefile with explicit app, probe, local build and local test targets.
- [x] Build the app from source with Swift Package Manager; do not download release binaries or Actions artifacts.
- [x] Replace the SwiftUI application shell with AppKit so Command Line Tools builds do not require the SwiftUI macro plug-in.
- [x] Assemble and ad-hoc sign a local `Amcam Imaging.app` bundle.
- [x] Hosted macOS package matrix and fixture-SDK app build/package/sign validation passed on source baseline commit `4f4a8ca` ([Actions run 44860717992](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44860717992)); `macos-version-0.3` additionally validates lifecycle regressions and the structured probe-report target.
- [x] Remove SDK file selection from the AppKit UI; the GenTL backend resolves the AmScope SDK from its managed vendor directory.
- [x] Copy vendor SDK files into the app bundle and sign packaged dylibs before signing the application.
- [ ] Validate the packaged AmScope dylib and all transitive dependencies on the target Mac; hosted CI cannot validate the proprietary local binary.
- [x] Run `make run` on the target Mac and verify the app opens; the existing-process relaunch path was also exercised successfully on 2026-11-21.

Acceptance: a clean macOS 13+ checkout with Apple's Swift compiler, macOS SDK and AppKit can build and launch with `make run`. Full Xcode, GitHub CLI authentication and downloaded binaries are not required. Actual AmScope camera access additionally requires the licensed SDK at `vendor/amcam/macos/libamcam.dylib` with its sibling runtime dependencies, or a supported machine-wide installation. `AMCAM_SDK_SOURCE` can select a build-time source path; `REQUIRE_AMCAM_SDK=1` makes the build fail if no SDK is found.

### Phase B — Physical MU503 acceptance

Run on the target Mac with the vendor SDK installed:

1. Enumerate and open the MU503.
2. Start continuous RGB8 acquisition and verify stable image delivery.
3. Stop and restart acquisition at least three times.
4. Verify ExposureAuto modes, fixed exposure range, setter and readback.
5. Verify analog gain percentage, setter and readback.
6. Close, disconnect, reconnect and reopen.
7. Record SDK version, model descriptor, camera firmware, macOS version, app commit and exact failure stage.

Acceptance: all steps pass on physical hardware. Hosted mock tests are not a substitute.

**Partial physical result (2026-11-21):** the user confirmed that `make run` exits an already-running app cleanly and launches the replacement, and that disconnecting/reconnecting the MU503 while the replacement app remains open recovers the camera session and re-enables Start. This closes only the process-relaunch and idle USB-reconnect checks. It does not close Phase B: sustained five-minute streaming, repeated start/stop, active-stream disconnect, feature setter/readback, and independent probe validation remain unverified. See [the hardware acceptance record](AMCAM_HARDWARE_ACCEPTANCE.md).

### Phase C — Acquisition correctness and diagnostics

- [x] Preserve the existing parent/child cleanup and retry semantics.
- [x] Add a 64-frame GenTL regression over one reused announced buffer; assert increasing frame sequence, changing pixel contents and exactly one buffer return per delivered frame.
- [x] Extend lifecycle coverage to four distinct acquisitions on one open device session (three stop/restart transitions), asserting one start, one stop and one close per acquisition.
- [x] Flush both Amcam camera-DDR and SDK-DLL frame caches (`AMCAM_OPTION_FLUSH`, option `0x3d`, value `3`) after successful `Amcam_Stop`; a later pull-mode start is gated until the flush succeeds.
- [x] Add a mock SDK regression that rejects pull-mode restart without the post-stop flush, plus an injected flush-failure test proving the pending flush is retried before the next Start.
- [x] Retain regressions for timeout recovery, stop/close races, copied-frame immutability and failed `DSQueueBuffer` not being retried with the same handle. The Producer may have accepted the first call despite its error status.
- [x] Add a versioned JSON report schema and `amcam-camera-probe --json`, including backend, SDK version/path, interface, model/display descriptor, stream payload, pixel-format code/namespace, image dimensions/stride, acquisition counters/timestamps, failure stage and cleanup errors.
- [x] Apply the GenTL 1.6 `ACQ_QUEUE_ALL_DISCARD` operation after stop/event unregistration and before `DSRevokeBuffer`; `ALL_TO_INPUT` leaves buffers in the input pool and is not a revocation-safe flush.
- [x] Make probe cleanup fail-fast and child-before-parent: stop, unregister events, discard queues, revoke buffers, then close stream/device/interface/transport/library. A release failure is recorded and blocks parent teardown.
- [ ] Run the JSON probe against the physical MU503 and verify discovery, open, acquisition and cleanup diagnostics with the proprietary SDK.
- [x] Keep hardware-specific facts explicitly distinguished from unsupported or unverified features.

Automated acceptance: GenTL close-order/retry tests, Amcam provider-buffer revocation integration, Amcam post-stop cache-flush and retry regressions, lifecycle regressions and probe report/cleanup tests must pass in hosted CI. Physical probe execution remains part of Phase B hardware acceptance; mock tests do not certify the camera. See the [GenTL 1.6 specification](https://www.emva.org/wp-content/uploads/GenICam_GenTL_1_6.pdf), sections 5.2.8–5.2.10.

### Phase D — Pixel-format implementation

Do not conflate sensor RAW formats with RGB formats.

- Implement a format registry driven by exact PFNC identifiers and the camera's SDK-reported supported-format list.
- Add independent decoders and tests for each selected format.
- Validate row stride, packing, payload length, bit alignment, endianness and odd-width behavior.
- Prioritize the actual MU503 formats observed during hardware acceptance.
- Keep RGB8 as the only enabled display decoder until each additional decoder has numerical and layout tests.

Acceptance: per-format fixtures pass exact pixel-value, stride and payload tests before the UI enables that format.

### Phase E — Feature model completion

- [x] Treat the latest descriptor for a feature name as authoritative; stale duplicate descriptors cannot re-enable reads, controls or writes.
- [x] Gate feature readbacks on descriptor availability and readability.
- [x] Validate writes against availability, writability, value kind, numeric bounds/increments, advertised enumeration values and declared vector cardinality.
- [x] Derive editable settings visibility, numeric slider ranges and enumeration choices from the active camera descriptors and model-profile capability policy.
- [x] Refresh state-dependent writability on acquisition start/stop events; verify resolution and pixel-format writes are disabled while streaming and restored after stop.
- [x] Clear stale settings visibility when camera state is absent or changes; expose manual exposure editing only after manual mode is read back.
- [x] Keep auto-exposure mode available independently of manual exposure range support; expose discrete frame-speed level as the fallback when precise FPS is not writable.
- Continue feature-by-feature from the supplied SDK wrapper and per-model runtime evidence.
- Keep symbol availability, model capability, successful runtime probe and application implementation as separate facts.
- Add tests before each feature implementation.
- Preserve vendor units and names where no SFNC-equivalent semantics are proven.
- Do not invent register maps, GenApi XML, ranges or feature availability.

Acceptance: every visible control has a documented source, availability rule, units, range semantics, write behavior and readback test.

### Phase F — Native CTI backend integration

- Validate against at least one real vendor CTI Producer.
- Implement feature access only through a verified GenApi XML and GenTL port path.
- Keep the native Producer implementation separate from the Amcam SDK backend.
- Exercise discovery, device lifecycle, streams, announced buffers, events and error paths against the real Producer.

Acceptance: the same app workflow can select the CTI backend without Amcam-specific calls or fabricated GenApi behavior.

### Phase G — Cross-platform application boundary

The current executable and camera backends are macOS-specific. AppKit is only the macOS frontend; it is not a cross-platform UI framework.

- [x] Keep `NSWindow`, `NSImage`, bitmap conversion and full-screen behavior in the AppKit frontend. `NSOpenPanel` is not used to select native SDK libraries.
- [x] Remove AppKit types and window/file-panel operations from `CameraApplicationModel`.
- [x] Pass validated RGB8 frames to the frontend as a value object containing dimensions, row stride, bytes and a sequence number.
- [x] Extract validated RGB8 frame values and GenTL payload validation into the platform-neutral AmcamImagingCore package.
- [x] Add deterministic tests for RGB8 format identity, row padding, payload bounds, invalid dimensions and arithmetic overflow.
- [x] Extract monotonic-timestamp frame-rate estimation into AmcamImagingCore and test smoothing-window bounds, invalid timestamps and reset behavior.
- [x] Add AmcamImagingRuntime with async backend protocols, an event stream, strict child-before-parent cleanup, retryable ownership and generation-based stale-frame rejection.
- [x] Add deterministic fake-runtime tests for acquisition-close retry, device-close retry, startup rollback, timeout recovery, unsolicited stop, fatal-read cleanup, FIFO concurrent-close serialization, same-device idempotent open, feature-I/O-versus-close ordering, frame delivery and stale-frame suppression.
- [x] Prevent a failed GenTL buffer requeue from being retried implicitly; add a regression test that rejects a duplicate enqueue attempt.
- [x] Verify announced-buffer reuse by mutating the mock Producer's buffer after delivery and proving the earlier frame's copied `Data` remains unchanged.
- [x] Add AmcamImagingGenTLAdapter to bridge GenTLRouter's synchronous device/acquisition sessions into the portable async lifecycle contracts; blocking reads run off the cooperative executor so stop/close can interrupt them.
- [x] Keep the opened backend session exclusively inside CameraSessionLifecycle; expose async feature descriptors/read/write through the lifecycle actor and queue backend operations FIFO against open/start/stop/close. Identified opens are idempotent for the same device and reject a different device until ordered close succeeds. Unexpected acquisition-stop and fatal-read transitions use the same queue.
- [x] Replace the AppKit model's direct acquisition task with the lifecycle coordinator and route device opening, session closure and acquisition operations through the adapter.
- [x] Move AmScope SDK registration, GenTL discovery and device metadata mapping into AmcamCameraProvider in the adapter; return model values plus opaque runtime devices, not GenTL handles.
- [x] Centralize hardware-evidence and model-profile capability resolution in AmcamCameraModel.
- [x] Add AmcamImagingState for testable control snapshots, readback conversion and resolution parsing; inject an async feature reader so it has no GenTL or AppKit dependency.
- [x] Validate feature writes against the current descriptor's existence, availability, writability and value kind before calling the backend.
- [x] Capture camera-selection generation and device identity when UI feature commands are submitted; discard stale writes rather than retargeting them to a replacement camera.
- [x] Bind acquisition start/stop completions and frame/lifecycle observers to the originating camera-selection generation so stale asynchronous completions cannot overwrite replacement-camera state.
- [x] Normalize numeric UI values against descriptor increments, including non-aligned maxima and floating-point decimal endpoints.
- [x] Gate every control and current-resolution readback on the current feature descriptor's availability and readability; never probe an unavailable or unreadable feature.
- [x] Exclude unavailable descriptors from generated control state as well, so stale ranges/options cannot expose controls for unsupported features.
- [x] Add state-resolver regression tests proving unavailable/unreadable features are not read and unavailable resolution features do not trigger backend I/O.
- [x] Keep observation boundaries explicit: lifecycle state changes use AsyncStream events, image delivery uses a latest-frame-only AsyncStream, and UI-facing camera/control state is published as value snapshots.
- [ ] Define platform-neutral camera application commands and state before adding another frontend.
- [ ] Evaluate each target OS's GenTL Producer loading, Amcam SDK availability, permissions, packaging and camera-driver support independently.
- [ ] Add another frontend only after its backend path is proven on that OS.

Do not describe the current application as cross-platform: the AppKit executable and native camera integrations remain macOS-specific, and the existing UI model still uses Combine. AmcamImagingCore and AmcamImagingRuntime are Foundation-only portable packages. AmcamImagingGenTLAdapter binds the runtime contract to the macOS GenTLRouter backend. The AppKit model delegates camera discovery to AmcamCameraProvider and device opening, acquisition, frame reading, feature discovery, typed feature reads/writes and resource cleanup to the runtime lifecycle. Backend session handles do not escape the lifecycle actor; backend operations wait on its FIFO ownership gate rather than failing merely because another UI command is in flight. Feature operations are asynchronous; the GenTL adapter runs blocking provider calls away from the UI executor and translates GenTL-specific feature types/errors into runtime contracts. AmcamCameraModel owns AmScope capability/profile policy, while AmcamImagingState derives control snapshots from typed runtime readbacks. The AppKit model is limited to presentation, user commands and view-facing state. This is a portable data/lifecycle/feature-contract foundation, not a portable camera driver. UI separation is progress toward portability, not proof of portable camera access.
### Phase H — Process relaunch and USB hot-plug recovery

**Purpose:** ensure a source rebuild starts a new application process with fresh provider/session ownership, and recover the selected camera after USB removal/re-enumeration without requiring an application restart.

Implementation delivered:
- [x] Before `make run` builds/launches, detect an existing app process, request normal termination through macOS, and wait for that process to exit.
- [x] Fail closed when the old process cannot be confirmed exited; do not force-kill it or launch a second camera owner.
- [x] Keep `make build-local` and CI fixture packaging side-effect-free with respect to an already-running app.
- [x] Poll camera discovery at low frequency for SDKs without a portable device-change notification.
- [x] Treat an incomplete enumeration as inconclusive: retain the current session during the failed scan, then recreate an idle session after a later complete scan, including when the camera returns with the same SDK identifier.
- [x] Recheck only live-stream capability while an idle session reports no usable data stream, allowing Start state to recover without re-reading every feature/control.
- [x] Preserve ordered acquisition/device/provider cleanup and retain native callback ownership until SDK stop succeeds.

Verification:
- [x] Hosted baseline run 44860717992 passed all six jobs; this includes compile/package tests, runtime/model/state tests, dependency-boundary checks, camera-probe build, and fixture-SDK app packaging/signing.
- [x] User-confirmed physical MU503 test: `make run` while an earlier process was open, followed by USB disconnect/reconnect while the new app remained open; the session recovered and Start became enabled.
- [ ] Test physical disconnect while actively streaming and verify the exact callback error and recovery sequence.
- [ ] Complete the remaining sustained-stream, repeated start/stop, feature readback and independent camera-probe checks from Phase B.

CI verifies compilation and mock/runtime contracts; the user-confirmed result verifies only the reported physical recovery sequence. There is no claim that the entire Phase B hardware checklist is complete.

## 4. Verification policy

- A green hosted package-test matrix proves the tested source and mock behavior compile and pass on the CI runner.
- An app artifact proves that the executable was built and packaged.
- Neither proves that a physical camera works.
- Every implementation increment must add or update tests first, run the focused test, then run the full affected package suite and hosted matrix.
- If local Xcode is unavailable, use hosted macOS CI and report the exact jobs that passed. Never describe unexecuted local tests as passed.
