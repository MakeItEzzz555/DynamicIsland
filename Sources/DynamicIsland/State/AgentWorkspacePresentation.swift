import SwiftUI

enum AgentWorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case feed, terminal
    var id: Self { self }
    var title: String { self == .feed ? "Feed" : "Terminal" }
    var symbol: String { self == .feed ? "bolt.horizontal" : "terminal" }
}

enum AgentInteractionMode: String, Sendable { case chat, terminal }

/// Presentation intent only. Agent truth, drafts and the terminal process stay
/// in their existing owners. AppDelegate retains this across shell remounts.
@MainActor
final class AgentWorkspacePresentation: ObservableObject {
    @Published private(set) var mode: AgentWorkspaceMode = .feed
    @Published private(set) var interactionMode: AgentInteractionMode = .chat
    @Published private(set) var isEmphasized = false
    @Published private(set) var terminalFocusRequest = 0

    func select(_ mode: AgentWorkspaceMode) {
        if self.mode != mode { self.mode = mode }
    }

    func interact(_ mode: AgentInteractionMode) {
        if interactionMode != mode { interactionMode = mode }
        if mode == .terminal {
            select(.terminal)
            terminalFocusRequest &+= 1
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
}
