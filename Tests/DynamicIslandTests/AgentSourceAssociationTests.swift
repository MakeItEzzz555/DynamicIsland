import XCTest
@testable import DynamicIsland

final class AgentSourceAssociationTests: XCTestCase {
    func testRequiresBothVerifiedIdentityAndOpenCapability() {
        let onlyIdentity = session(
            source: .terminal,
            bundleID: "com.apple.Terminal",
            capabilities: [.verifiedSourceIdentity]
        )
        XCTAssertNil(AgentSourceAssociationResolver.openTarget(for: onlyIdentity))

        let onlyOpen = session(
            source: .terminal,
            bundleID: "com.apple.Terminal",
            capabilities: [.sourceAppOpen]
        )
        XCTAssertNil(AgentSourceAssociationResolver.openTarget(for: onlyOpen))
    }

    func testTerminalAssociationAcceptsOnlyKnownTerminalBundle() {
        let terminal = session(
            source: .terminal,
            bundleID: "com.apple.Terminal",
            capabilities: [.verifiedSourceIdentity, .sourceAppOpen]
        )
        XCTAssertEqual(
            AgentSourceAssociationResolver.openTarget(for: terminal),
            AgentSourceOpenTarget(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        )

        let mismatch = session(
            source: .terminal,
            bundleID: "com.openai.codex",
            capabilities: [.verifiedSourceIdentity, .sourceAppOpen]
        )
        XCTAssertNil(AgentSourceAssociationResolver.openTarget(for: mismatch))
    }

    func testVSCodeSourceSupportsVSCodeAndCursor() {
        for bundleID in ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "co.anysphere.cursor.nightly"] {
            let value = session(
                source: .vscode,
                bundleID: bundleID,
                capabilities: [.verifiedSourceIdentity, .sourceAppOpen]
            )
            XCTAssertEqual(AgentSourceAssociationResolver.openTarget(for: value)?.bundleIdentifier, bundleID)
        }
    }

    func testJetBrainsRequiresVerifiedJetBrainsBundlePrefix() {
        let rider = session(
            source: .jetbrains,
            bundleID: "com.jetbrains.rider",
            capabilities: [.verifiedSourceIdentity, .sourceAppOpen],
            appName: "Rider"
        )
        XCTAssertEqual(
            AgentSourceAssociationResolver.openTarget(for: rider),
            AgentSourceOpenTarget(displayName: "Rider", bundleIdentifier: "com.jetbrains.rider")
        )

        let spoof = session(
            source: .jetbrains,
            bundleID: "com.example.rider",
            capabilities: [.verifiedSourceIdentity, .sourceAppOpen]
        )
        XCTAssertNil(AgentSourceAssociationResolver.openTarget(for: spoof))
    }

    func testDesktopAgentAssociationIsAllowlisted() {
        for bundleID in ["com.openai.codex", "com.anthropic.claudefordesktop"] {
            let value = session(
                source: .desktopApp,
                bundleID: bundleID,
                capabilities: [.verifiedSourceIdentity, .sourceAppOpen]
            )
            XCTAssertEqual(AgentSourceAssociationResolver.openTarget(for: value)?.bundleIdentifier, bundleID)
        }
    }

    func testUnknownAndCloudNeverProduceOpenAction() {
        for source in [AgentSource.unknown, .cloud] {
            let value = session(
                source: source,
                bundleID: "com.openai.codex",
                capabilities: [.verifiedSourceIdentity, .sourceAppOpen]
            )
            XCTAssertNil(AgentSourceAssociationResolver.openTarget(for: value))
        }
    }

    func testSameProjectDoesNotCreateOrMergeSourceIdentity() {
        let unverified = session(
            source: .terminal,
            bundleID: "com.apple.Terminal",
            capabilities: [],
            projectName: "DynamicIsland"
        )
        let verified = session(
            source: .vscode,
            bundleID: "com.microsoft.VSCode",
            capabilities: [.verifiedSourceIdentity, .sourceAppOpen],
            projectName: "DynamicIsland"
        )
        XCTAssertNil(AgentSourceAssociationResolver.openTarget(for: unverified))
        XCTAssertEqual(
            AgentSourceAssociationResolver.openTarget(for: verified)?.bundleIdentifier,
            "com.microsoft.VSCode"
        )
    }

    private func session(
        source: AgentSource,
        bundleID: String?,
        capabilities: Set<AgentCapability>,
        appName: String = "Source App",
        projectName: String = "Project"
    ) -> AgentSession {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        return AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .codex, nativeID: UUID().uuidString),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: source,
            state: .working,
            project: AgentProjectContext(
                displayName: projectName,
                sourceApplication: AgentSourceApplication(
                    displayName: appName,
                    bundleIdentifier: bundleID
                )
            ),
            capabilities: AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: capabilities.map {
                ($0, AgentCapabilityEvidence(authority: .lifecycle, source: "verified-test", observedAt: now))
            })),
            usage: AgentUsage(),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: now,
            endedAt: nil,
            lastUpdatedAt: now
        )
    }
}
