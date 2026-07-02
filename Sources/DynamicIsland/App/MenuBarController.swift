import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let settings: AppSettings
    private let onOpenSettings: () -> Void
    private let onToggleOverlay: () -> Void
    private let onQuit: () -> Void

    init(
        settings: AppSettings,
        onOpenSettings: @escaping () -> Void,
        onToggleOverlay: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onToggleOverlay = onToggleOverlay
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "DynamicIsland")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: settings.overlayEnabled ? "Hide Island" : "Show Island", action: #selector(toggleOverlay), keyEquivalent: "i"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DynamicIsland", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func toggleOverlay() {
        onToggleOverlay()
        rebuildMenu()
    }

    @objc private func quit() {
        onQuit()
    }
}
