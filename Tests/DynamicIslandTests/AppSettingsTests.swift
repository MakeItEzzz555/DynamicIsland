import XCTest
@testable import DynamicIsland

final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "AppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    @MainActor
    func testInvalidIslandThemeStyleFallsBackToClassicBlack() {
        defaults.set("unsupported-theme", forKey: "islandThemeStyle")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.islandThemeStyle, .classicBlack)
    }

    @MainActor
    func testIslandThemeStylePersistsRawValue() {
        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.islandThemeStyle = .liquidGlass

        let secondSettings = AppSettings(defaults: defaults)

        XCTAssertEqual(secondSettings.islandThemeStyle, .liquidGlass)
    }

    @MainActor
    func testLegacyHybridIslandThemeStyleMigratesToLiquidGlass() {
        defaults.set("hybridBlackGlass", forKey: "islandThemeStyle")
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.islandThemeStyle, .liquidGlass)
        XCTAssertEqual(defaults.string(forKey: "islandThemeStyle"), IslandThemeStyle.liquidGlass.rawValue)
    }

    @MainActor
    func testCollapsedLiveActivityPrioritiesClampAndReset() {
        defaults.set(500, forKey: "collapsedPriorityRunningTimer")
        defaults.set(-20, forKey: "collapsedPriorityPausedMedia")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.collapsedPriorityRunningTimer, 200)
        XCTAssertEqual(settings.collapsedPriorityPausedMedia, 0)

        settings.resetCollapsedLiveActivityPrioritySettings()

        XCTAssertEqual(settings.collapsedPriorityRunningTimer, CollapsedLiveActivityPrioritySource.runningTimer.defaultPriority)
        XCTAssertEqual(settings.collapsedPriorityPausedMedia, CollapsedLiveActivityPrioritySource.pausedMedia.defaultPriority)
    }
}
