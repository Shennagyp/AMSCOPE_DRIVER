# GenTL verification and development plan

**Branch:** \`swift-gentl-api\`  
**Companion research record:** \`swift/docs/GENTL_ENGINEERING_RESEARCH.tex\`  
**Status:** implementation plan; no test execution is implied by this document  
**Priority:** native mock Producer and exhaustive native dispatch verification

## 1. Objective

Establish an automated test environment that validates the existing shared \`GenTLAPI\` contract and, especially, proves that \`GenTLNativeImplementation\` forwards calls through the actual GenTL C ABI to dynamically loaded CTI exports.

A physical GenTL camera is unavailable. This does not block ABI, loader, dispatch, protocol, router, or deterministic acquisition tests. The first major deliverable is a compiled C Mock GenTL Producer loaded by the production native loader.

## 2. Non-negotiable architectural constraints

1. Preserve the existing application-facing \`GenTLAPI\` protocol. Do not replace it or require application rewrites.
2. Keep one authoritative pinned GenTL header in \`GenTLABI\`.
3. Native tests must load a compiled shared library using the production \`dlopen\`/\`dlsym\` path. A Swift fake alone is insufficient.
4. The mock exports real GenTL C symbols with signatures derived from the pinned header.
5. Keep the Amcam SDK implementation independent; do not create an Amcam CTI.
6. Run common contract tests against both backends where meaningful, but use capability-aware expectations. Do not require unsupported Amcam features to behave like native Producer features.
7. Do not claim hardware compatibility, GenTL certification, or complete conformance from mock tests.
8. Keep \`BackendConvenience\` SPI internal during migration; do not expose it as a second application API.

## 3. Target repository layout

Adapt names to the existing package conventions after inspecting the actual manifests and test targets; do not create duplicate package roots unnecessarily.

\`\`\`text
swift/
├── Packages/
│   ├── GenTLABI/
│   ├── GenTLAPI/
│   ├── GenTLNative/
│   ├── AmcamGenTL/
│   └── GenTLRouter/
├── Tests/
│   ├── MockGenTLProducer/
│   │   ├── include/
│   │   │   └── MockGenTLProducer.h
│   │   ├── Sources/
│   │   │   └── MockGenTLProducer.c
│   │   └── README.md
│   ├── GenTLAPITests/
│   ├── GenTLABITests/
│   ├── GenTLNativeTests/
│   ├── GenTLRouterTests/
│   └── GenTLIntegrationTests/
└── docs/
    ├── GENTL_IMPLEMENTATION_PLAN.md
    ├── GENTL_ENGINEERING_RESEARCH.tex
    └── GENTL_TEST_DEVELOPMENT_PLAN.md
\`\`\`

The Mock Producer may be a C target integrated into an appropriate SwiftPM test package if that is the cleanest build arrangement. The essential requirement is that tests load the resulting shared library as a CTI through the real loader. The layout above is a logical organization, not a mandate to introduce a redundant Swift package.

## 4. Execution phases

### Phase T0 — Establish a reproducible build baseline

**Purpose:** know exactly what is being tested before writing a large fixture.

Tasks:
- Inspect every package manifest and existing test target.
- Record supported macOS deployment target and Swift/Xcode toolchain.
- Build each package and the aggregate package graph.
- Resolve compile errors before attributing failures to test logic.
- Confirm the pinned header path, revision, license notice, and SHA-256.
- Generate an authoritative 64-operation inventory from the header and compare it with protocol requirements and native function-table entries.
- Generate a required/optional symbol table by GenTL revision from the header/specification, not by assumptions.

Deliverables:
- reproducible build instructions;
- machine-readable operation/symbol inventory;
- baseline compile report.

Exit gate: all package targets compile, or every remaining blocker is isolated and documented.

### Phase T1 — Build the native Mock GenTL Producer

**Purpose:** exercise the real native loading boundary without a physical camera.

Tasks:
- Implement a C shared library using the pinned GenTL header.
- Export the complete required GenTL 1.0 base function set with exact ABI signatures.
- Implement deterministic minimal Producer, System, Interface, Device, Port, Data Stream, Buffer, and Event behavior.
- Export test-only \`MockCTI_*\` controls for reset, call recording, configurable return codes, delays, and fault injection.
- Add build variants that omit selected required symbols and optional later-revision symbols.
- Ensure symbols have correct visibility and calling convention.
- Compile for the actual host architecture and test the exact dynamic library path/name accepted by \`GenTLNative\`.

Initial topology:
- one Producer/System;
- one Interface;
- one Device;
- one Data Stream;
- configurable buffer count;
- deterministic frame metadata and byte payload.

Exit gate:
- production native loader loads and initializes the mock;
- required-symbol omission rejects it;
- absent optional symbols follow the documented policy;
- test controls can prove which native export was invoked.

### Phase T2 — Exhaustive native dispatch suite

**Purpose:** prove the Swift contract reaches the correct C function pointer without semantic drift.

For each of the 64 operations:
- invoke through an \`any GenTLAPI\` value backed by \`GenTLNativeImplementation\`;
- configure the mock to record invocation and arguments;
- use distinguishable sentinel values to detect argument reordering;
- assert output pointer writes and buffer-size semantics;
- configure and assert exact \`GC_ERROR\` propagation;
- test null and invalid arguments only where permitted by the standard;
- test missing optional symbol behavior where applicable.

Deliverables:
- one test disposition per operation;
- argument/output/error assertions;
- coverage report mapped to header revision and module ownership.

Exit gate: no operation is unaccounted for. A test may explicitly mark a feature unsupported or not applicable, but may not silently omit it.

### Phase T3 — Protocol and ABI verification

Tasks:
- test all default protocol implementations return the exact not-implemented error;
- verify defaults do not manufacture valid output data;
- compile-time check imported ABI types and native function-pointer typedefs;
- test relevant structure sizes, alignments, offsets, and packing against C-side measurements;
- verify enum/constants and handle assumptions against the pinned header;
- test C string and output-buffer sizing contracts.

Exit gate: Swift declarations compile against imported types and ABI checks pass on supported platforms.

### Phase T4 — Router and lifecycle testing

Tasks:
- duplicate/malformed backend registration;
- repeated discovery and refresh;
- multiple Producer registrations;
- mixed native and Amcam backends;
- candidate/session backend identity;
- session survival across discovery refresh;
- idempotent close;
- initialization rollback;
- failed-close quarantine and provider retention;
- concurrent discovery and independent session operations;
- stale handles and invalid lifecycle ordering.

Exit gate: no backend cross-routing, use-after-close, double initialization, or unsafe unload under tested scenarios.

### Phase T5 — Simulated acquisition integration

Implement and test the path:

\`\`\`text
Initialize
 -> Discover
 -> Open interface/device
 -> Open stream
 -> Allocate/announce buffers
 -> Queue buffers
 -> Start acquisition
 -> Wait for event
 -> Read event payload
 -> Validate frame metadata and bytes
 -> Requeue
 -> Stop
 -> Flush/revoke buffers
 -> Close stream/device/interface/Producer
\`\`\`

Tasks:
- deterministic frame sequence and payload generation;
- frame IDs, payload sizes, pixel format, dimensions, completeness status;
- event delivery and timeout behavior;
- buffer ownership transitions;
- multi-frame acquisition;
- stop and cleanup behavior;
- failure injection at every step.

Exit gate: complete simulated capture and all failure-path cleanup tests pass.

### Phase T6 — Amcam contract and mapping tests

Tasks:
- preserve existing frame-layout and lifecycle tests;
- add an internal injectable SDK-call boundary only if needed for deterministic tests;
- test GenTL-to-SDK argument mapping, units, ranges, output semantics, and errors;
- test opaque handle token lifecycle and stale-token rejection;
- test event payload retry and buffer ownership;
- verify unsupported GenTL features return the chosen precise errors;
- keep real SDK/hardware validation separate.

Exit gate: all supported mapping behavior has deterministic tests; unsupported capabilities are explicit and never fabricated.

### Phase T7 — Stress, sanitizers, and sample application

Tasks:
- repeated load/init/terminate cycles;
- repeated discovery/open/close cycles;
- multiple devices and streams;
- concurrent independent sessions;
- sustained queue/requeue acquisition;
- timeout/cancellation races;
- fault injection during cleanup;
- run suitable Address Sanitizer and Undefined Behavior Sanitizer configurations for the C fixture where supported;
- create or finish \`GenTLDemo\` to discover, open, capture a frame from, and close the simulated device.

Exit gate: bounded stress suite is repeatable, no known leaks or invalid lifecycle transitions are observed within its tested scope, and the demo operates against the mock.

### Phase T8 — Hardware compatibility (later)

When hardware becomes available:
- test at least one real vendor CTI and its reported GenTL version;
- test Producer load and discovery without assuming a connected camera;
- test actual device open and stream acquisition;
- record vendor, CTI version/hash, camera model/firmware, transport, OS, architecture, and test results;
- add further vendors and transport-specific cases incrementally.

This phase is not a prerequisite for completing the mock-based engineering test suite. It is a prerequisite for claims about the tested hardware/Producer combination.

## 5. Required mock control surface

The mock needs a test-only control API, separate from GenTL exports:

- reset all Producer state;
- query call count by operation;
- retrieve last-call argument record;
- configure a return code for a selected operation;
- configure delay/barrier for concurrency tests;
- enable/disable selected symbols in build variants;
- configure topology (initially one device; later multiple interfaces/devices);
- configure frame dimensions, format, payload, frame ID, and completeness;
- inject failures at lifecycle transitions;
- inspect outstanding handles, buffers, and event registrations.

Control API memory ownership must be explicit. Do not return pointers into mutable internal storage without a defined lifetime. Keep test-control ABI private to the test target.

## 6. Required test matrix

| Area | Minimum cases | Evidence |
|---|---|---|
| API defaults | all defaulted operations | exact error and output-state assertions |
| ABI | layouts, types, function pointer types | C/Swift compile and runtime measurements |
| Loader | valid, invalid, missing required symbols | production loader integration |
| Optional exports | absent later-revision functions | successful base load and not-implemented invocation |
| Dispatch | all 64 operations | call recording, sentinel arguments, output and error assertions |
| Strings/buffers | exact size, too small, null where permitted | required-size and retry behavior |
| Router | registration, discovery, sessions, rollback | lifecycle tests |
| Acquisition | announce, queue, start, event, frame, requeue, stop | deterministic frame assertions |
| Failure | every lifecycle boundary | state and cleanup assertions |
| Concurrency | independent sessions and discovery interactions | repeatable synchronization tests |
| Amcam | mappings and unsupported operations | injected SDK tests plus later hardware tests |
| Resource safety | load/unload, handles, buffers, events | sanitizer/stress reports |
| Demo | discover/open/capture/close | executable integration test |

## 7. Test implementation rules

- Derive the operation inventory from the pinned header; do not maintain a handwritten second list as the source of truth.
- Every test name should identify operation/module/revision or lifecycle transition.
- Use distinct sentinel values to detect argument order errors.
- Assert exact GenTL error values, not only success/failure.
- Never dereference memory in the mock beyond the caller-supplied size.
- Do not assume every function shares the same buffer-sizing rules.
- Test legal nullability; do not treat every null pointer as valid.
- Make mock state reset deterministic and isolate tests that share a loaded dynamic library.
- Do not run unsafe concurrent operations merely to create load; concurrency tests must reflect documented/implemented synchronization guarantees.
- Keep test fixture controls out of production API products.
- A passing test is evidence only for the tested code path and environment.

## 8. Reporting format

Every milestone report should include:
- commit SHA;
- OS and architecture;
- Swift and Xcode versions;
- C compiler and version;
- exact build/test commands;
- test targets and counts;
- pass/fail/skip totals;
- coverage mapping for the 64 operations;
- mock fixture version and build variant;
- sanitizer configuration/results;
- unresolved failures;
- explicit statement whether any physical device was used.

Do not report “all tests pass” without the above context.

## 9. Immediate next actions

1. Inspect actual package manifests and test targets; reconcile the proposed layout with the repository rather than creating a duplicate package hierarchy.
2. Establish a clean package build baseline.
3. Extract the 64-operation and required/optional export inventories from the pinned header.
4. Implement the minimal compiled Mock Producer with test-control exports.
5. Connect it to the existing production native loader.
6. Add dispatch tests operation-by-operation, starting with initialization, discovery, open/close, info/string operations, then events and stream/buffer operations.
7. Add fault-injection and acquisition tests after the core loader/dispatch path is proven.

**Do not begin by writing a large simulated camera implementation before confirming the current package graph compiles.** A small correct mock and verified loader boundary are more valuable than a broad but unbuildable fixture.


## 10. Work log — documentation and first executable test coverage

### Completed source changes

- Added `GENTL_ENGINEERING_RESEARCH.tex` as the detailed internal engineering research record.
- Added this development plan as the ordered implementation roadmap.
- Updated `GENTL_IMPLEMENTATION_PLAN.md` to link both documents and make the mock-Producer test decision explicit.
- Extended `GenTLAPITests.swift` with an empty protocol conformer and 64 explicit assertions: every one of the 64 `GenTLAPI` requirements is invoked through its protocol default and must return `GC_ERR_NOT_IMPLEMENTED`.
- A source-level consistency check compared the protocol method names with the new assertions: 64 declared operations, 64 assertions, no missing, unexpected, or duplicate operation names.

### Evidence boundary

The test source has been committed but has **not** been compiled or executed. The source-level count check proves coverage enumeration only; it does not prove Swift type-checking or runtime behavior. The next verification step is to run the `GenTLAPI` package tests in a Swift 5.10-compatible macOS environment and correct any compiler issues before treating this test as passing.

### T0 inspection observations

- `GenTLABI`, `GenTLAPI`, `GenTLNative`, `AmcamGenTL`, and `GenTLRouter` each have their own SwiftPM package manifest.
- `GenTLAPI` already has a test target and test source; augmenting it is preferable to creating a parallel test package for protocol defaults.
- `GenTLNative` already declares a `GenTLNativeTests` test target. The actual test source layout still needs to be enumerated before adding a C fixture.
- The pinned header is at `swift/Packages/GenTLABI/Sources/GenTLABI/include/GenTL_v1_6.h`.
- The native implementation uses imported `PGC*` / `P*` function-pointer typedefs and resolves native exports in `GenTLNativeImplementation.swift`.

T0 is therefore partially complete at the source-inspection level. Package compilation, the full header-derived symbol inventory, and the native test target layout remain open. Do not advance the mock fixture design on assumptions about those items.


## 11. Work log — first native CTI integration fixture

### Source changes committed

- Added `Tests/MockGenTLProducer/MockGenTLProducer.c`, a C shared-library fixture that includes the pinned `GenTL_v1_6.h`.
- The fixture exports the 47 entry points currently classified by `GenTLProducerLibrary.requiredEntryPoints`: 46 deterministic `GC_ERR_NOT_IMPLEMENTED` stubs and a custom `GCGetInfo` implementation.
- The custom `GCGetInfo` writes a known datatype, payload marker, and payload size, then returns the distinctive error code `-4321`. This makes argument/output/result forwarding observable across the real C ABI.
- The fixture supports `MOCK_OMIT_<symbol>` for every required base export, creating a malformed Producer variant for each required-symbol rejection test.
- Added `GenTLNativeIntegrationTests.swift`. It compiles the C fixture at test runtime with the macOS SDK compiler, loads the resulting `.cti` through `GenTLNativeImplementation`, and tests output and error forwarding.
- Added tests for missing required `GCGetInfo` rejection and absent optional `GCGetNumPortURLs` behavior. The latter asserts `GC_ERR_NOT_IMPLEMENTED` and that the caller's output sentinel remains unchanged.
- Updated the native test target dependencies to import `GenTLABI` and `GenTLAPI`, and used the existing test target rather than adding a parallel package.

### Source-level inventory check

The mock fixture's declared exports were compared against `GenTLProducerLibrary.requiredEntryPoints`: all 47 required names are represented, with no missing required symbol. This is a source comparison only; the compiler and dynamic loader have not yet executed.

### Test execution status

Not run. This environment has no checked-out working tree with a Swift/Xcode toolchain. The tests require macOS with Xcode command-line tools because they compile a Mach-O dynamic library at test runtime. The next operator must run:

```sh
swift test --package-path swift/Packages/GenTLNative
swift test --package-path swift/Packages/GenTLAPI
```

Record the exact Xcode/Swift versions and full output. Fix compiler errors before treating the native integration tests as evidence.

### Important scope limit

This first mock is intentionally a dispatch/loader fixture, not yet a simulated camera. All required base exports exist, but most return `GC_ERR_NOT_IMPLEMENTED`. It proves the intended test architecture and creates the first real C ABI dispatch test; it does not yet support Producer discovery or acquisition. The next mock increment should implement a minimal valid Producer/System/Interface/Device path, then stream/buffer/event acquisition.


## 12. Continuous integration baseline

Added `.github/workflows/swift-gentl.yml` for macOS 14. It records OS, Xcode, Swift, and Clang versions; builds `GenTLABI`; and runs the test suites for `GenTLAPI`, `GenTLNative`, `AmcamGenTL`, and `GenTLRouter`. The workflow is triggered by pushes and pull requests targeting `swift-gentl-api`, and can be manually dispatched from GitHub Actions.

The workflow file is committed, but no workflow run has been observed yet. Its existence is not evidence of a successful CI run. If GitHub Actions does not start automatically for the repository, check repository Actions settings and workflow permissions; do not treat the empty run list as a pass.


### Clarification to the initial T0 inventory

The native test directory already contained `GenTLProducerCatalogTests.swift` and `GenTLProducerLibraryTests.swift`; the earlier inspection only checked for a guessed filename, `GenTLNativeTests.swift`, and did not establish that the directory was empty. The existing suites already cover catalog path handling, the 47-symbol GenTL 1.0 base-set inventory, and later-revision optional-symbol classification. The new `GenTLNativeIntegrationTests.swift` extends those suites rather than replacing them. The actual directory now contains all three Swift test files plus the C fixture.


## 13. Work log — exhaustive protocol-to-native dispatch matrix

### Expanded mock Producer

The C fixture now declares all 64 GenTL exports from the pinned header, not only the 47 required base exports. It retains the loader policy distinction:
- 47 GenTL 1.0 base exports are present in the normal build; each can be omitted individually using its `MOCK_OMIT_<symbol>` compile-time flag.
- 17 later-revision exports can be omitted together using `MOCK_OMIT_OPTIONAL_EXPORTS`.
- Every ordinary stub returns a unique error value derived from its header operation index. A wrong function-pointer mapping therefore produces the wrong result instead of passing because every stub returns the same generic error.
- Stateful library/event functions return success where needed to let the native implementation complete a legal registration and shutdown sequence.
- A test-only `MockCTI_GetCallCount` export records actual C invocation counts by operation index. It is outside the GenTL ABI and is used only by tests.

### Expanded protocol/native test

Added `testEveryProtocolOperationDispatchesToItsMatchingNativeExport`. It:
1. loads the compiled fixture through `GenTLNativeImplementation`;
2. stores the implementation as `any GenTLAPI`;
3. initializes the Producer;
4. registers an event and validates the returned native handle;
5. invokes 58 other operations with type-correct neutral arguments and uses separate sentinel probes for GCReadPort and GCWritePort;
6. asserts each operation's unique native return code;
7. unregisters the event and closes the Producer;
8. reads the test-only C counters and asserts the expected native invocation count for every operation, including the internal `EventKill` call performed by unregister.

Together, the 58 unique-return operations, two port sentinel operations, and four explicit lifecycle operations cover all 64 protocol requirements. The existing output-pointer test remains separate and checks the custom `GCGetInfo` datatype, payload marker, output size, and error result. The optional-export negative test now builds the mock with all 17 later-revision exports omitted and verifies the API returns `GC_ERR_NOT_IMPLEMENTED` without modifying the output sentinel.

### Source-level consistency audit

A script compared:
- all 64 `GC_API` declarations in the pinned C header;
- all 64 `GenTLAPI` protocol requirements;
- all 64 exports in the mock fixture;
- all 60 non-lifecycle calls in the dispatch test, plus explicit init/register/unregister/close calls.

Results: 64 header operations, 64 protocol requirements, 64 mock exports, zero missing or extra exports, 58 per-operation unique-return assertions, two port sentinel assertions, and four explicit lifecycle assertions. This is static source inspection only.

### Current blocker and next gate

The C fixture and Swift tests have not yet been compiled or executed. The immediate next task is to run the macOS CI workflow or the package commands locally, fix every compile/runtime failure, and record evidence. Only after that gate should the mock grow into a simulated Producer/System/Interface/Device topology and acquisition pipeline.


### Argument and pointer-forwarding sentinels

The latest fixture revision adds three operation-specific ABI probes:
- `GCGetInfo` validates a distinctive command value and writes a known datatype, payload marker, and output size.
- `GCReadPort` validates a non-null opaque handle, a distinctive 64-bit register address, the output pointer, and its input capacity; it writes a known 32-bit payload.
- `GCWritePort` validates the same opaque handle/address and compares the exact input bytes and byte count.

The dispatch matrix now uses 58 unique per-operation return-code assertions, two explicit port sentinel tests, and four lifecycle operations. The call-counter checks account for all 64 protocol operations. This provides stronger evidence than neutral-argument dispatch alone, but it is not yet exhaustive argument permutation coverage for every function. The next testing increment should expand argument/output sentinel cases by signature family and then per operation, especially info buffers, event payloads, stream buffers, and composite/stacked structures.


### SwiftPM target isolation correction

The C fixture has been moved to the sibling path `Tests/MockGenTLProducer/`, outside `Tests/GenTLNativeTests/`. This is deliberate: the Swift test target must remain a Swift-only target. Keeping a `.c` file nested inside its source directory risks SwiftPM treating the test target as a mixed-language target or compiling the fixture as part of the test module. The test compiles the sibling C source explicitly at runtime with `xcrun clang`, then loads the produced dynamic library. This preserves a clean SwiftPM target boundary.


### Optional-export absence coverage expanded to all 17 functions

The optional-export test now builds a Producer with all 17 later-revision symbols omitted and invokes every corresponding Swift protocol method. It verifies each returns exactly `GC_ERR_NOT_IMPLEMENTED`. Where an operation has output parameters, the test initializes sentinel counts, sizes, datatypes, or opaque handles and asserts they remain unchanged. This catches accidental writes or fabricated outputs when a function pointer is absent, not merely loader acceptance.


### Required-export rejection matrix expanded to all 47 base symbols

The mock fixture now supports a compile-time omission flag for each required GenTL 1.0 symbol. The native integration suite iterates over the loader's authoritative `requiredEntryPoints` list, builds one fixture variant per symbol, and asserts that `GenTLNativeImplementation` rejects each variant with `missingRequiredSymbol` naming the exact omitted export. This replaces the earlier single-`GCGetInfo` negative test. It tests the full required-symbol inventory rather than relying on one representative missing symbol.


### ABI version/layout runtime assertion

Added a native integration test asserting the compiled header version code is GenTL 1.6.0 and `GenTLABI_LayoutValid()` succeeds. The ABI C target also contains compile-time `_Static_assert` checks for the packed event, register-stack, chunk, and GenTL 1.6 stacked-info structures. The runtime assertion ensures the layout-validation function is actually linked and callable.


### CI execution attempt and infrastructure blocker

The workflow was triggered by push (run 54, commit `8512306e3c8d0cbc731fe32869bae82fb0f3278a`). All four matrix jobs were marked failed within seconds. The job records show `runner_id: 0`, empty `steps` arrays, and no runner logs (the log endpoint returned BlobNotFound). Rerunning failed jobs produced the same result. Therefore the Swift build/test commands did **not** execute; this is not evidence of source compilation failure or test assertion failure.

The repository's GitHub Actions hosted-runner access must be enabled or repaired before CI can provide code evidence. A later workflow run added an Ubuntu contract-test job; that job also failed with runner_id 0 and no steps, so this is not specific to the macOS label. In the meantime, the exact local commands remain:
```sh
swift test --package-path swift/Packages/GenTLNative
swift test --package-path swift/Packages/GenTLAPI
swift test --package-path swift/Packages/AmcamGenTL
swift test --package-path swift/Packages/GenTLRouter
```
Run them on macOS with Xcode command-line tools and record toolchain details. Do not treat the current red workflow state as a code regression because no job step ran.


### Native argument fault-injection cases

Added negative-path tests for the sentinel operations:
- invalid `GCGetInfo` command returns its configured custom error and leaves datatype, payload, and size untouched;
- invalid `GCReadPort` address returns its configured custom error and leaves the output buffer and size untouched;
- invalid `GCWritePort` payload returns its configured custom error while preserving the caller's size value.

These cases test that argument validation failures and custom Producer errors cross the native function-pointer boundary unchanged and do not create false output data.
