// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"]),
        .executable(name: "DynamicIslandAgentRelay", targets: ["DynamicIslandAgentRelay"])
    ],
    targets: [
        .target(
            name: "AgentBridgeShared",
            path: "Sources/AgentBridgeShared"
        ),
        .executableTarget(
            name: "DynamicIsland",
            dependencies: ["AgentBridgeShared"],
            path: "Sources/DynamicIsland",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .executableTarget(
            name: "DynamicIslandAgentRelay",
            dependencies: ["AgentBridgeShared"],
            path: "Sources/DynamicIslandAgentRelay"
        ),
        .testTarget(
            name: "DynamicIslandTests",
            dependencies: ["DynamicIsland", "AgentBridgeShared"],
            path: "Tests/DynamicIslandTests"
        )
    ]
)
