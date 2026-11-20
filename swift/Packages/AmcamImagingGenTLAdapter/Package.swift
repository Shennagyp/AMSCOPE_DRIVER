// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AmcamImagingGenTLAdapter",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AmcamImagingGenTLAdapter", targets: ["AmcamImagingGenTLAdapter"])
    ],
    dependencies: [
        .package(path: "../AmcamImagingCore"),
        .package(path: "../AmcamImagingRuntime"),
        .package(path: "../GenTLRouter")
    ],
    targets: [
        .target(
            name: "AmcamImagingGenTLAdapter",
            dependencies: [
                .product(name: "AmcamImagingCore", package: "AmcamImagingCore"),
                .product(name: "AmcamImagingRuntime", package: "AmcamImagingRuntime"),
                .product(name: "GenTLRouter", package: "GenTLRouter")
            ]
        ),
        .testTarget(
            name: "AmcamImagingGenTLAdapterTests",
            dependencies: ["AmcamImagingGenTLAdapter", .product(name: "GenTLRouter", package: "GenTLRouter")]
        )
    ]
)
