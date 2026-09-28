import AppKit

@MainActor
protocol AgentNotificationFeedbackPlaying {
    func play(_ intent: AgentAttentionSoundIntent)
}

@MainActor
final class SystemAgentNotificationFeedback: AgentNotificationFeedbackPlaying {
    static let shared = SystemAgentNotificationFeedback()

    // AgentNotch's public repository does not contain a notification-audio
    // implementation. The supplied AgentNotch screen recording has a short
    // metallic transient whose timing/envelope most closely matches macOS Tink,
    // so use that reference sound instead of the generic system alert beep.
    private let referenceSound: NSSound? = {
        let path = "/System/Library/Sounds/Tink.aiff"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSSound(contentsOfFile: path, byReference: true)
    }()

    private init() {}

    func play(_ intent: AgentAttentionSoundIntent) {
        if let referenceSound {
            referenceSound.stop()
            referenceSound.currentTime = 0
            referenceSound.play()
        } else {
            NSSound.beep()
        }
    }
}
