# GenTLABI

GenTLABI is the single shared Clang-imported C module for the GenTL ABI declarations used by this repository.

## Pinned header

- Header: GenTL_v1_6.h
- GenTL revision encoded by the header: 1.6.0
- Header notice: copyright 2004–2019, GenICam GenTL Subcommittee; the notice refers to the EMVA GenICam Standard Group license terms.
- Git blob object ID for the unchanged pinned header: 140c340dbf240c3c95ba13266d9965964b961517
- The header is retained as one file under this package. Do not maintain edited or copied variants in GenTLNative, GenTLAPI or AmcamGenTL.

The header was moved from the former GenTLNative ABI target into this package without changing its bytes. Its Git blob object ID is therefore unchanged. Repository history records the existing header copy as originating from the GenTL 1.6 header included with Aravis 0.9.2; before any header replacement, verify the upstream provenance, applicable EMVA license text and exact revision.

## Contents

- The public header imports the complete GenTL declarations and dynamic function-pointer typedefs.
- GenTLABI.c performs compile-time structure-size and field-offset checks for the packed ABI structures used by this implementation.
- GenTLABI_HeaderVersion and GenTLABI_LayoutValid expose the header revision and layout-check result to Swift.

## Rules

1. Treat GenTL_v1_6.h as the ABI authority; do not restate its C function-pointer signatures using handwritten Swift @convention(c) declarations.
2. Use the PGC/P* function-pointer typedefs declared by the header for dynamic CTI symbol bindings.
3. Use imported C types and constants for ABI-relevant declarations wherever the header defines them.
4. Any header upgrade is an explicit standards-version change. Review the specification changes, symbol inventory, structure layouts, license terms and all affected backends together.
5. Keep this package independent of both GenTLNative and AmcamGenTL. Both implementations, and the GenTLAPI contract, consume this same module.
