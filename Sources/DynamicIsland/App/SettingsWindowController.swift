import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(settings: AppSettings, shortcuts: ShortcutsStore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DynamicIsland Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, shortcuts: shortcuts))
        super.init()
        window.delegate = self
    }

    func show() {
        if !window.isVisible {
            window.center()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
