// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Setscry",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SetscryCore", targets: ["SetscryCore"]),
        .library(name: "SetscryML", targets: ["SetscryML"]),
        .library(name: "SetscryMLX", targets: ["SetscryMLX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.6")),
    ],
    targets: [
        .target(name: "SetscryCore"),
        // Deliberately free of MLX: the embedding interface and the Vision
        // backend must keep working if MLX is never loaded.
        .target(name: "SetscryML", dependencies: ["SetscryCore"]),
        .target(
            name: "SetscryMLX",
            dependencies: [
                "SetscryML",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
            ]
        ),
        .testTarget(
            name: "SetscryCoreTests",
            dependencies: ["SetscryCore", "SetscryML", "SetscryMLX"]
        ),
    ]
)
