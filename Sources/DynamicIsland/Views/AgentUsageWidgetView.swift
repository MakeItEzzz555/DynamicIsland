import SwiftUI

/// Provider-grouped quota usage (5h and Week, remaining). One composition is
/// used for the default Agents usage row and for the customizable Combined,
/// Codex and Claude usage widgets. Values come only from each provider's own
/// authoritative account usage; Context is intentionally not shown (see
/// context.md, "Context metric decision").
struct AgentUsageWidgetView: View {
    enum Scope: Equatable {
        case combined
        case provider(AgentProvider)

        init?(widget: IslandWidget) {
            switch widget {
            case .agentUsage: self = .combined
            case .codexUsage: self = .provider(.codex)
            case .claudeUsage: self = .provider(.claude)
            default: return nil
            }
        }

        var providers: [AgentProvider] {
            switch self {
            case .combined: [.codex, .claude]
            case .provider(let provider): [provider]
            }
        }
    }

    @ObservedObject var managedControl: AgentManagedSessionController
    let scope: Scope
    /// Smaller rings on narrow surfaces; hit targets are informational only.
    var compact = false

    var body: some View {
        let _ = AgentPerformanceProbe.count("agents.usage.body")
        let groups = AgentWorkspaceUsageProjection.providerGroups(accountUsage: managedControl.accountUsageByProvider)
        AgentUsageComposition(groups: scope.providers.map { ($0, groups[$0] ?? []) }, compact: compact)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(scope == .combined ? "Agent usage" : "\(scope.providers.first?.stableName.capitalized ?? "") usage")
    }
}

/// Pure layout for provider groups: each provider's gauges stay together,
/// groups are separated by a hairline, and the whole composition is centered.
struct AgentUsageComposition: View {
    let groups: [(provider: AgentProvider, indicators: [AgentUsageIndicator])]
    var compact = false

    private var diameter: CGFloat { compact ? 40 : 48 }

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 14 : 20) {
            ForEach(Array(groups.enumerated()), id: \.element.provider) { index, group in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: diameter * 0.9)
                        .accessibilityHidden(true)
                }
                providerGroup(group.provider, group.indicators)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func providerGroup(_ provider: AgentProvider, _ indicators: [AgentUsageIndicator]) -> some View {
        HStack(alignment: .center, spacing: compact ? 7 : 9) {
            VStack(spacing: 2) {
                Image(systemName: AgentVisualStyle.providerSymbol(provider))
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(AgentVisualStyle.providerAccent(provider))
                Text(provider.stableName.capitalized)
                    .font(.system(size: compact ? 7.5 : 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize()
            }
            HStack(alignment: .top, spacing: compact ? 7 : 10) {
                ForEach(indicators) { indicator in
                    VStack(spacing: 2) {
                        AgentUsageIndicatorCircle(
                            indicator: indicator,
                            metrics: .init(quotaDiameter: diameter, contextDiameter: diameter),
                            showsLabels: false
                        )
                        Text("\(indicator.label) · \(indicator.directionLabel)")
                            .font(.system(size: compact ? 7.5 : 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(provider.stableName.capitalized) usage")
    }
}
