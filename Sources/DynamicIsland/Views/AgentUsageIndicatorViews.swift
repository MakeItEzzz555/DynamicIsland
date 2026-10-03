import SwiftUI

/// Gauge sizes. The two account quotas (5h, Week) are the primary read and
/// get the large ring; Context stays smaller so the hierarchy is clear.
/// Under genuine width pressure both step down together.
struct AgentUsageIndicatorMetrics: Equatable, Sendable {
    static let narrowWidth: CGFloat = 520

    let quotaDiameter: CGFloat
    let contextDiameter: CGFloat

    static let standard = Self(quotaDiameter: 44, contextDiameter: 34)
    static let narrow = Self(quotaDiameter: 36, contextDiameter: 30)

    static func make(width: CGFloat) -> Self {
        width < narrowWidth ? .narrow : .standard
    }

    func diameter(for kind: AgentUsageIndicator.Kind) -> CGFloat {
        kind == .context ? contextDiameter : quotaDiameter
    }

    /// Ring line width and centered value size scale with the ring.
    static func lineWidth(for diameter: CGFloat) -> CGFloat { diameter >= 40 ? 3.5 : 3 }
    static func valueFontSize(for diameter: CGFloat) -> CGFloat { (diameter * 0.245).rounded(.down) + 0.5 }
    static func iconSize(for diameter: CGFloat) -> CGFloat { diameter >= 40 ? 11 : 9 }
}

/// One visual family for provider usage. The provider icon and value are
/// centered inside a fixed-diameter ring; the label states the metric and
/// whether the value is used or remaining.
struct AgentUsageIndicatorCircle: View {
    /// Tallest ring, used to size the control row that may host the gauges.
    static let diameter: CGFloat = AgentUsageIndicatorMetrics.standard.quotaDiameter

    let indicator: AgentUsageIndicator
    var metrics: AgentUsageIndicatorMetrics = .standard
    var showsLabels = true

    private var diameter: CGFloat { metrics.diameter(for: indicator.kind) }
    private var lineWidth: CGFloat { AgentUsageIndicatorMetrics.lineWidth(for: diameter) }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                // Inset by half the stroke so the ring stays inside its frame
                // and is never clipped by a tight control row.
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(.white.opacity(indicator.isAvailable ? 0.12 : 0.07), lineWidth: lineWidth)
                if let fraction = indicator.fraction {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: fraction)
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                } else if indicator.isAvailable {
                    // Absolute value without a known limit: dotted ring, no fake arc.
                    Circle()
                        .stroke(
                            ringColor.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                        )
                        .padding(lineWidth + 1)
                }
                VStack(spacing: 0) {
                    providerIcon
                    Text(indicator.valueText)
                        .font(.system(size: AgentUsageIndicatorMetrics.valueFontSize(for: diameter), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(indicator.isAvailable ? 0.92 : 0.38))
                }
                .frame(width: diameter - lineWidth * 2 - 4)
            }
            .frame(width: diameter, height: diameter)
            .opacity(indicator.freshness == .stale ? 0.55 : 1)

            if showsLabels {
            VStack(alignment: .leading, spacing: 0) {
                Text(indicator.label)
                    .font(.system(size: indicator.kind == .context ? 9 : 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(indicator.isAvailable ? 0.82 : 0.42))
                Text(secondaryText)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(secondaryColor)
            }
            .lineLimit(1)
            .fixedSize()
            }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(indicator.accessibilityDescription)
    }

    /// Provider-identity ring: Claude orange for Claude, the existing
    /// neutral ring for Codex. Red marks critically low remaining quota or
    /// nearly full context; Codex additionally shows orange as a warning.
    private var ringColor: Color {
        let base: Color = indicator.provider == .claude
            ? AgentVisualStyle.claudeOrange
            : .white.opacity(0.88)
        guard let fraction = indicator.fraction else { return base }
        let critical: Bool
        let warning: Bool
        switch indicator.direction {
        case .remaining:
            critical = fraction <= 0.1
            warning = fraction <= 0.25
        case .used:
            critical = fraction >= 0.9
            warning = fraction >= 0.75
        }
        if critical { return .red }
        if warning, indicator.provider != .claude { return .orange }
        return base
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let icon = AgentVisualStyle.installedProviderIcon(indicator.provider) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: AgentUsageIndicatorMetrics.iconSize(for: diameter),
                    height: AgentUsageIndicatorMetrics.iconSize(for: diameter)
                )
                .opacity(indicator.isAvailable ? 1 : 0.45)
        } else {
            Image(systemName: AgentVisualStyle.providerSymbol(indicator.provider))
                .font(.system(size: AgentUsageIndicatorMetrics.iconSize(for: diameter) - 2, weight: .bold))
                .foregroundStyle(
                    indicator.provider == .claude
                        ? AgentVisualStyle.claudeOrange.opacity(indicator.isAvailable ? 0.9 : 0.4)
                        : Color.white.opacity(indicator.isAvailable ? 0.62 : 0.32)
                )
        }
    }

    private var secondaryText: String {
        switch indicator.freshness {
        case .unavailable: "unavailable"
        case .stale: "\(indicator.directionLabel) · stale"
        case .live, .recent: indicator.directionLabel
        }
    }

    private var secondaryColor: Color {
        switch indicator.freshness {
        case .stale: .orange.opacity(0.8)
        case .unavailable: .white.opacity(0.30)
        case .live, .recent: .white.opacity(0.42)
        }
    }

    private var helpText: String {
        if let reason = indicator.unavailableReason { return reason }
        var parts = [
            indicator.scope == .account ? "Account-wide" : "Selected session",
            indicator.direction == .remaining ? "remaining" : "used"
        ]
        switch indicator.authority {
        case .providerAPI: parts.append("from the provider API")
        case .providerCLI: parts.append("from the provider's usage command")
        case .providerEvent: parts.append("from provider session events")
        case .providerTranscript: parts.append("from the provider transcript")
        case .unavailable: break
        }
        if indicator.kind == .context, indicator.fraction == nil {
            parts.append("(context window size not reported)")
        }
        if let updatedAt = indicator.updatedAt {
            parts.append("· updated \(updatedAt.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " ")
    }
}

struct AgentUsageIndicatorRow: View {
    let indicators: [AgentUsageIndicator]
    var spacing: CGFloat = 16
    var metrics: AgentUsageIndicatorMetrics = .standard

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(indicators) { indicator in
                AgentUsageIndicatorCircle(indicator: indicator, metrics: metrics)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent usage")
    }
}
