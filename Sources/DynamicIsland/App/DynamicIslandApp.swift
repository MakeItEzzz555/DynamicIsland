import AppKit
import SwiftUI

@main
struct DynamicIslandApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let islandState = IslandStateStore()
    private let fileShelf = FileShelfStore()
    private let shortcuts = ShortcutsStore()
    private let media = MediaController()
    private let geometryService = NotchGeometryService()

    private var overlayController: OverlayWindowController?
    private var menuController: MenuBarController?
    private var settingsController: SettingsWindowController?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcuts.seedDefaultsIfNeeded()

        let modules = IslandModules(
            media: media,
            fileShelf: fileShelf,
            shortcuts: shortcuts
        )

        let overlayController = OverlayWindowController(
            settings: settings,
            islandState: islandState,
            modules: modules,
            geometryService: geometryService
        )
        self.overlayController = overlayController
        overlayController.show()
        LaunchAtLoginController.setEnabled(settings.launchAtLogin)

        menuController = MenuBarController(
            settings: settings,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onToggleOverlay: { [weak self] in self?.toggleOverlay() },
            onQuit: { NSApp.terminate(nil) }
        )

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.overlayController?.collapseFromOutsideClick()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    @objc private func displaysChanged() {
        overlayController?.reposition()
    }

    private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                settings: settings,
                shortcuts: shortcuts
            )
        }
        settingsController?.show()
    }

    private func toggleOverlay() {
        settings.overlayEnabled.toggle()
        overlayController?.setVisible(settings.overlayEnabled)
    }
}
