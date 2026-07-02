import AppKit
import Foundation

@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var title = "Nothing Playing"
    @Published private(set) var artist = "Open Music or another player"
    @Published private(set) var isPlaying = false

    init() {
        refresh()
    }

    func refresh() {
        let script = """
        tell application "Music"
            if it is running then
                if player state is playing then
                    return (name of current track) & "||" & (artist of current track) & "||playing"
                else if player state is paused then
                    return (name of current track) & "||" & (artist of current track) & "||paused"
                end if
            end if
        end tell
        return "Nothing Playing||Open Music or another player||stopped"
        """
        if let result = runAppleScript(script) {
            let parts = result.components(separatedBy: "||")
            if parts.count == 3 {
                title = parts[0]
                artist = parts[1]
                isPlaying = parts[2] == "playing"
            }
        }
    }

    func playPause() {
        _ = runAppleScript("tell application \"Music\" to playpause")
        refresh()
    }

    func nextTrack() {
        _ = runAppleScript("tell application \"Music\" to next track")
        refresh()
    }

    func previousTrack() {
        _ = runAppleScript("tell application \"Music\" to previous track")
        refresh()
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let output = script?.executeAndReturnError(&error)
        return output?.stringValue
    }
}
