import Foundation
import XCTest
@testable import AmcamGenTL

#if os(macOS) || os(Linux)
final class AmcamDynamicLibraryTests: XCTestCase {
    func testLoadsNativeLibraryAndResolvesCFunction() throws {
        let libraryURL = try buildFixtureLibrary()
        let library = try AmcamDynamicLibrary(url: libraryURL)
        let symbol = try library.symbol(named: "amcam_loader_test_add")
        typealias AddFunction = @convention(c) (Int32, Int32) -> Int32
        let add = unsafeBitCast(symbol, to: AddFunction.self)

        XCTAssertEqual(add(19, 23), 42)
    }

    func testMissingSymbolIsReportedWithoutUnloadingLibraryEarly() throws {
        let libraryURL = try buildFixtureLibrary()
        let library = try AmcamDynamicLibrary(url: libraryURL)

        XCTAssertThrowsError(try library.symbol(named: "amcam_symbol_that_does_not_exist")) { error in
            guard case AmcamCameraError.missingSymbol("amcam_symbol_that_does_not_exist") = error else {
                XCTFail("Expected a missing-symbol error, got: \(error)")
                return
            }
        }

        let existing = try library.symbol(named: "amcam_loader_test_add")
        typealias AddFunction = @convention(c) (Int32, Int32) -> Int32
        XCTAssertEqual(unsafeBitCast(existing, to: AddFunction.self)(20, 22), 42)
    }

    func testMissingLibraryPathIsReported() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(Self.libraryExtension)

        XCTAssertThrowsError(try AmcamDynamicLibrary(url: url)) { error in
            guard case AmcamCameraError.libraryNotFound = error else {
                XCTFail("Expected a library-not-found error, got: \(error)")
                return
            }
        }
    }

    private static var libraryExtension: String {
        #if os(macOS)
        return "dylib"
        #else
        return "so"
        #endif
    }

    private func buildFixtureLibrary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AmcamDynamicLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = directory.appendingPathComponent("loader_fixture.c")
        let output = directory.appendingPathComponent("libLoaderFixture.\(Self.libraryExtension)")
        try """
        #include <stdint.h>
        int32_t amcam_loader_test_add(int32_t left, int32_t right) {
            return left + right;
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        #if os(macOS)
        process.arguments = ["-dynamiclib", "-fPIC", source.path, "-o", output.path]
        #else
        process.arguments = ["-shared", "-fPIC", source.path, "-o", output.path]
        #endif
        let diagnostics = Pipe()
        process.standardError = diagnostics
        try process.run()
        process.waitUntilExit()
        let message = String(
            data: diagnostics.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "Fixture compiler failed: \(message)")
        return output
    }
}
#endif
