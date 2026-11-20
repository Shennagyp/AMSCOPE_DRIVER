// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AmcamImagingCore",
    products: [
        .library(name: "AmcamImagingCore", targets: ["AmcamImagingCore"])
    ],
    targets: [
        .target(name: "AmcamImagingCore"),
        .testTarget(
            name: "AmcamImagingCoreTests",
            dependencies: ["AmcamImagingCore"]
        )
    ]
)
