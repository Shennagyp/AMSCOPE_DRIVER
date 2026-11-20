# GenTLAPI

GenTLAPI is the single application-facing GenTL contract shared by the native CTI backend and the Amcam SDK backend.

## Authority

The pinned EMVA GenTL 1.6 C header imported by GenTLABI is authoritative for function names and signatures, ABI types, constants, enumerations, structures, packing and handle definitions. The GenTL specification defines runtime semantics that cannot be expressed in C declarations.

The public GenTLAPI protocol mirrors the 64 function prototypes in the pinned header:

- Imported GenTL C types and opaque pointer handles are used for ABI-level arguments.
- C output parameters, buffer pointers, string pointers and size parameters remain explicit.
- Every operation returns the GenTL GC_ERROR status code. The raw API does not replace the C return model with Swift throws or result wrappers.
- The common contract has no separate hand-maintained public enum, handle or info-value system.

A source-level comparison was performed against the C header declarations. All 64 functions matched by name, parameter types and return type. This is source inspection, not compiler or runtime verification.

The protocol is a Swift call contract over imported C types; it does **not** export C symbols and is not itself a GenTL Producer.

## Transitional backend SPI

The earlier Swift convenience function groups, typed-handle wrappers and decoded info values remain temporarily under the explicit BackendConvenience Swift Package Interface. They are used internally by existing backend lifecycle and mapping code. Application code must use GenTLAPI and must not import BackendConvenience. The transitional layer is scheduled for removal after the internal backend and router logic no longer depends on it.

## Implementations

1. **GenTLNative** loads a manufacturer-supplied .cti Producer, resolves its GenTL C exports and forwards operations through the actual C ABI. The native backend must use function-pointer declarations that match the pinned header.
2. **AmcamGenTL** implements the same GenTL contract by mapping supported operations to the Amcam SDK. It does not create an AmScope .cti file and is not a binary GenTL Producer.

The application uses GenTLAPI. It does not call Amcam SDK types directly or maintain a second camera abstraction.

## Standard module groups

The shared contract follows the GenTL module structure:

- Library
- System
- Interface
- Device
- Data Stream and Buffer
- Port
- Signaling and Events
- Versioned Data Stream and Port extensions

Function ownership and revision must follow the standard. For example, stacked port register operations belong to Port, while chunk, multipart, flow and segment operations belong to the relevant Data Stream extensions.

## Backend rules

- GenTLNative requires the complete GenTL 1.0 base export set. EventGetDataInfo is part of GenTL 1.0 and is required.
- Functions introduced in later revisions are resolved according to the revision in which the standard defines them. A missing optional later-revision export returns the corresponding not-implemented error.
- The API revision does not prove that every loaded Producer implements every function in that revision. Query the Producer's own reported GenTL version and capabilities.
- AmcamGenTL maps only behavior supported by verified Amcam SDK functionality. Unsupported operations return an honest GenTL error.
- The current Amcam integration has no verified remote register map or GenApi XML port. Register and GenApi URL operations remain unsupported; feature getters/setters exposed by the SDK are not automatically equivalent to GenApi node access.
- Backends must not fabricate register behavior, serial numbers, timestamp validity, chunks, multipart data, flows, segments or other capabilities.

## Router and lifecycle

GenTLRouter creates one initialized System context per registered backend and reuses it across discovery refreshes. Interface handles are opened once per interface and retained with the context.

Candidates and opened device sessions retain their originating backend context. Device sessions close child modules before the final context release closes Interfaces, System and the native library. If a child handle cannot be closed, the Producer library is retained rather than unloaded beneath live native handles or callbacks.

Manual registration canonicalizes CTI and Amcam SDK paths so aliases cannot register the same library more than once. Router cleanup failures quarantine the affected backend context rather than risking unsafe reinitialization.

## Conformance boundary

The Swift GenTLAPI contract is not itself a GenTL Producer and does not export the GenTL C ABI. Only GenTLNative invokes the binary C API exported by third-party CTI Producers. AmcamGenTL is an SDK-backed implementation of the shared contract.

Neither backend is claimed to be formally certified. See CONFORMANCE.md for current capability mapping and limitations, and the repository-level GenTL implementation plan for the target architecture and remaining phases.
