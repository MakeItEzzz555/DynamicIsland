import XCTest
@testable import DynamicIsland

final class AgentSessionLauncherTests: XCTestCase {
    func testLiveSessionsShowsActiveAndResumableButNotOldTerminalWork() {
        let now = Date(timeIntervalSince1970: 10_000)
        let working = makeSession(
            nativeID: "working",
            state: .working,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/tmp/DynamicIsland",
            now: now
        )
        let resumable = makeSession(
            nativeID: "resume",
            state: .idle,
            availability: .resumable,
            project: "OtherRepo",
            path: "/tmp/OtherRepo",
            now: now.addingTimeInterval(-10)
        )
        let completed = makeSession(
            nativeID: "done",
            state: .completed,
            availability: nil,
            project: "OldRepo",
            path: "/tmp/OldRepo",
            now: now.addingTimeInterval(-20)
        )

        let result = AgentSessionLauncherProjection.liveSessions(
            [completed, resumable, working],
            query: ""
        )

        XCTAssertEqual(result.map { $0.id.sessionID.nativeID }, ["working", "resume"])
    }


    func testRecentCompletedObservedTurnRemainsVisibleLikeAgentNotchSessionWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let recent = makeSession(
            nativeID: "recent-idle-vscode",
            state: .completed,
            availability: nil,
            project: "DynamicIsland",
            path: "/tmp/DynamicIsland",
            now: now.addingTimeInterval(-120)
        )
        let old = makeSession(
            nativeID: "old-idle-vscode",
            state: .completed,
            availability: nil,
            project: "Old",
            path: "/tmp/Old",
            now: now.addingTimeInterval(-301)
        )

        let result = AgentSessionLauncherProjection.liveSessions(
            [old, recent],
            query: "",
            now: now,
            recentObservedWindow: 300
        )

        XCTAssertEqual(result.map { $0.id.sessionID.nativeID }, ["recent-idle-vscode"])
    }


    func testSearchCanRecoverOlderIdleExactThreadOutsideLiveWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let old = makeSession(
            nativeID: "019f22ce-fcd0-73d3-97d1-af70d12d902a",
            state: .completed,
            availability: nil,
            project: "DynamicIsland",
            path: "/tmp/DynamicIsland",
            now: now.addingTimeInterval(-3_600)
        )

        XCTAssertTrue(
            AgentSessionLauncherProjection.liveSessions(
                [old],
                query: "d902a",
                now: now
            ).contains { $0.id.sessionID.nativeID == old.id.sessionID.nativeID }
        )
        XCTAssertTrue(
            AgentSessionLauncherProjection.liveSessions(
                [old],
                query: "DynamicIsland",
                now: now
            ).contains { $0.id.sessionID.nativeID == old.id.sessionID.nativeID }
        )
    }

    func testLiveSessionSearchMatchesSourceModelBranchAndExactNativeID() {
        let now = Date()
        var session = makeSession(
            nativeID: "native-742a",
            state: .working,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/tmp/DynamicIsland",
            now: now
        )
        session.project.gitBranch = "feature/agents-ui"
        session.project.model = "gpt-5.6-sol"
        session.project.sourceApplication = AgentSourceApplication(
            displayName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode"
        )

        XCTAssertEqual(
            AgentSessionLauncherProjection.liveSessions([session], query: "Visual Studio").count,
            1
        )
        XCTAssertEqual(
            AgentSessionLauncherProjection.liveSessions([session], query: "5.6-sol").count,
            1
        )
        XCTAssertEqual(
            AgentSessionLauncherProjection.liveSessions([session], query: "742a").count,
            1
        )
        XCTAssertEqual(
            AgentSessionLauncherProjection.liveSessions([session], query: "nope").count,
            0
        )
    }

    func testRepositoryProjectionUsesOnlyExistingLocalPathsAndDeduplicatesByPath() {
        let now = Date()
        let first = makeSession(
            nativeID: "one",
            state: .working,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now
        )
        var duplicate = first
        duplicate = AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .claude, nativeID: "two"),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .vscode,
            state: .working,
            project: first.project,
            capabilities: AgentCapabilities(),
            usage: AgentUsage(),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: now,
            endedAt: nil,
            lastUpdatedAt: now,
            availability: .loaded
        )
        let missing = makeSession(
            nativeID: "missing",
            state: .working,
            availability: .loaded,
            project: "Missing",
            path: "/repos/Missing",
            now: now
        )

        let result = AgentSessionLauncherProjection.repositories(
            [first, duplicate, missing],
            query: "",
            fileExists: { $0 == "/repos/DynamicIsland" }
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.path, "/repos/DynamicIsland")
        XCTAssertEqual(result.first?.name, "DynamicIsland")
    }

    func testRepositoryProjectionCanonicalizesEquivalentPathsBeforeDeduplication() {
        let now = Date()
        let direct = makeSession(
            nativeID: "direct",
            state: .working,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now
        )
        let equivalent = makeSession(
            nativeID: "equivalent",
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/./DynamicIsland/",
            now: now.addingTimeInterval(-1)
        )

        let result = AgentSessionLauncherProjection.repositories(
            [direct, equivalent],
            query: "",
            fileExists: { $0 == "/repos/DynamicIsland" }
        )

        XCTAssertEqual(result.map(\.path), ["/repos/DynamicIsland"])
    }

    private func makeSession(
        nativeID: String,
        state: AgentState,
        availability: AgentSessionAvailability?,
        project: String,
        path: String,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .codex, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: state,
            project: AgentProjectContext(
                displayName: project,
                workingDirectory: path,
                repositoryIdentity: nil,
                gitBranch: "main",
                gitCommit: nil,
                model: "gpt-5.6-sol",
                sourceApplication: nil
            ),
            capabilities: AgentCapabilities(),
            usage: AgentUsage(),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: now,
            endedAt: nil,
            lastUpdatedAt: now,
            availability: availability
        )
    }
}
