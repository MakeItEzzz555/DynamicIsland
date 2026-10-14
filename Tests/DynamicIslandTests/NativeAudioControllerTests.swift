import XCTest
@testable import DynamicIsland

@MainActor
final class NativeAudioControllerTests: XCTestCase {
    func testConstructionAndSubscriptionAreInertAndExplicitStartIsIdempotent() async throws {
        let backend = TestSpectrumBackend()
        let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        let subscription = controller.presentationPublisher.sink { _ in }
        controller.suspend()
        XCTAssertEqual(controller.presentation.availability, .disabled, "inactive session cannot turn an off service into suspended capture")
        let observedCount1 = await backend.startCount()
        XCTAssertEqual(observedCount1, 0)
        controller.startFromUserAction(); controller.startFromUserAction()
        await wait { await backend.startCount() == 1 }
        XCTAssertEqual(controller.presentation.availability, .starting)
        await controller.shutdown()
        subscription.cancel()
        XCTAssertEqual(controller.presentation.availability, .disabled)
    }

    func testPermissionDenialDoesNotRetryOrProduceFrame() async {
        let backend = TestSpectrumBackend(error: .permissionDenied)
        let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        controller.startFromUserAction()
        await wait { controller.presentation.availability == .failed(.permissionDenied) }
        controller.refreshPresentation()
        XCTAssertEqual(controller.presentation.permission, .denied)
        XCTAssertNil(controller.presentation.frame)
        let observedCount2 = await backend.startCount()
        XCTAssertEqual(observedCount2, 1)
        await controller.shutdown()
    }

    func testActualFramesDistinguishSignalFromSilenceWithoutInventingPlaybackOrPermission() async throws {
        for signal in [false, true] {
            let backend = TestSpectrumBackend()
            let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
            let mailbox = await backend.mailbox
            mailbox.publish(frame(signal: signal))
            controller.startFromUserAction()
            await wait { controller.presentation.availability == .capturing }
            XCTAssertEqual(controller.presentation.playbackEvidence, signal ? .signalPresent : .silent)
            XCTAssertEqual(controller.presentation.permission, signal ? .accessEstablished : .notVerified)
            controller.stop()
            mailbox.publish(frame(signal: true, sequence: 2))
            controller.refreshPresentation()
            XCTAssertNil(controller.presentation.frame)
            XCTAssertEqual(controller.presentation.availability, .disabled)
            await controller.shutdown()
        }
    }

    func testNoFramesWatchdogStopsOnceAndFirstFrameResetsDeadline() async {
        var time = 10.0
        let backend = TestSpectrumBackend()
        let controller = AudioSpectrumController(backend: backend, now: { time }, observeSystemEvents: false)
        controller.startFromUserAction()
        await wait { await backend.startCount() == 1 }
        // Let the start task install its mailbox before advancing the synthetic clock.
        try? await Task.sleep(for: .milliseconds(30))
        let mailbox = await backend.mailbox
        time = 11.9; mailbox.publish(frame(signal: true)); controller.refreshPresentation()
        XCTAssertEqual(controller.presentation.availability, .capturing)
        time = 12.1; controller.refreshPresentation()
        XCTAssertEqual(controller.presentation.availability, .capturing)
        time = 14.0; controller.refreshPresentation(); controller.refreshPresentation()
        XCTAssertEqual(controller.presentation.availability, .failed(.noFrames))
        XCTAssertNil(controller.presentation.frame)
        await wait { await backend.stopCount() == 1 }
        await controller.shutdown()
    }

    func testStaleAsyncStartAfterDisableCannotRestoreFrame() async {
        let backend = TestSpectrumBackend(pauseStart: true)
        let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        controller.startFromUserAction()
        await wait { await backend.startCount() == 1 }
        controller.stop()
        await backend.resumeStart()
        try? await Task.sleep(for: .milliseconds(30))
        controller.refreshPresentation()
        XCTAssertEqual(controller.presentation.availability, .disabled)
        XCTAssertNil(controller.presentation.frame)
        let observedCount3 = await backend.liveGenerationCount()
        XCTAssertEqual(observedCount3, 0)
        await controller.shutdown()
    }

    func testOutputFormatChangeAndSleepSuspendWithoutAutomaticPermissionRetry() async {
        for invalidate in [false, true] {
            let backend = TestSpectrumBackend()
            let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
            let mailbox = await backend.mailbox
            mailbox.publish(frame(signal: true))
            controller.startFromUserAction()
            await wait { controller.presentation.availability == .capturing }
            if invalidate { mailbox.invalidate(); controller.refreshPresentation() } else { controller.suspend() }
            XCTAssertEqual(controller.presentation.availability, .suspended)
            XCTAssertNil(controller.presentation.frame)
            controller.refreshPresentation()
            let observedCount4 = await backend.startCount()
        XCTAssertEqual(observedCount4, 1)
            await controller.shutdown()
        }
    }

    func testShutdownWaitsForEarlierStopEvenThoughGenerationHasAdvanced() async {
        let backend = TestSpectrumBackend(pauseStop: true)
        let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        controller.startFromUserAction()
        await wait { await backend.startCount() == 1 }
        controller.stop()
        await wait { await backend.stopCount() == 1 }
        var finished = false
        let shutdown = Task { await controller.shutdown(); finished = true }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(finished)
        await backend.resumeStop()
        await shutdown.value
        XCTAssertTrue(finished)
        let observedCount5 = await backend.liveGenerationCount()
        XCTAssertEqual(observedCount5, 0)
    }

    private func frame(signal: Bool, sequence: UInt64 = 1) -> AudioSpectrumFrame {
        AudioSpectrumFrame(sequence: sequence, hostTime: 42, sampleRate: 48_000,
            bands: signal ? SIMD8(repeating: 0.5) : .zero,
            rms: signal ? 0.2 : 0, peak: signal ? 0.3 : 0, hasSignal: signal)
    }
    private func wait(_ predicate: @MainActor () async -> Bool) async {
        for _ in 0..<200 {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("audio lifecycle did not settle")
    }
}

private actor TestSpectrumBackend: AudioSpectrumCaptureBackend {
    let mailbox = AudioSpectrumMailbox()
    private var starts = 0, stops = 0
    private var generations: Set<UInt64> = []
    private let error: NativeAudioError?
    private var pauseStart: Bool
    private var pauseStop: Bool
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var stopContinuation: CheckedContinuation<Void, Never>?
    init(error: NativeAudioError? = nil, pauseStart: Bool = false, pauseStop: Bool = false) {
        self.error = error; self.pauseStart = pauseStart; self.pauseStop = pauseStop
    }
    func startCount() -> Int { starts }
    func stopCount() -> Int { stops }
    func liveGenerationCount() -> Int { generations.count }
    func start(generation: UInt64) async throws -> AudioSpectrumMailbox {
        starts += 1
        if pauseStart { await withCheckedContinuation { startContinuation = $0 } }
        if let error { throw error }
        generations.insert(generation)
        return mailbox
    }
    func stop(generation: UInt64) async throws {
        guard generations.contains(generation) else { return }
        stops += 1
        if pauseStop { await withCheckedContinuation { stopContinuation = $0 } }
        generations.remove(generation)
    }
    func resumeStart() { pauseStart = false; startContinuation?.resume(); startContinuation = nil }
    func resumeStop() { pauseStop = false; stopContinuation?.resume(); stopContinuation = nil }
}
