import Foundation

/// GenTL 1.6 return codes. Raw values are defined by the EMVA GenTL header.
public struct GC_ERROR: RawRepresentable, Error, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public var description: String {
        Self.knownNames[rawValue] ?? "GC_ERROR(\\(rawValue))"
    }

    private static let knownNames: [Int32: String] = [
        0: "GC_ERR_SUCCESS",
        -1001: "GC_ERR_ERROR",
        -1002: "GC_ERR_NOT_INITIALIZED",
        -1003: "GC_ERR_NOT_IMPLEMENTED",
        -1004: "GC_ERR_RESOURCE_IN_USE",
        -1005: "GC_ERR_ACCESS_DENIED",
        -1006: "GC_ERR_INVALID_HANDLE",
        -1007: "GC_ERR_INVALID_ID",
        -1008: "GC_ERR_NO_DATA",
        -1009: "GC_ERR_INVALID_PARAMETER",
        -1010: "GC_ERR_IO",
        -1011: "GC_ERR_TIMEOUT",
        -1012: "GC_ERR_ABORT",
        -1013: "GC_ERR_INVALID_BUFFER",
        -1014: "GC_ERR_NOT_AVAILABLE",
        -1015: "GC_ERR_INVALID_ADDRESS",
        -1016: "GC_ERR_BUFFER_TOO_SMALL",
        -1017: "GC_ERR_INVALID_INDEX",
        -1018: "GC_ERR_PARSING_CHUNK_DATA",
        -1019: "GC_ERR_INVALID_VALUE",
        -1020: "GC_ERR_RESOURCE_EXHAUSTED",
        -1021: "GC_ERR_OUT_OF_MEMORY",
        -1022: "GC_ERR_BUSY",
        -1023: "GC_ERR_AMBIGUOUS",
        -10000: "GC_ERR_CUSTOM_ID"
    ]

    public static let success = GC_ERROR(rawValue: 0)
    public static let error = GC_ERROR(rawValue: -1001)
    public static let notInitialized = GC_ERROR(rawValue: -1002)
    public static let notImplemented = GC_ERROR(rawValue: -1003)
    public static let resourceInUse = GC_ERROR(rawValue: -1004)
    public static let accessDenied = GC_ERROR(rawValue: -1005)
    public static let invalidHandle = GC_ERROR(rawValue: -1006)
    public static let invalidID = GC_ERROR(rawValue: -1007)
    public static let noData = GC_ERROR(rawValue: -1008)
    public static let invalidParameter = GC_ERROR(rawValue: -1009)
    public static let io = GC_ERROR(rawValue: -1010)
    public static let timeout = GC_ERROR(rawValue: -1011)
    public static let abort = GC_ERROR(rawValue: -1012)
    public static let invalidBuffer = GC_ERROR(rawValue: -1013)
    public static let notAvailable = GC_ERROR(rawValue: -1014)
    public static let invalidAddress = GC_ERROR(rawValue: -1015)
    public static let bufferTooSmall = GC_ERROR(rawValue: -1016)
    public static let invalidIndex = GC_ERROR(rawValue: -1017)
    public static let parsingChunkData = GC_ERROR(rawValue: -1018)
    public static let invalidValue = GC_ERROR(rawValue: -1019)
    public static let resourceExhausted = GC_ERROR(rawValue: -1020)
    public static let outOfMemory = GC_ERROR(rawValue: -1021)
    public static let busy = GC_ERROR(rawValue: -1022)
    public static let ambiguous = GC_ERROR(rawValue: -1023)
    public static let customID = GC_ERROR(rawValue: -10000)

    public static let GC_ERR_SUCCESS = success
    public static let GC_ERR_ERROR = error
    public static let GC_ERR_NOT_INITIALIZED = notInitialized
    public static let GC_ERR_NOT_IMPLEMENTED = notImplemented
    public static let GC_ERR_RESOURCE_IN_USE = resourceInUse
    public static let GC_ERR_ACCESS_DENIED = accessDenied
    public static let GC_ERR_INVALID_HANDLE = invalidHandle
    public static let GC_ERR_INVALID_ID = invalidID
    public static let GC_ERR_NO_DATA = noData
    public static let GC_ERR_INVALID_PARAMETER = invalidParameter
    public static let GC_ERR_IO = io
    public static let GC_ERR_TIMEOUT = timeout
    public static let GC_ERR_ABORT = abort
    public static let GC_ERR_INVALID_BUFFER = invalidBuffer
    public static let GC_ERR_NOT_AVAILABLE = notAvailable
    public static let GC_ERR_INVALID_ADDRESS = invalidAddress
    public static let GC_ERR_BUFFER_TOO_SMALL = bufferTooSmall
    public static let GC_ERR_INVALID_INDEX = invalidIndex
    public static let GC_ERR_PARSING_CHUNK_DATA = parsingChunkData
    public static let GC_ERR_INVALID_VALUE = invalidValue
    public static let GC_ERR_RESOURCE_EXHAUSTED = resourceExhausted
    public static let GC_ERR_OUT_OF_MEMORY = outOfMemory
    public static let GC_ERR_BUSY = busy
    public static let GC_ERR_AMBIGUOUS = ambiguous
}

public struct GenTLVersion: Hashable, Sendable {
    public let major: UInt16
    public let minor: UInt16
    public let subMinor: UInt16

    public init(major: UInt16, minor: UInt16, subMinor: UInt16 = 0) {
        self.major = major
        self.minor = minor
        self.subMinor = subMinor
    }

    public static let v1_6 = GenTLVersion(major: 1, minor: 6)
}

public enum GenTLConstants {
    public static let infiniteTimeout: UInt64 = .max
    public static let invalidHandle: UInt = 0
}

/// Typed representation of the opaque void* handles defined by GenTL.
/// The raw value is an opaque token; callers must not infer object identity from it.
public struct GenTLHandle<Tag: Hashable & Sendable>: Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public var isValid: Bool { rawValue != GenTLConstants.invalidHandle }
}

public enum TLModule: Hashable, Sendable {}
public enum IFModule: Hashable, Sendable {}
public enum DEVModule: Hashable, Sendable {}
public enum DSModule: Hashable, Sendable {}
public enum PORTModule: Hashable, Sendable {}
public enum BUFFERModule: Hashable, Sendable {}
public enum EVENTModule: Hashable, Sendable {}

public typealias TL_HANDLE = GenTLHandle<TLModule>
public typealias IF_HANDLE = GenTLHandle<IFModule>
public typealias DEV_HANDLE = GenTLHandle<DEVModule>
public typealias DS_HANDLE = GenTLHandle<DSModule>
public typealias PORT_HANDLE = GenTLHandle<PORTModule>
public typealias BUFFER_HANDLE = GenTLHandle<BUFFERModule>
public typealias EVENT_HANDLE = GenTLHandle<EVENTModule>

/// GenTL event sources may be System, Interface, Device, Data Stream or Buffer modules.
public enum EVENTSRC_HANDLE: Hashable, Sendable {
    case system(TL_HANDLE)
    case interface(IF_HANDLE)
    case device(DEV_HANDLE)
    case dataStream(DS_HANDLE)
    case buffer(BUFFER_HANDLE)
}

/// An info value returned by the GenTL INFO functions.
/// The raw case preserves values that are not yet decoded by this Swift wrapper.
public enum GenTLInfoValue: Equatable, Sendable {
    case string(String)
    case stringList([String])
    case int16(Int16)
    case uint16(UInt16)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case float64(Double)
    case pointer(UInt)
    case raw(Data)
}

public struct GenTLErrorInfo: Equatable, Sendable {
    public let code: GC_ERROR
    public let message: String

    public init(code: GC_ERROR, message: String) {
        self.code = code
        self.message = message
    }
}

/// Memory supplied by a GenTL consumer to DSAnnounceBuffer.
/// Its storage must remain alive and unchanged until DSRevokeBuffer succeeds.
public struct GenTLBufferMemory: @unchecked Sendable {
    public let baseAddress: UnsafeMutableRawPointer
    public let size: Int

    public init(baseAddress: UnsafeMutableRawPointer, size: Int) {
        self.baseAddress = baseAddress
        self.size = size
    }
}

/// Memory and private data returned when a consumer-owned buffer is revoked.
public struct GenTLRevokedBuffer: @unchecked Sendable {
    public let baseAddress: UnsafeMutableRawPointer?
    public let privateData: UnsafeMutableRawPointer?

    public init(baseAddress: UnsafeMutableRawPointer?, privateData: UnsafeMutableRawPointer?) {
        self.baseAddress = baseAddress
        self.privateData = privateData
    }
}
