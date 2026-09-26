import AgentBridgeShared
import SwiftUI

enum AgentVisualStyle {
    static func accent(for state: AgentState) -> Color {
        switch state {
        case .completed: .green
        case .failed: .red
        case .waitingForApproval, .waitingForUser: .orange
        case .planReady, .planning, .thinking: .cyan
        case .interrupted: .yellow
        case .working, .runningTool, .runningCommand: .blue
        case .idle: .secondary
        }
    }

    static func providerAccent(_ provider: AgentProvider) -> Color {
        switch provider {
        case .codex: .cyan
        case .claude: .orange
        case .other: .purple
        }
    }

    static func providerSymbol(_ provider: AgentProvider) -> String {
        switch provider {
        case .codex: "terminal"
        case .claude: "brain.head.profile"
        case .other: "cube"
        }
    }

    static func attentionSurfaceTint(for state: AgentState) -> Color {
        switch state {
        case .waitingForApproval, .waitingForUser:
            Color(red: 0.72, green: 0.34, blue: 0.42)
        case .failed:
            .red
        case .interrupted:
            .yellow
        case .planReady:
            .cyan
        default:
            accent(for: state)
        }
    }
}

struct AgentActivityDashboardView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var agentEvents: AgentEventStore
    @ObservedObject var approvalControl: AgentApprovalController
    let availableHeight: CGFloat

    var body: some View {
        AgentDashboardContentView(
            sessions: agentEvents.sessions,
            showsUsage: settings.agentUsageMetricsEnabled,
            approvalControl: approvalControl,
            availableHeight: availableHeight
        )
    }
}

struct AgentDashboardContentView: View {
    let sessions: [AgentSession]
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController
    let availableHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    let layout = AgentDashboardLayoutProjection.make(width: proxy.size.width)
                    ScrollView(.vertical, showsIndicators: true) {
                        AgentDashboardStack(
                            sessions: sessions,
                            showsUsage: showsUsage,
                            approvalControl: approvalControl,
                            layout: layout,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: availableHeight, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
            Text("No agent sessions")
                .font(.system(size: 13, weight: .semibold))
            Text("Verified Codex and Claude activity will appear after the first accepted event.")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct AgentDashboardStack: View {
    let sessions: [AgentSession]
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController
    let layout: AgentDashboardLayoutProjection
    let reduceMotion: Bool

    var body: some View {
        let dashboard = AgentDashboardPresentation.make(sessions: sessions)
        let metrics = showsUsage
            ? AgentGlobalUsagePresentation.make(sessions: sessions, limit: layout.maximumGaugeCount)
            : []

        VStack(alignment: .leading, spacing: 0) {
            if !metrics.isEmpty {
                AgentGlobalSummaryStrip(metrics: metrics, layout: layout)
                    .padding(.bottom, 11)
            }

            ForEach(Array(dashboard.groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Divider()
                        .overlay(.white.opacity(0.045))
                        .padding(.vertical, 4)
                }
                AgentProjectSection(
                    group: group,
                    layout: layout,
                    showsUsage: showsUsage,
                    approvalControl: approvalControl,
                    reduceMotion: reduceMotion
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentGlobalSummaryStrip: View {
    let metrics: [AgentGlobalUsagePresentation]
    let layout: AgentDashboardLayoutProjection

    var body: some View {
        HStack(spacing: layout.isNarrow ? 14 : 22) {
            ForEach(metrics) { metric in
                AgentUsageGauge(metric: metric)
                    .frame(maxWidth: layout.isNarrow ? .infinity : nil, alignment: .leading)
            }
            if !layout.isNarrow {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.white.opacity(0.025))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent usage summary")
    }
}

private struct AgentUsageGauge: View {
    let metric: AgentGlobalUsagePresentation

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 4)
                if let progress = metric.metric.progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.white.opacity(0.88),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: AgentVisualStyle.providerSymbol(metric.provider))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.provider.stableName.capitalized)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.50))
                Text(metric.metric.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(gaugeValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .monospacedDigit()
                    .lineLimit(1)
                if metric.metric.isStale {
                    Label("Stale", systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .help("Source: " + String(metric.metric.sample.source.prefix(120)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.provider.stableName), \(metric.metric.label), \(gaugeValue)\(metric.metric.isStale ? ", stale" : "")")
    }

    private var gaugeValue: String {
        if let progress = metric.metric.progress {
            return "\(Int((progress * 100).rounded()))%"
        }
        return metric.metric.sample.value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct AgentProjectSection: View {
    let group: AgentProjectGroupPresentation
    let layout: AgentDashboardLayoutProjection
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentProjectHeader(group: group)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

            ForEach(Array(group.sessions.enumerated()), id: \.element.id) { index, session in
                Group {
                    if AgentSessionPresentation.requiresAttention(session) {
                        AgentAttentionSessionRow(
                            session: session,
                            layout: layout,
                            showsUsage: showsUsage,
                            approvalControl: approvalControl
                        )
                    } else {
                        AgentSessionRow(
                            session: session,
                            layout: layout,
                            showsUsage: showsUsage,
                            approvalControl: approvalControl
                        )
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

                if index < group.sessions.count - 1 {
                    Divider()
                        .overlay(.white.opacity(0.035))
                        .padding(.leading, 42)
                }
            }
        }
    }
}

private struct AgentProjectHeader: View {
    let group: AgentProjectGroupPresentation

    var body: some View {
        HStack(spacing: 9) {
            Text(group.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.middle)
            Label("\(group.sessions.count)", systemImage: "rectangle.stack")
            if group.subagentCount > 0 {
                Label("\(group.subagentCount)", systemImage: "point.3.connected.trianglepath.dotted")
            }
            Spacer(minLength: 8)
        }
        .font(.system(size: 8.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.46))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title), \(group.sessions.count) sessions, \(group.subagentCount) subagents")
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession
    let layout: AgentDashboardLayoutProjection
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentStateMarker(session: session)
            AgentSessionRowContent(
                session: session,
                layout: layout,
                attention: false,
                approvalControl: approvalControl
            )
            Spacer(minLength: 8)
            AgentSessionTrailingStatus(session: session, layout: layout, showsUsage: showsUsage)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(isHovering ? Color.white.opacity(0.045) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sessionTitle), \(AgentSessionPresentation.stateLabel(session.state)), \(session.id.sessionID.provider.stableName)")
    }

    private var sessionTitle: String {
        AgentSessionPresentation.primaryTitle(for: session)
    }
}

private struct AgentAttentionSessionRow: View {
    let session: AgentSession
    let layout: AgentDashboardLayoutProjection
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(AgentVisualStyle.accent(for: session.state))
                .frame(width: 3)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 10) {
                AgentStateMarker(session: session, emphasized: true)
                AgentSessionRowContent(
                    session: session,
                    layout: layout,
                    attention: true,
                    approvalControl: approvalControl
                )
                Spacer(minLength: 8)
                AgentSessionTrailingStatus(session: session, layout: layout, showsUsage: showsUsage)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 11)
        }
        .background(AgentVisualStyle.attentionSurfaceTint(for: session.state).opacity(0.18))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AgentVisualStyle.attentionSurfaceTint(for: session.state).opacity(0.24))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Attention required, \(AgentSessionPresentation.stateLabel(session.state)), \(sessionTitle)")
    }

    private var sessionTitle: String {
        session.recentActivity.last?.title ?? AgentSessionPresentation.stateLabel(session.state)
    }
}

private struct AgentStateMarker: View {
    let session: AgentSession
    var emphasized = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AgentVisualStyle.providerAccent(session.id.sessionID.provider).opacity(emphasized ? 0.18 : 0.10))
            Image(systemName: AgentSessionPresentation.stateSymbol(session.state))
                .font(.system(size: emphasized ? 12 : 10, weight: .bold))
                .foregroundStyle(AgentVisualStyle.accent(for: session.state))
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel("\(session.id.sessionID.provider.stableName), \(AgentSessionPresentation.stateLabel(session.state))")
    }
}

private struct AgentSessionRowContent: View {
    let session: AgentSession
    let layout: AgentDashboardLayoutProjection
    let attention: Bool
    @ObservedObject var approvalControl: AgentApprovalController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: attention ? 12.5 : 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if session.capabilities.contains(.verifiedSourceIdentity), session.source != .unknown {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Verified source")
                }
            }

            HStack(spacing: 5) {
                Image(systemName: AgentVisualStyle.providerSymbol(session.id.sessionID.provider))
                if let branch = session.project.gitBranch, !branch.isEmpty {
                    Label(branch, systemImage: "arrow.triangle.branch")
                }
                Text(session.id.sessionID.provider.stableName.capitalized)
                if layout.showsModel, let model = session.project.model, !model.isEmpty {
                    Text("·")
                    Text(model)
                }
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.48))
            .lineLimit(1)

            if attention {
                Text(attentionDetail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(2)
            }

            if let actionableApproval {
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        approvalControl.resolve(
                            session: session.id,
                            requestID: actionableApproval.key.requestID,
                            decision: .deny
                        )
                    } label: {
                        Label("Deny", systemImage: "xmark.circle.fill")
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Deny this Codex permission request once")

                    Button {
                        approvalControl.resolve(
                            session: session.id,
                            requestID: actionableApproval.key.requestID,
                            decision: .allow
                        )
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Approve this Codex permission request once")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white.opacity(0.84))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Codex approval controls")
            }

            let operations = AgentOperationAggregation.make(
                for: session,
                includePendingApprovals: !(attention && session.state == .waitingForApproval)
            )
            if !operations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(operations.prefix(layout.isNarrow ? 3 : 6)) { operation in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: operation.symbol)
                                .frame(width: 11)
                            Text(operation.displayTitle)
                                .fontDesign(operation.isCommand ? .monospaced : .default)
                                .lineLimit(1)
                            if let detail = operation.detail, !detail.isEmpty {
                                Text(detail)
                                    .fontDesign(operation.isCommand ? .monospaced : .default)
                                    .foregroundStyle(.white.opacity(0.42))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(activityColor(operation.status))
                    }
                }
                .font(.system(size: 8.5, weight: .medium))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Live agent activity")
            }

            if attention, let target = AgentSourceAssociationResolver.openTarget(for: session) {
                Button {
                    _ = AppLaunchService.openApp(bundleIdentifier: target.bundleIdentifier)
                } label: {
                    Label("Continue in \(target.displayName)", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 8.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.12), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.88))
                .help("Open the verified source application")
                .accessibilityLabel("Open verified source application \(target.displayName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        AgentSessionPresentation.primaryTitle(for: session)
    }

    private var attentionDetail: String {
        AgentSessionPresentation.attentionDetail(for: session)
    }

    private var actionableApproval: AgentApprovalControlRequest? {
        guard attention else { return nil }
        let pending = approvalControl.pendingRequest(for: session.id)
        return AgentApprovalPresentation.isActionable(session: session, pending: pending) ? pending : nil
    }

    private func activityColor(_ status: AgentOperationStatus) -> Color {
        switch status {
        case .active: return .white.opacity(0.90)
        case .pending: return .orange.opacity(0.92)
        case .failed: return .red.opacity(0.88)
        case .completed, .resolved: return .white.opacity(0.48)
        case .cancelled, .unknown: return .white.opacity(0.40)
        }
    }
}

private struct AgentSessionTrailingStatus: View {
    let session: AgentSession
    let layout: AgentDashboardLayoutProjection
    let showsUsage: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let metric = progressMetric, let progress = metric.progress {
                HStack(spacing: 6) {
                    AgentProgressRail(progress: progress)
                        .frame(width: layout.isNarrow ? 36 : 48, height: 4)
                        .accessibilityLabel("\(metric.label) usage")
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            Label(
                AgentSessionPresentation.shortStateLabel(session.state),
                systemImage: AgentSessionPresentation.stateSymbol(session.state)
            )
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(AgentVisualStyle.accent(for: session.state))
            .lineLimit(1)

            Text(session.lastUpdatedAt, style: .relative)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.30))
                .lineLimit(1)
        }
        .frame(width: layout.trailingColumnWidth, alignment: .trailing)
    }

    private var progressMetric: AgentUsagePresentation? {
        guard showsUsage else { return nil }
        return AgentUsagePresentation.make(for: session).first { $0.progress != nil }
    }
}

private struct AgentProgressRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.11))
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.72))
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
    }
}

struct AgentCompactSessionIndicator: View {
    let session: AgentSession

    var body: some View {
        Image(systemName: AgentSessionPresentation.stateSymbol(session.state))
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(AgentVisualStyle.accent(for: session.state))
            .frame(width: 15, height: 15)
            .background(AgentVisualStyle.providerAccent(session.id.sessionID.provider).opacity(0.16), in: Circle())
            .overlay {
                Circle().stroke(AgentVisualStyle.providerAccent(session.id.sessionID.provider).opacity(0.45), lineWidth: 1)
            }
            .accessibilityLabel("\(session.id.sessionID.provider.stableName.capitalized), \(AgentSessionPresentation.stateLabel(session.state))")
    }
}

struct AgentCompactMarkerCluster: View {
    let presentation: AgentCompactPresentation

    var body: some View {
        HStack(spacing: 3) {
            ForEach(presentation.sessions, id: \.id) { session in
                AgentCompactSessionIndicator(session: session)
            }
            if presentation.overflowCount > 0 {
                Text("+\(presentation.overflowCount)")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AgentCompactSummaryLabel: View {
    let presentation: AgentCompactPresentation

    var body: some View {
        Text(presentation.summary)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.90))
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel(presentation.summary)
    }
}

struct AgentCompactOverviewView: View {
    let presentation: AgentCompactPresentation

    var body: some View {
        HStack(spacing: 7) {
            AgentCompactMarkerCluster(presentation: presentation)
            Spacer(minLength: 6)
            AgentCompactSummaryLabel(presentation: presentation)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.summary)
    }
}

struct AgentCompactAttentionLeadingView: View {
    let provider: AgentProvider
    let project: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: AgentVisualStyle.providerSymbol(provider))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AgentVisualStyle.providerAccent(provider))
            Text(project.flatMap { $0.isEmpty ? nil : $0 } ?? provider.stableName.capitalized)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct AgentCompactAttentionTrailingView: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent)
            Text(text)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
