# macOS version 0.3 — recovery, lifecycle regressions and probe diagnostics

## Branch baseline

- Branch: `macos-version-0.3`
- Source baseline: `macos-version-0.2` commit `4f4a8ca022274eba5fe49dc2489f9e7fa766dd64`
- Source baseline CI: [GitHub Actions run 44860717992](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44860717992) — all six jobs passed.
- Scope of this branch increment: record the user-verified process-relaunch and idle USB reconnect behavior; add deterministic sustained-buffer and repeated acquisition lifecycle regressions; and add a versioned JSON diagnostic report to `amcam-camera-probe`. The AppKit application and camera-session runtime behavior are inherited from the green source baseline; the probe executable and its supporting report target have additional code in 0.3.

## Acquisition regression coverage added in 0.3

The branch adds deterministic, hardware-independent coverage without changing camera runtime semantics:

- A GenTL acquisition test consumes 64 consecutive frames through one reused announced buffer and checks monotonically increasing frame sequence values, changing copied pixel contents, and exactly one buffer return per delivered frame.
- A lifecycle test uses one open device session with four distinct acquisitions. It performs three stop/restart transitions and verifies exactly one start, one stop and one close per acquisition.
- The existing regression set continues to cover timeout recovery, stop/close races, frame-copy immutability and the rule that a failed `DSQueueBuffer` call is surfaced once and is not retried on the same handle.

These mock/contract tests do not establish five-minute physical streaming or physical-camera start/stop behavior. The lifecycle test commit passed all six CI jobs in [run 44862950222](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44862950222).

## Structured camera-probe report

The `amcam-camera-probe` executable accepts `--json` and emits one schema-versioned JSON document to stdout. The default human-readable mode is unchanged. The report contains:

- Backend identifier and SDK path/version.
- Interface identifier and selected camera's model descriptor, display name and transient device identifier.
- Stream identifier, payload size and announced-buffer count.
- Pixel-format code and namespace, width, height, row stride/padding, size-filled and data-size.
- Complete/incomplete frame counts, sequence and device timestamp bounds, host-loop/camera timestamp rates and the last-frame SHA-256 digest.
- A typed failure stage and message, with cleanup errors reported separately.

The command retains a nonzero process exit status on failure while still emitting the JSON report. `make build-probe` builds the CLI; `make run-probe` directs SwiftPM build diagnostics to stderr so stdout remains parseable when `--json` is selected. The schema is isolated in the `AmcamCameraProbeSupport` target and has JSON encoding/decoding tests.

The real MU503 probe execution remains part of the outstanding hardware acceptance; a passing schema test or probe build is not physical-camera evidence.

## GenTL buffer release invariant\n\nThe shared `GenTLAcquisitionSession.close()` and the standalone probe now use `ACQ_QUEUE_ALL_DISCARD` after acquisition stop and event unregistration, before revoking announced buffers. `ACQ_QUEUE_ALL_TO_INPUT` is not sufficient: it deliberately keeps buffers in the input pool, where GenTL 1.6 says they cannot be revoked. The Amcam backend integration test checks this distinction, then confirms that provider-allocated memory is released by successful revocation.\n\nThe probe applies fail-fast, child-before-parent cleanup. A failed stop, event unregister, queue discard, buffer revoke or child close is recorded in `cleanup_errors`; subsequent parent teardown is not attempted while a child resource may remain owned.\n\nReference: [EMVA GenTL 1.6, sections 5.2.8–5.2.10 and `ACQ_QUEUE_ALL_DISCARD`](https://www.emva.org/wp-content/uploads/GenICam_GenTL_1_6.pdf).\n\n## Runtime behavior carried into 0.3

### Relaunch from source

`make run` now:

1. Detects an existing `amcam-imaging` process.
2. Requests that the running `com.amscope.imaging` application quit normally.
3. Waits for the existing process to exit.
4. Aborts if it cannot confirm process exit.
5. Builds, packages, signs and launches the new application.

The script never force-kills the existing process and never intentionally launches a second camera-owning application process. The `BUILD_ONLY=1` path used by `make build-local` and CI does not request application shutdown.

### USB disconnect/reconnect

The application polls discovery every two seconds because this camera SDK path does not depend on a portable device-change notification.

- An incomplete discovery report does not immediately destroy the current session.
- An idle session is marked for recreation if background discovery becomes inconclusive.
- After a later complete discovery scan, the application closes the stale session in ownership order and opens the selected device again. This also applies when the SDK returns the same transient device identifier.
- If an attached idle session reports no usable stream, only the live-capture capability is rechecked; full feature/control readbacks are not repeated on every poll.
- Disconnect failures during active acquisition are reported through the camera callback/runtime lifecycle. Native callback ownership is retained until SDK stop succeeds.

The relevant implementation commits on the source branch include deterministic router/provider shutdown, hot-plug recovery, incomplete-discovery handling, process relaunch, stream-capability revalidation, and idle-session recreation.

## Verification record

### Hosted CI

The source baseline commit `4f4a8ca` passed all six jobs in [run 44860717992](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44860717992):

- Portable imaging and runtime-library Linux tests.
- GenTLAPI tests.
- GenTLNative tests.
- GenTLRouter tests.
- AmcamGenTL tests, including the camera-probe build, dependency-boundary checks and fixture-SDK app packaging/signing.
- AmcamImagingGenTLAdapter tests.

This verifies the source baseline, package contracts and fixture packaging. It does not verify the proprietary SDK binary or physical camera. Later 0.3 CI validates the new 64-frame and repeated-restart regressions; the current branch workflow is also responsible for validating the structured probe target and packaging changes.

### Physical MU503 result — 2026-11-21

The user confirmed this sequence works on the MU503:

1. Run `make run` while an earlier Amcam Imaging process is already open.
2. The old process exits and the newly built application launches.
3. Disconnect and reconnect the MU503 while the new application remains open.
4. The camera session recovers and Start becomes enabled without manually restarting the app.

The user's confirmation did not include the SDK version, exact model descriptor, firmware, macOS build or Mac architecture; those values are intentionally not inferred.

## Explicitly not certified by this release record

The reconnect result is a partial physical acceptance, not full MU503 qualification. The following remain separate acceptance items:

- Five minutes of sustained live RGB8 acquisition.
- Repeated start/stop cycles.
- Disconnect while acquisition is actively streaming and exact error/recovery behavior.
- Setter/readback verification for each exposed camera control.
- Independent camera-probe validation of frame metadata, payload layout and cleanup.
- Validation of the proprietary SDK dylib and all of its transitive dependencies on the target Mac.

See [the physical-camera acceptance checklist](AMCAM_HARDWARE_ACCEPTANCE.md), [the application lifecycle guide](AMCAM_IMAGING_APPLICATION.md), and [the implementation plan](NEXT_IMPLEMENTATION_PLAN.md).
