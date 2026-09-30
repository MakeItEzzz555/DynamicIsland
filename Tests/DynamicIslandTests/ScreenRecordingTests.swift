import AVFoundation
import CoreGraphics
import XCTest
@testable import DynamicIsland

final class ScreenRecordingTests: XCTestCase {
    func testStateMachineRejectsInvalidTransitionsAndAllowsOneFinalize() {
        var machine = ScreenRecordingStateMachine()

        XCTAssertFalse(machine.pause())
        XCTAssertFalse(machine.resume())
        XCTAssertFalse(machine.beginFinalizing())

        XCTAssertTrue(machine.beginPreparing())
        XCTAssertEqual(machine.phase, .preparing)
        XCTAssertFalse(machine.beginPreparing())
        XCTAssertFalse(machine.pause())

        XCTAssertTrue(machine.didStart())
        XCTAssertEqual(machine.phase, .recording)
        XCTAssertFalse(machine.didStart())

        XCTAssertTrue(machine.pause())
        XCTAssertEqual(machine.phase, .paused)
        XCTAssertFalse(machine.pause())

        XCTAssertTrue(machine.resume())
        XCTAssertEqual(machine.phase, .recording)
        XCTAssertFalse(machine.resume())

        XCTAssertTrue(machine.beginFinalizing())
        XCTAssertEqual(machine.phase, .finalizing)
        XCTAssertFalse(machine.beginFinalizing())
        XCTAssertFalse(machine.pause())
        XCTAssertFalse(machine.resume())

        XCTAssertTrue(machine.didSave())
        XCTAssertEqual(machine.phase, .saved)
        XCTAssertFalse(machine.didSave())

        XCTAssertTrue(machine.beginPreparing(), "saved recordings can begin a new session")
    }

    func testTimelineClockRemovesPausedSourceTime() throws {
        var clock = ScreenRecordingTimelineClock()

        XCTAssertEqual(try XCTUnwrap(clock.adjustedTime(sourceTime: 10, establishesOrigin: true)), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(clock.adjustedTime(sourceTime: 11, establishesOrigin: true)), 1, accuracy: 0.0001)

        clock.pause()
        XCTAssertNil(clock.adjustedTime(sourceTime: 12, establishesOrigin: true))
        XCTAssertNil(clock.adjustedTime(sourceTime: 14, establishesOrigin: true))

        clock.resume()
        let resumed = try XCTUnwrap(clock.adjustedTime(sourceTime: 15, establishesOrigin: true))
        XCTAssertEqual(resumed, 1, accuracy: 0.0001, "four paused source seconds are removed")

        let later = try XCTUnwrap(clock.adjustedTime(sourceTime: 16.5, establishesOrigin: true))
        XCTAssertEqual(later, 2.5, accuracy: 0.0001)
        XCTAssertEqual(clock.pausedDuration, 4, accuracy: 0.0001)
    }

    func testTimelineClockRequiresVideoSampleToEstablishOrigin() {
        var clock = ScreenRecordingTimelineClock()
        XCTAssertNil(clock.adjustedTime(sourceTime: 3, establishesOrigin: false))
        XCTAssertNil(clock.sourceOrigin)

        XCTAssertEqual(try! XCTUnwrap(clock.adjustedTime(sourceTime: 4, establishesOrigin: true)), 0, accuracy: 0.0001)
        XCTAssertEqual(clock.sourceOrigin, 4)
    }

    func testFormattingUsesRecordedTimelineDuration() {
        XCTAssertEqual(ScreenRecordingController.formatDuration(0), "00:00")
        XCTAssertEqual(ScreenRecordingController.formatDuration(9.9), "00:09")
        XCTAssertEqual(ScreenRecordingController.formatDuration(61.2), "01:01")
        XCTAssertEqual(ScreenRecordingController.formatDuration(3661.9), "1:01:01")
    }

    func testOldRightWorkspaceConfigurationAppendsScreenRecordingTool() {
        let legacyTools = RightWorkspaceTool.allCases.filter { $0 != .screenRecording }
        var legacy = RightWorkspaceConfiguration.default
        legacy.toolOrder = legacyTools

        let normalized = legacy.normalized
        XCTAssertEqual(normalized.toolOrder.filter { $0 == .screenRecording }.count, 1)
        XCTAssertEqual(normalized.toolOrder.last, .screenRecording)
        XCTAssertTrue(normalized.visibleTools.contains(.screenRecording))
    }

    func testScreenRecordingCollapsedProfileAllocatesExtraHeightWithoutNewPersistentState() {
        let profile = CollapsedPresentationProfile.screenRecording
        XCTAssertEqual(profile.kind, .screenRecording)
        XCTAssertEqual(profile.contentProfile, .screenRecording)
        XCTAssertGreaterThan(profile.heightDelta, 0)
        XCTAssertGreaterThan(profile.widthDelta, 0)
        XCTAssertEqual(profile.glowStrength, 0)
    }

    func testAreaSourceRectTopLeftConversionMath() {
        let displayHeight: CGFloat = 982
        let appKitRect = CGRect(x: 100, y: 200, width: 500, height: 300)
        let sourceRect = ScreenRecordingAreaGeometry.sourceRect(
            fromAppKitLocalRect: appKitRect,
            displayHeight: displayHeight
        )

        XCTAssertEqual(sourceRect.origin.x, 100, accuracy: 0.0001)
        XCTAssertEqual(sourceRect.origin.y, 482, accuracy: 0.0001)
        XCTAssertEqual(sourceRect.width, 500, accuracy: 0.0001)
        XCTAssertEqual(sourceRect.height, 300, accuracy: 0.0001)
    }
}

final class ScreenRecordingLiveTests: XCTestCase {
    @MainActor
    func testRealDisplayRecordingPauseResumeAndValidatedOutput() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING=1 for real ScreenCaptureKit acceptance")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Screen Recording permission is not granted to the test process")
        }

        let liveActivities = LiveActivityStore()
        let capabilities = IslandCapabilityRegistry()
        let controller = ScreenRecordingController(
            liveActivities: liveActivities,
            capabilities: capabilities
        )
        controller.options.capturesSystemAudio = false
        controller.options.capturesMicrophone = false
        controller.options.showsCursor = true
        controller.options.excludesDynamicIsland = true

        await controller.prepareTargets(requestPermission: false)
        guard let display = controller.displays.first else {
            throw XCTSkip("ScreenCaptureKit exposed no shareable display: \(controller.statusText)")
        }

        await controller.startDisplay(display.id)
        try await waitUntil(timeout: 4) {
            controller.phase == .recording
        }
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertTrue(liveActivities.activities.contains { $0.kind == .screenRecording })

        try await Task.sleep(for: .milliseconds(700))
        controller.pause()
        XCTAssertEqual(controller.phase, .paused)
        let pausedDuration = controller.recordedDuration
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.recordedDuration, pausedDuration, accuracy: 0.20)

        controller.resume()
        XCTAssertEqual(controller.phase, .recording)
        try await Task.sleep(for: .milliseconds(700))

        await controller.stopAndSave()
        XCTAssertEqual(controller.phase, .saved, "Recorder status: \(controller.statusText)")
        let url = try XCTUnwrap(controller.lastSavedURL, "Recorder status: \(controller.statusText)")
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertTrue(seconds.isFinite)
        XCTAssertGreaterThan(seconds, 0.5)
        XCTAssertLessThan(seconds, 3.0, "paused wall-clock time should not be recorded")
        XCTAssertFalse(liveActivities.activities.contains { $0.kind == .screenRecording })
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for condition")
    }
}
