// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GenTLAPI",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GenTLAPI", targets: ["GenTLAPI"])
    ],
    targets: [
        .target(name: "GenTLAPI"),
        .testTarget(name: "GenTLAPITests", dependencies: ["GenTLAPI"])
    ]
)
