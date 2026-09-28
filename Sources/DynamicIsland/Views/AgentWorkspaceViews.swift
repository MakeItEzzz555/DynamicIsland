import SwiftUI

struct AgentWorkspaceHeader: View {
    let session: AgentSession
    @ObservedObject var managedControl: AgentManagedSessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseOn = false

    private var metadata: AgentWorkspaceMetadataPresentation {
        .make(
            session: session,
            isManaged: managedControl.isManaged(session),
            canConnect: managedControl.canConnect(session)
        )
    }

    private var displayedState: String {
        if managedControl.isInterrupting(session) { return "Stopping…" }
        switch metadata.ownership {
        case .managed, .observed:
            return AgentSessionPresentation.displayedStateLabel(for: session, at: Date())
        case .resumable:
            return "Resumable"
        case .unavailable:
            return "Not attached"
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(AgentVisualStyle.providerAccent(session.id.sessionID.provider).opacity(0.16))
                Image(systemName: AgentVisualStyle.providerSymbol(session.id.sessionID.provider))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AgentVisualStyle.providerAccent(session.id.sessionID.provider))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.id.sessionID.provider.stableName.capitalized)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.94))
                    ownershipBadge
                }
                HStack(spacing: 5) {
                    stateIndicator
                    Text(displayedState)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(stateColor.opacity(0.88))
                        .lineLimit(1)
                    if !metadata.project.isEmpty {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.20))
                        Text(metadata.project)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            if let model = metadata.model {
                Label(model, systemImage: "cpu")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.055), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.id.sessionID.provider.stableName.capitalized), \(displayedState), \(metadata.ownership.rawValue)"
        )
    }

    @ViewBuilder
    private var ownershipBadge: some View {
        let (text, symbol): (String, String) = switch metadata.ownership {
        case .managed: ("Managed", "link")
        case .observed: ("Observed", "eye")
        case .resumable: ("Resumable", "arrow.clockwise")
        case .unavailable: ("Not attached", "link.badge.slash")
        }
        Label(text, systemImage: symbol)
            .font(.system(size: 6.8, weight: .bold))
            .foregroundStyle(.white.opacity(metadata.ownership == .managed ? 0.70 : 0.42))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.white.opacity(metadata.ownership == .managed ? 0.085 : 0.045), in: Capsule())
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.state {
        case .runningTool, .runningCommand:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.55)
                .frame(width: 8, height: 8)
                .tint(stateColor)
        default:
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
                .scaleEffect(reduceMotion || !pulses ? 1 : (pulseOn ? 1.22 : 0.92))
                .opacity(reduceMotion || !pulses ? 1 : (pulseOn ? 0.72 : 1))
                .shadow(
                    color: reduceMotion || !pulses ? .clear : stateColor.opacity(0.42),
                    radius: pulseOn ? 4 : 2
                )
                .onAppear { synchronizePulse() }
                .onChange(of: pulses) { _, _ in synchronizePulse() }
        }
    }

    private func synchronizePulse() {
        pulseOn = false
        guard pulses, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
            pulseOn = true
        }
    }

    private var pulses: Bool {
        switch session.state {
        case .working, .thinking, .planning, .waitingForApproval: true
        default: false
        }
    }

    private var stateColor: Color {
        managedControl.isInterrupting(session) ? .orange : AgentVisualStyle.accent(for: session.state)
    }
}

struct AgentRecentActivityView: View {
    let session: AgentSession
    var mode: AgentRecentActivityDisplayMode = .recentList
    var limit = 4

    private var items: [AgentRecentActivityItem] {
        AgentRecentActivityPresentation.make(for: session, limit: limit)
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Recent Activity")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.40))
                    Spacer()
                    if let active = AgentRecentActivityPresentation.active(for: session) {
                        Text(active.title)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.28))
                            .lineLimit(1)
                    }
                }

                if mode == .activeDetail, let active = AgentRecentActivityPresentation.active(for: session) {
                    AgentRecentActivityRow(item: active, detailed: true)
                } else {
                    ForEach(items.suffix(3)) { item in
                        AgentRecentActivityRow(item: item, detailed: false)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.045), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recent agent activity")
        }
    }
}

struct AgentRecentActivityRow: View {
    let item: AgentRecentActivityItem
    let detailed: Bool
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: statusSymbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 11, height: 13)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: detailed ? 9 : 8.2, weight: item.status == .active ? .bold : .semibold))
                    .foregroundStyle(.white.opacity(item.status == .active ? 0.90 : 0.62))
                    .lineLimit(1)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 7.5, weight: .medium, design: item.isCommand ? .monospaced : .default))
                        .foregroundStyle(.white.opacity(0.34))
                        .lineLimit(detailed ? 2 : 1)
                }
            }

            Spacer(minLength: 5)

            TimelineView(.periodic(from: .now, by: 10)) { context in
                Text(relativeAge(now: context.date))
                    .font(.system(size: 6.8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.26))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.white.opacity(hovered ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 6))
        .scaleEffect(hovered ? 1.006 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }
    }

    private var statusColor: Color {
        switch item.status {
        case .active: .cyan
        case .pending: .orange
        case .failed: .red
        case .completed, .resolved: .green.opacity(0.75)
        case .cancelled, .unknown: .white.opacity(0.32)
        }
    }

    private var statusSymbol: String {
        switch item.status {
        case .active: "circle.fill"
        case .pending: "hand.raised.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .completed, .resolved: "checkmark"
        case .cancelled: "xmark"
        case .unknown: item.symbol
        }
    }

    private func relativeAge(now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(item.timestamp)), 0)
        if item.status == .active || item.status == .pending { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}

struct AgentCompactUsageStrip: View {
    let metrics: [AgentGlobalUsagePresentation]

    var body: some View {
        HStack(spacing: 7) {
            if metrics.isEmpty {
                Label("Usage waiting for provider data", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.30))
            } else {
                ForEach(metrics) { metric in
                    AgentCompactUsageItem(metric: metric)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent usage")
    }
}

private struct AgentCompactUsageItem: View {
    let metric: AgentGlobalUsagePresentation
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 2)
                if let progress = metric.metric.gaugeProgress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: metricSymbol)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(compactLabel)
                    .font(.system(size: 6.8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
                Text(metric.metric.gaugeValueText)
                    .font(.system(size: 7.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(metric.metric.isStale ? .orange.opacity(0.72) : .white.opacity(0.78))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.white.opacity(hovered ? 0.045 : 0), in: Capsule())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(metric.metric.isStale ? "\(metric.metric.label) · stale" : metric.metric.label)
    }

    private var compactLabel: String {
        let label = metric.metric.label
        if label.lowercased().contains("quota") {
            return label.replacingOccurrences(of: "Quota · ", with: "")
        }
        return label
    }

    private var metricSymbol: String {
        let label = metric.metric.label.lowercased()
        if label.contains("5h") { return "clock" }
        if label.contains("week") { return "calendar" }
        if label == "context" { return "gauge.with.dots.needle.33percent" }
        return AgentVisualStyle.providerSymbol(metric.provider)
    }
}

struct AgentContextFooter: View {
    let session: AgentSession
    @ObservedObject var managedControl: AgentManagedSessionController

    private var metadata: AgentWorkspaceMetadataPresentation {
        .make(
            session: session,
            isManaged: managedControl.isManaged(session),
            canConnect: managedControl.canConnect(session)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let context = metadata.context {
                HStack(spacing: 6) {
                    Text("Context")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.36))
                    Text(context.valueText)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(context.isStale ? .orange.opacity(0.70) : .white.opacity(0.68))
                    Spacer()
                    if context.isStale {
                        Label("Stale", systemImage: "clock.badge.exclamationmark")
                            .font(.system(size: 6.5, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.72))
                    }
                }
                if let progress = context.progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule()
                                .fill(.white.opacity(0.60))
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 3)
                }
            }

            ViewThatFits(in: .horizontal) {
                metadataRow(includeModel: true, includeThread: true)
                metadataRow(includeModel: false, includeThread: false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metadataRow(includeModel: Bool, includeThread: Bool) -> some View {
        HStack(spacing: 9) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let elapsed = AgentTurnTimingPresentation.elapsedText(
                    startedAt: managedControl.activeTurnStartedAt(for: session),
                    now: context.date
                ) {
                    Label(elapsed, systemImage: "clock")
                        .monospacedDigit()
                } else {
                    Text(AgentTurnTimingPresentation.relativeUpdateText(
                        lastUpdatedAt: session.lastUpdatedAt,
                        now: context.date
                    ))
                }
            }

            if let branch = metadata.branch, !branch.isEmpty {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(2)
            }

            if includeModel, let model = metadata.model {
                Label(model, systemImage: "cpu")
                    .lineLimit(1)
            }

            if includeThread {
                Text(metadata.threadSuffix)
                    .fontDesign(.monospaced)
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 7, weight: .medium))
        .foregroundStyle(.white.opacity(0.34))
    }
}

struct AgentSessionCardView: View {
    let session: AgentSession
    let selected: Bool
    @ObservedObject var managedControl: AgentManagedSessionController
    let onSelect: () -> Void
    @State private var hovered = false

    private var metadata: AgentWorkspaceMetadataPresentation {
        .make(
            session: session,
            isManaged: managedControl.isManaged(session),
            canConnect: managedControl.canConnect(session)
        )
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: AgentVisualStyle.providerSymbol(session.id.sessionID.provider))
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(AgentVisualStyle.providerAccent(session.id.sessionID.provider))
                    Text(metadata.project)
                        .font(.system(size: 8, weight: selected ? .bold : .semibold))
                        .foregroundStyle(.white.opacity(selected ? 0.92 : 0.68))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let progress = metadata.context?.progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: AgentSessionPresentation.displayedStateSymbol(for: session, at: Date()))
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(AgentVisualStyle.accent(for: session.state))
                    Text(stateLabel)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    Text(metadata.threadSuffix)
                        .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }

                if let branch = metadata.branch, !branch.isEmpty {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 6.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(width: 118, alignment: .leading)
            .background(
                selected ? Color.white.opacity(0.105) :
                    Color.white.opacity(hovered ? 0.060 : 0.030),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .scaleEffect(hovered ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.13), value: hovered)
        .help("\(metadata.ownership.rawValue.capitalized) · \(stateLabel)")
    }

    private var stateLabel: String {
        switch metadata.ownership {
        case .managed:
            return AgentSessionPresentation.displayedStateLabel(for: session, at: Date())
        case .observed: return "Observed"
        case .resumable: return "Resumable"
        case .unavailable: return "Not attached"
        }
    }

    private var borderColor: Color {
        if session.state == .waitingForApproval { return .orange.opacity(0.34) }
        if session.state == .failed { return .red.opacity(0.28) }
        if selected { return .white.opacity(0.18) }
        return .white.opacity(hovered ? 0.10 : 0.055)
    }
}
