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
        // No authoritative AgentNotch sound asset or implementation is
        // available. Preserve the app's existing system feedback rather than
        // guessing a named macOS sound from a recording.
        NSSound.beep()
    }
}
