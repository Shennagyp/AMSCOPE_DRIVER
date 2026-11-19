import Foundation

public struct GenTLProducerSearchIssue: Equatable, Sendable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct GenTLProducerSearchResult: Sendable {
    public let producers: [URL]
    public let searchedPaths: [URL]
    public let issues: [GenTLProducerSearchIssue]

    public init(
        producers: [URL],
        searchedPaths: [URL],
        issues: [GenTLProducerSearchIssue]
    ) {
        self.producers = producers
        self.searchedPaths = searchedPaths
        self.issues = issues
    }
}

/// Finds installed GenTL Producer libraries without loading them.
///
/// On 64-bit macOS, the standard GenICam search path is GENICAM_GENTL64_PATH.
/// Explicit paths may be directories or individual .cti files. Directories
/// are scanned one level deep, which matches the standard search-path model.
public enum GenTLProducerCatalog {
    public static let standardSearchPathEnvironmentVariable = "GENICAM_GENTL64_PATH"

    public static func discover(
        searchPaths: [URL] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GenTLProducerSearchResult {
        var requestedPaths = searchPaths

        if let value = environment[standardSearchPathEnvironmentVariable], !value.isEmpty {
            // GenICam search paths use the host platform's path-list separator.
            // This package targets macOS, where POSIX uses ':'.
            let components = value
                .components(separatedBy: ":")
                .filter { !$0.isEmpty }

            requestedPaths.append(contentsOf: components.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            })
        }

        var seenPaths = Set<String>()
        let normalizedPaths = requestedPaths.compactMap { url -> URL? in
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            guard seenPaths.insert(normalized.path).inserted else { return nil }
            return normalized
        }

        var producersByPath: [String: URL] = [:]
        var issues: [GenTLProducerSearchIssue] = []

        for path in normalizedPaths {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: path.path,
                isDirectory: &isDirectory
            ) else {
                issues.append(
                    GenTLProducerSearchIssue(
                        path: path.path,
                        message: "GenTL search path does not exist."
                    )
                )
                continue
            }

            if !isDirectory.boolValue {
                guard path.pathExtension.caseInsensitiveCompare("cti") == .orderedSame else {
                    issues.append(
                        GenTLProducerSearchIssue(
                            path: path.path,
                            message: "An explicit producer file must have the .cti extension."
                        )
                    )
                    continue
                }

                do {
                    let values = try path.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true else {
                        issues.append(
                            GenTLProducerSearchIssue(
                                path: path.path,
                                message: "An explicit .cti producer path must refer to a regular file."
                            )
                        )
                        continue
                    }
                    producersByPath[path.path] = path
                } catch {
                    issues.append(
                        GenTLProducerSearchIssue(
                            path: path.path,
                            message: "Could not inspect explicit .cti producer file: \(error.localizedDescription)"
                        )
                    )
                }
                continue
            }

            do {
                let children = try FileManager.default.contentsOfDirectory(
                    at: path,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                for child in children {
                    guard child.pathExtension.caseInsensitiveCompare("cti") == .orderedSame else {
                        continue
                    }

                    let normalized = child.standardizedFileURL.resolvingSymlinksInPath()
                    guard FileManager.default.fileExists(atPath: normalized.path) else {
                        issues.append(
                            GenTLProducerSearchIssue(
                                path: child.path,
                                message: "The .cti entry points to a missing file."
                            )
                        )
                        continue
                    }

                    do {
                        let values = try normalized.resourceValues(forKeys: [.isRegularFileKey])
                        guard values.isRegularFile == true else { continue }
                        producersByPath[normalized.path] = normalized
                    } catch {
                        // One broken or unreadable entry must not prevent valid
                        // Producers elsewhere in the same directory being found.
                        issues.append(
                            GenTLProducerSearchIssue(
                                path: child.path,
                                message: "Could not inspect .cti entry: \(error.localizedDescription)"
                            )
                        )
                    }
                }
            } catch {
                issues.append(
                    GenTLProducerSearchIssue(
                        path: path.path,
                        message: "Could not enumerate GenTL search path: \(error.localizedDescription)"
                    )
                )
            }
        }

        let producers = producersByPath.values.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }

        return GenTLProducerSearchResult(
            producers: producers,
            searchedPaths: normalizedPaths,
            issues: issues
        )
    }
}
