import AppKit
import SwiftUI

@MainActor
private final class SettingsWindow: NSWindow, CameraLocalEventWindow {
    var cameraEventGate: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        guard cameraEventGate?(event) != false else { return }
        super.sendEvent(event)
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    static let minimumContentSize = NSSize(width: 720, height: 560)
    let window: NSWindow
    private let settings: AppSettings

    static func resetPanelSize(_ window: NSWindow) -> Bool {
        guard !window.styleMask.contains(.fullScreen), window.attachedSheet == nil else { return false }
        window.setContentSize(NSSize(width: 720, height: 700))
        window.center()
        return true
    }

    static func makeWindow(frameAutosaveName: String = "DynamicIsland.Settings") -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DynamicIsland Settings"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.contentMinSize = minimumContentSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName(frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(frameAutosaveName)
        return window
    }

    init(
        settings: AppSettings,
        shortcuts: ShortcutsStore,
        agentIngestion: AgentIngestionCoordinator,
        agentEvents: AgentEventStore,
        productivity: ProductivityModules,
        agentManagedControl: AgentManagedSessionController? = nil,
        agentProjects: AgentProjectProjectionStore? = nil,
        messaging: MessagingController? = nil,
        faceTime: FaceTimeAccessibilityProvider? = nil,
        cameraNavigation: CameraNavigationController? = nil,
        previews: SettingsPreviewDependencies? = nil,
        navigation: SettingsNavigationStore? = nil,
        frameAutosaveName: String = "DynamicIsland.Settings"
    ) {
        self.settings = settings
        window = Self.makeWindow(frameAutosaveName: frameAutosaveName)
        let settingsWindow = window
        window.contentView = NSHostingView(
            rootView: SettingsView(
                settings: settings,
                shortcuts: shortcuts,
                agentIngestion: agentIngestion,
                agentEvents: agentEvents,
                productivity: productivity,
                agentManagedControl: agentManagedControl,
                agentProjects: agentProjects,
                messaging: messaging,
                faceTime: faceTime,
                cameraNavigation: cameraNavigation,
                previews: previews,
                navigation: navigation,
                resetPanelSize: { [weak settingsWindow] in
                    guard let settingsWindow else { return false }
                    return Self.resetPanelSize(settingsWindow)
                }
            )
        )
        super.init()
        window.delegate = self
    }

    func show() {
        installWindowCommands()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    static func makeWindowMenu(target: AnyObject) -> NSMenu {
        let menu = NSMenu(title: "Window")
        let commands: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Settings…", #selector(showSettings(_:)), ",", .command),
            ("Close Settings", #selector(closeSettings(_:)), "w", .command),
            ("Minimize", #selector(minimizeSettings(_:)), "m", .command),
            ("Enter Full Screen", #selector(fullscreenSettings(_:)), "f", [.command, .control])]
        for (title, action, key, modifiers) in commands {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers; item.target = target
        }
        return menu
    }
    private func installWindowCommands() {
        EditMenuInstaller.installIfNeeded()
        guard let main = NSApp.mainMenu else { return }
        let identifier = NSUserInterfaceItemIdentifier("DynamicIsland.Settings.Window")
        let item = main.items.first { $0.identifier == identifier } ?? NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        item.identifier = identifier
        item.submenu = Self.makeWindowMenu(target: self)
        if item.menu == nil { main.addItem(item) }
        NSApp.windowsMenu = item.submenu
    }
    @objc private func showSettings(_ sender: Any?) { show() }
    @objc private func closeSettings(_ sender: Any?) { window.performClose(sender) }
    @objc private func minimizeSettings(_ sender: Any?) { window.performMiniaturize(sender) }
    @objc private func fullscreenSettings(_ sender: Any?) { window.toggleFullScreen(sender) }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(showSettings(_:)) { return true }
        if item.action == #selector(fullscreenSettings(_:)) {
            item.title = window.styleMask.contains(.fullScreen) ? "Exit Full Screen" : "Enter Full Screen"
        }
        return window.isVisible && window.isKeyWindow && window.attachedSheet == nil
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(settings.dockIconEnabled ? .regular : .accessory)
    }
}
