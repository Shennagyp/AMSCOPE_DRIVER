import Foundation

/// Resolves the AmScope SDK from the application's managed vendor directory.
///
/// The UI never selects or supplies a native library path. The build assembles
/// vendor SDKs under Contents/Frameworks/Vendors/<vendor>/..., and this
/// backend-owned locator selects the current process architecture.
public enum AmcamSDKLibraryLocator {
    public static func locate() throws -> URL {
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unsupported"
        #endif

        var candidates: [URL] = []
        let frameworks = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks", isDirectory: true)
        for arch in [architecture, "universal"] {
            candidates.append(
                frameworks
                    .appendingPathComponent("Vendors/amscope/macos/\(arch)", isDirectory: true)
                    .appendingPathComponent("libamcam.dylib")
            )
        }

        // Source-tree fallback is for development/probing only. A packaged app
        // resolves from its own signed bundle and does not depend on cwd.
        let sourceVendorRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("vendor/amscope/macos", isDirectory: true)
        for arch in [architecture, "universal"] {
            candidates.append(
                sourceVendorRoot
                    .appendingPathComponent(arch, isDirectory: true)
                    .appendingPathComponent("libamcam.dylib")
            )
        }

        if let match = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) {
            return match.standardizedFileURL.resolvingSymlinksInPath()
        }

        throw AmcamCameraError.libraryNotFound(
            candidates.map(\.path).joined(separator: " or ")
        )
    }
}
