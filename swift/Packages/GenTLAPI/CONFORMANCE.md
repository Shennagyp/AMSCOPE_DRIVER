# GenTL API conformance and backend coverage

This document records the behavior implemented on the current branch. It is not a claim that either backend is a certified GenTL implementation. It must be read together with the repository's GenTL implementation plan, which defines the target header-first architecture.

## Shared API surface — current state

The current public Swift contract follows the GenTL 1.6 function groups and uses typed opaque handles, Swift values and Swift error propagation for GenTL errors. Its names and module boundaries are GenTL-shaped.

**Important architectural gap:** this contract is currently hand-authored in Swift. It has not yet been converted into a binding that derives its ABI-relevant types and declarations from the imported GenTL C header. The ABI target has now been extracted into the standalone GenTLABI package and is a declared dependency of GenTLAPI, GenTLNative and AmcamGenTL. The native implementation's C function-pointer aliases now reference the imported PGC/P* typedefs. The public GenTLAPI protocol and custom type system remain to be converted. Until that work is complete, this document describes the existing implementation, not the final API binding.

The Swift protocol is not a C ABI and is not a GenTL Producer. Only GenTLNative calls the C ABI exported by third-party CTI Producers. AmcamGenTL implements the common Swift contract by using the Amcam SDK directly.

The current protocol grouping follows GenTL module ownership: register-stack operations belong to the Port module (GenTL 1.1), while chunk/multipart/flow/segment methods are Data Stream extensions (GenTL 1.3–1.6).

The current Swift genTLVersion property identifies the revision represented by the API surface. It does not claim that every loaded CTI Producer implements every function in that revision. The native backend resolves later-revision entry points opportunistically, and the Producer's own supported revision is read from GCGetInfo / TL_INFO_GENTL_VER_MAJOR and TL_INFO_GENTL_VER_MINOR where available.

## GenTLNative

GenTLNative forwards GenTL function calls to a manufacturer-supplied CTI Producer.

- The 47 GenTL 1.0 base functions are validated as required exported symbols before the Producer is accepted. This includes EventGetDataInfo; it is part of GenTL 1.0.
- Later-revision entry points are resolved opportunistically, using the revisions specified by the pinned GenTL header:
  - GenTL 1.1: GCGetNumPortURLs, GCGetPortURLInfo, GCReadPortStacked, GCWritePortStacked.
  - GenTL 1.3: DSGetBufferChunkData.
  - GenTL 1.4: IFGetParentTL, DevGetParentIF, DSGetParentDev.
  - GenTL 1.5: DSGetNumBufferParts, DSGetBufferPartInfo.
  - GenTL 1.6: composite buffers, stacked buffer metadata, flows and buffer segments.
- An absent optional function returns GC_ERR_NOT_IMPLEMENTED.
- EVENT_SIZE_MAX is a GenTL 1.2 EventGetInfo command. When a GenTL 1.0 Producer rejects that command, the native Consumer can still receive the standard fixed-size New Buffer event structure (two pointers). It does not guess a maximum for variable Error-event payloads and returns GC_ERR_NOT_IMPLEMENTED for that legacy case.
- Producer handles remain opaque; this implementation does not synthesize handle IDs.
- If the native implementation is deallocated before a successful GCCloseLib, its CTI library is retained for process lifetime rather than unloaded with potentially live Producer state.
- The pinned GenTL 1.6 header is compiled through the standalone GenTLABI package, with layout checks for the packed GenTL structures used by this consumer. Native function-pointer aliases now refer to the PGC/P* typedefs imported from that header. This target will be extracted into the shared GenTLABI package as specified by the implementation plan.

Actual camera capability and compatibility still depend on the selected CTI Producer, its macOS architecture and its implementation of the standard.

## AmcamGenTL

AmcamGenTL maps supported GenTL function behavior to the Amcam SDK. It does not create an AmScope CTI file.

| GenTL module / capability | Current Amcam behavior |
|---|---|
| Library and System | Implemented as an Amcam SDK-managed system |
| Interface discovery | One SDK-managed interface |
| Device discovery/open/close | Implemented; exclusive read/write open only |
| Device serial number | Not reported; SDK enumeration ID is opaque and is not assumed to be a serial number |
| Device timestamp clock | 1 MHz; FrameInfoV2 timestamps are in microseconds when its timestamp-valid flag is set |
| Device access status | Unknown before this backend opens the camera; open-read/write while owned |
| Data Stream | One stream per open camera |
| Buffer announcement/allocation | Implemented |
| Queue, flush and acquisition | Implemented for supported default start/stop semantics |
| Buffer metadata | RGB8 image metadata with DWORD-aligned rows; padding bytes are included in payload and filled sizes and reported through BUFFER_INFO_XPADDING |
| Data Stream events | New-buffer and error events |
| Physical port/register access | Not implemented |
| GenApi XML URL access | Not implemented |
| Chunk data | Not available from the Amcam pull-image path |
| Multipart payload | One 2D image part when a complete image has been delivered; otherwise zero parts |
| Composite buffer announcement | Not implemented |
| Flow table | No flows exposed |
| Buffer segments | One contiguous memory segment |

Unsupported operations return a GenTL error rather than fabricated register or feature behavior.

## Important GenApi boundary

GenTL provides transport discovery, module lifecycle, register-port access and streaming. GenApi interprets a camera's XML feature description and maps features to the GenTL port.

The current Amcam SDK integration exposes feature getters and setters, but this implementation has not established a documented Amcam remote register map or GenApi XML port. Therefore, the current Amcam backend supports acquisition and its implemented module operations, but it does **not** yet expose exposure/gain/etc. through the standard GenApi feature-node path.

That is a separate integration milestone. It must be implemented using a verified feature description and SDK mapping; it must not pretend that arbitrary Amcam registers exist.

## Semantic constraints

- A GenTL buffer remains consumer-owned or producer-owned according to how it was announced. Revocation and stream close preserve that ownership distinction.
- An incomplete frame is still a completed buffer delivery and counts toward a finite acquisition request.
- GenTL BOOL8 metadata remains Boolean in the Swift value model.
- Access modes unsupported by the Amcam SDK are rejected.
- Event, buffer and stream handles must be released in their owning module's lifecycle order.

## Conformance status

The current test suite covers selected API defaults, native Producer catalog and library validation, Amcam RGB24 memory layout, and router/lifecycle behavior. These tests are implementation checks, not proof of full standard conformance.

The next conformance milestone is to run shared contract tests against both backends, add imported-header ABI checks, verify exact required/optional CTI symbol sets with mock Producers, and explicitly track every GenTL operation that remains unimplemented.
