import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

/// Owns a native library handle and resolves exported C symbols.
///
/// Camera SDK handles, callback function pointers, and sessions depend on the
/// library staying loaded. The AmcamSDK object retains this value for as long
/// as any session can call into the native SDK.
final class AmcamDynamicLibrary {
    #if os(Windows)
    private let handle: HMODULE
    #elseif canImport(Darwin) || canImport(Glibc)
    private let handle: UnsafeMutableRawPointer
    #else
    private let handle: UnsafeMutableRawPointer
    #endif

    init(url: URL) throws {
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw AmcamCameraError.libraryNotFound(path)
        }

        #if canImport(Darwin) || canImport(Glibc)
        guard let loadedHandle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "Unknown dynamic-loader error"
            throw AmcamCameraError.libraryLoadFailed("Unable to load '\\(path)': \\(message)")
        }
        self.handle = loadedHandle
        #elseif os(Windows)
        let widePath = Array(path.utf16) + [0]
        guard let loadedHandle = widePath.withUnsafeBufferPointer({ buffer in
            LoadLibraryW(buffer.baseAddress)
        }) else {
            throw AmcamCameraError.libraryLoadFailed(
                "LoadLibraryW failed for '\(path)' with Win32 error \(GetLastError())."
            )
        }
        self.handle = loadedHandle
        #else
        throw AmcamCameraError.libraryLoadFailed(
            "Dynamic loading is not implemented for this operating system."
        )
        #endif
    }

    func symbol(named name: String) throws -> UnsafeMutableRawPointer {
        #if canImport(Darwin) || canImport(Glibc)
        guard let pointer = name.withCString({ dlsym(handle, $0) }) else {
            throw AmcamCameraError.missingSymbol(name)
        }
        return pointer
        #elseif os(Windows)
        guard let procedure = name.withCString({ GetProcAddress(handle, $0) }) else {
            throw AmcamCameraError.missingSymbol(name)
        }
        return unsafeBitCast(procedure, to: UnsafeMutableRawPointer.self)
        #else
        throw AmcamCameraError.missingSymbol(name)
        #endif
    }

    deinit {
        #if canImport(Darwin) || canImport(Glibc)
        dlclose(handle)
        #elseif os(Windows)
        FreeLibrary(handle)
        #endif
    }
}
