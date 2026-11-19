# GenTLNative

Native GenTL Consumer implementation for macOS.

This package implements the shared `GenTLAPI` contract by loading manufacturer-supplied GenTL Producer libraries (`.cti`) and forwarding calls through their GenTL C ABI.

## Current implementation

- Loads a producer with `dlopen` and resolves the standard GenTL symbols.
- Forwards library, system, interface, device, data-stream, buffer, port and event operations.
- Preserves producer handles as opaque pointers.
- Uses the pinned GenTL 1.6 C declarations and validates the consumer-side ABI layouts before loading a producer.
- Implements GenTL 1.6 stacked buffer/part information using the standard packed structures.
- Resolves functions introduced by later GenTL revisions opportunistically. When a producer does not export a versioned extension, the corresponding Swift API call returns `GC_ERR_NOT_IMPLEMENTED`; it does not prevent use of the producer's supported baseline.

This package is a **GenTL Consumer**. It does not implement a GenTL Producer, does not create `.cti` files, and does not include camera-vendor SDKs.

## Header provenance

`GenTL_v1_6.h` is copied unmodified from the GenTL 1.6 header distributed with Aravis 0.9.2 at `src/gentl/GenTL_v1_6.h`. The upstream file identifies the GenICam GenTL Subcommittee copyright and carries its redistribution disclaimer. The same header is identified as byte-identical to the EMVA GenTL 1.6 reference header in the EMVA GenICam Package Version 2026.07.

- Upstream: https://github.com/AravisProject/aravis/blob/0.9.2/src/gentl/GenTL_v1_6.h
- Standard: https://www.emva.org/standards-technology/genicam/genicam-downloads/
