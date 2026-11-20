// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GenTLABI",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GenTLABI", targets: ["GenTLABI"])
    ],
    targets: [
        .target(name: "GenTLABI", publicHeadersPath: "include")
    ]
)
