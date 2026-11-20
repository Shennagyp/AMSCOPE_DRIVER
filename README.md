# AMSCOPE_DRIVER

Swift-first camera access library for macOS.

## Architecture

The application uses one GenTL API contract with two interchangeable implementations:

1. **GenTLNative** loads manufacturer-supplied GenTL Producer libraries (.cti) and calls their actual exported GenTL C functions.
2. **AmcamGenTL** implements the same GenTL operations by translating them to the Amcam SDK. It does not create, export or require an AmScope .cti file.

**GenTLRouter** selects and manages the backend. Application code uses the common GenTL contract and does not call vendor SDKs directly. There is no second camera abstraction.

## Packages

- **GenTLABI** — shared imported C declarations from the pinned EMVA GenTL header, including ABI structure-layout checks. This is the single ABI source of truth.
- **GenTLAPI** — the one application-facing GenTL contract; conversion of its current Swift wrapper to the imported GenTL declarations is in progress.
- **GenTLNative** — native GenTL Consumer implementation, dynamic CTI loading and C function dispatch.
- **AmcamGenTL** — Amcam SDK-backed implementation of the same contract.
- **GenTLRouter** — backend registration, discovery aggregation and backend-bound device candidates/sessions.

The shared GenTLABI package has now been extracted and the GenTLAPI, GenTLNative and AmcamGenTL dependencies are wired to it. The remaining transition is to convert the public GenTLAPI contract and its ABI-relevant types to use the imported declarations directly.

## Implementation plan

The implementation must bind to GenTL rather than recreate a parallel Swift version of it. The pinned GenTL 1.6 C header is authoritative for function signatures, types, constants, structures and ABI layout. The GenTL specification remains authoritative for runtime semantics.

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
