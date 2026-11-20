import Darwin
import Foundation
import GenTLABI
import GenTLAPI

enum GenTLProducerLibraryError: Error, LocalizedError, Sendable {
    case fileNotFound(String)
    case notRegularFile(String)
    case loadFailed(path: String, reason: String)
    case missingRequiredSymbol(String)
    case symbolNotFound(String)
    case unsupportedABI

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "GenTL Producer library was not found at '\(path)'."
        case .notRegularFile(let path):
            return "GenTL Producer path is not a regular file: '\(path)'."
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
final class GenTLProducerLibrary: @unchecked Sendable {
    /// Functions required by the GenTL 1.0 base API. Symbols introduced by
    /// later revisions are resolved optionally by GenTLNativeImplementation.
    static let requiredEntryPoints = [
        "GCGetInfo",
        "GCGetLastError",
        "GCInitLib",
        "GCCloseLib",
        "GCReadPort",
        "GCWritePort",
        "GCGetPortURL",
        "GCGetPortInfo",
        "GCRegisterEvent",
        "GCUnregisterEvent",
        "EventGetData",
        "EventGetDataInfo",
        "EventGetInfo",
        "EventFlush",
        "EventKill",
        "TLOpen",
        "TLClose",
        "TLGetInfo",
        "TLGetNumInterfaces",
        "TLGetInterfaceID",
        "TLGetInterfaceInfo",
        "TLOpenInterface",
        "TLUpdateInterfaceList",
        "IFClose",
        "IFGetInfo",
        "IFGetNumDevices",
        "IFGetDeviceID",
        "IFUpdateDeviceList",
        "IFGetDeviceInfo",
        "IFOpenDevice",
        "DevGetPort",
        "DevGetNumDataStreams",
        "DevGetDataStreamID",
        "DevOpenDataStream",
        "DevGetInfo",
        "DevClose",
        "DSAnnounceBuffer",
        "DSAllocAndAnnounceBuffer",
        "DSFlushQueue",
        "DSStartAcquisition",
        "DSStopAcquisition",
        "DSGetInfo",
        "DSGetBufferID",
        "DSClose",
        "DSRevokeBuffer",
        "DSQueueBuffer",
        "DSGetBufferInfo"
    ]

    let url: URL
    let genTLHeaderVersion = GenTLVersion.v1_6
    static let abiHeaderVersionCode: UInt32 = GenTLABI_HeaderVersion()

    private let libraryHandle: UnsafeMutableRawPointer
    private let lock = NSLock()

    init(url: URL) throws {
        guard GenTLABI_LayoutValid() == 1 else {
            throw GenTLProducerLibraryError.unsupportedABI
        }

        // Resolve aliases before loading so the library identity and retained
        // URL are stable even when the caller supplies a symlink.
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = standardizedURL.path

        guard FileManager.default.fileExists(atPath: path) else {
            throw GenTLProducerLibraryError.fileNotFound(path)
        }

        do {
            let values = try standardizedURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw GenTLProducerLibraryError.notRegularFile(path)
            }
        } catch let error as GenTLProducerLibraryError {
            throw error
        } catch {
            throw GenTLProducerLibraryError.notRegularFile(path)
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
    func resolveSymbol(_ name: String) throws -> UnsafeMutableRawPointer {
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
