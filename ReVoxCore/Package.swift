// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ReVoxCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReVoxCore", targets: ["ReVoxCore"]),
    ],
    targets: [
        .target(name: "ReVoxCore"),
        .testTarget(name: "ReVoxCoreTests", dependencies: ["ReVoxCore"]),
    ]
)
