import Foundation
import XCTest
import GenTLABI
import GenTLAPI
@_spi(BackendFactory) @testable import GenTLNative

final class GenTLNativeIntegrationTests: XCTestCase {
    private func buildMockProducer(omittingGetInfo: Bool = false) throws -> URL {
        let testDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let source = testDirectory.appendingPathComponent("Fixtures/MockGenTLProducer.c")
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
                        0,
                        typePointer,
                        UnsafeMutableRawPointer(payloadPointer),
                        sizePointer
                    )
                }
            }
        }

        XCTAssertEqual(result, -4321)
        XCTAssertEqual(infoType, INFO_DATATYPE_UINT32)
        XCTAssertEqual(payload, 0xC0FFEE01)
        XCTAssertEqual(payloadSize, MemoryLayout<UInt32>.size)
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
        let producerURL = try buildMockProducer()
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
