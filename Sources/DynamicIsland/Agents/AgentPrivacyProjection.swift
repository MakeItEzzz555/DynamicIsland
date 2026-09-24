import Foundation

enum AgentPrivacyProjection {
    static func title(_ value: String?, fallback: String) -> String {
        bounded(normalized(value), limit: AgentDomainLimits.titleLength) ?? fallback
    }

    static func summary(_ value: String?) -> String? {
        bounded(normalized(value), limit: AgentDomainLimits.summaryLength)
    }

    /// Accepts an executable/name field, never a complete command line. If a caller
    /// supplies arguments anyway, only the first path component's basename survives.
    static func commandSummary(executable value: String?) -> String {
        guard let normalized = normalized(value),
              let token = normalized.split(whereSeparator: { $0.isWhitespace }).first else {
            return "Running command"
        }
        let basename = URL(fileURLWithPath: String(token)).lastPathComponent
        guard !basename.isEmpty else { return "Running command" }
        return title(basename, fallback: "Running command")
    }

    static func toolName(_ value: String?) -> String {
        title(value, fallback: "Tool")
    }

    static func project(_ context: AgentProjectContext) -> AgentProjectContext {
        AgentProjectContext(
            displayName: summaryField(context.displayName, limit: AgentDomainLimits.titleLength),
            workingDirectory: boundedPath(context.workingDirectory),
            repositoryIdentity: summaryField(context.repositoryIdentity, limit: AgentDomainLimits.identifierLength),
            gitBranch: summaryField(context.gitBranch, limit: AgentDomainLimits.identifierLength),
            gitCommit: summaryField(context.gitCommit, limit: AgentDomainLimits.identifierLength),
            model: summaryField(context.model, limit: AgentDomainLimits.identifierLength),
            sourceApplication: sourceApplication(context.sourceApplication)
        )
    }

    static func displayProject(_ context: AgentProjectContext) -> AgentProjectDisplayContext {
        AgentProjectDisplayContext(
            displayName: context.displayName,
            gitBranch: context.gitBranch,
            model: context.model,
            sourceApplicationName: context.sourceApplication?.displayName
        )
    }

    static func capabilityEvidence(_ evidence: AgentCapabilityEvidence) -> AgentCapabilityEvidence {
        AgentCapabilityEvidence(
            authority: evidence.authority,
            source: title(evidence.source, fallback: "unknown"),
            observedAt: evidence.observedAt
        )
    }

    static func usage(_ usage: AgentUsage) -> AgentUsage {
        AgentUsage(samples: usage.samples.mapValues { sample in
            AgentUsageSample(
                value: sample.value,
                limit: sample.limit,
                unit: sample.unit,
                scope: title(sample.scope, fallback: "unknown"),
                source: title(sample.source, fallback: "unknown"),
                observedAt: sample.observedAt
            )
        })
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    static func bounded(_ value: String?, limit: Int) -> String? {
        guard let value, limit > 0 else { return nil }
        guard value.count > limit else { return value }
        guard limit > 1 else { return String(value.prefix(limit)) }
        return String(value.prefix(limit - 1)) + "…"
    }

    private static func summaryField(_ value: String?, limit: Int) -> String? {
        bounded(normalized(value), limit: limit)
    }

    private static func boundedPath(_ value: String?) -> String? {
        guard let value = summaryField(value, limit: AgentDomainLimits.pathLength),
              value.hasPrefix("/") else {
            return nil
        }
        return value
    }

    private static func sourceApplication(
        _ application: AgentSourceApplication?
    ) -> AgentSourceApplication? {
        guard let application else { return nil }
        return AgentSourceApplication(
            displayName: title(application.displayName, fallback: "Unknown App"),
            bundleIdentifier: summaryField(
                application.bundleIdentifier,
                limit: AgentDomainLimits.bundleIdentifierLength
            )
        )
    }
}
