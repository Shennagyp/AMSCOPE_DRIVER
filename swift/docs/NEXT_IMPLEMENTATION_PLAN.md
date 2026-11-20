# Next implementation plan

## 1. Delivery contract

The repository contains reusable SwiftPM libraries and two executable products:

| Product | Package | Purpose | Entry point |
|---|---|---|---|
| Imaging application | `swift/Apps/AmcamImagingApp` | User-facing camera application | `amcam-imaging` |
| Camera probe | `swift/Packages/AmcamGenTL` | Headless backend and hardware diagnostic | `amcam-camera-probe` |

The library packages are not standalone applications and must not acquire artificial `main` entry points merely to make them appear runnable. They are consumed by the executable products and tested through their own package test targets.

The repository-level Makefile is the supported command interface:

- `make run`: build every Swift library package, build the imaging app, assemble and ad-hoc sign its `.app` bundle, then launch it locally.
- `make run-probe`: build and run the Amcam camera diagnostic locally.
- `make build-local`: build every Swift library and the imaging app without launching it.
- `make run-local`: alias for `make run`.
- `make test-local`: run all six Swift package test suites locally.

The default `make run` path is a source build on the user's Mac. It requires macOS 13 or later, Apple's Swift compiler, the macOS SDK and AppKit. The full Xcode application is not required: the app uses AppKit rather than SwiftUI, so the build does not require the SwiftUI macro plugin. No GitHub Release, Actions artifact, GitHub CLI authentication or downloaded executable is involved. The vendor `libamcam.dylib` remains a separate runtime requirement for camera access.

Hosted macOS GitHub Actions remain responsible for package tests and app compilation validation. CI does not supply the local app binary and does not establish physical camera compatibility.

## 2. Package and executable boundaries

Keep the dependency direction:

```text
AmcamImagingApp
  -> AmcamCameraModel
  -> GenTLAPI + GenTLABI
  -> GenTLRouter
       -> GenTLNative
       -> AmcamGenTL
            -> AmcamCameraModel
            -> GenTLAPI + GenTLABI

amcam-camera-probe
  -> AmcamGenTL
  -> GenTLAPI
```

Rules:

1. The app must not import or instantiate `AmcamCameraDriver` or `AmcamCameraSession`.
2. Backend selection and session ownership remain in GenTLRouter.
3. Camera-independent contracts remain in GenTLAPI/GenTLABI.
4. Vendor SDK behavior remains in AmcamGenTL.
5. Camera UI and model-facing policy remain in AmcamCameraModel and AmcamImagingApp.
6. Do not create fake executables for library-only packages. Add a CLI only when it provides a real diagnostic or operational use case.

## 3. Immediate implementation sequence

### Phase A — Source build and local launch

- [x] Add a root Makefile with explicit app, probe, local build and local test targets.
- [x] Build the app from source with Swift Package Manager; do not download release binaries or Actions artifacts.
- [x] Replace the SwiftUI application shell with AppKit so Command Line Tools builds do not require the SwiftUI macro plug-in.
- [x] Assemble and ad-hoc sign a local `Amcam Imaging.app` bundle.
- [ ] Pass the hosted macOS app-build job on the latest branch commit.
- [ ] Run `make run` on the target Mac and verify the app opens.

Acceptance: a clean macOS 13+ checkout with Apple's Swift compiler, macOS SDK and AppKit can build and launch with `make run`. Full Xcode, GitHub CLI authentication and downloaded binaries are not required. The vendor `libamcam.dylib` is required for actual camera access.

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

### Phase C — Acquisition correctness and diagnostics

- Preserve the existing parent/child cleanup and retry semantics.
- Add sustained-stream tests for frame sequence, buffer reuse, timeout recovery and stop/close races.
- Make probe output structured and include backend, SDK version, model descriptor, pixel format, dimensions, stride, payload size and failure stage.
- Keep hardware-specific facts explicitly distinguished from unsupported or unverified features.

Acceptance: deterministic mock tests pass and physical probe output can diagnose discovery, open, acquisition and cleanup independently.

### Phase D — Pixel-format implementation

Do not conflate sensor RAW formats with RGB formats.

- Implement a format registry driven by exact PFNC identifiers and the camera's SDK-reported supported-format list.
- Add independent decoders and tests for each selected format.
- Validate row stride, packing, payload length, bit alignment, endianness and odd-width behavior.
- Prioritize the actual MU503 formats observed during hardware acceptance.
- Keep RGB8 as the only enabled display decoder until each additional decoder has numerical and layout tests.

Acceptance: per-format fixtures pass exact pixel-value, stride and payload tests before the UI enables that format.

### Phase E — Feature model completion

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

- [x] Keep `NSWindow`, `NSOpenPanel`, `NSImage`, bitmap conversion and full-screen behavior in the AppKit frontend.
- [x] Remove AppKit types and window/file-panel operations from `CameraApplicationModel`.
- [x] Pass validated RGB8 frames to the frontend as a value object containing dimensions, row stride, bytes and a sequence number.
- [ ] Move the application state model out of the executable target into a separately testable package with an explicitly chosen observation/event contract.
- [ ] Define platform-neutral camera application commands and state before adding another frontend.
- [ ] Evaluate each target OS's GenTL Producer loading, Amcam SDK availability, permissions, packaging and camera-driver support independently.
- [ ] Add another frontend only after its backend path is proven on that OS.

Do not describe the current application as cross-platform: the state model still uses Combine, the executable package targets macOS, and the current native camera integrations use macOS dynamic libraries. UI separation is progress toward portability, not proof of portable camera access.

## 4. Verification policy

- A green hosted package-test matrix proves the tested source and mock behavior compile and pass on the CI runner.
- An app artifact proves that the executable was built and packaged.
- Neither proves that a physical camera works.
- Every implementation increment must add or update tests first, run the focused test, then run the full affected package suite and hosted matrix.
- If local Xcode is unavailable, use hosted macOS CI and report the exact jobs that passed. Never describe unexecuted local tests as passed.
