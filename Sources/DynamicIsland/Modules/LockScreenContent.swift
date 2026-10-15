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
        /// Player app name (e.g. "Spotify"); only with the track-details opt-in.
        var source: String? = nil
    }
    struct Timer: Equatable, Sendable {
        var remainingSeconds: Int
        var progress: Double
        var isRunning: Bool
    }
    struct KeepAwake: Equatable, Sendable {
        var expiresAt: Date?
        /// Remaining share of a timed session; nil for an indefinite one.
        var progress: Double?
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
    var mediaSource: String?
    var timerRemainingSeconds: Int?
    var timerTotalSeconds: Int?
    var timerIsRunning = false
    var keepAwakeExpiresAt: Date?
    var keepAwakeTotalSeconds: Double?
    var keepAwakeActive = false
    var batteryPercent: Int?
    var batteryCharging = false
    var alertCategory: AlertCategory?

    enum AlertCategory: Sendable {
        case timerFinished, keepAwakeEnding, lowBattery
    }
}

enum LockScreenPrivacyProjector {
    static func project(_ sources: LockScreenSources, disclosure: LockScreenDisclosure, state: LockState,
                        now: Date = Date()) -> LockScreenContent {
        guard state.isConfirmedLocked else { return .empty }
        var content = LockScreenContent()
        if disclosure.media, let title = sources.mediaTitle?.trimmed, !title.isEmpty {
            content.media = .init(
                title: disclosure.mediaMetadata ? String(title.prefix(80)) : "Now Playing",
                artist: disclosure.mediaMetadata ? String((sources.mediaArtist?.trimmed ?? "").prefix(80)) : "",
                artworkRevision: disclosure.mediaMetadata ? sources.mediaArtworkRevision : nil,
                isPlaying: sources.mediaIsPlaying, canSkip: sources.mediaCanSkip, canSeek: sources.mediaCanSeek,
                source: disclosure.mediaMetadata ? sources.mediaSource : nil)
        }
        if disclosure.timer, let remaining = sources.timerRemainingSeconds, remaining >= 0 {
            let total = max(sources.timerTotalSeconds ?? remaining, 1)
            content.timer = .init(remainingSeconds: remaining, progress: min(max(Double(remaining) / Double(total), 0), 1),
                                  isRunning: sources.timerIsRunning)
        }
        if disclosure.keepAwake, sources.keepAwakeActive {
            var progress: Double?
            if let expires = sources.keepAwakeExpiresAt, let total = sources.keepAwakeTotalSeconds, total > 0 {
                progress = min(max(expires.timeIntervalSince(now) / total, 0), 1)
            }
            content.keepAwake = .init(expiresAt: sources.keepAwakeExpiresAt, progress: progress)
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

/// Lock-screen preferences, persisted as one Codable value. Everything is off
/// until the user turns the experimental master switch on.
struct LockScreenPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var hud = true
    var lockSound = "None"
    var unlockSound = "Default"
    var soundVolume = 0.5
    var keepVisibleDuringScreensaver = false
    var nowPlaying = true
    var showTrackDetails = false
    var timer = true
    var keepAwake = true
    var battery = true
    var alerts = true
    var sideVolume = false
    var sideBrightness = false
    var mediaVerticalOffset = 0.0
    var secondaryPlacement = LockScreenSecondaryPlacement.below
    var secondaryGap = 14.0
    var radialOrder = LockScreenRadialKind.allCases
    var mediaSize = LockScreenMediaSize.standard

    static let defaults = LockScreenPreferences()

    var disclosure: LockScreenDisclosure {
        .init(media: nowPlaying, mediaMetadata: showTrackDetails, timer: timer, keepAwake: keepAwake,
              battery: battery, alerts: alerts)
    }

    func normalized() -> Self {
        var copy = self
        copy.soundVolume = soundVolume.isFinite ? min(max(soundVolume, 0), 1) : 0.5
        copy.mediaVerticalOffset = mediaVerticalOffset.isFinite ? min(max(mediaVerticalOffset, -200), 200) : 0
        copy.secondaryGap = secondaryGap.isFinite ? min(max(secondaryGap, 0), 60) : 14
        var seen = Set<LockScreenRadialKind>()
        copy.radialOrder = radialOrder.filter { seen.insert($0).inserted }
            + LockScreenRadialKind.allCases.filter { !seen.contains($0) }
        return copy
    }

    static func decode(from defaults: UserDefaults, key: String) -> Self {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return .defaults }
        return decoded.normalized()
    }

    init() {}

    /// Missing keys keep their defaults, so adding a preference never resets the rest.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let base = Self.defaults
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        enabled = value(.enabled, base.enabled); hud = value(.hud, base.hud)
        lockSound = value(.lockSound, base.lockSound); unlockSound = value(.unlockSound, base.unlockSound)
        soundVolume = value(.soundVolume, base.soundVolume)
        keepVisibleDuringScreensaver = value(.keepVisibleDuringScreensaver, base.keepVisibleDuringScreensaver)
        nowPlaying = value(.nowPlaying, base.nowPlaying); showTrackDetails = value(.showTrackDetails, base.showTrackDetails)
        timer = value(.timer, base.timer); keepAwake = value(.keepAwake, base.keepAwake)
        battery = value(.battery, base.battery); alerts = value(.alerts, base.alerts)
        sideVolume = value(.sideVolume, base.sideVolume); sideBrightness = value(.sideBrightness, base.sideBrightness)
        mediaVerticalOffset = value(.mediaVerticalOffset, base.mediaVerticalOffset)
        secondaryPlacement = value(.secondaryPlacement, base.secondaryPlacement)
        secondaryGap = value(.secondaryGap, base.secondaryGap)
        radialOrder = value(.radialOrder, base.radialOrder)
        mediaSize = value(.mediaSize, base.mediaSize)
    }
}
