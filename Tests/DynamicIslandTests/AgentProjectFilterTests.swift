import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentProjectFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 80_000)

    private var index: AgentProjectLocationIndex {
        AgentProjectLocationIndex(locations: [
            "/repo": location("/repo", root: "/repo"),
            "/repo/apps/web": location("/repo/apps/web", root: "/repo"),
            "/site": location("/site", root: "/site"),
            "/notes": location("/notes", root: nil)
        ])
    }

    func testOptionsGroupByRepositoryAndListActiveFirst() {
        let sessions = [
            session("old-site", cwd: "/site", state: .idle, age: 600),
            session("web", cwd: "/repo/apps/web", state: .working, age: 5),
            session("claude-root", provider: .claude, cwd: "/repo", state: .idle, age: 30),
            session("notes", cwd: "/notes", state: .idle, age: 100)
        ]

        let options = AgentProjectFilter.options(for: sessions, locations: index)

        XCTAssertEqual(options.map(\.title), ["repo", "Display", "site"])
        XCTAssertEqual(options.map(\.path), ["/repo", "/notes", "/site"])
        XCTAssertEqual(options.first?.sessionCount, 2)
        XCTAssertEqual(options.first?.activeCount, 1)
        XCTAssertEqual(options.first?.providers, [.claude, .codex].sorted { $0.deterministicSortKey < $1.deterministicSortKey })
        XCTAssertEqual(options.first?.path, "/repo")
    }

    func testFilterShowsExactSessionsOfProjectAcrossProviders() {
        let web = session("web", cwd: "/repo/apps/web", state: .working, age: 5)
        let claude = session("claude-root", provider: .claude, cwd: "/repo", state: .idle, age: 30)
        let site = session("site", cwd: "/site", state: .working, age: 1)
        let key = AgentProjectGrouping.key(for: web, locations: index).rawValue

        let filtered = AgentProjectFilter.filter([web, claude, site], projectKey: key, locations: index)

        XCTAssertEqual(Set(filtered.map(\.id)), [web.id, claude.id])
    }

    func testNilOrStaleKeyShowsEverything() {
        let sessions = [session("a", cwd: "/repo", state: .idle, age: 1), session("b", cwd: "/site", state: .idle, age: 1)]
        XCTAssertEqual(AgentProjectFilter.filter(sessions, projectKey: nil, locations: index).count, 2)
        XCTAssertEqual(AgentProjectFilter.filter(sessions, projectKey: "repo:/gone", locations: index).count, 2)
        XCTAssertFalse(AgentProjectFilter.isEffective("repo:/gone", in: sessions, locations: index))
        XCTAssertFalse(AgentProjectFilter.isEffective(nil, in: sessions, locations: index))
    }

    func testResumableNotLoadedCodexSessionStaysInProject() {
        var resumable = session("thread", cwd: "/repo", state: .idle, age: 5_000)
        resumable.availability = .resumable
        let active = session("active", cwd: "/site", state: .working, age: 1)
        let key = AgentProjectGrouping.key(for: resumable, locations: index).rawValue

        XCTAssertEqual(
            AgentProjectFilter.filter([resumable, active], projectKey: key, locations: index).map(\.id),
            [resumable.id]
        )
        XCTAssertTrue(AgentProjectFilter.options(for: [resumable, active], locations: index).contains { $0.id == key })
    }

    func testSelectionInsideProjectIsKeptAndOutsideFallsBackToProjectPreference() {
        let explicit = session("explicit", cwd: "/repo", state: .idle, age: 200)
        let active = session("active", cwd: "/repo/apps/web", state: .working, age: 1)
        let other = session("other", cwd: "/site", state: .working, age: 1)
        let repoSessions = AgentProjectFilter.filter(
            [explicit, active, other],
            projectKey: "repo:/repo",
            locations: index
        )

        XCTAssertEqual(
            AgentSessionLauncherProjection.preferredSelection(
                current: explicit.id, sessions: repoSessions, now: now, locations: index
            ),
            explicit.id,
            "Explicitly selected exact session wins inside its project"
        )
        XCTAssertEqual(
            AgentSessionLauncherProjection.preferredSelection(
                current: other.id, sessions: repoSessions, now: now, locations: index
            ),
            active.id,
            "A selection from another project is replaced by the project's active session"
        )
    }

    func testIncrementalEventsKeepSelectionAndGrouping() {
        var web = session("web", cwd: "/repo/apps/web", state: .working, age: 5)
        let key = AgentProjectGrouping.key(for: web, locations: index)
        web.state = .runningTool
        web.lastUpdatedAt = now
        XCTAssertEqual(AgentProjectGrouping.key(for: web, locations: index), key)
        XCTAssertEqual(
            AgentSessionLauncherProjection.preferredSelection(current: web.id, sessions: [web], now: now),
            web.id
        )
    }

    func testStaleRepositoryIdentityDoesNotStealSessionFromItsCwdRepository() {
        var session = session("x", cwd: "/repo/apps/web", state: .working, age: 1)
        session.project.repositoryIdentity = "someone/else"
        XCTAssertEqual(AgentProjectGrouping.key(for: session, locations: index).rawValue, "repo:/repo")
    }

    func testDisplayLabelShowsPathWithinRepository() {
        XCTAssertEqual(
            AgentProjectFilter.displayLabel(for: session("w", cwd: "/repo/apps/web", state: .idle, age: 1), locations: index),
            "repo/apps/web"
        )
        XCTAssertEqual(
            AgentProjectFilter.displayLabel(for: session("r", cwd: "/repo", state: .idle, age: 1), locations: index),
            "repo"
        )
        XCTAssertEqual(
            AgentProjectFilter.displayLabel(for: session("n", cwd: "/notes", state: .idle, age: 1), locations: index),
            "Display"
        )
    }

    private func location(_ path: String, root: String?) -> AgentProjectLocation {
        AgentProjectLocation(
            reportedPath: path,
            normalizedPath: path,
            canonicalPath: path,
            repositoryRoot: root,
            repositoryKind: root == nil ? nil : .checkout,
            status: root == nil ? .directory : .repository
        )
    }

    private func session(
        _ nativeID: String,
        provider: AgentProvider = .codex,
        cwd: String,
        state: AgentState,
        age: TimeInterval
    ) -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: provider, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: state,
            project: AgentProjectContext(displayName: "Display", workingDirectory: cwd),
            capabilities: AgentCapabilities(),
            usage: AgentUsage(),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: now.addingTimeInterval(-age),
            endedAt: nil,
            lastUpdatedAt: now.addingTimeInterval(-age),
            availability: .loaded
        )
    }
}
