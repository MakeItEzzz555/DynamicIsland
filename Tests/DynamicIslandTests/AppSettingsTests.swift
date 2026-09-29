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

    @MainActor
    func testExpandedLiveActivitiesSectionDefaultsToVisible() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.showExpandedLiveActivitiesSection)
    }

    @MainActor
    func testExpandedLiveActivitiesSectionVisibilityPersists() {
        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.showExpandedLiveActivitiesSection = false

        let secondSettings = AppSettings(defaults: defaults)

        XCTAssertFalse(secondSettings.showExpandedLiveActivitiesSection)
    }

    @MainActor
    func testResetAllSettingsRestoresExpandedLiveActivitiesSectionVisibility() {
        let settings = AppSettings(defaults: defaults)
        settings.showExpandedLiveActivitiesSection = false

        settings.resetAllSettings()

        XCTAssertTrue(settings.showExpandedLiveActivitiesSection)
    }

    @MainActor
    func testSystemHUDDefaultsAndPersistence() {
        let first = AppSettings(defaults: defaults)
        XCTAssertTrue(first.systemHUDsEnabled)
        XCTAssertTrue(first.volumeHUDEnabled)
        XCTAssertTrue(first.brightnessHUDEnabled)
        XCTAssertEqual(first.systemHUDDurationSeconds, 1.4, accuracy: 0.001)

        first.systemHUDsEnabled = false
        first.volumeHUDEnabled = false
        first.brightnessHUDEnabled = false
        first.systemHUDDurationSeconds = 2.2

        let second = AppSettings(defaults: defaults)
        XCTAssertFalse(second.systemHUDsEnabled)
        XCTAssertFalse(second.volumeHUDEnabled)
        XCTAssertFalse(second.brightnessHUDEnabled)
        XCTAssertEqual(second.systemHUDDurationSeconds, 2.2, accuracy: 0.001)
    }

    func testSystemHUDSnapshotSymbolsMatchState() {
        XCTAssertEqual(
            SystemHUDSnapshot(kind: .volume, value: 0, isMuted: true, updatedAt: .distantPast).symbolName,
            "speaker.slash.fill"
        )
        XCTAssertEqual(
            SystemHUDSnapshot(kind: .volume, value: 0.8, isMuted: false, updatedAt: .distantPast).symbolName,
            "speaker.wave.3.fill"
        )
        XCTAssertEqual(
            SystemHUDSnapshot(kind: .brightness, value: 0.5, isMuted: false, updatedAt: .distantPast).symbolName,
            "sun.max.fill"
        )
    }

    @MainActor
    func testClipboardHistoryDefaults() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.clipboardHistoryEnabled)
        XCTAssertEqual(settings.clipboardHistoryMaximumItems, 50)
        XCTAssertFalse(settings.clipboardHistoryPersistenceEnabled)
        XCTAssertTrue(settings.clipboardHistoryCaptureImagesEnabled)
    }

    @MainActor
    func testClipboardHistorySettingsPersist() {
        let first = AppSettings(defaults: defaults)
        first.clipboardHistoryEnabled = true
        first.clipboardHistoryMaximumItems = 75
        first.clipboardHistoryPersistenceEnabled = true
        first.clipboardHistoryCaptureImagesEnabled = false

        let second = AppSettings(defaults: defaults)

        XCTAssertTrue(second.clipboardHistoryEnabled)
        XCTAssertEqual(second.clipboardHistoryMaximumItems, 75)
        XCTAssertTrue(second.clipboardHistoryPersistenceEnabled)
        XCTAssertFalse(second.clipboardHistoryCaptureImagesEnabled)
    }

    @MainActor
    func testClipboardHistoryMaximumItemsClamps() {
        let settings = AppSettings(defaults: defaults)

        settings.clipboardHistoryMaximumItems = 1
        XCTAssertEqual(settings.clipboardHistoryMaximumItems, 10)
        settings.clipboardHistoryMaximumItems = 500
        XCTAssertEqual(settings.clipboardHistoryMaximumItems, 200)
    }

    @MainActor
    func testClipboardHistoryResetAllRestoresDefaultsAndRemovesKeys() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryMaximumItems = 99
        settings.clipboardHistoryPersistenceEnabled = true
        settings.clipboardHistoryCaptureImagesEnabled = false

        settings.resetAllSettings()

        XCTAssertFalse(settings.clipboardHistoryEnabled)
        XCTAssertEqual(settings.clipboardHistoryMaximumItems, 50)
        XCTAssertFalse(settings.clipboardHistoryPersistenceEnabled)
        XCTAssertTrue(settings.clipboardHistoryCaptureImagesEnabled)
        XCTAssertNil(defaults.object(forKey: "clipboardHistoryEnabled"))
        XCTAssertNil(defaults.object(forKey: "clipboardHistoryMaximumItems"))
        XCTAssertNil(defaults.object(forKey: "clipboardHistoryPersistenceEnabled"))
        XCTAssertNil(defaults.object(forKey: "clipboardHistoryCaptureImagesEnabled"))
    }

    @MainActor
    func testClipboardHistoryModuleResetRestoresDefaults() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryMaximumItems = 99
        settings.clipboardHistoryPersistenceEnabled = true
        settings.clipboardHistoryCaptureImagesEnabled = false

        settings.resetModuleSettings()

        XCTAssertFalse(settings.clipboardHistoryEnabled)
        XCTAssertEqual(settings.clipboardHistoryMaximumItems, 50)
        XCTAssertFalse(settings.clipboardHistoryPersistenceEnabled)
        XCTAssertTrue(settings.clipboardHistoryCaptureImagesEnabled)
    }
}
