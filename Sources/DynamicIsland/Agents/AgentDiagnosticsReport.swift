import Foundation

/// Troubleshooting summary for providers and project resolution.
///
/// Privacy: contains only counts, capability flags, usage authority and
/// freshness, and home-abbreviated directory paths. It never includes
/// transcript text, prompts, session titles, commands or native session IDs.
struct AgentDiagnosticsReport: Equatable, Sendable {
    struct ProviderRow: Equatable, Sendable {
        let provider: AgentProvider
        let observedSessionCount: Int
        let resumableSessionCount: Int
        let managedControlAvailable: Bool
        let usage: [AgentUsageIndicator]
        let transportError: String?

        var detected: Bool { observedSessionCount > 0 || managedControlAvailable }
    }

    struct ProjectRow: Equatable, Sendable {
        let displayedDirectory: String
        let canonicalPath: String
        let repositoryRoot: String?
        /// nil while the path has not been resolved yet.
        let status: AgentProjectLocation.Status?
        let sessionCount: Int
    }

    static let maximumProjectRows = 12

    let providers: [ProviderRow]
    let projects: [ProjectRow]
    let projectionResolving: Bool
    let lastProjectionRefreshAt: Date?
    let generatedAt: Date

    static func make(
        sessions: [AgentSession],
        managedProviders: [AgentProvider],
        accountUsageByProvider: [AgentProvider: AgentUsage],
        selectedSessionIDs: [AgentProvider: AgentSessionInstanceID],
        transportErrors: [AgentProvider: String],
        locations: AgentProjectLocationIndex,
        projectionResolving: Bool,
        lastProjectionRefreshAt: Date?,
        now: Date = Date(),
        homeDirectory: String = NSHomeDirectory()
    ) -> Self {
        var providerSet = Set(managedProviders)
        sessions.forEach { providerSet.insert($0.id.sessionID.provider) }
        for provider in [AgentProvider.codex, .claude] { providerSet.insert(provider) }

        let providerRows = providerSet
            .sorted { $0.deterministicSortKey < $1.deterministicSortKey }
            .map { provider -> ProviderRow in
                let providerSessions = sessions.filter { $0.id.sessionID.provider == provider }
                let selected = selectedSessionIDs[provider].flatMap { id in
                    providerSessions.first { $0.id == id }
                } ?? providerSessions.sorted(by: AgentSessionPresentation.isOrderedBefore).first
                return ProviderRow(
                    provider: provider,
                    observedSessionCount: providerSessions.count,
                    resumableSessionCount: providerSessions.filter { $0.availability == .resumable }.count,
                    managedControlAvailable: managedProviders.contains(provider),
                    usage: AgentUsageIndicatorPresentation.make(
                        provider: provider,
                        accountUsage: accountUsageByProvider[provider] ?? AgentUsage(),
                        selectedSession: selected,
                        now: now
                    ),
                    transportError: transportErrors[provider].map { String($0.prefix(160)) }
                )
            }

        var counts: [String: Int] = [:]
        for session in sessions {
            guard let normalized = AgentProjectResolver.normalize(session.project.workingDirectory) else { continue }
            counts[normalized, default: 0] += 1
        }
        let projectRows = counts.keys.sorted().prefix(maximumProjectRows).map { path -> ProjectRow in
            let location = locations.locations[path]
            return ProjectRow(
                displayedDirectory: abbreviate(path, home: homeDirectory),
                canonicalPath: abbreviate(location?.canonicalPath ?? path, home: homeDirectory),
                repositoryRoot: location?.repositoryRoot.map { abbreviate($0, home: homeDirectory) },
                status: location?.status,
                sessionCount: counts[path] ?? 0
            )
        }

        return Self(
            providers: providerRows,
            projects: Array(projectRows),
            projectionResolving: projectionResolving,
            lastProjectionRefreshAt: lastProjectionRefreshAt,
            generatedAt: now
        )
    }

    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        let prefix = home.hasSuffix("/") ? home : home + "/"
        return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
    }

    /// Plain-text form for the Copy Diagnostics action.
    func plainText() -> String {
        var lines = ["DynamicIsland Agents diagnostics"]
        lines.append("Generated: \(ISO8601DateFormatter().string(from: generatedAt))")
        lines.append("")
        for row in providers {
            lines.append("[\(row.provider.stableName)]")
            lines.append("  detected: \(row.detected ? "yes" : "no")")
            lines.append("  observed sessions: \(row.observedSessionCount) (resumable \(row.resumableSessionCount))")
            lines.append("  managed control: \(row.managedControlAvailable ? "available" : "unavailable")")
            for indicator in row.usage {
                let value = indicator.isAvailable ? indicator.valueText + " " + indicator.directionLabel : "unavailable"
                lines.append(
                    "  usage \(indicator.label): \(value) · scope \(indicator.scope.rawValue)"
                        + " · authority \(indicator.authority.rawValue) · freshness \(indicator.freshness.rawValue)"
                )
            }
            if let error = row.transportError {
                lines.append("  last transport error: \(error)")
            }
        }
        lines.append("")
        lines.append("[projects]")
        lines.append("  projection: \(projectionResolving ? "resolving" : "idle")")
        lines.append("  last refresh: \(lastProjectionRefreshAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never")")
        for project in projects {
            lines.append("  \(project.displayedDirectory)")
            if project.canonicalPath != project.displayedDirectory {
                lines.append("    canonical: \(project.canonicalPath)")
            }
            lines.append("    repository root: \(project.repositoryRoot ?? "none")")
            lines.append("    status: \(project.status?.rawValue ?? "unresolved") · sessions \(project.sessionCount)")
        }
        return lines.joined(separator: "\n")
    }
}
