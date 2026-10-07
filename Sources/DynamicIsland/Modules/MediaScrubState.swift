import Foundation

/// Playback times inside the app and local player commands are seconds.
enum MediaPlaybackTime {
    /// Live Spotify endpoint seeks stalled at the duration and 100 ms before
    /// it; 250 ms before the end allowed the player to advance naturally.
    static let spotifyEndGuardMilliseconds = 250

    static func validDuration(_ duration: Double?) -> Double? {
        guard let duration, duration.isFinite, duration > 0, duration < Double(Int.max) else { return nil }
        return duration
    }

    static func clampedPosition(_ position: Double, duration: Double) -> Double? {
        guard position.isFinite, validDuration(duration) != nil else { return nil }
        return min(max(0, position), duration)
    }

    /// Invalid timing resolves to a safe zero; availability remains a separate
    /// provider capability so an unknown track never advertises seek support.
    static func normalizedProgress(position: Double, duration: Double) -> Double {
        guard let position = clampedPosition(position, duration: duration) else { return 0 }
        return position / duration
    }

    static func maximumSeekPosition(duration: Double, player: MediaController.MediaPlayer) -> Double? {
        guard validDuration(duration) != nil else { return nil }
        return player == .spotify ? max(0, duration - Double(spotifyEndGuardMilliseconds) / 1_000) : duration
    }

    static func clampedSeekPosition(_ position: Double, duration: Double, player: MediaController.MediaPlayer) -> Double? {
        guard let position = clampedPosition(position, duration: duration),
              let maximum = maximumSeekPosition(duration: duration, player: player) else { return nil }
        return min(position, maximum)
    }

    /// Clamp the live-verified Spotify boundary in seconds, floor into integer
    /// milliseconds, and enforce the same boundary in the provider's unit.
    static func spotifyMilliseconds(_ position: Double, duration: Double) -> Int? {
        guard let seconds = clampedSeekPosition(position, duration: duration, player: .spotify),
              let durationMilliseconds = spotifyDurationMilliseconds(duration) else { return nil }
        let milliseconds = seconds * 1_000
        guard milliseconds.isFinite, milliseconds < Double(Int.max) else { return nil }
        return min(Int(milliseconds.rounded(.towardZero)), max(0, durationMilliseconds - spotifyEndGuardMilliseconds))
    }

    /// Provider duration is quantized to whole milliseconds. Recover that
    /// value for comparisons without applying position's floor to binary noise.
    static func spotifyDurationMilliseconds(_ duration: Double) -> Int? {
        guard validDuration(duration) != nil else { return nil }
        let milliseconds = (duration * 1_000).rounded()
        guard milliseconds.isFinite, milliseconds > 0, milliseconds < Double(Int.max) else { return nil }
        return Int(milliseconds)
    }
}

struct MediaScrubContext: Equatable {
    let identity: MediaSourceIdentity
    let nativeTrackID: String?
    let duration: Double
    let player: MediaController.MediaPlayer
    let title: String
    let artist: String
    let generation: Int
}

struct MediaSeekRequest {
    let context: MediaScrubContext
    let position: Double
}

/// A cancelled gesture stays owned until release. Late binding writes from
/// that gesture must never create a fresh seek against the replacement track.
struct MediaScrubState {
    private(set) var isEditing = false
    private(set) var context: MediaScrubContext?
    private(set) var previewPosition: Double?

    mutating func begin(context: MediaScrubContext?, position: Double) {
        guard !isEditing else { return }
        isEditing = true
        self.context = context
        previewPosition = context.flatMap {
            MediaPlaybackTime.clampedSeekPosition(position, duration: $0.duration, player: $0.player)
        }
    }

    mutating func update(_ position: Double) {
        guard isEditing, let context else { return }
        guard let clamped = MediaPlaybackTime.clampedSeekPosition(position, duration: context.duration, player: context.player) else {
            cancel(retainingInteraction: true)
            return
        }
        previewPosition = clamped
    }

    mutating func reconcile(context current: MediaScrubContext?) {
        guard isEditing, context != current else { return }
        cancel(retainingInteraction: true)
    }

    mutating func finish(context current: MediaScrubContext?) -> MediaSeekRequest? {
        defer { cancel() }
        guard isEditing, let context, context == current, let previewPosition else { return nil }
        return MediaSeekRequest(context: context, position: previewPosition)
    }

    mutating func cancel(retainingInteraction: Bool = false) {
        isEditing = retainingInteraction && isEditing
        context = nil
        previewPosition = nil
    }
}
