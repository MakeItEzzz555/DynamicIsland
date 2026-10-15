import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland
@testable import LibrariesNative
import AgentBridgeShared

/// The Agents composer's Send starts disabled and becomes enabled only once
/// the user types. SwiftUI keeps a second, window-less copy of a Button's
/// label for its `.keyboardShortcut`, created at that moment. The copy's
/// visibility probe used to report "not visible" into the Send's shared state
/// and the real probe (already deduplicated at "visible") never corrected it:
/// the Metal clock and pointer stayed paused until the composer was remounted
/// (for example Chat -> Terminal -> Chat, which restores the stored draft so
/// Send mounts already enabled).
@MainActor
final class AgentSendFirstVisitTests: XCTestCase {
    @MainActor
    private final class Gate: ObservableObject {
        @Published var enabled: Bool
        init(enabled: Bool) { self.enabled = enabled }
    }

    private struct ComposerSend: View {
        @ObservedObject var gate: Gate
        let id: AgentSessionInstanceID
        var body: some View {
            // Same modifier chain the composer applies around MetalSendButton.
            MetalSendButton(configuration: .init(), isEnabled: gate.enabled, sessionID: id) {}
                .keyboardShortcut(.return, modifiers: [.command])
                .frame(width: 100, height: 100)
                .environment(\.rightWorkspacePageIsActive, true)
        }
    }

    func testVisibilityProbeThatNeverReachedAWindowStaysSilent() async throws {
        var reports: [Bool] = []
        let probe = NativeVisualVisibility.Probe { reports.append($0) }
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        container.addSubview(probe)
        probe.refresh()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reports, [], "An off-window copy is not authoritative for the shared visibility state")
    }

    /// First visit: the composer is empty (Send disabled), the user types.
    func testSendEnabledAfterTheHostSettledKeepsItsClockAndHoverBend() async throws {
        try await assertSendIsLive(enabledAtMount: false)
    }

    /// After a Terminal round trip the stored draft is restored: Send mounts enabled.
    func testSendMountedEnabledKeepsItsClockAndHoverBend() async throws {
        try await assertSendIsLive(enabledAtMount: true)
    }

    private func assertSendIsLive(enabledAtMount: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        NSApplication.shared.finishLaunching()
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Reduce Motion intentionally pauses Send")
        let id = AgentSessionInstanceID(sessionID: .init(provider: .codex, nativeID: "first-visit-\(UUID())"),
                                        generation: .init(rawValue: 1))
        let model = AgentMetalModelStore.model(for: id)
        let gate = Gate(enabled: enabledAtMount)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(contentRect: CGRect(x: screen.midX - 50, y: screen.midY - 50, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        let host = NSHostingView(rootView: ComposerSend(gate: gate, id: id))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }

        func advancing() -> Bool {
            let now = Date().timeIntervalSinceReferenceDate
            return model.time(now: now + 1) - model.time(now: now) > 0.9
        }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        }
        func move(_ point: CGPoint) {
            host.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        }

        // The page has settled before the user types: the host is visible.
        try await wait { window.isVisible && window.occlusionState.contains(.visible) }
        XCTAssertTrue(window.occlusionState.contains(.visible), "The fixture needs a visible native host", file: file, line: line)
        guard window.occlusionState.contains(.visible) else { return }
        if !enabledAtMount {
            try await Task.sleep(for: .milliseconds(300))
            gate.enabled = true
        }
        try await Task.sleep(for: .milliseconds(500))

        try await wait(advancing)
        XCTAssertTrue(advancing(), "Enabled Send must run its Metal clock (enabledAtMount=\(enabledAtMount))", file: file, line: line)

        host.mouseEntered(with: NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 50, y: 50), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        for step in 0..<5 {
            move(CGPoint(x: 62 + CGFloat(step) * 0.1, y: 50))
            try await Task.sleep(for: .milliseconds(30))
        }
        try await wait { model.pointer != .zero }
        XCTAssertNotEqual(model.pointer, .zero, "Hovering the enabled Send must feed the liquid bend (enabledAtMount=\(enabledAtMount))", file: file, line: line)
    }

    private final class Frames { var action = CGRect.null }

    private func descendants<T: NSView>(_ view: NSView, as type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, as: type) }
    }

    /// The real composer: typing, clearing and typing again keeps Send animatable and hover-reactive.
    func testRealComposerSendStaysLiveAcrossTypingAndClearing() async throws {
        NSApplication.shared.finishLaunching()
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Reduce Motion intentionally pauses Send")
        let id = AgentSessionInstanceID(sessionID: AgentSessionID(provider: .codex, nativeID: "first-visit-composer-\(UUID())"),
                                        generation: AgentSessionGeneration(rawValue: 1))
        let session = AgentSession(id: id, source: .terminal, state: .working,
            project: AgentProjectContext(displayName: "DynamicIsland"), capabilities: AgentCapabilities(),
            usage: AgentUsage(), tools: [:], commands: [:], approvals: [:], subagents: [:],
            recentActivity: [], startedAt: Date(), endedAt: nil, lastUpdatedAt: Date(), availability: .loaded)
        let model = AgentMetalModelStore.model(for: id)
        let frames = Frames()
        let view = AgentEmbeddedConsoleView(
            session: session, mode: .interactive(canInterrupt: false), interactionState: .ready,
            layoutStore: IslandLayoutStore(), approvalControl: AgentApprovalController(),
            onSelectSession: { _ in }, onSubmit: { _ in true }, onInterrupt: {}, loadDraft: { _ in "" })
            .onPreferenceChange(AgentComposerActionFrameKey.self) { frames.action = $0 }
            .frame(width: 500, height: 250)
            .coordinateSpace(name: IslandCanvasCoordinateSpace.name)
            .environment(\.rightWorkspacePageIsActive, true)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: CGRect(x: screen.midX - 250, y: screen.midY - 125, width: 500, height: 250),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }

        func advancing() -> Bool {
            let now = Date().timeIntervalSinceReferenceDate
            return model.time(now: now + 1) - model.time(now: now) > 0.9
        }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        }
        func hover() async throws {
            let local = CGPoint(x: frames.action.midX + 4, y: 250 - frames.action.midY)
            func event(_ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            }
            host.mouseExited(with: event(CGPoint(x: 1, y: 1)))
            host.mouseEntered(with: event(local))
            for step in 0..<5 {
                host.mouseMoved(with: event(CGPoint(x: local.x + CGFloat(step) * 0.1, y: local.y)))
                try await Task.sleep(for: .milliseconds(30))
            }
            try await wait { model.pointer != .zero }
            XCTAssertNotEqual(model.pointer, .zero, "Hovering the enabled Send must feed the liquid bend")
        }

        try await wait { window.isVisible && window.occlusionState.contains(.visible) }
        XCTAssertTrue(window.occlusionState.contains(.visible), "The fixture needs a visible native host")
        guard window.occlusionState.contains(.visible) else { return }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(descendants(host, as: NSTextView.self).first)

        for round in 1...2 {
            editor.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
            try await Task.sleep(for: .milliseconds(500))
            try await wait(advancing)
            XCTAssertTrue(advancing(), "Typed text must leave Send animating (round \(round))")
            try await hover()
            editor.string = ""
            editor.didChangeText()
            try await Task.sleep(for: .milliseconds(300))
        }
    }
}
