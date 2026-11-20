import Darwin
import Foundation
import XCTest
import GenTLABI
import GenTLAPI
@_spi(BackendFactory) @testable import GenTLNative

final class GenTLNativeIntegrationTests: XCTestCase {
    private func buildMockProducer(omittingGetInfo: Bool = false, omittingOptionalExports: Bool = false) throws -> URL {
        let testDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let source = testDirectory
            .appendingPathComponent("../MockGenTLProducer/MockGenTLProducer.c")
            .standardizedFileURL
        let packageDirectory = testDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let headerDirectory = packageDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("GenTLABI/Sources/GenTLABI/include", isDirectory: true)

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTLNativeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let output = outputDirectory.appendingPathComponent("MockProducer.cti")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        var arguments = [
            "--sdk", "macosx", "clang",
            "-dynamiclib",
            "-fPIC",
            "-w",
            "-I", headerDirectory.path
        ]
        if omittingGetInfo {
            arguments.append("-DMOCK_OMIT_GCGETINFO")
        }
        if omittingOptionalExports {
            arguments.append("-DMOCK_OMIT_OPTIONAL_EXPORTS")
        }
        arguments += [source.path, "-o", output.path]
        process.arguments = arguments

        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
            throw NSError(
                domain: "GenTLNativeIntegrationTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey:
                    String(decoding: diagnostic, as: UTF8.self)]
            )
        }
        return output
    }

    func testNativeImplementationLoadsCTIAndForwardsCFunctionOutputs() throws {
        let producerURL = try buildMockProducer()
        let implementation = try GenTLNativeImplementation(ctiURL: producerURL)
        let api: any GenTLAPI = implementation

        var infoType: INFO_DATATYPE = INFO_DATATYPE_UNKNOWN
        var payload: UInt32 = 0
        var payloadSize = MemoryLayout<UInt32>.size

        let result = withUnsafeMutablePointer(to: &infoType) { typePointer in
            withUnsafeMutablePointer(to: &payload) { payloadPointer in
                withUnsafeMutablePointer(to: &payloadSize) { sizePointer in
                    api.GCGetInfo(
                        0x1234,
                        typePointer,
                        UnsafeMutableRawPointer(payloadPointer),
                        sizePointer
                    )
                }
            }
        }

        XCTAssertEqual(result, -11000)
        XCTAssertEqual(infoType, INFO_DATATYPE_UINT32)
        XCTAssertEqual(payload, 0xC0FFEE01)
        XCTAssertEqual(payloadSize, MemoryLayout<UInt32>.size)
    }


    func testEveryProtocolOperationDispatchesToItsMatchingNativeExport() throws {
        let producerURL = try buildMockProducer()
        let implementation = try GenTLNativeImplementation(ctiURL: producerURL)
        let api: any GenTLAPI = implementation

        XCTAssertEqual(api.GCInitLib(), GC_ERR_SUCCESS)

        var eventStorage: EVENT_HANDLE = nil
        let registerResult = withUnsafeMutablePointer(to: &eventStorage) {
            api.GCRegisterEvent(nil, 0, $0)
        }
        XCTAssertEqual(registerResult, GC_ERR_SUCCESS)
        let eventHandle = try XCTUnwrap(eventStorage)
        XCTAssertEqual(UInt(bitPattern: eventHandle), 0x1234)

        let portHandle = UnsafeMutableRawPointer(bitPattern: 0x1111)!
        var readPayload: UInt32 = 0
        var readSize = MemoryLayout<UInt32>.size
        let readResult = withUnsafeMutablePointer(to: &readPayload) { payloadPointer in
            withUnsafeMutablePointer(to: &readSize) { sizePointer in
                api.GCReadPort(
                    portHandle,
                    0x1020304050607080,
                    UnsafeMutableRawPointer(payloadPointer),
                    sizePointer
                )
            }
        }
        XCTAssertEqual(readResult, -11004)
        XCTAssertEqual(readPayload, 0xA1B2C3D4)
        XCTAssertEqual(readSize, MemoryLayout<UInt32>.size)

        let writePayload: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        var writeSize = writePayload.count
        let writeResult = writePayload.withUnsafeBufferPointer { buffer in
            api.GCWritePort(
                portHandle,
                0x1020304050607080,
                UnsafeRawPointer(buffer.baseAddress!),
                &writeSize
            )
        }
        XCTAssertEqual(writeResult, -11005)
        XCTAssertEqual(writeSize, writePayload.count)

        let operations: [(name: String, index: UInt32, expected: GC_ERROR, invoke: () -> GC_ERROR)] = [
            ("GCGetInfo", 0, -11000, { api.GCGetInfo(0x1234, nil, nil, nil) }),
            ("GCGetLastError", 1, -12001, { api.GCGetLastError(nil, nil, nil) }),
            ("GCGetPortURL", 6, -12006, { api.GCGetPortURL(nil, nil, nil) }),
            ("GCGetPortInfo", 7, -12007, { api.GCGetPortInfo(nil, 0, nil, nil, nil) }),
            ("EventGetData", 10, -12010, { api.EventGetData(eventHandle, nil, nil, 0) }),
            ("EventGetDataInfo", 11, -12011, { api.EventGetDataInfo(eventHandle, nil, 0, 0, nil, nil, nil) }),
            ("EventGetInfo", 12, -12012, { api.EventGetInfo(eventHandle, 0, nil, nil, nil) }),
            ("EventFlush", 13, -12013, { api.EventFlush(eventHandle) }),
            ("EventKill", 14, 0, { api.EventKill(eventHandle) }),
            ("TLOpen", 15, -12015, { api.TLOpen(nil) }),
            ("TLClose", 16, -12016, { api.TLClose(nil) }),
            ("TLGetInfo", 17, -12017, { api.TLGetInfo(nil, 0, nil, nil, nil) }),
            ("TLGetNumInterfaces", 18, -12018, { api.TLGetNumInterfaces(nil, nil) }),
            ("TLGetInterfaceID", 19, -12019, { api.TLGetInterfaceID(nil, 0, nil, nil) }),
            ("TLGetInterfaceInfo", 20, -12020, { api.TLGetInterfaceInfo(nil, nil, 0, nil, nil, nil) }),
            ("TLOpenInterface", 21, -12021, { api.TLOpenInterface(nil, nil, nil) }),
            ("TLUpdateInterfaceList", 22, -12022, { api.TLUpdateInterfaceList(nil, nil, 0) }),
            ("IFClose", 23, -12023, { api.IFClose(nil) }),
            ("IFGetInfo", 24, -12024, { api.IFGetInfo(nil, 0, nil, nil, nil) }),
            ("IFGetNumDevices", 25, -12025, { api.IFGetNumDevices(nil, nil) }),
            ("IFGetDeviceID", 26, -12026, { api.IFGetDeviceID(nil, 0, nil, nil) }),
            ("IFUpdateDeviceList", 27, -12027, { api.IFUpdateDeviceList(nil, nil, 0) }),
            ("IFGetDeviceInfo", 28, -12028, { api.IFGetDeviceInfo(nil, nil, 0, nil, nil, nil) }),
            ("IFOpenDevice", 29, -12029, { api.IFOpenDevice(nil, nil, 0, nil) }),
            ("DevGetPort", 30, -12030, { api.DevGetPort(nil, nil) }),
            ("DevGetNumDataStreams", 31, -12031, { api.DevGetNumDataStreams(nil, nil) }),
            ("DevGetDataStreamID", 32, -12032, { api.DevGetDataStreamID(nil, 0, nil, nil) }),
            ("DevOpenDataStream", 33, -12033, { api.DevOpenDataStream(nil, nil, nil) }),
            ("DevGetInfo", 34, -12034, { api.DevGetInfo(nil, 0, nil, nil, nil) }),
            ("DevClose", 35, -12035, { api.DevClose(nil) }),
            ("DSAnnounceBuffer", 36, -12036, { api.DSAnnounceBuffer(nil, nil, 0, nil, nil) }),
            ("DSAllocAndAnnounceBuffer", 37, -12037, { api.DSAllocAndAnnounceBuffer(nil, 0, nil, nil) }),
            ("DSFlushQueue", 38, -12038, { api.DSFlushQueue(nil, 0) }),
            ("DSStartAcquisition", 39, -12039, { api.DSStartAcquisition(nil, 0, 0) }),
            ("DSStopAcquisition", 40, -12040, { api.DSStopAcquisition(nil, 0) }),
            ("DSGetInfo", 41, -12041, { api.DSGetInfo(nil, 0, nil, nil, nil) }),
            ("DSGetBufferID", 42, -12042, { api.DSGetBufferID(nil, 0, nil) }),
            ("DSClose", 43, -12043, { api.DSClose(nil) }),
            ("DSRevokeBuffer", 44, -12044, { api.DSRevokeBuffer(nil, nil, nil, nil) }),
            ("DSQueueBuffer", 45, -12045, { api.DSQueueBuffer(nil, nil) }),
            ("DSGetBufferInfo", 46, -12046, { api.DSGetBufferInfo(nil, nil, 0, nil, nil, nil) }),
            ("GCGetNumPortURLs", 47, -12047, { api.GCGetNumPortURLs(nil, nil) }),
            ("GCGetPortURLInfo", 48, -12048, { api.GCGetPortURLInfo(nil, 0, 0, nil, nil, nil) }),
            ("GCReadPortStacked", 49, -12049, { api.GCReadPortStacked(nil, nil, nil) }),
            ("GCWritePortStacked", 50, -12050, { api.GCWritePortStacked(nil, nil, nil) }),
            ("DSGetBufferChunkData", 51, -12051, { api.DSGetBufferChunkData(nil, nil, nil, nil) }),
            ("IFGetParentTL", 52, -12052, { api.IFGetParentTL(nil, nil) }),
            ("DevGetParentIF", 53, -12053, { api.DevGetParentIF(nil, nil) }),
            ("DSGetParentDev", 54, -12054, { api.DSGetParentDev(nil, nil) }),
            ("DSGetNumBufferParts", 55, -12055, { api.DSGetNumBufferParts(nil, nil, nil) }),
            ("DSGetBufferPartInfo", 56, -12056, { api.DSGetBufferPartInfo(nil, nil, 0, 0, nil, nil, nil) }),
            ("DSAnnounceCompositeBuffer", 57, -12057, { api.DSAnnounceCompositeBuffer(nil, 0, nil, nil, nil, nil) }),
            ("DSGetBufferInfoStacked", 58, -12058, { api.DSGetBufferInfoStacked(nil, nil, nil, 0) }),
            ("DSGetBufferPartInfoStacked", 59, -12059, { api.DSGetBufferPartInfoStacked(nil, nil, nil, 0) }),
            ("DSGetNumFlows", 60, -12060, { api.DSGetNumFlows(nil, nil) }),
            ("DSGetFlowInfo", 61, -12061, { api.DSGetFlowInfo(nil, 0, 0, nil, nil, nil) }),
            ("DSGetNumBufferSegments", 62, -12062, { api.DSGetNumBufferSegments(nil, nil, nil) }),
            ("DSGetBufferSegmentInfo", 63, -12063, { api.DSGetBufferSegmentInfo(nil, nil, 0, 0, nil, nil, nil) })
        ]

        for operation in operations {
            XCTAssertEqual(
                operation.invoke(),
                operation.expected,
                "Wrong native dispatch result for \(operation.name)"
            )
        }

        XCTAssertEqual(api.GCUnregisterEvent(nil, 0), GC_ERR_SUCCESS)
        XCTAssertEqual(api.GCCloseLib(), GC_ERR_SUCCESS)

        guard let library = dlopen(producerURL.path, RTLD_NOW | RTLD_LOCAL) else {
            return XCTFail("Could not reopen mock CTI for test-control inspection.")
        }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "MockCTI_GetCallCount") else {
            return XCTFail("Mock CTI did not export its test-only call counter.")
        }
        typealias CallCountFunction = @convention(c) (UInt32) -> UInt32
        let callCount = unsafeBitCast(symbol, to: CallCountFunction.self)

        for operation in operations {
            let expectedCount: UInt32 = operation.name == "EventKill" ? 2 : 1
            XCTAssertEqual(
                callCount(operation.index),
                expectedCount,
                "Unexpected native invocation count for \(operation.name)"
            )
        }
        XCTAssertEqual(callCount(4), 1, "GCReadPort must be invoked exactly once.")
        XCTAssertEqual(callCount(5), 1, "GCWritePort must be invoked exactly once.")
        XCTAssertEqual(callCount(2), 1, "GCInitLib must be invoked exactly once.")
        XCTAssertEqual(callCount(3), 1, "GCCloseLib must be invoked exactly once.")
        XCTAssertEqual(callCount(8), 1, "GCRegisterEvent must be invoked exactly once.")
        XCTAssertEqual(callCount(9), 1, "GCUnregisterEvent must be invoked exactly once.")
    }

    func testNativeLoaderRejectsCTIMissingRequiredEntryPoint() throws {
        let producerURL = try buildMockProducer(omittingGetInfo: true)

        XCTAssertThrowsError(try GenTLNativeImplementation(ctiURL: producerURL)) { error in
            guard let loaderError = error as? GenTLProducerLibraryError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            guard case .missingRequiredSymbol(let symbol) = loaderError else {
                return XCTFail("Unexpected loader error: \(loaderError)")
            }
            XCTAssertEqual(symbol, "GCGetInfo")
        }
    }

    func testAbsentLaterRevisionExportReturnsNotImplementedWithoutChangingOutput() throws {
        let producerURL = try buildMockProducer(omittingOptionalExports: true)
        let implementation = try GenTLNativeImplementation(ctiURL: producerURL)
        let api: any GenTLAPI = implementation
        var numberOfURLs: UInt32 = 0xDEADBEEF

        let result = withUnsafeMutablePointer(to: &numberOfURLs) { countPointer in
            api.GCGetNumPortURLs(nil, countPointer)
        }

        XCTAssertEqual(result, GC_ERR_NOT_IMPLEMENTED)
        XCTAssertEqual(numberOfURLs, 0xDEADBEEF)
    }

}
