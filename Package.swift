// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Helio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Helio", targets: ["HelioApp"]),
        .library(name: "HelioCore", targets: ["HelioCore"])
    ],
    targets: [
        .target(name: "HelioCore"),
        .executableTarget(name: "HelioApp", dependencies: ["HelioCore"]),
        .testTarget(name: "HelioCoreTests", dependencies: ["HelioCore"]),
        .testTarget(name: "HelioAppTests", dependencies: ["HelioApp"])
    ]
)
