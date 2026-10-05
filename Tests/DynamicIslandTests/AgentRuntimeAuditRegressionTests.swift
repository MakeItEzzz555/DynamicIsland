import AgentBridgeShared
import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentRuntimeAuditRegressionTests: XCTestCase {
    func testNoOpPolicyRetentionPublishesNothing() {
        let controller = AgentApprovalController()
        let session = instance()
        controller.setAutoApprove(true, for: session)
        var changes = 0
        let observation = controller.objectWillChange.sink { changes += 1 }
        controller.retainPolicies(for: [session])
        controller.retainPolicies(for: [session])
        XCTAssertEqual(changes, 0)
        controller.retainPolicies(for: [])
        XCTAssertEqual(changes, 1)
        controller.retainPolicies(for: [])
        controller.clearPolicies()
        XCTAssertEqual(changes, 1)
        withExtendedLifetime(observation) {}
    }

    func testPendingSelectionUsesArrivalNotRequestIDOrExpiry() async {
        let controller = AgentApprovalController()
        let first = request("z-arrived-first", expiration: .distantFuture)
        let second = request("a-arrived-second", expiration: Date().addingTimeInterval(1_000))
        let task1 = Task { await controller.request(first, maximumWait: nil) }
        while controller.pendingRequests[first.key] == nil { await Task.yield() }
        let task2 = Task { await controller.request(second, maximumWait: nil) }
        while controller.pendingRequests[second.key] == nil { await Task.yield() }
        XCTAssertEqual(controller.nextPendingRequest(), first)
        XCTAssertEqual(controller.pendingRequest(for: first.key.session), first)
        _ = controller.resolve(session: first.key.session, requestID: first.key.requestID, decision: .deny)
        XCTAssertEqual(controller.presentedRequest(for: first.key.session), first,
                       "Keep the first owner stable while provider acknowledgement is pending")
        controller.confirmDelivery(first.key)
        XCTAssertEqual(controller.nextPendingRequest(), second)
        controller.cancelAll()
        let decision1 = await task1.value
        let decision2 = await task2.value
        XCTAssertEqual(decision1, .deny)
        XCTAssertNil(decision2)
    }

    func testReplacingTerminalRendererRemovesRetiredNativeView() {
        let host = TerminalMountView()
        let retired = InteractiveTerminalView()
        let active = InteractiveTerminalView()
        host.mount(retired)
        host.mount(active)
        XCTAssertNil(retired.superview)
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertTrue(host.subviews.first === active)
        host.mount(active)
        XCTAssertEqual(host.subviews.count, 1)
        host.detach()
        XCTAssertTrue(host.subviews.isEmpty)
    }

    func testReturnDoesNotApproveNativeFeedPermissionCard() async throws {
        let controller = AgentApprovalController()
        let pending = request("return-must-not-approve", expiration: .distantFuture)
        let waiting = Task { await controller.request(pending, maximumWait: nil) }
        while controller.pendingRequests[pending.key] == nil { await Task.yield() }
        defer { controller.cancelAll() }
        let session = AgentSession(id: instance(), source: .terminal, state: .waitingForApproval,
            project: AgentProjectContext(), capabilities: AgentCapabilities(), usage: AgentUsage(),
            tools: [:], commands: [:], approvals: [:], subagents: [:], recentActivity: [],
            startedAt: Date(), endedAt: nil, lastUpdatedAt: Date())
        let host = NSHostingView(rootView: AgentConsoleApprovalRow(request: pending, session: session,
                                                                  approvalControl: controller).frame(width: 400, height: 180))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<4 { await Task.yield() }
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        XCTAssertFalse(host.performKeyEquivalent(with: enter), "Approve has no Return/default-action binding")
        window.sendEvent(enter)
        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(controller.deliveryState(for: pending.key), .awaitingDecision)
        controller.cancelAll()
        let decision = await waiting.value
        XCTAssertNil(decision)
    }

    func testHistoryRestorationUsesMeasuredEntryRatherThanEstimatedClip() async {
        final class FlippedDocument: NSView { override var isFlipped: Bool { true } }
        let id = instance()
        var saved = AgentTranscriptViewportStore.Position()
        saved.followingLatest = false; saved.origin = CGPoint(x: 0, y: 80)
        saved.width = 440; saved.readingEntryID = "reading"; saved.readingEntryOffset = 20
        AgentTranscriptViewportStore.shared.save(saved, for: id)
        let document = FlippedDocument(frame: CGRect(x: 0, y: 0, width: 400, height: 1_000))
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scroll.documentView = document
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = scroll; window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil) }
        let anchor = AgentTranscriptTailAnchor()
        let tail = AgentTranscriptTailMarker.Marker(frame: CGRect(x: 0, y: 999, width: 400, height: 1))
        document.addSubview(tail); anchor.view = tail
        let reading = AgentTranscriptEntryMarker.Marker(frame: CGRect(x: 0, y: 300, width: 400, height: 150))
        document.addSubview(reading); reading.configure(anchor: anchor, entryID: "reading")
        let probe = AgentTranscriptViewportProbe.Probe(frame: .zero)
        document.addSubview(probe)
        probe.configure(sessionID: id, contentToken: "test", jumpRequest: 0, realizationID: "tail",
                        tail: anchor, realizeLatest: {}, changed: { _ in })
        for _ in 0..<10 { await Task.yield(); scroll.layoutSubtreeIfNeeded() }
        XCTAssertEqual(scroll.contentView.bounds.minY, 320, accuracy: 1)
        reading.frame.origin.y = 370
        document.frame.size.height = 1_070
        anchor.geometryChanged?()
        for _ in 0..<10 { await Task.yield(); scroll.layoutSubtreeIfNeeded() }
        XCTAssertEqual(scroll.contentView.bounds.minY, 390, accuracy: 1,
                       "Late lazy realization preserves the same reading row and offset")
        probe.detach(); reading.detach()
    }

    func testRemovedHistoryAnchorFallsBackWithoutWaitingForImpossibleRow() async {
        final class FlippedDocument: NSView { override var isFlipped: Bool { true } }
        let id = instance()
        var saved = AgentTranscriptViewportStore.Position()
        saved.followingLatest = false; saved.origin = CGPoint(x: 0, y: 90)
        saved.width = 400; saved.readingEntryID = "aged-out-row"; saved.readingEntryOffset = 20
        AgentTranscriptViewportStore.shared.save(saved, for: id)
        let document = FlippedDocument(frame: CGRect(x: 0, y: 0, width: 400, height: 1_000))
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scroll.documentView = document
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = scroll; window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil) }
        let anchor = AgentTranscriptTailAnchor()
        let tail = AgentTranscriptTailMarker.Marker(frame: CGRect(x: 0, y: 999, width: 400, height: 1))
        document.addSubview(tail); anchor.view = tail
        let probe = AgentTranscriptViewportProbe.Probe(frame: .zero)
        document.addSubview(probe)
        var realizations = 0
        probe.configure(sessionID: id, contentToken: "test", jumpRequest: 0, realizationID: "tail", tail: anchor,
            realizeLatest: {}, realizeReadingAnchor: { _ in realizations += 1; return false }, changed: { _ in })
        for _ in 0..<10 { await Task.yield(); scroll.layoutSubtreeIfNeeded() }
        XCTAssertEqual(realizations, 1)
        XCTAssertEqual(scroll.contentView.bounds.minY, 90, accuracy: 1)
        XCTAssertFalse(AgentTranscriptViewportStore.shared.isRestoringHistory(for: id))
        probe.detach()
    }

    func testPermissionRepositionOnlyForChangedGeometry() {
        func signature(_ profile: CollapsedPresentationProfile) -> OverlayGeometrySignature {
            OverlayGeometrySignature(collapsedSize: CGSize(width: 216, height: 34),
                expandedSize: CGSize(width: 946, height: 400), expandedPresentationKind: .agentsWorkspace,
                collapsedActivityProfile: nil, collapsedPresentationProfile: profile,
                useAdaptiveNotchSizing: true, respectHardwareNotch: true)
        }
        let ordinary = signature(.normal)
        let pending = signature(.agentPermission(hovered: false, reduceMotion: false))
        XCTAssertTrue(OverlayPermissionGeometryPolicy.needsReposition(current: pending, applied: ordinary))
        for _ in 0..<200 {
            XCTAssertFalse(OverlayPermissionGeometryPolicy.needsReposition(current: pending, applied: pending),
                           "Streaming, policies and delivery status cannot schedule identical panel bounds")
        }
        let hovered = signature(.agentPermission(hovered: true, reduceMotion: false))
        XCTAssertTrue(OverlayPermissionGeometryPolicy.needsReposition(current: hovered, applied: pending))
        XCTAssertTrue(OverlayPermissionGeometryPolicy.needsReposition(current: ordinary, applied: pending))
    }

    func testStackHeaderHorizontalGestureLatchesOnceAndVerticalRemainsContent() {
        var swipe = RightWorkspaceSwipeRecognizer()
        XCTAssertEqual(swipe.handle(deltaX: -8, deltaY: 1, phase: .began, at: 0), .consumed)
        XCTAssertEqual(swipe.handle(deltaX: -26, deltaY: 1, phase: .changed, at: 0.01), .next)
        XCTAssertEqual(swipe.handle(deltaX: -90, deltaY: 0, phase: .momentum, at: 0.02), .consumed)
        XCTAssertEqual(swipe.handle(deltaX: -90, deltaY: 0, phase: .changed, at: 0.03), .consumed)
        swipe.reset()
        XCTAssertEqual(swipe.handle(deltaX: 1, deltaY: -8, phase: .began, at: 1), .passThrough)
        XCTAssertEqual(swipe.handle(deltaX: -50, deltaY: 1, phase: .changed, at: 1.01), .passThrough)
        XCTAssertEqual(swipe.handle(deltaX: -50, deltaY: 1, phase: .momentum, at: 1.02), .passThrough)
        swipe.reset()
        XCTAssertEqual(swipe.handle(deltaX: -90, deltaY: 0, phase: .momentum, at: 2), .ignored)
    }

    func testBothNativePanelAndMonitorRoutesGiveStackHeaderFirstOwnership() throws {
        // Panel events intentionally bypass the local monitor. Both entry
        // paths must arbitrate the header before ordinary shell navigation.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/DynamicIsland/Overlay/OverlayWindowController.swift"), encoding: .utf8)
        for name in ["handleExpandedScrollWheelFromMonitor", "handleExpandedScrollWheel"] {
            let start = try XCTUnwrap(source.range(of: "private func \(name)("))
            let remainder = source[start.upperBound...]
            let end = remainder.range(of: "\n    private func")?.lowerBound ?? remainder.endIndex
            let body = remainder[..<end]
            let stack = try XCTUnwrap(body.range(of: "routeAgentStackSwipe(event)"))
            let workspace = try XCTUnwrap(body.range(of: "routeRightWorkspaceSwipe(event)"))
            XCTAssertLessThan(stack.lowerBound, workspace.lowerBound, name)
        }
    }

    func testLazyTailRealizationUsesOnlyBoundedLayoutEventsAndStopsOnDetach() async {
        final class FlippedDocument: NSView { override var isFlipped: Bool { true } }
        let document = FlippedDocument(frame: CGRect(x: 0, y: 0, width: 400, height: 1_000))
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scroll.documentView = document
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = scroll; window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil) }
        let session = AgentSessionInstanceID(sessionID: .init(provider: .codex, nativeID: "layout-driven-latest"), generation: .init(rawValue: 1))
        let anchor = AgentTranscriptTailAnchor()
        let probe = AgentTranscriptViewportProbe.Probe(frame: .zero)
        document.addSubview(probe)
        var attempts = 0
        probe.configure(sessionID: session, contentToken: "one", jumpRequest: 0, realizationID: "missing-tail",
                        tail: anchor, realizeLatest: { attempts += 1 }, changed: { _ in })
        for _ in 0..<12 { await Task.yield() }
        let idleAttempts = attempts
        for _ in 0..<24 { await Task.yield() }
        XCTAssertEqual(attempts, idleAttempts, "No timer/retry polling without native layout progress")
        for _ in 0..<20 {
            probe.layout()
            for _ in 0..<3 { await Task.yield() }
        }
        XCTAssertEqual(attempts, AgentTranscriptViewportProbe.Probe.maximumRealizationAttempts)
        probe.detach()
        probe.layout()
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(attempts, AgentTranscriptViewportProbe.Probe.maximumRealizationAttempts,
                       "Retiring native callbacks cannot restart presentation work")
    }

    private func instance() -> AgentSessionInstanceID {
        AgentSessionInstanceID(sessionID: AgentSessionID(provider: .codex, nativeID: "audit"),
                               generation: AgentSessionGeneration(rawValue: 3))
    }
    private func request(_ id: String, expiration: Date) -> AgentApprovalControlRequest {
        AgentApprovalControlRequest(key: AgentApprovalControlKey(session: instance(), requestID: AgentCorrelationID(rawValue: id)),
                                    summary: "Audit harmless request", expiresAt: expiration)
    }
}
