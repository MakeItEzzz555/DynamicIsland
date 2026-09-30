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
