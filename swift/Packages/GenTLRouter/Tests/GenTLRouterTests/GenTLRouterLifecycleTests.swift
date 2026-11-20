import Foundation
import XCTest
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

    init(failSystemOpen: Bool = false, failLibraryClose: Bool = false) {
        self.failSystemOpen = failSystemOpen
        self.failLibraryClose = failLibraryClose
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

    func GCInitLib() throws {
        record { $0.gcInit += 1 }
    }

    func GCCloseLib() throws {
        record { $0.gcClose += 1 }
        if failLibraryClose { throw GC_ERROR.resourceInUse }
    }

    func TLOpen() throws -> TL_HANDLE {
        record { $0.tlOpen += 1 }
        if failSystemOpen { throw GC_ERROR.error }
        return TL_HANDLE(rawValue: 1)
    }

    func TLClose(_ hTL: TL_HANDLE) throws {
        record { $0.tlClose += 1 }
    }

    func TLUpdateInterfaceList(_ hTL: TL_HANDLE, timeout: UInt64) throws -> Bool {
        record { $0.tlUpdateInterfaces += 1 }
        return false
    }

    func TLGetNumInterfaces(_ hTL: TL_HANDLE) throws -> UInt32 {
        return 1
    }

    func TLGetInterfaceID(_ hTL: TL_HANDLE, index: UInt32) throws -> String {
        guard index == 0 else { throw GC_ERROR.invalidIndex }
        return "interface-0"
    }

    func TLOpenInterface(_ hTL: TL_HANDLE, interfaceID: String) throws -> IF_HANDLE {
        guard interfaceID == "interface-0" else { throw GC_ERROR.invalidID }
        record { $0.interfaceOpen += 1 }
        return IF_HANDLE(rawValue: 2)
    }

    func IFClose(_ hIF: IF_HANDLE) throws {
        record { $0.interfaceClose += 1 }
    }

    func IFUpdateDeviceList(_ hIF: IF_HANDLE, timeout: UInt64) throws -> Bool {
        record { $0.interfaceUpdateDevices += 1 }
        return false
    }

    func IFGetNumDevices(_ hIF: IF_HANDLE) throws -> UInt32 {
        return 1
    }

    func IFGetDeviceID(_ hIF: IF_HANDLE, index: UInt32) throws -> String {
        guard index == 0 else { throw GC_ERROR.invalidIndex }
        return "camera-0"
    }

    func IFOpenDevice(
        _ hIF: IF_HANDLE,
        deviceID: String,
        accessFlags: Int32
    ) throws -> DEV_HANDLE {
        guard deviceID == "camera-0" else { throw GC_ERROR.invalidID }
        guard accessFlags == GenTLDeviceAccess.exclusive.rawValue else {
            throw GC_ERROR.accessDenied
        }
        return DEV_HANDLE(rawValue: 3)
    }

    func DevClose(_ hDevice: DEV_HANDLE) throws {
        record { $0.deviceClose += 1 }
    }
}

final class GenTLRouterLifecycleTests: XCTestCase {
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
            XCTAssertEqual(session.deviceHandle, DEV_HANDLE(rawValue: 3))
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
