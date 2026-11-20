import AmcamImagingRuntime
import AmcamImagingCore
import Foundation
import GenTLRouter
import GenTLAPI
import GenTLABI

/// Opens a discovered GenTL candidate on behalf of the imaging runtime and adapts
/// the resulting session to the backend-neutral lifecycle contract.
public final class GenTLRuntimeDevice: CameraRuntimeDevice, @unchecked Sendable {
    private let candidate: GenTLDeviceCandidate
    private let access: GenTLDeviceAccessMode

    public init(candidate: GenTLDeviceCandidate, access: GenTLDeviceAccessMode = .exclusive) {
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

/// Keeps the GenTL handle private while exposing the backend-neutral runtime contract.
public final class GenTLRuntimeSession: CameraRuntimeSession, @unchecked Sendable {
    private let device: GenTLDeviceSession
    public init(device: GenTLDeviceSession) { self.device = device }
    public func supportsAcquisition() async -> Bool {
        let device = self.device
        return await Task.detached(priority: .userInitiated) {
            var count: UInt32 = 0
            return device.api.DevGetNumDataStreams(device.deviceHandle, &count) == GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) && count > 0
        }.value
    }
    public func featureDescriptors() async throws -> [CameraFeatureDescriptor] {
        let device = self.device
        do {
            return try await Task.detached(priority: .userInitiated) {
                try device.featureDescriptors().map(Self.map)
            }.value
        } catch {
            throw Self.mapFeatureError(error)
        }
    }
    public func readFeature(_ name: String) async throws -> CameraFeatureValue {
        let device = self.device
        do {
            return try await Task.detached(priority: .userInitiated) {
                Self.map(try device.readFeature(name))
            }.value
        } catch {
            throw Self.mapFeatureError(error)
        }
    }
    public func writeFeature(_ value: CameraFeatureValue, named name: String) async throws {
        let device = self.device
        do {
            try await Task.detached(priority: .userInitiated) {
                try device.writeFeature(Self.map(value), named: name)
            }.value
        } catch {
            throw Self.mapFeatureError(error)
        }
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
        try await Task.detached(priority: .userInitiated) { try device.close() }.value
    }
    private static func mapFeatureError(_ error: Error) -> CameraFeatureAccessError {
        guard let error = error as? GenTLFeatureAccessError else {
            return .backendFailure(error.localizedDescription)
        }
        switch error {
        case .featureNotFound(let name): return .featureNotFound(name)
        case .featureUnavailable(let name): return .featureUnavailable(name)
        case .featureNotReadable(let name): return .featureNotReadable(name)
        case .featureNotWritable(let name): return .featureNotWritable(name)
        case .valueTypeMismatch(let feature, let expected, let actual):
            return .valueTypeMismatch(feature: feature, expected: map(expected), actual: map(actual))
        case .invalidValue(let message): return .invalidValue(message)
        }
    }

    private static func map(_ kind: GenTLFeatureKind) -> CameraFeatureKind {
        switch kind {
        case .boolean: return .boolean
        case .integer: return .integer
        case .integerVector: return .integerVector
        case .floatingPoint: return .floatingPoint
        case .string: return .string
        case .enumeration: return .enumeration
        }
    }
    private static func map(_ value: GenTLFeatureValue) -> CameraFeatureValue {
        switch value {
        case .boolean(let v): return .boolean(v)
        case .integer(let v): return .integer(v)
        case .integerVector(let v): return .integerVector(v)
        case .floatingPoint(let v): return .floatingPoint(v)
        case .string(let v): return .string(v)
        case .enumeration(let v): return .enumeration(v)
        }
    }
    private static func map(_ value: CameraFeatureValue) -> GenTLFeatureValue {
        switch value {
        case .boolean(let v): return .boolean(v)
        case .integer(let v): return .integer(v)
        case .integerVector(let v): return .integerVector(v)
        case .floatingPoint(let v): return .floatingPoint(v)
        case .string(let v): return .string(v)
        case .enumeration(let v): return .enumeration(v)
        }
    }
    private static func map(_ descriptor: GenTLFeatureDescriptor) -> CameraFeatureDescriptor {
        let range = descriptor.numericRange.flatMap {
            CameraFeatureNumericRange(minimum: $0.minimum, maximum: $0.maximum, increment: $0.increment)
        }
        return CameraFeatureDescriptor(
            name: descriptor.name,
            displayName: descriptor.displayName,
            kind: map(descriptor.kind),
            unit: descriptor.unit,
            isAvailable: descriptor.isAvailable,
            isReadable: descriptor.isReadable,
            isWritable: descriptor.isWritable,
            numericRange: range,
            elementCount: descriptor.elementCount,
            enumerationValues: descriptor.enumerationValues
        )
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
