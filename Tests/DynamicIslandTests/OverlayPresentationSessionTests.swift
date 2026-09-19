import AppKit
import XCTest
@testable import DynamicIsland

@MainActor
final class OverlayPresentationSessionTests: XCTestCase {
    func testSavedEnabledPreferenceAllowsStartupPresentation() {
        withRestoredSettings(overlayEnabled: true) { settings in
            XCTAssertTrue(OverlayPresentationSession().allowsWork(overlayEnabled: settings.overlayEnabled))
        }
    }

    func testSavedDisabledPreferenceRejectsStartupPresentation() {
        withRestoredSettings(overlayEnabled: false) { settings in
            XCTAssertFalse(OverlayPresentationSession().allowsWork(overlayEnabled: settings.overlayEnabled))
        }
    }

    func testDisableRejectsCurrentPresentationAndNativeScroll() {
        var session = OverlayPresentationSession()
        session.invalidate(at: 10)
        XCTAssertFalse(session.allowsWork(overlayEnabled: false, generation: session.generation))
        XCTAssertFalse(scroll(&session, enabled: false, timestamp: 11, phase: .began))
    }

    func testDisableDuringExpansionRejectsCallbackAfterReenable() {
        var session = OverlayPresentationSession()
        let expansion = session.generation
        session.invalidate(at: 10)
        XCTAssertFalse(session.allowsWork(overlayEnabled: false, generation: expansion))
        session.invalidate(at: 11)
        XCTAssertFalse(session.allowsWork(overlayEnabled: true, generation: expansion))
    }

    func testPendingCollapseGeometryAndPollingCannotCrossSession() {
        var session = OverlayPresentationSession()
        let scheduledWork = session.generation
        session.invalidate(at: 10)
        XCTAssertFalse(session.allowsWork(overlayEnabled: false, generation: scheduledWork))
        session.invalidate(at: 11)
        XCTAssertFalse(session.allowsWork(overlayEnabled: true, generation: scheduledWork))
        XCTAssertTrue(session.allowsWork(overlayEnabled: true, generation: session.generation))
    }

    func testAlreadyEnqueuedGestureCompletionCannotExecuteAfterReenable() {
        var session = OverlayPresentationSession()
        let gesture = session.generation
        var commands = 0
        let completion: (OverlayPresentationSession) -> Void = { current in
            guard current.allowsWork(overlayEnabled: true, generation: gesture) else { return }
            commands += 1
        }
        session.invalidate(at: 10)
        session.invalidate(at: 11)
        completion(session)
        XCTAssertEqual(commands, 0)
    }

    func testReenableAllowsOnlyNewPresentationWork() {
        var session = OverlayPresentationSession()
        session.invalidate(at: 10)
        let disabledSession = session.generation
        session.invalidate(at: 11)
        XCTAssertTrue(session.allowsWork(overlayEnabled: true))
        XCTAssertFalse(session.allowsWork(overlayEnabled: true, generation: disabledSession))
        XCTAssertTrue(session.allowsWork(overlayEnabled: true, generation: session.generation))
    }

    func testNativeEventQueuedBeforeReenableIsRejectedEvenIfItHasBeganPhase() {
        var session = OverlayPresentationSession()
        session.invalidate(at: 10)
        XCTAssertFalse(scroll(&session, enabled: true, timestamp: 9, phase: .began))
    }

    func testContinuingScrollTailsRemainIneligibleAfterReenable() {
        var session = OverlayPresentationSession()
        session.invalidate(at: 10)
        for timestamp in [10.1, 10.2, 10.3, 10.4, 10.5, 10.9] {
            XCTAssertFalse(scroll(&session, enabled: true, timestamp: timestamp, phase: .changed))
        }
    }

    func testExplicitNewSwipeRestoresScrollWithoutChangingNormalSessionRouting() {
        var session = OverlayPresentationSession()
        session.invalidate(at: 10)
        XCTAssertFalse(scroll(&session, enabled: true, timestamp: 10.1, phase: .changed))
        XCTAssertTrue(scroll(&session, enabled: true, timestamp: 10.2, phase: .began))
        XCTAssertTrue(scroll(&session, enabled: true, timestamp: 10.21, phase: .changed))
        XCTAssertTrue(scroll(&session, enabled: true, timestamp: 10.22, phase: .ended))
    }

    func testPhaseLessDevicesResumeAfterExistingQuietBoundary() {
        var session = OverlayPresentationSession()
        session.invalidate(at: 10)
        XCTAssertFalse(scroll(&session, enabled: true, timestamp: 10.1, phase: []))
        XCTAssertTrue(scroll(&session, enabled: true, timestamp: 10.4, phase: []))
        XCTAssertTrue(scroll(&session, enabled: true, timestamp: 10.41, phase: []))
    }

    func testInitiallyEnabledSessionAcceptsLegacyPhaseLessScroll() {
        var session = OverlayPresentationSession()
        XCTAssertTrue(scroll(&session, enabled: true, timestamp: 1, phase: []))
    }

    func testRapidEnableDisableEnableRejectsAllEarlierCallbacks() {
        var session = OverlayPresentationSession()
        let initial = session.generation
        session.invalidate(at: 10)
        let firstEnable = session.generation
        session.invalidate(at: 10.1)
        session.invalidate(at: 10.2)
        XCTAssertFalse(session.allowsWork(overlayEnabled: true, generation: initial))
        XCTAssertFalse(session.allowsWork(overlayEnabled: true, generation: firstEnable))
        XCTAssertTrue(session.allowsWork(overlayEnabled: true, generation: session.generation))
    }

    private func scroll(
        _ session: inout OverlayPresentationSession, enabled: Bool,
        timestamp: TimeInterval, phase: NSEvent.Phase
    ) -> Bool {
        session.acceptsScroll(overlayEnabled: enabled, timestamp: timestamp, phase: phase, quietPeriod: 0.28)
    }

    private func withRestoredSettings(overlayEnabled: Bool, check: (AppSettings) -> Void) {
        let suite = "OverlayPresentationSessionTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.overlayEnabled = overlayEnabled
        check(AppSettings(defaults: defaults))
    }
}
