import Foundation

enum ExpandedIslandPage: CaseIterable {
    case island
    case tray

    var title: String {
        switch self {
        case .island:
            "Island"
        case .tray:
            "Tray"
        }
    }

    var symbolName: String {
        switch self {
        case .island:
            "sparkles"
        case .tray:
            "tray.full"
        }
    }

    var accessibilityLabel: String {
        "Show \(title) page"
    }
}

@MainActor
final class IslandNavigationStore: ObservableObject {
    @Published private(set) var selectedPage: ExpandedIslandPage = .island
    @Published private(set) var isFileDropTargeted = false

    func showIsland() {
        guard selectedPage != .island else { return }
        selectedPage = .island
        logPageChange()
    }

    func showTray() {
        guard selectedPage != .tray else { return }
        selectedPage = .tray
        logPageChange()
    }

    func showTrayForFileDrag() {
        let changedPage = selectedPage != .tray
        selectedPage = .tray
        if !isFileDropTargeted {
            isFileDropTargeted = true
        }
        if changedPage {
            logPageChange(reason: "file drag")
        }
    }

    func setFileDropTargeted(_ targeted: Bool) {
        guard isFileDropTargeted != targeted else { return }
        isFileDropTargeted = targeted
    }

    private func logPageChange(reason: String = "manual") {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        debugPrint("DynamicIsland expanded page changed", "page=\(selectedPage.title)", "reason=\(reason)")
        #endif
    }
}
