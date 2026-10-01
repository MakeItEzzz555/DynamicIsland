import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: AppSettings
    private let onOpenSettings: () -> Void
    private let onToggleOverlay: () -> Void
    private let onQuit: () -> Void
    private let hiddenBasketCount: () -> Int
    private let onShowBaskets: () -> Void

    init(
        settings: AppSettings,
        onOpenSettings: @escaping () -> Void,
        onToggleOverlay: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        hiddenBasketCount: @escaping () -> Int = { 0 },
        onShowBaskets: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onToggleOverlay = onToggleOverlay
        self.onQuit = onQuit
        self.hiddenBasketCount = hiddenBasketCount
        self.onShowBaskets = onShowBaskets
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "DynamicIsland")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        populate(menu)
        menu.delegate = self
        statusItem.menu = menu
    }

    private func populate(_ menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: settings.overlayEnabled ? "Hide Island" : "Show Island", action: #selector(toggleOverlay), keyEquivalent: "i"))
        // Recovery for auto-hidden Floating Baskets that still hold files.
        let hiddenBaskets = hiddenBasketCount()
        if hiddenBaskets > 0 {
            menu.addItem(NSMenuItem(
                title: hiddenBaskets == 1 ? "Show Hidden Basket" : "Show \(hiddenBaskets) Hidden Baskets",
                action: #selector(showBaskets),
                keyEquivalent: ""
            ))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DynamicIsland", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Refreshed in place right before display so counts are current.
        menu.removeAllItems()
        populate(menu)
    }

    @objc private func showBaskets() {
        onShowBaskets()
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
