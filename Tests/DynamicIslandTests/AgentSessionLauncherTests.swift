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
            AgentSessionLauncherProjection.liveSessions([session], query: "/tmp/DynamicIsland").count,
            1
        )
        XCTAssertEqual(
            AgentSessionLauncherProjection.liveSessions([session], query: "nope").count,
            0
        )
    }

    func testFiveResumableThreadsForSameRepositoryShowOnlyNewestExactSession() {
        let now = Date(timeIntervalSince1970: 20_000)
        let sessions = (0..<5).map { index in
            makeSession(
                nativeID: "resume-\(index)",
                state: .idle,
                availability: .resumable,
                project: "DynamicIsland",
                path: "/repos/DynamicIsland",
                now: now.addingTimeInterval(TimeInterval(index))
            )
        }

        let visible = AgentSessionLauncherProjection.liveSessions(sessions, query: "")

        XCTAssertEqual(visible.map { $0.id.sessionID.nativeID }, ["resume-4"])
        XCTAssertEqual(Set(sessions.map { $0.id.sessionID.nativeID }).count, 5)
    }

    func testSimultaneousActiveSessionsForSameRepositoryRemainDistinct() {
        let now = Date()
        let first = makeSession(
            nativeID: "active-one",
            state: .working,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now
        )
        let second = makeSession(
            nativeID: "active-two",
            state: .runningCommand,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now.addingTimeInterval(-1)
        )

        let visible = AgentSessionLauncherProjection.liveSessions([second, first], query: "")

        XCTAssertEqual(
            Set(visible.map { $0.id.sessionID.nativeID }),
            Set(["active-one", "active-two"])
        )
    }

    func testActiveSessionHidesSameRepositoryResumableRepresentative() {
        let now = Date()
        let active = makeSession(
            nativeID: "active",
            state: .thinking,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now.addingTimeInterval(-5)
        )
        let resumable = makeSession(
            nativeID: "newer-resumable",
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now
        )

        let visible = AgentSessionLauncherProjection.liveSessions([resumable, active], query: "")

        XCTAssertEqual(visible.map { $0.id.sessionID.nativeID }, ["active"])
    }

    func testHistoricalRepresentativeUsesTimestampThenGenerationAndProvenance() {
        let now = Date()
        var weaker = makeSession(
            nativeID: "weaker",
            generation: 1,
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now
        )
        weaker.sourceAuthority = .processObservation
        var stronger = makeSession(
            nativeID: "stronger",
            generation: 2,
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now
        )
        stronger.sourceAuthority = .lifecycle
        let newest = makeSession(
            nativeID: "newest",
            generation: 1,
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now.addingTimeInterval(1)
        )

        XCTAssertEqual(
            AgentSessionLauncherProjection.liveSessions([weaker, stronger], query: "")
                .first?.id.sessionID.nativeID,
            "stronger"
        )
        XCTAssertEqual(
            AgentSessionLauncherProjection.liveSessions([stronger, newest], query: "")
                .first?.id.sessionID.nativeID,
            "newest"
        )
    }


    func testHistoricalSameRepositoryAcrossProvidersCollapsesToNewestRepresentative() {
        let now = Date()
        let codex = makeSession(
            nativeID: "codex-old",
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now.addingTimeInterval(-20)
        )
        var claude = makeSession(
            nativeID: "claude-new",
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now
        )
        claude = AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .claude, nativeID: "claude-new"),
                generation: claude.id.generation
            ),
            source: claude.source,
            state: claude.state,
            project: claude.project,
            capabilities: claude.capabilities,
            usage: claude.usage,
            tools: claude.tools,
            commands: claude.commands,
            approvals: claude.approvals,
            subagents: claude.subagents,
            recentActivity: claude.recentActivity,
            startedAt: claude.startedAt,
            endedAt: claude.endedAt,
            lastUpdatedAt: claude.lastUpdatedAt,
            availability: claude.availability,
            sourceAuthority: claude.sourceAuthority
        )

        let visible = AgentSessionLauncherProjection.liveSessions([codex, claude], query: "")

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.id.sessionID.nativeID, "claude-new")
    }

    func testSearchReturnsLatestVisibleRepositoryRepresentative() {
        let now = Date()
        let old = makeSession(
            nativeID: "old-thread",
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now.addingTimeInterval(-100)
        )
        let latest = makeSession(
            nativeID: "latest-thread",
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now
        )

        let visible = AgentSessionLauncherProjection.liveSessions(
            [old, latest],
            query: "DynamicIsland"
        )

        XCTAssertEqual(visible.map { $0.id.sessionID.nativeID }, ["latest-thread"])
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

    func testRepositoryProjectionDeduplicatesNestedWorkingDirectoriesAtRepositoryRoot() {
        let now = Date()
        let nested = makeSession(
            nativeID: "nested",
            state: .working,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland/Sources/DynamicIsland",
            now: now
        )
        let root = makeSession(
            nativeID: "root",
            state: .idle,
            availability: .resumable,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland",
            now: now.addingTimeInterval(-1)
        )

        let result = AgentSessionLauncherProjection.repositories(
            [root, nested],
            query: "",
            fileExists: { $0.hasPrefix("/repos/DynamicIsland") },
            repositoryRoot: { _ in "/repos/DynamicIsland" }
        )

        XCTAssertEqual(result.map(\.path), ["/repos/DynamicIsland"])
    }

    func testRepositoryProjectionPrefersNewestSessionMetadataForSharedRepository() {
        let now = Date()
        let older = makeSession(
            nativeID: "older",
            state: .idle,
            availability: .resumable,
            project: "Old display",
            path: "/repos/DynamicIsland",
            now: now.addingTimeInterval(-20)
        )
        let newer = makeSession(
            nativeID: "newer",
            state: .working,
            availability: .loaded,
            project: "DynamicIsland",
            path: "/repos/DynamicIsland/Sources",
            now: now
        )

        let result = AgentSessionLauncherProjection.repositories(
            [older, newer],
            query: "",
            fileExists: { _ in true },
            repositoryRoot: { _ in "/repos/DynamicIsland" }
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "DynamicIsland")
        XCTAssertEqual(result.first?.branch, "main")
    }

    func testRepositoryProjectionFindsRealGitRootFromNestedWorkingDirectory() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("DynamicIslandLauncherTests-(UUID().uuidString)")
        let repository = temporaryRoot.appendingPathComponent("DynamicIsland")
        let nested = repository.appendingPathComponent("Sources/DynamicIsland")
        try fileManager.createDirectory(
            at: repository.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let session = makeSession(
            nativeID: "nested-real-repo",
            state: .working,
            availability: .loaded,
            project: "DynamicIsland",
            path: nested.path,
            now: Date()
        )

        let result = AgentSessionLauncherProjection.repositories([session], query: "")

        XCTAssertEqual(result.map(\.path), [repository.path])
    }

    private func makeSession(
        nativeID: String,
        generation: UInt64 = 1,
        state: AgentState,
        availability: AgentSessionAvailability?,
        project: String,
        path: String,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .codex, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: generation)
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
