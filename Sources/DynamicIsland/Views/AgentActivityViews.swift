import SwiftUI

private enum AgentVisualStyle {
    static let cardRadius: CGFloat = 14
    static let sectionRadius: CGFloat = 10

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
}

struct AgentActivityDashboardView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var agentEvents: AgentEventStore
    let availableHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if agentEvents.sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 310), spacing: 10, alignment: .top)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(agentEvents.sessions.sorted(by: AgentSessionPresentation.isOrderedBefore), id: \.id) { session in
                            AgentSessionCard(
                                session: session,
                                showsUsage: settings.agentUsageMetricsEnabled,
                                reduceMotion: reduceMotion
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: availableHeight, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "cpu")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            Text("No agent sessions")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Verified Codex and Claude activity will appear here when an integration sends its first event.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct AgentSessionCard: View {
    let session: AgentSession
    let showsUsage: Bool
    let reduceMotion: Bool

    private var activeTools: [AgentTool] {
        session.tools.values.filter { $0.status == .active || $0.status == .pending }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var activeCommands: [AgentCommand] {
        session.commands.values.filter { $0.status == .active || $0.status == .pending }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var pendingApprovals: [AgentApproval] {
        session.approvals.values.filter { $0.state == .pending }
            .sorted { $0.requestedAt > $1.requestedAt }
    }

    private var visibleSubagents: [AgentSubagent] {
        session.subagents.values.sorted {
            if $0.status != $1.status { return $0.status == .active }
            return $0.startedAt > $1.startedAt
        }
    }

    private var recentOperations: [AgentOperationPresentation] {
        let tools = session.tools.values.compactMap { tool -> AgentOperationPresentation? in
            guard tool.status != .active, tool.status != .pending else { return nil }
            return AgentOperationPresentation(
                id: "tool:\(tool.correlationID.rawValue)",
                symbol: "wrench.and.screwdriver",
                title: tool.name,
                detail: tool.summary,
                status: tool.status,
                date: tool.completedAt ?? tool.startedAt
            )
        }
        let commands = session.commands.values.compactMap { command -> AgentOperationPresentation? in
            guard command.status != .active, command.status != .pending else { return nil }
            return AgentOperationPresentation(
                id: "command:\(command.correlationID.rawValue)",
                symbol: "terminal",
                title: command.displaySummary,
                detail: command.exitCode.map { "Exit \($0)" },
                status: command.status,
                date: command.completedAt ?? command.startedAt
            )
        }
        return Array((tools + commands).sorted { $0.date > $1.date }.prefix(3))
    }

    private var hasOperations: Bool {
        !activeTools.isEmpty || !activeCommands.isEmpty || !pendingApprovals.isEmpty ||
            !visibleSubagents.isEmpty || !recentOperations.isEmpty
    }

    private var showsAttention: Bool {
        switch session.state {
        case .waitingForApproval, .waitingForUser, .failed, .interrupted, .planReady: true
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            AgentPrimaryStateRow(session: session)

            if showsAttention {
                attentionSection
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            if hasOperations {
                sectionLabel("Operations")
                operations
            }

            metadata

            if showsUsage, hasVisibleUsage {
                usage
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: AgentVisualStyle.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AgentVisualStyle.cardRadius, style: .continuous)
                .stroke(.white.opacity(0.075), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(session.id.sessionID.provider.stableName.capitalized)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(AgentVisualStyle.providerAccent(session.id.sessionID.provider))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AgentVisualStyle.providerAccent(session.id.sessionID.provider).opacity(0.13), in: Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(session.project.displayName ?? "Agent session")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let model = session.project.model, !model.isEmpty {
                    Text(model)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 5)
            AgentStatusBadge(state: session.state)
        }
    }

    private var attentionSection: some View {
        let content: (String, String, String) = switch session.state {
        case .waitingForApproval:
            ("Approval requested", pendingApprovals.first?.summary ?? "The provider is waiting for an approval decision.", "checkmark.shield.fill")
        case .waitingForUser:
            ("Waiting for input", "The session cannot continue until the user responds.", "person.crop.circle.badge.questionmark")
        case .failed:
            ("Session failed", session.recentActivity.last?.summary ?? "The provider reported a failure.", "xmark.octagon.fill")
        case .interrupted:
            ("Session interrupted", session.recentActivity.last?.summary ?? "The provider reported an interruption.", "stop.circle.fill")
        case .planReady:
            ("Plan ready", session.recentActivity.last?.summary ?? "The provider reported that a plan is ready.", "list.bullet.clipboard.fill")
        default:
            ("Attention", "This session needs attention.", "exclamationmark.circle.fill")
        }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: content.2)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.0)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                Text(content.1)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(AgentVisualStyle.accent(for: session.state))
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AgentVisualStyle.accent(for: session.state).opacity(0.11), in: RoundedRectangle(cornerRadius: AgentVisualStyle.sectionRadius, style: .continuous))
    }

    @ViewBuilder
    private var operations: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(pendingApprovals.prefix(2)), id: \.requestID) { approval in
                AgentOperationRow(symbol: "checkmark.shield", title: approval.summary, detail: "Pending approval", status: .pending)
            }
            ForEach(Array(activeTools.prefix(2)), id: \.correlationID) { tool in
                AgentOperationRow(symbol: "wrench.and.screwdriver", title: tool.name, detail: tool.summary, status: tool.status)
            }
            ForEach(Array(activeCommands.prefix(2)), id: \.correlationID) { command in
                AgentOperationRow(symbol: "terminal", title: command.displaySummary, detail: nil, status: command.status)
            }
            ForEach(Array(visibleSubagents.prefix(2)), id: \.correlationID) { subagent in
                AgentOperationRow(
                    symbol: "person.2",
                    title: subagent.displayName ?? "Subagent",
                    detail: subagent.status == .active ? "Active" : "\(subagent.status.rawValue.capitalized)",
                    status: subagent.status
                )
            }
            ForEach(recentOperations) { operation in
                AgentOperationRow(
                    symbol: operation.symbol,
                    title: operation.title,
                    detail: operation.detail,
                    status: operation.status
                )
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("Session")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    AgentMetadataChip(symbol: "cpu", text: session.id.sessionID.provider.stableName.capitalized)
                    if let project = session.project.displayName, !project.isEmpty {
                        AgentMetadataChip(symbol: "folder", text: project)
                    }
                    if let repo = session.project.repositoryIdentity, !repo.isEmpty {
                        AgentMetadataChip(symbol: "externaldrive", text: repo)
                    }
                    if let branch = session.project.gitBranch, !branch.isEmpty {
                        AgentMetadataChip(symbol: "arrow.triangle.branch", text: branch)
                    }
                    if let model = session.project.model, !model.isEmpty {
                        AgentMetadataChip(symbol: "brain", text: model)
                    }
                    if session.capabilities.contains(.verifiedSourceIdentity), session.source != .unknown {
                        AgentMetadataChip(symbol: "checkmark.seal.fill", text: verifiedSourceLabel)
                    }
                }
            }

            if let openTarget = AgentSourceAssociationResolver.openTarget(for: session) {
                Button {
                    _ = AppLaunchService.openApp(bundleIdentifier: openTarget.bundleIdentifier)
                } label: {
                    Label("Open \(openTarget.displayName)", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.76))
                .accessibilityLabel("Open verified source application \(openTarget.displayName)")
            }
        }
    }

    @ViewBuilder
    private var usage: some View {
        sectionLabel("Usage")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], spacing: 6) {
            ForEach(usageMetrics) { metric in
                AgentUsageMetricView(metric: metric)
            }
        }
    }

    private var usageMetrics: [AgentUsagePresentation] {
        AgentUsagePresentation.make(for: session)
    }

    private var hasVisibleUsage: Bool { !usageMetrics.isEmpty }

    private var verifiedSourceLabel: String {
        if let name = session.project.sourceApplication?.displayName, !name.isEmpty { return name }
        return session.source.rawValue.capitalized
    }

    private var accessibilityLabel: String {
        "\(session.id.sessionID.provider.stableName.capitalized), \(session.project.displayName ?? "agent session"), \(AgentSessionPresentation.stateLabel(session.state))"
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}

struct AgentStatusBadge: View {
    let state: AgentState

    var body: some View {
        Label(AgentSessionPresentation.shortStateLabel(state), systemImage: AgentSessionPresentation.stateSymbol(state))
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(AgentVisualStyle.accent(for: state))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AgentVisualStyle.accent(for: state).opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(AgentSessionPresentation.stateLabel(state))")
    }
}

struct AgentPrimaryStateRow: View {
    let session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: AgentSessionPresentation.stateSymbol(session.state))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AgentVisualStyle.accent(for: session.state))
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(AgentSessionPresentation.stateLabel(session.state))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                if let current = session.recentActivity.last {
                    Text(current.summary ?? current.title)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Text(session.lastUpdatedAt, style: .relative)
                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }
}

struct AgentOperationRow: View {
    let symbol: String
    let title: String
    let detail: String?
    let status: AgentOperationStatus

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 13)
            Text(title)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 7.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: statusSymbol)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(statusColor)
                .accessibilityLabel(status.rawValue.capitalized)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusColor: Color {
        switch status {
        case .failed: .red
        case .cancelled: .yellow
        case .active, .pending: .cyan
        case .completed, .resolved: .green
        case .unknown: .secondary
        }
    }

    private var statusSymbol: String {
        switch status {
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        case .active: "bolt.fill"
        case .pending: "clock.fill"
        case .completed, .resolved: "checkmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

struct AgentMetadataChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white.opacity(0.055), in: Capsule())
            .accessibilityLabel(text)
    }
}

struct AgentUsageMetricView: View {
    let metric: AgentUsagePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(metric.label)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if metric.isStale {
                    Label("Stale", systemImage: "clock.badge.exclamationmark")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Stale usage sample")
                }
            }
            .font(.system(size: 7.5, weight: .semibold, design: .rounded))

            Text(metric.valueText)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)

            if let progress = metric.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.cyan)
                    .accessibilityLabel("\(metric.label) usage")
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }
        }
        .padding(7)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Source: " + String(metric.sample.source.prefix(120)))
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

struct AgentCompactOverviewView: View {
    let presentation: AgentCompactPresentation

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(presentation.sessions, id: \.id) { session in
                    AgentCompactSessionIndicator(session: session)
                }
                if presentation.overflowCount > 0 {
                    Text("+\(presentation.overflowCount)")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Text(presentation.summary)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.summary)
    }
}

private struct AgentOperationPresentation: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String?
    let status: AgentOperationStatus
    let date: Date
}

struct AgentUsagePresentation: Identifiable {
    let id: String
    let label: String
    let sample: AgentUsageSample
    let effectiveLimit: Double?

    var isStale: Bool { isStale(at: Date()) }

    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(sample.observedAt) > 300
    }

    var progress: Double? {
        guard let effectiveLimit, effectiveLimit.isFinite, effectiveLimit > 0 else { return nil }
        return min(max(sample.value / effectiveLimit, 0), 1)
    }

    var valueText: String {
        let value = sample.value.formatted(.number.precision(.fractionLength(0...2)))
        guard let effectiveLimit else { return value + " " + sample.unit.rawValue }
        let limit = effectiveLimit.formatted(.number.precision(.fractionLength(0...2)))
        return value + " / " + limit + " " + sample.unit.rawValue
    }

    static func make(for session: AgentSession) -> [AgentUsagePresentation] {
        var values: [AgentUsagePresentation] = []
        if session.capabilities.contains(.contextUsage), let used = session.usage[.contextUsed] {
            let limit = used.limit ?? session.usage[.contextLimit]?.value
            values.append(.init(id: "context", label: "Context", sample: used, effectiveLimit: limit))
        }
        if session.capabilities.contains(.tokenUsage) {
            for (metric, label) in [(AgentUsageMetric.inputTokens, "Input"), (.outputTokens, "Output"), (.cachedInputTokens, "Cached"), (.reasoningTokens, "Reasoning")] {
                if let sample = session.usage[metric] {
                    values.append(.init(id: metric.rawValue, label: label, sample: sample, effectiveLimit: sample.limit))
                }
            }
        }
        if session.capabilities.contains(.quotaUsage), let used = session.usage[.quotaUsed] {
            let limit = used.limit ?? session.usage[.quotaLimit]?.value
            values.append(.init(id: "quota", label: "Quota", sample: used, effectiveLimit: limit))
        }
        if session.capabilities.contains(.quotaUsage), let remaining = session.usage[.rateLimitRemaining] {
            values.append(.init(id: "remaining", label: "Rate remaining", sample: remaining, effectiveLimit: remaining.limit))
        }
        if session.capabilities.contains(.costUsage), let cost = session.usage[.cost] {
            values.append(.init(id: "cost", label: "Cost", sample: cost, effectiveLimit: cost.limit))
        }
        return values
    }
}
