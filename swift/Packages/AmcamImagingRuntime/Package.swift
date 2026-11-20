// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AmcamImagingRuntime",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "AmcamImagingRuntime", targets: ["AmcamImagingRuntime"])
    ],
    dependencies: [
        .package(path: "../AmcamImagingCore")
    ],
    targets: [
        .target(
            name: "AmcamImagingRuntime",
            dependencies: [
                .product(name: "AmcamImagingCore", package: "AmcamImagingCore")
            ]
        ),
        .testTarget(
            name: "AmcamImagingRuntimeTests",
            dependencies: ["AmcamImagingRuntime"]
        )
    ]
)
