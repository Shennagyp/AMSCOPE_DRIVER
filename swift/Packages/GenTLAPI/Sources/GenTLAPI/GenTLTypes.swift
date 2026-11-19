import Foundation

/// GenTL 1.6 return codes. Raw values are defined by the EMVA GenTL header.
public enum GC_ERROR: Int32, Error, CaseIterable, Sendable {
    case success = 0
    case error = -1001
    case notInitialized = -1002
    case notImplemented = -1003
    case resourceInUse = -1004
    case accessDenied = -1005
    case invalidHandle = -1006
    case invalidID = -1007
    case noData = -1008
    case invalidParameter = -1009
    case io = -1010
    case timeout = -1011
    case abort = -1012
    case invalidBuffer = -1013
    case notAvailable = -1014
    case invalidAddress = -1015
    case bufferTooSmall = -1016
    case invalidIndex = -1017
    case parsingChunkData = -1018
    case invalidValue = -1019
    case resourceExhausted = -1020
    case outOfMemory = -1021
    case busy = -1022
    case ambiguous = -1023
    case customID = -10000

    public static let GC_ERR_SUCCESS = Self.success
    public static let GC_ERR_ERROR = Self.error
    public static let GC_ERR_NOT_INITIALIZED = Self.notInitialized
    public static let GC_ERR_NOT_IMPLEMENTED = Self.notImplemented
    public static let GC_ERR_RESOURCE_IN_USE = Self.resourceInUse
    public static let GC_ERR_ACCESS_DENIED = Self.accessDenied
    public static let GC_ERR_INVALID_HANDLE = Self.invalidHandle
    public static let GC_ERR_INVALID_ID = Self.invalidID
    public static let GC_ERR_NO_DATA = Self.noData
    public static let GC_ERR_INVALID_PARAMETER = Self.invalidParameter
    public static let GC_ERR_IO = Self.io
    public static let GC_ERR_TIMEOUT = Self.timeout
    public static let GC_ERR_ABORT = Self.abort
    public static let GC_ERR_INVALID_BUFFER = Self.invalidBuffer
    public static let GC_ERR_NOT_AVAILABLE = Self.notAvailable
    public static let GC_ERR_INVALID_ADDRESS = Self.invalidAddress
    public static let GC_ERR_BUFFER_TOO_SMALL = Self.bufferTooSmall
    public static let GC_ERR_INVALID_INDEX = Self.invalidIndex
    public static let GC_ERR_PARSING_CHUNK_DATA = Self.parsingChunkData
    public static let GC_ERR_INVALID_VALUE = Self.invalidValue
    public static let GC_ERR_RESOURCE_EXHAUSTED = Self.resourceExhausted
    public static let GC_ERR_OUT_OF_MEMORY = Self.outOfMemory
    public static let GC_ERR_BUSY = Self.busy
    public static let GC_ERR_AMBIGUOUS = Self.ambiguous
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
public struct GenTLHandle<Tag: Sendable>: Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public var isValid: Bool { rawValue != GenTLConstants.invalidHandle }
}

public enum TLModule: Sendable {}
public enum IFModule: Sendable {}
public enum DEVModule: Sendable {}
public enum DSModule: Sendable {}
public enum PORTModule: Sendable {}
public enum BUFFERModule: Sendable {}
public enum EVENTModule: Sendable {}

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
