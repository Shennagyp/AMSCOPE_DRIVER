import Foundation
import GenTLAPI
import GenTLNative
import AmcamGenTL

public enum GenTLRouterError: Error, LocalizedError, Sendable {
    case emptyBackendID
    case duplicateBackendID(String)
    case unknownBackendID(String)
    case interfaceHandleUnavailable(String)
    case providerContextUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyBackendID:
            return "A GenTL backend registration requires a non-empty identifier."
        case .duplicateBackendID(let id):
            return "GenTL backend '\(id)' is already registered."
        case .unknownBackendID(let id):
            return "No GenTL backend is registered with identifier '\(id)'."
        case .interfaceHandleUnavailable(let id):
            return "The discovered GenTL interface handle for '\(id)' is no longer available."
        case .providerContextUnavailable(let id):
            return "The GenTL provider context for backend '\(id)' is no longer available."
        }
    }
}

public struct GenTLProviderFailure: Equatable, Sendable, Identifiable {
    public let backendID: String
    public let message: String

    public var id: String { backendID }

    public init(backendID: String, message: String) {
        self.backendID = backendID
        self.message = message
    }
}

public struct GenTLDiscoveryReport: Sendable {
    public let devices: [GenTLDeviceCandidate]
    public let failures: [GenTLProviderFailure]

    public init(devices: [GenTLDeviceCandidate], failures: [GenTLProviderFailure]) {
        self.devices = devices
        self.failures = failures
    }

    public var isComplete: Bool { failures.isEmpty }
}

/// Result of scanning standard/explicit GenTL paths and registering producers.
public struct GenTLProducerRegistrationReport: Sendable {
    public let searchResult: GenTLProducerSearchResult
    public let registeredBackendIDs: [String]
    public let alreadyRegisteredBackendIDs: [String]
    public let failures: [GenTLProviderFailure]

    public init(
        searchResult: GenTLProducerSearchResult,
        registeredBackendIDs: [String],
        alreadyRegisteredBackendIDs: [String],
        failures: [GenTLProviderFailure]
    ) {
        self.searchResult = searchResult
        self.registeredBackendIDs = registeredBackendIDs
        self.alreadyRegisteredBackendIDs = alreadyRegisteredBackendIDs
        self.failures = failures
    }
}

/// A discovered device remains bound to the exact GenTLAPI implementation
/// and interface handle that discovered it. The app still uses GenTL function
/// calls; backend selection is not repeated at individual call sites.
public struct GenTLDeviceCandidate: Sendable, Identifiable {
    public let backendID: String
    public let interfaceID: String
    public let deviceID: String
    public let api: any GenTLAPI
    public let systemHandle: TL_HANDLE
    public let interfaceHandle: IF_HANDLE

    private let context: GenTLProviderContext

    public var id: String {
        "\(backendID)|\(interfaceID)|\(deviceID)"
    }

    fileprivate init(
        backendID: String,
        interfaceID: String,
        deviceID: String,
        context: GenTLProviderContext
    ) throws {
        guard let interfaceHandle = context.interfaceHandle(for: interfaceID) else {
            throw GenTLRouterError.interfaceHandleUnavailable(interfaceID)
        }
        self.backendID = backendID
        self.interfaceID = interfaceID
        self.deviceID = deviceID
        self.api = context.api
        self.systemHandle = context.systemHandle
        self.interfaceHandle = interfaceHandle
        self.context = context
    }

    public func open(accessFlags: Int32) throws -> GenTLDeviceSession {
        let handle = try context.openDevice(
            interfaceHandle,
            deviceID: deviceID,
            accessFlags: accessFlags
        )
        return GenTLDeviceSession(context: context, api: api, deviceHandle: handle)
    }
}

/// Prevents a native Producer from being unloaded after cleanup failed with live
/// module handles. Retention is process-lifetime by design: leaking a loaded CTI
/// is safer than invalidating handles still owned by its Producer.
private final class GenTLProviderRetainer: @unchecked Sendable {
    static let shared = GenTLProviderRetainer()

    private let lock = NSLock()
    private var retainedAPIs: [any GenTLAPI] = []

    func retain(_ api: any GenTLAPI) {
        lock.lock()
        defer { lock.unlock() }
        retainedAPIs.append(api)
    }
}

/// Owns the GenTL Library/System/Interface lifetime for one backend instance.
/// It remains alive while any discovered candidate or opened device session uses it.
private final class GenTLProviderContext: @unchecked Sendable {
    let backendID: String
    let api: any GenTLAPI
    let systemHandle: TL_HANDLE

    private let lock = NSRecursiveLock()
    private var interfaceHandles: [IF_HANDLE] = []
    private var closed = false

    private var interfaceHandlesByID: [String: IF_HANDLE] = [:]

    init(backendID: String, api: any GenTLAPI, systemHandle: TL_HANDLE) {
        self.backendID = backendID
        self.api = api
        self.systemHandle = systemHandle
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func interfaceHandle(for id: String) -> IF_HANDLE? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return nil }
        return interfaceHandlesByID[id]
    }

    func openDevice(
        _ interfaceHandle: IF_HANDLE,
        deviceID: String,
        accessFlags: Int32
    ) throws -> DEV_HANDLE {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else {
            throw GenTLRouterError.providerContextUnavailable(backendID)
        }
        let deviceHandle = try api.IFOpenDevice(
            interfaceHandle,
            deviceID: deviceID,
            accessFlags: accessFlags
        )
        guard deviceHandle.isValid else { throw GC_ERROR.invalidHandle }
        return deviceHandle
    }

    func closeDevice(_ deviceHandle: DEV_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        try api.DevClose(deviceHandle)
    }

    /// Refreshes discovery while reusing this backend's already-open System
    /// and Interface modules. Existing candidate handles remain valid across scans.
    func discoverDevices(timeout: UInt64) throws -> [GenTLDeviceCandidate] {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else {
            throw GenTLRouterError.providerContextUnavailable(backendID)
        }

        try api.TLUpdateInterfaceList(systemHandle, timeout: timeout)
        let interfaceCount = try api.TLGetNumInterfaces(systemHandle)
        var candidates: [GenTLDeviceCandidate] = []

        for interfaceIndex in 0..<interfaceCount {
            let interfaceID = try api.TLGetInterfaceID(systemHandle, index: interfaceIndex)
            let interfaceHandle: IF_HANDLE

            if let existingHandle = interfaceHandlesByID[interfaceID] {
                interfaceHandle = existingHandle
            } else {
                let openedHandle = try api.TLOpenInterface(systemHandle, interfaceID: interfaceID)
                guard openedHandle.isValid else { throw GC_ERROR.invalidHandle }
                interfaceHandlesByID[interfaceID] = openedHandle
                interfaceHandles.append(openedHandle)
                interfaceHandle = openedHandle
            }

            try api.IFUpdateDeviceList(interfaceHandle, timeout: timeout)
            let deviceCount = try api.IFGetNumDevices(interfaceHandle)

            for deviceIndex in 0..<deviceCount {
                let deviceID = try api.IFGetDeviceID(interfaceHandle, index: deviceIndex)
                candidates.append(try GenTLDeviceCandidate(
                    backendID: backendID,
                    interfaceID: interfaceID,
                    deviceID: deviceID,
                    context: self
                ))
            }
        }

        return candidates
    }

    /// Abandons teardown without unloading a Producer that may still own live
    /// device/stream handles. Used only after a child handle could not be closed.
    func abandon() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        GenTLProviderRetainer.shared.retain(api)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }

        for handle in interfaceHandles.reversed() {
            do {
                try api.IFClose(handle)
            } catch {
                closed = true
                GenTLProviderRetainer.shared.retain(api)
                return
            }
        }
        interfaceHandles.removeAll()
        interfaceHandlesByID.removeAll()

        do {
            try api.TLClose(systemHandle)
        } catch {
            closed = true
            GenTLProviderRetainer.shared.retain(api)
            return
        }

        do {
            try api.GCCloseLib()
        } catch {
            closed = true
            GenTLProviderRetainer.shared.retain(api)
            return
        }

        closed = true
    }

    deinit {
        close()
    }
}

/// Open device ownership. Close the device before releasing its GenTL route.
public final class GenTLDeviceSession: @unchecked Sendable {
    public let api: any GenTLAPI
    public let deviceHandle: DEV_HANDLE

    private let context: GenTLProviderContext
    private let lock = NSLock()
    private var isClosed = false

    fileprivate init(
        context: GenTLProviderContext,
        api: any GenTLAPI,
        deviceHandle: DEV_HANDLE
    ) {
        self.context = context
        self.api = api
        self.deviceHandle = deviceHandle
    }

    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        try context.closeDevice(deviceHandle)
        isClosed = true
    }

    deinit {
        do {
            try close()
        } catch {
            // A device can still own data streams or callbacks. Do not allow
            // the context to dlclose its Producer while those handles remain.
            context.abandon()
        }
    }
}

private struct BackendRegistration: Sendable {
    let identifier: String
    let makeAPI: @Sendable () throws -> any GenTLAPI
}

/// Registers and routes to GenTLAPI implementations.
///
/// A native registration is one CTI Producer. An Amcam registration is the
/// Amcam SDK-backed implementation of the same GenTL-shaped Swift API.
public final class GenTLRouter: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var registrations: [String: BackendRegistration] = [:]
    private var providerContexts: [String: GenTLProviderContext] = [:]

    public init() {}

    public var backendIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.keys.sorted()
    }

    public func register(
        backendID: String,
        makeAPI: @escaping @Sendable () throws -> any GenTLAPI
    ) throws {
        let normalized = backendID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized == backendID else {
            throw GenTLRouterError.emptyBackendID
        }

        lock.lock()
        defer { lock.unlock() }
        guard registrations[backendID] == nil else {
            throw GenTLRouterError.duplicateBackendID(backendID)
        }
        registrations[backendID] = BackendRegistration(
            identifier: backendID,
            makeAPI: makeAPI
        )
    }

    public func registerNativeProducer(backendID: String, ctiURL: URL) throws {
        try register(backendID: backendID) {
            try GenTLNativeImplementation(ctiURL: ctiURL)
        }
    }

    public func registerAmcam(backendID: String, sdkLibraryURL: URL) throws {
        try register(backendID: backendID) {
            AmcamGenTLImplementation(sdkLibraryURL: sdkLibraryURL)
        }
    }

    /// Discovers .cti files using GENICAM_GENTL64_PATH plus explicit paths,
    /// then registers each producer under its normalized absolute file path.
    /// Calling this repeatedly is safe: previously registered paths are skipped.
    public func registerDiscoveredNativeProducers(
        searchPaths: [URL] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GenTLProducerRegistrationReport {
        let searchResult = GenTLProducerCatalog.discover(
            searchPaths: searchPaths,
            environment: environment
        )

        var existing = Set(backendIDs)
        var registered: [String] = []
        var alreadyRegistered: [String] = []
        var failures = searchResult.issues.map {
            GenTLProviderFailure(backendID: $0.path, message: $0.message)
        }

        for producerURL in searchResult.producers {
            let backendID = producerURL.standardizedFileURL.path
            guard existing.insert(backendID).inserted else {
                alreadyRegistered.append(backendID)
                continue
            }

            do {
                try registerNativeProducer(backendID: backendID, ctiURL: producerURL)
                registered.append(backendID)
            } catch GenTLRouterError.duplicateBackendID(_) {
                // Another concurrent discovery call registered this producer
                // after the initial backendIDs snapshot.
                alreadyRegistered.append(backendID)
            } catch {
                existing.remove(backendID)
                failures.append(
                    GenTLProviderFailure(
                        backendID: backendID,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return GenTLProducerRegistrationReport(
            searchResult: searchResult,
            registeredBackendIDs: registered,
            alreadyRegisteredBackendIDs: alreadyRegistered,
            failures: failures
        )
    }

    private func providerContext(
        for registration: BackendRegistration
    ) throws -> GenTLProviderContext {
        lock.lock()
        defer { lock.unlock() }

        if let existing = providerContexts[registration.identifier],
           !existing.isClosed {
            return existing
        }

        let api = try registration.makeAPI()
        try api.GCInitLib()

        do {
            let systemHandle = try api.TLOpen()
            guard systemHandle.isValid else { throw GC_ERROR.invalidHandle }

            let context = GenTLProviderContext(
                backendID: registration.identifier,
                api: api,
                systemHandle: systemHandle
            )
            providerContexts[registration.identifier] = context
            return context
        } catch {
            do {
                try api.GCCloseLib()
            } catch {
                GenTLProviderRetainer.shared.retain(api)
            }
            throw error
        }
    }

    public func discover(timeout: UInt64 = 2_000) -> GenTLDiscoveryReport {
        lock.lock()
        let current = registrations.values.sorted { $0.identifier < $1.identifier }
        lock.unlock()

        var devices: [GenTLDeviceCandidate] = []
        var failures: [GenTLProviderFailure] = []

        for registration in current {
            do {
                let context = try providerContext(for: registration)
                let discovered = try context.discoverDevices(timeout: timeout)
                devices.append(contentsOf: discovered)
            } catch {
                failures.append(
                    GenTLProviderFailure(
                        backendID: registration.identifier,
                        message: error.localizedDescription
                    )
                )
            }
        }

        devices.sort {
            if $0.backendID != $1.backendID { return $0.backendID < $1.backendID }
            if $0.interfaceID != $1.interfaceID { return $0.interfaceID < $1.interfaceID }
            return $0.deviceID < $1.deviceID
        }

        return GenTLDiscoveryReport(devices: devices, failures: failures)
    }
}
