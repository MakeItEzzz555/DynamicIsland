import Foundation

enum ExpandedIslandPage: CaseIterable {
    case island
    case agents
    case tray
    case timer
    case stats
    case tools
    case messages

    var title: String {
        switch self {
        case .island:
            "Island"
        case .agents:
            "Agents"
        case .tray:
            "Tray"
        case .timer:
            "Timer"
        case .stats:
            "Stats"
        case .tools:
            "Tools"
        case .messages:
            "Messages"
        }
    }

    var symbolName: String {
        switch self {
        case .island:
            "sparkles"
        case .agents:
            "cpu"
        case .tray:
            "tray.fill"
        case .timer:
            "timer"
        case .stats:
            "chart.xyaxis.line"
        case .tools:
            "wand.and.stars"
        case .messages:
            "message.fill"
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
    /// Runtime availability of the Messages page: true only while a
    /// visible incoming message is queued.
    @Published var hasActionableMessages = false

    func availablePages(using settings: AppSettings) -> [ExpandedIslandPage] {
        var pages: [ExpandedIslandPage] = [.island]
        if hasActionableMessages {
            pages.append(.messages)
        }
        if settings.agentActivityEnabled && settings.showAgentsTab {
            pages.append(.agents)
        }
        if settings.trayEnabled && settings.showTrayTab {
            pages.append(.tray)
        }
        if settings.timerEnabled && settings.showTimerTab {
            pages.append(.timer)
        }
        if settings.statsEnabled && settings.showStatsTab {
            pages.append(.stats)
        }
        if settings.showToolsTab {
            pages.append(.tools)
        }
        return pages
    }

    func ensureValidSelection(using settings: AppSettings) {
        let pages = availablePages(using: settings)
        guard !pages.contains(selectedPage) else { return }
        selectedPage = resolvedDefaultPage(using: settings, availablePages: pages)
        logPageChange(reason: "settings fallback")
    }

    func applyDefaultSelectionIfNeeded(using settings: AppSettings) {
        selectedPage = resolvedDefaultPage(using: settings, availablePages: availablePages(using: settings))
        logPageChange(reason: "default selection")
    }

    func showIsland() {
        select(.island)
    }

    func showAgents() {
        select(.agents)
    }

    func showTray() {
        select(.tray)
    }

    func showTimer() {
        select(.timer)
    }

    func showStats() {
        select(.stats)
    }

    func showMessages() {
        guard hasActionableMessages else { return }
        select(.messages)
    }

    func select(_ page: ExpandedIslandPage) {
        guard selectedPage != page else { return }
        selectedPage = page
        logPageChange()
    }

    func selectNextPage(using settings: AppSettings) {
        selectAdjacentPage(offset: 1, using: settings)
    }

    func selectPreviousPage(using settings: AppSettings) {
        selectAdjacentPage(offset: -1, using: settings)
    }

    func showTrayForFileDrag(using settings: AppSettings) {
        guard settings.trayEnabled, settings.fileShelfEnabled, settings.showTrayTab else { return }
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

    func endFileDropTargeting() {
        setFileDropTargeted(false)
    }

    private func logPageChange(reason: String = "manual") {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        debugPrint("DynamicIsland expanded page changed", "page=\(selectedPage.title)", "reason=\(reason)")
        #endif
    }

    private func selectAdjacentPage(offset: Int, using settings: AppSettings) {
        let pages = availablePages(using: settings)
        guard pages.count > 1 else { return }
        guard let currentIndex = pages.firstIndex(of: selectedPage) else {
            selectedPage = resolvedDefaultPage(using: settings, availablePages: pages)
            logPageChange(reason: "gesture fallback")
            return
        }

        let nextIndex = (currentIndex + offset + pages.count) % pages.count
        guard pages[nextIndex] != selectedPage else { return }
        selectedPage = pages[nextIndex]
        logPageChange(reason: "gesture")
    }

    private func resolvedDefaultPage(using settings: AppSettings, availablePages: [ExpandedIslandPage]) -> ExpandedIslandPage {
        let preferred: ExpandedIslandPage
        switch settings.defaultExpandedTab {
        case .island, .activities, .liveActivities, .gestures:
            preferred = .island
        case .tray:
            preferred = .tray
        case .timer:
            preferred = .timer
        case .stats:
            preferred = .stats
        }
        return availablePages.contains(preferred) ? preferred : (availablePages.first ?? .island)
    }
}
