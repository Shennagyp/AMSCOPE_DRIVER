# Next implementation plan

## 1. Delivery contract

The repository contains reusable SwiftPM libraries and two executable products:

| Product | Package | Purpose | Entry point |
|---|---|---|---|
| Imaging application | `swift/Apps/AmcamImagingApp` | User-facing camera application | `amcam-imaging` |
| Camera probe | `swift/Packages/AmcamGenTL` | Headless backend and hardware diagnostic | `amcam-camera-probe` |

The library packages are not standalone applications and must not acquire artificial `main` entry points merely to make them appear runnable. They are consumed by the executable products and tested through their own package test targets.

The repository-level Makefile is the supported command interface:

- `make run`: download and launch the latest hosted Apple Silicon imaging-app artifact for `macos-version-optimization`.
- `make run-probe`: download and execute the latest hosted camera-probe artifact.
- `make build-local`: build the app with the local Swift toolchain.
- `make run-local`: build and launch the app locally.
- `make test-local`: run all six Swift package test suites locally.

The default `make run` path deliberately uses the hosted macOS build. It requires macOS 13+, Apple Silicon, GitHub CLI (`gh`) and an authenticated GitHub CLI session, but does not require a local Xcode installation. Local build/test targets require a compatible local Swift toolchain and Apple SDK; they are optional and are not prerequisites for `make run`.

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

### Phase A — Make the repository runnable

- [x] Add a root Makefile with explicit app, probe, local build and local test targets.
- [x] Add an Xcode-free hosted-artifact launcher for the default run path.
- [ ] Verify the launcher against a fresh successful workflow artifact on an Apple Silicon Mac.
- [ ] Add a CI contract check that the app and probe artifacts are uploaded with the exact names expected by the launcher.
- [ ] Add a small smoke check that the app bundle contains an arm64 executable and that the probe executable is present.

Acceptance: a clean checkout can run `make run` after GitHub CLI authentication, without Xcode or a manually copied artifact.

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

### Phase G — Multiplatform decision

Do not begin multiplatform work before macOS physical acceptance. First isolate platform-specific dynamic loading, camera presentation, image display and packaging boundaries. Then decide whether a separate platform adapter is needed; do not move the GenTL contract or vendor SDK semantics into UI code.

## 4. Verification policy

- A green hosted package-test matrix proves the tested source and mock behavior compile and pass on the CI runner.
- An app artifact proves that the executable was built and packaged.
- Neither proves that a physical camera works.
- Every implementation increment must add or update tests first, run the focused test, then run the full affected package suite and hosted matrix.
- If local Xcode is unavailable, use hosted macOS CI and report the exact jobs that passed. Never describe unexecuted local tests as passed.
