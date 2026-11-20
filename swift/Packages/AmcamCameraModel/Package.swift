// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AmcamCameraModel",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AmcamCameraModel", targets: ["AmcamCameraModel"])
    ],
    targets: [
        .target(name: "AmcamCameraModel"),
        .testTarget(
            name: "AmcamCameraModelTests",
            dependencies: ["AmcamCameraModel"]
        )
    ]
)
