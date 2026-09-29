@testable import DynamicIsland
import CoreGraphics
import XCTest

final class LiveActivityLayoutResolverTests: XCTestCase {
    func testMediaAloneResolvesPrimary() {
        let media = activity("media", .media, priority: 80)
        let result = resolve([media])

        XCTAssertEqual(result.primary?.activity.id, "media")
        XCTAssertNil(result.leadingSidecar)
        XCTAssertNil(result.trailingSidecar)
    }

    func testTimerAloneResolvesPrimary() {
        let timer = activity("timer", .timer, priority: 90, progress: 0.5)
        let result = resolve([timer])

        XCTAssertEqual(result.primary?.activity.id, "timer")
    }

    func testMediaAndTimerResolveMediaPrimaryAndTimerSidecar() {
        let result = resolve([
            activity("timer", .timer, priority: 90, progress: 0.4),
            activity("media", .media, priority: 80)
        ])

        XCTAssertEqual(result.primary?.activity.id, "media")
        XCTAssertEqual(result.trailingSidecar?.activity.id, "timer")
    }

    func testMediaBatteryTimerUseDeterministicSides() {
        let result = resolve([
            activity("battery", .battery, priority: 85, progress: 0.18, batteryState: .low),
            activity("media", .media, priority: 80),
            activity("timer", .timer, priority: 90, progress: 0.6)
        ])

        XCTAssertEqual(result.primary?.activity.id, "media")
        XCTAssertEqual(result.leadingSidecar?.activity.id, "battery")
        XCTAssertEqual(result.trailingSidecar?.activity.id, "timer")
    }

    func testActiveAgentBeatsMediaAsPrimary() {
        let result = resolve([
            activity("media", .media, priority: 80),
            activity("agent", .agent, priority: 130)
        ])

        XCTAssertEqual(result.primary?.activity.id, "agent")
    }

    func testTimerLeadingPreferenceIsHonored() {
        let result = resolve(
            [
                activity("media", .media, priority: 80),
                activity("timer", .timer, priority: 90, progress: 0.5)
            ],
            timerSidePreference: .leading
        )

        XCTAssertEqual(result.leadingSidecar?.activity.id, "timer")
    }

    func testPreferredSideFallsBackWhenOccupied() {
        let result = resolve(
            [
                activity("media", .media, priority: 80),
                activity("timer", .timer, priority: 90, progress: 0.5),
                activity("battery", .battery, priority: 85, progress: 0.18, batteryState: .low)
            ],
            timerSidePreference: .leading
        )

        XCTAssertEqual(result.leadingSidecar?.activity.id, "timer")
        XCTAssertEqual(result.trailingSidecar?.activity.id, "battery")
    }

    func testWideGeometryPermitsBothSidecars() {
        let result = resolve(fullSet, availableWidth: 320)
        XCTAssertNotNil(result.leadingSidecar)
        XCTAssertNotNil(result.trailingSidecar)
    }

    func testMediumGeometryDropsLowerPrioritySidecar() {
        let result = resolve(fullSet, availableWidth: 230)
        XCTAssertEqual(result.trailingSidecar?.activity.id, "timer")
        XCTAssertNil(result.leadingSidecar)
    }

    func testNarrowGeometryDropsBothSidecars() {
        let result = resolve(fullSet, availableWidth: 200)
        XCTAssertNil(result.leadingSidecar)
        XCTAssertNil(result.trailingSidecar)
        XCTAssertEqual(result.primary?.activity.id, "media")
    }

    func testDisablingSimultaneousSidecarsCapsAtOne() {
        let result = resolve(
            fullSet,
            availableWidth: 320,
            allowSimultaneousSidecars: false
        )

        XCTAssertEqual(
            [result.leadingSidecar, result.trailingSidecar].compactMap { $0 }.count,
            1
        )
    }

    func testResolverIsIndependentOfInputOrder() {
        let first = resolve(fullSet)
        let second = resolve(Array(fullSet.reversed()))
        XCTAssertEqual(first, second)
    }

    func testEqualPriorityTieBreakIsDeterministicByID() {
        let a = activity("a", .fileTray, priority: 60)
        let b = activity("b", .fileTray, priority: 60)
        let media = activity("media", .media, priority: 80)

        let result = resolve([b, media, a])
        XCTAssertEqual(result.leadingSidecar?.activity.id, "a")
    }

    func testSystemHUDIsOverlayAndDoesNotMutatePersistentSlots() {
        let persistent = resolve(fullSet)
        let withHUD = resolve(
            fullSet + [activity("hud", .system, priority: 200, progress: 0.68)]
        )

        XCTAssertEqual(withHUD.persistentActivityIDs, persistent.persistentActivityIDs)
        XCTAssertEqual(withHUD.overlayTransient?.activity.id, "hud")
    }

    func testRemovingTransientRestoresIdenticalPersistentResolution() {
        let withHUD = resolve(
            fullSet + [activity("hud", .system, priority: 200, progress: 0.68)]
        )
        let withoutHUD = resolve(fullSet)

        XCTAssertEqual(withHUD.leadingSidecar, withoutHUD.leadingSidecar)
        XCTAssertEqual(withHUD.primary, withoutHUD.primary)
        XCTAssertEqual(withHUD.trailingSidecar, withoutHUD.trailingSidecar)
    }

    func testCompositeGeometryPlacesSidecarsOutsidePrimaryWithoutOverlap() throws {
        let resolution = resolve(fullSet)
        let primary = CGRect(x: 100, y: 30, width: 220, height: 34)
        let geometry = LiveActivityCompositeGeometry.resolve(
            primaryFrame: primary,
            canvasSize: CGSize(width: 500, height: 100),
            resolution: resolution
        )

        let leading = try XCTUnwrap(geometry.leadingSidecarFrame)
        let trailing = try XCTUnwrap(geometry.trailingSidecarFrame)

        XCTAssertLessThan(leading.maxX, primary.minX)
        XCTAssertGreaterThan(trailing.minX, primary.maxX)
        XCTAssertTrue(geometry.interactionFrame.contains(primary))
        XCTAssertTrue(geometry.interactionFrame.contains(leading))
        XCTAssertTrue(geometry.interactionFrame.contains(trailing))
    }

    func testCompositeGeometryDropsOutOfCanvasSidecarFrameSafely() {
        let resolution = resolve(fullSet)
        let geometry = LiveActivityCompositeGeometry.resolve(
            primaryFrame: CGRect(x: 0, y: 10, width: 220, height: 34),
            canvasSize: CGSize(width: 260, height: 70),
            resolution: resolution
        )

        XCTAssertNil(geometry.leadingSidecarFrame)
        XCTAssertNotNil(geometry.trailingSidecarFrame)
    }

    func testNotchlessContextResolvesSameSemanticSlots() {
        let result = resolve(fullSet, hasHardwareNotch: false)
        XCTAssertEqual(result.primary?.activity.id, "media")
        XCTAssertEqual(result.trailingSidecar?.activity.id, "timer")
        XCTAssertEqual(result.leadingSidecar?.activity.id, "battery")
    }

    func testKeepAwakeCanCoexistAsSidecarWithMediaPrimary() {
        let result = resolve([
            activity("media", .media, priority: 80),
            activity("awake", .keepAwake, priority: 72)
        ])

        XCTAssertEqual(result.primary?.activity.id, "media")
        XCTAssertEqual(result.trailingSidecar?.activity.id, "awake")
    }

    func testVoiceRecordingPrefersPrimaryOverMedia() {
        let result = resolve([
            activity("media", .media, priority: 80),
            activity("voice", .voiceRecording, priority: 125)
        ])

        XCTAssertEqual(result.primary?.activity.id, "voice")
        XCTAssertEqual(result.primary?.descriptor.preemptionPolicy, .persistent)
    }

    func testWindowSnapPreviewIsTransientOverlayAndPreservesPersistentSlots() {
        let persistent = resolve(fullSet)
        let withPreview = resolve(
            fullSet + [activity("snap", .windowSnapPreview, priority: 170)]
        )

        XCTAssertEqual(withPreview.persistentActivityIDs, persistent.persistentActivityIDs)
        XCTAssertEqual(withPreview.overlayTransient?.activity.id, "snap")
        XCTAssertEqual(withPreview.overlayTransient?.descriptor.preemptionPolicy, .transientOverlay)
    }

    func testProductivityKindsExposeDeterministicPresentationMetadata() {
        let expectations: [(DynamicIslandLiveActivityKind, LiveActivityPlacement, LiveActivityPreemptionPolicy)] = [
            (.keepAwake, .trailingSidecar, .persistent),
            (.terminalTask, .trailingSidecar, .persistent),
            (.windowSnapPreview, .overlayTransient, .transientOverlay),
            (.reminder, .leadingSidecar, .persistent),
            (.voiceRecording, .primary, .persistent),
            (.voiceTranscription, .primary, .persistent),
            (.camera, .primary, .persistent),
            (.backgroundRemoval, .leadingSidecar, .persistent)
        ]

        for (kind, placement, preemption) in expectations {
            let item = activity(kind.rawValue, kind, priority: 1)
            let descriptor = LiveActivityPresentationPolicy.descriptor(for: item)
            XCTAssertEqual(descriptor.preferredPlacement, placement, "kind=\(kind.rawValue)")
            XCTAssertEqual(descriptor.preemptionPolicy, preemption, "kind=\(kind.rawValue)")
        }
    }

    private var fullSet: [DynamicIslandLiveActivity] {
        [
            activity("media", .media, priority: 80),
            activity("timer", .timer, priority: 90, progress: 0.6),
            activity("battery", .battery, priority: 85, progress: 0.18, batteryState: .low)
        ]
    }

    private func resolve(
        _ activities: [DynamicIslandLiveActivity],
        availableWidth: CGFloat = 320,
        hasHardwareNotch: Bool = true,
        allowSimultaneousSidecars: Bool = true,
        timerSidePreference: LiveActivitySidePreference = .automatic
    ) -> LiveActivityLayoutResolution {
        LiveActivityLayoutResolver.resolve(
            activities: activities,
            context: LiveActivityLayoutContext(
                availableWidth: availableWidth,
                hasHardwareNotch: hasHardwareNotch,
                hardwareNotchWidth: hasHardwareNotch ? 180 : 0,
                primaryMinimumWidth: 172,
                primaryIdealWidth: 226,
                sidecarDiameter: 30,
                sidecarGap: 7,
                allowSimultaneousSidecars: allowSimultaneousSidecars,
                timerSidePreference: timerSidePreference
            )
        )
    }

    private func activity(
        _ id: String,
        _ kind: DynamicIslandLiveActivityKind,
        priority: Int,
        isActive: Bool = true,
        progress: Double? = nil,
        batteryState: BatteryLiveActivityState? = nil
    ) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: id,
            kind: kind,
            title: id.capitalized,
            subtitle: nil,
            symbolName: "circle.fill",
            priority: priority,
            isActive: isActive,
            progress: progress,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            batteryState: batteryState
        )
    }
}
