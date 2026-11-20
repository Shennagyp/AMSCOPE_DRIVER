# Mock GenTL Producer fixture

This directory contains a test-only native GenTL Producer used by GenTLNativeIntegrationTests.

## Purpose

The fixture is a compiled C dynamic library. Tests build it with the macOS SDK compiler and load the resulting .cti file through the production GenTLNativeImplementation loader. This intentionally exercises the actual dlopen/dlsym and imported C function-pointer path.

A Swift object conforming to GenTLAPI is not a substitute for this fixture: it bypasses the C ABI boundary being tested.

## Export behavior

- All 64 GenTL 1.6 function exports from the pinned header are represented.
- The 47 GenTL 1.0 base exports are present in the normal build.
- The 17 later-revision exports are optional and can be omitted together.
- Ordinary operations return distinct test error values based on their declaration index, making incorrect function-table mapping observable.
- GCGetInfo, GCReadPort, and GCWritePort validate sentinel arguments and/or output memory.
- Library and event lifecycle functions return controlled success values so the integration test can exercise registration and clean shutdown.
- MockCTI_GetCallCount is a test-only export. It is not a GenTL function and must never be added to production API requirements.

## Build variants

- Default: all 64 GenTL exports.
- MOCK_OMIT_<symbol>: omit one required GenTL 1.0 export, where <symbol> is the exact GenTL function name (for example GCGetInfo); the loader must reject the library. The test iterates all 47 required symbols.
- MOCK_OMIT_OPTIONAL_EXPORTS: omit all 17 later-revision exports; the base Producer must still load, and calls to absent optional functions must return GC_ERR_NOT_IMPLEMENTED.

## Limits

This is currently an ABI/loader/dispatch fixture, not a simulated camera. Most exports intentionally return deterministic test errors. It does not yet provide a valid System/Interface/Device topology, stream, buffers, or frame acquisition. Those behaviors are a later fixture increment after the current Swift package and integration tests compile and execute successfully.

No physical camera or vendor CTI is required to run these tests.
