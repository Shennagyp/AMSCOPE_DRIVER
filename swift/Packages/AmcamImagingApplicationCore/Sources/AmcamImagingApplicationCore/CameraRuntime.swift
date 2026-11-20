import AmcamImagingCore
import Foundation

/// Recoverable outcomes from a camera acquisition read.
/// Timeouts do not invalidate the acquisition; stopped means the read loop
/// should terminate normally. Other errors are reported as failures.
public enum CameraAcquisitionFailure: Error, Equatable, Sendable {
    case timeout
    case stopped
    case failed(String)
}

/// Backend adapter contract for one opened camera acquisition.
/// Implementations must make stop/close interrupt a pending nextFrame call.
public protocol CameraRuntimeAcquisition: Sendable {
    func start() async throws
    func nextFrame(timeoutMilliseconds: UInt64) async throws -> CameraFramePayload
    func stop() async throws
    func close() async throws
}

/// Backend adapter contract for one opened device session.
/// The session owns the device; its acquisition is a child resource.
public protocol CameraRuntimeSession: Sendable {
    func makeAcquisition() async throws -> any CameraRuntimeAcquisition
    func close() async throws
}

/// Events emitted by the portable session lifecycle coordinator.
public enum CameraSessionLifecycleEvent: Equatable, Sendable {
    case frame(CameraFramePayload)
    case streamingChanged(Bool)
    case failure(String)
    case closed
}

/// A read-only snapshot of resource ownership and stream state.
public struct CameraSessionLifecycleSnapshot: Equatable, Sendable {
    public let hasSession: Bool
    public let hasAcquisition: Bool
    public let isStreaming: Bool

    public init(hasSession: Bool, hasAcquisition: Bool, isStreaming: Bool) {
        self.hasSession = hasSession
        self.hasAcquisition = hasAcquisition
        self.isStreaming = isStreaming
    }
}

public enum CameraSessionLifecycleError: Error, Equatable, Sendable {
    case sessionNotAttached
    case sessionAlreadyAttached
    case acquisitionAlreadyRunning
}
