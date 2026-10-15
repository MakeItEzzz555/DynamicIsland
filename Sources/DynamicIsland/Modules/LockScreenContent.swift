import Foundation

/// The only data a lock-screen surface may render. Anything not representable
/// here (clipboard, files, agent text, messages, notification bodies, calendar
/// titles, people, credentials) cannot reach a locked screen by construction.
struct LockScreenContent: Equatable, Sendable {
    struct Media: Equatable, Sendable {
        var title: String
        var artist: String
        var artworkRevision: Int?
        var isPlaying: Bool
        var canSkip: Bool
        var canSeek: Bool
    }
    struct Timer: Equatable, Sendable {
        var remainingSeconds: Int
        var progress: Double
        var isRunning: Bool
    }
    struct KeepAwake: Equatable, Sendable {
        var expiresAt: Date?
    }
    struct Battery: Equatable, Sendable {
        var percent: Int
        var isCharging: Bool
    }
    /// Generic urgency only: a symbol and a fixed category label.
    struct Alert: Equatable, Sendable {
        var symbolName: String
        var label: String
    }

    var media: Media?
    var timer: Timer?
    var keepAwake: KeepAwake?
    var battery: Battery?
    var alert: Alert?

    static let empty = LockScreenContent()
}

/// What the user allowed on the lock screen. Every widget is off by default.
struct LockScreenDisclosure: Equatable, Sendable {
    var media = false
    var mediaMetadata = false
    var timer = false
    var keepAwake = false
    var battery = false
    var alerts = false
}

/// Raw module state, captured on the main actor. The projector is the single
/// place that decides what survives onto the lock screen.
struct LockScreenSources: Sendable {
    var mediaTitle: String?
    var mediaArtist: String?
    var mediaArtworkRevision: Int?
    var mediaIsPlaying = false
    var mediaCanSkip = false
    var mediaCanSeek = false
    var timerRemainingSeconds: Int?
    var timerTotalSeconds: Int?
    var timerIsRunning = false
    var keepAwakeExpiresAt: Date?
    var keepAwakeActive = false
    var batteryPercent: Int?
    var batteryCharging = false
    var alertCategory: AlertCategory?

    enum AlertCategory: Sendable {
        case timerFinished, keepAwakeEnding, lowBattery
    }
}

enum LockScreenPrivacyProjector {
    static func project(_ sources: LockScreenSources, disclosure: LockScreenDisclosure, state: LockState) -> LockScreenContent {
        guard state.isConfirmedLocked else { return .empty }
        var content = LockScreenContent()
        if disclosure.media, let title = sources.mediaTitle?.trimmed, !title.isEmpty {
            content.media = .init(
                title: disclosure.mediaMetadata ? String(title.prefix(80)) : "Now Playing",
                artist: disclosure.mediaMetadata ? String((sources.mediaArtist?.trimmed ?? "").prefix(80)) : "",
                artworkRevision: disclosure.mediaMetadata ? sources.mediaArtworkRevision : nil,
                isPlaying: sources.mediaIsPlaying, canSkip: sources.mediaCanSkip, canSeek: sources.mediaCanSeek)
        }
        if disclosure.timer, let remaining = sources.timerRemainingSeconds, remaining >= 0 {
            let total = max(sources.timerTotalSeconds ?? remaining, 1)
            content.timer = .init(remainingSeconds: remaining, progress: min(max(Double(remaining) / Double(total), 0), 1),
                                  isRunning: sources.timerIsRunning)
        }
        if disclosure.keepAwake, sources.keepAwakeActive {
            content.keepAwake = .init(expiresAt: sources.keepAwakeExpiresAt)
        }
        if disclosure.battery, let percent = sources.batteryPercent {
            content.battery = .init(percent: min(max(percent, 0), 100), isCharging: sources.batteryCharging)
        }
        if disclosure.alerts, let category = sources.alertCategory {
            content.alert = switch category {
            case .timerFinished: .init(symbolName: "timer", label: "Timer finished")
            case .keepAwakeEnding: .init(symbolName: "cup.and.saucer.fill", label: "Keep Awake ending")
            case .lowBattery: .init(symbolName: "battery.25", label: "Battery low")
            }
        }
        return content
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
