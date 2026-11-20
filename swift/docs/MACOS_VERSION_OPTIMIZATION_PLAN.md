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
