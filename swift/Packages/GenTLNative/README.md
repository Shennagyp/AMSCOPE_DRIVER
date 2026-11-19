# GenTLNative

Native GenTL Consumer integration for macOS.

The package loads manufacturer-supplied `.cti` GenTL Producers and resolves their exported GenTL C functions. It does not implement a Producer and does not contain any camera-vendor SDK.

## Current implementation

- Loads a CTI dynamic library with `dlopen`.
- Verifies the required GenTL library/system entry points.
- Resolves exported GenTL symbols by their standard names.
- Uses the EMVA GenTL 1.6 reference C header for ABI declarations.

The module-to-Swift-function forwarding layer is the next implementation milestone. Do not treat symbol loading alone as a working GenTL Consumer.

## Header provenance

`GenTL_v1_6.h` is copied unmodified from the GenTL 1.6 header distributed with Aravis 0.9.2 at `src/gentl/GenTL_v1_6.h`. The upstream file identifies the GenICam GenTL Subcommittee copyright and carries its redistribution disclaimer. The same header is identified as byte-identical to the EMVA GenTL 1.6 reference header in the EMVA GenICam Package Version 2026.07.

- Upstream: https://github.com/AravisProject/aravis/blob/0.9.2/src/gentl/GenTL_v1_6.h
- Standard: https://www.emva.org/standards-technology/genicam/genicam-downloads/
