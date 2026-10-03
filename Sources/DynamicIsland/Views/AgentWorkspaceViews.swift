import AppKit
import AgentBridgeShared
import LibrariesNative
import SwiftUI

struct AgentWorkspaceSplitView<Chat: View, Workspace: View>: View {
    @ObservedObject var presentation: AgentWorkspacePresentation
    let reduceMotion: Bool
    @ViewBuilder let chat: () -> Chat
    @ViewBuilder let workspace: (Bool) -> Workspace

    var body: some View {
        GeometryReader { geometry in
            let columns = AgentWorkspaceColumns.make(width: geometry.size.width, emphasized: presentation.isEmphasized)
            HStack(alignment: .top, spacing: columns.gap) {
                chat().frame(width: columns.chat, height: geometry.size.height)
                workspace(columns.canEmphasize).frame(width: columns.workspace, height: geometry.size.height)
            }
            .animation(AgentWorkspaceMotion.resize(reduceMotion: reduceMotion), value: presentation.isEmphasized)
        }
    }
}

struct AgentWorkspaceUsageStrip: View {
    let groups: [[AgentUsageIndicator]]

    static func diameter(for width: CGFloat) -> CGFloat {
        width < 620 ? 40 : 48
    }

    static func rowHeight(for width: CGFloat) -> CGFloat {
        diameter(for: width) + 18
    }

    var body: some View {
        GeometryReader { geometry in
            let side = Self.diameter(for: geometry.size.width)
            HStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: 3) {
                        HStack(spacing: side >= 48 ? 12 : 8) {
                            ForEach(pair) { value in
                                AgentUsageIndicatorCircle(
                                    indicator: value,
                                    metrics: .init(quotaDiameter: side, contextDiameter: side),
                                    showsLabels: false
                                )
                            }
                        }
                        Text(pair.first.map { "\($0.label) · \($0.directionLabel)" } ?? "")
                            .font(.system(size: side >= 48 ? 9 : 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(minHeight: 58, idealHeight: 66)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Both providers: five-hour, weekly and selected-session context usage")
    }
}

struct AgentWorkspaceSwitcher: View {
    @ObservedObject var presentation: AgentWorkspacePresentation
    let canEmphasize: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @State private var hoveredMode: AgentWorkspaceMode?
    @State private var emphasisHovered = false

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(AgentWorkspaceMode.allCases) { mode in
                    Button {
                        withAnimation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion)) {
                            presentation.select(mode)
                        }
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                presentation.mode == mode || hoveredMode == mode
                                    ? .primary
                                    : .secondary
                            )
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background {
                                if presentation.mode == mode {
                                    Capsule().fill(.primary.opacity(0.10))
                                        .matchedGeometryEffect(id: "agent-workspace-tab", in: selection)
                                } else if hoveredMode == mode {
                                    Capsule().fill(.primary.opacity(0.065))
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion)) {
                            if hovering {
                                hoveredMode = mode
                            } else if hoveredMode == mode {
                                hoveredMode = nil
                            }
                        }
                    }
                    .help("Show agent \(mode.title.lowercased())")
                    .accessibilityLabel("Agent workspace \(mode.title)")
                    .accessibilityAddTraits(presentation.mode == mode ? [.isSelected, .isButton] : .isButton)
                }
            }
            .background(.primary.opacity(0.035), in: Capsule())
            Spacer(minLength: 0)
            Button {
                withAnimation(AgentWorkspaceMotion.resize(reduceMotion: reduceMotion)) {
                    presentation.toggleEmphasis()
                }
            } label: {
                Image(systemName: presentation.isEmphasized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(emphasisHovered && canEmphasize ? .primary : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        emphasisHovered && canEmphasize ? Color.primary.opacity(0.065) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion)) {
                    emphasisHovered = hovering
                }
            }
            .disabled(!canEmphasize)
            .help(presentation.isEmphasized ? "Balance conversation and workspace" : "Give the selected workspace more room")
            .accessibilityLabel(presentation.isEmphasized ? "Restore balanced agent workspace" : "Expand agent workspace")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent workspace controls")
    }
}

/// Feed is the only subscriber to operational history. Its publications do
/// not travel through the selected transcript or surrounding Agents chrome.
struct AgentWorkspaceFeedView: View {
    @ObservedObject var feed: AgentWorkspaceFeedStore
    @ObservedObject var approvals: AgentApprovalController
    let sessions: [AgentSession]
    var selectedSessionID: AgentSessionInstanceID? = nil
    let onSelect: (AgentSessionInstanceID) -> Void
    let isVisible: Bool
    @Environment(\.agentVisualPreferences) private var visualPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = AgentPerformanceProbe.count("agents.feed.body")
        let selectedItems = feed.items(for: selectedSessionID, session: sessions.first { $0.id == selectedSessionID })
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 6) {
                if selectedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Agents, in motion", systemImage: "bolt.horizontal")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Recent actions and permission requests for the selected agent appear here.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 14)
                }
                ForEach(selectedItems) { item in
                    feedRow(item)
                        .id(item.id)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
            .animation(
                AgentWorkspaceMotion.selection(reduceMotion: reduceMotion),
                value: selectedItems.map(\.id)
            )
        }
        .id(selectedSessionID)
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { feed.reconcileApprovals(sessions: sessions) }
        .onChange(of: sessions) { _, value in feed.reconcileApprovals(sessions: value) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selectedSessionID.map { "Selected \($0.sessionID.provider.stableName) agent operational feed" } ?? "No selected agent feed")
    }

    private func feedRow(_ item: AgentWorkspaceFeedItem) -> some View {
        let session = sessions.first { $0.id == item.sessionID }
        let active = item.isCurrentActivity(in: session)
        let approval = item.approvalKey.flatMap { key in item.approvalPresentation(delivery: approvals.deliveryState(for: key)) }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                BotAvatarView(
                    sessionID: item.sessionID,
                    configuration: feedAvatar,
                    state: active ? .working : .idle,
                    compact: true,
                    paused: !isVisible || !active,
                    frozenTime: active ? nil : 0
                )
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
                Button { onSelect(item.sessionID) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: AgentVisualStyle.providerSymbol(item.provider))
                            Text(item.provider.stableName.capitalized)
                            Text("…" + item.sessionID.sessionID.nativeID.suffix(4)).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 8, weight: .semibold))
                        Text(approval?.label ?? item.title)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.provider.stableName.capitalized), \(approval?.label ?? item.title), select exact session")
                Text(item.updatedAt, style: .time)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if let session, let key = item.approvalKey,
               let request = approvals.pendingRequests[key] ?? approvals.deliveringRequests[key], request.key == key,
               approval == .pending || approval == .submitting || approval == .failed {
                AgentConsoleApprovalRow(request: request, session: session, approvalControl: approvals)
            } else if let session, let key = item.approvalKey, approval == .pending {
                // Observed sessions cannot deliver decisions. They retain the
                // established source-opening path, without managed buttons.
                Text(session.approvals[key.requestID]?.summary ?? "Provider permission request")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                if let target = AgentSourceAssociationResolver.openTarget(for: session) {
                    Button("Open source") { _ = AppLaunchService.openApp(bundleIdentifier: target.bundleIdentifier) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text("Observed · resolve in the source application")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .padding(7)
        .background(.primary.opacity(approval == .pending ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .leading) {
            if approval == .pending || approval == .failed {
                Capsule().fill(approval == .failed ? Color.red : .orange).frame(width: 2).padding(.vertical, 7)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var feedAvatar: BotAvatarConfiguration {
        var value = visualPreferences.avatar
        value.size = 26
        value.interactive = false // Event identity cannot steal transcript/scroll gestures.
        return value
    }
}

struct AgentChatSurface<Conversation: View>: View {
    let session: AgentSession
    @ObservedObject var controller: AgentManagedSessionController
    @ObservedObject var presentation: AgentWorkspacePresentation
    let isVisible: Bool
    let onNewSession: () -> Void
    @ViewBuilder let conversation: () -> Conversation
    @Environment(\.agentVisualPreferences) private var visuals
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredInteractionMode: AgentInteractionMode?

    var body: some View {
        let interaction = controller.interactionState(for: session)
        BorderBeam(
            size: .md, colorVariant: .colorful, strength: 0.7,
            active: AgentWorkspaceMotion.animatesBeam(session: session, interaction: interaction),
            theme: .auto, borderRadius: 12, visible: isVisible
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    AgentOrbView(
                        state: AgentOrbStateMapper.state(for: interaction, session: session),
                        size: 28, speed: visuals.orbSpeed, paused: !isVisible,
                        terminal: !AgentVisualMotion.animates(session.state)
                    )
                    .accessibilityLabel("\(session.id.sessionID.provider.stableName.capitalized), \(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AgentSessionPresentation.primaryTitle(for: session))
                            .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: AgentVisualStyle.providerSymbol(session.id.sessionID.provider))
                            Text(session.id.sessionID.provider.stableName.capitalized)
                            Text("· \(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))")
                        }
                        .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 1) {
                        interactionButton(.chat, icon: "bubble.left", title: "Chat")
                        interactionButton(.terminal, icon: "terminal", title: "Terminal")
                    }
                    .background(.primary.opacity(0.04), in: Capsule())
                }
                .padding(.horizontal, 9).padding(.top, 7).padding(.bottom, 3)
                conversation()
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                if controller.isManaged(session),
                   controller.mode(for: session).showsComposer,
                   !controller.availableReasoningEfforts(for: session).isEmpty {
                    HStack(spacing: 5) {
                        reasoningControl
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)
                }
            }
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.055), lineWidth: 1).allowsHitTesting(false) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.id.sessionID.provider.stableName.capitalized) conversation")
    }

    private func interactionButton(_ mode: AgentInteractionMode, icon: String, title: String) -> some View {
        Button {
            withAnimation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion)) { presentation.interact(mode) }
        } label: {
            let highlighted = presentation.interactionMode == mode || hoveredInteractionMode == mode
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(highlighted ? .primary : .secondary)
                .frame(width: 28, height: 25)
                .background(
                    presentation.interactionMode == mode
                        ? Color.primary.opacity(0.10)
                        : hoveredInteractionMode == mode
                            ? Color.primary.opacity(0.06)
                            : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion)) {
                if hovering {
                    hoveredInteractionMode = mode
                } else if hoveredInteractionMode == mode {
                    hoveredInteractionMode = nil
                }
            }
        }
        .help(mode == .chat ? "Use selected agent chat" : "Focus the project terminal without interrupting the agent")
        .accessibilityLabel("Selected agent \(title) interaction")
        .accessibilityAddTraits(presentation.interactionMode == mode ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private var modelControl: some View {
        let options = controller.availableModels(for: session)
        let model = controller.pendingModel(for: session) ?? controller.selectedModel(for: session)
        let name = options.first { $0.model == model }?.displayName ?? model ?? "Model unavailable"
        if !options.isEmpty, controller.isManaged(session) {
            Menu {
                if controller.modelSelectionScope(for: session) != nil {
                    Button("Use thread model") { controller.selectModel(nil, for: session) }
                    ForEach(options) { option in
                        Button { controller.selectModel(option.model, for: session) } label: {
                            Label(option.displayName, systemImage: model == option.model ? "checkmark" : "cpu")
                        }
                    }
                } else {
                    Text("This provider keeps the current session model")
                    ForEach(options) { option in
                        Button("New session with \(option.displayName)") {
                            controller.selectProvider(session.id.sessionID.provider)
                            if controller.selectNewSessionModel(option.model, for: session.id.sessionID.provider) { onNewSession() }
                        }
                    }
                }
            } label: { controlLabel(name, icon: "cpu") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .disabled(controller.modelSelectionScope(for: session) != nil && !controller.canSelectModel(for: session))
            .help("Selected model; supported changes apply to a future turn")
            .accessibilityLabel("Agent model: \(name)")
        } else {
            controlLabel(name, icon: "cpu").accessibilityLabel("Agent model: \(name)")
        }
    }

    @ViewBuilder private var reasoningControl: some View {
        let efforts = controller.availableReasoningEfforts(for: session)
        let selected = controller.selectedReasoningEffort(for: session)
        if !efforts.isEmpty {
            Menu {
                Button("Use model default") { controller.selectReasoningEffort(nil, for: session) }
                ForEach(efforts) { option in
                    Button { controller.selectReasoningEffort(option.id, for: session) } label: {
                        Label(option.id.capitalized, systemImage: selected == option.id ? "checkmark" : "brain")
                    }
                }
            } label: { controlLabel(selected?.capitalized ?? "Default", icon: "brain") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .disabled(!controller.canSelectReasoningEffort(for: session))
            .help("Reasoning effort for the next turn; unavailable while a turn is active")
            .accessibilityLabel("Next-turn reasoning effort: \(selected ?? "model default")")
        } else {
            controlLabel("Provider default", icon: "brain")
                .foregroundStyle(.secondary)
                .help("This provider/model does not advertise selectable reasoning effort")
                .accessibilityLabel("Reasoning effort: provider default; selection unsupported")
        }
    }

    private func controlLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 8.5, weight: .medium))
        .padding(.horizontal, 6).frame(height: 24)
        .background(.primary.opacity(0.04), in: Capsule())
        .contentShape(Capsule())
    }
}

struct AgentRightWorkspace: View {
    @ObservedObject var presentation: AgentWorkspacePresentation
    let feed: AgentWorkspaceFeedStore
    let approvals: AgentApprovalController
    let terminal: TerminalSessionController?
    let sessions: [AgentSession]
    let selectedSession: AgentSession?
    let onSelect: (AgentSessionInstanceID) -> Void
    let onSelectAttention: (AgentSessionInstanceID) -> Void
    let canEmphasize: Bool
    let isVisible: Bool
    let layoutStore: IslandLayoutStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                AgentWorkspaceSwitcher(presentation: presentation, canEmphasize: canEmphasize)
                    .frame(maxWidth: .infinity)
                AgentWorkspaceApprovalAttentionControl(
                    approvals: approvals,
                    selectedSessionID: selectedSession?.id,
                    onSelect: onSelectAttention
                )
            }
            .padding(.horizontal, 3)
            GeometryReader { geometry in
                RetainedWorkspacePages(
                    pages: AgentWorkspaceMode.allCases, selection: presentation.mode,
                    size: geometry.size, travel: 8, blur: 0, reduceMotion: reduceMotion
                ) { mode in
                    switch mode {
                    case .feed:
                        AgentWorkspaceFeedView(
                            feed: feed, approvals: approvals, sessions: sessions, selectedSessionID: selectedSession?.id,
                            onSelect: onSelect, isVisible: isVisible && presentation.mode == .feed
                        )
                    case .terminal:
                        if let terminal {
                            AgentWorkspaceTerminalView(
                                controller: terminal, session: selectedSession,
                                isVisible: isVisible && presentation.mode == .terminal,
                                focusRequest: presentation.terminalFocusRequest,
                                layoutStore: layoutStore
                            )
                        } else {
                            Text("Terminal is unavailable in this preview")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .animation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion), value: presentation.mode)
                .background {
                    GeometryReader { region in
                        Color.clear.preference(key: AgentWorkspaceScrollRegionKey.self, value: region.frame(in: .named(IslandCanvasCoordinateSpace.name)))
                    }
                }
                .onPreferenceChange(AgentWorkspaceScrollRegionKey.self) { frame in
                    guard let layoutStore else { return }
                    layoutStore.setAgentWorkspaceScrollRegion(isVisible ? IslandCanvasCoordinateSpace.appKitLocalRect(fromSwiftUI: frame, canvasHeight: layoutStore.canvasSize.height) : .zero)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent workspace, \(presentation.mode.title)")
        .onDisappear { layoutStore?.setAgentWorkspaceScrollRegion(.zero) }
        .onChange(of: isVisible) { _, visible in if !visible { layoutStore?.setAgentWorkspaceScrollRegion(.zero) } }
    }
}

private struct AgentWorkspaceScrollRegionKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Native command surface reuses the one existing terminal controller. Changing
/// pages never starts/stops a process; cwd is adopted only on explicit Run and
/// only when idle. The selected agent transcript continues independently.
struct AgentWorkspaceTerminalView: View {
    @ObservedObject var controller: TerminalSessionController
    let session: AgentSession?
    let isVisible: Bool
    let focusRequest: Int
    let layoutStore: IslandLayoutStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(URL(fileURLWithPath: controller.shellPath).lastPathComponent)
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { controller.interrupt() } label: {
                    Image(systemName: "stop.fill").frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Interrupt foreground terminal command")
                Button { controller.resetOutput() } label: {
                    Image(systemName: "eraser").frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Clear terminal display")
                Button { controller.terminate(); try? controller.startShell() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Restart embedded shell")
            }
            NativeTerminalHost(controller: controller,
                               initialDirectory: session?.project.workingDirectory,
                               isVisible: isVisible, focusRequest: focusRequest,
                               onFocusChange: { value in layoutStore?.setTextInputFocused(value) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            if case .failed = controller.state {
                Text(controller.statusText).font(.system(size: 8)).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Embedded interactive project terminal")
    }
}
