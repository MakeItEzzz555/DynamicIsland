import AppKit
import CoreGraphics
import XCTest
@testable import DynamicIsland

/// Fake SkyLight entry points; C function pointers cannot capture, so state is static.
private enum FakeSLS {
    nonisolated(unsafe) static var calls: [String] = []
    nonisolated(unsafe) static var connection: Int32 = 7
    nonisolated(unsafe) static var space: UInt64 = 0x1_0000_0005 // > 32 bits: proves 64-bit plumbing
    nonisolated(unsafe) static var levelResult: Int32 = 0
    nonisolated(unsafe) static var levels: [UInt64] = []
    static func reset() { calls = []; connection = 7; space = 0x1_0000_0005; levelResult = 0; levels = [] }
}
private let fakeMain: @convention(c) () -> Int32 = { FakeSLS.calls.append("main"); return FakeSLS.connection }
private let fakeCreate: @convention(c) (Int32, Int32, UnsafeRawPointer?) -> UInt64 = { _, flag, options in
    FakeSLS.calls.append("create flag=\(flag) options=\(options == nil ? "nil" : "set")"); return FakeSLS.space }
private let fakeLevel: @convention(c) (Int32, UInt64, Int32) -> Int32 = { _, space, level in
    FakeSLS.levels.append(space); FakeSLS.calls.append("level \(level)"); return FakeSLS.levelResult }
// Void like the real calls: SLSShowSpaces returns 1 and Add returns nothing on 15.7.4.
private let fakeShow: @convention(c) (Int32, CFArray) -> Void = { _, _ in FakeSLS.calls.append("show") }
private let fakeHide: @convention(c) (Int32, CFArray) -> Void = { _, _ in FakeSLS.calls.append("hide") }
private let fakeAdd: @convention(c) (Int32, UInt64, CFArray, Int32) -> Void = { _, _, windows, mode in
    FakeSLS.calls.append("add \((windows as NSArray).count) mode=\(mode)") }
private let fakeDestroy: @convention(c) (Int32, UInt64) -> Int32 = { _, _ in FakeSLS.calls.append("destroy"); return 0 }

private func fakeSymbols(missing: Set<String> = []) -> (String) -> UnsafeMutableRawPointer? {
    { name in
        guard !missing.contains(name) else { return nil }
        switch name {
        case "SLSMainConnectionID": return unsafeBitCast(fakeMain, to: UnsafeMutableRawPointer.self)
        case "SLSSpaceCreate": return unsafeBitCast(fakeCreate, to: UnsafeMutableRawPointer.self)
        case "SLSSpaceSetAbsoluteLevel": return unsafeBitCast(fakeLevel, to: UnsafeMutableRawPointer.self)
        case "SLSShowSpaces": return unsafeBitCast(fakeShow, to: UnsafeMutableRawPointer.self)
        case "SLSHideSpaces": return unsafeBitCast(fakeHide, to: UnsafeMutableRawPointer.self)
        case "SLSSpaceAddWindowsAndRemoveFromSpaces": return unsafeBitCast(fakeAdd, to: UnsafeMutableRawPointer.self)
        case "SLSSpaceDestroy": return unsafeBitCast(fakeDestroy, to: UnsafeMutableRawPointer.self)
        default: return nil
        }
    }
}

@MainActor
final class SkyLightLockScreenSpaceTests: XCTestCase {
    override func setUp() async throws { FakeSLS.reset() }

    func testOnlyTestedMacOSVersionsAreEnabled() {
        XCTAssertTrue(SkyLightLockScreenSpace.isTestedOS(.init(majorVersion: 15, minorVersion: 7, patchVersion: 4)))
        XCTAssertFalse(SkyLightLockScreenSpace.isTestedOS(.init(majorVersion: 15, minorVersion: 6, patchVersion: 0)))
        XCTAssertFalse(SkyLightLockScreenSpace.isTestedOS(.init(majorVersion: 26, minorVersion: 0, patchVersion: 0)))
        var lookups = 0
        let space = SkyLightLockScreenSpace(isTestedOS: false, loadSymbol: { _ in lookups += 1; return nil })
        XCTAssertNotEqual(space.availability, .available)
        XCTAssertEqual(lookups, 0, "untested systems never even resolve private symbols")
        XCTAssertFalse(space.adopt(windowNumber: 42))
    }

    func testAMissingRequiredSymbolDisablesEverythingWithoutCalls() {
        let space = SkyLightLockScreenSpace(isTestedOS: true, loadSymbol: fakeSymbols(missing: ["SLSShowSpaces"]))
        XCTAssertNotEqual(space.availability, .available)
        XCTAssertFalse(space.adopt(windowNumber: 42))
        XCTAssertTrue(FakeSLS.calls.isEmpty, "a missing function is never called")
        let optionalMissing = SkyLightLockScreenSpace(isTestedOS: true, loadSymbol: fakeSymbols(missing: ["SLSHideSpaces", "SLSSpaceDestroy"]))
        XCTAssertEqual(optionalMissing.availability, .available, "teardown helpers are optional")
    }

    func testSpaceIsCreatedLazilyOnceAtLevel400AndWindowsAdoptedOnce() {
        let space = SkyLightLockScreenSpace(isTestedOS: true, loadSymbol: fakeSymbols())
        XCTAssertTrue(FakeSLS.calls.isEmpty, "creating the provider opens nothing")
        XCTAssertTrue(space.adopt(windowNumber: 42))
        XCTAssertEqual(FakeSLS.calls, ["main", "create flag=1 options=nil", "level 400", "show", "add 1 mode=7"])
        XCTAssertEqual(FakeSLS.levels, [0x1_0000_0005], "the full 64-bit space ID reaches SkyLight")
        XCTAssertTrue(space.adopt(windowNumber: 42))
        XCTAssertTrue(space.adopt(windowNumber: 43))
        XCTAssertEqual(FakeSLS.calls.filter { $0.hasPrefix("add") }.count, 2, "each window is delegated once")
        XCTAssertEqual(FakeSLS.calls.filter { $0.hasPrefix("create") }.count, 1)
        XCTAssertFalse(space.adopt(windowNumber: 0), "invalid window numbers are refused")

        space.teardown(); space.teardown()
        XCTAssertEqual(Array(FakeSLS.calls.suffix(2)), ["hide", "destroy"])
        XCTAssertEqual(FakeSLS.calls.filter { $0 == "destroy" }.count, 1, "teardown is idempotent")
    }

    func testPrepareCreatesTheSpaceOnceBeforeAnyWindow() {
        let space = SkyLightLockScreenSpace(isTestedOS: true, loadSymbol: fakeSymbols())
        XCTAssertTrue(space.prepare()); XCTAssertTrue(space.prepare())
        XCTAssertEqual(FakeSLS.calls, ["main", "create flag=1 options=nil", "level 400", "show"])
        XCTAssertTrue(space.adopt(windowNumber: 42))
        XCTAssertEqual(FakeSLS.calls.last, "add 1 mode=7")
        XCTAssertFalse(SkyLightLockScreenSpace(isTestedOS: false, loadSymbol: fakeSymbols()).prepare())
    }

    func testFailuresFailClosed() {
        FakeSLS.connection = 0
        let noConnection = SkyLightLockScreenSpace(isTestedOS: true, loadSymbol: fakeSymbols())
        XCTAssertFalse(noConnection.adopt(windowNumber: 42))
        XCTAssertNotEqual(noConnection.availability, .available)

        FakeSLS.reset(); FakeSLS.space = 0
        let noSpace = SkyLightLockScreenSpace(isTestedOS: true, loadSymbol: fakeSymbols())
        XCTAssertFalse(noSpace.adopt(windowNumber: 42))
        XCTAssertFalse(FakeSLS.calls.contains("level 400"))

        FakeSLS.reset(); FakeSLS.levelResult = 1000
        let noLevel = SkyLightLockScreenSpace(isTestedOS: true, loadSymbol: fakeSymbols())
        XCTAssertFalse(noLevel.adopt(windowNumber: 42))
        XCTAssertTrue(FakeSLS.calls.contains("destroy"), "a space that could not be raised is destroyed")
        XCTAssertFalse(FakeSLS.calls.contains { $0.hasPrefix("add") })
    }
}

@MainActor
private final class Signals: LockSignalSource {
    var handler: (@MainActor (LockSignal) -> Void)?
    func start(_ handler: @escaping @MainActor (LockSignal) -> Void) { self.handler = handler }
    func stop() { handler = nil }
}

@MainActor
private final class AdoptingSpace: LockScreenSpaceProviding {
    var availability = LockScreenSpaceAvailability.available
    var teardowns = 0
    var adopted: Set<Int> = []
    func prepare() -> Bool { true }
    func adopt(windowNumber: Int) -> Bool { guard windowNumber > 0 else { return false }; adopted.insert(windowNumber); return true }
    func teardown() { teardowns += 1 }
}

@MainActor
final class LockScreenCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var signals: Signals!
    private var space: AdoptingSpace!
    private var sounds: [String] = []
    private var coordinator: LockScreenCoordinator!

    override func setUp() async throws {
        _ = NSApplication.shared
        defaults = UserDefaults(suiteName: "LockScreenCoordinatorTests.\(UUID())")
        settings = AppSettings(defaults: defaults)
        signals = Signals(); space = AdoptingSpace(); sounds = []
        let activities = LiveActivityStore()
        coordinator = LockScreenCoordinator(
            settings: settings, media: MediaController(startsAutomatically: false), timer: TimerController(),
            keepAwake: KeepAwakeController(liveActivities: activities, capabilities: IslandCapabilityRegistry()),
            systemHUD: SystemHUDController(settings: settings, liveActivities: activities),
            monitor: LockStateMonitor(source: signals), makeSpace: { [unowned self] in self.space },
            readBattery: { BatteryActivitySnapshot(percentage: 80, powerSourceStateDescription: nil, isPluggedIn: false,
                                                   isCharging: false, isCharged: false, isOnBattery: true) },
            playSound: { [unowned self] name, _ in self.sounds.append(name) },
            unlockDuration: .milliseconds(400))
        coordinator.start()
    }

    override func tearDown() async throws { coordinator.terminate() }

    private func settle() async { for _ in 0..<10 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(20)) }
    private func send(_ signal: LockSignal) async { signals.handler?(signal); await settle() }
    private func enable(_ change: (inout LockScreenPreferences) -> Void = { _ in }) async {
        var prefs = settings.lockScreenPreferences
        prefs.enabled = true; prefs.lockSound = "Funk"; prefs.unlockSound = "Glass"
        change(&prefs)
        settings.lockScreenPreferences = prefs
        await settle()
    }

    func testOffByDefaultObservesNothingAndShowsNothing() async {
        XCTAssertFalse(settings.lockScreenPreferences.enabled)
        await settle()
        XCTAssertNil(signals.handler, "no lock observers while the feature is off")
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty)
    }

    func testLockShowsAllowedSurfacesWithOneSoundAndUnlockMorphsThenHides() async throws {
        await enable()
        XCTAssertNotNil(signals.handler)
        await send(.screenUnlocked)
        await send(.screenLocked)
        XCTAssertEqual(sounds, ["Funk"], "the lock sound plays exactly once")
        XCTAssertEqual(coordinator.hudPhase, .locked)
        XCTAssertTrue(coordinator.visibleSurfaces.isSuperset(of: [.hud, .status]), "\(coordinator.visibleSurfaces)")
        XCTAssertNil(coordinator.content.media, "no active media source means no media card")
        XCTAssertEqual(coordinator.content.battery?.percent, 80)

        await send(.screensSlept)
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty, "a sleeping display hides everything")
        await send(.screensWoke)
        XCTAssertEqual(sounds, ["Funk"], "waking a locked Mac does not replay the lock sound")
        XCTAssertFalse(coordinator.visibleSurfaces.isEmpty)

        await send(.screenUnlocked)
        XCTAssertEqual(sounds, ["Funk", "Glass"], "the unlock sound plays exactly once")
        XCTAssertEqual(coordinator.hudPhase, .unlocking)
        XCTAssertEqual(coordinator.visibleSurfaces, [.hud], "widgets leave at once; only the HUD morphs")
        XCTAssertEqual(coordinator.content, .empty)
        let deadline = ContinuousClock.now + .seconds(3)
        while coordinator.hudPhase != .hidden, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(coordinator.hudPhase, .hidden)
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty)
    }

    func testEnablingPreparesTheSpaceAndEveryWindowBeforeAnyLock() async {
        await enable()
        XCTAssertEqual(space.adopted.count, LockScreenSurfaceKind.allCases.count,
                       "windows join the space while unlocked; a space made mid-lock only appears next time")
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty, "prepared windows stay hidden until a confirmed lock")
        XCTAssertFalse(NSApp.windows.contains { $0 is LockScreenPanel && $0.isVisible })
        await send(.screenLocked)
        XCTAssertFalse(coordinator.visibleSurfaces.isEmpty, "the very first lock shows surfaces")
        XCTAssertEqual(space.adopted.count, LockScreenSurfaceKind.allCases.count, "no adoption happens during the lock")
    }

    func testTheFirstLockAfterEnablingPlaysItsSound() async {
        await enable()
        await send(.screenLocked)
        XCTAssertEqual(sounds, ["Funk"])
        await send(.screensaverStarted)
        await send(.screensaverStopped)
        XCTAssertEqual(sounds, ["Funk"], "ending the screensaver over a lock is silent")
    }

    func testUncertainOwnershipHidesImmediatelyWithoutSounds() async {
        await enable()
        await send(.screenUnlocked)
        await send(.screenLocked)
        sounds.removeAll()
        await send(.sessionResigned)
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty, "user switching hides at once")
        XCTAssertTrue(sounds.isEmpty)
        XCTAssertEqual(coordinator.content, .empty)
    }

    func testScreensaverHidesUnlessAllowedAndDisableReleasesTheSpace() async {
        await enable()
        await send(.screenUnlocked)
        await send(.screenLocked)
        await send(.screensaverStarted)
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty, "hidden during the screensaver by default")
        await enable { $0.keepVisibleDuringScreensaver = true }
        XCTAssertFalse(coordinator.visibleSurfaces.isEmpty)

        var prefs = settings.lockScreenPreferences
        prefs.enabled = false
        settings.lockScreenPreferences = prefs
        await settle()
        XCTAssertTrue(coordinator.visibleSurfaces.isEmpty)
        XCTAssertEqual(space.teardowns, 1)
        XCTAssertNil(signals.handler, "observers are removed when disabled")
        XCTAssertFalse(NSApp.windows.contains { $0 is LockScreenPanel && $0.isVisible })
    }

    func testPreferencesPersistAndDecodeMissingKeysAsDefaults() throws {
        var prefs = LockScreenPreferences()
        prefs.enabled = true; prefs.soundVolume = 7; prefs.mediaVerticalOffset = .nan
        settings.lockScreenPreferences = prefs
        let restored = AppSettings(defaults: defaults).lockScreenPreferences
        XCTAssertTrue(restored.enabled)
        XCTAssertEqual(restored.soundVolume, 1, "values are normalized before saving")
        XCTAssertEqual(restored.mediaVerticalOffset, 0)
        let partial = try JSONDecoder().decode(LockScreenPreferences.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertTrue(partial.enabled)
        XCTAssertEqual(partial.unlockSound, LockScreenPreferences.defaults.unlockSound, "new keys keep their defaults")
        XCTAssertFalse(partial.showTrackDetails, "track details stay private by default")
    }
}
