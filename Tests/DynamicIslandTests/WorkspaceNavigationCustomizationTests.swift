import XCTest
@testable import DynamicIsland

@MainActor
final class WorkspaceNavigationCustomizationTests: XCTestCase {
    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "WorkspaceNavigationCustomizationTests-\(UUID().uuidString)")!)
    }
    func testConfiguredOrderControlsNavigationSwipes() {
        let settings = settings()
        settings.showAgentsTab = true
        settings.showTimerTab = true
        settings.agentActivityEnabled = true
        settings.timerEnabled = true
        let navigation = IslandNavigationStore()
        var config = NavigationTabConfiguration.initial
        config.move(.timer, before: .agents)
        config.move(.timer, before: .island)
        navigation.applyConfiguration(config, using: settings)
        XCTAssertEqual(navigation.availablePages(using: settings).first, .timer)
        navigation.select(.timer)
        navigation.selectNextPage(using: settings)
        XCTAssertEqual(navigation.selectedPage, .island)
        navigation.selectPreviousPage(using: settings)
        XCTAssertEqual(navigation.selectedPage, .timer)
    }
    func testHiddenSelectedTabFallsBackAndCanRestore() {
        let settings = settings()
        settings.showTimerTab = true; settings.timerEnabled = true
        let navigation = IslandNavigationStore()
        navigation.select(.timer)
        var config = NavigationTabConfiguration.initial
        config.setVisible(.timer, visible: false)
        navigation.applyConfiguration(config, using: settings)
        XCTAssertEqual(navigation.selectedPage, .island)
        XCTAssertFalse(navigation.availablePages(using: settings).contains(.timer))
        config.setVisible(.timer, visible: true)
        navigation.applyConfiguration(config, using: settings)
        XCTAssertTrue(navigation.availablePages(using: settings).contains(.timer))
    }
    func testGlobalFeatureGatesCannotBeBypassedByLayout() {
        let settings = settings()
        settings.agentActivityEnabled = false
        settings.timerEnabled = false
        settings.statsEnabled = false
        settings.trayEnabled = false
        let navigation = IslandNavigationStore()
        navigation.applyConfiguration(NavigationTabConfiguration.initial, using: settings)
        XCTAssertFalse(navigation.availablePages(using: settings).contains(.agents))
        XCTAssertFalse(navigation.availablePages(using: settings).contains(.timer))
        XCTAssertFalse(navigation.availablePages(using: settings).contains(.stats))
        XCTAssertFalse(navigation.availablePages(using: settings).contains(.tray))
        XCTAssertTrue(navigation.availablePages(using: settings).contains(.island))
    }
    func testRequiredIslandAndRuntimeMessagesCannotBeHidden() {
        let settings = settings()
        let navigation = IslandNavigationStore()
        let config = NavigationTabConfiguration(order: [.tools, .timer], hidden: Set(ExpandedIslandPage.allCases))
        navigation.hasActionableMessages = true
        navigation.applyConfiguration(config, using: settings)
        XCTAssertEqual(Set(navigation.availablePages(using: settings)), Set([.island, .messages]))
        navigation.showMessages()
        navigation.hasActionableMessages = false
        navigation.ensureValidSelection(using: settings)
        XCTAssertEqual(navigation.selectedPage, .island)
    }
    func testNavigationPersistenceDoesNotHideTimerWidget() {
        let preferences = UserDefaults(suiteName: "WorkspaceNavigationPersistence-\(UUID().uuidString)")!
        let store = WorkspaceCustomizationStore(defaults: preferences)
        var config = store.configuration
        config.navigation.move(.tools, before: .agents)
        config.navigation.setVisible(.timer, visible: false)
        config.add(.timer, on: .media)
        store.commit(config)
        let restored = WorkspaceCustomizationStore(defaults: preferences).configuration
        XCTAssertEqual(restored.navigation, config.navigation.normalized())
        XCTAssertTrue(restored.navigation.hidden.contains(.timer))
        XCTAssertTrue(restored.widgets(on: .media).contains { $0.kind == .timer })
    }
    func testDirectActionsCannotSelectHiddenTabsAndRestoreMakesThemReachable() {
        let settings = settings()
        let navigation = IslandNavigationStore()
        var config = NavigationTabConfiguration.initial
        for page in [ExpandedIslandPage.timer, .agents, .stats, .tray] {
            config.setVisible(page, visible: false)
        }
        navigation.applyConfiguration(config, using: settings)
        navigation.showTimer()
        XCTAssertEqual(navigation.selectedPage, .island)
        navigation.showAgents()
        XCTAssertEqual(navigation.selectedPage, .island)
        navigation.showStats()
        XCTAssertEqual(navigation.selectedPage, .island)
        navigation.showTray()
        XCTAssertEqual(navigation.selectedPage, .island)
        navigation.select(.timer)
        XCTAssertEqual(navigation.selectedPage, .island)
        for page in [ExpandedIslandPage.timer, .agents, .stats, .tray] {
            config.setVisible(page, visible: true)
        }
        navigation.applyConfiguration(config, using: settings)
        navigation.showTimer()
        XCTAssertEqual(navigation.selectedPage, .timer)
        navigation.showAgents()
        XCTAssertEqual(navigation.selectedPage, .agents)
        navigation.showStats()
        XCTAssertEqual(navigation.selectedPage, .stats)
        navigation.showTray()
        XCTAssertEqual(navigation.selectedPage, .tray)
    }

}
