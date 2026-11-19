// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GenTLRouter",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GenTLRouter", targets: ["GenTLRouter"])
    ],
    dependencies: [
        .package(path: "../GenTLAPI"),
        .package(path: "../GenTLNative"),
        .package(path: "../AmcamGenTL")
    ],
    targets: [
        .target(
            name: "GenTLRouter",
            dependencies: [
                .product(name: "GenTLAPI", package: "GenTLAPI"),
                .product(name: "GenTLNative", package: "GenTLNative"),
                .product(name: "AmcamGenTL", package: "AmcamGenTL")
            ]
        )
    ]
)
