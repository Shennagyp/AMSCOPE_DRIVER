# Amcam multiplatform refactor plan

## Decision and sequencing

The first milestone is physical acceptance on the user's Apple Silicon Mac using the packaged application. Multiplatform changes begin after this baseline passes. This avoids changing the camera ABI, streaming lifecycle, and UI architecture simultaneously while the first physical camera integration remains unverified.

The full Xcode application is not required for the local macOS build: Apple's Swift compiler, macOS SDK and AppKit SDK are sufficient. Hosted CI performs package tests and app compilation validation. The user's Mac builds and launches the app with `make run`, then connects the physical camera for hardware acceptance.

## Current platform coupling

The current package contains three distinct concerns:

1. **Camera model and policy** — device identity values, model flags, feature groups, profiles and capability resolution are extracted into AmcamCameraModel.
2. **Frame and runtime contracts** — validated frame values and rate estimation are in AmcamImagingCore; device/session/acquisition lifecycle and typed feature contracts are in AmcamImagingRuntime.
3. **Application state** — descriptor-gated control snapshots, readback conversion and feature-write validation are in AmcamImagingState.
4. **Backend adaptation** — AmcamImagingGenTLAdapter maps GenTLRouter discovery, feature and acquisition contracts to the portable runtime.
5. **Native SDK loading** — AmcamGenTL still performs dynamic library loading and symbol resolution through Darwin; this is not yet a cross-platform loader.
6. **Application presentation** — the current macOS frontend uses AppKit and NSImage/NSBitmapImageRep. It is not a shared cross-platform UI target.

These must not be combined into one cross-platform target.

## Target package boundaries

### 1. AmcamCameraModel and AmcamImagingCore

These platform-neutral packages already exist.

AmcamCameraModel contains:
- camera/device model values and identity metadata;
- model feature flags and feature groups;
- camera profiles and hardware-evidence capability resolution.

AmcamImagingCore contains:
- validated RGB8 frames and backend-neutral frame payloads;
- pixel-format/payload validation;
- monotonic frame-rate estimation.

Neither package may import Darwin, Glibc, WinSDK, AppKit, SwiftUI or platform graphics types.

### 2. AmcamABI

C declarations and ABI layout verification for the vendor API.

- Keep fixed-width integer fields and explicit structure packing/alignment assertions.
- Keep C-string handling bounded.
- Keep callback signatures and frame structures defined once.
- Do not invent an Amcam GenTL Producer or a GenApi register map.

The C target must be compiled and layout-checked on each supported platform.

### 3. AmcamLoader

A narrow platform-specific dynamic-library abstraction:

- macOS: \`dlopen\`, \`dlsym\`, \`dlclose\` through Darwin.
- Linux: \`dlopen\`, \`dlsym\`, \`dlclose\` through Glibc.
- Windows: \`LoadLibraryW\`, \`GetProcAddress\`, \`FreeLibrary\` through WinSDK.

Loader lifetime must be coupled to all native function pointers, camera handles, callbacks, and in-flight acquisitions. Never unload a library while a session or callback can still execute code from it.

Optional symbols remain optional. A missing optional symbol must disable only the corresponding feature, not prevent the camera from opening.

### 4. AmcamImagingRuntime, AmcamImagingState and AmcamImagingGenTLAdapter

These packages already separate backend-neutral runtime behavior from AmScope policy and GenTL implementation details.

- AmcamImagingRuntime owns device/session/acquisition lifecycles, serializes feature I/O against lifecycle transitions, retains failed resources for retry, and publishes backend-neutral events/frames.
- AmcamImagingState converts descriptors and typed readbacks into control snapshots and validates writes without GenTL or AppKit dependencies.
- AmcamImagingGenTLAdapter adapts GenTLRouter and the Amcam backend to runtime protocols. Blocking GenTL calls execute away from the cooperative executor so stop/close can interrupt a pending frame read.
- AmcamGenTL remains the AmScope-specific SDK implementation and native dynamic loader.
- Keep exposure, gain, white balance, pixel format and frame-rate features independently probed. Hardware-unsupported controls must remain unavailable.
- Do not expose OS-specific image objects or GenTL handles through the runtime contracts.

### 5. Imaging presentation

The imaging interface consumes platform-neutral camera models, runtime commands/events, typed feature contracts and frame values.

The current macOS target uses AppKit. Other operating systems require their own presentation target unless a deliberate shared UI technology is selected. Do not put NSImage or AppKit in camera model, frame, state or runtime packages.

The first shared UI contract should expose camera list, current camera/session state, frame stream, capability groups, control descriptors, and typed setting commands. A presenter converts the raw frame into the platform's display surface.

## Supported-platform decision gates

The refactor must not claim a platform is supported merely because the Swift compiler can compile the source.

For each OS/architecture combination, verify:

1. vendor Amcam SDK binary exists for that OS and architecture;
2. vendor binary exports the required symbols and reports the expected ABI/version;
3. C structure sizes, alignments, and callbacks match the vendor SDK;
4. dynamic loading and SDK lifetime work;
5. camera enumeration/open/control/streaming/close pass on real hardware.

Initial CI matrix proposal:

| Target | CI build/test | Physical camera |
|---|---|---|
| macOS arm64 | Required | MU503 first acceptance |
| macOS x86_64 | Only if vendor SDK still ships x86_64 | Required before claiming support |
| Linux x86_64 | Required after loader split | Required before claiming support |
| Windows x86_64 | Required after WinSDK loader implementation | Required before claiming support |

Do not add iOS, Android, Linux ARM, or Windows ARM to the support claim without matching vendor SDK availability and hardware tests.

## TDD migration gates

The refactor is performed in small steps with behavior-preserving tests:

1. Add protocol-conformance tests against the existing macOS Amcam implementation before moving it.
2. Extract value types and capability registry into AmcamCore; keep the current macOS tests green.
3. Extract the loader interface; run missing-symbol, library lifetime, callback-after-close, and concurrent-session tests.
4. Add Linux loader implementation and Linux ABI tests; macOS behavior must remain unchanged.
5. Add Windows loader implementation and Windows ABI tests.
6. Add platform frame-display adapters without changing camera frame bytes or stride semantics.
7. Build each app shell with its platform UI technology and run the shared UI-contract tests.

Do not perform a broad mechanical rewrite. Each extraction needs a failing test first, followed by the smallest code move and full regression suite.

## Current non-goals

- Rewriting the Amcam vendor SDK.
- Converting Amcam into a GenTL Producer.
- Pretending GenTL register-port or GenApi XML support exists when the vendor SDK does not expose it.
- Changing camera streaming semantics during the first physical acceptance cycle.
- Bundling vendor SDK binaries without redistribution permission.
- Requiring the user to install Xcode or a local compiler.

## Exit criteria

The multiplatform refactor is complete only when shared behavior tests pass on every claimed platform, each platform loader has ABI and lifetime coverage, each platform app builds in CI, and physical camera validation exists for every claimed OS/architecture pair.
