# GenTL Swift API and backend implementation plan

**Branch:** swift-gentl-api  
**Plan status:** Phases 1–5 implemented at source level; build, runtime and conformance verification remain pending  
**Standards baseline:** EMVA GenICam GenTL 1.6, with versioned functions identified by the pinned header

## 1. Objective

Keep one application-facing Swift protocol that mirrors the GenTL function surface, while binding the native CTI backend to the actual standard GenTL C ABI. The Swift protocol is the application's call contract; it does not implement or export a GenTL Producer. The CTI supplies the native function implementations. Imported C declarations remain authoritative for ABI types and native function-pointer signatures.

The checked-in GenTL 1.6 C header is the authority for:

- Function names, signatures, calling conventions and return types.
- Handle types and opaque-handle semantics.
- Enumerations, constants, structures, packing and field layouts.
- Revision ownership of functions and data structures.

The standard specification remains authoritative for behavioral semantics that cannot be established from declarations alone. Header upgrades must be deliberate, versioned and reviewed.

## 2. Required architecture

There is one GenTL contract and two interchangeable implementations.

### GenTLAPI

The sole application-facing GenTL API contract.

It is the stable application-facing Swift contract and mirrors the GenTL function surface and semantics. Its declarations are checked against the imported C declarations. ABI-level argument and return types come from GenTLABI; do not create independent copies of GenTL enums, constants, structures or handle representations when the header already defines them.

The public operations must preserve GenTL naming, module ownership, parameter meaning, output-parameter behavior, error results and lifecycle semantics. Any safer Swift conveniences must be thin additions over this contract; they must not replace or redefine the GenTL operations.

### GenTLNative

A GenTL Consumer implementation for manufacturer-supplied CTI Producer libraries.

- Load a CTI library dynamically.
- Resolve the actual GenTL C exports using the function declarations and function-pointer types from the shared ABI module.
- Require the complete GenTL 1.0 base function set before accepting a Producer.
- Resolve later-revision functions according to the pinned header and Producer capability.
- Forward calls without changing their ABI, argument meaning or error semantics.
- Preserve the existing safe handle, event, stream and library-lifetime rules.

This is real GenTL C interoperability. The native backend must not simulate a Producer using a Swift-only API.

### AmcamGenTL

A second implementation of the same GenTL operations, translated to the Amcam SDK.

- It does not create, export or impersonate a CTI Producer.
- It does not call GenTLNative or route through a synthetic CTI library.
- It must implement the shared GenTL contract directly.
- It reports only capabilities that the SDK can actually provide.
- Unsupported operations return the appropriate GenTL error; they must not fabricate register maps, GenApi XML, chunks, multipart data, flows or other capabilities.
- Amcam-specific driver, camera, session and SDK details remain internal to the package.

### GenTLRouter

Selects and owns backend contexts, aggregates discovery, and returns candidates and sessions bound to the implementation that created them.

The application uses the common GenTL contract and does not branch on vendor SDK types.

## 3. Package dependency correction

The current GenTLABI C target is nested inside the GenTLNative package. That makes the ABI declarations structurally owned by the native implementation even though the API contract and Amcam implementation also need the same declarations.

Move the ABI target and its header into a standalone Swift package:

- GenTLABI — the shared C module containing the pinned GenTL header and ABI layout checks.
- GenTLAPI — depends on GenTLABI and defines the single application-facing contract.
- GenTLNative — depends on GenTLABI and GenTLAPI.
- AmcamGenTL — depends on GenTLABI and GenTLAPI.
- GenTLRouter — depends on GenTLAPI, GenTLNative and AmcamGenTL.

The header must exist in one authoritative location. Do not copy it into multiple packages.

## 4. ABI and API binding rules

1. Import the checked-in GenTL header through the GenTLABI Clang module.
2. Use the imported C types, constants, enumerations and structures wherever the header defines them.
3. Use the header's dynamic-loading function-pointer typedefs for CTI calls where possible. Avoid retyping each C function signature by hand.
4. Keep dynamic symbol resolution in GenTLNative. The header declares the function ABI; a CTI file supplies the implementation at runtime.
5. Do not confuse a Swift protocol or wrapper with a GenTL C Producer. AmcamGenTL is a Swift backend for the common contract, not a binary CTI Producer.
6. Keep GenTL C error results and output-parameter semantics observable at the GenTL contract boundary. Swift convenience methods may translate them only in a clearly separate layer.
7. Do not use independently invented enum raw values, structure layouts, packing, pointer ownership or calling conventions.
8. Keep versioned additions tied to the revision in which the header introduces them. Absence of an optional later-revision export must not be treated as absence of the GenTL 1.0 base API.
9. Do not classify a function as optional or required by guesswork. The pinned header and corresponding GenTL revision define the mapping.
10. Do not claim GenTL certification or full device compatibility without the applicable conformance evidence.

## 5. Function revision policy

The native loader validates the GenTL 1.0 base export set before accepting a CTI Producer. EventGetDataInfo is part of the GenTL 1.0 base and is required.

Later functions are resolved according to their standard revision and the pinned header:

- GenTL 1.1: port URL enumeration and stacked port register operations.
- GenTL 1.3: buffer chunk data.
- GenTL 1.4: parent-module queries.
- GenTL 1.5: buffer-part enumeration and information.
- GenTL 1.6: composite buffers, stacked buffer information, flows and buffer segments.

An absent later-revision function is reported as not implemented when invoked. The Producer's supported GenTL revision must be queried from the Producer; the revision represented by the shared API contract does not prove that every Producer supports every later function.

## 6. Implementation phases

### Phase 0 — Establish the source of truth

- Keep one pinned GenTL 1.6 header.
- Record its source, license notice, revision and content hash in the repository.
- Review the relevant GenTL specification for semantics not expressed by C declarations.
- Maintain an explicit function/revision inventory derived from the header.
- Confirm the required GenTL 1.0 exports and the later-revision additions.

**Exit condition:** the header, revision inventory and source provenance are documented and internally consistent.

### Phase 1 — Extract the shared ABI package

**Status: completed on 2026-11-20.** The shared package, package dependencies and removal of the former nested ABI copy are committed on this branch.

- Move the GenTL C target, header and layout-check source into GenTLABI.
- Keep the header byte-for-byte unchanged during the move.
- Expose the ABI module as a package product.
- Rewire GenTLAPI, GenTLNative and AmcamGenTL to depend on that one product.
- Remove the old nested copy from GenTLNative.

**Exit condition:** all three packages import the same GenTL C declarations from one location; there is no duplicate header.

### Phase 2 — Correct the GenTLAPI contract

**Status: implemented at source level.** GenTLAPI now declares the 64 functions from the pinned header using imported GenTL ABI types, raw pointers, output parameters and GC_ERROR return values. A source-level comparison against the 64 C prototypes found exact parameter and return-type matches. The older typed-handle, decoded-info and throwing convenience helpers remain behind BackendConvenience SPI for internal backend use. They are not the application-facing GenTL contract.

- Audit every public type and operation against the imported header.
- Replace hand-maintained duplicates with imported C declarations.
- Align function operations with the standard names, signatures, module boundaries and error semantics.
- Preserve the GenTL output-buffer sizing pattern and opaque handles.
- Keep any Swift-safe convenience layer thin and secondary.
- Remove API concepts that have no GenTL source or are only duplicate abstractions.

**Exit condition:** every public GenTL operation and ABI-relevant type has a traceable source in the pinned header or the standard specification.

### Phase 3 — Bind the native CTI implementation

**Status: implemented at source level.** All 64 native GenTLAPI methods are present and their signatures match the common protocol. The dynamic function table uses the 64 PGC/P* typedefs imported from the pinned header. Optional later-revision symbols still return GC_ERR_NOT_IMPLEMENTED when absent. Mock-CTI and real-Producer runtime verification remain outstanding.

- Bind the native loader to imported function-pointer typedefs.
- Verify every required symbol against the GenTL 1.0 inventory.
- Verify each optional symbol against its revision.
- Keep dynamic symbol lookup and C-call mechanics isolated in GenTLNative.
- Preserve the existing producer, module, event, buffer and library lifetime safeguards.
- Exercise the native implementation against a controlled mock CTI library and, separately, real vendor CTIs when available.

**Exit condition:** native calls use the actual GenTL C ABI and no independently maintained signature table can drift from the header.

### Phase 4 — Map the Amcam implementation

**Status: implemented at source level.** AmcamGenTL provides all 64 GenTLAPI operations. It translates supported calls to the Amcam SDK, uses opaque pointer tokens for GenTL handles, preserves event payloads for buffer-too-small retries, and reports unsupported capabilities explicitly. Hardware/SDK runtime verification remains outstanding.

- Make AmcamGenTL implement the corrected common contract.
- Translate only operations with verified SDK equivalents.
- Preserve GenTL ownership, queue, acquisition, timeout and event semantics as far as the SDK permits.
- Return precise unsupported/not-available errors for capabilities the SDK does not expose.
- Keep vendor-specific SDK objects out of the common public API.
- Treat GenApi XML/register-port integration as a separate milestone requiring verified documentation.

**Exit condition:** Amcam uses the same GenTL contract as the native backend, with no fabricated capabilities and no CTI requirement.

### Phase 5 — Integrate the router

**Status: implemented at source level.** Public candidates and sessions now expose the raw GenTLAPI contract and C-style handles. The router retains backend-bound lifecycle ownership internally; its BackendConvenience SPI is not the application-facing API.

- Keep one initialized context per registered backend.
- Preserve context and handle ownership across discovery refreshes and open sessions.
- Retain the existing duplicate-registration, rollback, quarantine and failed-close protections.
- Ensure candidates and sessions remain bound to their originating backend.
- Keep application code independent of implementation-specific types.

**Exit condition:** repeated discovery, concurrent lifecycle operations and failed cleanup cannot cause use-after-close, duplicate initialization or backend confusion.

### Phase 6 — Verify conformance and remove duplication

**Status: pending verification and cleanup.** A raw-contract default test has been added, but no Swift build or tests have been run. Mock CTI coverage, real Producer checks, Amcam SDK/hardware verification and removal of the transitional SPI convenience layer remain outstanding.

- Run the same contract tests against both implementations wherever the operation is applicable.
- Add ABI layout and imported-type checks against the pinned header.
- Test exact required/optional symbol resolution with mock CTI libraries.
- Test unsupported Amcam operations and capability reporting.
- Test buffer ownership, event cancellation, acquisition, close ordering and failure cleanup.
- Remove redundant handwritten declarations, stale documentation and misleading claims.
- Record unimplemented standard functions explicitly.

**Exit condition:** one source of truth, one shared API, two implementations, and tests that detect semantic drift.

## 7. Existing work to preserve

The architecture correction does not discard valid implementation work. Preserve and re-audit:

- CTI discovery, path normalization, dynamic loading and required/optional symbol resolution.
- Native producer handle and library lifetime safeguards.
- Router context reuse, registration identity and failure quarantine.
- Amcam buffer layout, queue ownership, acquisition and event synchronization.
- Honest reporting of unsupported Amcam register/GenApi functionality.
- Existing tests for lifecycle, path identity, event handling and buffer layout.

These components must be adapted to the corrected API contract where required; they are not permission to retain duplicate GenTL definitions.

## 8. Current implementation status

The current branch contains:

- One standalone GenTLABI package and one unchanged pinned GenTL 1.6 header.
- GenTLAPI, GenTLNative, AmcamGenTL and GenTLRouter wired to the shared ABI package.
- A public Swift GenTLAPI protocol with all 64 function names declared by the header, using imported ABI types, pointer arguments, output parameters and GC_ERROR return values.
- A source-level signature comparison of all 64 C prototypes against GenTLAPI. All function names, argument types and return types matched.
- GenTLNative implementations for all 64 operations. Its dynamic function table uses all 64 PGC/P* function-pointer typedefs imported from the header.
- AmcamGenTL implementations for all 64 operations, translating supported operations to the Amcam SDK and returning explicit GenTL errors for unsupported capabilities.
- Opaque pointer-token handles for the Amcam backend, including retired-token handling to prevent handle-address reuse during the backend lifetime.
- Router candidates and sessions exposing the raw GenTLAPI contract and C-style module handles. Backend lifecycle orchestration remains internal to the router.
- A raw GenTLAPI default test for unsupported operations, in addition to the existing lifecycle, native catalog and Amcam frame-layout tests.

A transitional BackendConvenience SPI still exists for the earlier Swift-facing methods and custom typed handles used internally by backend and router lifecycle code. It is not the application-facing API and requires explicit SPI import. Removing that internal migration layer is still cleanup work; it must not be re-exported as another application camera abstraction.

No Swift build, unit test, mock CTI run, real Producer run or Amcam hardware run has been performed in this continuation. The source-level signature comparison is not a substitute for compiler, ABI-runtime or device conformance verification.

## 9. Definition of done

The work is complete only when:

- One pinned GenTL header is the authority for all ABI declarations.
- GenTLAPI is traceably aligned to the imported standard declarations and semantics.
- GenTLNative invokes actual CTI exports through matching C function-pointer types.
- AmcamGenTL implements the same contract directly through the Amcam SDK.
- No Amcam CTI, parallel camera abstraction or duplicated GenTL type system exists.
- Required and optional functions are classified by the correct GenTL revision.
- The router preserves backend and handle ownership through normal and failed lifecycles.
- Shared conformance tests pass for supported operations, and unsupported behavior is explicit.
- Documentation distinguishes implemented behavior, planned work and formal certification.



## 10. Verification research and dedicated test plan

The detailed engineering rationale, decision record, evidence policy, mock Producer design, operation coverage model, fault-injection catalogue, acquisition test sequence, risks, and verification ledger are maintained in:

- [GenTL Engineering Research Record](GENTL_ENGINEERING_RESEARCH.tex)
- [GenTL Test Development Plan](GENTL_TEST_DEVELOPMENT_PLAN.md)

These documents are complementary:
- The research record explains the architecture, decisions, assumptions, test model, limits, and evidence standard.
- The development plan defines the ordered implementation phases and their exit gates.

### Updated test strategy decision

A physical GenTL camera is not a prerequisite for most of the test program. The critical native boundary must be exercised with a compiled C Mock GenTL Producer loaded through the production `GenTLNative` dynamic loader. A Swift-only fake remains useful for isolated router tests but does not test `dlopen`, `dlsym`, C exports, calling conventions, native function pointers, or ABI-level pointer behavior.

The mock is a first-class deterministic test fixture. It must implement the required GenTL 1.0 base exports and a controlled subset of later behavior, expose test-only call recording and fault injection, and simulate a deterministic device/stream/buffer/event acquisition path. Build variants must test missing required symbols and absent optional later-revision exports.

All 64 protocol operations require an explicit test disposition. Native dispatch tests must verify operation identity, argument forwarding, output writes, buffer sizing, and exact `GC_ERROR` propagation. Amcam tests must use capability-aware expectations: the shared contract is common, but unsupported SDK capabilities must not be fabricated.

### Current test-target facts from source inspection

The package manifests currently define test targets inside `GenTLAPI`, `GenTLNative`, `GenTLRouter`, and `AmcamGenTL`. The `GenTLAPI` package already has a test source file that exercises legacy typed convenience values and constants. That file alone does not establish exhaustive tests of all raw protocol defaults. The native package manifest declares `GenTLNativeTests`; its test source location and current coverage must be inspected before adding fixture code.

No build or test command has been executed as part of this documentation update. The new documents specify work and acceptance criteria; they do not claim that the mock Producer or expanded tests already exist.

### Immediate next phase

Proceed with T0 in `GENTL_TEST_DEVELOPMENT_PLAN.md`: inspect the actual source and test target layout, establish a reproducible package build baseline, and derive the 64-operation and required/optional symbol inventories from the pinned header. Only then implement the C mock fixture and native dispatch tests. Do not create a parallel package hierarchy if the existing package test targets can host the fixture cleanly.


### Raw protocol-default test update (2026-11-20)

`swift/Packages/GenTLAPI/Tests/GenTLAPITests/GenTLAPITests.swift` now contains an empty `GenTLAPI` conformer and one explicit assertion for each of the 64 protocol requirements. Each default operation is expected to return `GenTLABI.GC_ERR_NOT_IMPLEMENTED`. A source-level name comparison found 64/64 operations represented exactly once. This test has not yet been compiled or run; it is source coverage, not passing test evidence.


### Native mock integration increment (2026-11-20)

The native package now contains a C Mock Producer fixture and integration tests that compile it as a macOS dynamic library at test runtime, load it through the production `GenTLNativeImplementation`, and call it through `GenTLAPI`. The initial tests cover a distinctive `GCGetInfo` return code plus output pointer writes, rejection of a CTI missing required `GCGetInfo`, and safe handling of an absent optional GenTL 1.1 export. The fixture currently exports the 47 names in the loader's required-symbol list; most are stubs, so discovery and acquisition simulation are not implemented yet.

See `GENTL_TEST_DEVELOPMENT_PLAN.md` and `GENTL_ENGINEERING_RESEARCH.tex` for the detailed work log. These tests have not been compiled or executed. Source-level inventory comparison is not test-pass evidence.


### Exhaustive native dispatch source coverage (2026-11-20)

The C Mock Producer now exports all 64 pinned GenTL functions. The native integration test invokes 58 operations through `any GenTLAPI` and asserts unique per-export return codes and native call counts; `GCReadPort` and `GCWritePort` receive separate sentinel argument and memory-forwarding tests; the four lifecycle operations (init, close, event register, event unregister) are exercised explicitly. The fixture supports variants that omit the required `GCGetInfo` symbol or all 17 optional later-revision symbols. A separate output-pointer test checks `GCGetInfo` writes and error propagation.

Static source comparison confirms 64 header declarations, 64 protocol requirements, 64 mock exports, and complete dispatch-test enumeration. These are not compiler or runtime results. Execution is still pending on macOS/Xcode.


### Native argument and memory sentinel expansion (2026-11-20)

The native mock now checks more than function identity. `GCGetInfo` validates its command and output writes; `GCReadPort` validates an opaque handle, 64-bit address, output pointer/capacity, and payload write; `GCWritePort` validates the handle, address, input pointer, exact bytes, and size. The all-operation dispatch matrix has 58 unique return-code assertions, these two additional port probes, and four lifecycle calls, with call counters covering all 64 operations. Full argument permutation and output-buffer coverage remains outstanding.
