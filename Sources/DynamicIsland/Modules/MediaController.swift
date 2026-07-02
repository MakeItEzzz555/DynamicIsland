import AppKit
import Foundation

@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var title = "Nothing Playing"
    @Published private(set) var artist = "Open Spotify or Music"
    @Published private(set) var isPlaying = false
    @Published private(set) var sourceName = "Media"
    @Published private(set) var artworkImage: NSImage?

    private var activePlayer: MediaPlayer = .spotify
    private var refreshTimer: Timer?
    private var currentArtworkURL: String?

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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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
        title = "Nothing Playing"
        artist = "Open Spotify or Music"
        isPlaying = false
        sourceName = "Media"
        artworkImage = nil
        currentArtworkURL = nil
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

    private func readPlayer(_ player: MediaPlayer) -> Bool {
        let script = """
        tell application "\(player.rawValue)"
            if it is running then
                if player state is playing then
                    return (name of current track) & "||" & (artist of current track) & "||playing||\(player.displayName)" & "||" & \(artworkExpression(for: player))
                else if player state is paused then
                    return (name of current track) & "||" & (artist of current track) & "||paused||\(player.displayName)" & "||" & \(artworkExpression(for: player))
                end if
            end if
        end tell
        return ""
        """
        if let result = runAppleScript(script), !result.isEmpty {
            let parts = result.components(separatedBy: "||")
            if parts.count >= 4 {
                title = parts[0]
                artist = parts[1]
                isPlaying = parts[2] == "playing"
                sourceName = parts[3]
                activePlayer = player
                if parts.count > 4 {
                    loadArtwork(from: parts[4])
                }
                return true
            }
        }
        return false
    }

    private func artworkExpression(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            "artwork url of current track"
        case .music:
            "\"\""
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
}
