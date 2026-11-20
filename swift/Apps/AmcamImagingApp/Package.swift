// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AmcamImagingApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "amcam-imaging", targets: ["AmcamImagingApp"])
    ],
    dependencies: [
        .package(path: "../../Packages/GenTLABI"),
        .package(path: "../../Packages/GenTLAPI"),
        .package(path: "../../Packages/GenTLRouter"),
        .package(path: "../../Packages/AmcamCameraModel")
    ],
    targets: [
        .executableTarget(
            name: "AmcamImagingApp",
            dependencies: [
                .product(name: "GenTLABI", package: "GenTLABI"),
                .product(name: "GenTLAPI", package: "GenTLAPI"),
                .product(name: "GenTLRouter", package: "GenTLRouter"),
                .product(name: "AmcamCameraModel", package: "AmcamCameraModel")
            ]
        )
    ]
)
