// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"])
    ],
    targets: [
        .executableTarget(
            name: "DynamicIsland",
            path: "Sources/DynamicIsland"
        ),
        .testTarget(
            name: "DynamicIslandTests",
            dependencies: ["DynamicIsland"],
            path: "Tests/DynamicIslandTests"
        )
    ]
)
