import XCTest
@testable import DynamicIsland

@MainActor
final class IslandGestureCoordinatorTests: XCTestCase {
    func testDisabledGesturesDoNothing() {
        let settings = makeSettings()
        settings.gesturesEnabled = false
        settings.gestureInputSource = .trackpad
        settings.expandGestureEnabled = true

        var expandCount = 0
        let coordinator = IslandGestureCoordinator()

        let handled = coordinator.handle(
            .doubleClick,
            settings: settings,
            context: makeContext(state: .collapsed),
            callbacks: IslandGestureCallbacks(expand: { expandCount += 1 })
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(expandCount, 0)
    }

    func testCooldownBlocksRepeatedAction() {
        let settings = makeSettings()
        settings.gesturesEnabled = true
        settings.gestureInputSource = .trackpad
        settings.expandGestureEnabled = true
        settings.collapsedDoubleClickAction = .expand
        settings.gestureCooldownSeconds = 0.75

        var currentTime: TimeInterval = 100
        var expandCount = 0
        let coordinator = IslandGestureCoordinator(now: { currentTime })
        let callbacks = IslandGestureCallbacks(expand: { expandCount += 1 })

        XCTAssertTrue(
            coordinator.handle(
                .doubleClick,
                settings: settings,
                context: makeContext(state: .collapsed),
                callbacks: callbacks
            )
        )

        currentTime += 0.3
        XCTAssertFalse(
            coordinator.handle(
                .doubleClick,
                settings: settings,
                context: makeContext(state: .collapsed),
                callbacks: callbacks
            )
        )
        XCTAssertEqual(expandCount, 1)

        currentTime += 0.5
        XCTAssertTrue(
            coordinator.handle(
                .doubleClick,
                settings: settings,
                context: makeContext(state: .collapsed),
                callbacks: callbacks
            )
        )
        XCTAssertEqual(expandCount, 2)
    }

    func testLowSensitivityRequiresBiggerSwipe() {
        XCTAssertNil(
            IslandPointerGesture.detected(
                from: CGSize(width: 40, height: 4),
                sensitivity: 0.4
            )
        )
        XCTAssertEqual(
            IslandPointerGesture.detected(
                from: CGSize(width: 92, height: 4),
                sensitivity: 0.4
            ),
            .swipeRight
        )
    }

    func testConfiguredCollapsedGestureReturnsConfiguredAction() {
        let settings = makeSettings()
        settings.collapsedSwipeDownAction = .expand
        settings.collapsedDoubleClickAction = .mediaPlayPause
        let coordinator = IslandGestureCoordinator()

        XCTAssertEqual(
            coordinator.action(
                for: .swipeDown,
                settings: settings,
                context: makeContext(state: .collapsed)
            ),
            .expand
        )
        XCTAssertEqual(
            coordinator.action(
                for: .doubleClick,
                settings: settings,
                context: makeContext(state: .collapsed)
            ),
            .mediaPlayPause
        )
    }

    func testDefaultCollapsedMediaPillSwipeMappingsUseTracks() {
        let settings = makeSettings()
        let coordinator = IslandGestureCoordinator()

        XCTAssertEqual(
            coordinator.action(
                for: .swipeLeft,
                settings: settings,
                context: makeContext(state: .collapsed)
            ),
            .mediaNextTrack
        )
        XCTAssertEqual(
            coordinator.action(
                for: .swipeRight,
                settings: settings,
                context: makeContext(state: .collapsed)
            ),
            .mediaPreviousTrack
        )
        XCTAssertEqual(
            coordinator.action(
                for: .swipeDown,
                settings: settings,
                context: makeContext(state: .collapsed)
            ),
            .expand
        )
    }

    func testMediaNextAndPreviousGesturesUseMediaCallbacksWhenAvailable() {
        let settings = makeSettings()
        settings.gesturesEnabled = true
        settings.gestureInputSource = .trackpad

        var nextCount = 0
        var previousCount = 0
        let coordinator = IslandGestureCoordinator()

        XCTAssertTrue(
            coordinator.handle(
                .swipeLeft,
                settings: settings,
                context: makeContext(state: .collapsed, mediaControlAvailable: true),
                callbacks: IslandGestureCallbacks(
                    mediaNextTrack: { nextCount += 1 },
                    mediaPreviousTrack: { previousCount += 1 }
                )
            )
        )

        XCTAssertEqual(nextCount, 1)
        XCTAssertEqual(previousCount, 0)
    }

    func testMediaTrackGesturesNoOpWhenMediaUnavailable() {
        let settings = makeSettings()
        settings.gesturesEnabled = true
        settings.gestureInputSource = .trackpad

        var nextCount = 0
        let coordinator = IslandGestureCoordinator()

        XCTAssertFalse(
            coordinator.handle(
                .swipeLeft,
                settings: settings,
                context: makeContext(state: .collapsed, mediaControlAvailable: false),
                callbacks: IslandGestureCallbacks(mediaNextTrack: { nextCount += 1 })
            )
        )
        XCTAssertEqual(nextCount, 0)
    }

    func testConfiguredExpandedGestureReturnsConfiguredAction() {
        let settings = makeSettings()
        settings.expandedSwipeLeftAction = .nextTab
        settings.expandedSwipeRightAction = .previousTab
        let coordinator = IslandGestureCoordinator()

        XCTAssertEqual(
            coordinator.action(
                for: .swipeLeft,
                settings: settings,
                context: makeContext(state: .expanded)
            ),
            .nextTab
        )
        XCTAssertEqual(
            coordinator.action(
                for: .swipeRight,
                settings: settings,
                context: makeContext(state: .expanded)
            ),
            .previousTab
        )
    }

    func testCollapsedDoubleClickFallsBackToToggleWhenMediaUnavailable() {
        let settings = makeSettings()
        settings.gesturesEnabled = true
        settings.gestureInputSource = .trackpad
        settings.expandGestureEnabled = true
        settings.collapsedDoubleClickAction = .mediaPlayPause

        var expandCount = 0
        let coordinator = IslandGestureCoordinator()

        let handled = coordinator.handle(
            .doubleClick,
            settings: settings,
            context: makeContext(state: .collapsed, mediaControlAvailable: false),
            callbacks: IslandGestureCallbacks(expand: { expandCount += 1 })
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(expandCount, 1)
    }

    func testInvalidStoredGestureActionFallsBackSafely() {
        let suiteName = "IslandGestureCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("not-a-valid-action", forKey: "collapsedSwipeDownAction")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.collapsedSwipeDownAction, .expand)
    }

    func testNextAndPreviousTabSkipDisabledTabs() {
        let settings = makeSettings()
        settings.showTrayTab = false
        settings.showTimerTab = true
        settings.showStatsTab = true
        settings.showAgentsTab = false

        let navigation = IslandNavigationStore()
        XCTAssertEqual(navigation.selectedPage, .island)

        navigation.selectNextPage(using: settings)
        XCTAssertEqual(navigation.selectedPage, .timer)

        navigation.selectNextPage(using: settings)
        XCTAssertEqual(navigation.selectedPage, .stats)

        navigation.selectPreviousPage(using: settings)
        XCTAssertEqual(navigation.selectedPage, .timer)
    }

    func testRapidDirectNavigationConvergesOnNewestSelection() {
        let navigation = IslandNavigationStore()

        navigation.select(.agents)
        navigation.select(.stats)
        navigation.select(.agents)
        navigation.select(.island)

        XCTAssertEqual(navigation.selectedPage, .island)
        XCTAssertEqual(
            ExpandedPresentationProfile.resolve(for: navigation.selectedPage),
            .standard
        )
    }

    private func makeSettings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "IslandGestureCoordinatorTests-\(UUID().uuidString)")!
        return AppSettings(defaults: defaults)
    }

    private func makeContext(
        state: IslandPresentationState,
        mediaControlAvailable: Bool = true
    ) -> IslandGestureContext {
        IslandGestureContext(
            presentationState: state,
            selectedPage: .island,
            mediaControlAvailable: mediaControlAvailable,
            timerIsRunning: false,
            timerCanResume: true,
            collapsedPreviewActive: false,
            isShellMorphing: false,
            isCollapseShellOnly: false,
            isExpandedContentExiting: false,
            isFileDropTargeted: false
        )
    }
}
