# GenTLAPI

GenTLAPI is the single application-facing GenTL contract shared by the native CTI backend and the Amcam SDK backend.

## Authority

The pinned EMVA GenTL 1.6 C header imported by GenTLABI is the authority for ABI declarations: function names and signatures, types, constants, enumerations, structures, packing and handle definitions. The GenTL specification defines the behavioral semantics that the header cannot express.

GenTLAPI must not maintain a parallel, independently authored copy of these declarations. Its operations must preserve GenTL function meaning, module ownership, output-parameter behavior, error results and lifecycle semantics. Any Swift-safe convenience API must remain a thin layer over the standard contract.

**Transition status:** the GenTLABI package is now a shared dependency of GenTLAPI, GenTLNative and AmcamGenTL. The native loader's function-pointer aliases now refer to the imported PGC/P* typedefs from the header. However, the current GenTLAPI source still contains a manually authored Swift protocol, function groups and type definitions; it does not yet expose an API contract derived from the imported declarations. Do not treat the dependency wiring or native alias conversion as completion of that API conversion.

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
