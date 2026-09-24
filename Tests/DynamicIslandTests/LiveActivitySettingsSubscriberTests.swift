import Combine
import XCTest
@testable import DynamicIsland

final class LiveActivitySettingsSubscriberTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "LiveActivitySettingsSubscriberTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    @MainActor
    func testPublisherDeliversNewValueWithoutPostCommitRead() {
        let settings = AppSettings(defaults: defaults)
        var receivedSnapshot: LiveActivitySettingsSnapshot?
        var storedValueDuringCallback: Bool?
        let subscription = settings.liveActivitySettingsPublisher
            .dropFirst()
            .sink { snapshot in
                receivedSnapshot = snapshot
                storedValueDuringCallback = settings.liveActivitiesEnabled
            }

        settings.liveActivitiesEnabled = false

        XCTAssertEqual(receivedSnapshot?.liveActivitiesEnabled, false)
        XCTAssertEqual(storedValueDuringCallback, true)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testGlobalSettingTransitionsEmitOnceInBothDirections() {
        let settings = AppSettings(defaults: defaults)
        var receivedValues: [Bool] = []
        let subscription = settings.liveActivitySettingsPublisher
            .dropFirst()
            .sink { receivedValues.append($0.liveActivitiesEnabled) }

        settings.liveActivitiesEnabled = false
        settings.liveActivitiesEnabled = true

        XCTAssertEqual(receivedValues, [false, true])
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testEachSourceSettingProducesOneCoherentSnapshot() {
        let settings = AppSettings(defaults: defaults)
        var snapshots: [LiveActivitySettingsSnapshot] = []
        let subscription = settings.liveActivitySettingsPublisher
            .dropFirst()
            .sink { snapshots.append($0) }

        settings.showMusicLiveActivity = false
        settings.showTimerLiveActivity = false
        settings.showFileDropLiveActivity = false
        settings.showBatteryLiveActivity = false

        XCTAssertEqual(
            snapshots.last,
            LiveActivitySettingsSnapshot(
                liveActivitiesEnabled: true,
                showMusicLiveActivity: false,
                showTimerLiveActivity: false,
                showFileDropLiveActivity: false,
                showBatteryLiveActivity: false
            )
        )

        settings.showMusicLiveActivity = true
        settings.showTimerLiveActivity = true
        settings.showFileDropLiveActivity = true
        settings.showBatteryLiveActivity = true

        XCTAssertEqual(snapshots.count, 8)
        XCTAssertEqual(
            snapshots.last,
            LiveActivitySettingsSnapshot(
                liveActivitiesEnabled: true,
                showMusicLiveActivity: true,
                showTimerLiveActivity: true,
                showFileDropLiveActivity: true,
                showBatteryLiveActivity: true
            )
        )
        withExtendedLifetime(subscription) {}
    }
}
