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
        .executable(name: "DynamicIslandCodexHookRelay", targets: ["DynamicIslandCodexHookRelay"]),
        .executable(name: "DynamicIslandClaudeHookRelay", targets: ["DynamicIslandClaudeHookRelay"])
    ],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")],
    targets: [
        .target(name: "LibrariesNative", path: "Sources/LibrariesNative", resources: [.copy("LICENSE.txt"), .copy("BorderBeam/Resources"), .copy("MetalFx/MetalResources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "AgentBridgeShared",
            path: "Sources/AgentBridgeShared"
        ),
        .executableTarget(
            name: "DynamicIsland",
            dependencies: ["AgentBridgeShared", "LibrariesNative", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/DynamicIsland",
            resources: [
                .process("Assets.xcassets"), .copy("ThirdPartyNotices")
            ]
        ),
        .target(
            name: "CodexHookShared",
            dependencies: ["AgentBridgeShared"],
            path: "Sources/CodexHookShared"
        ),
        .target(
            name: "ClaudeHookShared",
            dependencies: ["AgentBridgeShared"],
            path: "Sources/ClaudeHookShared"
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
        .executableTarget(
            name: "DynamicIslandClaudeHookRelay",
            dependencies: ["AgentBridgeShared", "ClaudeHookShared"],
            path: "Sources/DynamicIslandClaudeHookRelay"
        ),
        .testTarget(
            name: "DynamicIslandTests",
            dependencies: ["DynamicIsland", "LibrariesNative", "AgentBridgeShared", "CodexHookShared", "ClaudeHookShared"],
            path: "Tests/DynamicIslandTests",
            exclude: ["ReferenceVectors"]
        )
    ]
)
