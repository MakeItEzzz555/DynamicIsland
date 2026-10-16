import CoreGraphics
import XCTest
@testable import DynamicIsland

private final class FakeWindowSnapSystem: WindowSnapSystemProviding {
    var accessibilityGranted = true
    var windowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
    var availableScreens: [WindowSnapScreen] = [
        WindowSnapScreen(id: "main", visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 876))
    ]
    var setFrames: [CGRect] = []
    var focusedWindowError: Error?
    var setError: Error?

    func focusedWindowFrame() throws -> CGRect {
        if let focusedWindowError { throw focusedWindowError }
        return windowFrame
    }

    func screens() -> [WindowSnapScreen] {
        availableScreens
    }

    func setFocusedWindowFrame(_ frame: CGRect) throws {
        if let setError { throw setError }
        setFrames.append(frame)
        windowFrame = frame
    }
}

@MainActor
final class WindowSnapControllerTests: XCTestCase {
    func testMoveToNextDisplayPreservesSizeAndOffsetAndWrapsAround() throws {
        let system = FakeWindowSnapSystem()
        system.availableScreens = [
            .init(id: "left", visibleFrame: CGRect(x: -1440, y: 30, width: 1440, height: 870)),
            .init(id: "main", visibleFrame: CGRect(x: 0, y: 24, width: 1920, height: 1056))
        ]
        system.windowFrame = CGRect(x: -1340, y: 130, width: 800, height: 600)
        let fixture = makeFixture(system: system)
        try fixture.controller.moveToNextDisplay()
        XCTAssertEqual(system.windowFrame, CGRect(x: 100, y: 124, width: 800, height: 600))
        try fixture.controller.moveToNextDisplay()
        XCTAssertEqual(system.windowFrame, CGRect(x: -1340, y: 130, width: 800, height: 600))
        XCTAssertNil(fixture.controller.lastError)
    }

    func testMoveToSmallerDisplayFitsWindowAndClearsPreviousSnapPreview() throws {
        let system = FakeWindowSnapSystem()
        system.availableScreens = [
            .init(id: "main", visibleFrame: CGRect(x: 0, y: 24, width: 1920, height: 1056)),
            .init(id: "small", visibleFrame: CGRect(x: 1920, y: 80, width: 1024, height: 700))
        ]
        let fixture = makeFixture(system: system)
        try fixture.controller.snap(to: .bottomRight)
        XCTAssertNotNil(fixture.activities.activities.first { $0.id == WindowSnapController.previewActivityID })
        system.windowFrame = CGRect(x: 200, y: 100, width: 1500, height: 900)
        try fixture.controller.moveToNextDisplay()
        XCTAssertEqual(system.windowFrame, CGRect(x: 1920, y: 80, width: 1024, height: 700))
        XCTAssertNil(fixture.controller.lastTarget)
        XCTAssertFalse(fixture.activities.activities.contains { $0.id == WindowSnapController.previewActivityID })
    }

    func testMoveToNextDisplayRejectsSingleDisplayAndMissingPermissionWithoutMoving() {
        let system = FakeWindowSnapSystem()
        let fixture = makeFixture(system: system)
        XCTAssertThrowsError(try fixture.controller.moveToNextDisplay()) {
            XCTAssertEqual($0 as? WindowSnapControllerError, .noOtherDisplay)
        }
        XCTAssertNotNil(fixture.controller.lastError)
        system.accessibilityGranted = false
        XCTAssertThrowsError(try fixture.controller.moveToNextDisplay()) {
            XCTAssertEqual($0 as? WindowSnapControllerError, .accessibilityPermissionRequired)
        }
        XCTAssertTrue(system.setFrames.isEmpty)
        fixture.controller.setEnabled(false)
        XCTAssertNoThrow(try fixture.controller.moveToNextDisplay())
        XCTAssertTrue(system.setFrames.isEmpty)
    }

    func testMoveToNextDisplayClampsANormalWindowAtTheDestinationEdges() throws {
        let system = FakeWindowSnapSystem()
        system.availableScreens = [
            .init(id: "main", visibleFrame: CGRect(x: 0, y: 24, width: 1920, height: 1056)),
            .init(id: "small", visibleFrame: CGRect(x: 1920, y: 80, width: 1024, height: 700))
        ]
        system.windowFrame = CGRect(x: 1100, y: 500, width: 800, height: 600)
        try makeFixture(system: system).controller.moveToNextDisplay()
        XCTAssertEqual(system.windowFrame, CGRect(x: 2144, y: 180, width: 800, height: 600))
    }

    func testAllSnapTargetsProduceExpectedFrames() {
        let frame = CGRect(x: 30, y: 20, width: 1200, height: 900)
        let expected: [WindowSnapTarget: CGRect] = [
            .leftHalf: CGRect(x: 30, y: 20, width: 600, height: 900),
            .rightHalf: CGRect(x: 630, y: 20, width: 600, height: 900),
            .topHalf: CGRect(x: 30, y: 20, width: 1200, height: 450),
            .bottomHalf: CGRect(x: 30, y: 470, width: 1200, height: 450),
            .topLeft: CGRect(x: 30, y: 20, width: 600, height: 450),
            .topRight: CGRect(x: 630, y: 20, width: 600, height: 450),
            .bottomLeft: CGRect(x: 30, y: 470, width: 600, height: 450),
            .bottomRight: CGRect(x: 630, y: 470, width: 600, height: 450),
            .leftThird: CGRect(x: 30, y: 20, width: 400, height: 900),
            .centerThird: CGRect(x: 430, y: 20, width: 400, height: 900),
            .rightThird: CGRect(x: 830, y: 20, width: 400, height: 900)
        ]

        for target in WindowSnapTarget.allCases {
            XCTAssertEqual(WindowSnapGeometry.frame(for: target, in: frame), expected[target])
        }
    }

    func testTargetDisplayUsesLargestWindowIntersection() {
        let screens = [
            WindowSnapScreen(id: "left", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            WindowSnapScreen(id: "right", visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        ]
        let window = CGRect(x: 900, y: 100, width: 700, height: 500)

        XCTAssertEqual(
            WindowSnapScreenResolver.targetScreen(for: window, screens: screens)?.id,
            "right"
        )
    }

    func testSnapUsesTargetDisplaysVisibleFrameNotMainDisplay() throws {
        let system = FakeWindowSnapSystem()
        system.windowFrame = CGRect(x: 1600, y: 100, width: 500, height: 500)
        system.availableScreens = [
            WindowSnapScreen(id: "main", visibleFrame: CGRect(x: 0, y: 20, width: 1440, height: 880)),
            WindowSnapScreen(id: "external", visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        ]
        let fixture = makeFixture(system: system)

        try fixture.controller.snap(to: .rightHalf)

        XCTAssertEqual(
            system.setFrames.last,
            CGRect(x: 2400, y: 0, width: 960, height: 1080)
        )
        XCTAssertEqual(fixture.registry.snapshot(for: .windowSnap)?.permission, .granted)
    }

    func testPermissionDeniedFailsClosedWithoutMovingWindow() {
        let system = FakeWindowSnapSystem()
        system.accessibilityGranted = false
        let fixture = makeFixture(system: system)

        XCTAssertThrowsError(try fixture.controller.snap(to: .leftHalf))
        XCTAssertTrue(system.setFrames.isEmpty)
        XCTAssertEqual(fixture.registry.snapshot(for: .windowSnap)?.permission, .required)
        guard case .failed = fixture.registry.snapshot(for: .windowSnap)?.health else {
            return XCTFail("Expected failed health after rejected snap")
        }
    }

    func testNoFocusedWindowDoesNotPublishSuccessfulPreview() {
        let system = FakeWindowSnapSystem()
        system.focusedWindowError = WindowSnapControllerError.noFocusedWindow
        let fixture = makeFixture(system: system)

        XCTAssertThrowsError(try fixture.controller.snap(to: .leftHalf))
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testSuccessfulSnapPublishesTransientPreviewMetadata() throws {
        let system = FakeWindowSnapSystem()
        let fixture = makeFixture(system: system)

        try fixture.controller.snap(to: .topLeft)

        let preview = fixture.activities.activities.first
        XCTAssertEqual(preview?.kind, .windowSnapPreview)
        XCTAssertEqual(preview?.subtitle, "Top Left")
        XCTAssertEqual(preview?.lifecycle.authority, .accessibilityAPI)
        XCTAssertEqual(
            LiveActivityPresentationPolicy.descriptor(for: try XCTUnwrap(preview)).preemptionPolicy,
            .transientOverlay
        )
    }

    func testDisabledControllerDoesNotMoveWindow() throws {
        let system = FakeWindowSnapSystem()
        let fixture = makeFixture(system: system)
        fixture.controller.setEnabled(false)

        try fixture.controller.snap(to: .leftHalf)

        XCTAssertTrue(system.setFrames.isEmpty)
        XCTAssertEqual(fixture.registry.snapshot(for: .windowSnap)?.isEnabled, false)
    }

    /// The capability registry must never advertise an action the adapter rejects.
    func testAdvertisedActionsAreAllPerformable() async {
        let fixture = makeFixture(system: FakeWindowSnapSystem())
        let advertised = fixture.registry.snapshot(for: .windowSnap)?.supportedActions ?? []
        for action in IslandCapabilityAction.allCases where action != .openSettings {
            do {
                try await fixture.controller.perform(action)
            } catch WindowSnapControllerError.unsupportedAction {
                XCTAssertFalse(advertised.contains(action), "\(action) is advertised but unsupported")
            } catch {}
        }
    }

    private func makeFixture(
        system: FakeWindowSnapSystem
    ) -> (
        controller: WindowSnapController,
        activities: LiveActivityStore,
        registry: IslandCapabilityRegistry
    ) {
        let activities = LiveActivityStore()
        let registry = IslandCapabilityRegistry()
        let controller = WindowSnapController(
            liveActivities: activities,
            capabilities: registry,
            system: system,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        return (controller, activities, registry)
    }
}
