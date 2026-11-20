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
        .package(path: "../AmcamImagingApplicationCore"),
        .package(path: "../GenTLRouter")
    ],
    targets: [
        .target(
            name: "AmcamImagingGenTLAdapter",
            dependencies: [
                .product(name: "AmcamImagingCore", package: "AmcamImagingCore"),
                .product(name: "AmcamImagingApplicationCore", package: "AmcamImagingApplicationCore"),
                .product(name: "GenTLRouter", package: "GenTLRouter")
            ]
        ),
        .testTarget(
            name: "AmcamImagingGenTLAdapterTests",
            dependencies: ["AmcamImagingGenTLAdapter", .product(name: "GenTLRouter", package: "GenTLRouter")]
        )
    ]
)
