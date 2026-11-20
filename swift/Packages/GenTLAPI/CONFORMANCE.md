# GenTL API conformance and backend coverage

This document records the behavior implemented on the current branch. It is not a claim that either backend is a certified GenTL implementation. It must be read together with the repository's GenTL implementation plan, which defines the target header-first architecture.

## Shared API surface — current state

The public GenTLAPI protocol mirrors all 64 C function declarations in the pinned GenTL 1.6 header. It uses imported GenTL ABI types, opaque pointer handles, explicit C output parameters and GC_ERROR return values.

A source-level comparison was performed using the header's 64 GC_API declarations. The protocol matched every function name, parameter type and return type exactly. The same comparison confirmed that GenTLNative and AmcamGenTL each implement all 64 protocol signatures.

The public protocol is a Swift contract over imported C declarations. It is not itself a C ABI and does not export GenTL Producer symbols.

The earlier Swift convenience protocol groups, custom typed handles, decoded info values and Swift-throws wrappers remain behind explicit BackendConvenience SPI. This is a transitional internal implementation layer, not a second application-facing API. It is still present and must be removed after the remaining backend/router internals are migrated.

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
- The pinned GenTL 1.6 header is compiled through the standalone GenTLABI package, with layout checks for the packed GenTL structures used by this consumer. The native function table uses the PGC/P* typedefs imported from that header, and all 64 public GenTLAPI operations have corresponding native implementation methods. This target will be extracted into the shared GenTLABI package as specified by the implementation plan.

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

The repository contains tests for legacy backend conveniences, raw API unsupported defaults, native Producer catalog/library validation, Amcam RGB24 memory layout, and router lifecycle behavior. No Swift build or test suite has been run during this continuation. The source-level signature comparison is not proof of ABI runtime compatibility or formal GenTL conformance.

Remaining verification: build all Swift packages on macOS; run unit tests; test exact required/optional CTI symbol resolution with mock Producers; exercise native calls against real vendor CTIs; verify Amcam behavior with the actual SDK and cameras; and record any remaining operation-level limitations.
