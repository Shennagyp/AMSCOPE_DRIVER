# AMSCOPE_DRIVER

Swift-first camera access library for macOS.

The public API follows the EMVA GenICam GenTL 1.6 module and function model. It has two interchangeable implementations:

1. A native GenTL Consumer implementation that loads third-party GenTL Producer libraries (`.cti`).
2. An Amcam implementation that maps the same GenTL-shaped Swift API onto the Amcam SDK. It does not require or generate an Amcam `.cti` file.

The application-facing API is GenTL-shaped. It is not a second, vendor-neutral camera abstraction.

## Repository layout

The Swift packages are under `swift/Packages`. The first milestone defines the GenTL 1.6 types, module handles, error codes, and function groups before implementing either backend.

## Standards baseline

- GenICam GenTL 1.6
- GenTL SFNC 1.2 (for standardized GenTL module feature names)
- PFNC pixel-format identifiers where frame payload metadata requires them

The implementation must preserve GenTL semantics. An operation unsupported by the Amcam SDK returns the corresponding GenTL error (normally `GC_ERR_NOT_IMPLEMENTED` or `GC_ERR_NOT_AVAILABLE`); it must not fabricate behavior.

## Amcam Swift integration

The proposed native Swift integration and acquisition-thread design are documented in [Swift Amcam Backend: Native Acquisition Design](docs/architecture/amcam-swift-acquisition.md). It uses the vendor's native SDK through a C-compatible boundary; Python is a reference implementation, not a runtime dependency.
