import CoreGraphics
import Foundation
import XCTest
@testable import DynamicIsland

/// Phase 13F regression coverage: productivity activities built by the
/// production controllers, resolved by the real layout resolver.
@MainActor
final class ProductivityIntegrationTests: XCTestCase {
    // MARK: Resolver scenarios (shared with the Settings preview)

    func testEveryPreviewScenarioResolvesDeterministicallyRegardlessOfOrder() {
        for scenario in LiveActivityLayoutPreviewScenario.allCases {
            let activities = LiveActivityPreviewCatalog.activities(for: scenario)
            let forward = resolve(activities)
            let reversed = resolve(activities.reversed())
            XCTAssertEqual(forward, reversed, "scenario=\(scenario.rawValue)")
            XCTAssertNotNil(forward.primary, "scenario=\(scenario.rawValue)")
        }
    }

    func testMediaPlusKeepAwake() {
        let result = resolve(LiveActivityPreviewCatalog.activities(for: .mediaKeepAwake))
        XCTAssertEqual(result.primary?.activity.kind, .media)
        XCTAssertEqual(sidecarKinds(result), [.keepAwake])
    }

    func testMediaTimerKeepAwakeKeepsMediaPrimaryAndBothSidecars() {
        let result = resolve(LiveActivityPreviewCatalog.activities(for: .mediaTimerKeepAwake))
        XCTAssertEqual(result.primary?.activity.kind, .media)
        XCTAssertEqual(sidecarKinds(result), [.keepAwake, .timer])
    }

    func testMediaTimerKeepAwakeDropsLowerPrioritySidecarWhenOnlyOneAllowed() {
        let result = resolve(
            LiveActivityPreviewCatalog.activities(for: .mediaTimerKeepAwake),
            allowSimultaneousSidecars: false
        )
        XCTAssertEqual(result.primary?.activity.kind, .media)
        XCTAssertEqual(sidecarKinds(result), [.timer])
    }

    func testAgentPlusTerminalTaskKeepsAgentPrimaryAndSeparate() {
        let result = resolve(LiveActivityPreviewCatalog.activities(for: .agentTerminal))
        XCTAssertEqual(result.primary?.activity.kind, .agent)
        XCTAssertEqual(sidecarKinds(result), [.terminalTask])
    }

    func testTimerPlusReminder() {
        let result = resolve(LiveActivityPreviewCatalog.activities(for: .timerReminder))
        XCTAssertEqual(Set(result.persistentActivityIDs), [
            LiveActivityPreviewCatalog.timer.id,
            RemindersController.activityID
        ])
        XCTAssertEqual(result.primary?.activity.kind, .timer)
        XCTAssertEqual(result.leadingSidecar?.activity.kind, .reminder)
    }

    func testVoiceRecordingPlusTimerMakesRecordingPrimary() {
        let result = resolve(LiveActivityPreviewCatalog.activities(for: .voiceTimer))
        XCTAssertEqual(result.primary?.activity.kind, .voiceRecording)
        XCTAssertEqual(sidecarKinds(result), [.timer])
    }

    func testCameraActiveIsPrimary() {
        let result = resolve(LiveActivityPreviewCatalog.activities(for: .camera) + [LiveActivityPreviewCatalog.media])
        XCTAssertEqual(result.primary?.activity.kind, .camera)
    }

    func testBackgroundRemovalProcessingIsShown() {
        let result = resolve(LiveActivityPreviewCatalog.activities(for: .backgroundRemoval))
        XCTAssertEqual(result.persistentActivityIDs, [BackgroundRemovalController.activityID])
    }

    func testTransientVolumeHUDAboveProductivityRestoresSameComposition() {
        let persistentOnly = [LiveActivityPreviewCatalog.media, LiveActivityPreviewCatalog.keepAwake]
        let withHUD = resolve(persistentOnly + [LiveActivityPreviewCatalog.volume])
        let withoutHUD = resolve(persistentOnly)

        XCTAssertEqual(withHUD.overlayTransient?.activity.kind, .system)
        XCTAssertEqual(withHUD.primary, withoutHUD.primary)
        XCTAssertEqual(withHUD.leadingSidecar, withoutHUD.leadingSidecar)
        XCTAssertEqual(withHUD.trailingSidecar, withoutHUD.trailingSidecar)

        let keepAwakeHUD = resolve(LiveActivityPreviewCatalog.activities(for: .keepAwakeVolume))
        XCTAssertEqual(keepAwakeHUD.overlayTransient?.activity.kind, .system)
        XCTAssertEqual(keepAwakeHUD.persistentActivityIDs, [KeepAwakeController.activityID])
    }

    func testNotchlessContextKeepsSameSemanticSlotsForProductivity() {
        let activities = LiveActivityPreviewCatalog.activities(for: .mediaTimerKeepAwake)
        let notched = resolve(activities, hasHardwareNotch: true)
        let notchless = resolve(activities, hasHardwareNotch: false)
        XCTAssertEqual(notched.primary?.activity.id, notchless.primary?.activity.id)
        XCTAssertEqual(sidecarKinds(notched), sidecarKinds(notchless))
    }

    // MARK: Production metadata

    func testProductionBuildersCarryTruthfulAuthorityAndNoSynthesizedProgress() {
        let expectations: [(DynamicIslandLiveActivity, LiveActivitySourceAuthority)] = [
            (LiveActivityPreviewCatalog.terminal, .process),
            (LiveActivityPreviewCatalog.reminder, .eventKit),
            (LiveActivityPreviewCatalog.voiceRecording, .avFoundation),
            (VoiceTranscriptionController.makeTranscriptionActivity(onDevice: true, updatedAt: .distantPast), .systemAPI),
            (LiveActivityPreviewCatalog.camera, .avFoundation),
            (LiveActivityPreviewCatalog.backgroundRemoval, .vision)
        ]
        for (activity, authority) in expectations {
            XCTAssertEqual(activity.lifecycle.authority, authority, "kind=\(activity.kind.rawValue)")
            XCTAssertNil(activity.progress, "kind=\(activity.kind.rawValue)")
        }

        let indefiniteKeepAwake = KeepAwakeController.makeActivity(
            subtitle: "On",
            progress: nil,
            hasDuration: false,
            updatedAt: .distantPast
        )
        XCTAssertNil(indefiniteKeepAwake.lifecycle.progressEvidence)
        XCTAssertEqual(indefiniteKeepAwake.lifecycle.authority, .systemAPI)
    }

    func testEveryProductivityControllerPublishesIntoTheSharedRegistry() {
        let registry = IslandCapabilityRegistry()
        let activities = LiveActivityStore()
        _ = RemindersController(liveActivities: activities, capabilities: registry, provider: NullRemindersProvider())
        _ = BackgroundRemovalController(liveActivities: activities, capabilities: registry, addToShelf: { _ in })

        XCTAssertNotNil(registry.snapshot(for: .reminders))
        XCTAssertNotNil(registry.snapshot(for: .backgroundRemoval))
        XCTAssertTrue(activities.activities.isEmpty, "Construction must not fabricate activities")
    }

    // MARK: Navigation

    func testToolsPageIsAnExpandedPageNotAShellState() {
        let settings = makeSettings()
        let navigation = IslandNavigationStore()

        XCTAssertTrue(settings.showToolsTab)
        XCTAssertTrue(navigation.availablePages(using: settings).contains(.tools))
        XCTAssertEqual(ExpandedPresentationProfile.resolve(for: .tools), .standard)

        settings.showToolsTab = false
        XCTAssertFalse(navigation.availablePages(using: settings).contains(.tools))

        navigation.select(.tools)
        navigation.ensureValidSelection(using: settings)
        XCTAssertNotEqual(navigation.selectedPage, .tools)
    }

    func testToolsTabSettingPersists() {
        let suite = "ProductivityIntegrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        AppSettings(defaults: defaults).showToolsTab = false
        XCTAssertFalse(AppSettings(defaults: defaults).showToolsTab)
    }

    // MARK: Helpers

    private func sidecarKinds(_ result: LiveActivityLayoutResolution) -> [DynamicIslandLiveActivityKind] {
        [result.leadingSidecar?.activity.kind, result.trailingSidecar?.activity.kind]
            .compactMap { $0 }
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func resolve(
        _ activities: [DynamicIslandLiveActivity],
        hasHardwareNotch: Bool = true,
        allowSimultaneousSidecars: Bool = true
    ) -> LiveActivityLayoutResolution {
        LiveActivityLayoutResolver.resolve(
            activities: activities,
            context: LiveActivityLayoutContext(
                availableWidth: 320,
                hasHardwareNotch: hasHardwareNotch,
                hardwareNotchWidth: hasHardwareNotch ? 180 : 0,
                primaryMinimumWidth: 172,
                primaryIdealWidth: 226,
                sidecarDiameter: 30,
                sidecarGap: 7,
                allowSimultaneousSidecars: allowSimultaneousSidecars,
                timerSidePreference: .automatic
            )
        )
    }

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "ProductivityIntegrationTests-\(UUID().uuidString)")!)
    }
}

@MainActor
private final class NullRemindersProvider: RemindersProviding {
    var accessState: ReminderAccessState { .notDetermined }
    var changeNotificationName: Notification.Name? { nil }
    func requestFullAccess() async throws -> ReminderAccessState { .notDetermined }
    func fetchLists() throws -> [ReminderListDescriptor] { [] }
    func createReminder(title: String, listID: String, dueDate: Date?) throws -> ReminderDescriptor {
        throw RemindersControllerError.permissionRequired
    }
    func completeReminder(id: String) throws {}
    func fetchUpcomingReminders(from start: Date, through end: Date) async throws -> [ReminderDescriptor] { [] }
}
