import Darwin
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

    func testDirectoryScanContinuesAfterBrokenCTISymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTLBrokenEntryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let producer = root.appendingPathComponent("valid.cti")
        let brokenLink = root.appendingPathComponent("broken.cti")
        XCTAssertTrue(FileManager.default.createFile(atPath: producer.path, contents: Data()))
        try FileManager.default.createSymbolicLink(
            atPath: brokenLink.path,
            withDestinationPath: root.appendingPathComponent("missing.cti").path
        )

        let result = GenTLProducerCatalog.discover(
            searchPaths: [root],
            environment: [:]
        )

        XCTAssertEqual(result.producers.map(\.lastPathComponent), ["valid.cti"])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.path, brokenLink.path)
    }

    func testExplicitCTIPathMustBeARegularFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTLNonRegularEntryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fifo = root.appendingPathComponent("not-a-library.cti")
        let status = fifo.path.withCString { mkfifo($0, mode_t(0o600)) }
        XCTAssertEqual(status, 0)

        let result = GenTLProducerCatalog.discover(
            searchPaths: [fifo],
            environment: [:]
        )

        XCTAssertTrue(result.producers.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.issues[0].message.contains("regular file"))
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
