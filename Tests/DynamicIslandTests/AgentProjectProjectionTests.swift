import Combine
import Foundation
import XCTest
@testable import DynamicIsland

private final class CountingFileSystem: AgentProjectFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: AgentProjectFileType]
    private var symlinks: [String: String]
    private var _calls = 0

    init(entries: [String: AgentProjectFileType], symlinks: [String: String] = [:]) {
        self.entries = entries
        self.symlinks = symlinks
    }

    var calls: Int { lock.withLock { _calls } }

    func fileType(atPath path: String) -> AgentProjectFileType {
        lock.withLock {
            _calls += 1
            return entries[path] ?? .missing
        }
    }

    func resolvingSymlinks(_ path: String) -> String {
        lock.withLock { symlinks[path] ?? path }
    }
}

final class AgentProjectResolverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentProjectResolverTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testNormalizeIsStringOnly() {
        XCTAssertEqual(AgentProjectResolver.normalize("/repo/./apps/../apps/web/"), "/repo/apps/web")
        XCTAssertEqual(AgentProjectResolver.normalize("  /repo  "), "/repo")
        XCTAssertNil(AgentProjectResolver.normalize("relative/path"))
        XCTAssertNil(AgentProjectResolver.normalize("   "))
        XCTAssertNil(AgentProjectResolver.normalize(nil))
        XCTAssertEqual(AgentProjectResolver.normalize("~"), NSHomeDirectory())
    }

    func testRepositoryRootItself() throws {
        let repo = try makeRepo("repo")
        let location = try XCTUnwrap(AgentProjectResolver.resolve(repo.path))
        XCTAssertEqual(location.status, .repository)
        XCTAssertEqual(location.repositoryRoot, repo.path)
        XCTAssertEqual(location.repositoryKind, .checkout)
        XCTAssertNil(location.pathWithinRepository)
    }

    func testChildDirectoryKeepsWorkingDirectoryDistinctFromRoot() throws {
        let repo = try makeRepo("mono")
        let app = try makeDirectory("mono/apps/frontend")
        let location = try XCTUnwrap(AgentProjectResolver.resolve(app.path))

        XCTAssertEqual(location.canonicalPath, app.path)
        XCTAssertEqual(location.repositoryRoot, repo.path)
        XCTAssertEqual(location.directoryName, "frontend")
        XCTAssertEqual(location.repositoryName, "mono")
        XCTAssertEqual(location.pathWithinRepository, "apps/frontend")
    }

    func testNestedRepositoryUsesNearestRoot() throws {
        _ = try makeRepo("outer")
        let inner = try makeRepo("outer/vendor/inner")
        let deep = try makeDirectory("outer/vendor/inner/src")
        let location = try XCTUnwrap(AgentProjectResolver.resolve(deep.path))
        XCTAssertEqual(location.repositoryRoot, inner.path)
    }

    func testLinkedWorktreeIsRecognizedByGitFile() throws {
        let worktree = try makeDirectory("worktrees/feature")
        try Data("gitdir: /elsewhere/.git/worktrees/feature\n".utf8)
            .write(to: worktree.appendingPathComponent(".git"))
        let location = try XCTUnwrap(AgentProjectResolver.resolve(worktree.path))
        XCTAssertEqual(location.repositoryRoot, worktree.path)
        XCTAssertEqual(location.repositoryKind, .linkedCheckout)
    }

    func testNonGitDirectory() throws {
        let plain = try makeDirectory("notes")
        let location = try XCTUnwrap(AgentProjectResolver.resolve(plain.path))
        XCTAssertEqual(location.status, .directory)
        XCTAssertNil(location.repositoryRoot)
    }

    func testSymlinkResolvesToRealRepositoryButKeepsReportedPath() throws {
        let repo = try makeRepo("real")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)

        let location = try XCTUnwrap(AgentProjectResolver.resolve(link.path))
        XCTAssertEqual(location.reportedPath, link.path)
        XCTAssertEqual(location.normalizedPath, link.path)
        XCTAssertEqual(location.canonicalPath, repo.path)
        XCTAssertEqual(location.repositoryRoot, repo.path)
    }

    func testMissingDirectoryIsReportedNotInvented() throws {
        let missing = root.appendingPathComponent("gone/away").path
        let location = try XCTUnwrap(AgentProjectResolver.resolve(missing))
        XCTAssertEqual(location.status, .missing)
        XCTAssertEqual(location.canonicalPath, missing)
        XCTAssertNil(location.repositoryRoot)
    }

    func testFakeFileSystemCoversFileProviderStylePaths() {
        let cloud = "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/proj"
        let fileSystem = CountingFileSystem(entries: [
            cloud: .directory,
            cloud + "/.git": .directory
        ])
        let location = AgentProjectResolver.resolve(cloud, fileSystem: fileSystem)
        XCTAssertEqual(location?.repositoryRoot, cloud)
    }

    func testAncestorWalkIsBounded() {
        let deep = "/" + (0..<200).map { "d\($0)" }.joined(separator: "/")
        let fileSystem = CountingFileSystem(entries: [deep: .directory])
        let location = AgentProjectResolver.resolve(deep, fileSystem: fileSystem)
        XCTAssertEqual(location?.status, .directory)
        XCTAssertLessThanOrEqual(fileSystem.calls, AgentProjectResolver.maximumAncestorDepth + 1)
    }

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRepo(_ relative: String) throws -> URL {
        let url = try makeDirectory(relative)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        return url
    }
}

@MainActor
final class AgentProjectGroupingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 50_000)

    func testSessionsInSameRepositoryWithDifferentCwdGroupTogetherButKeepCwd() {
        let index = AgentProjectLocationIndex(locations: [
            "/repo/apps/web": location("/repo/apps/web", root: "/repo"),
            "/repo/apps/api": location("/repo/apps/api", root: "/repo")
        ])
        let web = session("web", cwd: "/repo/apps/web")
        let api = session("api", provider: .claude, cwd: "/repo/apps/api")

        let webKey = AgentProjectGrouping.key(for: web, locations: index)
        let apiKey = AgentProjectGrouping.key(for: api, locations: index)

        XCTAssertEqual(webKey, apiKey)
        XCTAssertEqual(webKey.title, "repo")
        XCTAssertEqual(web.project.workingDirectory, "/repo/apps/web")
        XCTAssertEqual(api.project.workingDirectory, "/repo/apps/api")
    }

    func testSameCwdFromMultipleProvidersSharesGroupButNotIdentity() {
        let index = AgentProjectLocationIndex(locations: [
            "/proj": location("/proj", root: nil)
        ])
        let codex = session("x", provider: .codex, cwd: "/proj")
        let claude = session("x", provider: .claude, cwd: "/proj")

        XCTAssertEqual(
            AgentProjectGrouping.key(for: codex, locations: index),
            AgentProjectGrouping.key(for: claude, locations: index)
        )
        XCTAssertNotEqual(codex.id, claude.id)
    }

    func testNestedRepositoriesDoNotMerge() {
        let index = AgentProjectLocationIndex(locations: [
            "/outer/src": location("/outer/src", root: "/outer"),
            "/outer/vendor/inner": location("/outer/vendor/inner", root: "/outer/vendor/inner")
        ])
        XCTAssertNotEqual(
            AgentProjectGrouping.key(for: session("a", cwd: "/outer/src"), locations: index),
            AgentProjectGrouping.key(for: session("b", cwd: "/outer/vendor/inner"), locations: index)
        )
    }

    func testMissingDirectoryKeepsItsOwnCwdGroup() {
        let index = AgentProjectLocationIndex(locations: [
            "/old/place": AgentProjectLocation(
                reportedPath: "/old/place",
                normalizedPath: "/old/place",
                canonicalPath: "/old/place",
                repositoryRoot: nil,
                repositoryKind: nil,
                status: .missing
            )
        ])
        let key = AgentProjectGrouping.key(for: session("a", cwd: "/old/place"), locations: index)
        XCTAssertEqual(key.rawValue, "path:/old/place")
    }

    func testUnresolvedPathFallsBackToNormalizedCwdWithoutFilesystem() {
        let key = AgentProjectGrouping.key(for: session("a", cwd: "/repo/./apps/web/"), locations: .empty)
        XCTAssertEqual(key.rawValue, "path:/repo/apps/web")
    }

    func testProviderRepositoryIdentityUsedWhenNoLocalRoot() {
        var claude = session("a", provider: .claude, cwd: nil)
        claude.project.repositoryIdentity = "Org/Repo"
        XCTAssertEqual(AgentProjectGrouping.key(for: claude, locations: .empty).rawValue, "repository:org/repo")
    }

    func testNoEvidenceFallbacks() {
        var bare = session("a", provider: .claude, cwd: nil)
        bare.project.displayName = nil
        XCTAssertEqual(
            AgentProjectGrouping.key(for: bare, locations: .empty, fallback: .perSession).rawValue,
            "session:\(AgentProvider.claude.deterministicSortKey):a"
        )
        XCTAssertEqual(
            AgentProjectGrouping.key(for: bare, locations: .empty, fallback: .perProvider).title,
            "Claude sessions"
        )
    }

    func testLauncherGroupingUsesCachedRootsForCurrentSessionSelection() {
        let index = AgentProjectLocationIndex(locations: [
            "/repo/apps/web": location("/repo/apps/web", root: "/repo"),
            "/repo": location("/repo", root: "/repo")
        ])
        var active = session("active", cwd: "/repo/apps/web")
        active.state = .working
        var resumable = session("resumable", cwd: "/repo")
        resumable.state = .idle
        resumable.availability = .resumable
        resumable.lastUpdatedAt = now.addingTimeInterval(-3_000)

        let withIndex = AgentSessionLauncherProjection.projectSummaries(
            [active, resumable], now: now, locations: index
        )
        XCTAssertEqual(withIndex.count, 1)
        XCTAssertEqual(withIndex.first?.current?.id, active.id)
        XCTAssertEqual(withIndex.first?.latestResumable?.id, resumable.id)

        let withoutIndex = AgentSessionLauncherProjection.projectSummaries(
            [active, resumable], now: now, locations: .empty
        )
        XCTAssertEqual(withoutIndex.count, 2, "Without cached roots, distinct cwds stay distinct")
    }

    func testLauncherProjectionNeverWalksTheFilesystem() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentProjectGroupingTests-\(UUID().uuidString)")
        let nested = tempRoot.appendingPathComponent("repo/Sources")
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("repo/.git"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let identity = AgentSessionLauncherProjection.projectIdentity(session("a", cwd: nested.path))
        XCTAssertEqual(identity, "path:\(AgentProjectResolver.normalize(nested.path)!.lowercased())")
    }

    func testResumableNotLoadedSessionRemainsDiscoverableUnderProject() {
        let index = AgentProjectLocationIndex(locations: ["/repo": location("/repo", root: "/repo")])
        var resumable = session("thread", cwd: "/repo")
        resumable.state = .idle
        resumable.availability = .resumable
        let live = AgentSessionLauncherProjection.liveSessions(
            [resumable], query: "", now: now, locations: index
        )
        XCTAssertEqual(live.map(\.id), [resumable.id])
    }

    // MARK: Helpers

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
        cwd: String?
    ) -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: provider, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: .working,
            project: AgentProjectContext(displayName: "Display", workingDirectory: cwd),
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

@MainActor
final class AgentProjectProjectionStoreTests: XCTestCase {
    func testResolvesInBackgroundAndCachesByPathSet() async {
        let fileSystem = CountingFileSystem(entries: [
            "/repo": .directory,
            "/repo/.git": .directory,
            "/repo/app": .directory
        ])
        let store = AgentProjectProjectionStore(fileSystem: fileSystem, now: { Date(timeIntervalSince1970: 7) })

        store.update(workingDirectories: ["/repo/app"])
        await store.waitForIdle()

        XCTAssertEqual(store.index.location(for: "/repo/app")?.repositoryRoot, "/repo")
        XCTAssertEqual(store.status, .idle)
        XCTAssertEqual(store.lastRefreshAt, Date(timeIntervalSince1970: 7))

        let callsAfterFirst = fileSystem.calls
        store.update(workingDirectories: ["/repo/app"])
        await store.waitForIdle()
        XCTAssertEqual(fileSystem.calls, callsAfterFirst, "Unchanged paths must not re-resolve")

        store.refresh()
        await store.waitForIdle()
        XCTAssertGreaterThan(fileSystem.calls, callsAfterFirst, "Explicit refresh re-resolves")
    }

    func testDropsLocationsNoLongerReferenced() async {
        let fileSystem = CountingFileSystem(entries: ["/a": .directory, "/b": .directory])
        let store = AgentProjectProjectionStore(fileSystem: fileSystem)
        store.update(workingDirectories: ["/a", "/b"])
        await store.waitForIdle()
        store.update(workingDirectories: ["/b"])
        XCTAssertNil(store.index.location(for: "/a"))
        XCTAssertNotNil(store.index.location(for: "/b"))
    }

    func testObservingSessionsIgnoresActivityOnlyChanges() async throws {
        let fileSystem = CountingFileSystem(entries: ["/repo": .directory, "/repo/.git": .directory])
        let store = AgentProjectProjectionStore(fileSystem: fileSystem)
        let subject = PassthroughSubject<[AgentSession], Never>()
        store.observe(subject)

        var session = AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .codex, nativeID: "t"),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: .working,
            project: AgentProjectContext(workingDirectory: "/repo"),
            capabilities: AgentCapabilities(),
            usage: AgentUsage(),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: .distantPast,
            endedAt: nil,
            lastUpdatedAt: .distantPast
        )
        subject.send([session])
        for _ in 0..<100 where store.index.location(for: "/repo") == nil {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        await store.waitForIdle()
        let calls = fileSystem.calls
        XCTAssertEqual(store.index.location(for: "/repo")?.repositoryRoot, "/repo")

        session.state = .idle
        session.lastUpdatedAt = Date()
        subject.send([session])
        try await Task.sleep(nanoseconds: 20_000_000)
        await store.waitForIdle()
        XCTAssertEqual(fileSystem.calls, calls)
    }
}
