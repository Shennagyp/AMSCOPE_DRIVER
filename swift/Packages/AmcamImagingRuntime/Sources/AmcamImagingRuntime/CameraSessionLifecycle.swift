import Foundation
import AmcamImagingCore

/// Owns one camera session and its optional acquisition child.
///
/// Resource ownership is strict: acquisition close must succeed before the
/// parent device session is closed. Failed closes retain the corresponding
/// handle so callers can retry. A monotonically increasing generation rejects
/// frames already in flight when stop or close begins.
public actor CameraSessionLifecycle {
    private var session: (any CameraRuntimeSession)?
    private var acquisition: (any CameraRuntimeAcquisition)?
    private var captureTask: Task<Void, Never>?
    private var isStreaming = false
    private var lastDeliveredFrameSequence: UInt64?
    /// Actor methods are re-entrant across awaits. This FIFO gate queues backend
    /// operations instead of rejecting ordinary UI overlap or exposing owned handles.
    private var lifecycleOperationHeld = false
    private var lifecycleOperationWaiters: [CheckedContinuation<Void, Never>] = []
    private var generation: UInt64 = 0
    private var eventContinuations: [UUID: AsyncStream<CameraSessionLifecycleEvent>.Continuation] = [:]
    private var frameContinuations: [UUID: AsyncStream<CameraFramePayload>.Continuation] = [:]

    public init() {}

    /// Reliable, low-volume state events. This stream is unbounded because
    /// dropping a close/failure transition could leave a frontend stale.
    public func events() -> AsyncStream<CameraSessionLifecycleEvent> {
        let identifier = UUID()
        let pair = AsyncStream<CameraSessionLifecycleEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        eventContinuations[identifier] = pair.continuation
        pair.continuation.onTermination = { @Sendable [weak self] _ in
            guard let lifecycle = self else { return }
            Task { await lifecycle.removeEventContinuation(identifier) }
        }
        return pair.stream
    }

    /// Image delivery is intentionally latest-frame-only. A slow renderer must
    /// not accumulate full camera payloads or delay lifecycle state transitions.
    public func frames() -> AsyncStream<CameraFramePayload> {
        let identifier = UUID()
        let pair = AsyncStream<CameraFramePayload>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        frameContinuations[identifier] = pair.continuation
        pair.continuation.onTermination = { @Sendable [weak self] _ in
            guard let lifecycle = self else { return }
            Task { await lifecycle.removeFrameContinuation(identifier) }
        }
        return pair.stream
    }

    public func snapshot() -> CameraSessionLifecycleSnapshot {
        CameraSessionLifecycleSnapshot(
            hasSession: session != nil,
            hasAcquisition: acquisition != nil,
            isStreaming: isStreaming,
            lastDeliveredFrameSequence: lastDeliveredFrameSequence
        )
    }

    /// Opens and adopts a device as one atomic library-owned lifecycle operation.
    /// The backend session never escapes this actor.
    public func open(_ device: any CameraRuntimeDevice) async throws {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }

        guard session == nil, acquisition == nil, captureTask == nil else {
            throw CameraSessionLifecycleError.sessionAlreadyAttached
        }

        let openedSession = try await device.open()
        session = openedSession
        lastDeliveredFrameSequence = nil
    }

    /// Feature I/O is serialized with lifecycle transitions. The backend session
    /// never escapes this actor, so close cannot race a borrowed feature handle.
    public func supportsAcquisition() async -> Bool {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        guard let session else { return false }
        return await session.supportsAcquisition()
    }

    public func featureDescriptors() async throws -> [CameraFeatureDescriptor] {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        guard let session else { throw CameraSessionLifecycleError.sessionNotAttached }
        return try await session.featureDescriptors()
    }

    public func readFeature(_ name: String) async throws -> CameraFeatureValue {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        guard let session else { throw CameraSessionLifecycleError.sessionNotAttached }
        return try await session.readFeature(name)
    }

    public func writeFeature(_ value: CameraFeatureValue, named name: String) async throws {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        guard let session else { throw CameraSessionLifecycleError.sessionNotAttached }
        try await session.writeFeature(value, named: name)
    }

    public func start() async throws {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }

        guard let session else {
            throw CameraSessionLifecycleError.sessionNotAttached
        }
        guard !isStreaming else {
            throw CameraSessionLifecycleError.acquisitionAlreadyRunning
        }

        // A stopped or failed acquisition remains owned until it is closed.
        if let previous = acquisition {
            try await previous.close()
            acquisition = nil
        }
        if let previousTask = captureTask {
            captureTask = nil
            await previousTask.value
        }

        let newAcquisition = try await session.makeAcquisition()
        acquisition = newAcquisition
        do {
            try await newAcquisition.start()
        } catch {
            // If cleanup itself fails, retain the acquisition for a later retry.
            do {
                try await newAcquisition.close()
                acquisition = nil
            } catch {
                // Preserve the original start error; ownership remains retained.
            }
            throw error
        }

        generation &+= 1
        let activeGeneration = generation
        isStreaming = true
        publish(.streamingChanged(true))
        captureTask = Task { [weak self, newAcquisition] in
            await self?.captureFrames(
                from: newAcquisition,
                generation: activeGeneration
            )
        }
    }

    /// Stops the acquisition but keeps the device session open.
    /// If stop fails, the acquisition and capture task remain owned for retry.
    public func stop() async throws {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }

        guard let acquisition else { return }

        if isStreaming {
            generation &+= 1
            isStreaming = false
            publish(.streamingChanged(false))
        }

        try await acquisition.stop()

        if let task = captureTask {
            captureTask = nil
            await task.value
        }
    }

    /// Closes the acquisition first, then its owning device session.
    /// Any failed close leaves the failed resource retained for a later call.
    public func close() async throws {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }

        generation &+= 1
        if isStreaming {
            isStreaming = false
            publish(.streamingChanged(false))
        }

        captureTask?.cancel()

        if let acquisition {
            try await acquisition.close()
            self.acquisition = nil
        }

        if let task = captureTask {
            captureTask = nil
            await task.value
        }

        if let session {
            try await session.close()
            self.session = nil
        }

        publish(.closed)
    }

    private func captureFrames(
        from acquisition: any CameraRuntimeAcquisition,
        generation activeGeneration: UInt64
    ) async {
        while !Task.isCancelled {
            do {
                let frame = try await acquisition.nextFrame(timeoutMilliseconds: 5_000)
                guard !frame.isIncomplete else { continue }
                guard activeGeneration == generation, isStreaming else { return }
                lastDeliveredFrameSequence = frame.sequence
                publishFrame(frame)
            } catch let failure as CameraAcquisitionFailure {
                switch failure {
                case .timeout:
                    continue
                case .stopped:
                    reportUnexpectedStop(generation: activeGeneration)
                    return
                case .failed(let message):
                    Task { [weak self] in
                        await self?.reportFailure(message, from: acquisition, generation: activeGeneration)
                    }
                    return
                }
            } catch {
                let message = error.localizedDescription
                Task { [weak self] in
                    await self?.reportFailure(message, from: acquisition, generation: activeGeneration)
                }
                return
            }
        }
    }

    private func reportUnexpectedStop(generation activeGeneration: UInt64) {
        guard activeGeneration == generation, isStreaming else { return }
        generation &+= 1
        isStreaming = false
        publish(.streamingChanged(false))
        publish(.failure("The camera acquisition stopped without a stop request."))
    }

    private func reportFailure(
        _ message: String,
        from acquisition: any CameraRuntimeAcquisition,
        generation activeGeneration: UInt64
    ) async {
        guard activeGeneration == generation, isStreaming else { return }

        // A fatal read must stop the producer, not merely abandon the reader.
        // Queue the stop against feature writes and explicit lifecycle operations.
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        guard activeGeneration == generation, isStreaming else { return }

        generation &+= 1
        isStreaming = false
        publish(.streamingChanged(false))

        do {
            try await acquisition.stop()
            publish(.failure(message))
        } catch {
            publish(.failure(
                "\(message) The acquisition also failed to stop: \(error.localizedDescription)"
            ))
        }
    }


    private func acquireLifecycleOperation() async {
        if !lifecycleOperationHeld {
            lifecycleOperationHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            lifecycleOperationWaiters.append(continuation)
        }
    }

    private func releaseLifecycleOperation() {
        if lifecycleOperationWaiters.isEmpty {
            lifecycleOperationHeld = false
        } else {
            lifecycleOperationWaiters.removeFirst().resume()
        }
    }

    private func publish(_ event: CameraSessionLifecycleEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func publishFrame(_ frame: CameraFramePayload) {
        for continuation in frameContinuations.values {
            continuation.yield(frame)
        }
    }

    private func removeEventContinuation(_ identifier: UUID) {
        eventContinuations.removeValue(forKey: identifier)
    }

    private func removeFrameContinuation(_ identifier: UUID) {
        frameContinuations.removeValue(forKey: identifier)
    }
}
