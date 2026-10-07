import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland
@testable import LibrariesNative
import AgentBridgeShared

@MainActor
final class MetalSendInteractionTests: XCTestCase {
    func testEnabledNativeHostUnpausesClockAndUnmountPausesIt() async throws {
        let id = AgentSessionInstanceID(sessionID: .init(provider: .codex, nativeID: "metal-visible-host"), generation: .init(rawValue: 1))
        let model = AgentMetalModelStore.model(for: id)
        model.setPaused(true, now: Date().timeIntervalSinceReferenceDate)
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: MetalSendButton(configuration: .init(), isEnabled: true, sessionID: id) {}.frame(width: 100, height: 100))
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        func advancing() -> Bool {
            let now = Date().timeIntervalSinceReferenceDate
            return model.time(now: now + 1) - model.time(now: now) > 0.9
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while !advancing(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(advancing(), "A visible enabled Send must not remain paused")
        func surface(in view: NSView) -> NativeMetalSheet.Surface? {
            if let surface = view as? NativeMetalSheet.Surface { return surface }
            for child in view.subviews { if let value = surface(in: child) { return value } }
            return nil
        }
        let renderer = try XCTUnwrap(window.contentView.flatMap(surface(in:)))
        let firstTime = renderer.parameters?.uniforms.first?.z
        let redrawDeadline = ContinuousClock.now + .seconds(3)
        while renderer.parameters?.uniforms.first?.z == firstTime, ContinuousClock.now < redrawDeadline { await Task.yield() }
        XCTAssertNotEqual(renderer.parameters?.uniforms.first?.z, firstTime, "Visible Timeline must deliver new material frames")
        window.contentView = nil
        let cleanupDeadline = ContinuousClock.now + .seconds(3)
        while advancing(), ContinuousClock.now < cleanupDeadline { await Task.yield() }
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
