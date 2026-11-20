# GenTL API conformance and backend coverage

This document describes the current behavior of the two implementations of the shared Swift `GenTLAPI` contract. It is an implementation-status record, not a claim that either backend is a certified GenTL implementation.

## Shared API surface

The public Swift protocol follows the GenTL 1.6 function groups and uses typed opaque handles, Swift values and `throws` for GenTL errors. The function names and module boundaries are GenTL-shaped; the Swift protocol is not a C ABI and is not a GenTL Producer.

The Swift protocol grouping follows GenTL module ownership: register-stack operations belong to the Port module (GenTL 1.1), while chunk/multipart/flow/segment methods are Data Stream extensions (GenTL 1.3–1.6).

The Swift `genTLVersion` property identifies the revision represented by this API surface. It does not claim that every loaded `.cti` Producer implements all functions in that revision. The native backend resolves later-revision entry points opportunistically, and the Producer's own supported revision is read from `GCGetInfo`/`TL_INFO_GENTL_VER_MAJOR` and `TL_INFO_GENTL_VER_MINOR` where available.

## GenTLNative

`GenTLNativeImplementation` forwards the GenTL function calls to a manufacturer-supplied `.cti` Producer.

- The 47 GenTL 1.0 base functions are validated as required exported symbols before the Producer is accepted. This includes `EventGetDataInfo`; it is part of GenTL 1.0.
- Later-revision entry points are resolved opportunistically, using the revisions specified by the pinned GenTL header:
  - GenTL 1.1: `GCGetNumPortURLs`, `GCGetPortURLInfo`, `GCReadPortStacked`, `GCWritePortStacked`.
  - GenTL 1.3: `DSGetBufferChunkData`.
  - GenTL 1.4: `IFGetParentTL`, `DevGetParentIF`, `DSGetParentDev`.
  - GenTL 1.5: `DSGetNumBufferParts`, `DSGetBufferPartInfo`.
  - GenTL 1.6: composite buffers, stacked buffer metadata, flows and buffer segments.
- An absent optional function returns `GC_ERR_NOT_IMPLEMENTED`.
- Producer handles remain opaque; this implementation does not synthesize handle IDs.
- The pinned GenTL 1.6 header is compiled into the ABI target, with layout checks for the packed GenTL structures used by this consumer.

Actual camera capability and compatibility still depend on the selected `.cti` Producer, its macOS architecture and its implementation of the standard.

## AmcamGenTL

`AmcamGenTLImplementation` maps the supported GenTL function behavior to the Amcam SDK. It does not create an AmScope `.cti` file.

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
- GenTL `BOOL8` metadata remains Boolean in the Swift value model.
- Access modes unsupported by the Amcam SDK are rejected.
- Event, buffer and stream handles must be released in their owning module's lifecycle order.
