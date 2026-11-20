// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AmcamImagingState",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AmcamImagingState", targets: ["AmcamImagingState"])
    ],
    dependencies: [
        .package(path: "../AmcamCameraModel"),
        .package(path: "../AmcamImagingRuntime")
    ],
    targets: [
        .target(
            name: "AmcamImagingState",
            dependencies: [
                .product(name: "AmcamCameraModel", package: "AmcamCameraModel"),
                .product(name: "AmcamImagingRuntime", package: "AmcamImagingRuntime")
            ]
        ),
        .testTarget(
            name: "AmcamImagingStateTests",
            dependencies: ["AmcamImagingState"]
        )
    ]
)
