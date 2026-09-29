import Combine
import Foundation
import SwiftUI

/// Filesystem facts about one session working directory.
///
/// These are metadata only. Session identity stays
/// `(provider, native session ID, generation)`; a repository root never
/// replaces the working directory the provider reported.
struct AgentProjectLocation: Equatable, Sendable {
    enum Status: String, Equatable, Sendable {
        /// Directory exists and is inside a Git checkout.
        case repository
        /// Directory exists but no enclosing `.git` was found.
        case directory
        /// Directory no longer exists (moved, deleted, unmounted).
        case missing
    }

    enum RepositoryKind: String, Equatable, Sendable {
        /// `.git` is a directory: a normal checkout (possibly nested).
        case checkout
        /// `.git` is a file: a linked worktree or submodule checkout.
        case linkedCheckout
    }

    /// Path as reported by the provider, trimmed.
    let reportedPath: String
    /// Tilde-expanded and standardized, without touching the filesystem.
    let normalizedPath: String
    /// Symlinks resolved when the directory exists; otherwise `normalizedPath`.
    let canonicalPath: String
    /// Nearest enclosing checkout root (nearest wins for nested repositories).
    let repositoryRoot: String?
    let repositoryKind: RepositoryKind?
    let status: Status

    var repositoryName: String? {
        repositoryRoot.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// Last path component of the working directory itself, e.g. `frontend`
    /// for `/repo/apps/frontend`.
    var directoryName: String {
        URL(fileURLWithPath: canonicalPath).lastPathComponent
    }

    /// Working directory relative to the repository root, if inside one and
    /// not equal to it (e.g. `apps/frontend`).
    var pathWithinRepository: String? {
        guard let repositoryRoot, canonicalPath != repositoryRoot else { return nil }
        let prefix = repositoryRoot.hasSuffix("/") ? repositoryRoot : repositoryRoot + "/"
        guard canonicalPath.hasPrefix(prefix) else { return nil }
        return String(canonicalPath.dropFirst(prefix.count))
    }
}

enum AgentProjectFileType: Equatable, Sendable {
    case missing
    case directory
    case file
}

protocol AgentProjectFileSystem: Sendable {
    func fileType(atPath path: String) -> AgentProjectFileType
    func resolvingSymlinks(_ path: String) -> String
}

struct SystemAgentProjectFileSystem: AgentProjectFileSystem {
    func fileType(atPath path: String) -> AgentProjectFileType {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .missing
        }
        return isDirectory.boolValue ? .directory : .file
    }

    func resolvingSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().path
    }
}

/// Pure resolution. Must only run off the main actor (see
/// `AgentProjectProjectionStore`) or from explicit user actions.
enum AgentProjectResolver {
    static let maximumAncestorDepth = 64

    /// String-only normalization; safe on any thread and in view code.
    static func normalize(_ rawPath: String?) -> String? {
        guard let trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        return standardized.count > 1 && standardized.hasSuffix("/")
            ? String(standardized.dropLast())
            : standardized
    }

    static func resolve(
        _ rawPath: String,
        fileSystem: AgentProjectFileSystem = SystemAgentProjectFileSystem()
    ) -> AgentProjectLocation? {
        let reported = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = normalize(reported) else { return nil }

        guard fileSystem.fileType(atPath: normalized) == .directory else {
            return AgentProjectLocation(
                reportedPath: reported,
                normalizedPath: normalized,
                canonicalPath: normalized,
                repositoryRoot: nil,
                repositoryKind: nil,
                status: .missing
            )
        }

        let canonical = normalize(fileSystem.resolvingSymlinks(normalized)) ?? normalized
        var candidate = canonical
        for _ in 0..<maximumAncestorDepth {
            let marker = (candidate as NSString).appendingPathComponent(".git")
            switch fileSystem.fileType(atPath: marker) {
            case .directory:
                return AgentProjectLocation(
                    reportedPath: reported,
                    normalizedPath: normalized,
                    canonicalPath: canonical,
                    repositoryRoot: candidate,
                    repositoryKind: .checkout,
                    status: .repository
                )
            case .file:
                return AgentProjectLocation(
                    reportedPath: reported,
                    normalizedPath: normalized,
                    canonicalPath: canonical,
                    repositoryRoot: candidate,
                    repositoryKind: .linkedCheckout,
                    status: .repository
                )
            case .missing:
                break
            }
            let parent = (candidate as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != candidate else { break }
            candidate = parent
        }

        return AgentProjectLocation(
            reportedPath: reported,
            normalizedPath: normalized,
            canonicalPath: canonical,
            repositoryRoot: nil,
            repositoryKind: nil,
            status: .directory
        )
    }
}

/// Immutable lookup handed to presentation code. Lookups are dictionary
/// reads keyed by the string-normalized working directory.
struct AgentProjectLocationIndex: Equatable, Sendable {
    static let empty = AgentProjectLocationIndex(locations: [:])

    let locations: [String: AgentProjectLocation]

    func location(for rawPath: String?) -> AgentProjectLocation? {
        guard let normalized = AgentProjectResolver.normalize(rawPath) else { return nil }
        return locations[normalized]
    }
}

/// Grouping key for "which project/repository does this session belong to".
/// Grouping never merges or rewrites sessions; it only buckets them.
struct AgentProjectGroupKey: Hashable, Sendable {
    let rawValue: String
    let title: String
}

enum AgentProjectGrouping {
    enum Fallback {
        /// Sessions without project evidence stay distinct.
        case perSession
        /// Sessions without project evidence share a per-provider bucket.
        case perProvider
    }

    static func key(
        for session: AgentSession,
        locations: AgentProjectLocationIndex,
        fallback: Fallback = .perSession
    ) -> AgentProjectGroupKey {
        let displayName = session.project.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        // 1. Local repository root resolved from the reported cwd.
        if let location = locations.location(for: session.project.workingDirectory),
           let root = location.repositoryRoot {
            return AgentProjectGroupKey(
                rawValue: "repo:\(root.lowercased())",
                title: location.repositoryName ?? displayName ?? root
            )
        }

        // 2. Provider-sourced repository identity.
        if let repository = session.project.repositoryIdentity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            return AgentProjectGroupKey(
                rawValue: "repository:\(repository.lowercased())",
                title: displayName ?? repository
            )
        }

        // 3. The working directory itself (non-Git, missing, or unresolved).
        if let location = locations.location(for: session.project.workingDirectory) {
            return AgentProjectGroupKey(
                rawValue: "path:\(location.canonicalPath.lowercased())",
                title: displayName ?? location.directoryName
            )
        }
        if let normalized = AgentProjectResolver.normalize(session.project.workingDirectory) {
            return AgentProjectGroupKey(
                rawValue: "path:\(normalized.lowercased())",
                title: displayName ?? URL(fileURLWithPath: normalized).lastPathComponent
            )
        }

        // 4. No path evidence.
        let provider = session.id.sessionID.provider
        switch fallback {
        case .perSession:
            return AgentProjectGroupKey(
                rawValue: "session:\(provider.deterministicSortKey):\(session.id.sessionID.nativeID)",
                title: displayName ?? "\(provider.stableName.capitalized) session"
            )
        case .perProvider:
            if let displayName {
                return AgentProjectGroupKey(
                    rawValue: "project:\(displayName.lowercased())",
                    title: displayName
                )
            }
            return AgentProjectGroupKey(
                rawValue: "provider:\(provider.deterministicSortKey)",
                title: "\(provider.stableName.capitalized) sessions"
            )
        }
    }
}

/// Resolves session working directories in the background and publishes a
/// cached index. Resolution runs only when the set of reported working
/// directories changes or on explicit `refresh()`.
@MainActor
final class AgentProjectProjectionStore: ObservableObject {
    enum Status: Equatable, Sendable {
        case idle
        case resolving
    }

    @Published private(set) var index: AgentProjectLocationIndex = .empty
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastRefreshAt: Date?

    private let fileSystem: AgentProjectFileSystem
    private let now: () -> Date
    private var requestedPaths: Set<String> = []
    private var generation = 0
    private var task: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    init(
        fileSystem: AgentProjectFileSystem = SystemAgentProjectFileSystem(),
        now: @escaping () -> Date = Date.init
    ) {
        self.fileSystem = fileSystem
        self.now = now
    }

    /// Keeps the index in sync with the event store's sessions.
    func observe(_ sessions: some Publisher<[AgentSession], Never>) {
        cancellable = sessions
            .map { Self.workingDirectories(in: $0) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paths in
                self?.update(workingDirectories: paths)
            }
    }

    nonisolated static func workingDirectories(in sessions: [AgentSession]) -> Set<String> {
        Set(sessions.compactMap { AgentProjectResolver.normalize($0.project.workingDirectory) })
    }

    /// Resolves paths that are not yet cached; drops entries no longer used.
    func update(workingDirectories paths: Set<String>) {
        requestedPaths = paths
        let missing = paths.subtracting(index.locations.keys)
        let stale = Set(index.locations.keys).subtracting(paths)
        if !stale.isEmpty {
            var locations = index.locations
            stale.forEach { locations.removeValue(forKey: $0) }
            index = AgentProjectLocationIndex(locations: locations)
        }
        guard !missing.isEmpty else { return }
        resolve(missing)
    }

    /// Explicit refresh: re-resolve every current path.
    func refresh() {
        resolve(requestedPaths)
    }

    /// Awaits the in-flight resolution, if any. For tests and diagnostics.
    func waitForIdle() async {
        await task?.value
    }

    private func resolve(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        generation += 1
        let token = generation
        let fileSystem = fileSystem
        let previousTask = task
        status = .resolving
        task = Task { [weak self] in
            await previousTask?.value
            let resolved = await Task.detached(priority: .utility) {
                paths.compactMap { AgentProjectResolver.resolve($0, fileSystem: fileSystem) }
            }.value
            guard let self else { return }
            var locations = self.index.locations
            for location in resolved where self.requestedPaths.contains(location.normalizedPath) {
                locations[location.normalizedPath] = location
            }
            self.index = AgentProjectLocationIndex(locations: locations)
            self.lastRefreshAt = self.now()
            if token == self.generation {
                self.status = .idle
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct AgentProjectLocationsKey: EnvironmentKey {
    static let defaultValue: AgentProjectLocationIndex = .empty
}

extension EnvironmentValues {
    /// Cached project locations for Agents presentation. Views read this;
    /// they never resolve paths themselves.
    var agentProjectLocations: AgentProjectLocationIndex {
        get { self[AgentProjectLocationsKey.self] }
        set { self[AgentProjectLocationsKey.self] = newValue }
    }
}
