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
    private var generation: UInt64 = 0
    private var continuations: [UUID: AsyncStream<CameraSessionLifecycleEvent>.Continuation] = [:]

    public init() {}

    public func events() -> AsyncStream<CameraSessionLifecycleEvent> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            continuations[identifier] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeContinuation(identifier) }
            }
        }
    }

    public func snapshot() -> CameraSessionLifecycleSnapshot {
        CameraSessionLifecycleSnapshot(
            hasSession: session != nil,
            hasAcquisition: acquisition != nil,
            isStreaming: isStreaming
        )
    }

    public func attach(_ newSession: any CameraRuntimeSession) throws {
        guard session == nil, acquisition == nil, captureTask == nil else {
            throw CameraSessionLifecycleError.sessionAlreadyAttached
        }
        session = newSession
    }

    public func start() async throws {
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
                publish(.frame(frame))
            } catch let failure as CameraAcquisitionFailure {
                switch failure {
                case .timeout:
                    continue
                case .stopped:
                    return
                case .failed(let message):
                    reportFailure(message, generation: activeGeneration)
                    return
                }
            } catch {
                reportFailure(error.localizedDescription, generation: activeGeneration)
                return
            }
        }
    }

    private func reportFailure(_ message: String, generation activeGeneration: UInt64) {
        guard activeGeneration == generation, isStreaming else { return }
        generation &+= 1
        isStreaming = false
        publish(.streamingChanged(false))
        publish(.failure(message))
    }

    private func publish(_ event: CameraSessionLifecycleEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ identifier: UUID) {
        continuations.removeValue(forKey: identifier)
    }
}
