import Foundation
import XCTest
@testable import GenTLNative

final class GenTLProducerLibraryTests: XCTestCase {
    func testRequiredEntryPointsAreTheCompleteGenTL10BaseSet() {
        let expected: Set<String> = [
            "GCGetInfo", "GCGetLastError", "GCInitLib", "GCCloseLib",
            "GCReadPort", "GCWritePort", "GCGetPortURL", "GCGetPortInfo",
            "GCRegisterEvent", "GCUnregisterEvent", "EventGetData", "EventGetDataInfo",
            "EventGetInfo", "EventFlush", "EventKill",
            "TLOpen", "TLClose", "TLGetInfo", "TLGetNumInterfaces", "TLGetInterfaceID",
            "TLGetInterfaceInfo", "TLOpenInterface", "TLUpdateInterfaceList",
            "IFClose", "IFGetInfo", "IFGetNumDevices", "IFGetDeviceID", "IFUpdateDeviceList",
            "IFGetDeviceInfo", "IFOpenDevice",
            "DevGetPort", "DevGetNumDataStreams", "DevGetDataStreamID", "DevOpenDataStream",
            "DevGetInfo", "DevClose",
            "DSAnnounceBuffer", "DSAllocAndAnnounceBuffer", "DSFlushQueue",
            "DSStartAcquisition", "DSStopAcquisition", "DSGetInfo", "DSGetBufferID",
            "DSClose", "DSRevokeBuffer", "DSQueueBuffer", "DSGetBufferInfo"
        ]

        let actual = GenTLProducerLibrary.requiredEntryPoints
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertEqual(Set(actual), expected)
    }

    func testGenTL10EventDataInfoIsMandatory() {
        XCTAssertTrue(
            GenTLProducerLibrary.requiredEntryPoints.contains("EventGetDataInfo")
        )
    }

    func testLaterRevisionExtensionsAreNotRequiredForBaseProducerLoading() {
        let required = Set(GenTLProducerLibrary.requiredEntryPoints)
        let laterRevisionFunctions = [
            "GCGetNumPortURLs",
            "GCGetPortURLInfo",
            "GCReadPortStacked",
            "GCWritePortStacked",
            "IFGetParentTL",
            "DevGetParentIF",
            "DSGetParentDev",
            "DSGetBufferChunkData",
            "DSGetNumBufferParts",
            "DSGetBufferPartInfo",
            "DSAnnounceCompositeBuffer",
            "DSGetBufferInfoStacked",
            "DSGetBufferPartInfoStacked",
            "DSGetNumFlows",
            "DSGetFlowInfo",
            "DSGetNumBufferSegments",
            "DSGetBufferSegmentInfo"
        ]

        for function in laterRevisionFunctions {
            XCTAssertFalse(required.contains(function), "\(function) must remain optional.")
        }
    }

    func testLoaderRejectsDirectoryAsProducerFile() throws {
        XCTAssertThrowsError(
            try GenTLProducerLibrary(url: FileManager.default.temporaryDirectory)
        ) { error in
            guard case GenTLProducerLibraryError.notRegularFile = error else {
                return XCTFail("Expected notRegularFile, received \(error)")
            }
        }
    }


    func testLoaderReportsInvalidDynamicLibrary() throws {
        let invalid = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-\(UUID().uuidString).cti")
        try Data("not a Mach-O dynamic library".utf8).write(to: invalid)
        defer { try? FileManager.default.removeItem(at: invalid) }

        XCTAssertThrowsError(try GenTLProducerLibrary(url: invalid)) { error in
            guard case GenTLProducerLibraryError.loadFailed(let path, _) = error else {
                return XCTFail("Expected loadFailed, received \(error)")
            }
            XCTAssertEqual(path, invalid.standardizedFileURL.resolvingSymlinksInPath().path)
        }
    }

    func testLoaderReportsMissingProducerFile() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).cti")

        XCTAssertThrowsError(try GenTLProducerLibrary(url: missing)) { error in
            guard case GenTLProducerLibraryError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound, received \(error)")
            }
        }
    }
}
