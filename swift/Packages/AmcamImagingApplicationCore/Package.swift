// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AmcamImagingApplicationCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AmcamImagingApplicationCore", targets: ["AmcamImagingApplicationCore"])
    ],
    dependencies: [
        .package(path: "../AmcamImagingCore")
    ],
    targets: [
        .target(
            name: "AmcamImagingApplicationCore",
            dependencies: [
                .product(name: "AmcamImagingCore", package: "AmcamImagingCore")
            ]
        ),
        .testTarget(
            name: "AmcamImagingApplicationCoreTests",
            dependencies: ["AmcamImagingApplicationCore"]
        )
    ]
)
