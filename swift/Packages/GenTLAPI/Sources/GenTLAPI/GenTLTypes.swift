import Foundation

/// GenTL 1.6 return codes. Raw values are defined by the EMVA GenTL header.
public struct GC_ERROR: RawRepresentable, Error, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public var description: String {
        Self.knownNames[rawValue] ?? "GC_ERROR(\(rawValue))"
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
    case bool8(Bool)
    case size(Int)
    case pointerDifference(Int)
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


/// GenTL INFO function data-type identifiers (INFO_DATATYPE in GenTL 1.6).
public enum GenTLInfoDataType: Int32, Sendable {
    case unknown = 0
    case string = 1
    case stringList = 2
    case int16 = 3
    case uint16 = 4
    case int32 = 5
    case uint32 = 6
    case int64 = 7
    case uint64 = 8
    case float64 = 9
    case pointer = 10
    case bool8 = 11
    case size = 12
    case buffer = 13
    case pointerDifference = 14
}

/// Standard GenTL 1.6 command identifiers used by INFO functions.
public enum GenTLInfoCommand {
    public enum TransportLayer: Int32, Sendable {
        case id = 0, vendor = 1, model = 2, version = 3, transportType = 4
        case fileName = 5, pathName = 6, displayName = 7, charEncoding = 8
    }
    public enum Interface: Int32, Sendable {
        case id = 0, displayName = 1, transportType = 2
    }
    public enum Device: Int32, Sendable {
        case id = 0, vendor = 1, model = 2, transportType = 3
        case displayName = 4, accessStatus = 5, userDefinedName = 6
        case serialNumber = 7, version = 8, timestampFrequency = 9
    }
    public enum Port: Int32, Sendable {
        case id = 0, vendor = 1, model = 2, transportType = 3
        case module = 4, littleEndian = 5, bigEndian = 6
        case accessRead = 7, accessWrite = 8, accessNotAvailable = 9
        case accessNotImplemented = 10, version = 11, portName = 12
    }
    public enum Stream: Int32, Sendable {
        case id = 0, numDelivered = 1, numUnderrun = 2, numAnnounced = 3
        case numQueued = 4, numAwaitDelivery = 5, numStarted = 6
        case payloadSize = 7, isGrabbing = 8, definesPayloadSize = 9
        case transportType = 10
    }
    public enum Buffer: Int32, Sendable {
        case base = 0, size = 1, userPointer = 2, timestamp = 3
        case newData = 4, isQueued = 5, isAcquiring = 6, isIncomplete = 7
        case transportType = 8, sizeFilled = 9, width = 10, height = 11
        case xOffset = 12, yOffset = 13, xPadding = 14, yPadding = 15
        case frameID = 16, imagePresent = 17, imageOffset = 18, payloadType = 19
        case pixelFormat = 20, pixelFormatNamespace = 21, deliveredImageHeight = 22
        case deliveredChunkPayloadSize = 23, chunkLayoutID = 24, fileName = 25
        case pixelEndianness = 26, dataSize = 27, timestampNanoseconds = 28
        case dataLargerThanBuffer = 29, containsChunkData = 30, isComposite = 31
    }
    public enum Event: Int32, Sendable {
        case eventType = 0, numInQueue = 1, numFired = 2, maxSize = 3
        case infoDataSizeMax = 4
    }
    public enum EventData: Int32, Sendable {
        case id = 0, value = 1, numericID = 2
    }
}

/// Standard GenTL event identifiers.
public enum GenTLEventType: Int32, Sendable {
    case error = 0
    case newBuffer = 1
    case featureInvalidate = 2
    case featureChange = 3
    case remoteDevice = 4
    case module = 5
}

/// Standard GenTL acquisition queue operations.
public enum GenTLQueueOperation: Int32, Sendable {
    case inputToOutput = 0
    case outputDiscard = 1
    case allToInput = 2
    case unqueuedToInput = 3
    case allDiscard = 4
}

/// Standard GenTL device access modes.
public enum GenTLDeviceAccess: Int32, Sendable {
    case unknown = 0
    case none = 1
    case readOnly = 2
    case control = 3
    case exclusive = 4
}


/// Register-stack read request. Each entry is one independent address/size operation.
public struct GenTLPortReadRequest: Sendable, Equatable {
    public let address: UInt64
    public let size: Int

    public init(address: UInt64, size: Int) {
        self.address = address
        self.size = size
    }
}

/// Register-stack write request.
public struct GenTLPortWriteRequest: Sendable, Equatable {
    public let address: UInt64
    public let data: Data

    public init(address: UInt64, data: Data) {
        self.address = address
        self.data = data
    }
}

/// Chunk metadata reported by DSGetBufferChunkData.
public struct GenTLChunkData: Sendable, Equatable {
    public let chunkID: UInt64
    public let offset: Int64
    public let length: Int

    public init(chunkID: UInt64, offset: Int64, length: Int) {
        self.chunkID = chunkID
        self.offset = offset
        self.length = length
    }
}

/// One request entry for GenTL 1.6 DSGetBufferPartInfoStacked.
public struct GenTLBufferPartInfoStackedRequest: Sendable, Equatable {
    public let partIndex: UInt32
    public let command: Int32

    public init(partIndex: UInt32, command: Int32) {
        self.partIndex = partIndex
        self.command = command
    }
}

/// One memory segment for GenTL 1.6 composite-buffer announcement.
public struct GenTLCompositeBufferSegment: @unchecked Sendable {
    public let memory: GenTLBufferMemory

    public init(memory: GenTLBufferMemory) {
        self.memory = memory
    }
}
