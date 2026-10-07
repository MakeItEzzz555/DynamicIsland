import AppKit
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

        clock.pause(at: 11)
        XCTAssertNil(clock.adjustedTime(sourceTime: 12, establishesOrigin: true))
        XCTAssertNil(clock.adjustedTime(sourceTime: 14, establishesOrigin: true))

        clock.resume(at: 15)
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

    // MARK: - Static-screen timeline (runtime regression: 3.5 s -> 0.017 s movie)
    //
    // ScreenCaptureKit only delivers complete frames when the screen changes,
    // and its PTS is on the host clock. The recording session timeline must
    // follow the host clock at pause/resume/stop, not the last changed frame.

    func testStaticRecordingSessionEndsAtTheStopTimeNotTheLastFrame() throws {
        var clock = ScreenRecordingTimelineClock()
        XCTAssertEqual(try XCTUnwrap(clock.adjustedTime(sourceTime: 100, establishesOrigin: true)), 0, accuracy: 0.0001)
        // No further complete frames: the screen is static until stop.
        let end = try XCTUnwrap(clock.sessionEndTime(at: 103.5, lastVideoEnd: 1.0 / 60.0))
        XCTAssertEqual(end, 3.5, accuracy: 0.0001)
        XCTAssertEqual(clock.activeDuration(at: 103.5), 3.5, accuracy: 0.0001)
    }

    func testPauseDuringStaticPeriodIsMeasuredAtTheControlTimes() throws {
        var clock = ScreenRecordingTimelineClock()
        _ = clock.adjustedTime(sourceTime: 100, establishesOrigin: true)
        clock.pause(at: 102)          // 2 s static recorded
        XCTAssertEqual(clock.activeDuration(at: 103.5), 2, accuracy: 0.0001, "frozen while paused")
        clock.resume(at: 104)         // 2 s paused
        let end = try XCTUnwrap(clock.sessionEndTime(at: 106, lastVideoEnd: 1.0 / 60.0))  // 2 s static
        XCTAssertEqual(end, 4, accuracy: 0.0001, "record 2 + pause 2 + record 2 = 4 s, not 6 and not 0")
        XCTAssertEqual(clock.pausedDuration, 2, accuracy: 0.0001)
    }

    func testRecordPauseResumeWithChangingFramesExcludesOnlyThePause() throws {
        var clock = ScreenRecordingTimelineClock()
        _ = clock.adjustedTime(sourceTime: 50, establishesOrigin: true)
        _ = clock.adjustedTime(sourceTime: 51.9, establishesOrigin: true)
        clock.pause(at: 52)
        clock.resume(at: 55)
        let resumed = try XCTUnwrap(clock.adjustedTime(sourceTime: 55.5, establishesOrigin: true))
        XCTAssertEqual(resumed, 2.5, accuracy: 0.0001)
        let end = try XCTUnwrap(clock.sessionEndTime(at: 57, lastVideoEnd: resumed + 1.0 / 60.0))
        XCTAssertEqual(end, 4, accuracy: 0.0001, "record 2 + pause 3 + record 2 = 4 s")
    }

    func testFramesCapturedDuringThePauseAreDroppedEvenWhenDeliveredLate() throws {
        var clock = ScreenRecordingTimelineClock()
        _ = clock.adjustedTime(sourceTime: 10, establishesOrigin: true)
        clock.pause(at: 12)
        // Captured before the pause but delivered after it: kept.
        XCTAssertEqual(try XCTUnwrap(clock.adjustedTime(sourceTime: 11.99, establishesOrigin: true)), 1.99, accuracy: 0.0001)
        XCTAssertNil(clock.adjustedTime(sourceTime: 12.5, establishesOrigin: true))
        clock.resume(at: 14)
        // Captured during the pause, delivered after resume: dropped.
        XCTAssertNil(clock.adjustedTime(sourceTime: 13.9, establishesOrigin: true))
        XCTAssertEqual(try XCTUnwrap(clock.adjustedTime(sourceTime: 14, establishesOrigin: true)), 2, accuracy: 0.0001)
    }

    func testSessionEndNeverPrecedesTheLastAppendedVideoFrame() throws {
        var clock = ScreenRecordingTimelineClock()
        _ = clock.adjustedTime(sourceTime: 0, establishesOrigin: true)
        let lastVideoEnd = 2.0 + 1.0 / 60.0
        let end = try XCTUnwrap(clock.sessionEndTime(at: 2.0, lastVideoEnd: lastVideoEnd))
        XCTAssertGreaterThanOrEqual(end, lastVideoEnd, "stop racing the last frame must not trim it")
    }

    func testNoVideoFrameMeansNoSessionEnd() {
        var clock = ScreenRecordingTimelineClock()
        XCTAssertNil(clock.adjustedTime(sourceTime: 5, establishesOrigin: false))
        XCTAssertNil(clock.sessionEndTime(at: 9, lastVideoEnd: 0), "no video must still fail truthfully")
        XCTAssertEqual(clock.activeDuration(at: 9), 0)
    }

    func testStoppingWhilePausedEndsAtThePauseBoundary() throws {
        var clock = ScreenRecordingTimelineClock()
        _ = clock.adjustedTime(sourceTime: 20, establishesOrigin: true)
        clock.pause(at: 23)
        let end = try XCTUnwrap(clock.sessionEndTime(at: 30, lastVideoEnd: 1.0 / 60.0))
        XCTAssertEqual(end, 3, accuracy: 0.0001)
    }

    func testSamplesCapturedAfterTheStopRequestAreNotRecorded() throws {
        var clock = ScreenRecordingTimelineClock()
        _ = clock.adjustedTime(sourceTime: 0, establishesOrigin: true)
        clock.stop(at: 3)
        // In flight from before Stop: kept.
        XCTAssertNotNil(clock.adjustedTime(sourceTime: 2.99, establishesOrigin: true))
        // Captured during stopCapture's round trip: not part of the movie.
        XCTAssertNil(clock.adjustedTime(sourceTime: 3.1, establishesOrigin: true))
        XCTAssertEqual(try XCTUnwrap(clock.sessionEndTime(at: 3.4, lastVideoEnd: 2.99 + 1.0 / 60.0)), 3.0067, accuracy: 0.001)
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

    // MARK: - Setup presentation (runtime regression: tile click showed nothing)
    //
    // The setup was a SwiftUI .sheet owned by the tile's @State inside the
    // island panel. AppKit attached it over the island (black on black),
    // pushed the top-pinned panel 35pt off the screen top, and any island
    // collapse unmounted the tile and dismissed the sheet. Presentation is
    // now owned by ScreenRecordingSetupPresenter outside the island tree.

    @MainActor
    func testConstructingThePresenterCreatesNoSurface() {
        var created = 0
        let presenter = ScreenRecordingSetupPresenter(makeSurface: {
            created += 1
            return FakeSetupSurface()
        })
        XCTAssertFalse(presenter.isPresented)
        XCTAssertEqual(created, 0, "no window (and no permission work) before the tile is clicked")
    }

    @MainActor
    func testRepeatedTileClicksKeepExactlyOneVisibleSetupSurface() throws {
        var surfaces: [FakeSetupSurface] = []
        let presenter = ScreenRecordingSetupPresenter(makeSurface: {
            let surface = FakeSetupSurface()
            surfaces.append(surface)
            return surface
        })
        presenter.present()
        presenter.present()
        presenter.present()
        XCTAssertTrue(presenter.isPresented)
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces.filter(\.isVisible).count, 1)
    }

    @MainActor
    func testCloseThenReopenShowsTheSetupAgain() throws {
        var surfaces: [FakeSetupSurface] = []
        let presenter = ScreenRecordingSetupPresenter(makeSurface: {
            let surface = FakeSetupSurface()
            surfaces.append(surface)
            return surface
        })
        presenter.present()
        presenter.dismiss()
        XCTAssertFalse(presenter.isPresented)
        XCTAssertFalse(try XCTUnwrap(surfaces.first).isVisible)

        presenter.present()
        XCTAssertTrue(presenter.isPresented)
        XCTAssertEqual(surfaces.filter(\.isVisible).count, 1)
        XCTAssertEqual(surfaces.count, 1, "the owned surface is reused, never orphaned")
    }

    @MainActor
    func testClosingTheSurfaceDirectlyClearsPresentationState() throws {
        let surface = FakeSetupSurface()
        let presenter = ScreenRecordingSetupPresenter(makeSurface: { surface })
        presenter.present()
        surface.simulateUserClose()
        XCTAssertFalse(presenter.isPresented)
        presenter.present()
        XCTAssertTrue(surface.isVisible, "reopen after a user close (Esc / close button)")
    }

    @MainActor
    func testSetupSurvivesIslandCollapseAndRefresh() {
        let surface = FakeSetupSurface()
        var anchor: ScreenRecordingSetupAnchor? = ScreenRecordingSetupAnchor(
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            islandFrame: CGRect(x: 376, y: 696, width: 760, height: 286)
        )
        let presenter = ScreenRecordingSetupPresenter(makeSurface: { surface }, anchorProvider: { anchor })
        presenter.present()
        // The island collapses / re-renders / its presentation generation
        // changes: nothing in the island tree owns the setup any more.
        anchor = nil
        XCTAssertTrue(presenter.isPresented)
        XCTAssertTrue(surface.isVisible)
        // Clicking the tile again after the refresh only brings it forward.
        presenter.present()
        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.shownFrames.count, 2)
    }

    func testSetupPlacementHangsBelowTheIslandAndStaysOnScreen() {
        let fixtures: [(CGRect, CGRect)] = [
            (CGRect(x: 0, y: 0, width: 1512, height: 950), CGRect(x: 376, y: 696, width: 760, height: 286)),
            (CGRect(x: 0, y: 0, width: 1280, height: 695), CGRect(x: 260, y: 425, width: 760, height: 260)),
            (CGRect(x: 1512, y: 0, width: 3840, height: 2135), CGRect(x: 3052, y: 1875, width: 760, height: 260)),
            (CGRect(x: 0, y: 0, width: 5120, height: 2855), CGRect(x: 2180, y: 2594, width: 760, height: 286))
        ]
        let size = CGSize(width: 440, height: 380)
        for (visible, island) in fixtures {
            let frame = ScreenRecordingSetupPlacement.frame(
                contentSize: size,
                anchor: ScreenRecordingSetupAnchor(screenVisibleFrame: visible, islandFrame: island)
            )
            XCTAssertEqual(frame.size, size)
            XCTAssertEqual(frame.midX, island.midX, accuracy: 1)
            XCTAssertLessThanOrEqual(frame.maxY, island.minY, "below the island, never over it: \(visible)")
            XCTAssertTrue(visible.contains(frame), "on the island's screen: \(visible) \(frame)")
        }
    }

    func testSetupPlacementClampsInsideShortScreens() {
        let visible = CGRect(x: 0, y: 0, width: 1024, height: 600)
        let island = CGRect(x: 132, y: 340, width: 760, height: 260)
        let frame = ScreenRecordingSetupPlacement.frame(
            contentSize: CGSize(width: 440, height: 420),
            anchor: ScreenRecordingSetupAnchor(screenVisibleFrame: visible, islandFrame: island)
        )
        XCTAssertTrue(visible.contains(frame))
    }

    /// Real AppKit lifecycle of the production surface: a visible panel above
    /// the island's status-bar level, hosting the production setup view,
    /// that closes cleanly and reopens without duplicating windows.
    @MainActor
    func testProductionSetupPanelIsVisibleAboveTheIslandAndClosesCleanly() throws {
        _ = NSApplication.shared
        let controller = ScreenRecordingController(
            liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry()
        )
        let presenter = ScreenRecordingSetupPresenter.production(controller: controller, anchorProvider: {
            let screen = try? XCTUnwrap(NSScreen.main)
            guard let screen else { return nil }
            let visible = screen.visibleFrame
            return ScreenRecordingSetupAnchor(
                screenVisibleFrame: visible,
                islandFrame: CGRect(x: visible.midX - 380, y: screen.frame.maxY - 260, width: 760, height: 260)
            )
        })
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        presenter.present()
        presenter.present()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let created = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) }
        XCTAssertEqual(created.count, 1, "exactly one recorder surface")
        let panel = try XCTUnwrap(created.first)
        XCTAssertTrue(panel.isVisible)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue)
        XCTAssertNil(panel.sheetParent, "not an attached sheet of the island panel")
        XCTAssertGreaterThan(panel.frame.width, 200)
        XCTAssertGreaterThan(panel.frame.height, 120)

        presenter.dismiss()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(panel.isVisible)

        presenter.present()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) }.count, 1)
        presenter.dismiss()
    }
}

@MainActor
private final class FakeSetupSurface: ScreenRecordingSetupSurface {
    private(set) var isVisible = false
    private(set) var shownFrames: [CGRect] = []
    var onUserClose: (() -> Void)?
    var fittingSize: CGSize { CGSize(width: 440, height: 380) }

    func show(frame: CGRect) {
        shownFrames.append(frame)
        isVisible = true
    }

    func close() {
        isVisible = false
    }

    func simulateUserClose() {
        isVisible = false
        onUserClose?()
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

    // MARK: - Static timeline, Window and Area (real ScreenCaptureKit)
    //
    // A test-owned, never-changing window is the static source. The movie must
    // last as long as the active recording (pauses excluded), not end at the
    // last changed frame (the 3.5 s -> 0.017 s runtime regression).

    /// Allowed deviation between asset duration and active recorded time:
    /// first-frame latency plus the Stop round trip.
    private let durationTolerance: TimeInterval = 0.35

    @MainActor
    func testRealStaticWindowRecordingKeepsItsActiveDuration() async throws {
        let (controller, window) = try await makeLiveControllerWithStaticWindow()
        defer { window.orderOut(nil) }

        await controller.startWindow(CGWindowID(window.windowNumber))
        try await waitUntil(timeout: 4) { controller.phase == .recording }
        try await Task.sleep(for: .seconds(3))
        XCTAssertGreaterThan(controller.recordedDuration, 2.4, "UI timeline keeps advancing on a static screen")
        await controller.stopAndSave()

        let movie = try await validatedMovie(controller)
        XCTAssertEqual(movie.duration, 3.0, accuracy: durationTolerance, "static 3 s must not collapse to one frame")
        XCTAssertEqual(movie.videoTrackDuration, movie.duration, accuracy: 0.05)
    }

    @MainActor
    func testRealStaticWindowPauseResumeExcludesOnlyThePause() async throws {
        let (controller, window) = try await makeLiveControllerWithStaticWindow()
        defer { window.orderOut(nil) }

        await controller.startWindow(CGWindowID(window.windowNumber))
        try await waitUntil(timeout: 4) { controller.phase == .recording }
        try await Task.sleep(for: .seconds(1.2))
        controller.pause()
        try await Task.sleep(for: .seconds(1.2))
        controller.resume()
        try await Task.sleep(for: .seconds(1.2))
        await controller.stopAndSave()

        let movie = try await validatedMovie(controller)
        XCTAssertEqual(movie.duration, 2.4, accuracy: durationTolerance, "record 1.2 + pause 1.2 + record 1.2 = 2.4 s, not 3.6 and not ~0")
    }

    @MainActor
    func testRealAreaRecordingCropsToTheSelectedRegion() async throws {
        let (controller, window) = try await makeLiveControllerWithStaticWindow()
        defer { window.orderOut(nil) }
        let screen = try XCTUnwrap(window.screen)
        let displayID = try XCTUnwrap(ScreenRecordingController.displayID(for: screen))
        let area = CGRect(
            x: window.frame.minX - screen.frame.minX,
            y: screen.frame.maxY - window.frame.maxY,
            width: window.frame.width,
            height: window.frame.height
        )

        await controller.startArea(displayID: displayID, sourceRect: area)
        try await waitUntil(timeout: 4) { controller.phase == .recording }
        try await Task.sleep(for: .seconds(2))
        await controller.stopAndSave()

        let movie = try await validatedMovie(controller)
        XCTAssertEqual(movie.duration, 2.0, accuracy: durationTolerance)
        XCTAssertEqual(movie.size.width, area.width * screen.backingScaleFactor, accuracy: 2)
        XCTAssertEqual(movie.size.height, area.height * screen.backingScaleFactor, accuracy: 2)
    }

    @MainActor
    func testRealDisplayRecordingWithSystemAudioProducesAnAudioTrack() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING=1 for real ScreenCaptureKit acceptance")
        }
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("Screen Recording permission not granted") }
        let controller = ScreenRecordingController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry())
        controller.options.capturesSystemAudio = true
        controller.options.capturesMicrophone = false
        await controller.prepareTargets(requestPermission: false)
        let display = try XCTUnwrap(controller.displays.first)

        await controller.startDisplay(display.id)
        try await waitUntil(timeout: 4) { controller.phase == .recording }
        // Real system output while recording (a bundled system sound).
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", "0.15", "/System/Library/Sounds/Glass.aiff"]
        try player.run()
        try await Task.sleep(for: .seconds(2))
        await controller.stopAndSave()

        let movie = try await validatedMovie(controller)
        XCTAssertGreaterThanOrEqual(movie.audioTracks, 1, "system audio track")
        XCTAssertGreaterThan(movie.audioSamples, 0, "system audio samples were written")
        XCTAssertEqual(movie.duration, 2.0, accuracy: 0.6)
    }

    @MainActor
    private func makeLiveControllerWithStaticWindow() async throws -> (ScreenRecordingController, NSWindow) {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING=1 for real ScreenCaptureKit acceptance")
        }
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("Screen Recording permission not granted") }
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 120, y: 160, width: 480, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.80, alpha: 1)
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(600))

        let controller = ScreenRecordingController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry())
        controller.options.capturesSystemAudio = false
        controller.options.capturesMicrophone = false
        controller.options.showsCursor = false
        controller.options.excludesDynamicIsland = false
        await controller.prepareTargets(requestPermission: false)
        return (controller, window)
    }

    private struct ValidatedMovie {
        let duration: TimeInterval
        let videoTrackDuration: TimeInterval
        let size: CGSize
        let audioTracks: Int
        let audioSamples: Int
    }

    @MainActor
    private func validatedMovie(
        _ controller: ScreenRecordingController,
        name: String = #function
    ) async throws -> ValidatedMovie {
        XCTAssertEqual(controller.phase, .saved, "Recorder status: \(controller.statusText)")
        let url = try XCTUnwrap(controller.lastSavedURL, "Recorder status: \(controller.statusText)")
        defer { try? FileManager.default.removeItem(at: url) }   // test-owned output only
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first, "video track")
        let audio = try await asset.loadTracks(withMediaType: .audio)
        var audioSamples = 0
        if let track = audio.first {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            reader.startReading()
            while let buffer = output.copyNextSampleBuffer() { audioSamples += CMSampleBufferGetNumSamples(buffer) }
        }
        let movie = ValidatedMovie(
            duration: CMTimeGetSeconds(try await asset.load(.duration)),
            videoTrackDuration: CMTimeGetSeconds(try await video.load(.timeRange).duration),
            size: try await video.load(.naturalSize),
            audioTracks: audio.count,
            audioSamples: audioSamples
        )
        print("[ScreenRecordingLive] \(name): duration=\(movie.duration) video=\(movie.videoTrackDuration) size=\(movie.size) audioTracks=\(movie.audioTracks) audioSamples=\(movie.audioSamples)")
        return movie
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
