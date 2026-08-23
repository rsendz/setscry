// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Setscry",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SetscryCore", targets: ["SetscryCore"]),
        .library(name: "SetscryML", targets: ["SetscryML"]),
        .library(name: "SetscryMLX", targets: ["SetscryMLX"]),
        .executable(name: "Setscry", targets: ["Setscry"]),
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
        .executableTarget(
            name: "Setscry",
            dependencies: ["SetscryCore", "SetscryML", "SetscryMLX"],
            path: "Sources/SetscryApp"
        ),
        // A build tool, not part of the app: it prepares the weights that
        // Scripts/make-app.sh puts inside the bundle.
        .executableTarget(
            name: "prepare-model",
            dependencies: [
                "SetscryMLX",
                .product(name: "MLX", package: "mlx-swift"),
            ],
            path: "Sources/PrepareModel"
        ),
        .testTarget(
            name: "SetscryCoreTests",
            dependencies: ["SetscryCore", "SetscryML", "SetscryMLX", "Setscry"]
        ),
    ]
)
