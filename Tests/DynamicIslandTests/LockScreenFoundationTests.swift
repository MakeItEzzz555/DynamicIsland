import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
private final class FakeLockSignals: LockSignalSource {
    var handler: (@MainActor (LockSignal) -> Void)?
    var stops = 0
    func start(_ handler: @escaping @MainActor (LockSignal) -> Void) { self.handler = handler }
    func stop() { stops += 1; handler = nil }
    func send(_ signal: LockSignal) { handler?(signal) }
}

@MainActor
private final class FakeLockSpace: LockScreenSpaceProviding {
    var availability = LockScreenSpaceAvailability.available
    var accepts = true
    var adopted: [Int] = []
    var teardowns = 0
    var prepares = 0
    func prepare() -> Bool { prepares += 1; return accepts }
    func adopt(windowNumber: Int) -> Bool { guard accepts, windowNumber > 0 else { return false }; adopted.append(windowNumber); return true }
    func teardown() { teardowns += 1 }
}

@MainActor
final class LockStateMonitorTests: XCTestCase {
    private func run(_ signals: [LockSignal], from start: LockState = .unknown) -> LockState {
        signals.reduce(start, LockStateReducer.reduce)
    }

    func testOnlyAnExplicitUnlockConfirmsUnlocked() {
        XCTAssertEqual(run([.screenLocked]), .locked)
        XCTAssertEqual(run([.screenLocked, .screenUnlocked]), .unlocked)
        XCTAssertEqual(run([.screenLocked, .sessionBecameActive]), .locked, "session activation is not proof of unlock")
        XCTAssertEqual(run([.screenLocked, .screensSlept, .screensWoke]), .locked, "wake is not unlock")
    }

    func testUncertainTransitionsFailClosed() {
        XCTAssertEqual(run([.screenUnlocked, .screensSlept, .screensWoke]), .unknown, "sleep may engage the lock")
        XCTAssertEqual(run([.screenUnlocked, .screensaverStarted, .screensaverStopped]), .unknown, "the saver may require a password")
        XCTAssertEqual(run([.screenLocked, .sessionResigned]), .sessionInactive, "another user owns the console")
        XCTAssertEqual(run([.screenLocked, .sessionResigned, .sessionBecameActive]), .unknown, "returning passes loginwindow")
        for state in [LockState.unknown, .unlocked, .sessionInactive, .sleeping(locked: true), .screensaver(locked: false)] {
            XCTAssertFalse(state.isConfirmedLocked, "\(state)")
        }
    }

    func testScreensaverKeepsTheLockUnderneath() {
        XCTAssertEqual(run([.screenLocked, .screensaverStarted]), .screensaver(locked: true))
        XCTAssertTrue(run([.screenLocked, .screensaverStarted]).isConfirmedLocked)
        XCTAssertEqual(run([.screenLocked, .screensaverStarted, .screensaverStopped]), .locked)
        XCTAssertEqual(run([.screenLocked, .screensaverStarted, .screensSlept, .screensWoke]), .locked)
    }

    func testMonitorDeduplicatesAndAdvancesGenerationOnlyOnChange() {
        let source = FakeLockSignals()
        let monitor = LockStateMonitor(source: source)
        monitor.start(); monitor.start()
        source.send(.screenLocked)
        let afterLock = monitor.generation
        source.send(.screenLocked); source.send(.sessionBecameActive)
        XCTAssertEqual(monitor.generation, afterLock, "duplicates do not republish")
        XCTAssertEqual(monitor.state, .locked)
        source.send(.screenUnlocked)
        XCTAssertEqual(monitor.state, .unlocked)
        XCTAssertGreaterThan(monitor.generation, afterLock)
        monitor.stop(); monitor.stop()
        XCTAssertEqual(source.stops, 1)
        XCTAssertEqual(monitor.state, .unknown, "a stopped monitor never claims a lock")
        source.send(.screenLocked)
        XCTAssertEqual(monitor.state, .unknown, "signals after stop are ignored")
    }
}

final class LockScreenPrivacyProjectorTests: XCTestCase {
    private let sources = LockScreenSources(
        mediaTitle: "  Song  ", mediaArtist: "Artist", mediaArtworkRevision: 3, mediaIsPlaying: true,
        mediaCanSkip: true, mediaCanSeek: false, timerRemainingSeconds: 90, timerTotalSeconds: 180, timerIsRunning: true,
        keepAwakeExpiresAt: Date(timeIntervalSince1970: 100), keepAwakeActive: true,
        batteryPercent: 140, batteryCharging: true, alertCategory: .lowBattery)

    func testNothingIsDisclosedByDefaultOrWhenNotConfirmedLocked() {
        XCTAssertEqual(LockScreenPrivacyProjector.project(sources, disclosure: .init(), state: .locked), .empty)
        let all = LockScreenDisclosure(media: true, mediaMetadata: true, timer: true, keepAwake: true, battery: true, alerts: true)
        for state in [LockState.unknown, .unlocked, .sessionInactive, .sleeping(locked: true), .screensaver(locked: false)] {
            XCTAssertEqual(LockScreenPrivacyProjector.project(sources, disclosure: all, state: state), .empty, "\(state)")
        }
    }

    func testAllowlistedFieldsOnlyWithMetadataOptIn() {
        var disclosure = LockScreenDisclosure(media: true, timer: true, keepAwake: true, battery: true, alerts: true)
        let generic = LockScreenPrivacyProjector.project(sources, disclosure: disclosure, state: .locked)
        XCTAssertEqual(generic.media?.title, "Now Playing", "track metadata needs its own opt-in")
        XCTAssertEqual(generic.media?.artist, "")
        XCTAssertNil(generic.media?.artworkRevision)
        XCTAssertEqual(generic.timer, .init(remainingSeconds: 90, progress: 0.5, isRunning: true))
        XCTAssertEqual(generic.battery?.percent, 100, "values are clamped")
        XCTAssertEqual(generic.alert?.label, "Battery low", "alerts carry only fixed generic labels")
        disclosure.mediaMetadata = true
        let detailed = LockScreenPrivacyProjector.project(sources, disclosure: disclosure, state: .screensaver(locked: true))
        XCTAssertEqual(detailed.media?.title, "Song")
        XCTAssertEqual(detailed.media?.artist, "Artist")
        XCTAssertEqual(detailed.media?.artworkRevision, 3)
    }
}

@MainActor
final class LockScreenSurfaceControllerTests: XCTestCase {
    override func setUp() async throws { _ = NSApplication.shared }

    private func controller(_ space: LockScreenSpaceProviding) -> LockScreenSurfaceController {
        LockScreenSurfaceController(space: space, frame: { _ in CGRect(x: -4000, y: -4000, width: 120, height: 40) },
                                    content: { AnyView(Text($0.rawValue)) })
    }

    func testProductionDefaultShowsNothingAnywhere() {
        let space = UnavailableLockScreenSpace()
        let surfaces = controller(space)
        surfaces.update(state: .locked, requested: Set(LockScreenSurfaceKind.allCases))
        XCTAssertTrue(surfaces.visible.isEmpty)
        guard case .unavailable = surfaces.availability else { return XCTFail("must be unavailable without approval") }
        XCTAssertFalse(NSApp.windows.contains { $0 is LockScreenPanel && $0.isVisible })
        surfaces.stop()
    }

    func testWindowsAppearOnlyWhenAdoptedAndConfirmedLocked() {
        let space = FakeLockSpace()
        let surfaces = controller(space)
        surfaces.update(state: .unknown, requested: [.hud, .nowPlaying])
        XCTAssertTrue(surfaces.visible.isEmpty)
        XCTAssertTrue(space.adopted.isEmpty, "nothing is delegated before a confirmed lock")

        surfaces.update(state: .locked, requested: [.hud, .nowPlaying])
        XCTAssertEqual(surfaces.visible, [.hud, .nowPlaying])
        XCTAssertEqual(space.adopted.count, 2)

        surfaces.update(state: .unlocked, requested: [.hud, .nowPlaying])
        XCTAssertTrue(surfaces.visible.isEmpty)
        surfaces.update(state: .locked, requested: [.hud, .nowPlaying])
        XCTAssertEqual(space.adopted.count, 2, "each window is delegated once and reused")

        surfaces.stop(); surfaces.stop()
        XCTAssertTrue(surfaces.visible.isEmpty)
        XCTAssertEqual(space.teardowns, 2)
        XCTAssertFalse(NSApp.windows.contains { $0 is LockScreenPanel && $0.isVisible })
    }

    func testRefusedAdoptionNeverShowsTheWindow() {
        let space = FakeLockSpace()
        space.accepts = false
        let surfaces = controller(space)
        surfaces.update(state: .locked, requested: [.hud])
        XCTAssertTrue(surfaces.visible.isEmpty)
        XCTAssertFalse(NSApp.windows.contains { $0 is LockScreenPanel && $0.isVisible })
        surfaces.stop()
    }

    func testWindowRecipeKeepsKeyboardWithLoginAndOnlyControlsTakeThePointer() {
        for kind in LockScreenSurfaceKind.allCases {
            let window = LockScreenSurfaceController.makeWindow(kind)
            XCTAssertFalse(window.canBecomeKey, "\(kind) never takes the password field's focus")
            XCTAssertFalse(window.canBecomeMain)
            XCTAssertTrue(window.canBecomeVisibleWithoutLogin)
            XCTAssertEqual(window.sharingType, NSWindow.SharingType.none)
            XCTAssertEqual(window.ignoresMouseEvents, !kind.isInteractive, "\(kind)")
            XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
            XCTAssertTrue(window.collectionBehavior.contains(.stationary))
            window.close()
        }
        XCTAssertTrue(LockScreenSurfaceKind.hud.isInteractive == false)
    }
}
