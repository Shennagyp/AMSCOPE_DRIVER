# AMSCOPE_DRIVER

Swift-first camera access library for macOS.

## Architecture

The application uses one GenTL API contract with two interchangeable implementations:

1. **GenTLNative** loads manufacturer-supplied GenTL Producer libraries (.cti) and calls their actual exported GenTL C functions.
2. **AmcamGenTL** implements the same GenTL operations by translating them to the Amcam SDK. It does not create, export or require an AmScope .cti file.

**GenTLRouter** selects and manages the backend. The target application architecture is GenTLAPI + GenTLRouter, with backend-specific behavior kept behind the selected implementation. The imaging app uses GenTLAPI through GenTLRouter. Its camera presentation models are isolated in AmcamCameraModel; the app package has no dependency on the Amcam backend implementation.

## Packages

- **GenTLABI** — shared imported C declarations from the pinned EMVA GenTL header, including ABI structure-layout checks. This is the single ABI source of truth.
- **GenTLAPI** — the one application-facing Swift protocol. It mirrors the GenTL function surface and uses the imported GenTL C ABI types; it is a contract, not a Producer implementation.
- **GenTLNative** — native GenTL Consumer implementation, dynamic CTI loading and C function dispatch.
- **AmcamCameraModel** — SDK-independent camera value types, capability descriptors, control snapshots and model-profile policy.
- **AmcamGenTL** — Amcam SDK-backed implementation of the same contract; it re-exports AmcamCameraModel for source compatibility.
- **GenTLRouter** — backend registration, discovery aggregation, backend-bound sessions, typed feature forwarding and generic GenTL data-stream acquisition.
- **AmcamImagingApp** — standalone macOS SwiftUI executable under `swift/Apps/AmcamImagingApp`; depends on AmcamCameraModel + GenTLABI + GenTLAPI + GenTLRouter, never on AmcamGenTL.

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
