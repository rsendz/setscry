// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Setscry",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SetscryCore", targets: ["SetscryCore"]),
        .library(name: "SetscryML", targets: ["SetscryML"]),
    ],
    targets: [
        .target(name: "SetscryCore"),
        // Deliberately free of MLX: the embedding interface and the Vision
        // backend must keep working if MLX is never loaded.
        .target(name: "SetscryML", dependencies: ["SetscryCore"]),
        .testTarget(name: "SetscryCoreTests", dependencies: ["SetscryCore", "SetscryML"]),
    ]
)
