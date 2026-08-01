// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Setscry",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SetscryCore", targets: ["SetscryCore"]),
    ],
    targets: [
        .target(name: "SetscryCore"),
    ]
)
