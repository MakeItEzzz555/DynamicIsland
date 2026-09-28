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
        AgentProviderVisualIdentity.resolve(provider).systemSymbolName
    }
}

struct AgentProviderVisualIdentity: Equatable, Sendable {
    let systemSymbolName: String
    let accessibilityName: String

    static func resolve(_ provider: AgentProvider) -> Self {
        switch provider {
        case .codex:
            return Self(systemSymbolName: "sparkles", accessibilityName: "Codex")
        case .claude:
            return Self(systemSymbolName: "brain.head.profile", accessibilityName: "Claude")
        case .other:
            return Self(systemSymbolName: "cube", accessibilityName: "Agent provider")
        }
    }
}

private extension AgentVisualStyle {

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
    @ObservedObject var managedControl: AgentManagedSessionController
    @ObservedObject var layoutStore: IslandLayoutStore
    let availableHeight: CGFloat

    var body: some View {
        let visibleSessions = agentEvents.sessions.filter(managedControl.shouldPresent)
        AgentDashboardContentView(
            sessions: visibleSessions,
            accountUsage: managedControl.accountUsage,
            showsUsage: settings.agentUsageMetricsEnabled,
            approvalControl: approvalControl,
            managedControl: managedControl,
            layoutStore: layoutStore,
            availableHeight: availableHeight
        )
    }
}

struct AgentDashboardContentView: View {
    let sessions: [AgentSession]
    let accountUsage: AgentUsage
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController
    @ObservedObject var managedControl: AgentManagedSessionController
    var layoutStore: IslandLayoutStore? = nil
    let availableHeight: CGFloat
    private let initialSelectedSessionID: AgentSessionInstanceID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        sessions: [AgentSession],
        accountUsage: AgentUsage = AgentUsage(),
        showsUsage: Bool,
        approvalControl: AgentApprovalController,
        managedControl: AgentManagedSessionController,
        layoutStore: IslandLayoutStore? = nil,
        availableHeight: CGFloat,
        initialSelectedSessionID: AgentSessionInstanceID? = nil
    ) {
        self.sessions = sessions
        self.accountUsage = accountUsage
        self.showsUsage = showsUsage
        _approvalControl = ObservedObject(wrappedValue: approvalControl)
        _managedControl = ObservedObject(wrappedValue: managedControl)
        self.layoutStore = layoutStore
        self.availableHeight = availableHeight
        self.initialSelectedSessionID = initialSelectedSessionID
    }

    var body: some View {
        GeometryReader { proxy in
            let controlSessions = (managedControl.selectedProvider ?? managedControl.managedProvider).map { provider in
                sessions.filter { $0.id.sessionID.provider == provider }
            } ?? sessions
            let layout = AgentDashboardLayoutProjection.make(width: proxy.size.width)
            let verticalLayout = AgentWorkspaceVerticalLayoutProjection.make(
                availableHeight: proxy.size.height
            )
            let selectedSession = AgentWorkspaceSelection.session(
                current: managedControl.selectedSessionID,
                sessions: controlSessions,
                activeManagedSessionIDs: managedControl.activeManagedSessionIDs
            )
            let metrics = showsUsage
                ? AgentGlobalUsagePresentation.makeForSelectedSession(
                    provider: managedControl.managedProvider ?? .codex,
                    accountUsage: accountUsage,
                    selectedSession: selectedSession,
                    limit: layout.maximumGaugeCount
                )
                : []
            VStack(alignment: .leading, spacing: 10) {
                if showsUsage {
                    AgentGlobalSummaryStrip(metrics: metrics, layout: layout)
                }

                if controlSessions.isEmpty {
                    AgentEmptyConsoleState(managedControl: managedControl)
                } else {
                    AgentCLIControlBar(
                        sessions: controlSessions,
                        managedControl: managedControl,
                        approvalControl: approvalControl
                    )

                    if let pending = approvalControl.nextPendingRequest(),
                       pending.key.session != selectedSession?.id,
                       let approvalSession = sessions.first(where: { $0.id == pending.key.session }) {
                        AgentConsoleApprovalRow(
                            request: pending,
                            session: approvalSession,
                            approvalControl: approvalControl
                        )
                    }

                    if let selectedSession {
                        AgentSelectedSessionControlView(
                            session: selectedSession,
                            managedControl: managedControl,
                            approvalControl: approvalControl,
                            detailHeight: max(verticalLayout.selectedDetailHeight, 138),
                            activityLimit: max(verticalLayout.selectedDetailActivityLimit, 6),
                            layoutStore: layoutStore
                        )
                        .layoutPriority(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: availableHeight, alignment: .topLeading)
        .foregroundStyle(.white)
        .onChange(of: sessions.map(\.id)) { _, _ in
            managedControl.reconcileSelection(with: sessions)
        }
        .onAppear {
            if managedControl.selectedSessionID == nil,
               let initialSelectedSessionID {
                managedControl.selectSession(initialSelectedSessionID)
            }
            managedControl.reconcileSelection(with: sessions)
        }
        .onDisappear {
            layoutStore?.setExpandedContentScrollRegion(.zero)
        }
    }
}

private struct AgentCLIControlBar: View {
    let sessions: [AgentSession]
    @ObservedObject var managedControl: AgentManagedSessionController
    @ObservedObject var approvalControl: AgentApprovalController

    private var selectedSession: AgentSession? {
        AgentWorkspaceSelection.session(
            current: managedControl.selectedSessionID,
            sessions: sessions,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs
        )
    }

    private var groupedSessions: [AgentProjectGroupPresentation] {
        let ordered = AgentWorkspaceSelection.ordered(
            sessions: sessions,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs
        )
        return AgentDashboardPresentation.make(orderedSessions: ordered).groups
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls(compact: false)
                .fixedSize(horizontal: true, vertical: false)
            controls(compact: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent console controls")
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 8) {
            providerMenu(compact: compact)
            sessionMenu(compact: compact)
                .layoutPriority(2)

            if let session = selectedSession {
                Spacer(minLength: compact ? 2 : 6)
                modelControl(for: session, compact: compact)
                approvalPolicyControl(for: session, compact: compact)
                statusControl(for: session, compact: compact)

                if managedControl.mode(for: session).canInterrupt {
                    Button {
                        managedControl.interrupt(session)
                    } label: {
                        adaptiveLabel("Stop", systemImage: "stop.fill", compact: compact)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.86))
                    .help("Interrupt the exact active managed turn")
                    .accessibilityLabel("Stop active agent turn")
                }
            }
        }
    }

    private func providerMenu(compact: Bool) -> some View {
        let provider = selectedSession?.id.sessionID.provider ?? managedControl.managedProvider ?? .other("agent")
        return Menu {
            ForEach(managedControl.managedProviders, id: \.self) { supported in
                Button {
                    managedControl.selectProvider(supported)
                    managedControl.reconcileSelection(with: sessions)
                } label: {
                    Label(
                        supported.stableName.capitalized,
                        systemImage: supported == provider ? "checkmark" : AgentVisualStyle.providerSymbol(supported)
                    )
                }
            }
        } label: {
            adaptiveLabel(
                provider.stableName.capitalized,
                systemImage: AgentVisualStyle.providerSymbol(provider),
                compact: compact
            )
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .menuStyle(.borderlessButton)
        .help("Managed agent provider")
    }

    private func sessionMenu(compact: Bool) -> some View {
        Menu {
            ForEach(groupedSessions) { group in
                Section("\(group.title) (\(group.sessions.count))") {
                    ForEach(group.sessions, id: \.id) { session in
                        Button {
                            managedControl.selectSession(session.id)
                        } label: {
                            Label(
                                sessionMenuTitle(session),
                                systemImage: selectorStateSymbol(session)
                            )
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedSession.map(selectedSessionLabel) ?? "Choose session")
                    .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.86))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func modelControl(for session: AgentSession, compact: Bool) -> some View {
        let provider = session.id.sessionID.provider
        let models = managedControl.availableModels(for: session)
        if managedControl.capabilities(for: provider).contains(.selectModel),
           !models.isEmpty {
            Menu {
                Button("Use thread model") {
                    managedControl.selectModel(nil, for: session)
                }
                Divider()
                ForEach(models) { option in
                    Button {
                        managedControl.selectModel(option.model, for: session)
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if option.model == (
                                managedControl.pendingModel(for: session) ??
                                managedControl.selectedModel(for: session)
                            ) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    if compact { Image(systemName: "cpu") }
                    Text(modelLabel(for: session))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6.5, weight: .semibold))
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))
            }
            .menuStyle(.borderlessButton)
            .disabled(!managedControl.canSelectModel(for: session))
            .help(
                managedControl.canSelectModel(for: session)
                    ? modelSelectionHelp(for: session)
                    : "Model changes are unavailable while a turn is active or submitting"
            )
        } else if !compact {
            Text(modelLabel(for: session))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.40))
                .lineLimit(1)
        }
    }

    private func modelSelectionHelp(for session: AgentSession) -> String {
        switch managedControl.modelSelectionScope(for: session) {
        case .turnAndSubsequent:
            "Applies to the next turn and subsequent turns in this thread"
        case nil:
            "Thread model"
        }
    }

    @ViewBuilder
    private func approvalPolicyControl(for session: AgentSession, compact: Bool) -> some View {
        let provider = session.id.sessionID.provider
        if managedControl.isManaged(session),
           managedControl.capabilities(for: provider).contains(.resolveApprovals),
           session.capabilities.contains(.approvalControl) {
            let policy = managedControl.approvalPolicy(for: session)
            Menu {
                Button {
                    managedControl.setApprovalPolicyChoice(.askEveryTime, for: session)
                } label: {
                    Label(
                        "Ask every time",
                        systemImage: policy == .askEveryTime ? "checkmark" : "hand.raised"
                    )
                }

                Button {
                    managedControl.setApprovalPolicyChoice(.autoApprove, for: session)
                } label: {
                    Label(
                        "Auto approve",
                        systemImage: policy == .autoApprove ? "checkmark" : "bolt.shield"
                    )
                }
            } label: {
                adaptiveLabel(
                    policy.isAutomatic ? "Auto" : "Ask",
                    systemImage: policy.isAutomatic ? "bolt.fill" : "hand.raised",
                    compact: compact
                )
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(
                    policy.isAutomatic
                        ? Color.orange.opacity(0.92)
                        : Color.white.opacity(0.48)
                )
            }
            .menuStyle(.borderlessButton)
            .help(policy.isAutomatic ? "Auto-approval enabled: \(policy.displayName)" : "Approval policy")
            .accessibilityLabel("Approval policy: \(policy.displayName)")
        }
    }

    private func statusControl(for session: AgentSession, compact: Bool) -> some View {
        adaptiveLabel(
            selectorStateLabel(session),
            systemImage: selectorStateSymbol(session),
            compact: compact
        )
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(
            (managedControl.activeManagedSessionIDs.contains(session.id.sessionID)
                ? Color.green
                : AgentVisualStyle.accent(for: session.state)).opacity(0.82)
        )
        .help(selectorStateLabel(session))
    }

    @ViewBuilder
    private func adaptiveLabel(
        _ title: String,
        systemImage: String,
        compact: Bool
    ) -> some View {
        if compact {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
        }
    }

    private func sessionLabel(_ session: AgentSession) -> String {
        let project = AgentPrivacyProjection.displayProject(session.project)
        if let displayName = project.displayName, !displayName.isEmpty {
            return displayName
        }
        return AgentSessionPresentation.primaryTitle(for: session)
    }

    private func selectedSessionLabel(_ session: AgentSession) -> String {
        "\(sessionLabel(session)) · \(threadSuffix(session))"
    }

    private func modelLabel(for session: AgentSession) -> String {
        if let authoritative = managedControl.selectedModel(for: session),
           let option = managedControl.availableModels(for: session).first(where: { $0.model == authoritative }) {
            if let pending = managedControl.pendingModel(for: session), pending != authoritative,
               let pendingOption = managedControl.availableModels(for: session).first(where: { $0.model == pending }) {
                return "\(option.displayName) → \(pendingOption.displayName)"
            }
            return option.displayName
        }
        if let pending = managedControl.pendingModel(for: session),
           let pendingOption = managedControl.availableModels(for: session).first(where: { $0.model == pending }) {
            return "Next: \(pendingOption.displayName)"
        }
        return managedControl.selectedModel(for: session) ?? "Model unavailable"
    }

    private func sessionMenuTitle(_ session: AgentSession) -> String {
        let state = selectorStateLabel(session)
        let model = modelLabel(for: session)
        let recency = RelativeDateTimeFormatter().localizedString(
            for: session.lastUpdatedAt,
            relativeTo: Date()
        )
        return "\(state) · \(model) · \(recency) · \(threadSuffix(session))"
    }

    private func threadSuffix(_ session: AgentSession) -> String {
        "…" + session.id.sessionID.nativeID.suffix(4)
    }

    private func selectorStateLabel(_ session: AgentSession) -> String {
        if managedControl.activeManagedSessionIDs.contains(session.id.sessionID) {
            switch session.state {
            case .waitingForApproval, .waitingForUser, .thinking, .planning,
                 .working, .runningTool, .runningCommand, .planReady:
                break
            case .idle, .completed, .failed, .interrupted:
                return "Working"
            }
        }
        return AgentSessionPresentation.displayedStateLabel(for: session, at: Date())
    }

    private func selectorStateSymbol(_ session: AgentSession) -> String {
        if managedControl.activeManagedSessionIDs.contains(session.id.sessionID) {
            return "circle.fill"
        }
        return AgentSessionPresentation.displayedStateSymbol(for: session, at: Date())
    }
}

private struct AgentSelectedSessionControlView: View {
    let session: AgentSession
    @ObservedObject var managedControl: AgentManagedSessionController
    @ObservedObject var approvalControl: AgentApprovalController
    let detailHeight: CGFloat
    let activityLimit: Int
    let layoutStore: IslandLayoutStore?

    var body: some View {
        if managedControl.isManaged(session), managedControl.mode(for: session).showsComposer {
            AgentEmbeddedConsoleView(
                session: session,
                mode: managedControl.mode(for: session),
                maximumActivityEntries: activityLimit,
                transcriptEntries: managedControl.transcript(for: session),
                layoutStore: layoutStore,
                approvalControl: approvalControl,
                onSubmit: { await managedControl.submit($0, for: session) },
                onInterrupt: { managedControl.interrupt(session) }
            )
            .frame(minHeight: detailHeight, maxHeight: .infinity)
            .task(id: session.id) {
                await managedControl.refreshTranscript(for: session)
            }
        } else {
            VStack(spacing: 5) {
                if managedControl.supportsManagedControl(for: session) {
                    HStack(spacing: 8) {
                        Image(systemName: "link.badge.plus")
                            .foregroundStyle(.white.opacity(0.50))
                        Text(session.availability == .resumable
                            ? "Resumable \(providerName(session)) session"
                            : "Observed \(providerName(session)) session")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        if let status = managedControl.statusMessage(for: session) {
                            Text(status)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.orange.opacity(0.78))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if managedControl.canConnect(session) ||
                            managedControl.connecting.contains(session.id.sessionID) {
                            Button {
                                managedControl.connect(session)
                            } label: {
                                Label(
                                    managedControl.connecting.contains(session.id.sessionID)
                                        ? "Connecting…"
                                        : (session.availability == .resumable ? "Resume" : "Control"),
                                    systemImage: "terminal"
                                )
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 8.5, weight: .semibold))
                            .disabled(!managedControl.canConnect(session))
                            .help("Resume this provider session through its managed control plane")
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(.white.opacity(0.022))
                    .accessibilityElement(children: .contain)
                }

                AgentEmbeddedConsoleView(
                    session: session,
                    mode: .observed,
                    maximumActivityEntries: activityLimit,
                    transcriptEntries: managedControl.transcript(for: session),
                    layoutStore: layoutStore,
                    approvalControl: approvalControl,
                    onSubmit: { _ in false },
                    onInterrupt: {}
                )
                .frame(minHeight: max(detailHeight - 31, 104), maxHeight: .infinity)
            }
            .task(id: session.id) {
                await managedControl.reconcileObservedSession(session)
            }
        }
    }

    private func providerName(_ session: AgentSession) -> String {
        session.id.sessionID.provider.stableName.capitalized
    }
}

private struct AgentEmptyConsoleState: View {
    @ObservedObject var managedControl: AgentManagedSessionController
    @State private var starting = false

    var body: some View {
        let provider = managedControl.managedProvider ?? .other("agent")
        let providerName = provider.stableName.capitalized
        VStack(spacing: 10) {
            Image(systemName: AgentVisualStyle.providerSymbol(provider))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
            Text("No \(providerName) session")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            Text("Start a managed session to use the embedded agent console.")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))

            if let status = managedControl.lastTransportError {
                Label(status, systemImage: "exclamationmark.circle")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.78))
                    .lineLimit(2)
            }

            if managedControl.interactiveCapabilities.contains(.startSession) {
                if managedControl.interactiveCapabilities.contains(.selectModel),
                   !managedControl.availableModels.isEmpty {
                    Menu {
                        Button("Provider default") {
                            _ = managedControl.selectNewSessionModel(nil, for: provider)
                        }
                        Divider()
                        ForEach(managedControl.availableModels) { option in
                            Button {
                                _ = managedControl.selectNewSessionModel(option.model, for: provider)
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                    if managedControl.newSessionModel(for: provider) == option.model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(
                            managedControl.newSessionModel(for: provider).flatMap { selected in
                                managedControl.availableModels.first(where: { $0.model == selected })?.displayName
                            } ?? "Provider default model",
                            systemImage: "cpu"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .font(.system(size: 8.5, weight: .medium))
                }

                Button {
                    guard !starting else { return }
                    starting = true
                    Task { @MainActor in
                        _ = await managedControl.startNewSession(cwd: nil)
                        starting = false
                    }
                } label: {
                    Label(starting ? "Starting…" : "New session", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(starting)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No \(providerName) session")
    }
}

private struct AgentStandbyUsageGauge: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 4)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.74))
                Text("—")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
                Text("Waiting for data")
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
        .help("No trustworthy live value has been received for this metric.")
    }
}

struct AgentDashboardStack: View {
    let sessions: [AgentSession]
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController
    let layout: AgentDashboardLayoutProjection
    let reduceMotion: Bool

    var body: some View {
        let metrics = showsUsage
            ? AgentGlobalUsagePresentation.make(sessions: sessions, limit: layout.maximumGaugeCount)
            : []

        VStack(alignment: .leading, spacing: 0) {
            if showsUsage {
                AgentGlobalSummaryStrip(metrics: metrics, layout: layout)
                    .padding(.bottom, 11)
            }
            AgentDashboardGroups(
                sessions: sessions,
                showsUsage: showsUsage,
                approvalControl: approvalControl,
                layout: layout,
                reduceMotion: reduceMotion,
                selectedSessionID: .constant(
                    AgentWorkspaceSelection.resolve(current: nil, sessions: sessions)
                )
            )
        }
        .padding(.vertical, 2)
    }
}

private struct AgentDashboardGroups: View {
    let sessions: [AgentSession]
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController
    let layout: AgentDashboardLayoutProjection
    let reduceMotion: Bool
    @Binding var selectedSessionID: AgentSessionInstanceID?

    var body: some View {
        let dashboard = AgentDashboardPresentation.make(sessions: sessions)
        VStack(alignment: .leading, spacing: 0) {
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
                    reduceMotion: reduceMotion,
                    selectedSessionID: $selectedSessionID
                )
            }
        }
    }
}

private struct AgentGlobalSummaryStrip: View {
    let metrics: [AgentGlobalUsagePresentation]
    let layout: AgentDashboardLayoutProjection

    private var missingSlots: [(String, String)] {
        let labels = Set(metrics.map { $0.metric.label.lowercased() })
        let canonical: [(String, String, (String) -> Bool)] = [
            ("clock", "5h", { $0.contains("5h") }),
            ("calendar", "Week", { $0.contains("week") }),
            ("gauge.with.dots.needle.33percent", "Context", { $0 == "context" })
        ]
        let available = max(layout.maximumGaugeCount - metrics.count, 0)
        return Array(
            canonical
                .filter { entry in !labels.contains(where: entry.2) }
                .prefix(available)
                .map { ($0.0, $0.1) }
        )
    }

    var body: some View {
        HStack(spacing: layout.isNarrow ? 10 : 16) {
            ForEach(metrics) { metric in
                AgentUsageGauge(metric: metric)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            ForEach(Array(missingSlots.enumerated()), id: \.offset) { _, slot in
                AgentStandbyUsageGauge(symbol: slot.0, label: slot.1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.white.opacity(0.025))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(metrics.isEmpty ? "Usage metrics waiting for provider data" : "Agent usage summary")
    }
}

private struct AgentUsageGauge: View {
    let metric: AgentGlobalUsagePresentation

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 4)
                if let progress = metric.metric.gaugeProgress {
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
        metric.metric.gaugeValueText
    }
}

private struct AgentProjectSection: View {
    let group: AgentProjectGroupPresentation
    let layout: AgentDashboardLayoutProjection
    let showsUsage: Bool
    @ObservedObject var approvalControl: AgentApprovalController
    let reduceMotion: Bool
    @Binding var selectedSessionID: AgentSessionInstanceID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentProjectHeader(group: group)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

            sessionRows(group.primarySessions)

            if group.showsRecentSection {
                AgentRecentSessionsSeparator()
                sessionRows(group.recentSessions)
            }
        }
    }

    @ViewBuilder
    private func sessionRows(_ sessions: [AgentSession]) -> some View {
        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
            Group {
                if AgentSessionPresentation.requiresAttention(session) {
                    AgentAttentionSessionRow(
                        session: session,
                        layout: layout,
                        showsUsage: showsUsage,
                        approvalControl: approvalControl,
                        selected: selectedSessionID == session.id,
                        select: { selectedSessionID = session.id }
                    )
                } else {
                    AgentSessionRow(
                        session: session,
                        layout: layout,
                        showsUsage: showsUsage,
                        approvalControl: approvalControl,
                        selected: selectedSessionID == session.id,
                        select: { selectedSessionID = session.id }
                    )
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

            if index < sessions.count - 1 {
                Divider()
                    .overlay(.white.opacity(0.035))
                    .padding(.leading, 42)
            }
        }
    }
}

private struct AgentRecentSessionsSeparator: View {
    var body: some View {
        HStack(spacing: 7) {
            Text("Recent")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.34))
            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(height: 1)
        }
        .padding(.leading, 42)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent sessions")
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
    let selected: Bool
    let select: () -> Void
    @State private var isHovering = false

    var body: some View {
        let emphasis = AgentSessionRowEmphasis.resolve(
            session: session,
            selected: selected,
            hovering: isHovering
        )
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
        .background(
            emphasis == .selected
                ? Color.white.opacity(0.075)
                : (emphasis == .hovered ? Color.white.opacity(0.045) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if selected {
                Rectangle()
                    .fill(.white.opacity(0.62))
                    .frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sessionTitle), \(AgentSessionPresentation.displayedStateLabel(for: session, at: Date())), \(session.id.sessionID.provider.stableName)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Select session", select)
        .focusable()
        .onKeyPress(.return) {
            select()
            return .handled
        }
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
    let selected: Bool
    let select: () -> Void

    var body: some View {
        let emphasis = AgentSessionRowEmphasis.resolve(
            session: session,
            selected: selected,
            hovering: false
        )
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
        .background(
            AgentVisualStyle.attentionSurfaceTint(for: session.state)
                .opacity(emphasis == .selectedAttention ? 0.25 : 0.18)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AgentVisualStyle.attentionSurfaceTint(for: session.state).opacity(0.24))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Attention required, \(AgentSessionPresentation.stateLabel(session.state)), \(sessionTitle)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Select session", select)
        .focusable()
        .onKeyPress(.return) {
            select()
            return .handled
        }
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
            Image(systemName: AgentSessionPresentation.displayedStateSymbol(for: session, at: Date()))
                .font(.system(size: emphasized ? 12 : 10, weight: .bold))
                .foregroundStyle(AgentVisualStyle.accent(for: session.state))
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel("\(session.id.sessionID.provider.stableName), \(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))")
    }
}

private struct AgentSessionRowContent: View {
    let session: AgentSession
    let layout: AgentDashboardLayoutProjection
    let attention: Bool
    @ObservedObject var approvalControl: AgentApprovalController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(AgentSessionPresentation.displayedPrimaryTitle(for: session, at: timeline.date))
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
                    .accessibilityHint("Deny this agent permission request once")

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
                    .accessibilityHint("Approve this agent permission request once")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white.opacity(0.84))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Agent approval controls")
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
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let stale = AgentSessionPresentation.hasStaleActiveSignal(session, at: timeline.date)
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
                    AgentSessionPresentation.displayedStateLabel(for: session, at: timeline.date),
                    systemImage: AgentSessionPresentation.displayedStateSymbol(for: session, at: timeline.date)
                )
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(
                    stale
                        ? Color.white.opacity(0.44)
                        : AgentVisualStyle.accent(for: session.state)
                )
                .lineLimit(1)

                HStack(spacing: 2) {
                    Text("Last event")
                    Text(session.lastUpdatedAt, style: .relative)
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.30))
                .lineLimit(1)
            }
            .frame(width: layout.trailingColumnWidth, alignment: .trailing)
        }
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
        Image(systemName: AgentSessionPresentation.displayedStateSymbol(for: session, at: Date()))
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(AgentVisualStyle.accent(for: session.state))
            .frame(width: 15, height: 15)
            .background(AgentVisualStyle.providerAccent(session.id.sessionID.provider).opacity(0.16), in: Circle())
            .overlay {
                Circle().stroke(AgentVisualStyle.providerAccent(session.id.sessionID.provider).opacity(0.45), lineWidth: 1)
            }
            .accessibilityLabel("\(session.id.sessionID.provider.stableName.capitalized), \(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))")
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
