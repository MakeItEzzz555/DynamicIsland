import SwiftUI

/// One visual family for provider usage. The provider icon and value are
/// centered inside a fixed-diameter ring; the label states the metric and
/// whether the value is used or remaining.
struct AgentUsageIndicatorCircle: View {
    static let diameter: CGFloat = 34
    static let lineWidth: CGFloat = 3

    let indicator: AgentUsageIndicator

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(indicator.isAvailable ? 0.12 : 0.07), lineWidth: Self.lineWidth)
                if let fraction = indicator.fraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                } else if indicator.isAvailable {
                    // Absolute value without a known limit: dotted ring, no fake arc.
                    Circle()
                        .stroke(
                            ringColor.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                        )
                        .padding(Self.lineWidth + 1)
                }
                VStack(spacing: 0) {
                    Image(systemName: AgentVisualStyle.providerSymbol(indicator.provider))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(indicator.isAvailable ? 0.62 : 0.32))
                    Text(indicator.valueText)
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(indicator.isAvailable ? 0.92 : 0.38))
                }
                .frame(width: Self.diameter - Self.lineWidth * 2 - 4)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .opacity(indicator.freshness == .stale ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(indicator.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(indicator.isAvailable ? 0.82 : 0.42))
                Text(secondaryText)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(secondaryColor)
            }
            .lineLimit(1)
            .fixedSize()
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(indicator.accessibilityDescription)
    }

    private var ringColor: Color {
        guard let fraction = indicator.fraction else { return .white }
        switch indicator.direction {
        case .remaining:
            if fraction <= 0.1 { return .red }
            if fraction <= 0.25 { return .orange }
            return .white.opacity(0.88)
        case .used:
            if fraction >= 0.9 { return .red }
            if fraction >= 0.75 { return .orange }
            return .white.opacity(0.88)
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

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(indicators) { indicator in
                AgentUsageIndicatorCircle(indicator: indicator)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent usage")
    }
}
