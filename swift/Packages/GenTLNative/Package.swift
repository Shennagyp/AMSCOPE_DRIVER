// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GenTLNative",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GenTLNative", targets: ["GenTLNative"])
    ],
    dependencies: [
        .package(path: "../GenTLAPI"),
        .package(path: "../GenTLABI")
    ],
    targets: [
        .target(
            name: "GenTLNative",
            dependencies: [
                .product(name: "GenTLABI", package: "GenTLABI"),
                .product(name: "GenTLAPI", package: "GenTLAPI")
            ]
        ),
        .testTarget(
            name: "GenTLNativeTests",
            dependencies: ["GenTLNative"]
        )
    ]
)
