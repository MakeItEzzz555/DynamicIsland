import Foundation

/// AgentNotch parity for agent attention sounds.
///
/// Forensic result (2026-09-30): AgentNotch plays no notification sound, for
/// approval or for completion. Nothing here is a guessed sound.
/// - Installed `/Applications/AgentNotch.app` 1.1 (build 5,
///   `com.nedimfakic.AgentNotch`) ships no audio resources: `Assets.car` holds
///   only AppIcon images. The executable has no `NSSound` class reference, no
///   AudioToolbox / `AudioServices*` / `AVAudioPlayer` / `UNNotificationSound`
///   imports, no system sound names and no "sound" string. Its only AVFoundation
///   use is the optional looping "meme video" (`AVQueuePlayer`/`AVPlayerLooper`).
/// - Upstream `github.com/AppGram/agentnotch` (every ref, tags v1.0.0 through
///   v1.1.2): `git log --all -G 'sound|NSSound|AudioServices|playSound|beep|…'`
///   finds no commits. `MemeVideoPlayerView.swift` sets `player.isMuted = true`.
///
/// So for every event, parity means making no sound at all. The earlier
/// `NSSound.beep()` fallback was not AgentNotch behavior and has been removed.
enum AgentNotchSoundParity {
    /// Sound AgentNotch plays for an attention reason. It is `nil` for every
    /// reason, because AgentNotch 1.1 has no sound playback.
    static func sound(for reason: AgentAttentionReason) -> AgentNotificationSound? {
        switch reason {
        case .approvalRequired, .userInputRequired, .planReady,
             .completed, .failed, .interrupted:
            return nil
        }
    }
}

/// A sound the feedback layer can emit. There are no cases, because no
/// AgentNotch-owned sound exists. Add a case only when one is proven
/// (API/name, or a licensed asset with provenance).
enum AgentNotificationSound: Equatable, Sendable {}

/// One exact event identity (event ID + reason) is let through at most once,
/// no matter how often the intent is republished through re-render,
/// re-projection, a new generation, or restored state. Memory is bounded and
/// evicted in FIFO order, so the behavior is deterministic.
struct AgentNotificationSoundDeduplicator: Sendable {
    struct Key: Hashable, Sendable {
        let eventID: AgentEventID
        let reason: AgentAttentionReason
    }

    let capacity: Int
    private var order: [Key] = []
    private var seen: Set<Key> = []

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    /// Returns `true` only the first time this event identity is seen.
    mutating func admit(_ intent: AgentAttentionSoundIntent) -> Bool {
        let key = Key(eventID: intent.eventID, reason: intent.reason)
        guard seen.insert(key).inserted else { return false }
        order.append(key)
        if order.count > capacity {
            seen.remove(order.removeFirst())
        }
        return true
    }
}

@MainActor
protocol AgentNotificationFeedbackPlaying {
    func play(_ intent: AgentAttentionSoundIntent)
}

@MainActor
final class SystemAgentNotificationFeedback: AgentNotificationFeedbackPlaying {
    static let shared = SystemAgentNotificationFeedback()

    private var deduplicator: AgentNotificationSoundDeduplicator
    private let emit: @MainActor (AgentNotificationSound) -> Void
    private let soundForReason: (AgentAttentionReason) -> AgentNotificationSound?

    init(
        deduplicator: AgentNotificationSoundDeduplicator = AgentNotificationSoundDeduplicator(),
        soundForReason: @escaping (AgentAttentionReason) -> AgentNotificationSound? = AgentNotchSoundParity.sound(for:),
        emit: @escaping @MainActor (AgentNotificationSound) -> Void = { sound in switch sound {} }
    ) {
        self.deduplicator = deduplicator
        self.soundForReason = soundForReason
        self.emit = emit
    }

    /// Returns the sound emitted, or `nil` if the intent was a duplicate or
    /// parity says to stay silent.
    @discardableResult
    func handle(_ intent: AgentAttentionSoundIntent) -> AgentNotificationSound? {
        guard deduplicator.admit(intent) else { return nil }
        guard let sound = soundForReason(intent.reason) else { return nil }
        emit(sound)
        return sound
    }

    func play(_ intent: AgentAttentionSoundIntent) {
        handle(intent)
    }
}
