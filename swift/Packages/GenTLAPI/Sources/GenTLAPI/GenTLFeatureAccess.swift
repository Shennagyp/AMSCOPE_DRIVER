import GenTLABI

/// The semantic type of a feature exposed by a GenApi-compatible or
/// SDK-backed feature provider. This is deliberately separate from GenTLAPI:
/// GenTL 1.6 transports register access; it does not prescribe these Swift types.
public enum GenTLFeatureKind: String, Codable, Equatable, Sendable {
    case boolean
    case integer
    case floatingPoint
    case string
    case enumeration
}

/// A typed feature value. Enumeration values use their symbolic names, not
/// transport-specific integer encodings.
public enum GenTLFeatureValue: Equatable, Sendable {
    case boolean(Bool)
    case integer(Int64)
    case floatingPoint(Double)
    case string(String)
    case enumeration(String)

    public var kind: GenTLFeatureKind {
        switch self {
        case .boolean: return .boolean
        case .integer: return .integer
        case .floatingPoint: return .floatingPoint
        case .string: return .string
        case .enumeration: return .enumeration
        }
    }
}

/// Inclusive numeric bounds and an optional positive increment, expressed in
/// the feature's declared unit.
public struct GenTLFeatureNumericRange: Equatable, Sendable {
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

public struct GenTLFeatureDescriptor: Equatable, Sendable, Identifiable {
    public let name: String
    public let displayName: String
    public let kind: GenTLFeatureKind
    public let unit: String?
    public let isAvailable: Bool
    public let isReadable: Bool
    public let isWritable: Bool
    public let numericRange: GenTLFeatureNumericRange?
    public let enumerationValues: [String]

    public var id: String { name }

    public init(
        name: String,
        displayName: String,
        kind: GenTLFeatureKind,
        unit: String? = nil,
        isAvailable: Bool,
        isReadable: Bool,
        isWritable: Bool,
        numericRange: GenTLFeatureNumericRange? = nil,
        enumerationValues: [String] = []
    ) {
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.unit = unit
        self.isAvailable = isAvailable
        self.isReadable = isReadable
        self.isWritable = isWritable
        self.numericRange = numericRange
        self.enumerationValues = enumerationValues
    }
}

public enum GenTLFeatureAccessError: Error, Equatable, Sendable {
    case featureNotFound(String)
    case featureUnavailable(String)
    case featureNotReadable(String)
    case featureNotWritable(String)
    case valueTypeMismatch(feature: String, expected: GenTLFeatureKind, actual: GenTLFeatureKind)
    case invalidValue(String)
}

/// Optional typed feature access layered beside the exact GenTL 1.6 operation
/// contract. A provider may implement this using GenApi over GenTL ports or a
/// documented vendor SDK API. Callers must inspect descriptors before access.
public protocol GenTLFeatureAccess: Sendable {
    func featureDescriptors(for device: GenTLABI.DEV_HANDLE) throws -> [GenTLFeatureDescriptor]
    func readFeature(_ name: String, from device: GenTLABI.DEV_HANDLE) throws -> GenTLFeatureValue
    func writeFeature(
        _ value: GenTLFeatureValue,
        named name: String,
        to device: GenTLABI.DEV_HANDLE
    ) throws
}
