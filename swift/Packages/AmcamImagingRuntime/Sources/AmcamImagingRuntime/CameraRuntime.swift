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

/// Backend adapter contract for a discovered camera device.
/// The imaging runtime invokes open() and assumes ownership of the returned session.
public protocol CameraRuntimeDevice: Sendable {
    func open() async throws -> any CameraRuntimeSession
}


public enum CameraFeatureKind: String, Codable, Equatable, Sendable {
    case boolean, integer, integerVector, floatingPoint, string, enumeration
}
public enum CameraFeatureValue: Equatable, Sendable {
    case boolean(Bool), integer(Int64), integerVector([Int64]), floatingPoint(Double), string(String), enumeration(String)
    public var kind: CameraFeatureKind {
        switch self {
        case .boolean: return .boolean
        case .integer: return .integer
        case .integerVector: return .integerVector
        case .floatingPoint: return .floatingPoint
        case .string: return .string
        case .enumeration: return .enumeration
        }
    }
}
public struct CameraFeatureNumericRange: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double
    public let increment: Double?
    public init?(minimum: Double, maximum: Double, increment: Double? = nil) {
        guard minimum.isFinite, maximum.isFinite, minimum <= maximum else { return nil }
        if let increment, (!increment.isFinite || increment <= 0) { return nil }
        self.minimum = minimum
        self.maximum = maximum
        self.increment = increment
    }
}
public struct CameraFeatureDescriptor: Equatable, Sendable, Identifiable {
    public let name: String
    public let displayName: String
    public let kind: CameraFeatureKind
    public let unit: String?
    public let isAvailable: Bool
    public let isReadable: Bool
    public let isWritable: Bool
    public let numericRange: CameraFeatureNumericRange?
    public let elementCount: Int?
    public let enumerationValues: [String]
    public var id: String { name }
    public init(name: String, displayName: String, kind: CameraFeatureKind, unit: String? = nil, isAvailable: Bool, isReadable: Bool, isWritable: Bool, numericRange: CameraFeatureNumericRange? = nil, elementCount: Int? = nil, enumerationValues: [String] = []) {
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.unit = unit
        self.isAvailable = isAvailable
        self.isReadable = isReadable
        self.isWritable = isWritable
        self.numericRange = numericRange
        self.elementCount = elementCount
        self.enumerationValues = enumerationValues
    }
}
public enum CameraFeatureAccessError: Error, Equatable, Sendable, LocalizedError {
    case unsupported
    case featureNotFound(String)
    case featureUnavailable(String)
    case featureNotReadable(String)
    case featureNotWritable(String)
    case valueTypeMismatch(feature: String, expected: CameraFeatureKind, actual: CameraFeatureKind)
    case invalidValue(String)
    case backendFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported: return "This camera backend does not expose typed feature access."
        case .featureNotFound(let name): return "Camera feature '\(name)' was not found."
        case .featureUnavailable(let name): return "Camera feature '\(name)' is currently unavailable."
        case .featureNotReadable(let name): return "Camera feature '\(name)' is not readable."
        case .featureNotWritable(let name): return "Camera feature '\(name)' is not writable."
        case .valueTypeMismatch(let name, let expected, let actual):
            return "Camera feature '\(name)' expects \(expected.rawValue), received \(actual.rawValue)."
        case .invalidValue(let message): return message
        case .backendFailure(let message): return message
        }
    }
}
/// Application-facing camera session. Transport handles remain inside adapters.
public protocol CameraRuntimeSession: Sendable {
    func supportsAcquisition() async -> Bool
    func featureDescriptors() async throws -> [CameraFeatureDescriptor]
    func readFeature(_ name: String) async throws -> CameraFeatureValue
    func writeFeature(_ value: CameraFeatureValue, named name: String) async throws
    func makeAcquisition() async throws -> any CameraRuntimeAcquisition
    func close() async throws
}
public extension CameraRuntimeSession {
    func supportsAcquisition() async -> Bool { false }
    func featureDescriptors() async throws -> [CameraFeatureDescriptor] {
        throw CameraFeatureAccessError.unsupported
    }
    func readFeature(_ name: String) async throws -> CameraFeatureValue {
        throw CameraFeatureAccessError.unsupported
    }
    func writeFeature(_ value: CameraFeatureValue, named name: String) async throws {
        throw CameraFeatureAccessError.unsupported
    }
}

/// Events emitted by the portable session lifecycle coordinator.
public enum CameraSessionLifecycleEvent: Equatable, Sendable {
    case streamingChanged(Bool)
    case failure(String)
    case closed
}

/// A read-only snapshot of resource ownership and stream state.
public struct CameraSessionLifecycleSnapshot: Equatable, Sendable {
    public let hasSession: Bool
    public let hasAcquisition: Bool
    public let isStreaming: Bool
    public let lastDeliveredFrameSequence: UInt64?

    public init(
        hasSession: Bool,
        hasAcquisition: Bool,
        isStreaming: Bool,
        lastDeliveredFrameSequence: UInt64?
    ) {
        self.hasSession = hasSession
        self.hasAcquisition = hasAcquisition
        self.isStreaming = isStreaming
        self.lastDeliveredFrameSequence = lastDeliveredFrameSequence
    }
}

public enum CameraSessionLifecycleError: Error, Equatable, Sendable {
    case sessionNotAttached
    case sessionAlreadyAttached
    case acquisitionAlreadyRunning
    case operationInProgress
}
