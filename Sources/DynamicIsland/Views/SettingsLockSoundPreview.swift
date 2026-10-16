import AppKit
import SwiftUI

/// Lock/unlock sound catalog shared by Settings and the lock-screen coordinator.
@MainActor
final class SettingsLockSoundModel: ObservableObject {
    static let names = ["Default", "None", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    static var availableNames: [String] { names.filter { $0 == "Default" || $0 == "None" || FileManager.default.fileExists(atPath: soundURL($0).path) } }
    static func soundURL(_ name: String) -> URL { URL(fileURLWithPath: "/System/Library/Sounds").appendingPathComponent(name + ".aiff") }
    @Published var lock: String { didSet { defaults.set(lock, forKey: "settings.lockPreview.lockSound") } }
    @Published var unlock: String { didSet { defaults.set(unlock, forKey: "settings.lockPreview.unlockSound") } }
    @Published var volume = 0.5
    @Published private(set) var message: String?
    private let defaults: UserDefaults
    private var sound: NSSound?
    init(defaults: UserDefaults) {
        self.defaults = defaults
        let storedLock = defaults.string(forKey: "settings.lockPreview.lockSound") ?? "Default"
        let storedUnlock = defaults.string(forKey: "settings.lockPreview.unlockSound") ?? "Default"
        lock = Self.availableNames.contains(storedLock) ? storedLock : "Default"
        unlock = Self.availableNames.contains(storedUnlock) ? storedUnlock : "Default"
    }
    func preview(_ name: String) {
        stop()
        guard name != "None", Self.availableNames.contains(name) else { return }
        guard let sample = NSSound(contentsOf: Self.soundURL(name == "Default" ? "Glass" : name), byReference: true) else {
            message = "This sound is unavailable on this Mac."; return
        }
        sample.volume = Float(volume); sound = sample
        message = sample.play() ? "Preview playing. System mute and output volume still apply." : "macOS could not play the sound."
    }
    func stop() { sound?.stop(); sound = nil; message = nil }
}
