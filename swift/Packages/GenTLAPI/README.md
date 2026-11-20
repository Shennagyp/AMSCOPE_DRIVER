# GenTLAPI

The public Swift API follows the EMVA GenTL 1.6 function model and module boundaries:

- Library
- System
- Interface
- Device
- Data Stream and Buffer
- Port (including GenTL 1.1 stacked register operations)
- Data Stream extensions (chunk, multipart, stacked buffer info, flows and segments)
- Signaling / Events

This is the sole application-facing camera API. It is not a second vendor-neutral abstraction.

## Two implementations

1. **GenTLNative** forwards operations to third-party `.cti` GenTL Producers through the GenTL C ABI.
2. **AmcamGenTL** maps the same Swift function surface to the Amcam SDK where equivalent operations exist. It does not create an AmScope `.cti`. Its raw camera driver, session, frame, control and error types are module-internal; only the GenTL implementation is exported from the package.

The Swift surface uses typed opaque handles and Swift values while preserving GenTL function names, module ownership, error codes and lifecycle semantics. It is not itself a C ABI and is not a GenTL Producer.

## Router lifecycle

`GenTLRouter` creates one initialized GenTL System context per registered backend and reuses it across discovery refreshes. Interface handles are opened once per interface ID and retained with the context, so a refresh does not reload the same `.cti` or reopen a Producer's module hierarchy while earlier candidates or sessions still exist.

Candidates and opened device sessions retain their provider context. Device sessions close their Device modules before the final context release closes Interfaces, the System, and the GenTL library. If a child handle cannot be closed, the Producer library is deliberately retained rather than unloaded underneath live native handles.

Manual registration also canonicalizes CTI and Amcam SDK paths. The same library cannot be registered twice under different backend IDs through the native/Amcam registration methods.

## Compatibility rules

- The API surface follows the GenTL 1.6 header.
- The native implementation resolves functions introduced in later GenTL revisions when the producer exports them. Missing versioned extensions return `GC_ERR_NOT_IMPLEMENTED`.
- The Amcam implementation maps only behavior the Amcam SDK can provide. Unsupported operations return the appropriate GenTL error, normally `GC_ERR_NOT_IMPLEMENTED` or `GC_ERR_NOT_AVAILABLE`.
- The Amcam SDK exposes feature getters/setters but no documented remote register map or GenApi XML port in the current implementation. Register and GenApi URL operations therefore remain unsupported.
- Backends must not fabricate capabilities, register behavior, chunks, flows or payload features.

The interface is GenTL-shaped at the Swift API level; it is not a drop-in binary implementation of the GenTL C ABI.
