// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GenTLNative",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GenTLNative", targets: ["GenTLNative"])
    ],
    targets: [
        .target(name: "GenTLABI", publicHeadersPath: "include"),
        .target(
            name: "GenTLNative",
            dependencies: ["GenTLABI", .product(name: "GenTLAPI", package: "GenTLAPI")]
        )
    ]
)
