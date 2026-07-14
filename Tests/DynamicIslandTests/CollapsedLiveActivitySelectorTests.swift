import XCTest
@testable import DynamicIsland

final class CollapsedLiveActivitySelectorTests: XCTestCase {
    func testRunningTimerBeatsPausedMediaByDefault() {
        let mode = select([
            activity(id: "media", kind: .media, title: "Song", isActive: false),
            activity(id: "timer", kind: .timer, title: "Timer", isActive: true)
        ])

        XCTAssertEqual(mode, .timer(activity(id: "timer", kind: .timer, title: "Timer", isActive: true)))
    }

    func testRunningTimerBeatsPlayingMediaByDefault() {
        let mode = select([
            activity(id: "media", kind: .media, title: "Song", isActive: true),
            activity(id: "timer", kind: .timer, title: "Timer", isActive: true)
        ])

        XCTAssertEqual(mode, .timer(activity(id: "timer", kind: .timer, title: "Timer", isActive: true)))
    }

    func testPlayingMediaBeatsRecentFilesByDefault() {
        let mode = select([
            activity(id: "files", kind: .fileTray, title: "Files added"),
            activity(id: "media", kind: .media, title: "Song", isActive: true)
        ])

        XCTAssertEqual(mode, .media)
    }

    func testPausedTimerBeatsPausedMediaByDefault() {
        let mode = select([
            activity(id: "media", kind: .media, title: "Song", isActive: false),
            activity(id: "timer", kind: .timer, title: "Timer", isActive: false)
        ])

        XCTAssertEqual(mode, .timer(activity(id: "timer", kind: .timer, title: "Timer", isActive: false)))
    }

    func testPausedMediaWinsWhenNoTimerFilesOrPlayingMedia() {
        let mode = select([
            activity(id: "media", kind: .media, title: "Song", isActive: false)
        ])

        XCTAssertEqual(mode, .media)
    }

    func testRecentFilesWinWhenNoTimerOrMedia() {
        let mode = select([
            activity(id: "files", kind: .fileTray, title: "Files added")
        ])

        XCTAssertEqual(mode, .fileTray(activity(id: "files", kind: .fileTray, title: "Files added")))
    }

    func testDisabledTimerSourceRemovesTimerEligibility() {
        let mode = select(
            [
                activity(id: "timer", kind: .timer, title: "Timer", isActive: true),
                activity(id: "media", kind: .media, title: "Song", isActive: false)
            ],
            toggles: CollapsedLiveActivitySourceToggles(
                liveActivitiesEnabled: true,
                timerEnabled: false,
                mediaEnabled: true,
                fileTrayEnabled: true,
                batteryEnabled: true
            )
        )

        XCTAssertEqual(mode, .media)
    }

    func testCustomPriorityCanMakePlayingMediaBeatRunningTimer() {
        var priorities = CollapsedLiveActivityPrioritySettings.defaults
        priorities.playingMedia = 120

        let mode = select(
            [
                activity(id: "timer", kind: .timer, title: "Timer", isActive: true),
                activity(id: "media", kind: .media, title: "Song", isActive: true)
            ],
            priorities: priorities
        )

        XCTAssertEqual(mode, .media)
    }

    func testSelectedCollapsedActivityReturnsOnlyPrimaryWinner() {
        let mode = select([
            activity(id: "media", kind: .media, title: "Song", isActive: false),
            activity(id: "timer", kind: .timer, title: "Timer", isActive: true)
        ])

        switch mode {
        case .timer(let selected):
            XCTAssertEqual(selected.id, "timer")
        default:
            XCTFail("Expected only the timer winner in the selected collapsed mode, got \(mode)")
        }
    }

    func testCustomPriorityCanMakeRecentFilesBeatPausedMedia() {
        var priorities = CollapsedLiveActivityPrioritySettings.defaults
        priorities.recentFiles = 70
        priorities.pausedMedia = 65

        let mode = select(
            [
                activity(id: "media", kind: .media, title: "Song", isActive: false),
                activity(id: "files", kind: .fileTray, title: "Files added")
            ],
            priorities: priorities
        )

        XCTAssertEqual(mode, .fileTray(activity(id: "files", kind: .fileTray, title: "Files added")))
    }

    func testCustomPriorityCanMakePausedMediaBeatRunningTimer() {
        var priorities = CollapsedLiveActivityPrioritySettings.defaults
        priorities.pausedMedia = 150

        let mode = select(
            [
                activity(id: "timer", kind: .timer, title: "Timer", isActive: true),
                activity(id: "media", kind: .media, title: "Song", isActive: false)
            ],
            priorities: priorities
        )

        XCTAssertEqual(mode, .media)
    }

    func testSelectedTimerModeIsNotInactive() {
        let mode = select([
            activity(id: "timer", kind: .timer, title: "Timer", isActive: true)
        ])

        XCTAssertNotEqual(mode, .inactive)
    }

    func testSelectedFileModeIsNotInactive() {
        let mode = select([
            activity(id: "files", kind: .fileTray, title: "Files added")
        ])

        XCTAssertNotEqual(mode, .inactive)
    }

    func testTiesUseDefaultOrder() {
        let priorities = CollapsedLiveActivityPrioritySettings(
            runningTimer: 80,
            playingMedia: 80,
            pausedTimer: 80,
            recentFiles: 80,
            pausedMedia: 80
        )

        let mode = select(
            [
                activity(id: "files", kind: .fileTray, title: "Files added"),
                activity(id: "media", kind: .media, title: "Song", isActive: true)
            ],
            priorities: priorities
        )

        XCTAssertEqual(mode, .media)
    }

    func testPrioritiesClampDuringSelection() {
        let priorities = CollapsedLiveActivityPrioritySettings(
            runningTimer: 500,
            playingMedia: 90,
            pausedTimer: 80,
            recentFiles: 60,
            pausedMedia: -20
        )

        XCTAssertEqual(priorities.priority(for: .runningTimer), 200)
        XCTAssertEqual(priorities.priority(for: .pausedMedia), 0)
    }

    func testTimerFormattingUnderOneHourUsesMinutesAndSeconds() {
        XCTAssertEqual(LiveActivityTimeFormatting.remainingTime(572), "9:32")
        XCTAssertEqual(LiveActivityTimeFormatting.remainingTime(724), "12:04")
    }

    func testTimerFormattingOverOneHourUsesHoursMinutesAndSeconds() {
        XCTAssertEqual(LiveActivityTimeFormatting.remainingTime(3_735), "1:02:15")
    }

    func testPreviewActivitiesIncludePrimaryTimerAndSecondaryMedia() {
        let activities = [
            activity(id: "media", kind: .media, title: "Song", isActive: true),
            activity(id: "timer", kind: .timer, title: "Timer", isActive: true)
        ]

        let preview = previewActivities(activities)

        XCTAssertEqual(preview.map(\.id), ["timer", "media"])
    }

    func testPreviewActivitiesIncludeTimerAndPausedMediaWhenBothEligible() {
        let activities = [
            activity(id: "media", kind: .media, title: "Song", isActive: false),
            activity(id: "timer", kind: .timer, title: "Timer", isActive: true)
        ]

        let preview = previewActivities(activities)

        XCTAssertEqual(preview.map(\.id), ["timer", "media"])
    }

    func testNonHoveredCollapsedPreviewContentIsNotMounted() {
        let content = collapsedPreviewContent(rowIDs: ["timer", "media"])

        XCTAssertNil(CollapsedPreviewContent.mounted(content, previewActive: false))
    }

    func testHoveredCollapsedPreviewContentMountsStackedRows() throws {
        let content = collapsedPreviewContent(rowIDs: ["timer", "media"])

        let mounted = try XCTUnwrap(CollapsedPreviewContent.mounted(content, previewActive: true))

        XCTAssertEqual(mounted.rows.map(\.id), ["timer", "media"])
    }

    func testPreviewActivitiesRespectMaxRowCount() {
        let activities = [
            activity(id: "media", kind: .media, title: "Song", isActive: true),
            activity(id: "timer", kind: .timer, title: "Timer", isActive: true),
            activity(id: "files", kind: .fileTray, title: "Files added")
        ]

        let preview = previewActivities(activities, maxCount: 2)

        XCTAssertEqual(preview.count, 2)
        XCTAssertEqual(preview.map(\.id), ["timer", "media"])
    }

    func testPreviewActivitiesFollowCustomPriorityOrdering() {
        var priorities = CollapsedLiveActivityPrioritySettings.defaults
        priorities.recentFiles = 140

        let preview = previewActivities(
            [
                activity(id: "media", kind: .media, title: "Song", isActive: true),
                activity(id: "timer", kind: .timer, title: "Timer", isActive: true),
                activity(id: "files", kind: .fileTray, title: "Files added")
            ],
            priorities: priorities
        )

        XCTAssertEqual(preview.map(\.id), ["files", "timer", "media"])
    }

    func testPreviewActivitiesExcludeDisabledSources() {
        let preview = previewActivities(
            [
                activity(id: "timer", kind: .timer, title: "Timer", isActive: true),
                activity(id: "files", kind: .fileTray, title: "Files added")
            ],
            toggles: CollapsedLiveActivitySourceToggles(
                liveActivitiesEnabled: true,
                timerEnabled: false,
                mediaEnabled: true,
                fileTrayEnabled: true,
                batteryEnabled: true
            )
        )

        XCTAssertEqual(preview.map(\.id), ["files"])
    }

    func testRunningTimerBeatsLowBatteryByDefault() {
        let timer = activity(id: "timer", kind: .timer, title: "Timer", isActive: true)
        let battery = batteryActivity(state: .low, percentage: 18)

        let mode = select([battery, timer])

        XCTAssertEqual(mode, .timer(timer))
    }

    func testLowBatteryBeatsPausedMediaByDefault() {
        let battery = batteryActivity(state: .low, percentage: 18)

        let mode = select([
            activity(id: "media", kind: .media, title: "Song", isActive: false),
            battery
        ])

        XCTAssertEqual(mode, .battery(battery))
    }

    func testLowBatteryBeatsRecentFilesByDefault() {
        let battery = batteryActivity(state: .low, percentage: 18)

        let mode = select([
            activity(id: "files", kind: .fileTray, title: "Files added"),
            battery
        ])

        XCTAssertEqual(mode, .battery(battery))
    }

    func testPlayingMediaBeatsChargingBatteryByDefault() {
        let mode = select([
            activity(id: "media", kind: .media, title: "Song", isActive: true),
            batteryActivity(state: .charging, percentage: 74)
        ])

        XCTAssertEqual(mode, .media)
    }

    func testNormalBatteryDoesNotBecomeCollapsedWinner() {
        let normalBattery = activity(
            id: "battery",
            kind: .battery,
            title: "Battery",
            isActive: false,
            batteryState: nil
        )

        let mode = select([normalBattery])

        XCTAssertEqual(mode, .inactive)
    }

    func testBatteryCanAppearInPreviewActivitiesWhenEligible() {
        let preview = previewActivities([
            activity(id: "media", kind: .media, title: "Song", isActive: false),
            batteryActivity(state: .low, percentage: 18)
        ])

        XCTAssertEqual(preview.map(\.id), ["battery", "media"])
    }

    func testDisabledBatteryLiveActivityRemovesBatteryEligibility() {
        let preview = previewActivities(
            [
                batteryActivity(state: .low, percentage: 18),
                activity(id: "media", kind: .media, title: "Song", isActive: false)
            ],
            toggles: CollapsedLiveActivitySourceToggles(
                liveActivitiesEnabled: true,
                timerEnabled: true,
                mediaEnabled: true,
                fileTrayEnabled: true,
                batteryEnabled: false
            )
        )

        XCTAssertEqual(preview.map(\.id), ["media"])
    }

    func testPreviewActivitiesWithBatteryRespectMaxRowCount() {
        let preview = previewActivities(
            [
                activity(id: "media", kind: .media, title: "Song", isActive: true),
                activity(id: "timer", kind: .timer, title: "Timer", isActive: true),
                activity(id: "files", kind: .fileTray, title: "Files added"),
                batteryActivity(state: .low, percentage: 18)
            ],
            maxCount: 3
        )

        XCTAssertEqual(preview.count, 3)
        XCTAssertEqual(preview.map(\.id), ["timer", "media", "battery"])
    }

    func testTimerPausedMediaAndBatteryDoNotMountNonHoveredPreviewContent() {
        let content = collapsedPreviewContent(rowIDs: ["timer", "battery", "media"])

        XCTAssertNil(CollapsedPreviewContent.mounted(content, previewActive: false))
    }

    private func select(
        _ activities: [DynamicIslandLiveActivity],
        priorities: CollapsedLiveActivityPrioritySettings = .defaults,
        toggles: CollapsedLiveActivitySourceToggles = CollapsedLiveActivitySourceToggles(
            liveActivitiesEnabled: true,
            timerEnabled: true,
            mediaEnabled: true,
            fileTrayEnabled: true,
            batteryEnabled: true
        )
    ) -> CollapsedIslandContentMode {
        CollapsedLiveActivitySelector.select(
            activities: activities,
            priorities: priorities,
            toggles: toggles
        )
    }

    private func previewActivities(
        _ activities: [DynamicIslandLiveActivity],
        priorities: CollapsedLiveActivityPrioritySettings = .defaults,
        toggles: CollapsedLiveActivitySourceToggles = CollapsedLiveActivitySourceToggles(
            liveActivitiesEnabled: true,
            timerEnabled: true,
            mediaEnabled: true,
            fileTrayEnabled: true,
            batteryEnabled: true
        ),
        maxCount: Int = 3
    ) -> [DynamicIslandLiveActivity] {
        CollapsedLiveActivitySelector.previewActivities(
            activities: activities,
            priorities: priorities,
            toggles: toggles,
            maxCount: maxCount
        )
    }

    private func activity(
        id: String,
        kind: DynamicIslandLiveActivityKind,
        title: String,
        isActive: Bool = true,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000),
        batteryState: BatteryLiveActivityState? = nil
    ) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: id,
            kind: kind,
            title: title,
            subtitle: nil,
            symbolName: "sparkles",
            priority: 0,
            isActive: isActive,
            progress: nil,
            updatedAt: updatedAt,
            batteryState: batteryState
        )
    }

    private func batteryActivity(
        state: BatteryLiveActivityState,
        percentage: Int,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: "battery",
            kind: .battery,
            title: state == .low ? "Low Battery" : "Battery",
            subtitle: "\(percentage)%",
            symbolName: "battery.25percent",
            priority: 0,
            isActive: state != .full,
            progress: Double(percentage) / 100,
            updatedAt: updatedAt,
            batteryState: state
        )
    }

    private func collapsedPreviewContent(rowIDs: [String]) -> CollapsedPreviewContent {
        CollapsedPreviewContent(
            rows: rowIDs.map { id in
                CollapsedPreviewRowContent(
                    id: id,
                    title: id.capitalized,
                    subtitle: nil,
                    trailingText: nil,
                    symbolName: "sparkles",
                    fallbackSymbolName: "sparkles",
                    kind: id == "timer" ? .timer : (id == "battery" ? .battery : .media),
                    isPrimary: id == rowIDs.first
                )
            }
        )
    }
}
