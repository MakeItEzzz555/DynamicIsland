import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class AudioWidgetIntegrationTests: XCTestCase {
    func testCodexMailboxChangesClaudeProductionBarsWithoutStartingFromMount() async throws {
        _ = NSApplication.shared
        let backend = AudioWidgetFixtureBackend()
        let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        let host = NSHostingView(rootView: AudioVisualizerView(isPlaying: true, variant: .expanded)
            .environment(\.liveSpectrum, controller))
        host.frame = CGRect(x: 0, y: 0, width: 76, height: 28)
        // On screen: SwiftUI does not commit updates for a window placed off
        // every display (headless CI), which froze both rasters.
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSPanel(contentRect: CGRect(x: visible.minX + 8, y: visible.minY + 8, width: 76, height: 28),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        await settleRender()
        let starts = await backend.starts
        XCTAssertEqual(starts, 0)
        controller.startFromUserAction()
        backend.mailbox.publish(frame(0.1, sequence: 1))
        await wait { controller.presentation.availability == .capturing }
        let low = try raster(host)
        backend.mailbox.publish(frame(0.95, sequence: 2))
        controller.refreshPresentation()
        await settleRender()
        let high = try raster(host)
        XCTAssertNotEqual(low, high, "one backend's measured spectrum drives Claude's existing renderer")
        controller.stop()
        XCTAssertNil(controller.presentation.frame)
        await controller.shutdown()
    }

    func testPreviewRemainsSyntheticWithInjectedLiveProvider() async throws {
        _ = NSApplication.shared
        let backend = AudioWidgetFixtureBackend()
        let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        let host = NSHostingView(rootView: AudioVisualizerView(isPlaying: true, variant: .expanded)
            .environment(\.liveSpectrum, controller)
            .environment(\.isSettingsPreview, true)
            .environment(\.settingsPreviewReduceMotion, true))
        host.frame = CGRect(x: 0, y: 0, width: 76, height: 28)
        let window = NSPanel(contentRect: CGRect(x: -5000, y: -5000, width: 76, height: 28),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        await settleRender()
        let before = try raster(host)
        controller.startFromUserAction()
        backend.mailbox.publish(frame(0.95, sequence: 1))
        await wait { controller.presentation.availability == .capturing }
        XCTAssertEqual(before, try raster(host))
        await controller.shutdown()
    }

    private func frame(_ level: Float, sequence: UInt64) -> AudioSpectrumFrame {
        .init(sequence: sequence, hostTime: 1, sampleRate: 48_000, bands: SIMD8(repeating: level),
            rms: level, peak: level, hasSignal: true)
    }
    private func raster(_ host: NSView) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
    private func settleRender() async { try? await Task.sleep(for: .milliseconds(120)) }
    private func wait(_ predicate: () -> Bool) async {
        for _ in 0..<200 {
            if predicate() { await settleRender(); return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("spectrum fixture did not settle")
    }
}

private actor AudioWidgetFixtureBackend: AudioSpectrumCaptureBackend {
    let mailbox = AudioSpectrumMailbox()
    private(set) var starts = 0
    private var active: UInt64?
    func start(generation: UInt64) -> AudioSpectrumMailbox { starts += 1; active = generation; return mailbox }
    func stop(generation: UInt64) { if active == generation { active = nil } }
}
