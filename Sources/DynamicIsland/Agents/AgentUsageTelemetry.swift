import Foundation

/// Provider-neutral usage indicator with explicit semantics. Unavailable data
/// is represented as unavailable, never as 0% or 100%.
struct AgentUsageIndicator: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case fiveHour
        case week
        case context
    }

    enum Scope: String, Equatable, Sendable {
        /// Provider account (rate-limit windows). Independent of selection.
        case account
        /// The selected exact thread/session.
        case thread
    }

    enum Direction: String, Equatable, Sendable {
        case used
        case remaining
    }

    enum Authority: String, Equatable, Sendable {
        case providerAPI
        case providerEvent
        case providerTranscript
        case unavailable
    }

    enum Freshness: String, Equatable, Sendable {
        case live
        case recent
        case stale
        case unavailable
    }

    let provider: AgentProvider
    let kind: Kind
    let scope: Scope
    let direction: Direction
    /// 0...1 in the indicator's direction; nil when no limit is known.
    let fraction: Double?
    /// Absolute amount when no fraction is available (e.g. context tokens).
    let absoluteValue: Double?
    let authority: Authority
    let freshness: Freshness
    let updatedAt: Date?
    let unavailableReason: String?

    var id: String { "\(provider.deterministicSortKey):\(kind.rawValue)" }

    var label: String {
        switch kind {
        case .fiveHour: "5h"
        case .week: "Week"
        case .context: "Context"
        }
    }

    var directionLabel: String {
        direction == .remaining ? "left" : "used"
    }

    var isAvailable: Bool { authority != .unavailable }

    /// Centered value text for the circle.
    var valueText: String {
        guard isAvailable else { return "—" }
        if let fraction {
            return "\(Int((fraction * 100).rounded()))%"
        }
        if let absoluteValue {
            return Self.compactTokens(absoluteValue)
        }
        return "—"
    }

    var accessibilityDescription: String {
        let providerName = provider.stableName.capitalized
        guard isAvailable else {
            return "\(providerName) \(label): unavailable"
                + (unavailableReason.map { ". \($0)" } ?? "")
        }
        var text: String
        if let fraction {
            text = "\(providerName) \(label): \(Int((fraction * 100).rounded())) percent \(directionLabel)"
        } else if let absoluteValue {
            text = "\(providerName) \(label): \(Self.compactTokens(absoluteValue)) tokens \(directionLabel)"
        } else {
            text = "\(providerName) \(label)"
        }
        if freshness == .stale { text += ", stale" }
        return text
    }

    static func compactTokens(_ value: Double) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            return (value / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M"
        }
        if absolute >= 1_000 {
            return (value / 1_000).formatted(.number.precision(.fractionLength(0))) + "k"
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}

enum AgentUsageIndicatorPresentation {
    /// Account windows change slowly; thread context changes with activity.
    static let accountLiveWindow: TimeInterval = 5 * 60
    static let accountStaleAfter: TimeInterval = 30 * 60
    static let threadLiveWindow: TimeInterval = 2 * 60
    static let threadStaleAfter: TimeInterval = 15 * 60

    static let claudeAccountUnavailableReason =
        "Claude Code does not expose account rate-limit windows to DynamicIsland"

    /// Indicators for one provider: 5h and Week from account usage for that
    /// provider only, Context from the selected exact session of that
    /// provider only. Providers never share values.
    static func make(
        provider: AgentProvider,
        accountUsage: AgentUsage,
        selectedSession: AgentSession?,
        now: Date = Date()
    ) -> [AgentUsageIndicator] {
        let session = selectedSession?.id.sessionID.provider == provider ? selectedSession : nil
        return [
            accountIndicator(.fiveHour, provider: provider, usage: accountUsage, now: now),
            accountIndicator(.week, provider: provider, usage: accountUsage, now: now),
            contextIndicator(provider: provider, session: session, now: now)
        ]
    }

    static func freshness(
        observedAt: Date,
        scope: AgentUsageIndicator.Scope,
        now: Date
    ) -> AgentUsageIndicator.Freshness {
        let age = max(now.timeIntervalSince(observedAt), 0)
        switch scope {
        case .account:
            if age <= accountLiveWindow { return .live }
            return age <= accountStaleAfter ? .recent : .stale
        case .thread:
            if age <= threadLiveWindow { return .live }
            return age <= threadStaleAfter ? .recent : .stale
        }
    }

    private static func accountIndicator(
        _ kind: AgentUsageIndicator.Kind,
        provider: AgentProvider,
        usage: AgentUsage,
        now: Date
    ) -> AgentUsageIndicator {
        let wanted = kind == .fiveHour ? "5h" : "Week"
        let used = usage.samples(for: .quotaUsed).first {
            AgentUsagePresentation.quotaScopeLabel($0.scope) == wanted
        }
        guard let used else {
            return unavailable(
                kind,
                provider: provider,
                scope: .account,
                direction: .remaining,
                reason: provider == .claude
                    ? claudeAccountUnavailableReason
                    : "No \(wanted) limit reported by the provider yet"
            )
        }
        let limit = used.limit ?? usage.samples(for: .quotaLimit)
            .first(where: { $0.scope == used.scope })?.value
        guard let limit, limit.isFinite, limit > 0 else {
            return unavailable(
                kind,
                provider: provider,
                scope: .account,
                direction: .remaining,
                reason: "The provider reported \(wanted) usage without a limit"
            )
        }
        let usedFraction = min(max(used.value / limit, 0), 1)
        return AgentUsageIndicator(
            provider: provider,
            kind: kind,
            scope: .account,
            direction: .remaining,
            fraction: 1 - usedFraction,
            absoluteValue: nil,
            authority: .providerAPI,
            freshness: freshness(observedAt: used.observedAt, scope: .account, now: now),
            updatedAt: used.observedAt,
            unavailableReason: nil
        )
    }

    private static func contextIndicator(
        provider: AgentProvider,
        session: AgentSession?,
        now: Date
    ) -> AgentUsageIndicator {
        guard let session else {
            return unavailable(
                .context,
                provider: provider,
                scope: .thread,
                direction: .used,
                reason: "No \(provider.stableName.capitalized) session selected"
            )
        }
        guard let used = session.usage[.contextUsed], used.isValid else {
            return unavailable(
                .context,
                provider: provider,
                scope: .thread,
                direction: .used,
                reason: "The selected session has not reported context usage"
            )
        }
        let limit = used.limit ?? session.usage[.contextLimit]?.value
        let fraction: Double?
        if let limit, limit.isFinite, limit > 0 {
            fraction = min(max(used.value / limit, 0), 1)
        } else {
            fraction = nil
        }
        let authority: AgentUsageIndicator.Authority =
            used.source.localizedCaseInsensitiveContains("transcript")
                ? .providerTranscript
                : .providerEvent
        return AgentUsageIndicator(
            provider: provider,
            kind: .context,
            scope: .thread,
            direction: .used,
            fraction: fraction,
            absoluteValue: fraction == nil ? used.value : nil,
            authority: authority,
            freshness: freshness(observedAt: used.observedAt, scope: .thread, now: now),
            updatedAt: used.observedAt,
            unavailableReason: nil
        )
    }

    private static func unavailable(
        _ kind: AgentUsageIndicator.Kind,
        provider: AgentProvider,
        scope: AgentUsageIndicator.Scope,
        direction: AgentUsageIndicator.Direction,
        reason: String
    ) -> AgentUsageIndicator {
        AgentUsageIndicator(
            provider: provider,
            kind: kind,
            scope: scope,
            direction: direction,
            fraction: nil,
            absoluteValue: nil,
            authority: .unavailable,
            freshness: .unavailable,
            updatedAt: nil,
            unavailableReason: reason
        )
    }
}
