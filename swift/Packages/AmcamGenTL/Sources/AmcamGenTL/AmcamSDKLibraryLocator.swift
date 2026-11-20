import Foundation

/// Resolves the AmScope SDK without exposing native library paths to the UI.
///
/// Packaged applications load the SDK from their own signed bundle first.
/// Machine-wide and per-user locations are development fallbacks only.
public enum AmcamSDKLibraryLocator {
    public static func locate() throws -> URL {
        let candidates = candidateURLs(
            bundleURL: Bundle.main.bundleURL,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        if let match = candidates.first(where: {
            FileManager.default.isReadableFile(atPath: $0.path)
        }) {
            return match.standardizedFileURL.resolvingSymlinksInPath()
        }
        throw AmcamCameraError.libraryNotFound(
            candidates.map(\.path).joined(separator: " or ")
        )
    }

    static func candidateURLs(bundleURL: URL, homeDirectory: URL) -> [URL] {
        let frameworks = bundleURL
            .appendingPathComponent("Contents/Frameworks", isDirectory: true)
        return [
            frameworks
                .appendingPathComponent("Vendors/amcam/macos", isDirectory: true)
                .appendingPathComponent("libamcam.dylib"),
            homeDirectory
                .appendingPathComponent("Library/Application Support/AmScopeMicroscope/SDK", isDirectory: true)
                .appendingPathComponent("libamcam.dylib"),
            URL(fileURLWithPath: "/Library/Application Support/AmScopeMicroscope/SDK", isDirectory: true)
                .appendingPathComponent("libamcam.dylib"),
            URL(fileURLWithPath: "/Library/Frameworks", isDirectory: true)
                .appendingPathComponent("libamcam.dylib"),
            URL(fileURLWithPath: "/usr/local/lib", isDirectory: true)
                .appendingPathComponent("libamcam.dylib"),
            URL(fileURLWithPath: "/opt/homebrew/lib", isDirectory: true)
                .appendingPathComponent("libamcam.dylib")
        ]
    }
}
