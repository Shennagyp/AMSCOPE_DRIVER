# GenTLAPI

The public Swift API follows the EMVA GenTL 1.6 C API and its module boundaries:

- Library
- System
- Interface
- Device
- Data Stream and Buffer
- Port
- Signaling / Events

This is the only application-facing camera API. It is not a second camera abstraction.

## Two implementations

1. **Native GenTL implementation** — loads third-party `.cti` GenTL Producers and forwards the GenTL function calls through the producer's C ABI.
2. **Amcam implementation** — exposes the same Swift GenTL function surface but maps supported operations to the Amcam SDK. It does not create an Amcam `.cti`.

The Swift surface uses typed opaque handles and Swift values while preserving GenTL function names, module ownership, error codes and lifecycle semantics. It is not itself a C ABI and is not a GenTL Producer.

Operations that the Amcam SDK cannot support must fail with the appropriate GenTL error, normally `GC_ERR_NOT_IMPLEMENTED` or `GC_ERR_NOT_AVAILABLE`. Unsupported operations must not be simulated.

## Initial scope

The first implementation slice covers library/system/interface/device discovery, data-stream setup and buffer acquisition, port access, and event operations. GenTL 1.6 extensions (composite buffers, flows, multipart and stacked buffer information) are tracked as explicit API-surface work; the public API must not claim full 1.6 conformance until those are implemented.
