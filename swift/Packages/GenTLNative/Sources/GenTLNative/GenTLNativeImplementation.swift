import Darwin
import Foundation
import GenTLABI
import GenTLAPI

private typealias GCInitLibFunction = @convention(c) () -> Int32
private typealias GCCloseLibFunction = @convention(c) () -> Int32
private typealias GCGetLastErrorFunction = @convention(c) (
    UnsafeMutablePointer<Int32>?,
    UnsafeMutablePointer<CChar>?,
    UnsafeMutablePointer<Int>?
) -> Int32

private typealias TLOpenFunction = @convention(c) (
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias TLCloseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias TLGetNumInterfacesFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias TLGetInterfaceIDFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UInt32,
    UnsafeMutablePointer<CChar>?,
    UnsafeMutablePointer<Int>?
) -> Int32
private typealias TLUpdateInterfaceListFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UInt8>?,
    UInt64
) -> Int32
private typealias TLOpenInterfaceFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32

private typealias IFCloseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias IFUpdateDeviceListFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UInt8>?,
    UInt64
) -> Int32
private typealias IFGetNumDevicesFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UInt32>?
) -> Int32
private typealias IFGetDeviceIDFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UInt32,
    UnsafeMutablePointer<CChar>?,
    UnsafeMutablePointer<Int>?
) -> Int32
private typealias IFOpenDeviceFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UInt32,
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32
private typealias DevCloseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32

/// Direct GenTL Consumer implementation backed by one vendor .cti Producer.
///
/// Each instance owns one CTI library/System. Register multiple instances with
/// GenTLRouter when multiple independent Producers are installed.
public final class GenTLNativeImplementation: GenTLAPI, @unchecked Sendable {
    private struct Functions {
        let gcInitLib: GCInitLibFunction
        let gcCloseLib: GCCloseLibFunction
        let gcGetLastError: GCGetLastErrorFunction
        let tlOpen: TLOpenFunction
        let tlClose: TLCloseFunction
        let tlGetNumInterfaces: TLGetNumInterfacesFunction
        let tlGetInterfaceID: TLGetInterfaceIDFunction
        let tlUpdateInterfaceList: TLUpdateInterfaceListFunction
        let tlOpenInterface: TLOpenInterfaceFunction
        let ifClose: IFCloseFunction
        let ifUpdateDeviceList: IFUpdateDeviceListFunction
        let ifGetNumDevices: IFGetNumDevicesFunction
        let ifGetDeviceID: IFGetDeviceIDFunction
        let ifOpenDevice: IFOpenDeviceFunction
        let devClose: DevCloseFunction
    }

    private let library: GenTLProducerLibrary
    private let functions: Functions
    private let lock = NSRecursiveLock()
    private var initialized = false

    public let genTLVersion = GenTLVersion.v1_6
    public static var compiledHeaderVersionCode: UInt32 {
        GenTLABI_HeaderVersion()
    }

    public init(ctiURL: URL) throws {
        let library = try GenTLProducerLibrary(url: ctiURL)

        func load<T>(_ name: String, as type: T.Type) throws -> T {
            let address = try library.resolveSymbol(name)
            return unsafeBitCast(address, to: type)
        }

        self.library = library
        self.functions = try Functions(
            gcInitLib: load("GCInitLib", as: GCInitLibFunction.self),
            gcCloseLib: load("GCCloseLib", as: GCCloseLibFunction.self),
            gcGetLastError: load("GCGetLastError", as: GCGetLastErrorFunction.self),
            tlOpen: load("TLOpen", as: TLOpenFunction.self),
            tlClose: load("TLClose", as: TLCloseFunction.self),
            tlGetNumInterfaces: load("TLGetNumInterfaces", as: TLGetNumInterfacesFunction.self),
            tlGetInterfaceID: load("TLGetInterfaceID", as: TLGetInterfaceIDFunction.self),
            tlUpdateInterfaceList: load("TLUpdateInterfaceList", as: TLUpdateInterfaceListFunction.self),
            tlOpenInterface: load("TLOpenInterface", as: TLOpenInterfaceFunction.self),
            ifClose: load("IFClose", as: IFCloseFunction.self),
            ifUpdateDeviceList: load("IFUpdateDeviceList", as: IFUpdateDeviceListFunction.self),
            ifGetNumDevices: load("IFGetNumDevices", as: IFGetNumDevicesFunction.self),
            ifGetDeviceID: load("IFGetDeviceID", as: IFGetDeviceIDFunction.self),
            ifOpenDevice: load("IFOpenDevice", as: IFOpenDeviceFunction.self),
            devClose: load("DevClose", as: DevCloseFunction.self)
        )
    }

    public func GCInitLib() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !initialized else { throw GC_ERROR.resourceInUse }
        try check(functions.gcInitLib())
        initialized = true
    }

    public func GCCloseLib() throws {
        lock.lock()
        defer { lock.unlock() }
        guard initialized else { throw GC_ERROR.notInitialized }
        try check(functions.gcCloseLib())
        initialized = false
    }

    public func GCGetLastError() -> GenTLErrorInfo {
        lock.lock()
        defer { lock.unlock() }

        var errorCode: Int32 = GC_ERROR.success.rawValue
        var size = 0
        let queryResult = functions.gcGetLastError(&errorCode, nil, &size)
        guard queryResult == GC_ERROR.success.rawValue, size > 0, size <= 1_048_576 else {
            return GenTLErrorInfo(
                code: GC_ERROR(rawValue: errorCode),
                message: "GenTL Producer returned error information with an invalid text size."
            )
        }

        var text = [CChar](repeating: 0, count: size)
        let readResult = text.withUnsafeMutableBufferPointer { buffer in
            functions.gcGetLastError(&errorCode, buffer.baseAddress, &size)
        }
        guard readResult == GC_ERROR.success.rawValue else {
            return GenTLErrorInfo(
                code: GC_ERROR(rawValue: errorCode),
                message: "GenTL Producer could not return its last-error text (status \(readResult))."
            )
        }

        return GenTLErrorInfo(
            code: GC_ERROR(rawValue: errorCode),
            message: String(cString: text)
        )
    }

    public func TLOpen() throws -> TL_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        var rawHandle: UnsafeMutableRawPointer?
        try check(functions.tlOpen(&rawHandle))
        guard let rawHandle else { throw GC_ERROR.invalidHandle }
        return TL_HANDLE(rawValue: UInt(bitPattern: rawHandle))
    }

    public func TLClose(_ hTL: TL_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        try check(functions.tlClose(try pointer(hTL)))
    }

    public func TLGetNumInterfaces(_ hTL: TL_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        var count: UInt32 = 0
        try check(functions.tlGetNumInterfaces(try pointer(hTL), &count))
        return count
    }

    public func TLGetInterfaceID(_ hTL: TL_HANDLE, index: UInt32) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        let handle = try pointer(hTL)
        var size = 0
        let query = functions.tlGetInterfaceID(handle, index, nil, &size)
        try checkStringQuery(query, size: size)

        var bytes = [CChar](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBufferPointer {
            functions.tlGetInterfaceID(handle, index, $0.baseAddress, &size)
        }
        try check(result)
        return String(cString: bytes)
    }

    public func TLUpdateInterfaceList(_ hTL: TL_HANDLE, timeout: UInt64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        var changed: UInt8 = 0
        try check(functions.tlUpdateInterfaceList(try pointer(hTL), &changed, timeout))
        return changed != 0
    }

    public func TLOpenInterface(_ hTL: TL_HANDLE, interfaceID: String) throws -> IF_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        var rawHandle: UnsafeMutableRawPointer?
        let result = interfaceID.withCString {
            functions.tlOpenInterface(try! pointer(hTL), $0, &rawHandle)
        }
        try check(result)
        guard let rawHandle else { throw GC_ERROR.invalidHandle }
        return IF_HANDLE(rawValue: UInt(bitPattern: rawHandle))
    }

    public func IFClose(_ hIF: IF_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        try check(functions.ifClose(try pointer(hIF)))
    }

    public func IFUpdateDeviceList(_ hIF: IF_HANDLE, timeout: UInt64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        var changed: UInt8 = 0
        try check(functions.ifUpdateDeviceList(try pointer(hIF), &changed, timeout))
        return changed != 0
    }

    public func IFGetNumDevices(_ hIF: IF_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        var count: UInt32 = 0
        try check(functions.ifGetNumDevices(try pointer(hIF), &count))
        return count
    }

    public func IFGetDeviceID(_ hIF: IF_HANDLE, index: UInt32) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        let handle = try pointer(hIF)
        var size = 0
        let query = functions.ifGetDeviceID(handle, index, nil, &size)
        try checkStringQuery(query, size: size)

        var bytes = [CChar](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBufferPointer {
            functions.ifGetDeviceID(handle, index, $0.baseAddress, &size)
        }
        try check(result)
        return String(cString: bytes)
    }

    public func IFOpenDevice(
        _ hIF: IF_HANDLE,
        deviceID: String,
        accessFlags: UInt32
    ) throws -> DEV_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()

        var rawHandle: UnsafeMutableRawPointer?
        let result = deviceID.withCString {
            functions.ifOpenDevice(try! pointer(hIF), $0, accessFlags, &rawHandle)
        }
        try check(result)
        guard let rawHandle else { throw GC_ERROR.invalidHandle }
        return DEV_HANDLE(rawValue: UInt(bitPattern: rawHandle))
    }

    public func DevClose(_ hDevice: DEV_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        try check(functions.devClose(try pointer(hDevice)))
    }

    private func requireInitialized() throws {
        guard initialized else { throw GC_ERROR.notInitialized }
    }

    private func check(_ result: Int32) throws {
        guard result == GC_ERROR.success.rawValue else {
            throw GC_ERROR(rawValue: result)
        }
    }

    private func checkStringQuery(_ result: Int32, size: Int) throws {
        guard size > 0, size <= 1_048_576 else { throw GC_ERROR.invalidValue }
        if result == GC_ERROR.success.rawValue || result == GC_ERROR.bufferTooSmall.rawValue {
            return
        }
        throw GC_ERROR(rawValue: result)
    }

    private func pointer<Tag: Hashable & Sendable>(
        _ handle: GenTLHandle<Tag>
    ) throws -> UnsafeMutableRawPointer {
        guard handle.isValid,
              let pointer = UnsafeMutableRawPointer(bitPattern: handle.rawValue) else {
            throw GC_ERROR.invalidHandle
        }
        return pointer
    }
}
