import Foundation
import GenTLABI
import GenTLAPI
@_spi(BackendFactory) import GenTLNative
@_spi(BackendFactory) import AmcamGenTL

public enum GenTLRouterError: Error, LocalizedError, Sendable {
    case emptyBackendID
    case duplicateBackendID(String)
    case duplicateBackendResource(String)
    case unknownBackendID(String)
    case interfaceHandleUnavailable(String)
    case providerContextUnavailable(String)
    case genTLCallFailed(Int32)
    case featureAccessUnavailable(String)
    case deviceSessionClosed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyBackendID:
            return "A GenTL backend registration requires a non-empty identifier."
        case .duplicateBackendID(let id):
            return "GenTL backend '\(id)' is already registered."
        case .duplicateBackendResource(let id):
            return "The same GenTL backend library is already registered as '\(id)'."
        case .unknownBackendID(let id):
            return "No GenTL backend is registered with identifier '\(id)'."
        case .interfaceHandleUnavailable(let id):
            return "The discovered GenTL interface handle for '\(id)' is no longer available."
        case .providerContextUnavailable(let id):
            return "The GenTL provider context for backend '\(id)' is no longer available."
        case .genTLCallFailed(let code):
            return "A GenTL API call failed with GC_ERROR \(code)."
        case .featureAccessUnavailable(let id):
            return "Backend '\(id)' does not expose typed feature access."
        case .deviceSessionClosed(let id):
            return "The device session for backend '\(id)' is closed."
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

/// A discovered device remains bound to the exact GenTL implementation and
/// interface handle that discovered it. The opaque C handles are immutable;
/// their lifetime is retained by the provider context, and provider lifecycle
/// transitions are serialized by that context. The API contract is Sendable.
/// This audited boundary is therefore explicitly unchecked rather than
/// pretending UnsafeMutableRawPointer itself is Sendable.

/// Public GenTL device access modes for routed device opening.
public enum GenTLDeviceAccessMode: Int32, Sendable {
    case readOnly = 2
    case control = 3
    case exclusive = 4
}

public struct GenTLDeviceCandidate: @unchecked Sendable, Identifiable {
    public let backendID: String
    public let interfaceID: String
    public let deviceID: String
    public let api: any GenTLAPI
    public let systemHandle: GenTLABI.TL_HANDLE
    public let interfaceHandle: GenTLABI.IF_HANDLE

    private let context: GenTLProviderContext

    public var id: String {
        [backendID, interfaceID, deviceID]
            .map { "\($0.utf8.count):\($0)" }
            .joined()
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

    public func open(access: GenTLDeviceAccessMode) throws -> GenTLDeviceSession {
        try open(accessFlags: GenTLABI.DEVICE_ACCESS_FLAGS(access.rawValue))
    }

    public func open(accessFlags: GenTLABI.DEVICE_ACCESS_FLAGS) throws -> GenTLDeviceSession {
        let handle = try context.openDevice(
            interfaceHandle,
            deviceID: deviceID,
            accessFlags: accessFlags
        )
        return GenTLDeviceSession(context: context, api: api, deviceHandle: handle)
    }
}

/// Keeps a Producer loaded for process lifetime when teardown fails. Unloading
/// a CTI while it may still own handles or callbacks is less safe than retaining it.
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

private func checkGenTLStatus(_ status: GenTLABI.GC_ERROR) throws {
    guard status == GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) else {
        throw GenTLRouterError.genTLCallFailed(Int32(status))
    }
}

private func readGenTLString(
    _ operation: (
        UnsafeMutablePointer<CChar>?,
        UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR
) throws -> String {
    var requiredSize = 0
    let queryStatus = operation(nil, &requiredSize)
    if queryStatus != GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) &&
       queryStatus != GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_BUFFER_TOO_SMALL) {
        try checkGenTLStatus(queryStatus)
    }
    guard requiredSize > 0, requiredSize <= 1_048_576 else {
        throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_VALUE))
    }

    var bytes = [CChar](repeating: 0, count: requiredSize)
    var capacity = requiredSize
    let status = bytes.withUnsafeMutableBufferPointer { buffer in
        operation(buffer.baseAddress, &capacity)
    }
    try checkGenTLStatus(status)
    guard capacity > 0, capacity <= bytes.count else {
        throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_VALUE))
    }
    bytes[bytes.count - 1] = 0
    guard let terminator = bytes.firstIndex(of: 0) else {
        throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_VALUE))
    }
    return String(decoding: bytes[..<terminator].map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// Owns Library/System/Interface lifetime for one backend instance. All
/// lifecycle operations use the public raw GenTLAPI contract directly.
private final class GenTLProviderContext: @unchecked Sendable {
    let backendID: String
    let api: any GenTLAPI
    let systemHandle: GenTLABI.TL_HANDLE

    private let lock = NSRecursiveLock()
    private var interfaceHandles: [UnsafeMutableRawPointer] = []
    private var interfaceHandlesByID: [String: UnsafeMutableRawPointer] = [:]
    private var closed = false

    init(
        backendID: String,
        api: any GenTLAPI,
        systemHandle: UnsafeMutableRawPointer
    ) {
        self.backendID = backendID
        self.api = api
        self.systemHandle = systemHandle
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func interfaceHandle(for id: String) -> GenTLABI.IF_HANDLE? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return nil }
        return interfaceHandlesByID[id]
    }

    func openDevice(
        _ interfaceHandle: GenTLABI.IF_HANDLE,
        deviceID: String,
        accessFlags: GenTLABI.DEVICE_ACCESS_FLAGS
    ) throws -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else {
            throw GenTLRouterError.providerContextUnavailable(backendID)
        }
        var device: GenTLABI.DEV_HANDLE? = nil
        let status = deviceID.withCString {
            api.IFOpenDevice(interfaceHandle, $0, accessFlags, &device)
        }
        try checkGenTLStatus(status)
        guard let device else {
            throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE))
        }
        return device
    }

    func closeDevice(_ deviceHandle: GenTLABI.DEV_HANDLE) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else {
            throw GenTLRouterError.providerContextUnavailable(backendID)
        }
        try checkGenTLStatus(api.DevClose(deviceHandle))
    }

    /// Refreshes discovery while reusing this backend's System and Interface
    /// handles. Existing candidate handles remain bound to the same context.
    func discoverDevices(timeout: UInt64) throws -> [GenTLDeviceCandidate] {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else {
            throw GenTLRouterError.providerContextUnavailable(backendID)
        }

        var changed: GenTLABI.bool8_t = 0
        try checkGenTLStatus(api.TLUpdateInterfaceList(systemHandle, &changed, timeout))

        var interfaceCount: UInt32 = 0
        try checkGenTLStatus(api.TLGetNumInterfaces(systemHandle, &interfaceCount))
        guard interfaceCount <= 4_096 else {
            throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_RESOURCE_EXHAUSTED))
        }

        var candidates: [GenTLDeviceCandidate] = []
        var seenInterfaceIDs = Set<String>()

        for interfaceIndex in 0..<interfaceCount {
            let interfaceID = try readGenTLString { buffer, size in
                api.TLGetInterfaceID(systemHandle, interfaceIndex, buffer, size)
            }
            guard !interfaceID.isEmpty, seenInterfaceIDs.insert(interfaceID).inserted else {
                throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_ID))
            }

            let interfaceHandle: UnsafeMutableRawPointer
            if let existingHandle = interfaceHandlesByID[interfaceID] {
                interfaceHandle = existingHandle
            } else {
                var openedHandle: GenTLABI.IF_HANDLE? = nil
                let status = interfaceID.withCString {
                    api.TLOpenInterface(systemHandle, $0, &openedHandle)
                }
                try checkGenTLStatus(status)
                guard let openedHandle else {
                    throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE))
                }
                guard !interfaceHandles.contains(openedHandle) else {
                    throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_RESOURCE_IN_USE))
                }
                interfaceHandlesByID[interfaceID] = openedHandle
                interfaceHandles.append(openedHandle)
                interfaceHandle = openedHandle
            }

            changed = 0
            try checkGenTLStatus(api.IFUpdateDeviceList(interfaceHandle, &changed, timeout))

            var deviceCount: UInt32 = 0
            try checkGenTLStatus(api.IFGetNumDevices(interfaceHandle, &deviceCount))
            guard deviceCount <= 65_536 else {
                throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_RESOURCE_EXHAUSTED))
            }

            var seenDeviceIDs = Set<String>()
            for deviceIndex in 0..<deviceCount {
                let deviceID = try readGenTLString { buffer, size in
                    api.IFGetDeviceID(interfaceHandle, deviceIndex, buffer, size)
                }
                guard !deviceID.isEmpty, seenDeviceIDs.insert(deviceID).inserted else {
                    throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_ID))
                }
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
            let status = api.IFClose(handle)
            guard status == GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) else {
                closed = true
                GenTLProviderRetainer.shared.retain(api)
                return
            }
        }
        interfaceHandles.removeAll()
        interfaceHandlesByID.removeAll()

        guard api.TLClose(systemHandle) == GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) else {
            closed = true
            GenTLProviderRetainer.shared.retain(api)
            return
        }

        guard api.GCCloseLib() == GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) else {
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

/// Owns one opened device module and retains the provider context until closed.
public final class GenTLDeviceSession: @unchecked Sendable {
    public let api: any GenTLAPI
    public let deviceHandle: GenTLABI.DEV_HANDLE

    private let context: GenTLProviderContext
    private let featureDeviceHandle: GenTLFeatureDeviceHandle
    private let lock = NSLock()
    private var isClosed = false

    fileprivate init(
        context: GenTLProviderContext,
        api: any GenTLAPI,
        deviceHandle: UnsafeMutableRawPointer
    ) {
        self.context = context
        self.api = api
        self.deviceHandle = deviceHandle
        self.featureDeviceHandle = GenTLFeatureDeviceHandle(rawValue: UInt(bitPattern: deviceHandle))
    }

    /// True when this backend supplies typed feature access alongside GenTLAPI.
    /// Native CTI backends return false until their GenApi adapter is available.
    public var supportsFeatureAccess: Bool {
        api is any GenTLFeatureAccess
    }

    public func featureDescriptors() throws -> [GenTLFeatureDescriptor] {
        try withFeatureAccess { provider in
            try provider.featureDescriptors(for: featureDeviceHandle)
        }
    }

    public func readFeature(_ name: String) throws -> GenTLFeatureValue {
        try withFeatureAccess { provider in
            try provider.readFeature(name, from: featureDeviceHandle)
        }
    }

    public func writeFeature(_ value: GenTLFeatureValue, named name: String) throws {
        try withFeatureAccess { provider in
            try provider.writeFeature(value, named: name, to: featureDeviceHandle)
        }
    }

    private func withFeatureAccess<T>(
        _ operation: (any GenTLFeatureAccess) throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else {
            throw GenTLRouterError.deviceSessionClosed(context.backendID)
        }
        guard let provider = api as? any GenTLFeatureAccess else {
            throw GenTLRouterError.featureAccessUnavailable(context.backendID)
        }
        return try operation(provider)
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
            context.abandon()
        }
    }
}

private struct BackendRegistration: Sendable {
    let identifier: String
    let makeAPI: @Sendable () throws -> any GenTLAPI
}

/// Registers and routes to implementations of the common GenTLAPI contract.
///
/// A native registration is one CTI Producer. An Amcam registration is the
/// Amcam SDK-backed implementation of the same GenTL-shaped Swift API.
public final class GenTLRouter: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var registrations: [String: BackendRegistration] = [:]
    private var providerContexts: [String: GenTLProviderContext] = [:]
    /// A backend whose GCInitLib succeeded but GCCloseLib cleanup failed must
    /// never be initialized again in this process.
    private var unavailableBackendIDs: Set<String> = []
    private var backendResourceOwners: [String: String] = [:]

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

    private func registerUniqueResource(
        backendID: String,
        resourceIdentity: String,
        makeAPI: @escaping @Sendable () throws -> any GenTLAPI & GenTLAPI
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
        if let existingBackendID = backendResourceOwners[resourceIdentity] {
            throw GenTLRouterError.duplicateBackendResource(existingBackendID)
        }

        registrations[backendID] = BackendRegistration(
            identifier: backendID,
            makeAPI: makeAPI
        )
        backendResourceOwners[resourceIdentity] = backendID
    }

    public func registerNativeProducer(backendID: String, ctiURL: URL) throws {
        let canonicalURL = ctiURL.standardizedFileURL.resolvingSymlinksInPath()
        try registerUniqueResource(
            backendID: backendID,
            resourceIdentity: "cti:\(canonicalURL.path)"
        ) {
            try GenTLNativeImplementation(ctiURL: canonicalURL)
        }
    }

    /// Registers the bundled AmScope SDK. Vendor path resolution belongs to the
    /// backend package; callers do not select native libraries from the UI.
    public func registerAmcam(backendID: String) throws {
        try registerAmcam(
            backendID: backendID,
            sdkLibraryURL: AmcamSDKLibraryLocator.locate()
        )
    }

    public func registerAmcam(backendID: String, sdkLibraryURL: URL) throws {
        let canonicalURL = sdkLibraryURL.standardizedFileURL.resolvingSymlinksInPath()
        try registerUniqueResource(
            backendID: backendID,
            resourceIdentity: "amcam-sdk:\(canonicalURL.path)"
        ) {
            AmcamGenTLImplementation(sdkLibraryURL: canonicalURL)
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
            } catch GenTLRouterError.duplicateBackendResource(_) {
                // The same CTI was registered manually under a different ID.
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

        guard !unavailableBackendIDs.contains(registration.identifier) else {
            throw GenTLRouterError.providerContextUnavailable(registration.identifier)
        }

        if let existing = providerContexts[registration.identifier] {
            guard !existing.isClosed else {
                // An abandoned Producer may still own live native handles.
                // Do not initialize a second instance of the same backend.
                throw GenTLRouterError.providerContextUnavailable(registration.identifier)
            }
            return existing
        }

        let api = try registration.makeAPI()
        try checkGenTLStatus(api.GCInitLib())

        do {
            var systemHandle: GenTLABI.TL_HANDLE? = nil
            try checkGenTLStatus(api.TLOpen(&systemHandle))
            guard let systemHandle else {
                throw GenTLRouterError.genTLCallFailed(GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE))
            }

            let context = GenTLProviderContext(
                backendID: registration.identifier,
                api: api,
                systemHandle: systemHandle
            )
            providerContexts[registration.identifier] = context
            return context
        } catch {
            if api.GCCloseLib() != GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) {
                unavailableBackendIDs.insert(registration.identifier)
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
