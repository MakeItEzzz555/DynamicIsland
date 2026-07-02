import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(settings: AppSettings, shortcuts: ShortcutsStore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DynamicIsland Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, shortcuts: shortcuts))
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
