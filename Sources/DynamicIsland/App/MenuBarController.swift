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
    private let onEditWorkspace: () -> Void
    private let onOpenClipboard: () -> Void
    private let onNextPage: () -> Void
    private let onPreviousPage: () -> Void
    private let onToggleLiveAudio: () -> Void

    init(
        settings: AppSettings,
        onOpenSettings: @escaping () -> Void,
        onToggleOverlay: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        hiddenBasketCount: @escaping () -> Int = { 0 },
        onShowBaskets: @escaping () -> Void = {},
        onEditWorkspace: @escaping () -> Void = {},
        onOpenClipboard: @escaping () -> Void = {},
        onNextPage: @escaping () -> Void = {},
        onPreviousPage: @escaping () -> Void = {},
        onToggleLiveAudio: @escaping () -> Void = {}
    ) {
        self.onToggleLiveAudio = onToggleLiveAudio
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onToggleOverlay = onToggleOverlay
        self.onQuit = onQuit
        self.hiddenBasketCount = hiddenBasketCount
        self.onShowBaskets = onShowBaskets
        self.onEditWorkspace = onEditWorkspace
        self.onOpenClipboard = onOpenClipboard
        self.onNextPage = onNextPage
        self.onPreviousPage = onPreviousPage
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "DynamicIsland")
        statusItem.isVisible = settings.menuBarIconEnabled
        rebuildMenu()
    }

    func setVisible(_ visible: Bool) { statusItem.isVisible = visible }

    func makeNotchMenu() -> NSMenu {
        let menu = NSMenu(title: "Island")
        menu.autoenablesItems = false
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(item("Customize Workspace…", #selector(editWorkspace)))
        let clipboard = NSMenuItem(title: "Clipboard", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Clipboard")
        submenu.autoenablesItems = false
        let history = item("Open Clipboard History", #selector(openClipboard))
        history.isEnabled = settings.clipboardHistoryEnabled
        submenu.addItem(history)
        clipboard.submenu = submenu
        clipboard.isEnabled = settings.clipboardHistoryEnabled
        menu.addItem(clipboard)
        menu.addItem(liveAudioItem())
        menu.addItem(.separator())
        menu.addItem(item("Previous Page", #selector(previousPage)))
        menu.addItem(item("Next Page", #selector(nextPage)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Island", #selector(quit)))
        return menu
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        populate(menu)
        menu.delegate = self
        statusItem.menu = menu
    }

    private func populate(_ menu: NSMenu) {
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Edit Workspace...", action: #selector(editWorkspace), keyEquivalent: ""))
        if settings.clipboardHistoryEnabled {
            menu.addItem(NSMenuItem(title: "Clipboard History", action: #selector(openClipboard), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Next Page", action: #selector(nextPage), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Previous Page", action: #selector(previousPage), keyEquivalent: ""))
        menu.addItem(liveAudioItem())
        if !settings.showNavigationControls {
            menu.addItem(NSMenuItem(title: "Show Navigation Controls", action: #selector(showNavigation), keyEquivalent: ""))
        }
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

    @objc private func editWorkspace() { onEditWorkspace() }
    @objc private func toggleLiveAudio() { onToggleLiveAudio() }

    /// Checked from the saved preference (desired state), not capture status.
    private func liveAudioItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Live Audio", action: #selector(toggleLiveAudio), keyEquivalent: "")
        item.target = self
        item.state = settings.liveAudioVisualizerEnabled ? .on : .off
        return item
    }
    @objc private func openClipboard() {
        if settings.clipboardHistoryEnabled { onOpenClipboard() }
    }
    @objc private func nextPage() { onNextPage() }
    @objc private func previousPage() { onPreviousPage() }
    @objc private func showNavigation() { settings.showNavigationControls = true }

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
