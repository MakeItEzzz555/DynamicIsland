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
        // XCTest does not run NSApplication's normal launch sequence. Finish
        // AppKit setup before requiring a live window's occlusion updates.
        NSApplication.shared.finishLaunching()
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

    /// Real hosted Send: pointer moves at each edge bend the rim toward that
    /// edge (y-down SwiftUI hover mapped onto the y-up bend), the silhouette
    /// visibly changes, and leaving springs the rim back to rest.
    func testHoverBendsTheRimTowardEachEdgeAndReturnsToRest() async throws {
        NSApplication.shared.finishLaunching()
        let id = AgentSessionInstanceID(sessionID: .init(provider: .codex, nativeID: "metal-bend-\(UUID())"), generation: .init(rawValue: 1))
        let model = AgentMetalModelStore.model(for: id)
        var config = MetalSendConfiguration()
        config.glowEnabled = false // measure the outline itself, not the halo
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(contentRect: CGRect(x: screen.midX - 50, y: screen.midY - 50, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        defer { window.contentView = nil; window.close() }
        let host = NSHostingView(rootView: MetalSendButton(configuration: config, isEnabled: true, sessionID: id) {}
            .frame(width: 100, height: 100)
            .environment(\.rightWorkspacePageIsActive, true))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        func advancing() -> Bool {
            let now = Date().timeIntervalSinceReferenceDate
            return model.time(now: now + 1) - model.time(now: now) > 0.9
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while !advancing(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard advancing() else {
            // Reduce Motion or an invisible host keeps Send still and pointer-free.
            XCTAssertEqual(model.pointer, .zero)
            return
        }

        func move(_ point: CGPoint) {
            // XCTest windows do not route synthetic moves through tracking areas;
            // deliver them to the hosting view the way AppKit's tracking area does.
            host.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        }
        func silhouette(rows: Range<Int>) throws -> Int {
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width // rows/columns are given in points
            var count = 0
            for y in Int(CGFloat(rows.lowerBound) * scale)..<Int(CGFloat(rows.upperBound) * scale) {
                for x in Int(30 * scale)..<Int(70 * scale) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 }
            }
            return count
        }
        func settle(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        }

        // Rows just above the 30 pt surface (y-down bitmap rows 30..<35).
        let restAbove = try silhouette(rows: 30..<35)
        // AppKit always sends entered before moved.
        host.mouseEntered(with: NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 50, y: 50), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        // Window coordinates are y-up; the 34 pt target spans 33...67.
        let edges: [(name: String, point: CGPoint, outward: CGVector)] = [
            ("top", CGPoint(x: 50, y: 65.5), CGVector(dx: 0, dy: -1)),
            ("right", CGPoint(x: 65.5, y: 50), CGVector(dx: 1, dy: 0)),
            ("bottom", CGPoint(x: 50, y: 34.5), CGVector(dx: 0, dy: 1)),
            ("left", CGPoint(x: 34.5, y: 50), CGVector(dx: -1, dy: 0))
        ]
        for edge in edges {
            for step in 0..<5 {
                move(CGPoint(x: edge.point.x + CGFloat(step) * 0.1, y: edge.point.y))
                try await Task.sleep(for: .milliseconds(30))
            }
            try await settle {
                guard let field = model.bend.field else { return false }
                return field.dirX * edge.outward.dx + field.dirY * edge.outward.dy > 2.5
            }
            let field = try XCTUnwrap(model.bend.field, edge.name)
            XCTAssertGreaterThan(field.dirX * edge.outward.dx + field.dirY * edge.outward.dy, 2.5,
                                 "\(edge.name): the rim bulges toward the pointer by more than 2.5 pt")
            XCTAssertEqual(field.cx + edge.outward.dx * -15, 15, accuracy: 4, "\(edge.name) contact x")
            XCTAssertEqual(field.cy + edge.outward.dy * -15, 15, accuracy: 4, "\(edge.name) contact y")
            if edge.name == "top" {
                XCTAssertGreaterThan(try silhouette(rows: 30..<35), restAbove + 4, "the bent outline is visible above the button")
            }
        }

        host.mouseExited(with: NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 98, y: 98), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        move(CGPoint(x: 98, y: 98))
        try await settle { model.bend.field == nil }
        XCTAssertEqual(model.pointer, .zero)
        XCTAssertNil(model.bend.field, "the rim springs back to rest after the pointer leaves")
        XCTAssertLessThanOrEqual(try silhouette(rows: 30..<35), restAbove + 1)
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
        let points = [CGPoint(x: 50, y: 50), CGPoint(x: 36, y: 50), CGPoint(x: 64, y: 50), CGPoint(x: 50, y: 36), CGPoint(x: 50, y: 64), CGPoint(x: 33.25, y: 33.25), CGPoint(x: 66.75, y: 33.25), CGPoint(x: 33.25, y: 66.75), CGPoint(x: 66.75, y: 66.75)]
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
