# AMSCOPE_DRIVER

Swift-first camera access library for macOS.

The application uses one public **GenTL-shaped Swift API** with two interchangeable implementations:

1. **GenTLNative** loads manufacturer-supplied GenTL Producer libraries (`.cti`) and forwards the standard GenTL C API.
2. **AmcamGenTL** implements the same Swift API over the Amcam SDK. It does not require or generate an AmScope `.cti` file.

The application does not call vendor SDKs directly and does not maintain a second camera abstraction.

## Packages

- `GenTLAPI` — shared Swift function surface, GenTL handles, information types and error codes.
- `GenTLNative` — native GenTL Consumer, C ABI interop and `.cti` producer loading.
- `AmcamGenTL` — Amcam-backed implementation of supported GenTL operations.
- `GenTLRouter` — producer registration, discovery aggregation and backend-bound device candidates.

## GenTL producer discovery

`GenTLRouter.registerDiscoveredNativeProducers()` reads the standard macOS `GENICAM_GENTL64_PATH` environment variable. Additional directories or individual `.cti` paths can be supplied explicitly. Each producer is registered once under its normalized path.

The native consumer resolves versioned GenTL extensions when they are exported by a producer. Missing extensions return `GC_ERR_NOT_IMPLEMENTED`; they do not prevent the producer's supported base API from being used.

## Amcam limitations

Amcam feature controls are accessed through the vendor SDK. The current Amcam GenTL implementation supports discovery, device/session lifecycle, data-stream buffers, acquisition and buffer events. It does not expose a documented register map or GenApi XML port, so GenApi port/URL operations remain unsupported rather than being simulated.

## Standards baseline

- EMVA GenICam GenTL 1.6 API surface
- GenTL SFNC 1.2 module information conventions
- PFNC pixel-format identifiers for image payload metadata

The implementation preserves GenTL error and lifecycle semantics. A backend must report unsupported operations honestly.
