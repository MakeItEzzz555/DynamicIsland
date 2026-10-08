import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland
@testable import LibrariesNative
import AgentBridgeShared

private struct MetalSendMotionEnvironmentProbe: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let changed: (Bool) -> Void

    var body: some View {
        Color.clear
            .onAppear { changed(reduceMotion) }
            .onChange(of: reduceMotion) { _, value in changed(value) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

@MainActor
final class MetalSendInteractionTests: XCTestCase {
    func testEnabledNativeHostUnpausesClockAndUnmountPausesIt() async throws {
        _ = NSApplication.shared
        let id = AgentSessionInstanceID(sessionID: .init(provider: .codex, nativeID: "metal-visible-host"), generation: .init(rawValue: 1))
        let model = AgentMetalModelStore.model(for: id)
        model.setPaused(true, now: Date().timeIntervalSinceReferenceDate)
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 180, height: 180)
        let window = NSWindow(contentRect: CGRect(x: screenFrame.midX - 50, y: screenFrame.midY - 50, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        defer { window.contentView = nil; window.close() }
        var reduceMotion: Bool?
        window.contentView = NSHostingView(rootView: MetalSendButton(configuration: .init(), isEnabled: true, sessionID: id) {}
            .frame(width: 100, height: 100)
            .environment(\.rightWorkspacePageIsActive, true)
            .background { MetalSendMotionEnvironmentProbe { reduceMotion = $0 } })
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()

        func descendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
            if let value = view as? T { return value }
            for child in view.subviews { if let value = descendant(in: child, as: type) { return value } }
            return nil
        }
        func visibilityProbe() -> NativeVisualVisibility.Probe? {
            window.contentView.flatMap { descendant(in: $0, as: NativeVisualVisibility.Probe.self) }
        }
        func hostIsVisible() -> Bool {
            guard let probe = visibilityProbe() else { return false }
            return window.isVisible && window.occlusionState.contains(.visible) &&
                !probe.isHiddenOrHasHiddenAncestor && !probe.visibleRect.isEmpty
        }
        func diagnostics() -> String {
            let probe = visibilityProbe()
            return "appActive=\(NSApp.isActive) screens=\(NSScreen.screens.count) windowVisible=\(window.isVisible) " +
                "occlusionVisible=\(window.occlusionState.contains(.visible)) occlusionRaw=\(window.occlusionState.rawValue) " +
                "windowFrame=\(window.frame) probeFrame=\(String(describing: probe?.frame)) " +
                "probeVisibleRect=\(String(describing: probe?.visibleRect)) hidden=\(String(describing: probe?.isHiddenOrHasHiddenAncestor)) " +
                "swiftUIReduceMotion=\(String(describing: reduceMotion)) systemReduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)"
        }

        let visibilityDeadline = ContinuousClock.now + .seconds(3)
        while (!hostIsVisible() || reduceMotion == nil), ContinuousClock.now < visibilityDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(hostIsVisible(), "The live animation fixture requires an actually visible native host: \(diagnostics())")
        guard hostIsVisible() else { return }
        XCTAssertNotNil(reduceMotion, "The hosted motion environment must be observed: \(diagnostics())")
        guard let reduceMotion else { return }
        func advancing() -> Bool {
            let now = Date().timeIntervalSinceReferenceDate
            return model.time(now: now + 1) - model.time(now: now) > 0.9
        }

        if reduceMotion {
            XCTAssertFalse(advancing(), "The inherited system Reduce Motion setting must pause Send: \(diagnostics())")
        } else {
            let deadline = ContinuousClock.now + .seconds(3)
            while !advancing(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(advancing(), "A visible enabled Send must not remain paused: \(diagnostics())")
            let renderer = try XCTUnwrap(window.contentView.flatMap { descendant(in: $0, as: NativeMetalSheet.Surface.self) })
            let firstTime = renderer.parameters?.uniforms.first?.z
            let redrawDeadline = ContinuousClock.now + .seconds(3)
            while renderer.parameters?.uniforms.first?.z == firstTime, ContinuousClock.now < redrawDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNotEqual(renderer.parameters?.uniforms.first?.z, firstTime, "Visible Timeline must deliver new material frames: \(diagnostics())")
        }
        window.contentView = nil
        let cleanupDeadline = ContinuousClock.now + .seconds(3)
        while advancing(), ContinuousClock.now < cleanupDeadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(advancing(), "Detached Send must stop its decorative clock")
    }

    func testVisibleSendTargetClicksIncludingPaddingAndDisabledFallback() async throws {
        var sent = 0
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        func host(enabled: Bool, metal: Bool) {
            var config = MetalSendConfiguration()
            config.enabled = metal
            config.animationEnabled = false
            window.contentView = NSHostingView(rootView: MetalSendButton(configuration: config, isEnabled: enabled) { sent += 1 }
                .frame(width: 100, height: 100))
            window.makeKeyAndOrderFront(nil)
            window.contentView?.layoutSubtreeIfNeeded()
        }

        func click(_ point: CGPoint) async throws {
            for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0))
                window.sendEvent(event)
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        host(enabled: true, metal: true)
        try await Task.sleep(for: .milliseconds(80))
        // Center, four rim points, and four points in the padded 34pt target.
        let points = [CGPoint(x: 50, y: 50), CGPoint(x: 36, y: 50), CGPoint(x: 64, y: 50), CGPoint(x: 50, y: 36), CGPoint(x: 50, y: 64), CGPoint(x: 34, y: 34), CGPoint(x: 66, y: 34), CGPoint(x: 34, y: 66), CGPoint(x: 66, y: 66)]
        for (index, point) in points.enumerated() {
            try await click(point)
            XCTAssertEqual(sent, index + 1, "Dead hit zone at \(point)")
        }
        host(enabled: false, metal: true)
        try await click(CGPoint(x: 50, y: 50))
        XCTAssertEqual(sent, points.count)
        host(enabled: true, metal: false)
        try await click(CGPoint(x: 50, y: 50))
        XCTAssertEqual(sent, points.count + 1)
    }
}
