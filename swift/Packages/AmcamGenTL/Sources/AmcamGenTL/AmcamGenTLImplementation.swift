import Foundation
import GenTLAPI

/// Amcam-backed implementation of the Swift GenTLAPI contract.
///
/// This is not a GenTL Producer and does not create a .cti file. It exposes
/// GenTL module operations directly to this application's Swift API and maps
/// operations to the Amcam SDK where the SDK provides equivalent semantics.
public final class AmcamGenTLImplementation: GenTLAPI, @unchecked Sendable {
    private let sdkLibraryURL: URL
    private let lock = NSRecursiveLock()

    private var driver: AmcamCameraDriver?
    private var initialized = false
    private var systemOpen = false
    private var interfaceOpen = false
    private var discoveredDevices: [AmcamDevice] = []
    private var openDevices: [UInt: AmcamCameraSession] = [:]
    private var nextDeviceHandle: UInt = 1
    private var lastError = GenTLErrorInfo(code: .success, message: "No Error")

    private let systemHandle = TL_HANDLE(rawValue: 1)
    private let interfaceHandle = IF_HANDLE(rawValue: 1)

    public init(sdkLibraryURL: URL) {
        self.sdkLibraryURL = sdkLibraryURL.standardizedFileURL
    }

    public var genTLVersion: GenTLVersion { .v1_6 }

    public func GCInitLib() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !initialized else {
            lastError = GenTLErrorInfo(code: .resourceInUse, message: "GCInitLib was already called.")
            throw GC_ERROR.resourceInUse
        }

        do {
            driver = try AmcamCameraDriver(libraryURL: sdkLibraryURL)
            initialized = true
            lastError = GenTLErrorInfo(code: .success, message: "No Error")
        } catch {
            lastError = GenTLErrorInfo(code: .error, message: error.localizedDescription)
            throw GC_ERROR.error
        }
    }

    public func GCCloseLib() throws {
        lock.lock()
        defer { lock.unlock() }

        guard initialized else {
            lastError = GenTLErrorInfo(code: .notInitialized, message: "GCInitLib has not been called.")
            throw GC_ERROR.notInitialized
        }

        closeAllDevices()
        driver = nil
        discoveredDevices.removeAll(keepingCapacity: false)
        interfaceOpen = false
        systemOpen = false
        initialized = false
        lastError = GenTLErrorInfo(code: .success, message: "No Error")
    }

    public func GCGetLastError() -> GenTLErrorInfo {
        lock.lock()
        defer { lock.unlock() }
        return lastError
    }

    public func TLOpen() throws -> TL_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInitialized()
        guard !systemOpen else { throw GC_ERROR.resourceInUse }
        systemOpen = true
        return systemHandle
    }

    public func TLClose(_ hTL: TL_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        closeAllDevices()
        discoveredDevices.removeAll(keepingCapacity: false)
        interfaceOpen = false
        systemOpen = false
    }

    public func TLGetNumInterfaces(_ hTL: TL_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        // The Amcam SDK owns its transport enumeration. This implementation
        // exposes one SDK-managed virtual interface containing its devices.
        return 1
    }

    public func TLGetInterfaceID(_ hTL: TL_HANDLE, index: UInt32) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        guard index == 0 else { throw GC_ERROR.invalidIndex }
        return "amcam-sdk-interface"
    }

    public func TLUpdateInterfaceList(_ hTL: TL_HANDLE, timeout: UInt64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        // Interface topology is owned by the Amcam SDK; camera hot-plug changes
        // are discovered by IFUpdateDeviceList.
        return false
    }

    public func TLOpenInterface(_ hTL: TL_HANDLE, interfaceID: String) throws -> IF_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireSystem(hTL)
        guard interfaceID == "amcam-sdk-interface" else { throw GC_ERROR.invalidID }
        guard !interfaceOpen else { throw GC_ERROR.resourceInUse }
        interfaceOpen = true
        return interfaceHandle
    }

    public func IFClose(_ hIF: IF_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        closeAllDevices()
        discoveredDevices.removeAll(keepingCapacity: false)
        interfaceOpen = false
    }

    public func IFUpdateDeviceList(_ hIF: IF_HANDLE, timeout: UInt64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        guard let driver else { throw GC_ERROR.notInitialized }

        let previousIDs = Set(discoveredDevices.map(\.identifier))
        do {
            let updated = try driver.discover()
            let updatedIDs = Set(updated.map(\.identifier))
            discoveredDevices = updated
            return previousIDs != updatedIDs
        } catch {
            lastError = GenTLErrorInfo(code: .error, message: error.localizedDescription)
            throw GC_ERROR.error
        }
    }

    public func IFGetNumDevices(_ hIF: IF_HANDLE) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        guard discoveredDevices.count <= Int(UInt32.max) else { throw GC_ERROR.resourceExhausted }
        return UInt32(discoveredDevices.count)
    }

    public func IFGetDeviceID(_ hIF: IF_HANDLE, index: UInt32) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        guard Int(index) < discoveredDevices.count else { throw GC_ERROR.invalidIndex }
        return discoveredDevices[Int(index)].identifier
    }

    public func IFOpenDevice(
        _ hIF: IF_HANDLE,
        deviceID: String,
        accessFlags: UInt32
    ) throws -> DEV_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)

        guard discoveredDevices.contains(where: { $0.identifier == deviceID }) else {
            throw GC_ERROR.invalidID
        }
        guard let driver else { throw GC_ERROR.notInitialized }

        do {
            let session = try driver.open(deviceIdentifier: deviceID)
            let rawHandle = nextDeviceHandle
            guard rawHandle != GenTLConstants.invalidHandle else { throw GC_ERROR.resourceExhausted }
            nextDeviceHandle &+= 1
            openDevices[rawHandle] = session
            return DEV_HANDLE(rawValue: rawHandle)
        } catch let error as GC_ERROR {
            throw error
        } catch {
            lastError = GenTLErrorInfo(code: .accessDenied, message: error.localizedDescription)
            throw GC_ERROR.accessDenied
        }
    }

    public func IFGetParentTL(_ hIF: IF_HANDLE) throws -> TL_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireInterface(hIF)
        return systemHandle
    }

    public func DevClose(_ hDevice: DEV_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let session = openDevices.removeValue(forKey: hDevice.rawValue) else {
            throw GC_ERROR.invalidHandle
        }
        do {
            try session.close()
        } catch {
            lastError = GenTLErrorInfo(code: .error, message: error.localizedDescription)
            throw GC_ERROR.error
        }
    }

    public func DevGetParentIF(_ hDevice: DEV_HANDLE) throws -> IF_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        try requireDevice(hDevice)
        return interfaceHandle
    }

    // The remaining GenTL operations use the GenTLAPI default implementation
    // until their Amcam mapping is implemented. In particular, register-port
    // access requires a synthetic GenApi XML/register map, and streaming requires
    // correct GenTL buffer/event semantics over the Amcam callback/pull model.

    private func requireInitialized() throws {
        guard initialized, driver != nil else { throw GC_ERROR.notInitialized }
    }

    private func requireSystem(_ handle: TL_HANDLE) throws {
        try requireInitialized()
        guard systemOpen, handle == systemHandle else { throw GC_ERROR.invalidHandle }
    }

    private func requireInterface(_ handle: IF_HANDLE) throws {
        try requireSystem(systemHandle)
        guard interfaceOpen, handle == interfaceHandle else { throw GC_ERROR.invalidHandle }
    }

    private func requireDevice(_ handle: DEV_HANDLE) throws {
        try requireInterface(interfaceHandle)
        guard openDevices[handle.rawValue] != nil else { throw GC_ERROR.invalidHandle }
    }

    private func closeAllDevices() {
        for (_, session) in openDevices {
            try? session.close()
        }
        openDevices.removeAll(keepingCapacity: false)
    }
}
