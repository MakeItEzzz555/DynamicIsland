import Foundation
import XCTest
@testable import DynamicIsland

final class AgentDiagnosticsReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 200_000)

    func testProviderRowsAreProviderScopedAndAlwaysListCodexAndClaude() {
        let report = makeReport(sessions: [session("secret-native-id-123", provider: .claude, cwd: "/Users/me/repo/app")])

        XCTAssertEqual(report.providers.map(\.provider), [AgentProvider.claude, .codex].sorted { $0.deterministicSortKey < $1.deterministicSortKey })
        let claude = report.providers.first { $0.provider == .claude }!
        XCTAssertTrue(claude.detected)
        XCTAssertEqual(claude.observedSessionCount, 1)
        XCTAssertFalse(claude.managedControlAvailable)
        XCTAssertEqual(claude.usage.first?.authority, .unavailable)

        let codex = report.providers.first { $0.provider == .codex }!
        XCTAssertTrue(codex.managedControlAvailable)
        XCTAssertEqual(codex.observedSessionCount, 0)
    }

    func testPlainTextNeverContainsSessionIDsTitlesOrTranscript() {
        var session = session("secret-native-id-123", provider: .claude, cwd: "/Users/me/repo/app")
        session.project.displayName = "Private Title"
        session.recentActivity = []
        let text = makeReport(sessions: [session]).plainText()

        XCTAssertFalse(text.contains("secret-native-id-123"))
        XCTAssertFalse(text.contains("Private Title"))
        XCTAssertTrue(text.contains("~/repo/app"))
        XCTAssertFalse(text.contains("/Users/me/"))
    }

    func testProjectRowsDistinguishCwdRootAndResolution() {
        let index = AgentProjectLocationIndex(locations: [
            "/Users/me/repo/app": AgentProjectLocation(
                reportedPath: "/Users/me/repo/app",
                normalizedPath: "/Users/me/repo/app",
                canonicalPath: "/Volumes/Data/repo/app",
                repositoryRoot: "/Volumes/Data/repo",
                repositoryKind: .checkout,
                status: .repository
            )
        ])
        let report = makeReport(
            sessions: [
                session("a", provider: .codex, cwd: "/Users/me/repo/app"),
                session("b", provider: .claude, cwd: "/Users/me/repo/app"),
                session("c", provider: .codex, cwd: "/Users/me/unresolved")
            ],
            locations: index
        )

        let resolved = report.projects.first { $0.displayedDirectory == "~/repo/app" }!
        XCTAssertEqual(resolved.canonicalPath, "/Volumes/Data/repo/app")
        XCTAssertEqual(resolved.repositoryRoot, "/Volumes/Data/repo")
        XCTAssertEqual(resolved.status, .repository)
        XCTAssertEqual(resolved.sessionCount, 2)

        let unresolved = report.projects.first { $0.displayedDirectory == "~/unresolved" }!
        XCTAssertNil(unresolved.status)
        XCTAssertTrue(report.plainText().contains("status: unresolved"))
    }

    func testProjectRowsAreBounded() {
        let sessions = (0..<30).map { session("s\($0)", provider: .codex, cwd: "/p/\($0)") }
        XCTAssertEqual(makeReport(sessions: sessions).projects.count, AgentDiagnosticsReport.maximumProjectRows)
    }

    func testAbbreviation() {
        XCTAssertEqual(AgentDiagnosticsReport.abbreviate("/Users/me", home: "/Users/me"), "~")
        XCTAssertEqual(AgentDiagnosticsReport.abbreviate("/Users/me/x", home: "/Users/me"), "~/x")
        XCTAssertEqual(AgentDiagnosticsReport.abbreviate("/Users/meme/x", home: "/Users/me"), "/Users/meme/x")
    }

    private func makeReport(
        sessions: [AgentSession],
        locations: AgentProjectLocationIndex = .empty
    ) -> AgentDiagnosticsReport {
        AgentDiagnosticsReport.make(
            sessions: sessions,
            managedProviders: [.codex],
            accountUsageByProvider: [:],
            selectedSessionIDs: [:],
            transportErrors: [:],
            locations: locations,
            projectionResolving: false,
            lastProjectionRefreshAt: nil,
            now: now,
            homeDirectory: "/Users/me"
        )
    }

    private func session(_ nativeID: String, provider: AgentProvider, cwd: String) -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: provider, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: .working,
            project: AgentProjectContext(displayName: "d", workingDirectory: cwd),
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
    }
}
