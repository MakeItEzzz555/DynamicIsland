import AppKit

@MainActor
protocol AgentNotificationFeedbackPlaying {
    func play(_ intent: AgentAttentionSoundIntent)
}

@MainActor
final class SystemAgentNotificationFeedback: AgentNotificationFeedbackPlaying {
    static let shared = SystemAgentNotificationFeedback()

    private init() {}

    func play(_ intent: AgentAttentionSoundIntent) {
        // AgentNotch's public source and installed 1.1 build 5 contain no
        // authoritative notification audio asset/API. Preserve DynamicIsland's
        // existing system beep behind one replaceable abstraction.
        NSSound.beep()
    }
}
