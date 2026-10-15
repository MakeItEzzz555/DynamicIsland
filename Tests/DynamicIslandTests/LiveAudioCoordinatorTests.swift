import Combine
import XCTest
@testable import DynamicIsland

/// Counts backend calls and can fail starts; frames only when a test asks.
private final class LifecycleBackend: AudioSpectrumCaptureBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _starts = 0, _stops = 0
    private var _failure: NativeAudioError?
    let mailbox = AudioSpectrumMailbox()
    var starts: Int { lock.withLock { _starts } }
    var stops: Int { lock.withLock { _stops } }
    func fail(with error: NativeAudioError?) { lock.withLock { _failure = error } }
    func start(generation: UInt64) async throws -> AudioSpectrumMailbox {
        let failure = lock.withLock { () -> NativeAudioError? in _starts += 1; return _failure }
        if let failure { throw failure }
        return mailbox
    }
    func stop(generation: UInt64) async throws { lock.withLock { _stops += 1 } }
}

/// Live Audio contract revision 3: saved consent + visibility + playback +
/// session drive one capture; no real audio or permission is ever touched.
@MainActor
final class LiveAudioCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var backend: LifecycleBackend!
    private var controller: AudioSpectrumController!
    private var playing: CurrentValueSubject<Bool, Never>!
    private var coordinator: LiveAudioCoordinator!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "LiveAudioCoordinatorTests.\(UUID().uuidString)")
        settings = AppSettings(defaults: defaults)
        makeCoordinator()
    }

    override func tearDown() async throws {
        await controller.shutdown()
    }

    private func makeCoordinator() {
        backend = LifecycleBackend()
        controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        playing = CurrentValueSubject(false)
        coordinator = LiveAudioCoordinator(controller: controller, settings: settings, playback: playing.eraseToAnyPublisher(),
                                           releaseGrace: .milliseconds(40), resumeDelay: .milliseconds(30), observeSystemEvents: false)
    }

    private func settle(_ ms: Int = 80) async { try? await Task.sleep(for: .milliseconds(ms)) }
    private var running: Bool {
        [.starting, .capturing].contains(controller.presentation.availability)
    }
    private func capture() async {
        backend.mailbox.publish(AudioSpectrumFrame(sequence: UInt64.random(in: 1...UInt64.max), hostTime: 1, sampleRate: 48_000,
                                                   bands: SIMD8(repeating: 0.5), rms: 0.3, peak: 0.5, hasSignal: true))
        await settle()
    }

    func testDisabledByDefaultAndNothingStartsWithoutConsent() async {
        XCTAssertFalse(settings.liveAudioVisualizerEnabled)
        XCTAssertFalse(coordinator.desiredEnabled)
        coordinator.acquire(UUID()); playing.send(true)
        await settle()
        XCTAssertEqual(backend.starts, 0, "launch, previews and visible bars never start capture without consent")
    }

    func testFirstExplicitEnableStartsNowThenSettlesWhenNotEligible() async {
        coordinator.userSetEnabled(true)
        XCTAssertTrue(settings.liveAudioVisualizerEnabled)
        XCTAssertEqual(LiveAudioStatus(controller.presentation, desired: coordinator.desiredEnabled).isOn, true)
        await settle()
        XCTAssertEqual(backend.starts, 1, "the explicit action is what may raise the macOS prompt")
        await capture() // permission settled: the first buffers arrive
        await settle(150)
        XCTAssertFalse(running, "no visible, playing visualizer: the explicit start settles and stops")
        XCTAssertTrue(LiveAudioStatus(controller.presentation, desired: true).isOn, "stopped capture never shows the switch off")
    }

    func testConsentPersistsAndAutomaticallyStartsAfterRelaunch() async {
        coordinator.userSetEnabled(true)
        await settle(150)
        await controller.shutdown()
        settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.liveAudioVisualizerEnabled)
        makeCoordinator()
        XCTAssertTrue(coordinator.desiredEnabled)
        coordinator.acquire(UUID()); playing.send(true)
        await settle()
        XCTAssertEqual(backend.starts, 1, "previously authorized consent resumes without another click")
        await capture()
        XCTAssertEqual(controller.presentation.availability, .capturing)
    }

    func testPausePlayAndFinalObserverRemoval() async {
        settings.liveAudioVisualizerEnabled = true; makeCoordinator()
        let lease = UUID()
        coordinator.acquire(lease); playing.send(true); await capture()
        playing.send(false); await settle()
        XCTAssertFalse(running, "pause stops capture")
        playing.send(true); await settle()
        XCTAssertEqual(backend.starts, 2)
        coordinator.release(lease)
        XCTAssertTrue(running, "release waits for the grace period")
        await settle(120)
        XCTAssertFalse(running, "the last visualizer leaving stops capture")
    }

    func testCompactToExpandedSwapKeepsOneTap() async {
        settings.liveAudioVisualizerEnabled = true; makeCoordinator()
        let compact = UUID(), expanded = UUID()
        coordinator.acquire(compact); playing.send(true); await capture()
        coordinator.release(compact)
        coordinator.acquire(expanded)
        coordinator.acquire(expanded) // SwiftUI remount re-appears
        await settle(120)
        XCTAssertEqual(backend.starts, 1)
        XCTAssertEqual(coordinator.activeLeaseCount, 1)
        XCTAssertTrue(running)
    }

    func testSleepLockAndWakeSuspendAndResume() async {
        settings.liveAudioVisualizerEnabled = true; makeCoordinator()
        coordinator.acquire(UUID()); playing.send(true); await capture()
        coordinator.setSessionActive(false); await settle()
        XCTAssertFalse(running)
        coordinator.setSessionActive(true); await settle()
        XCTAssertTrue(running)
        XCTAssertEqual(backend.starts, 2)
    }

    func testOutputDeviceSuspensionResumesOnceWhileEligible() async {
        settings.liveAudioVisualizerEnabled = true; makeCoordinator()
        coordinator.acquire(UUID()); playing.send(true); await capture()
        controller.suspend() // what the backend reports after an output change
        // `.starting` already counts as running before the backend's async start
        // runs, so wait for that start instead of a fixed sleep (slow CI raced it).
        let deadline = ContinuousClock.now + .seconds(2)
        while backend.starts < 2, ContinuousClock.now < deadline { await settle(5) }
        XCTAssertTrue(running, "capture resumes on the new output")
        XCTAssertEqual(backend.starts, 2)
        coordinator.setSessionActive(false)
        controller.suspend(); await settle(150)
        XCTAssertFalse(running, "a locked or sleeping session never resumes")
    }

    func testPermissionDenialBlocksAutomaticRetriesUntilTheUserActs() async {
        backend.fail(with: .permissionDenied)
        coordinator.acquire(UUID()); playing.send(true)
        coordinator.userSetEnabled(true); await settle(150)
        XCTAssertTrue(coordinator.permissionBlocked)
        XCTAssertTrue(LiveAudioStatus(controller.presentation, desired: true).offersPrivacySettings)
        playing.send(false); playing.send(true); coordinator.setSessionActive(false); coordinator.setSessionActive(true)
        await settle()
        XCTAssertEqual(backend.starts, 1, "a denial is never retried automatically")
        backend.fail(with: nil)
        coordinator.userSetEnabled(true); await capture()
        XCTAssertEqual(backend.starts, 2, "an explicit retry is allowed")
        XCTAssertEqual(controller.presentation.availability, .capturing)
    }

    func testOtherFailuresRetryOnlyOnTheNextEdgeNotInALoop() async {
        settings.liveAudioVisualizerEnabled = true; makeCoordinator()
        backend.fail(with: .operationFailed(.createTap, -1))
        coordinator.acquire(UUID()); playing.send(true); await settle(200)
        XCTAssertEqual(backend.starts, 1, "no retry loop")
        XCTAssertFalse(coordinator.permissionBlocked)
        backend.fail(with: nil)
        playing.send(false); playing.send(true); await capture()
        XCTAssertEqual(backend.starts, 2)
        XCTAssertEqual(controller.presentation.availability, .capturing)
    }

    func testRapidTogglesEndInTheLastChoice() async {
        coordinator.acquire(UUID()); playing.send(true)
        for _ in 0..<5 { coordinator.userSetEnabled(true); coordinator.userSetEnabled(false) }
        await settle(200)
        XCTAssertFalse(settings.liveAudioVisualizerEnabled)
        XCTAssertFalse(running)
        coordinator.userSetEnabled(true); await capture()
        XCTAssertEqual(controller.presentation.availability, .capturing)
    }

    func testShutdownBlocksAutomaticRestarts() async {
        settings.liveAudioVisualizerEnabled = true; makeCoordinator()
        coordinator.acquire(UUID()); playing.send(true); await capture()
        coordinator.prepareForShutdown()
        await controller.shutdown()
        playing.send(false); playing.send(true); await settle()
        XCTAssertEqual(backend.starts, 1)
        XCTAssertNil(controller.presentation.frame, "late frames cannot relight after shutdown")
    }
}
