import AppKit
import SwiftUI

/// Settings-only audition. macOS secure-screen integration remains unavailable.
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

struct SettingsLockSoundPreview: View {
    @StateObject private var model: SettingsLockSoundModel
    init(defaults: UserDefaults) { _model = StateObject(wrappedValue: SettingsLockSoundModel(defaults: defaults)) }
    var body: some View {
        SettingsGroup("Lock / unlock sound preview") {
            soundRow("Lock sound", selection: $model.lock)
            soundRow("Unlock sound", selection: $model.unlock)
            Slider(value: $model.volume, in: 0...1) { Text("Preview volume") }.controlSize(.small)
            Text("Preview settings only; not applied to the macOS Lock Screen. Default auditions the system Glass tone. Selecting a preset never plays it automatically.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.onDisappear { model.stop() }
    }
    private func soundRow(_ title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(SettingsLockSoundModel.availableNames, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).labelsHidden().frame(width: 170)
            Button("Preview") { model.preview(selection.wrappedValue) }
                .disabled(selection.wrappedValue == "None")
                .accessibilityLabel("Preview \(title.lowercased())")
        }
    }
}
