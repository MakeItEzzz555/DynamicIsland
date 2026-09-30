import AgentBridgeShared
import AppKit
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

    /// Claude brand orange (#D97757), defined once.
    static let claudeOrange = Color(red: 0.851, green: 0.467, blue: 0.341)

    static func providerAccent(_ provider: AgentProvider) -> Color {
        switch provider {
        case .codex: .cyan
        case .claude: claudeOrange
        case .other: .purple
        }
    }

    /// The installed provider app's own icon, when that app is installed.
    /// DynamicIsland bundles no third-party logos.
    @MainActor
    static func installedProviderIcon(_ provider: AgentProvider) -> NSImage? {
        let bundleID: String? = switch provider {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex, .other: nil
        }
        guard let bundleID else { return nil }
        if let cached = ProviderIconCache.icons[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        ProviderIconCache.icons[bundleID] = .some(icon)
        return icon
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

enum AgentsPagePresentationPhase: Int, Equatable, Sendable {
    case inactive
    case entering
    case chromeVisible
    case transcriptReady
}

struct AgentsPagePresentationState: Equatable, Sendable {
    private(set) var phase: AgentsPagePresentationPhase = .inactive
    private(set) var generation = 0

    @discardableResult
    mutating func begin() -> Int {
        generation &+= 1
        phase = .entering
        return generation
    }

    @discardableResult
    mutating func revealChrome(generation expected: Int) -> Bool {
        guard generation == expected, phase == .entering else { return false }
        phase = .chromeVisible
        return true
    }

    @discardableResult
    mutating func revealTranscript(generation expected: Int) -> Bool {
        guard generation == expected,
              phase == .chromeVisible || phase == .entering else { return false }
        phase = .transcriptReady
        return true
    }

    mutating func cancel() {
        generation &+= 1
        phase = .inactive
    }

    var chromeVisible: Bool {
        phase == .chromeVisible || phase == .transcriptReady
    }

    var transcriptReady: Bool {
        phase == .transcriptReady
    }
}

struct AgentTranscriptLoadGate: Equatable, Sendable {
    private(set) var requestedSessionID: AgentSessionInstanceID?
    private(set) var readySessionID: AgentSessionInstanceID?
    private(set) var generation = 0

    mutating func begin(for sessionID: AgentSessionInstanceID) -> Int {
        generation &+= 1
        requestedSessionID = sessionID
        readySessionID = nil
        return generation
    }

    @discardableResult
    mutating func complete(for sessionID: AgentSessionInstanceID, generation expected: Int) -> Bool {
        guard expected == generation, requestedSessionID == sessionID else { return false }
        readySessionID = sessionID
        return true
    }

    mutating func cancel() {
        generation &+= 1
        requestedSessionID = nil
        readySessionID = nil
    }

    func isReady(for sessionID: AgentSessionInstanceID?) -> Bool {
        sessionID != nil && readySessionID == sessionID
    }
}

struct AgentActivityDashboardView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var agentEvents: AgentEventStore
    @ObservedObject var projects: AgentProjectProjectionStore
    @ObservedObject var approvalControl: AgentApprovalController
    @ObservedObject var managedControl: AgentManagedSessionController
    @ObservedObject var layoutStore: IslandLayoutStore
    let availableHeight: CGFloat
    let contentVisible: Bool
    let isContentRemoving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation = AgentsPagePresentationState()
    @State private var presentationTask: Task<Void, Never>?

    var body: some View {
        let visibleSessions = agentEvents.sessions.filter(managedControl.shouldPresent)
        AgentDashboardContentView(
            sessions: visibleSessions,
            accountUsage: managedControl.accountUsage,
            showsUsage: settings.agentUsageMetricsEnabled,
            approvalControl: approvalControl,
            managedControl: managedControl,
            layoutStore: layoutStore,
            availableHeight: availableHeight,
            settings: settings,
            contentVisible: contentVisible && presentation.chromeVisible,
            isContentRemoving: isContentRemoving,
            reduceMotion: reduceMotion,
            transcriptPresentationReady: presentation.transcriptReady,
            presentationGeneration: presentation.generation,
            transcriptLoadDelay: reduceMotion ? 0 : 0.04
        )
        .environment(\.agentProjectLocations, projects.index)
        .environment(\.agentProjectSelection, AgentProjectSelectionBinding(
            key: projects.selectedProjectKey,
            set: { projects.selectedProjectKey = $0 }
        ))
        .onAppear {
            beginPresentation()
        }
        .onChange(of: contentVisible) { _, isVisible in
            if isVisible {
                if presentation.phase == .inactive {
                    beginPresentation()
                }
            } else {
                cancelPresentation()
            }
        }
        .onDisappear {
            cancelPresentation()
        }
    }

    private func beginPresentation() {
        presentationTask?.cancel()
        let generation = presentation.begin()
        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        let chromeDelay = reduceMotion
            ? 0
            : IslandContentTransitionTiming.expansionContentDelay(shellDuration: shellDuration)
        let transcriptDelay = max(0, shellDuration - chromeDelay)

        presentationTask = Task { @MainActor in
            if chromeDelay > 0 {
                try? await Task.sleep(for: .seconds(chromeDelay))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            _ = presentation.revealChrome(generation: generation)

            if transcriptDelay > 0 {
                try? await Task.sleep(for: .seconds(transcriptDelay))
            }
            guard !Task.isCancelled else { return }
            _ = presentation.revealTranscript(generation: generation)
        }
    }

    private func cancelPresentation() {
        presentationTask?.cancel()
        presentationTask = nil
        presentation.cancel()
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
    let settings: AppSettings?
    let contentVisible: Bool
    let isContentRemoving: Bool
    let reduceMotion: Bool
    let transcriptPresentationReady: Bool
    let presentationGeneration: Int
    let transcriptLoadDelay: TimeInterval
    private let initialSelectedSessionID: AgentSessionInstanceID?
    @StateObject private var launchFlow = AgentNewSessionFlow()
    @State private var transcriptLoadGate = AgentTranscriptLoadGate()
    @Environment(\.agentProjectLocations) private var projectLocations
    @Environment(\.agentProjectSelection) private var projectSelection

    init(
        sessions: [AgentSession],
        accountUsage: AgentUsage = AgentUsage(),
        showsUsage: Bool,
        approvalControl: AgentApprovalController,
        managedControl: AgentManagedSessionController,
        layoutStore: IslandLayoutStore? = nil,
        availableHeight: CGFloat,
        initialSelectedSessionID: AgentSessionInstanceID? = nil,
        settings: AppSettings? = nil,
        contentVisible: Bool = true,
        isContentRemoving: Bool = false,
        reduceMotion: Bool = false,
        transcriptPresentationReady: Bool = true,
        presentationGeneration: Int = 0,
        transcriptLoadDelay: TimeInterval = 0.4
    ) {
        self.sessions = sessions
        self.accountUsage = accountUsage
        self.showsUsage = showsUsage
        _approvalControl = ObservedObject(wrappedValue: approvalControl)
        _managedControl = ObservedObject(wrappedValue: managedControl)
        self.layoutStore = layoutStore
        self.availableHeight = availableHeight
        self.initialSelectedSessionID = initialSelectedSessionID
        self.settings = settings
        self.contentVisible = contentVisible
        self.isContentRemoving = isContentRemoving
        self.reduceMotion = reduceMotion
        self.transcriptPresentationReady = transcriptPresentationReady
        self.presentationGeneration = presentationGeneration
        self.transcriptLoadDelay = transcriptLoadDelay
    }

    var body: some View {
        GeometryReader { proxy in
            let workspace = AgentWorkspaceProjection.make(
                sessions: sessions,
                controller: managedControl,
                projectKey: projectSelection.key,
                locations: projectLocations,
                launcherOpen: launchFlow.isPresented
            )
            let providerSessions = workspace.providerSessions
            let projectOptions = AgentProjectFilter.options(
                for: providerSessions,
                locations: projectLocations,
                activeManagedSessionIDs: managedControl.activeManagedSessionIDs
            )
            let effectiveProjectKey = workspace.effectiveProjectKey
            let controlSessions = workspace.controlSessions
            let layout = AgentDashboardLayoutProjection.make(width: proxy.size.width)
            let verticalLayout = AgentWorkspaceVerticalLayoutProjection.make(
                availableHeight: proxy.size.height
            )
            let selectedSession = workspace.selectedSession
            let newSessionFolder = projectOptions.first { $0.id == effectiveProjectKey }?.path
                ?? selectedSession?.project.workingDirectory
            let usageProvider = managedControl.managedProvider
                ?? selectedSession?.id.sessionID.provider
                ?? .codex
            let usageIndicators = showsUsage
                ? Array(AgentUsageIndicatorPresentation.make(
                    provider: usageProvider,
                    accountUsage: accountUsage,
                    selectedSession: selectedSession
                ).prefix(layout.maximumGaugeCount + 1))
                : []
            let usageInHeader = !usageIndicators.isEmpty &&
                proxy.size.width >= AgentWorkspaceHeaderLayout.inlineUsageMinimumWidth
            VStack(alignment: .leading, spacing: 7) {
                if showsUsage, !usageIndicators.isEmpty, !usageInHeader {
                    stagedAgentContent(index: 1) {
                        AgentUsageIndicatorRow(
                            indicators: usageIndicators,
                            spacing: layout.isNarrow ? 10 : 18
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 3)
                    }
                }

                stagedAgentContent(index: 2) {
                    AgentCLIControlBar(
                    sessions: controlSessions,
                    managedControl: managedControl,
                    approvalControl: approvalControl,
                    projectOptions: projectOptions,
                    selectedProjectKey: effectiveProjectKey,
                    onSelectProject: { key in
                        selectProject(key, among: providerSessions)
                    },
                    trailingUsage: usageInHeader ? usageIndicators : [],
                    launcherOpen: launchFlow.isPresented,
                        onToggleLauncher: {
                            withAnimation(.easeOut(duration: 0.14)) {
                                launchFlow.toggle(provider: managedControl.selectedProvider)
                            }
                        },
                        onNewSession: { openNewSession(folder: newSessionFolder) }
                    )
                }

                workspaceContent(
                    workspace: workspace,
                    newSessionFolder: newSessionFolder,
                    verticalLayout: verticalLayout
                )
            }
            .frame(maxWidth: .infinity, maxHeight: proxy.size.height, alignment: .topLeading)
            .task(
                id: AgentTranscriptPresentationRequest(
                    sessionID: selectedSession?.id,
                    presentationGeneration: presentationGeneration,
                    isAllowed: transcriptPresentationReady
                )
            ) {
                await deferTranscript(
                    for: selectedSession?.id,
                    isAllowed: transcriptPresentationReady,
                    presentationGeneration: presentationGeneration
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: availableHeight, alignment: .topLeading)
        .foregroundStyle(.white)
        .onChange(of: sessions.map(\.id)) { _, _ in
            reconcileWorkspaceSelection()
        }
        .onAppear {
            if managedControl.selectedSessionID == nil,
               let initialSelectedSessionID {
                managedControl.selectSession(initialSelectedSessionID)
            }
            reconcileWorkspaceSelection()
        }
        .onChange(of: launchFlow.isPresented) { _, isOpen in
            layoutStore?.isTransientInteractionActive = isOpen
            if isOpen {
                layoutStore?.setExpandedScrollGestureSuppressed(true)
            } else {
                layoutStore?.setExpandedScrollGestureSuppressed(false)
            }
        }
        .onDisappear {
            transcriptLoadGate.cancel()
            layoutStore?.isTransientInteractionActive = false
            layoutStore?.setExpandedScrollGestureSuppressed(false)
            layoutStore?.setExpandedContentScrollRegion(.zero)
        }
    }

    @ViewBuilder
    private func workspaceContent(
        workspace: AgentWorkspaceProjection,
        newSessionFolder: String?,
        verticalLayout: AgentWorkspaceVerticalLayoutProjection
    ) -> some View {
        let controlSessions = workspace.controlSessions
        let selectedSession = workspace.selectedSession
        if launchFlow.isPresented {
            AgentSessionLauncherView(
                sessions: sessions,
                managedControl: managedControl,
                flow: launchFlow,
                onSelectSession: { id in managedControl.selectSession(id) },
                onStarted: { started in
                    didStartSession(started)
                },
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.12)) {
                        launchFlow.dismiss()
                    }
                }
            )
            .padding(.horizontal, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .zIndex(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .layoutPriority(2)
        } else if controlSessions.isEmpty {
            stagedAgentContent(index: 3) {
                AgentEmptyConsoleState(managedControl: managedControl) {
                    openNewSession(folder: newSessionFolder)
                }
            }
        } else {
            if let pending = approvalControl.nextPendingRequest(),
               pending.key.session != selectedSession?.id,
               let approvalSession = sessions.first(where: { $0.id == pending.key.session }) {
                stagedAgentContent(index: 3) {
                    AgentConsoleApprovalRow(
                        request: pending,
                        session: approvalSession,
                        approvalControl: approvalControl
                    )
                }
            }

            if let selectedSession {
                stagedAgentContent(index: 4) {
                    AgentSelectedSessionControlView(
                        session: selectedSession,
                        surface: AgentWorkspaceProjection.controlSurface(
                            for: selectedSession,
                            controller: managedControl
                        ),
                        sessions: controlSessions,
                        managedControl: managedControl,
                        approvalControl: approvalControl,
                        detailHeight: max(verticalLayout.selectedDetailHeight, 138),
                        activityLimit: max(verticalLayout.selectedDetailActivityLimit, 6),
                        layoutStore: layoutStore,
                        transcriptReady: transcriptLoadGate.isReady(for: selectedSession.id)
                    )
                    .layoutPriority(2)
                }
            }
        }
    }

    private func openNewSession(folder: String?) {
        withAnimation(.easeOut(duration: 0.14)) {
            launchFlow.present(
                .newSession,
                provider: managedControl.selectedProvider ?? managedControl.managedProvider,
                folder: folder
            )
        }
    }

    /// The exact new session is already selected and managed; make sure
    /// the project filter shows it.
    private func didStartSession(_ started: AgentManagedStartedSession) {
        guard let session = sessions.first(where: { $0.id == started.instance })
            ?? managedControl.session(for: started.instance) else { return }
        let key = AgentWorkspaceProjection.projectKey(
            afterStarting: session,
            currentKey: projectSelection.key,
            locations: projectLocations
        )
        if key != projectSelection.key { projectSelection.set(key) }
        managedControl.selectSession(started.instance)
    }

    /// Filter change only: cached lookups, no filesystem work, and the
    /// selected exact session is kept whenever it belongs to the project.
    private func selectProject(_ key: String?, among providerSessions: [AgentSession]) {
        projectSelection.set(key)
        let filtered = AgentProjectFilter.filter(
            providerSessions,
            projectKey: key,
            locations: projectLocations
        )
        let preferred = AgentSessionLauncherProjection.preferredSelection(
            current: managedControl.selectedSessionID,
            sessions: filtered,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs,
            locations: projectLocations
        )
        if preferred != managedControl.selectedSessionID {
            managedControl.selectSession(preferred)
        }
    }

    private func reconcileWorkspaceSelection() {
        let preferred = AgentSessionLauncherProjection.preferredSelection(
            current: managedControl.selectedSessionID,
            sessions: sessions,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs,
            locations: projectLocations
        )
        if preferred != managedControl.selectedSessionID {
            managedControl.selectSession(preferred)
        }
        managedControl.reconcileSelection(with: sessions)
    }

    @ViewBuilder
    private func stagedAgentContent<Content: View>(
        index: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let settings {
            content()
                .innerBlurScaleClean(
                    settings: settings,
                    isVisible: contentVisible,
                    isRemoval: isContentRemoving,
                    index: index,
                    reduceMotion: reduceMotion
                )
        } else {
            content()
        }
    }

    @MainActor
    private func deferTranscript(
        for sessionID: AgentSessionInstanceID?,
        isAllowed: Bool,
        presentationGeneration expectedPresentationGeneration: Int
    ) async {
        guard isAllowed, let sessionID else {
            transcriptLoadGate.cancel()
            return
        }
        let generation = transcriptLoadGate.begin(for: sessionID)
        do {
            if transcriptLoadDelay > 0 {
                try await Task.sleep(for: .seconds(transcriptLoadDelay))
            } else {
                await Task.yield()
            }
            try Task.checkCancellation()
        } catch {
            return
        }
        guard presentationGeneration == expectedPresentationGeneration,
              transcriptPresentationReady else {
            transcriptLoadGate.cancel()
            return
        }
        _ = transcriptLoadGate.complete(for: sessionID, generation: generation)
    }
}

private struct AgentTranscriptPresentationRequest: Hashable {
    let sessionID: AgentSessionInstanceID?
    let presentationGeneration: Int
    let isAllowed: Bool
}

private struct AgentCLIControlBar: View {
    let sessions: [AgentSession]
    @ObservedObject var managedControl: AgentManagedSessionController
    @ObservedObject var approvalControl: AgentApprovalController
    var projectOptions: [AgentProjectOption] = []
    var selectedProjectKey: String? = nil
    var onSelectProject: (String?) -> Void = { _ in }
    var trailingUsage: [AgentUsageIndicator] = []
    let launcherOpen: Bool
    let onToggleLauncher: () -> Void
    var onNewSession: () -> Void = {}

    private var selectedSession: AgentSession? {
        AgentWorkspaceSelection.session(
            current: managedControl.selectedSessionID,
            sessions: sessions,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                controls(compact: false)
                    .fixedSize(horizontal: true, vertical: false)
                controls(compact: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 31)

            if !trailingUsage.isEmpty {
                AgentUsageIndicatorRow(indicators: trailingUsage, spacing: 12)
                    .layoutPriority(2)
            }
        }
        .frame(minHeight: trailingUsage.isEmpty ? 31 : AgentUsageIndicatorCircle.diameter + 4)
        .padding(.horizontal, 10)
        .padding(.bottom, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent console controls")
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 8) {
            launcherButton(compact: compact)
            newSessionButton(compact: compact)
            projectMenu(compact: compact)

            if let session = selectedSession {
                HStack(spacing: 4) {
                    Image(systemName: selectorStateSymbol(session))
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(selectedSessionLabel(session))
                        .font(.system(size: compact ? 9 : 10.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.82))
                .layoutPriority(2)

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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.86))
                    .keyboardShortcut(".", modifiers: [.command])
                    .help("Interrupt the exact active managed turn (Command-.)")
                    .accessibilityLabel("Stop active agent turn")
                }
            }
        }
    }

    private func launcherButton(compact: Bool) -> some View {
        let provider = selectedSession?.id.sessionID.provider ?? managedControl.managedProvider ?? .other("agent")
        let project = selectedSession.map { AgentPrivacyProjection.displayProject($0.project).displayName }
            ?? nil
        let title = project ?? provider.stableName.capitalized
        return Button(action: onToggleLauncher) {
            HStack(spacing: 4) {
                Image(systemName: AgentVisualStyle.providerSymbol(provider))
                if !compact {
                    Text(title)
                        .lineLimit(1)
                }
                Image(systemName: launcherOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.74))
            .padding(.horizontal, compact ? 4 : 7)
            .frame(height: 25)
            .background(
                launcherOpen ? Color.white.opacity(0.09) : Color.white.opacity(0.035),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help("Live sessions and local repositories")
        .accessibilityLabel("Open live sessions and repository launcher")
    }

    private func newSessionButton(compact: Bool) -> some View {
        Button(action: onNewSession) {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                if !compact { Text("New") }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.74))
            .padding(.horizontal, compact ? 5 : 7)
            .frame(height: 25)
            .background(Color.white.opacity(0.035), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(managedControl.managedProviders.isEmpty)
        .help("New Claude or Codex session in a folder")
        .accessibilityLabel("New agent session")
    }

    @ViewBuilder
    private func projectMenu(compact: Bool) -> some View {
        if projectOptions.count > 1 || selectedProjectKey != nil {
            let selected = projectOptions.first { $0.id == selectedProjectKey }
            Menu {
                Button {
                    onSelectProject(nil)
                } label: {
                    Label("All projects", systemImage: selectedProjectKey == nil ? "checkmark" : "square.stack")
                }
                Divider()
                ForEach(projectOptions) { option in
                    Button {
                        onSelectProject(option.id)
                    } label: {
                        Label(
                            projectMenuTitle(option),
                            systemImage: option.id == selectedProjectKey ? "checkmark" : "folder"
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    if !compact {
                        Text(selected?.title ?? "All projects")
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6.5, weight: .bold))
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(selected == nil ? 0.52 : 0.78))
                .padding(.horizontal, compact ? 4 : 7)
                .frame(height: 25)
                .background(Color.white.opacity(0.035), in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            }
            // Plain button menu style keeps the custom label typography;
            // the borderless style substitutes the system control font.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(selected?.path ?? "Filter sessions by project")
            .accessibilityLabel("Project filter: \(selected?.title ?? "All projects")")
        }
    }

    private func projectMenuTitle(_ option: AgentProjectOption) -> String {
        var parts = [option.title]
        parts.append(option.activeCount > 0
            ? "\(option.activeCount) active"
            : "\(option.sessionCount) session\(option.sessionCount == 1 ? "" : "s")")
        if option.providers.count > 1 {
            parts.append(option.providers.map { $0.stableName.capitalized }.joined(separator: " + "))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func modelControl(for session: AgentSession, compact: Bool) -> some View {
        let provider = session.id.sessionID.provider
        let models = managedControl.availableModels(for: session)
        if managedControl.capabilities(for: provider).contains(.selectModel),
           !models.isEmpty,
           managedControl.modelSelectionScope(for: provider) == nil {
            // The provider cannot switch a running session's model: show the
            // actual model and offer a new session instead of pretending.
            Menu {
                Section("Start a new session in this folder with") {
                    ForEach(models) { option in
                        Button(option.displayName) {
                            startNewSession(for: session, model: option.model)
                        }
                    }
                }
            } label: {
                compactModelLabel(for: session, compact: compact)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("This session keeps its model. Choose a model to start a new session.")
        } else if managedControl.capabilities(for: provider).contains(.selectModel),
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
                compactModelLabel(for: session, compact: compact)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
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

    /// Preselects the model and opens the New Session launcher for this
    /// session's folder, so the user sees where it will run before Start.
    private func startNewSession(for session: AgentSession, model: String) {
        let provider = session.id.sessionID.provider
        managedControl.selectProvider(provider)
        guard managedControl.selectNewSessionModel(model, for: provider) else { return }
        onNewSession()
    }

    private func compactModelLabel(for session: AgentSession, compact: Bool) -> some View {
        HStack(spacing: 3) {
            if compact { Image(systemName: "cpu") }
            Text(modelLabel(for: session))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 6.5, weight: .semibold))
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.48))
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Color.white.opacity(0.03), in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
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
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(policy.isAutomatic ? "Auto-approval enabled: \(policy.displayName)" : "Approval policy")
            .accessibilityLabel("Approval policy: \(policy.displayName)")
        }
    }

    private func statusControl(for session: AgentSession, compact: Bool) -> some View {
        let stopping = managedControl.isInterrupting(session)
        let label = stopping ? "Stopping…" : selectorStateLabel(session)
        let symbol = stopping ? "stop.circle" : selectorStateSymbol(session)
        return adaptiveLabel(label, systemImage: symbol, compact: compact)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(
                (stopping
                    ? Color.orange
                    : managedControl.activeManagedSessionIDs.contains(session.id.sessionID)
                        ? Color.green
                        : AgentVisualStyle.accent(for: session.state)).opacity(0.82)
            )
            .help(label)
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

    @Environment(\.agentProjectLocations) private var projectLocations

    private func sessionLabel(_ session: AgentSession) -> String {
        if let label = AgentProjectFilter.displayLabel(for: session, locations: projectLocations),
           !label.isEmpty {
            return label
        }
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
    let surface: AgentSessionControlSurface
    let sessions: [AgentSession]
    @ObservedObject var managedControl: AgentManagedSessionController
    @ObservedObject var approvalControl: AgentApprovalController
    let detailHeight: CGFloat
    let activityLimit: Int
    let layoutStore: IslandLayoutStore?
    let transcriptReady: Bool

    var body: some View {
        Group {
            if surface == .composer {
                // A managed, input-ready session always gets its composer
                // immediately; it never waits for a first provider event
                // or the transcript reveal.
                AgentEmbeddedConsoleView(
                    session: session,
                    mode: managedControl.mode(for: session),
                    interactionState: managedControl.interactionState(for: session),
                    maximumActivityEntries: activityLimit,
                    transcriptEntries: transcriptReady ? managedControl.transcript(for: session) : [],
                    workspaceSessions: AgentWorkspaceSelection.ordered(
                        sessions: sessions,
                        activeManagedSessionIDs: managedControl.activeManagedSessionIDs
                    ),
                    layoutStore: layoutStore,
                    approvalControl: approvalControl,
                    onSelectSession: managedControl.selectSession,
                    onSubmit: { await managedControl.submit($0, for: session) },
                    onInterrupt: { managedControl.interrupt(session) },
                    loadDraft: managedControl.composerDraft(for:),
                    saveDraft: managedControl.setComposerDraft(_:for:)
                )
                // Ideal, not minimum: under height pressure the transcript
                // shrinks so the composer and Send stay inside the page clip.
                .frame(minHeight: 0, idealHeight: detailHeight, maxHeight: .infinity)
                .task(id: session.id) {
                    await managedControl.refreshTranscript(for: session)
                }
            } else if !transcriptReady {
                AgentTranscriptLoadingView(session: session)
                    .frame(minHeight: 0, idealHeight: detailHeight, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                VStack(spacing: 5) {
                    AgentSessionControlBanner(
                        session: session,
                        surface: surface,
                        status: managedControl.statusMessage(for: session),
                        onConnect: { managedControl.connect(session) }
                    )

                    AgentEmbeddedConsoleView(
                        session: session,
                        mode: .observed,
                        interactionState: managedControl.interactionState(for: session),
                        maximumActivityEntries: activityLimit,
                        transcriptEntries: managedControl.transcript(for: session),
                        workspaceSessions: AgentWorkspaceSelection.ordered(
                            sessions: sessions,
                            activeManagedSessionIDs: managedControl.activeManagedSessionIDs
                        ),
                        layoutStore: layoutStore,
                        approvalControl: approvalControl,
                        onSelectSession: managedControl.selectSession,
                        onSubmit: { _ in false },
                        onInterrupt: {}
                    )
                    .frame(minHeight: 0, idealHeight: max(detailHeight - 31, 104), maxHeight: .infinity)
                }
                .task(id: session.id) {
                    await managedControl.reconcileObservedSession(session)
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: transcriptReady)
    }
}

/// Explicit state for a selected session that is not composer-ready.
struct AgentSessionControlBanner: View {
    let session: AgentSession
    let surface: AgentSessionControlSurface
    let status: String?
    let onConnect: () -> Void

    var body: some View {
        let content = Self.content(for: surface, provider: session.id.sessionID.provider)
        HStack(spacing: 8) {
            Image(systemName: content.symbol)
                .foregroundStyle(.white.opacity(0.50))
            Text(content.title)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
            if let detail = content.detail ?? status {
                Text(detail)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let action = content.action {
                Button(action: onConnect) {
                    Label(action, systemImage: "terminal")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black.opacity(0.86))
                        .padding(.horizontal, 9)
                        .frame(height: 21)
                        .background(.white.opacity(0.90), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(action == "Resume"
                    ? "Resume this exact session with an embedded composer"
                    : "Take managed control of this exact session")
                .accessibilityLabel("\(action) \(content.providerName) session")
            } else if surface == .attaching {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.white.opacity(0.03))
        .accessibilityElement(children: .contain)
    }

    struct Content: Equatable {
        let providerName: String
        let symbol: String
        let title: String
        let detail: String?
        let action: String?
    }

    static func content(for surface: AgentSessionControlSurface, provider: AgentProvider) -> Content {
        let name = provider.stableName.capitalized
        switch surface {
        case .composer:
            return Content(providerName: name, symbol: "link", title: "Managed \(name) session", detail: nil, action: nil)
        case .resumable:
            return Content(providerName: name, symbol: "arrow.clockwise.circle", title: "Resumable \(name) session", detail: nil, action: "Resume")
        case .controllable:
            return Content(providerName: name, symbol: "eye", title: "Observed \(name) session", detail: nil, action: "Take Control")
        case .attaching:
            return Content(providerName: name, symbol: "link.badge.plus", title: "Attaching \(name) session…", detail: nil, action: nil)
        case .controlUnavailable(let reason):
            return Content(providerName: name, symbol: "eye", title: "Observed \(name) session", detail: reason, action: nil)
        case .readOnly:
            return Content(providerName: name, symbol: "lock", title: "Read-only observed session", detail: nil, action: nil)
        }
    }
}

private struct AgentTranscriptLoadingView: View {
    let session: AgentSession

    var body: some View {
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: AgentSessionPresentation.stateSymbol(session.state))
                        .foregroundStyle(AgentVisualStyle.accent(for: session.state).opacity(0.78))
                    Text(AgentSessionPresentation.displayedPrimaryTitle(for: session, at: Date()))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.40))
                }

                Spacer(minLength: 0)

                Label("Loading session…", systemImage: "ellipsis")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading selected agent session")
        }
    }
}

private struct AgentEmptyConsoleState: View {
    @ObservedObject var managedControl: AgentManagedSessionController
    let onNewSession: () -> Void

    var body: some View {
        let provider = managedControl.managedProvider
        let providerName = provider?.stableName.capitalized ?? "agent"
        VStack(spacing: 9) {
            Image(systemName: AgentVisualStyle.providerSymbol(provider ?? .other("agent")))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
            Text("No active \(providerName) session")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            if let status = managedControl.lastTransportError {
                Label(status, systemImage: "exclamationmark.circle")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.78))
                    .lineLimit(2)
            }

            if !managedControl.managedProviders.isEmpty {
                Button(action: onNewSession) {
                    Label("New Session", systemImage: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.86))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(.white.opacity(0.92), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Choose provider, folder and model, then start")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No active \(providerName) session")
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

    var body: some View {
        HStack(spacing: layout.isNarrow ? 18 : 28) {
            ForEach(metrics) { metric in
                AgentUsageGauge(metric: metric)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent usage summary")
    }
}

private struct AgentUsageGauge: View {
    let metric: AgentGlobalUsagePresentation

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 3)
                if let progress = metric.metric.gaugeProgress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.white.opacity(0.88),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: AgentVisualStyle.providerSymbol(metric.provider))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.metric.label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(gaugeValue)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
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
    var symbol: String = "exclamationmark"

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
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


struct AgentCompactPeekNotificationView: View {
    let presentation: AgentAttentionPresentation
    let session: AgentSession?

    private var primary: AgentAttentionEvent? { presentation.primary }

    var body: some View {
        if let primary {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: primary.reason))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent(for: primary.reason))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title(for: primary.reason))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(primary.session.sessionID.provider.stableName.capitalized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                AgentVisualStyle.providerAccent(primary.session.sessionID.provider).opacity(0.80)
                            )
                    }
                    Text(String(primary.displaySummary.prefix(110)))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let project = session?.project.displayName, !project.isEmpty {
                    Text(project)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title(for: primary.reason)), \(primary.displaySummary)")
        }
    }

    private func title(for reason: AgentAttentionReason) -> String {
        switch reason {
        case .approvalRequired: "Permission required"
        case .userInputRequired: "Input required"
        case .completed: "Task Complete"
        case .failed: "Task Failed"
        case .planReady: "Plan ready"
        case .interrupted: "Interrupted"
        }
    }

    private func symbol(for reason: AgentAttentionReason) -> String {
        switch reason {
        case .approvalRequired, .userInputRequired: "hand.raised.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .planReady: "list.bullet.clipboard.fill"
        case .interrupted: "stop.circle.fill"
        }
    }

    private func accent(for reason: AgentAttentionReason) -> Color {
        switch reason {
        case .completed: .green
        case .failed: .red
        case .approvalRequired, .userInputRequired: .orange
        case .planReady: .cyan
        case .interrupted: .yellow
        }
    }
}

struct AgentCompactRoutineLeadingView: View {
    let session: AgentSession

    var body: some View {
        Text(session.project.displayName ?? session.id.sessionID.provider.stableName.capitalized)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

struct AgentCompactRoutineTrailingView: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(AgentVisualStyle.accent(for: session.state))
                .frame(width: 5, height: 5)
            Text(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

enum AgentWorkspaceHeaderLayout {
    /// Below this width usage indicators get their own centered row above
    /// the controls; at or above it they sit at the trailing edge of the
    /// control row so the transcript keeps the vertical space.
    static let inlineUsageMinimumWidth: CGFloat = 820
}

/// Looked up once per launch so view rendering never queries LaunchServices.
@MainActor
private enum ProviderIconCache {
    static var icons: [String: NSImage?] = [:]
}
