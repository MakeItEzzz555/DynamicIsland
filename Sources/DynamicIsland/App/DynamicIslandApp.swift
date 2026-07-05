import AppKit
import Combine
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
    private lazy var fileShelf = FileShelfStore(settings: settings)
    private let shortcuts = ShortcutsStore()
    private let media = MediaController()
    private let timer = TimerController()
    private let stats = SystemStatsController()
    private let navigation = IslandNavigationStore()
    private let geometryService = NotchGeometryService()

    private var overlayController: OverlayWindowController?
    private var menuController: MenuBarController?
    private var settingsController: SettingsWindowController?
    private var eventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcuts.seedDefaultsIfNeeded()

        let modules = IslandModules(
            media: media,
            fileShelf: fileShelf,
            shortcuts: shortcuts,
            timer: timer,
            stats: stats,
            navigation: navigation
        )
        #if DEBUG
        debugPrint(
            "DynamicIsland AppDelegate modules",
            "mediaInstance=\(ObjectIdentifier(media))"
        )
        #endif

        let overlayController = OverlayWindowController(
            settings: settings,
            islandState: islandState,
            modules: modules,
            geometryService: geometryService,
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )
        self.overlayController = overlayController
        overlayController.show()
        LaunchAtLoginController.setEnabled(settings.launchAtLoginEnabled)

        settings.$launchAtLoginEnabled
            .removeDuplicates()
            .sink { enabled in
                LaunchAtLoginController.setEnabled(enabled)
            }
            .store(in: &cancellables)

        settings.$statsRefreshIntervalSeconds
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.stats.setRefreshInterval(interval)
            }
            .store(in: &cancellables)

        menuController = MenuBarController(
            settings: settings,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onToggleOverlay: { [weak self] in self?.toggleOverlay() },
            onQuit: { NSApp.terminate(nil) }
        )

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
