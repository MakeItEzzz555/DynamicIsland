import AppKit
import Foundation

struct LauncherShortcut: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var target: String
    var symbolName: String

    init(id: UUID = UUID(), title: String, target: String, symbolName: String) {
        self.id = id
        self.title = title
        self.target = target
        self.symbolName = symbolName
    }
}

@MainActor
final class ShortcutsStore: ObservableObject {
    @Published var shortcuts: [LauncherShortcut] = [] {
        didSet { save() }
    }

    private let defaultsKey = "launcherShortcuts"

    init() {
        load()
    }

    func seedDefaultsIfNeeded() {
        guard shortcuts.isEmpty else { return }
        shortcuts = [
            LauncherShortcut(title: "Safari", target: "/Applications/Safari.app", symbolName: "safari"),
            LauncherShortcut(title: "Finder", target: "/System/Library/CoreServices/Finder.app", symbolName: "folder"),
            LauncherShortcut(title: "Settings", target: "/System/Applications/System Settings.app", symbolName: "gearshape")
        ]
    }

    func open(_ shortcut: LauncherShortcut) {
        if let url = URL(string: shortcut.target), url.scheme != nil {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: shortcut.target))
    }

    func update(_ shortcut: LauncherShortcut) {
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        shortcuts[index] = shortcut
    }

    func addDefault() {
        shortcuts.append(LauncherShortcut(title: "New", target: "https://apple.com", symbolName: "link"))
    }

    func remove(_ shortcut: LauncherShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([LauncherShortcut].self, from: data)
        else {
            return
        }
        shortcuts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
