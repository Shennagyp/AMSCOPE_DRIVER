import Darwin
import Foundation
import GenTLABI
import GenTLAPI

public enum GenTLProducerLibraryError: Error, LocalizedError, Sendable {
    case fileNotFound(String)
    case loadFailed(path: String, reason: String)
    case missingRequiredSymbol(String)
    case symbolNotFound(String)
    case unsupportedABI

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "GenTL Producer library was not found at '\(path)'."
        case .loadFailed(let path, let reason):
            return "Could not load GenTL Producer '\(path)': \(reason)"
        case .missingRequiredSymbol(let symbol):
            return "The selected CTI library is missing required GenTL entry point '\(symbol)'."
        case .symbolNotFound(let symbol):
            return "GenTL Producer does not export symbol '\(symbol)'."
        case .unsupportedABI:
            return "The current process architecture does not match the GenTL 1.6 ABI layouts compiled into this consumer."
        }
    }
}

/// Owns one loaded GenTL Producer (.cti) dynamic library.
///
/// This class only loads and resolves the Producer's GenTL C ABI. Module
/// operations are implemented by the GenTLNative API adapter, not by this loader.
public final class GenTLProducerLibrary: @unchecked Sendable {
    public static let requiredEntryPoints = [
        "GCInitLib",
        "GCCloseLib",
        "TLOpen",
        "TLClose"
    ]

    public let url: URL
    public let genTLHeaderVersion = GenTLVersion.v1_6
    public static let abiHeaderVersionCode: UInt32 = GenTLABI_HeaderVersion()

    private let libraryHandle: UnsafeMutableRawPointer
    private let lock = NSLock()

    public init(url: URL) throws {
        guard GenTLABI_LayoutValid() == 1 else {
            throw GenTLProducerLibraryError.unsupportedABI
        }

        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path

        guard FileManager.default.fileExists(atPath: path) else {
            throw GenTLProducerLibraryError.fileNotFound(path)
        }

        guard let loaded = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "Unknown dynamic-loader error."
            throw GenTLProducerLibraryError.loadFailed(path: path, reason: reason)
        }

        self.url = standardizedURL
        self.libraryHandle = loaded

        do {
            for entryPoint in Self.requiredEntryPoints {
                guard dlsym(loaded, entryPoint) != nil else {
                    throw GenTLProducerLibraryError.missingRequiredSymbol(entryPoint)
                }
            }
        } catch {
            dlclose(loaded)
            throw error
        }
    }

    /// Resolves a GenTL function exported by this Producer.
    /// The returned address is valid only while this library instance is alive.
    public func resolveSymbol(_ name: String) throws -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }

        guard let address = dlsym(libraryHandle, name) else {
            throw GenTLProducerLibraryError.symbolNotFound(name)
        }
        return address
    }

    deinit {
        dlclose(libraryHandle)
    }
}
