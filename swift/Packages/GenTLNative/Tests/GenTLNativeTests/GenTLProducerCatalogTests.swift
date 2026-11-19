import Foundation
import XCTest
@testable import GenTLNative

final class GenTLProducerCatalogTests: XCTestCase {
    func testDiscoversOnlyTopLevelCTIFilesAndSortsResults() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTLProducerCatalogTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for name in ["zeta.cti", "alpha.CTI", "ignore.txt"] {
            let url = root.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        }
        let nestedProducer = nested.appendingPathComponent("nested.cti")
        XCTAssertTrue(FileManager.default.createFile(atPath: nestedProducer.path, contents: Data()))

        let result = GenTLProducerCatalog.discover(
            searchPaths: [root],
            environment: [:]
        )

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(
            result.producers.map(\.lastPathComponent),
            ["alpha.CTI", "zeta.cti"]
        )
    }

    func testReadsStandardGenICamEnvironmentSearchPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTLProducerEnvironmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let producer = root.appendingPathComponent("camera.cti")
        XCTAssertTrue(FileManager.default.createFile(atPath: producer.path, contents: Data()))

        let result = GenTLProducerCatalog.discover(
            environment: [GenTLProducerCatalog.standardSearchPathEnvironmentVariable: root.path]
        )

        XCTAssertEqual(result.producers.map(\.standardizedFileURL), [producer.standardizedFileURL])
    }

    func testReportsMissingSearchPathsInsteadOfSilentlyIgnoringThem() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)", isDirectory: true)

        let result = GenTLProducerCatalog.discover(
            searchPaths: [missing],
            environment: [:]
        )

        XCTAssertTrue(result.producers.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.path, missing.standardizedFileURL.path)
    }

    func testEnvironmentPathsPreserveSemicolonsInMacOSDirectoryNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTL;Producer;Path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let producer = root.appendingPathComponent("camera.cti")
        XCTAssertTrue(FileManager.default.createFile(atPath: producer.path, contents: Data()))

        let result = GenTLProducerCatalog.discover(
            environment: [GenTLProducerCatalog.standardSearchPathEnvironmentVariable: root.path]
        )

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.producers.map(\.standardizedFileURL), [producer.standardizedFileURL])
    }

    func testDirectCTIPathsAndSymlinkAliasesAreRegisteredOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTLProducerAliasTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let producer = root.appendingPathComponent("camera.cti")
        let alias = root.appendingPathComponent("camera-alias.cti")
        XCTAssertTrue(FileManager.default.createFile(atPath: producer.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: producer)

        let result = GenTLProducerCatalog.discover(
            searchPaths: [producer, alias, root],
            environment: [:]
        )

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.producers.count, 1)
        XCTAssertEqual(
            result.producers.first?.resolvingSymlinksInPath(),
            producer.resolvingSymlinksInPath()
        )
    }
}
