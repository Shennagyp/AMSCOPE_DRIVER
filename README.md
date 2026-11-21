# AMSCOPE_DRIVER

Swift-first camera access library for macOS.

## Architecture

The application uses one GenTL API contract with two interchangeable implementations:

1. **GenTLNative** loads manufacturer-supplied GenTL Producer libraries (.cti) and calls their actual exported GenTL C functions.
2. **AmcamGenTL** implements the same GenTL operations by translating them to the Amcam SDK. It does not create, export or require an AmScope .cti file.

**GenTLRouter** registers and discovers backend devices. AmcamImagingGenTLAdapter maps discovery candidates and adapts GenTL sessions/features to the portable runtime contract. **AmcamImagingRuntime** exclusively owns device opening/closing, acquisition lifecycle and typed feature I/O; the app sends commands to the runtime and consumes events and frames. Camera domain types and capability policy live in AmcamCameraModel, while control snapshots and descriptor-gated readbacks live in AmcamImagingState. The app's CameraApplicationModel exposes validated RGB8 frames as a value type and contains no AppKit window or image APIs; the AppKit frontend owns bitmap conversion, windows and full-screen behavior. Vendor SDK discovery, path resolution and loading belong to the backend libraries, never to a UI file picker. This is a UI boundary, not a claim that the current app or camera backends are cross-platform.

## Run from source

From the repository root on a Mac running macOS 13 or later with Apple's Swift toolchain available:

```sh
make run
```

`make run` builds every Swift library package in this repository, then builds the app executable through Swift Package Manager, assembles a local `Amcam Imaging.app` bundle, ad-hoc signs it and launches it. It does not download binaries, use GitHub Releases, require GitHub CLI authentication, or depend on a hosted Actions artifact. Before launch, the script detects an existing `amcam-imaging` process, requests an orderly quit through macOS, and waits for that process to exit. If the old process does not exit, the script stops rather than force-killing it or launching a competing camera owner. `make build-local` remains build-only and does not close an already-running app.

The full Xcode application is not required. The application UI uses AppKit rather than SwiftUI, avoiding the SwiftUI macro plug-in that is missing from some Command Line Tools installations. Apple's Swift compiler, AppKit SDK and macOS SDK are required. If `swift` is unavailable, install Apple's Command Line Tools with `xcode-select --install`, then verify with `swift --version`. Vendor SDKs are placed under `vendor/<vendor>/<platform>/` and copied into `Contents/Frameworks/Vendors/<vendor>/` by the build script. The AmScope SDK uses `vendor/amcam/macos/libamcam.dylib`; the backend resolves the bundled copy first, then standard per-user and machine-wide installation paths. The build checks binary architectures and signs the bundled copy before signing the app. `AMCAM_SDK_SOURCE` can specify a build-time source path, and `REQUIRE_AMCAM_SDK=1` makes packaging fail if it is missing. No SDK file picker is exposed in the UI. Proprietary SDK binaries are not committed unless redistribution is explicitly permitted.

Other targets:

- `make build-local` — build all libraries and the app executable without launching the UI.
- `make run-probe` — compile and run the camera diagnostic from source; pass optional arguments with `PROBE_ARGS='--help'`.
- `make test-local` — run all Swift package test suites locally.

See [the next implementation plan](swift/docs/NEXT_IMPLEMENTATION_PLAN.md) for package boundaries, acceptance criteria and the implementation sequence. The `macos-version-0.3` baseline and its [release notes](swift/docs/MACOS_VERSION_0.3_RELEASE_NOTES.md), [application lifecycle guide](swift/docs/AMCAM_IMAGING_APPLICATION.md), and [physical MU503 acceptance record](swift/docs/AMCAM_HARDWARE_ACCEPTANCE.md) document process relaunch and USB reconnect recovery.

## Packages

- **GenTLABI** — shared imported C declarations from the pinned EMVA GenTL header, including ABI structure-layout checks. This is the single ABI source of truth.
- **GenTLAPI** — the one application-facing Swift protocol. It mirrors the GenTL function surface and uses the imported GenTL C ABI types; it is a contract, not a Producer implementation.
- **GenTLNative** — native GenTL Consumer implementation, dynamic CTI loading and C function dispatch.
- **AmcamCameraModel** — SDK-independent camera value types, capability descriptors, control snapshots and model-profile policy.
- **AmcamImagingCore** — platform-neutral RGB8 frames, generic camera payload values and frame-rate estimation; Foundation-only, with Linux CI coverage.
- **AmcamImagingRuntime** — backend-neutral async device/session/acquisition lifecycle with serialized operations, ordered cleanup, retryable ownership, reliable state events, latest-frame-only delivery and typed feature I/O; no AppKit, Combine, GenTL handles or vendor SDK dependency.
- **AmcamImagingState** — descriptor-gated feature readbacks, control snapshots, resolution parsing and feature-write validation; no GenTL or AppKit dependency.
- **AmcamImagingGenTLAdapter** — macOS GenTLRouter adapter implementing the portable lifecycle contracts; blocking GenTL reads execute away from Swift's cooperative executor so stop/close can interrupt them concurrently.
- **AmcamGenTL** — Amcam SDK-backed implementation of the same contract; it re-exports AmcamCameraModel for source compatibility.
- **GenTLRouter** — backend registration, discovery aggregation, backend-bound sessions, typed feature forwarding and generic GenTL data-stream acquisition.
- **AmcamImagingApp** — standalone macOS AppKit executable under `swift/Apps/AmcamImagingApp`; depends on AmcamCameraModel + AmcamImagingCore + AmcamImagingRuntime + AmcamImagingGenTLAdapter + AmcamImagingState, never on GenTLABI, GenTLAPI, GenTLRouter or AmcamGenTL. The AppKit model delegates discovery to AmcamCameraProvider and device opening, acquisition start/stop, frame reading, feature reads/writes and cleanup to AmcamImagingRuntime through the adapter. The frontend only consumes lifecycle events and frames.

The shared GenTLABI package is extracted. GenTLAPI declares all 64 GenTL 1.6 operations as a Swift protocol using imported C ABI types and raw GenTL-style return codes. GenTLNative forwards those calls to the actual C function pointers exported by dynamically loaded .cti Producers. GenTLRouter and application code call the Swift protocol; they do not call C function pointers directly. Both backends implement the same contract. A source-level prototype comparison found exact signature matches; build, runtime and device verification remain pending. Older typed-handle and throwing convenience helpers remain internal behind BackendConvenience SPI.

## Implementation plan

The native backend binds to the real GenTL C ABI rather than reimplementing a CTI Producer. GenTLAPI is intentionally a Swift protocol mirror used as the application's stable contract; it does not export C symbols or replace the Producer. The pinned GenTL 1.6 C header is authoritative for function signatures, types, constants, structures and ABI layout. The GenTL specification remains authoritative for runtime semantics.

See [the GenTL implementation plan](swift/docs/GENTL_IMPLEMENTATION_PLAN.md) for the architecture rules, package dependency graph, phases, current status and completion criteria.

## GenTL Producer discovery

The native backend reads the standard macOS GENICAM_GENTL64_PATH environment variable. Additional directories or individual .cti paths can be supplied explicitly. CTI paths are normalized to prevent registering the same library more than once under aliases.

The native consumer validates the GenTL 1.0 required exports and resolves later-revision functions according to the pinned header. An absent optional extension is reported as not implemented; it does not invalidate a Producer that supports the required base API.

## Amcam capability boundary

Amcam feature controls are accessed through the vendor SDK. The current Amcam integration does not have a verified remote register map or GenApi XML port. GenApi port/URL operations therefore remain unsupported rather than simulated. The Amcam implementation must not invent serial numbers, timestamps, register behavior, chunks, multipart data, flows or other capabilities.

## Standards baseline

- EMVA GenICam GenTL 1.6 C API and specification.
- GenTL SFNC module-information conventions where applicable.
- PFNC pixel-format identifiers for image payload metadata.

This project does not claim formal GenTL certification. Compatibility depends on the Producer, device, SDK and behavior actually verified.
