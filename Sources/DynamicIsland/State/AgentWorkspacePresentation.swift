import SwiftUI

enum AgentWorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case feed, terminal
    var id: Self { self }
    var title: String { self == .feed ? "Feed" : "Terminal" }
    var symbol: String { self == .feed ? "bolt.horizontal" : "terminal" }
}

enum AgentInteractionMode: String, Sendable { case chat, terminal }

/// Which surface a standalone Chat or Terminal region currently shows. This
/// is presentation state only: switching never mutates `WorkspaceConfiguration`
/// (the region keeps its id, rectangle and semantic size).
typealias AgentConsolePresentationMode = AgentInteractionMode

/// Where an embedded Chat/Terminal switch applies for a region.
enum AgentConsoleSwitchTarget: Equatable {
    /// An explicit Chat+Terminal stack pages between its two surfaces.
    case stack
    /// A standalone Chat or Terminal region switches its own presentation.
    case region(WidgetID)
    /// Not a console region.
    case none

    static func resolve(_ region: WorkspaceWidgetRegion) -> Self {
        if region.isStack { return .stack }
        switch region.widgets.first?.kind {
        case .chat?, .terminal?: return .region(region.id)
        default: return .none
        }
    }
}

enum AgentStackPage: String, CaseIterable, Identifiable {
    case chat, terminal
    var id: Self { self }
    var title: String { self == .chat ? "Chat" : "Terminal" }
    var symbol: String { self == .chat ? "bubble.left" : "terminal" }
}

/// Presentation intent only. Agent truth, drafts and the terminal process stay
/// in their existing owners. AppDelegate retains this across shell remounts.
@MainActor
final class AgentWorkspacePresentation: ObservableObject {
    @Published private(set) var mode: AgentWorkspaceMode = .feed
    @Published private(set) var interactionMode: AgentInteractionMode = .chat
    @Published private(set) var isEmphasized = false
    @Published private(set) var terminalFocusRequest = 0
    @Published private(set) var stackPage: AgentStackPage = .chat
    @Published private(set) var stackDirection = 1
    /// Per-region console presentation (keyed by the stable region id).
    @Published private(set) var consoleModes: [WidgetID: AgentConsolePresentationMode] = [:]

    /// The surface a standalone console region shows; defaults to its kind.
    func consoleMode(for region: WorkspaceWidgetRegion) -> AgentConsolePresentationMode {
        consoleModes[region.id] ?? (region.widgets.first?.kind == .terminal ? .terminal : .chat)
    }

    /// The embedded Chat/Terminal switch. Presentation only: it never adds,
    /// removes or reorders workspace widgets. Each surface is presented at
    /// most once (one PTY host, one composer): if another standalone console
    /// region already shows the requested surface, the two regions swap.
    func switchConsole(to mode: AgentConsolePresentationMode, in region: WorkspaceWidgetRegion,
                       among regions: [WorkspaceWidgetRegion] = []) {
        switch AgentConsoleSwitchTarget.resolve(region) {
        case .stack:
            showStack(mode == .chat ? .chat : .terminal)
        case .region(let id):
            let previous = consoleMode(for: region)
            guard previous != mode else { return }
            var next = consoleModes
            for other in regions where other.id != id && AgentConsoleSwitchTarget.resolve(other) == .region(other.id)
                && consoleMode(for: other) == mode {
                next[other.id] = previous
            }
            next[id] = mode
            consoleModes = next
            if interactionMode != mode { interactionMode = mode }
        case .none:
            break
        }
    }

    func showStack(_ page: AgentStackPage) {
        guard stackPage != page else { return }
        stackDirection = page == .terminal ? 1 : -1
        stackPage = page
        if page == .terminal { terminalFocusRequest &+= 1 }
    }

    func swipeStack(by direction: Int) {
        guard direction != 0 else { return }
        showStack(stackPage == .chat ? .terminal : .chat)
    }

    func select(_ mode: AgentWorkspaceMode) {
        if self.mode != mode { self.mode = mode }
        if mode == .terminal { terminalFocusRequest &+= 1 }
    }

    func interact(_ mode: AgentInteractionMode) {
        if interactionMode != mode { interactionMode = mode }
        if mode == .terminal {
            select(.terminal)
        }
    }

    func toggleEmphasis() { isEmphasized.toggle() }
}

struct AgentWorkspaceColumns: Equatable, Sendable {
    let chat: CGFloat
    let workspace: CGFloat
    let gap: CGFloat
    let canEmphasize: Bool

    static func make(width: CGFloat, emphasized: Bool) -> Self {
        let width = width.isFinite ? max(0, width) : 0
        let gap: CGFloat = min(10, width * 0.02)
        let available = max(0, width - gap)
        let canEmphasize = available >= 530
        let minimumChat = min(240, available * 0.55)
        let desiredRight = available * (emphasized && canEmphasize ? 0.57 : 0.40)
        let right = min(max(desiredRight, min(210, available * 0.45)), max(available - minimumChat, 0))
        return Self(chat: available - right, workspace: right, gap: gap, canEmphasize: canEmphasize)
    }
}

/// Native adaptation of transitions.dev resize / sliding-tabs / panel-reveal:
/// reversible 250ms content handoff, 300ms resize, smooth-out easing; no delays
/// and no spatial motion when accessibility Reduce Motion is enabled.
enum AgentWorkspaceMotion {
    static func transcriptJump(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }
    static func selection(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.25)
    }
    static func resize(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.30)
    }
    static func animatesBeam(session: AgentSession?, interaction: AgentManagedInteractionState) -> Bool {
        guard let session, AgentVisualMotion.animates(session.state) else { return false }
        // Transport attachment/submission may connect, but does not override
        // an authoritative approval/user wait or terminal state.
        switch interaction {
        case .stopping, .failed: return false
        default: return true
        }
    }
}

enum AgentWorkspaceUsageProjection {
    /// Pair providers by semantic category. Context is the retained exact
    /// selection of EACH provider, never a cross-provider fallback thread.
    static func make(
        accountUsage: [AgentProvider: AgentUsage],
        selectedSessions: [AgentProvider: AgentSession],
        now: Date = Date()
    ) -> [[AgentUsageIndicator]] {
        let providers: [AgentProvider] = [.codex, .claude]
        let values = providers.map { provider in
            AgentUsageIndicatorPresentation.make(
                provider: provider,
                accountUsage: accountUsage[provider] ?? AgentUsage(),
                selectedSession: selectedSessions[provider], now: now
            )
        }
        return (0..<3).map { index in values.map { $0[index] } }
    }

    /// Quota indicators grouped by provider (5h, Week). Context is excluded
    /// from production presentation: its per-provider semantics differ and it
    /// is unavailable for most selections (see context.md).
    static func providerGroups(
        accountUsage: [AgentProvider: AgentUsage],
        now: Date = Date()
    ) -> [AgentProvider: [AgentUsageIndicator]] {
        Dictionary(uniqueKeysWithValues: [AgentProvider.codex, .claude].map { provider in
            (provider, AgentUsageIndicatorPresentation.make(
                provider: provider, accountUsage: accountUsage[provider] ?? AgentUsage(), selectedSession: nil, now: now
            ).filter { $0.kind != .context })
        })
    }
}
