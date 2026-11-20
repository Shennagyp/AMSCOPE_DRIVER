import AmcamImagingApplicationCore
import AmcamImagingCore
import Foundation
import GenTLRouter

/// Adapts one already-open GenTL device session to the portable lifecycle contract.
/// The caller delegates device close responsibility to this wrapper. It may retain
/// the session reference for feature access, but must not close it independently.
public final class GenTLRuntimeDevice: CameraRuntimeDevice, @unchecked Sendable {
    private let candidate: GenTLDeviceCandidate
    private let access: GenTLDeviceAccess

    public init(candidate: GenTLDeviceCandidate, access: GenTLDeviceAccess = .exclusive) {
        self.candidate = candidate
        self.access = access
    }

    public func open() async throws -> any CameraRuntimeSession {
        let candidate = self.candidate
        let access = self.access
        let device = try await Task.detached(priority: .userInitiated) {
            try candidate.open(access: access)
        }.value
        return GenTLRuntimeSession(device: device)
    }
}

/// A GenTL session owned and closed by CameraSessionLifecycle. `featureSession`
/// is a borrowed handle for typed feature access; callers must never close it.
public final class GenTLRuntimeSession: CameraRuntimeSession, @unchecked Sendable {
    private let device: GenTLDeviceSession

    public var featureSession: GenTLDeviceSession { device }

    public init(device: GenTLDeviceSession) {
        self.device = device
    }

    public func makeAcquisition() async throws -> any CameraRuntimeAcquisition {
        let device = self.device
        let acquisition = try await Task.detached(priority: .userInitiated) {
            try GenTLAcquisitionSession(device: device)
        }.value
        return GenTLRuntimeAcquisition(acquisition: acquisition)
    }

    public func close() async throws {
        let device = self.device
        try await Task.detached(priority: .userInitiated) {
            try device.close()
        }.value
    }
}

/// The GenTL implementation is synchronous and may block in EventGetData.
/// Each blocking operation runs on a detached worker so stop/close can execute
/// concurrently and use GenTL EventKill to interrupt a pending frame read.
public final class GenTLRuntimeAcquisition: CameraRuntimeAcquisition, @unchecked Sendable {
    private let acquisition: GenTLAcquisitionSession

    public init(acquisition: GenTLAcquisitionSession) {
        self.acquisition = acquisition
    }

    public func start() async throws {
        let acquisition = self.acquisition
        try await Task.detached(priority: .userInitiated) {
            try acquisition.start()
        }.value
    }

    public func nextFrame(timeoutMilliseconds: UInt64) async throws -> CameraFramePayload {
        let acquisition = self.acquisition
        do {
            let frame = try await Task.detached(priority: .userInitiated) {
                try acquisition.nextFrame(timeoutMilliseconds: timeoutMilliseconds)
            }.value
            return CameraFramePayload(
                width: frame.width,
                height: frame.height,
                pixelFormat: frame.pixelFormat,
                pixelFormatNamespace: frame.pixelFormatNamespace,
                rowPaddingBytes: frame.rowPaddingBytes,
                sizeFilled: frame.sizeFilled,
                dataSize: frame.dataSize,
                sequence: frame.sequence,
                timestamp: frame.timestamp,
                isIncomplete: frame.isIncomplete,
                bytes: frame.bytes
            )
        } catch let error as GenTLAcquisitionError {
            throw Self.map(error)
        }
    }

    public func stop() async throws {
        let acquisition = self.acquisition
        try await Task.detached(priority: .userInitiated) {
            try acquisition.stop()
        }.value
    }

    public func close() async throws {
        let acquisition = self.acquisition
        try await Task.detached(priority: .userInitiated) {
            try acquisition.close()
        }.value
    }

    static func map(_ error: GenTLAcquisitionError) -> CameraAcquisitionFailure {
        switch error {
        case .eventTimeout:
            return .timeout
        case .acquisitionStopped, .sessionClosed, .acquisitionNotStarted:
            return .stopped
        default:
            return .failed(error.localizedDescription)
        }
    }
}
