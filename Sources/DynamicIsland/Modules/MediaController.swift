import AppKit
import Foundation

@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var title = "Nothing Playing"
    @Published private(set) var artist = "Open Spotify or Music"
    @Published private(set) var isPlaying = false
    @Published private(set) var sourceName = "Media"
    @Published private(set) var artworkImage: NSImage?
    @Published private(set) var playbackPosition: Double = 0
    @Published private(set) var duration: Double = 1

    private var activePlayer: MediaPlayer = .spotify
    private var refreshTimer: Timer?
    private var currentArtworkURL: String?
    private var lastPlaybackIdentity: String?
    private var lastPlaybackPosition: Double?
    private var lastPlaybackAdvancedAt: Date?
    private var isScrubbing = false

    private enum MediaPlayer: String, CaseIterable {
        case spotify = "Spotify"
        case music = "Music"

        var displayName: String {
            rawValue
        }

        var playPauseCommand: String {
            switch self {
            case .spotify:
                "playpause"
            case .music:
                "playpause"
            }
        }
    }

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        if readPlayer(.spotify) {
            return
        }
        if readPlayer(.music) {
            return
        }
        if readBrowserAudio() {
            return
        }
        title = "Nothing Playing"
        artist = "Open Spotify or Music"
        isPlaying = false
        sourceName = "Media"
        artworkImage = nil
        currentArtworkURL = nil
        lastPlaybackIdentity = nil
        lastPlaybackPosition = nil
        lastPlaybackAdvancedAt = nil
        playbackPosition = 0
        duration = 1
    }

    func playPause() {
        send(command: activePlayer.playPauseCommand, to: activePlayer)
        refresh()
    }

    func nextTrack() {
        send(command: "next track", to: activePlayer)
        refresh()
    }

    func previousTrack() {
        send(command: "previous track", to: activePlayer)
        refresh()
    }

    func updateScrubPosition(_ position: Double) {
        isScrubbing = true
        playbackPosition = min(max(0, position), duration)
    }

    func seek(to position: Double) {
        let clampedPosition = min(max(0, position), duration)
        send(command: "set player position to \(clampedPosition)", to: activePlayer)
        isScrubbing = false
        refresh()
    }

    private func readPlayer(_ player: MediaPlayer) -> Bool {
        let script = """
        with timeout of 1 seconds
            tell application "\(player.rawValue)"
                if it is running then
                    if player state is playing then
                        return (name of current track) & "||" & (artist of current track) & "||playing||\(player.displayName)" & "||" & (player position as text) & "||" & (\(durationExpression(for: player)) as text) & "||" & \(artworkExpression(for: player))
                    else if player state is paused then
                        return (name of current track) & "||" & (artist of current track) & "||paused||\(player.displayName)" & "||" & (player position as text) & "||" & (\(durationExpression(for: player)) as text) & "||" & \(artworkExpression(for: player))
                    end if
                end if
            end tell
        end timeout
        return ""
        """
        if let result = runAppleScript(script), !result.isEmpty {
            let parts = result.components(separatedBy: "||")
            if parts.count >= 4 {
                title = parts[0]
                artist = parts[1]
                let reportedPlaybackState = parts[2]
                sourceName = parts[3]
                activePlayer = player
                let parsedPlaybackPosition = Double(parts[safe: 4] ?? "") ?? playbackPosition
                let playbackIdentity = "\(player.rawValue)||\(title)||\(artist)"
                if lastPlaybackIdentity != playbackIdentity {
                    lastPlaybackAdvancedAt = nil
                }
                let playbackPositionAdvanced = lastPlaybackIdentity == playbackIdentity &&
                    parsedPlaybackPosition > ((lastPlaybackPosition ?? parsedPlaybackPosition) + 0.08)
                if playbackPositionAdvanced {
                    lastPlaybackAdvancedAt = Date()
                }
                let recentlyAdvanced = lastPlaybackIdentity == playbackIdentity &&
                    lastPlaybackAdvancedAt.map { Date().timeIntervalSince($0) < 1.6 } == true
                isPlaying = reportedPlaybackState == "playing" || playbackPositionAdvanced || recentlyAdvanced
                if !isScrubbing {
                    playbackPosition = parsedPlaybackPosition
                }
                lastPlaybackIdentity = playbackIdentity
                lastPlaybackPosition = parsedPlaybackPosition
                duration = max(1, Double(parts[safe: 5] ?? "") ?? duration)
                if parts.count > 6 {
                    loadArtwork(from: parts[6])
                }
                return true
            }
        }
        return false
    }

    private func readBrowserAudio() -> Bool {
        let browserScripts = [
            browserScript(applicationName: "Safari", usesChromeScripting: false),
            browserScript(applicationName: "Google Chrome", usesChromeScripting: true),
            browserScript(applicationName: "Microsoft Edge", usesChromeScripting: true),
            browserScript(applicationName: "Brave Browser", usesChromeScripting: true)
        ]

        for script in browserScripts {
            if runAppleScript(script) == "playing" {
                title = "Browser Audio"
                artist = "Safari, Chrome, Edge, or Brave"
                isPlaying = true
                sourceName = "Browser"
                artworkImage = nil
                currentArtworkURL = nil
                lastPlaybackIdentity = nil
                lastPlaybackPosition = nil
                lastPlaybackAdvancedAt = nil
                playbackPosition = 0
                duration = 1
                return true
            }
        }
        return false
    }

    private func browserScript(applicationName: String, usesChromeScripting: Bool) -> String {
        let mediaCheck = """
        (() => Array.from(document.querySelectorAll('video,audio')).some(element => !element.paused && !element.muted && element.readyState > 1))()
        """
        if usesChromeScripting {
            return """
            with timeout of 1 seconds
                tell application "\(applicationName)"
                    if it is running then
                        repeat with browserWindow in windows
                            repeat with browserTab in tabs of browserWindow
                                try
                                    if execute browserTab javascript "\(Self.appleScriptEscaped(mediaCheck))" is true then return "playing"
                                end try
                            end repeat
                        end repeat
                    end if
                end tell
            end timeout
            return ""
            """
        }

        return """
        with timeout of 1 seconds
            tell application "\(applicationName)"
                if it is running then
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                if do JavaScript "\(Self.appleScriptEscaped(mediaCheck))" in browserTab is true then return "playing"
                            end try
                        end repeat
                    end repeat
                end if
            end tell
        end timeout
        return ""
        """
    }

    private func artworkExpression(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            "artwork url of current track"
        case .music:
            "\"\""
        }
    }

    private func durationExpression(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            "((duration of current track) / 1000)"
        case .music:
            "duration of current track"
        }
    }

    private func loadArtwork(from rawValue: String) {
        guard let url = URL(string: rawValue), !rawValue.isEmpty else {
            artworkImage = nil
            currentArtworkURL = nil
            return
        }
        guard rawValue != currentArtworkURL else { return }
        currentArtworkURL = rawValue

        Task {
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = NSImage(data: data)
            else {
                return
            }
            await MainActor.run {
                self.artworkImage = image
            }
        }
    }

    private func send(command: String, to player: MediaPlayer) {
        _ = runAppleScript("tell application \"\(player.rawValue)\" to \(command)")
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let output = script?.executeAndReturnError(&error)
        return output?.stringValue
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
