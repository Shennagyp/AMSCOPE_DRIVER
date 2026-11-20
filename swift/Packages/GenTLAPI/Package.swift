// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GenTLAPI",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GenTLAPI", targets: ["GenTLAPI"])
    ],
    dependencies: [
        .package(path: "../GenTLABI")
    ],
    targets: [
        .target(
            name: "GenTLAPI",
            dependencies: [
                .product(name: "GenTLABI", package: "GenTLABI")
            ]
        ),
        .testTarget(
            name: "GenTLAPITests",
            dependencies: [
                "GenTLAPI",
                .product(name: "GenTLABI", package: "GenTLABI")
            ]
        )
    ]
)
