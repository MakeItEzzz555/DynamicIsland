// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"]),
        .executable(name: "DynamicIslandAgentRelay", targets: ["DynamicIslandAgentRelay"]),
        .executable(name: "DynamicIslandCodexHookRelay", targets: ["DynamicIslandCodexHookRelay"])
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
        .target(
            name: "CodexHookShared",
            dependencies: ["AgentBridgeShared"],
            path: "Sources/CodexHookShared"
        ),
        .executableTarget(
            name: "DynamicIslandAgentRelay",
            dependencies: ["AgentBridgeShared"],
            path: "Sources/DynamicIslandAgentRelay"
        ),
        .executableTarget(
            name: "DynamicIslandCodexHookRelay",
            dependencies: ["AgentBridgeShared", "CodexHookShared"],
            path: "Sources/DynamicIslandCodexHookRelay"
        ),
        .testTarget(
            name: "DynamicIslandTests",
            dependencies: ["DynamicIsland", "AgentBridgeShared", "CodexHookShared"],
            path: "Tests/DynamicIslandTests"
        )
    ]
)
