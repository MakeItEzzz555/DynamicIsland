import Foundation

struct CodexRolloutCandidate: Equatable, Sendable {
    let url: URL
    let modifiedAt: Date
}

enum CodexRolloutSessionDiscovery {
    static func recentRolloutCandidates(
        in sessionsDirectory: URL,
        now: Date = Date(),
        recentWindow: TimeInterval = 300,
        limit: Int = 32,
        fileManager: FileManager = .default
    ) -> [CodexRolloutCandidate] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path),
              let enumerator = fileManager.enumerator(
                at: sessionsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }

        let threshold = now.addingTimeInterval(-max(0, recentWindow))
        var candidates: [(url: URL, modified: Date)] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-") else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= threshold else { continue }
            candidates.append((url, modified))
        }

        return candidates
            .sorted {
                if $0.modified != $1.modified { return $0.modified > $1.modified }
                return $0.url.path < $1.url.path
            }
            .prefix(max(0, limit))
            .map { CodexRolloutCandidate(url: $0.url, modifiedAt: $0.modified) }
    }

    static func recentRollouts(
        in sessionsDirectory: URL,
        now: Date = Date(),
        recentWindow: TimeInterval = 300,
        limit: Int = 32,
        fileManager: FileManager = .default
    ) -> [URL] {
        recentRolloutCandidates(
            in: sessionsDirectory,
            now: now,
            recentWindow: recentWindow,
            limit: limit,
            fileManager: fileManager
        ).map(\.url)
    }
}

actor CodexRolloutSessionMonitor {
    private let adapter: CodexRolloutRecoveryAdapter
    private let sessionsDirectory: URL
    private let scanInterval: Duration
    private let recentWindow: TimeInterval
    private let maximumSessions: Int
    private var watched: Set<URL> = []
    private var lastObservedModificationDates: [URL: Date] = [:]
    private var scanTask: Task<Void, Never>?

    init(
        coordinator: AgentIngestionCoordinator,
        integrationRouter: AgentIntegrationRouter? = nil,
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        scanInterval: Duration = .seconds(10),
        recentWindow: TimeInterval = 300,
        maximumSessions: Int = 32
    ) {
        self.adapter = CodexRolloutRecoveryAdapter(
            coordinator: coordinator,
            integrationRouter: integrationRouter
        )
        self.sessionsDirectory = sessionsDirectory
        self.scanInterval = scanInterval
        self.recentWindow = recentWindow
        self.maximumSessions = maximumSessions
    }

    func start() async {
        guard scanTask == nil else { return }
        guard await adapter.start() else { return }
        await scanNow()
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.scanInterval)
                guard !Task.isCancelled else { return }
                await self.scanNow()
            }
        }
    }

    func scanNow(now: Date = Date()) async {
        let directory = sessionsDirectory
        let window = recentWindow
        let limit = maximumSessions
        let candidates = await Task.detached(priority: .utility) {
            CodexRolloutSessionDiscovery.recentRolloutCandidates(
                in: directory,
                now: now,
                recentWindow: window,
                limit: limit
            )
        }.value

        let current = Set(candidates.map(\.url))
        for candidate in candidates {
            let url = candidate.url
            if !watched.contains(url) {
                if await adapter.attach(fileURL: url, initialPolicy: .boundedCatchUp) {
                    watched.insert(url)
                }
            }
            guard watched.contains(url) else { continue }
            let previousModification = lastObservedModificationDates[url]
            if previousModification == nil || candidate.modifiedAt > previousModification! {
                await adapter.observeFileActivity(
                    fileURL: url,
                    modifiedAt: candidate.modifiedAt,
                    observedAt: now
                )
                lastObservedModificationDates[url] = candidate.modifiedAt
            }
        }
        for url in watched.subtracting(current) {
            await adapter.detach(fileURL: url)
            watched.remove(url)
            lastObservedModificationDates.removeValue(forKey: url)
        }
        await adapter.reconcileAll()
    }

    func stop() async {
        scanTask?.cancel()
        scanTask = nil
        watched.removeAll()
        lastObservedModificationDates.removeAll()
        await adapter.stop()
    }

    func watchedURLs() -> Set<URL> { watched }
}
