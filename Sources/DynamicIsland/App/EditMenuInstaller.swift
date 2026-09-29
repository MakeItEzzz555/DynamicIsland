import AppKit

/// Installs a standard Edit menu so Command-A/C/V/X/Z reach text editors and
/// selectable text in the island and Settings. The app is an accessory, so
/// the menu is only visible while Settings temporarily makes it regular.
/// Deliberately contains no Quit item: the island panel can be key while
/// another app is frontmost.
@MainActor
enum EditMenuInstaller {
    static let editMenuTitle = "Edit"

    static func installIfNeeded(on application: NSApplication = .shared) {
        let mainMenu = application.mainMenu ?? NSMenu(title: "Main")
        if mainMenu.items.contains(where: { $0.submenu?.title == editMenuTitle }) {
            return
        }
        if mainMenu.items.isEmpty {
            // AppKit treats the first item as the application menu.
            let appItem = NSMenuItem()
            appItem.submenu = NSMenu(title: "DynamicIsland")
            mainMenu.addItem(appItem)
        }
        let editItem = NSMenuItem()
        editItem.submenu = makeEditMenu()
        mainMenu.addItem(editItem)
        application.mainMenu = mainMenu
    }

    static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: editMenuTitle)
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        return menu
    }
}
