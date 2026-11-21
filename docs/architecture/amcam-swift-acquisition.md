# Swift Amcam Backend: Native Acquisition Design

**Status:** Proposed architecture; not yet implemented  
**Target:** `main`  
**Scope:** Integrate the vendor Amcam SDK into the Swift-first macOS camera library without making Python a runtime dependency.

This document records a Swift-compatible implementation of the vendor's Amcam acquisition model. It is an architectural direction, not a claim that the Amcam backend or the proposed frame pipeline already exists in this branch.

## 1. Decision

Keep the application and camera-control layer Swift. Call the vendor's native Amcam SDK from Swift through its C interface where available, with a small C or Objective-C++ bridge only where needed.

Separate camera control from high-throughput frame acquisition:

- The Swift-facing camera/session API owns discovery, open/close, device configuration, exposure, gain, white balance, resolution, capability reporting, and state.
- A backend-owned acquisition engine owns frame retrieval, native callback handling, buffer allocation/reuse, frame metadata, and publication.
- Both capabilities belong to the same backend session and use the same opened camera handle. Do not open a second camera handle for streaming.
- The UI receives completed frames; it does not retrieve them from the SDK.

This keeps the existing native GenTL Producer backend as a distinct implementation. The Amcam backend uses the Amcam SDK directly and does not require an Amcam `.cti` Producer.

## 2. What the vendor PyQt sample proves

The supplied vendor sample uses:

```python
self.hcam.StartPullModeWithCallback(self.eventCallBack, self)
```

The SDK invokes `eventCallBack` on an internal SDK thread. The sample emits a Qt signal, and the Qt UI thread later handles the image event by calling:

```python
self.hcam.PullImageV4(self.pData, 0, 24, 0, None)
```

It then constructs and scales a `QImage` and updates a `QLabel`.

This demonstrates the vendor's Pull-mode event model and the control operations available through its Python binding. It does **not** establish that image retrieval must occur on the UI thread. The UI-thread pull is a choice made by the sample.

The Swift implementation should preserve the SDK's required event/pull sequence but move retrieval and buffer handling away from the UI thread.

## 3. Swift-to-SDK boundary

### Preferred integration

1. Use the vendor's macOS SDK binary and matching C header.
2. Add a Swift Package C target (for example, `AmcamABI`) that exposes the vendor header through a module map.
3. Call the C API from Swift using imported declarations and opaque pointers.
4. Keep vendor-specific C types, calling conventions, and callback details inside the backend boundary.

If the SDK exposes only a C++ interface, or its headers cannot be imported safely by Swift, add a very small Objective-C++ (`.mm`) adapter. Give Swift a C-compatible façade with opaque session/context handles and plain C structs. Do not expose C++ classes, templates, STL containers, or C++ exceptions across the Swift boundary.

The adapter is an interoperability boundary, not a second camera implementation. It must delegate to the vendor SDK rather than reimplementing its acquisition logic.

### Callback context and lifetime

Do not pass an unretained Swift object to a native callback. The callback context must remain valid until the SDK has stopped issuing callbacks and the adapter has confirmed callback quiescence. A Swift implementation can use a retained opaque context token; an adapter can instead own the callback context and expose explicit start/stop operations.

Do not capture arbitrary Swift closures in a C callback unless their lifetime and calling convention are explicitly managed. A static C-compatible trampoline with an opaque context is easier to audit.

## 4. Acquisition and frame-delivery path

### Initial implementation: Pull mode

Use the vendor's proven `StartPullModeWithCallback` path first.

```text
Amcam SDK internal acquisition
            |
            v
SDK callback thread
            |
            |  signal only; no UI, conversion, or processing
            v
Backend event ingress
            |
            v
Dedicated acquisition worker
            |
            |  PullImageV4 into a reusable application-owned buffer
            v
Frame buffer pool / frame lease
            |
            +--------------------+
            |                    |
            v                    v
Latest-frame preview       Ordered consumer path
            |               (when required)
            v
Swift presentation         Future processing / recording
```

The SDK callback should perform only a minimal, non-blocking notification to the backend worker. It should not call UI APIs, scale images, encode files, run image processing, or wait for a renderer.

The acquisition worker performs the corresponding `PullImageV4` call and publishes the completed frame. Use one serialized owner for Pull-mode retrieval unless the vendor explicitly documents a different concurrency contract. Do not move the pull into the main actor or the UI event loop.

The vendor sample's Push mode, if available in the installed SDK, can be evaluated later. Do not select it merely because it sounds faster: first establish callback-buffer ownership, callback duration requirements, SDK thread guarantees, and whether the SDK permits the application to retain or reuse the supplied memory.

### Frame memory and format

- Allocate a bounded pool of reusable buffers; do not allocate a fresh full-frame buffer for every notification.
- Derive payload size, row stride, pixel format, and alignment from the selected camera mode and SDK metadata. Do not assume every device is RGB24. The sample's 24-bit RGB path is only one format.
- A published frame owns a lease on its buffer. The buffer cannot be overwritten or returned to the free pool until all consumers have released that lease.
- Treat published frame memory as immutable.
- Include at least frame sequence, timestamp (when provided by the SDK), width, height, pixel format, row stride, payload length, and configuration generation in frame metadata.
- Bound every queue. Preview should normally use a latest-frame slot so obsolete preview frames are replaced rather than accumulated. Consumers that require every frame need a separate bounded policy with explicit backpressure or drop reporting.

The first implementation may pull into application-owned CPU memory. Do not claim zero-copy GPU acquisition unless the vendor SDK explicitly supports a compatible user-buffer or shareable-surface path and that path is verified on the target hardware.

## 5. Control plane, session ownership, and configuration

The control layer and acquisition engine must share one authoritative session and one camera handle. The acquisition split is a separation of responsibilities, not permission for two independently managed SDK sessions to operate the same device.

The SDK's thread-safety rules must be checked against its headers and documentation. Until concurrent calls are documented as safe, route SDK operations through a session-level synchronization policy. Keep the critical section around SDK calls only; never hold it while rendering, processing, or waiting for consumers.

Operations that change stream geometry or interpretation (for example, resolution or pixel format) require a reconfiguration transaction:

1. Stop accepting new frame notifications.
2. Stop acquisition and wait until callbacks have quiesced.
3. Resolve outstanding frame leases.
4. Apply the new camera configuration.
5. Recalculate buffer sizes/strides and rebuild the pool if needed.
6. Restart acquisition and publish frames with a new configuration generation.

Exposure or gain changes may be applied while streaming only where the vendor SDK permits it. The control layer remains authoritative for requested values and read-back state.

## 6. UI and GPU ownership

The UI thread is responsible for UI state and presentation, not SDK frame retrieval.

The rendering path should receive a frame lease and schedule presentation independently of the SDK callback. If the application uses a dedicated GPU/render thread, that thread owns GPU resource creation, upload, and command submission. Do not confuse:

- the SDK's internal acquisition/callback thread;
- the backend's frame-pull worker;
- the GPU/render execution thread; and
- the UI/main thread.

A CPU-backed frame normally needs an upload into a GPU resource. Direct GPU or zero-copy import is a later optimization that depends on an SDK-supported memory-sharing mechanism and the chosen macOS graphics API. Keep that optimization behind the frame-storage boundary so it does not change camera-control semantics.

## 7. Stop, close, and failure semantics

Treat acquisition lifecycle as an explicit state machine, not a side effect of setting the camera handle to `nil`.

A safe stop/close sequence is:

1. Prevent new starts and configuration changes.
2. Request acquisition stop.
3. Wait for the SDK to stop issuing callbacks.
4. Drain or invalidate pending notifications.
5. Wait for the acquisition worker to leave all SDK calls.
6. Resolve outstanding frame leases according to the documented shutdown policy.
7. Release the callback context and native buffers.
8. Close the camera handle.
9. Mark the session closed.

The sequence must be idempotent and safe after partial start failure, device removal, SDK error, and repeated start/stop. Never free callback context or frame storage while native code may still reference it.

## 8. Relationship to the existing GenTL design

Keep the two backend strategies distinct:

- **GenTL backend:** load a `.cti` Producer and preserve GenTL module/data-stream semantics.
- **Amcam backend:** call the Amcam SDK directly; do not invent or require an Amcam `.cti` file.

At the application boundary, common camera controls and frame-consumer metadata can be shared where their semantics genuinely match. Backend-specific acquisition mechanics should remain behind the backend boundary. Do not fabricate a GenTL capability when the Amcam SDK does not provide equivalent behavior; report unsupported or unavailable operations explicitly.

The frame-stream capability should be separable from the general control surface. If the public GenTL API exposes standard Data Stream operations, their GenTL semantics must still be preserved by the GenTL implementation; the Amcam-specific worker is an internal implementation detail, not a reason to weaken the GenTL contract.

The separate ImageProcessing project is outside this change. This design only defines a stable frame hand-off boundary so that the projects can be integrated later without making camera acquisition depend on the processing library.

## 9. Implementation sequence

1. **SDK contract check:** obtain the exact macOS headers and library; verify architectures, exported functions, callback signatures, pixel formats, buffer rules, callback shutdown behavior, and thread-safety guarantees.
2. **Interop proof:** make a minimal Swift target open, query, configure, and close one camera through the vendor SDK. Use a C target or Objective-C++ adapter only as required by the actual SDK interface.
3. **Native controls:** implement enumeration, open/close, exposure, gain, white balance, resolution, and read-back/error mapping behind the existing Swift-facing control/session API.
4. **Pull acquisition worker:** implement callback notification, serialized `PullImageV4`, reusable buffers, frame leases, metadata, and bounded publication.
5. **Presentation:** display the newest frame without performing acquisition on the UI thread; keep rendering/GPU work separate.
6. **Lifecycle verification:** exercise repeated open/start/stop/reconfigure/close, device unplug, partial start failure, and callback shutdown. Measure delivered, displayed, and dropped frames separately.

## 10. Acceptance criteria

- The Swift application uses the vendor's native SDK; Python is not required at runtime.
- The Amcam backend and native GenTL backend remain independently selectable.
- Camera controls and acquisition share one authoritative camera session/handle.
- No SDK frame pull, full-frame conversion, or image processing runs on the UI thread.
- The SDK callback does bounded notification work only.
- Frame memory is reused safely, with explicit ownership and bounded queues.
- Preview can discard obsolete frames without silently changing the policy of consumers that require ordered delivery.
- Stop, close, reconfigure, and device removal do not leave callbacks accessing released objects or buffers.
- Performance is measured on the target camera and macOS hardware; no zero-copy or maximum-frame-rate claim is made without measurement.

## 11. Open SDK facts to verify before implementation

This design intentionally does not guess the following vendor-specific facts:

- The exact Amcam C declarations and calling convention in the installed macOS SDK.
- Whether the SDK's callback can be stopped synchronously, or how callback quiescence is guaranteed.
- Whether `PullImageV4` is safe concurrently with control calls on the same handle.
- Whether Pull mode provides frame sequence/timestamp metadata for the selected model.
- Which pixel formats, row-stride rules, and buffer alignment apply to each model.
- Whether Push mode or application-provided buffers are supported and what their lifetime guarantees are.
- Whether the SDK exposes a GPU-shareable buffer path on macOS.

These facts must be resolved from the exact SDK headers/documentation and validated on the target camera before optimizing beyond the safe reusable-buffer Pull-mode path.
