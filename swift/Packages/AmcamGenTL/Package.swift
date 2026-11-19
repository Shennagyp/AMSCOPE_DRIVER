// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AmcamGenTL",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AmcamGenTL", targets: ["AmcamGenTL"])
    ],
    dependencies: [
        .package(path: "../GenTLAPI")
    ],
    targets: [
        .target(name: "AmcamABI", publicHeadersPath: "include"),
        .target(
            name: "AmcamGenTL",
            dependencies: [
                "AmcamABI",
                .product(name: "GenTLAPI", package: "GenTLAPI")
            ]
        ),
        .testTarget(
            name: "AmcamGenTLTests",
            dependencies: ["AmcamGenTL"]
        )
    ]
)
