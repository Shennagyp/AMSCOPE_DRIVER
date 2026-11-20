import Foundation
import XCTest
import GenTLABI
import GenTLAPI
@testable import GenTLRouter

private struct CallCounts {
    var gcInit = 0
    var gcClose = 0
    var tlOpen = 0
    var tlClose = 0
    var tlUpdateInterfaces = 0
    var interfaceOpen = 0
    var interfaceClose = 0
    var interfaceUpdateDevices = 0
    var deviceClose = 0
}

private final class RecordingGenTLAPI: GenTLAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = CallCounts()
    private let failSystemOpen: Bool
    private let failLibraryClose: Bool
    private let failDeviceClose: Bool

    private let systemToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private let interfaceToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    let deviceToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    init(
        failSystemOpen: Bool = false,
        failLibraryClose: Bool = false,
        failDeviceClose: Bool = false
    ) {
        self.failSystemOpen = failSystemOpen
        self.failLibraryClose = failLibraryClose
        self.failDeviceClose = failDeviceClose
    }

    deinit {
        systemToken.deallocate()
        interfaceToken.deallocate()
        deviceToken.deallocate()
    }

    private func record(_ update: (inout CallCounts) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        update(&calls)
    }

    func snapshot() -> CallCounts {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    private func writeCString(
        _ value: String,
        output: UnsafeMutablePointer<CChar>?,
        size: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let size else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        let bytes = value.utf8CString
        let capacity = size.pointee
        size.pointee = bytes.count
        guard let output else { return GenTLABI.GC_ERR_SUCCESS }
        guard capacity >= bytes.count else { return GenTLABI.GC_ERR_BUFFER_TOO_SMALL }
        for (index, byte) in bytes.enumerated() {
            output[index] = byte
        }
        return GenTLABI.GC_ERR_SUCCESS
    }

    func GCInitLib() -> GenTLABI.GC_ERROR {
        record { $0.gcInit += 1 }
        return GenTLABI.GC_ERR_SUCCESS
    }

    func GCCloseLib() -> GenTLABI.GC_ERROR {
        record { $0.gcClose += 1 }
        return failLibraryClose ? GenTLABI.GC_ERR_RESOURCE_IN_USE : GenTLABI.GC_ERR_SUCCESS
    }

    func TLOpen(_ phTL: UnsafeMutablePointer<GenTLABI.TL_HANDLE>?) -> GenTLABI.GC_ERROR {
        record { $0.tlOpen += 1 }
        guard let phTL else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        if failSystemOpen {
            phTL.pointee = nil
            return GenTLABI.GC_ERR_ERROR
        }
        phTL.pointee = systemToken
        return GenTLABI.GC_ERR_SUCCESS
    }

    func TLClose(_ hTL: GenTLABI.TL_HANDLE) -> GenTLABI.GC_ERROR {
        record { $0.tlClose += 1 }
        return hTL == systemToken ? GenTLABI.GC_ERR_SUCCESS : GenTLABI.GC_ERR_INVALID_HANDLE
    }

    func TLUpdateInterfaceList(
        _ hTL: GenTLABI.TL_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        record { $0.tlUpdateInterfaces += 1 }
        guard hTL == systemToken else { return GenTLABI.GC_ERR_INVALID_HANDLE }
        pbChanged?.pointee = 0
        return GenTLABI.GC_ERR_SUCCESS
    }

    func TLGetNumInterfaces(
        _ hTL: GenTLABI.TL_HANDLE,
        _ piNumIfaces: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        guard hTL == systemToken, let piNumIfaces else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        piNumIfaces.pointee = 1
        return GenTLABI.GC_ERR_SUCCESS
    }

    func TLGetInterfaceID(
        _ hTL: GenTLABI.TL_HANDLE,
        _ iIndex: UInt32,
        _ sID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard hTL == systemToken, iIndex == 0 else { return GenTLABI.GC_ERR_INVALID_INDEX }
        return writeCString("interface-0", output: sID, size: piSize)
    }

    func TLOpenInterface(
        _ hTL: GenTLABI.TL_HANDLE,
        _ sIfaceID: UnsafePointer<CChar>?,
        _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard hTL == systemToken, let sIfaceID, let phIface,
              String(cString: sIfaceID) == "interface-0" else {
            return GenTLABI.GC_ERR_INVALID_ID
        }
        record { $0.interfaceOpen += 1 }
        phIface.pointee = interfaceToken
        return GenTLABI.GC_ERR_SUCCESS
    }

    func IFClose(_ hIface: GenTLABI.IF_HANDLE) -> GenTLABI.GC_ERROR {
        record { $0.interfaceClose += 1 }
        return hIface == interfaceToken ? GenTLABI.GC_ERR_SUCCESS : GenTLABI.GC_ERR_INVALID_HANDLE
    }

    func IFUpdateDeviceList(
        _ hIface: GenTLABI.IF_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        record { $0.interfaceUpdateDevices += 1 }
        guard hIface == interfaceToken else { return GenTLABI.GC_ERR_INVALID_HANDLE }
        pbChanged?.pointee = 0
        return GenTLABI.GC_ERR_SUCCESS
    }

    func IFGetNumDevices(
        _ hIface: GenTLABI.IF_HANDLE,
        _ piNumDevices: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        guard hIface == interfaceToken, let piNumDevices else { return GenTLABI.GC_ERR_INVALID_PARAMETER }
        piNumDevices.pointee = 1
        return GenTLABI.GC_ERR_SUCCESS
    }

    func IFGetDeviceID(
        _ hIface: GenTLABI.IF_HANDLE,
        _ iIndex: UInt32,
        _ sDeviceID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard hIface == interfaceToken, iIndex == 0 else { return GenTLABI.GC_ERR_INVALID_INDEX }
        return writeCString("camera-0", output: sDeviceID, size: piSize)
    }

    func IFOpenDevice(
        _ hIface: GenTLABI.IF_HANDLE,
        _ sDeviceID: UnsafePointer<CChar>?,
        _ iOpenFlag: GenTLABI.DEVICE_ACCESS_FLAGS,
        _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE>?
    ) -> GenTLABI.GC_ERROR {
        guard hIface == interfaceToken, let sDeviceID, let phDevice,
              String(cString: sDeviceID) == "camera-0" else {
            return GenTLABI.GC_ERR_INVALID_ID
        }
        guard iOpenFlag == 4 else { return GenTLABI.GC_ERR_ACCESS_DENIED }
        phDevice.pointee = deviceToken
        return GenTLABI.GC_ERR_SUCCESS
    }

    func DevClose(_ hDevice: GenTLABI.DEV_HANDLE) -> GenTLABI.GC_ERROR {
        record { $0.deviceClose += 1 }
        guard hDevice == deviceToken else { return GenTLABI.GC_ERR_INVALID_HANDLE }
        return failDeviceClose ? GenTLABI.GC_ERR_RESOURCE_IN_USE : GenTLABI.GC_ERR_SUCCESS
    }
}

final class GenTLRouterLifecycleTests: XCTestCase {
    func testDeviceSessionForwardsTypedFeatureAccessToItsOwningBackend() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "feature-backend") { api }

        let report = router.discover()
        let candidate = try XCTUnwrap(report.devices.first)
        let session = try candidate.open(accessFlags: GenTLDeviceAccess.exclusive.rawValue)
        defer { try? session.close() }

        XCTAssertTrue(session.supportsFeatureAccess)
        XCTAssertEqual(
            try session.featureDescriptors().map(\\.name),
            ["MockFeature"]
        )
        XCTAssertEqual(try session.readFeature("MockFeature"), .integer(42))
        try session.writeFeature(.integer(84), named: "MockFeature")
    }

    func testSuccessfulInitializationRollbackAllowsRetry() throws {
        let api = RecordingGenTLAPI(failSystemOpen: true)
        let router = GenTLRouter()
        try router.register(backendID: "retry-after-cleanup") { api }

        let first = router.discover()
        XCTAssertEqual(first.failures.count, 1)

        let second = router.discover()
        XCTAssertEqual(second.failures.count, 1)

        let calls = api.snapshot()
        XCTAssertEqual(calls.gcInit, 2)
        XCTAssertEqual(calls.tlOpen, 2)
        XCTAssertEqual(calls.gcClose, 2)
    }

    func testFailedDeviceCloseAbandonsAndQuarantinesProviderContext() throws {
        let api = RecordingGenTLAPI(failDeviceClose: true)
        let router = GenTLRouter()
        try router.register(backendID: "device-close-failure") { api }

        var candidate: GenTLDeviceCandidate?
        do {
            let report = router.discover()
            XCTAssertTrue(report.failures.isEmpty)
            candidate = try XCTUnwrap(report.devices.first)
        }

        var session: GenTLDeviceSession? = try XCTUnwrap(candidate).open(
            accessFlags: GenTLDeviceAccess.exclusive.rawValue
        )
        XCTAssertThrowsError(try XCTUnwrap(session).close())

        // Releasing a session whose native close failed abandons the context.
        session = nil
        candidate = nil

        let subsequent = router.discover()
        XCTAssertEqual(subsequent.devices.count, 0)
        XCTAssertEqual(subsequent.failures.count, 1)

        let calls = api.snapshot()
        XCTAssertEqual(calls.gcInit, 1)
        XCTAssertEqual(calls.tlOpen, 1)
        XCTAssertGreaterThanOrEqual(calls.deviceClose, 2)
    }

    func testFailedInitializationCleanupQuarantinesBackend() throws {
        let api = RecordingGenTLAPI(failSystemOpen: true, failLibraryClose: true)
        let router = GenTLRouter()
        try router.register(backendID: "partial-init") { api }

        let first = router.discover()
        XCTAssertEqual(first.devices.count, 0)
        XCTAssertEqual(first.failures.count, 1)

        let second = router.discover()
        XCTAssertEqual(second.devices.count, 0)
        XCTAssertEqual(second.failures.count, 1)

        // GCInitLib is the observable proof that the API factory was not
        // invoked for a second producer instance.
        let calls = api.snapshot()
        XCTAssertEqual(calls.gcInit, 1)
        XCTAssertEqual(calls.tlOpen, 1)
        XCTAssertEqual(calls.gcClose, 1)
    }

    func testNativeProducerSymlinkAliasesCannotRegisterTwice() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTLRouterProducerIdentity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let producer = root.appendingPathComponent("camera.cti")
        let alias = root.appendingPathComponent("camera-alias.cti")
        XCTAssertTrue(FileManager.default.createFile(atPath: producer.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: producer)

        let router = GenTLRouter()
        try router.registerNativeProducer(backendID: "primary", ctiURL: producer)

        XCTAssertThrowsError(
            try router.registerNativeProducer(backendID: "alias", ctiURL: alias)
        ) { error in
            guard case GenTLRouterError.duplicateBackendResource(let existingID) = error else {
                return XCTFail("Expected duplicate backend resource, received \(error)")
            }
            XCTAssertEqual(existingID, "primary")
        }
    }

    func testRepeatedDiscoveryReusesOneProducerSystemAndInterface() throws {
        let api = RecordingGenTLAPI()

        func discoverTwiceAndOpenDevice() throws {
            let router = GenTLRouter()
            try router.register(backendID: "recording") { api }

            let first = router.discover()
            XCTAssertTrue(first.failures.isEmpty)
            XCTAssertEqual(first.devices.count, 1)

            let second = router.discover()
            XCTAssertTrue(second.failures.isEmpty)
            XCTAssertEqual(second.devices.count, 1)

            let firstCandidate = try XCTUnwrap(first.devices.first)
            let secondCandidate = try XCTUnwrap(second.devices.first)

            XCTAssertEqual(firstCandidate.id, secondCandidate.id)
            XCTAssertEqual(firstCandidate.interfaceHandle, secondCandidate.interfaceHandle)
            XCTAssertTrue(
                (firstCandidate.api as AnyObject) === (secondCandidate.api as AnyObject)
            )

            let session = try firstCandidate.open(
                accessFlags: GenTLDeviceAccess.exclusive.rawValue
            )
            XCTAssertEqual(session.deviceHandle, api.deviceToken)
            try session.close()

            let activeCounts = api.snapshot()
            XCTAssertEqual(activeCounts.gcInit, 1)
            XCTAssertEqual(activeCounts.tlOpen, 1)
            XCTAssertEqual(activeCounts.interfaceOpen, 1)
            XCTAssertEqual(activeCounts.tlUpdateInterfaces, 2)
            XCTAssertEqual(activeCounts.interfaceUpdateDevices, 2)
            XCTAssertEqual(activeCounts.deviceClose, 1)
            XCTAssertEqual(activeCounts.interfaceClose, 0)
            XCTAssertEqual(activeCounts.tlClose, 0)
            XCTAssertEqual(activeCounts.gcClose, 0)
        }

        try discoverTwiceAndOpenDevice()

        // The router, both discovery reports, and the opened session have now
        // released their context. Its module hierarchy must close exactly once.
        let finalCounts = api.snapshot()
        XCTAssertEqual(finalCounts.interfaceClose, 1)
        XCTAssertEqual(finalCounts.tlClose, 1)
        XCTAssertEqual(finalCounts.gcClose, 1)
    }
}


extension RecordingGenTLAPI: GenTLFeatureAccess {
    func featureDescriptors(for device: DEV_HANDLE) throws -> [GenTLFeatureDescriptor] {
        guard device.rawValue == UInt(bitPattern: deviceToken) else {
            throw GenTLFeatureAccessError.featureUnavailable("wrong-device-handle")
        }
        return [
            GenTLFeatureDescriptor(
                name: "MockFeature",
                displayName: "Mock Feature",
                kind: .integer,
                isAvailable: true,
                isReadable: true,
                isWritable: true
            )
        ]
    }

    func readFeature(_ name: String, from device: DEV_HANDLE) throws -> GenTLFeatureValue {
        guard name == "MockFeature", device.rawValue == UInt(bitPattern: deviceToken) else {
            throw GenTLFeatureAccessError.featureNotFound(name)
        }
        return .integer(42)
    }

    func writeFeature(
        _ value: GenTLFeatureValue,
        named name: String,
        to device: DEV_HANDLE
    ) throws {
        guard name == "MockFeature", device.rawValue == UInt(bitPattern: deviceToken),
              value.kind == .integer else {
            throw GenTLFeatureAccessError.invalidValue(name)
        }
    }
}
