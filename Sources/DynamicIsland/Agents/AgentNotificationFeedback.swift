import AppKit
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
///
/// Product decision (2026-10-06): DynamicIsland now intentionally departs
/// from AgentNotch and plays one subtle completion chime
/// (`AgentNotificationFeedbackPolicy`). This enum remains the forensic record.
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

/// A sound the feedback layer can emit. Only macOS system-resident sounds,
/// referenced by name (`/System/Library/Sounds`); no audio asset is bundled.
enum AgentNotificationSound: String, CaseIterable, Equatable, Sendable {
    /// Agent task completed: the ambient "Glass" chime.
    case completionChime

    var systemSoundName: String {
        switch self {
        case .completionChime: "Glass"
        }
    }
}

/// DynamicIsland's agent sound policy: one chime for a *fresh* completed
/// task, nothing else (approval/failure sounds are deliberately not added).
/// Recovered or replayed history - completions that happened long before
/// they were projected - stays silent even if it is new to the deduplicator.
struct AgentNotificationFeedbackPolicy: Equatable, Sendable {
    var completionSoundEnabled: Bool
    /// How old an event may be and still count as live.
    var maximumEventAge: TimeInterval = 30

    func sound(for intent: AgentAttentionSoundIntent, now: Date) -> AgentNotificationSound? {
        guard completionSoundEnabled, intent.reason == .completed else { return nil }
        let age = now.timeIntervalSince(intent.occurredAt)
        guard age <= maximumEventAge, age >= -5 else { return nil }
        return .completionChime
    }
}

/// Plays OS-provided sounds by name. A sound that cannot load stays silent:
/// no `NSSound.beep()` fallback.
@MainActor
enum SystemNotificationSoundPlayer {
    static let volume: Float = 0.55

    @discardableResult
    static func play(_ sound: AgentNotificationSound) -> Bool {
        play(named: sound.systemSoundName)
    }

    /// Plays a macOS system sound by name (e.g. "Glass"); `false` if it
    /// cannot load. Never bundles or copies the audio.
    @discardableResult
    static func play(named name: String, volume: Float = volume) -> Bool {
        guard let player = NSSound(named: NSSound.Name(name)) else { return false }
        player.stop()
        player.volume = volume
        return player.play()
    }
}

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

    /// Updated from settings by the composition root.
    var policy: AgentNotificationFeedbackPolicy
    private var deduplicator: AgentNotificationSoundDeduplicator
    private let now: () -> Date
    private let emit: @MainActor (AgentNotificationSound) -> Bool

    init(
        policy: AgentNotificationFeedbackPolicy = AgentNotificationFeedbackPolicy(completionSoundEnabled: false),
        deduplicator: AgentNotificationSoundDeduplicator = AgentNotificationSoundDeduplicator(),
        now: @escaping () -> Date = Date.init,
        emit: @escaping @MainActor (AgentNotificationSound) -> Bool = SystemNotificationSoundPlayer.play
    ) {
        self.policy = policy
        self.deduplicator = deduplicator
        self.now = now
        self.emit = emit
    }

    /// Returns the sound requested, or `nil` for a duplicate event identity,
    /// a reason/setting the policy keeps silent, or stale history. A sound
    /// that fails to load is reported as `nil` too (silence, never a beep).
    @discardableResult
    func handle(_ intent: AgentAttentionSoundIntent) -> AgentNotificationSound? {
        guard deduplicator.admit(intent) else { return nil }
        guard let sound = policy.sound(for: intent, now: now()) else { return nil }
        return emit(sound) ? sound : nil
    }

    func play(_ intent: AgentAttentionSoundIntent) {
        handle(intent)
    }
}
