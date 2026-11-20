# macOS version optimization plan

**Branch:** `macos-version-optimization`  
**Status:** plan only; implementation has not started  
**Method:** strict test-driven development (Red → Green → Refactor)  
**Platform scope:** macOS only. No Linux/Windows extraction in this branch.

## 1. Objective

Optimize and complete the existing macOS AmScope imaging application without redesigning the project architecture.

The application must use the existing shared GenTL contract and router:

```text
AmScope Imaging App
    -> GenTLAPI + GenApi feature access
    -> GenTLRouter
    -> selected backend
         -> GenTLNative (vendor CTI)
         -> AmcamGenTL (Amcam SDK)
```

The app must not instantiate `AmcamCameraDriver`, `AmcamCameraSession`, or call the vendor SDK directly. Device discovery, selection, opening, streaming and closing go through the router and the selected backend. Camera features are accessed through a common feature model, not vendor-specific UI branches.

This plan preserves the existing GenTL 1.6 protocol contract. The 64 GenTL operations remain the transport-layer interface; GenApi feature access is a complementary layer that interprets feature descriptions and uses the selected device's GenTL port. SFNC names and semantics should be used where the camera supports the corresponding standard features.

## 2. Verified baseline and constraints

The current source and documentation establish these facts:

- `GenTLAPI` mirrors all 64 operations in the pinned GenTL 1.6 header.
- `GenTLNative` forwards those operations to a vendor CTI.
- `GenTLRouter` selects and manages registered backends.
- `AmcamGenTL` implements the shared GenTL contract and maps acquisition behavior to the Amcam SDK.
- Amcam's existing SDK/session layer already implements exposure, automatic exposure, gain, white balance, pixel format and frame-rate controls, including capability/range checks and readback verification.
- The Amcam GenTL port currently returns `notImplemented` for register reads/writes and `notAvailable` for the port URL. It therefore does not currently expose those controls through a GenApi feature-node path.
- The imaging app currently imports `AmcamGenTL` and owns `AmcamCameraDriver` / `AmcamCameraSession` directly. This conflicts with the intended router-based application architecture.
- The existing Amcam package contains the app executable target, while GenTLRouter depends on AmcamGenTL. The app cannot simply add a dependency on GenTLRouter inside that same package without creating a SwiftPM dependency cycle.
- Existing mock-SDK tests already cover SDK control calls, ranges, readbacks and important session lifecycle cases. These tests are the starting regression baseline, not proof of real-camera acceptance.

### Non-negotiable constraints

1. Do not replace the GenTL 1.6 protocol with a custom camera protocol.
2. Do not add Amcam-specific exposure/gain methods to the standard 64-operation GenTL protocol.
3. Do not create fictitious physical register addresses or claim an undocumented register map exists.
4. Do not assume all AmScope camera models support the same features.
5. Do not remove existing working UI capabilities merely to simplify the backend migration.
6. Do not combine this work with the deferred multiplatform refactor.
7. Do not require the user to install Xcode. Builds and automated tests run on hosted macOS GitHub Actions.
8. Do not claim physical camera acceptance from mock tests or CI builds.

## 3. TDD execution rules

Every behavior change follows this sequence:

1. **Red:** add the smallest focused test that expresses the required behavior; run it and record the failing assertion/build result.
2. **Green:** implement only enough code to pass that test.
3. **Regression:** run the focused suite, then all affected package suites.
4. **Refactor:** simplify the implementation without changing behavior; rerun the same tests.
5. **Record:** update this plan or the engineering record with test names, CI run URL, result, and any limitation.

A test that has not been observed failing is not to be reported as a demonstrated Red phase. Existing tests are characterized as baseline/regression tests, not retroactively called TDD.

For each phase, keep the branch buildable. Do not combine package relocation, GenApi implementation, UI redesign and streaming changes in one commit.

## 4. Phased plan

### Phase 0 — Reconfirm the branch baseline

**Purpose:** establish the exact state before modifying behavior.

Tests and checks:
- Run existing `AmcamGenTL` tests on hosted macOS CI.
- Build `GenTLABI`, `GenTLAPI`, `GenTLNative`, `GenTLRouter`, and `AmcamGenTL` independently.
- Record the current test count and package build status.
- Confirm the workflow triggers on pushes and pull requests for this branch.
- Keep a baseline artifact of the current macOS app and camera probe.

Exit gate: a reproducible green baseline, or documented pre-existing failures with exact failing targets.

### Phase 1 — Router contract tests before application migration

**Purpose:** prove the existing router can provide the application lifecycle without leaking backend identity.

Add tests first for:
- backend registration and discovery through the router;
- candidate identity and selected backend identity;
- opening a candidate and retaining the correct API/device handles;
- stream/device close and repeated close behavior;
- discovery refresh while an already-open session remains valid;
- failure during initialization/open and cleanup;
- no accidental routing of a device operation to another backend.

Only fix router defects demonstrated by these tests. Do not add a second application-facing camera-driver abstraction.

Exit gate: router lifecycle and error behavior are deterministic under mock/fake backends.

### Phase 2 — Resolve the camera feature-access design

**Purpose:** expose standard camera features through the common application API while preserving the GenTL contract.

First establish the actual Amcam capabilities and the available GenApi path from authoritative SDK/header/documentation evidence. Do not infer support from symbol names alone.

TDD work:
- Add tests for feature discovery, feature type, access mode, unit, range, increment, enumeration values and availability.
- Add tests for model-specific feature absence and read-only/locked states.
- Add tests for setting exposure, auto exposure, gain, white balance and pixel format through the common feature interface.
- Assert the requested value is validated before a vendor call.
- Assert successful writes are followed by readback and mismatches surface as errors.
- Assert unsupported features are absent or explicitly unavailable; never return fabricated values.
- Assert feature errors preserve useful transport/backend error information.

Design decision gate:
- Prefer a real GenApi-compatible feature description and GenTL port when a verified mapping can be implemented correctly.
- If the Amcam SDK does not expose a physical register map/XML, do not invent one. Define a narrowly scoped feature-provider integration that presents the same typed feature semantics to the app while keeping the 64-operation GenTLAPI contract unchanged. Document precisely that this is SDK-backed feature access, not native GenApi port access.
- Native CTI devices should use their actual GenApi XML/port path. The application must not branch on Amcam SDK types.

Do not implement both approaches speculatively. First tests and evidence establish which path the Amcam backend can support.

Exit gate: a documented feature-access contract with passing tests for supported, unsupported, read-only, invalid-range and readback-mismatch cases.

### Phase 3 — Separate the app package to remove the dependency cycle

**Purpose:** allow the app to depend on GenTLAPI and GenTLRouter without making AmcamGenTL depend on its own router-dependent consumer.

TDD/build-first work:
- Add a package-boundary/build test or CI step proving the new app package can resolve and build with dependencies on GenTLAPI and GenTLRouter only.
- Move the macOS app executable target into a dedicated package under `swift/Apps/AmcamImagingApp`.
- Keep the Amcam driver library and camera probe in `swift/Packages/AmcamGenTL`.
- Verify the app package does not import or depend on AmcamGenTL directly.
- Preserve the existing app bundle identifier, executable name, deployment target and packaging behavior.

This is a dependency-boundary correction, not a redesign of the UI or camera model.

Exit gate: app builds from its own package and the package graph has no cycle.

### Phase 4 — Migrate the application model to GenTLRouter

**Purpose:** replace direct Amcam driver ownership with router-owned backend selection.

Tests first:
- app model discovers devices using the router;
- backend registration/configuration is explicit;
- selected device opens through the router;
- the model uses the candidate/session GenTLAPI for standard device and stream operations;
- app lifecycle closes stream, device and backend resources in the correct order;
- switching backend or SDK configuration cannot leave stale handles active;
- errors and no-device states are represented without crashing or silently retrying forever.

Then migrate `CameraApplicationModel` while preserving the existing SwiftUI views and interaction semantics. Keep macOS-specific AppKit image presentation in the app target; keep it out of GenTLAPI and backend packages.

Exit gate: no direct Amcam driver/session imports or calls remain in the app target; all device lifecycle and acquisition use the router-selected backend.

### Phase 5 — Connect the existing controls to the common feature interface

**Purpose:** retain current AmScope controls without vendor-specific application coupling.

Tests first:
- exposure auto/manual state and exposure-time units/ranges;
- gain state, units/ranges and readback;
- white-balance temperature/tint or RGB controls according to actual model capability;
- pixel format availability and acquisition-stopped requirement;
- frame-rate mode/range/increment where supported;
- controls hidden/disabled correctly when unavailable or locked;
- UI values refresh from authoritative readback rather than optimistic local state;
- a control failure does not corrupt unrelated controls or stop acquisition unless required by the device.

Then connect the existing controls UI to feature descriptors and typed commands. Keep feature metadata—not hard-coded model assumptions—as the source of labels, ranges, units and availability.

Exit gate: existing controls remain usable through the common feature interface and per-model capabilities are respected.

### Phase 6 — macOS application performance and lifecycle optimization

**Purpose:** optimize only after correctness is covered by tests.

Measure before optimizing:
- frame callback-to-display latency;
- UI main-thread occupancy during continuous acquisition;
- frame copy/allocation rate and peak memory;
- CPU use during sustained preview;
- start/stop/restart and close latency;
- discovery and camera-open latency.

Tests and instrumentation:
- deterministic frame delivery does not block the UI executor;
- frame buffers are not reused while the UI is reading them;
- bounded frame handoff prevents unbounded memory growth when rendering is slower than capture;
- dropped/replaced preview frames are counted and do not corrupt frame ownership;
- stopping acquisition cancels pending UI delivery safely;
- repeated start/stop/reconnect does not leak callbacks, buffers or SDK handles.

Optimize only measured bottlenecks. Preserve pixel format, stride, payload size, timestamp and buffer ownership semantics. Do not change the acquisition model merely to improve a benchmark.

Exit gate: before/after measurements are recorded and all lifecycle/frame correctness tests remain green.

### Phase 7 — CI completeness and release validation

Update GitHub Actions to:
- trigger on `macos-version-optimization` pushes and pull requests;
- build/test all affected Swift packages, not only AmcamGenTL;
- build the dedicated macOS app package and camera probe;
- produce the arm64 app artifact;
- run static checks and relevant sanitizer configurations where supported;
- retain logs and artifacts for each run.

Keep hardware acceptance separate. On the user's Mac, validate the packaged app with the MU503:
- discovery and identity;
- open/close and repeated start/stop;
- sustained live preview for at least five minutes;
- disconnect/reconnect;
- exposure and gain changes with SDK readback;
- all controls actually supported by that model;
- no false capability claims.

Exit gate: CI green and physical acceptance checklist recorded. CI alone does not satisfy hardware acceptance.

## 5. Required test layers

| Layer | Test mechanism | What it proves |
|---|---|---|
| GenTL contract | protocol/conformance tests | transport contract and error semantics |
| Router | deterministic backend fakes | backend selection and lifecycle |
| Amcam SDK mapping | compiled mock C SDK | symbol calls, argument mapping, ranges, readback and failures |
| Feature interface | fake feature provider + backend integration tests | feature types, access, units and capabilities |
| App model | model/presenter tests | state transitions and UI-facing behavior |
| App packaging | hosted macOS SwiftPM build | dependency graph and executable build |
| Hardware | MU503 acceptance checklist | actual camera/SDK behavior |

## 6. CI and local-environment policy

The user does not have Xcode and will not install it. Do not ask for local Xcode builds or debugging.

Use hosted macOS GitHub Actions for compilation and automated tests. The user-side validation is limited to downloading and running the packaged app and camera probe when physical-camera testing is needed. Clearly distinguish:
- source-level inspection;
- mock-SDK tests;
- CI build/test results;
- physical camera results.

Never report one category as proof of another.

## 7. Out of scope

- Linux or Windows support and loader extraction.
- Rewriting GenTLAPI's 64-operation protocol.
- Replacing GenTLRouter or introducing another router.
- Rewriting the UI or changing its visual design without a demonstrated usability defect.
- Replacing the Amcam SDK or implementing a new Amcam CTI Producer.
- Unverified register maps, fabricated GenApi XML, or guessed feature ranges.
- Unmeasured performance rewrites.
- Claiming formal GenTL/GenApi certification.

## 8. Completion criteria

This branch is complete when:
1. the application uses GenTLRouter and does not depend directly on AmcamGenTL;
2. the common feature interface exposes supported camera features with correct types, units, access and capability checks;
3. Amcam controls map to real SDK behavior and verified readback;
4. native CTI devices continue to use their own GenTL/GenApi feature path;
5. existing imaging and streaming behavior is preserved;
6. all relevant CI tests and app builds pass;
7. performance changes are supported by before/after measurements;
8. MU503 physical acceptance is recorded separately from CI results.

**Implementation order is strict:** baseline → router tests → feature-access decision/tests → package boundary → app router migration → feature UI integration → measured optimization → CI/hardware acceptance.

---

## Implementation log

### 2026-11-20 — Router contract test and CI expansion

**Code changes**
- Added `GenTLRouterRegistrationTests.swift` with coverage for lazy backend construction, duplicate backend identifiers, canonical non-empty identifiers, and provider-factory failure reporting.
- Kept invocation counters synchronized because backend factories are `@Sendable` closures.
- Expanded the macOS GitHub Actions package matrix to run tests for `GenTLAPI`, `GenTLNative`, `GenTLRouter`, and `AmcamGenTL`.
- Enabled push and pull-request validation for `macos-version-optimization`; documentation changes are now included in the workflow path filters.
- The existing app/probe packaging steps remain attached to the AmcamGenTL package until the app is extracted into its own package.

**TDD classification**
- These are router contract/characterization tests for behavior already present in the implementation. They are not represented as red-green tests for a new feature.
- No production behavior was changed in this step.
- Hosted macOS execution is required. No local Xcode build or test run was performed.

**Validation state**
- Source and workflow changes are committed to `macos-version-optimization`.
- GitHub commit status currently reports no status checks, and the available workflow-run lookup did not expose a push-triggered run. Therefore the tests are **not yet claimed as passing**.
- Next implementation gate: obtain a confirmed green hosted run, then add the routed application/session contract tests before changing application ownership from `AmcamCameraDriver` to `GenTLRouter`.

### 2026-11-20 — Typed feature contract and app package boundary

**Production code**
- Added `GenTLFeatureAccess` beside the unchanged 64-operation `GenTLAPI` contract. It carries typed values, descriptors, availability, access flags, units, numeric ranges and symbolic enumeration values.
- Added opaque feature-device identity so feature providers do not expose the transitional BackendConvenience handle types to application code.
- Added routed `GenTLDeviceSession` feature forwarding. Calls remain bound to the backend and device handle that created the session.
- Implemented the Amcam adapter for `ExposureAuto`, `ExposureTime` and `AmcamAnalogGainPercent`. It delegates to the existing `AmcamCameraSession` setters, so the SDK's validation and readback checks remain authoritative.
- Exposure time is writable only after automatic exposure is disabled. Amcam gain remains vendor-namespaced and percent-valued; it is not mislabeled as SFNC Gain in dB.
- The Amcam adapter reports model/runtime capability availability. It does not create register addresses or synthetic GenApi XML.
- Native CTI backends intentionally do not conform to the feature protocol until a real GenApi XML/port implementation is available.

**Tests added before the Amcam adapter implementation**
- Feature value kind and numeric-range validation.
- Descriptor metadata and vendor-specific feature naming.
- Amcam mock-SDK integration for exposure mode, exposure range, gain range, typed writes and readback.
- Router session forwarding and device-handle identity.

**Application package boundary**
- Moved the three imaging application source files into `swift/Apps/AmcamImagingApp`.
- Removed the app executable target from the Amcam backend package.
- The new app package depends on GenTLAPI, GenTLRouter and AmcamGenTL, eliminating the SwiftPM dependency-cycle obstacle to routing the application through GenTLRouter.
- Updated hosted macOS CI to build the standalone app package and to trigger on `swift/Apps/**`.

**Validation**
- No local Xcode or Swift build/test was run.
- The GitHub status endpoint currently reports no status checks for the latest workflow commit, and the available workflow-run lookup does not return push-triggered runs. Compilation and tests therefore remain pending hosted macOS CI.
- The app source has been moved but is not yet migrated: `CameraApplicationModel` still directly creates `AmcamCameraDriver` and `AmcamCameraSession`. The next implementation task is the routed application acquisition/session path, followed by migration of the existing controls to `GenTLDeviceSession` feature access.

**Additional lifecycle hardening**
- Routed feature calls are serialized against `GenTLDeviceSession.close()`.
- Feature access after session closure now fails deterministically with `deviceSessionClosed`, rather than forwarding a stale handle to the backend.
- Router lifecycle tests cover the owning device-handle identity and the closed-session boundary.

### CI correction cycle — 2026-11-20

The hosted macOS run for the preceding implementation did **not** pass. The first compile exposed incorrect assumptions in the router's use of imported C ABI types: GenTL handles are optional raw pointers at C out-parameter boundaries, and C enum constants must be converted to their ABI integer representation before comparing with `GC_ERROR`. The native test target also had corresponding C-enum/optional-handle typing errors and a brittle `Result.failure` assertion.

Corrections committed:
- Use `GenTLABI_ErrorFromCode` for GenTL error constants.
- Use optional pointer variables for `TLOpen`, `TLOpenInterface` and `IFOpenDevice` out parameters, then unwrap after checking the returned status.
- Preserve non-optional handle types once ownership is established.
- Normalize imported `INFO_DATATYPE` constants and `GC_ERROR` values in native integration tests.
- Replace the ambiguous `Result.failure` extraction with `XCTAssertThrowsError`.

These changes are a response to compiler diagnostics from the actual hosted run. They are not yet verified; the next hosted macOS run must establish whether the corrections compile and whether further test failures remain.



## 2026-11-20 — Camera model package boundary

Extracted Amcam camera value types, capability descriptors, control snapshots and model-profile policy into the SDK-independent `AmcamCameraModel` Swift package. AmcamGenTL imports and re-exports that package for source compatibility. AmcamImagingApp now depends on AmcamCameraModel, GenTLABI, GenTLAPI and GenTLRouter only; its sources no longer import AmcamGenTL. This keeps vendor SDK implementation ownership in the backend while preserving the UI's camera presentation types.


## 2026-11-20 — Isolated camera model package and test ownership

- Extracted `AmcamCameraModels.swift` and `AmcamCameraCapabilities.swift` into `swift/Packages/AmcamCameraModel`. The package has no Amcam SDK, C ABI or GenTL dependency.
- AmcamGenTL imports and re-exports AmcamCameraModel to preserve existing source-level access to public model types.
- AmcamImagingApp now depends on AmcamCameraModel, GenTLABI, GenTLAPI and GenTLRouter only. It no longer imports or depends on AmcamGenTL.
- Moved pure camera capability/profile tests to AmcamCameraModelTests. This makes the model package independently testable rather than relying on backend tests to validate backend-independent policy.
- Added AmcamCameraModel to the hosted macOS package test matrix and enforced the application dependency boundary in CI.
- The new package boundary is not considered validated until the current hosted workflow succeeds.



## 2026-11-20 — Hosted validation after model extraction

Hosted macOS workflow [44700221429](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44700221429) completed successfully on commit `628972c0da4c055df0eae1fae7d4693ef2c7e10d`.

- All five package test jobs passed: GenTLAPI, GenTLNative, GenTLRouter, AmcamCameraModel and AmcamGenTL.
- The Amcam camera probe release build and upload passed.
- The application dependency guard passed.
- The standalone routed app release build, app-bundle signature verification and arm64 executable check passed.
- Application artifact `amcam-imaging-macos-arm64`, artifact ID `14612188825`, expires 2026-12-04.

This is hosted software validation only. No local Xcode run or physical camera acceptance occurred. MU503 discovery, stream acquisition, exposure/gain changes, restart behavior and disconnect/reconnect still require hardware validation.


## 2026-11-20 — Routed application controls and typed integer vectors

- Extended the optional typed feature contract with `integerVector` values and descriptor `elementCount`. This supports multi-channel SDK features without encoding arrays as comma-separated strings or changing the GenTL 1.6 C ABI.
- Added Amcam SDK-backed descriptors and read/write mapping for color matrix, enumerated pixel formats, white-balance temperature/tint, three-channel RGB white-balance gain, fixed frame rate, discrete frame-speed level and discrete resolution.
- Resolution options preserve the exact SDK index and dimensions in the enumeration symbol. Resolution and pixel-format descriptors become non-writable while the camera session is streaming.
- The app now reads these controls only through GenTLDeviceSession and writes through the routed feature contract. Model-profile allow/deny policy is enforced at the app boundary as well as reflected in capability availability.
- SDK-specific validation remains in AmcamCameraSession: pixel formats must be in the camera-reported list; resolution must be a reported index; white-balance temperature/tint and fixed FPS use SDK wrapper ranges; RGB gain requires exactly three Int32 values and exact readback; frame-speed requires a valid model range.
- RGB white-balance exposes a vector length of three but no invented numeric range, because the SDK does not report one.
- Added test-first API and mock-SDK integration coverage for vector kinds, descriptor element count, RGB gain reads/writes, feature metadata and existing control readback.
- Hosted run [44703255740](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44703255740) passed all five package suites and the app build. App artifact ID: `14613319868`.
- Cleaned Swift concurrency and best-effort rollback warnings; the successful app build log contained no compiler warnings.
- No physical camera acceptance was performed. RGB8 remains the only app display decoder. Other PFNC formats, physical MU503 behavior and native CTI GenApi access remain separate acceptance items.
