# macOS version 0.3 — recovery and lifecycle baseline

## Branch baseline

- Branch: `macos-version-0.3`
- Source baseline: `macos-version-0.2` commit `4f4a8ca022274eba5fe49dc2489f9e7fa766dd64`
- Source baseline CI: [GitHub Actions run 44860717992](https://github.com/Shennagyp/AMSCOPE_DRIVER/actions/runs/44860717992) — all six jobs passed.
- Scope of this branch increment: document the already implemented and user-verified process-relaunch and USB reconnect recovery. The application/backend code is inherited unchanged from the green source baseline.

## Runtime behavior carried into 0.3

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

This verifies the tested source, mock behavior, package builds and fixture packaging. It does not verify the proprietary SDK binary or physical camera.

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
