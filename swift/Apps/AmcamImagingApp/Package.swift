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
        .package(path: "../../Packages/AmcamCameraModel"),
        .package(path: "../../Packages/AmcamImagingCore"),
        .package(path: "../../Packages/AmcamImagingRuntime"),
        .package(path: "../../Packages/AmcamImagingGenTLAdapter")
    ],
    targets: [
        .executableTarget(
            name: "AmcamImagingApp",
            dependencies: [
                .product(name: "GenTLABI", package: "GenTLABI"),
                .product(name: "GenTLAPI", package: "GenTLAPI"),
                .product(name: "GenTLRouter", package: "GenTLRouter"),
                .product(name: "AmcamCameraModel", package: "AmcamCameraModel"),
                .product(name: "AmcamImagingCore", package: "AmcamImagingCore"),
                .product(name: "AmcamImagingRuntime", package: "AmcamImagingRuntime"),
                .product(name: "AmcamImagingGenTLAdapter", package: "AmcamImagingGenTLAdapter")
            ]
        )
    ]
)
