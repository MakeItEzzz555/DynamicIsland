import AppKit
import AgentBridgeShared
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
private final class CameraHostedView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CameraHostedWindow: NSPanel, CameraLocalEventWindow {
    override var canBecomeKey: Bool { true }
    var cameraEventGate: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if cameraEventGate?(event) != false { super.sendEvent(event) }
    }
}

@MainActor
enum CameraNativeHostedFixture {
    static func hosted<V: View>(_ view: V, size: CGSize = CGSize(width: 300, height: 100)) -> NSWindow {
        _ = NSApplication.shared
        let window = CameraHostedWindow(contentRect: CGRect(origin: CGPoint(x: -1500, y: -1500), size: size),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.contentView = CameraHostedView(rootView: view.frame(width: size.width, height: size.height))
        window.makeKeyAndOrderFront(nil)
        pump()
        return window
    }
    static func pump() {
        let deadline = Date().addingTimeInterval(0.06)
        repeat {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        } while Date() < deadline
    }
    static func click(_ router: CameraInteractionRouter, at point: CGPoint) {
        let release = Timer(timeInterval: 0.08, repeats: false) { [weak router] _ in
            MainActor.assumeIsolated { router?.release(at: point) }
        }
        RunLoop.main.add(release, forMode: .common)
        defer { release.invalidate() }
        router.press(at: point)
        let deadline = Date().addingTimeInterval(1)
        repeat { pump() } while router.isPressed && Date() < deadline
        pump()
    }
}

@MainActor
final class CameraNativeRoutingTests: XCTestCase {
    func testRawPhysicalTouchOwnsInputBeforeAnyWheelEvent() {
        var count = 0
        let window = CameraNativeHostedFixture.hosted(Button("Fixture") { count += 1 })
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.physicalTouchSession(active: true)
        router.press(at: CGPoint(x: 150, y: 50)); router.release(at: CGPoint(x: 150, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertTrue(router.physicalOwnsInput)
        XCTAssertEqual(count, 0)
        router.physicalTouchSession(active: false)
        XCTAssertTrue(router.physicalOwnsInput, "The quiet period starts after the physical touch ends")
    }
    func testFirstCameraDragWorksWhilePanelIsNotKey() {
        var ends = 0
        let window = CameraNativeHostedFixture.hosted(Color.gray.frame(width: 200, height: 50)
            .gesture(DragGesture(minimumDistance: 0).onEnded { _ in ends += 1 }))
        window.resignKey()
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 100, y: 50)); router.drag(to: CGPoint(x: 190, y: 50))
        router.release(at: CGPoint(x: 190, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(ends, 1)
    }
    func testCameraCanFocusNativeTextFieldWithoutEnteringText() {
        var text = ""
        let window = CameraNativeHostedFixture.hosted(TextField("Fixture", text: Binding(get: { text }, set: { text = $0 })).frame(width: 200))
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 150, y: 50)); router.release(at: CGPoint(x: 150, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertTrue(window.firstResponder is NSTextView)
        XCTAssertEqual(text, "")
    }
    func testDeliveredCameraPressCancellationCannotActivateNativeHandle() {
        let window = CameraNativeHostedFixture.hosted(Color.clear)
        let handle = WorkspaceNativeDragView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        var clicks = 0
        handle.clicked = { clicks += 1 }; window.contentView = handle
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 150, y: 50)); CameraNativeHostedFixture.pump()
        router.cancel(); CameraNativeHostedFixture.pump()
        XCTAssertEqual(clicks, 0)
    }
    func testCameraEditorHandleCannotStartGlobalDraggingSession() {
        let window = CameraNativeHostedFixture.hosted(Color.clear)
        let handle = WorkspaceNativeDragView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        var begins = 0, clicks = 0
        handle.began = { begins += 1 }; handle.clicked = { clicks += 1 }
        window.contentView = handle
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 100, y: 50)); router.drag(to: CGPoint(x: 200, y: 50))
        router.release(at: CGPoint(x: 200, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(begins, 0)
        XCTAssertEqual(clicks, 0)
    }
    func testNativeTabUsesCentralNavigation() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "camera-tabs-\(UUID())")!)
        let navigation = IslandNavigationStore(), anchor = TabPointerAnchor(movePointer: { _ in XCTFail("Camera warp"); return false })
        let pages = navigation.availablePages(using: settings)
        guard let index = pages.firstIndex(where: { $0 != navigation.selectedPage }) else { return XCTFail("No tabs") }
        let window = CameraNativeHostedFixture.hosted(ExpandedIslandPageSwitcher(settings: settings, navigation: navigation, pointerAnchor: anchor))
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        let x = ExpandedIslandHeaderMetrics.tabPadding + ExpandedIslandHeaderMetrics.buttonWidth / 2 +
            CGFloat(index) * (ExpandedIslandHeaderMetrics.buttonWidth + ExpandedIslandHeaderMetrics.tabSpacing)
        router.press(at: CGPoint(x: x, y: 50)); router.release(at: CGPoint(x: x, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(navigation.selectedPage, pages[index])
        XCTAssertFalse(anchor.isActive)
    }
    func testNativeTimerRulerDragCommitsOnce() {
        var seconds = 120, commits = 0
        let window = CameraNativeHostedFixture.hosted(TimerRuler(snapshot: .init(), now: { .zero },
            seconds: Binding(get: { seconds }, set: { seconds = $0 }), extraMotion: false,
            onCommit: { _ in commits += 1 }, tickFeedback: {}))
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 100, y: 50)); router.drag(to: CGPoint(x: 200, y: 50))
        router.release(at: CGPoint(x: 200, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(commits, 1)
        XCTAssertNotEqual(seconds, 120)
    }
    func testNativeExactApprovalUsesExistingAuthority() async {
        let session = SettingsPreviewFixtures.agentSession(provider: .codex)
        let request = AgentApprovalControlRequest(key: .init(session: session.id, requestID: .init(rawValue: "camera-exact")),
            summary: "Synthetic request", expiresAt: .distantFuture)
        let controller = AgentApprovalController()
        let waiting = Task { await controller.request(request, maximumWait: .seconds(2)) }
        await Task.yield()
        let window = CameraNativeHostedFixture.hosted(AgentCompactPermissionView(permission: .init(request: request, session: session),
            approvals: controller, topBandHeight: 20), size: CGSize(width: 330, height: 110))
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 208, y: 50)); router.release(at: CGPoint(x: 208, y: 50)); CameraNativeHostedFixture.pump()
        let result = await waiting.value
        XCTAssertEqual(result, .allow)
        XCTAssertEqual(controller.resolve(session: session.id, requestID: request.key.requestID, decision: .allow), .missing)
    }
    func testClipboardFixtureKeepsExistingWorkspaceAction() {
        let layout = IslandLayoutStore()
        let window = CameraNativeHostedFixture.hosted(Button("Clipboard") { layout.requestWorkspaceAction(.clipboard) })
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 150, y: 50)); router.release(at: CGPoint(x: 150, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(layout.workspaceActionRequest?.action, .clipboard)
    }
    func testSwiftUIButtonExactlyOnceAndSystemCursorDoesNotMove() throws {
        var count = 0
        let window = CameraNativeHostedFixture.hosted(Button("Click") { count += 1 }.frame(width: 120, height: 50).contentShape(Rectangle()))
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        var externalPointerMoved = false
        let observe: (NSEvent) -> Void = { event in
            guard !CameraInteractionRouter.isCameraEvent(event), let cg = event.cgEvent,
                  cg.getIntegerValueField(.eventSourceUnixProcessID) != Int64(ProcessInfo.processInfo.processIdentifier) else { return }
            externalPointerMoved = true
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in observe(event); return event }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            MainActor.assumeIsolated { observe(event) }
        }
        defer {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
        }
        let cursor = NSEvent.mouseLocation
        window.ignoresMouseEvents = true
        router.press(at: CGPoint(x: 150, y: 50)); router.press(at: CGPoint(x: 150, y: 50))
        router.release(at: CGPoint(x: 150, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(count, 1)
        if externalPointerMoved && NSEvent.mouseLocation != cursor {
            throw XCTSkip("An external pointer event moved the system cursor during this check; local button routing completed once.")
        }
        XCTAssertEqual(NSEvent.mouseLocation, cursor)
    }
    func testMediaButtonCenterAndCornerAndDisabled() {
        for enabled in [true, false] {
            var count = 0
            let window = CameraNativeHostedFixture.hosted(MediaRowButton(symbol: "play.fill", label: "Play", size: 34, enabled: enabled) { count += 1 })
            let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
            for point in [CGPoint(x: 150, y: 50), CGPoint(x: 135, y: 35)] {
                router.press(at: point); router.release(at: point); CameraNativeHostedFixture.pump()
            }
            XCTAssertEqual(count, enabled ? 2 : 0)
            router.shutdown(); CameraNativeHostedFixture.pump(); window.close()
        }
    }
    func testStandardSwiftUISliderDragUsesItsTargetAndBinding() {
        var value = 0.2
        let window = CameraNativeHostedFixture.hosted(Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...1).frame(width: 200))
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 75, y: 50))
        router.drag(to: CGPoint(x: 220, y: 50)); router.release(at: CGPoint(x: 220, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertGreaterThan(value, 0.8)
        XCTAssertFalse(router.isPressed)
    }
    func testSliderEditingTransactionEndsOnceAndCancellationDoesNotCommit() {
        for cancelled in [false, true] {
            var value = 0.2, edits: [Bool] = [], cancellations = 0
            let window = CameraNativeHostedFixture.hosted(Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...1)
                .frame(width: 200)
                .background(CameraSliderEditingBridge(onEditingChanged: { edits.append($0) }, onCancel: { cancellations += 1 })))
            let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
            router.press(at: CGPoint(x: 90, y: 50)); router.drag(to: CGPoint(x: 200, y: 50))
            if cancelled { router.cancel() } else { router.release(at: CGPoint(x: 200, y: 50)) }
            CameraNativeHostedFixture.pump()
            XCTAssertEqual(edits, cancelled ? [true] : [true, false])
            XCTAssertEqual(cancellations, cancelled ? 1 : 0)
            router.shutdown(); CameraNativeHostedFixture.pump(); window.close()
        }
    }
    func testCameraCannotAcquireTabPointerAnchor() {
        let anchor = TabPointerAnchor(movePointer: { _ in XCTFail("Camera must not warp"); return false })
        anchor.register(.agents, owner: UUID()) { CGRect(x: 10, y: 10, width: 30, height: 30) }
        XCTAssertNil(anchor.activate(.agents, eventType: .leftMouseUp, pointer: CGPoint(x: 20, y: 20), maximumDuration: 1, isCameraInput: true))
        XCTAssertFalse(anchor.isActive)
    }
    func testLocalScrollMovesNativeViewport() {
        let window = CameraNativeHostedFixture.hosted(Color.clear)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        scroll.hasVerticalScroller = true
        scroll.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 280, height: 1200))
        window.contentView = scroll
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 400))
        let prior = scroll.contentView.bounds.origin.y
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        router.scroll(at: CGPoint(x: 150, y: 50), delta: 40); CameraNativeHostedFixture.pump()
        XCTAssertNotEqual(scroll.contentView.bounds.origin.y, prior)
        router.shutdown(); CameraNativeHostedFixture.pump(); window.close()
    }
    func testPhysicalInputInvalidatesCameraBeforeDispatch() {
        var clicks = 0
        let window = CameraNativeHostedFixture.hosted(Button("Click") { clicks += 1 })
        let router = CameraInteractionRouter(window: window)
        router.press(at: CGPoint(x: 150, y: 50))
        let physical = NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 150, y: 50),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 20, clickCount: 0, pressure: 0)!
        window.sendEvent(physical)
        CameraNativeHostedFixture.pump()
        XCTAssertEqual(clicks, 0)
        XCTAssertTrue(router.physicalOwnsInput)
        XCTAssertFalse(router.isPressed)
        router.press(at: CGPoint(x: 150, y: 50)); router.release(at: CGPoint(x: 150, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(clicks, 0)
        router.shutdown(); CameraNativeHostedFixture.pump(); window.close()
    }
    func testLocalDragGestureDeliversOneEnd() {
        var ends = 0, movement = 0.0
        let surface = Color.gray.frame(width: 200, height: 50).gesture(DragGesture(minimumDistance: 0)
            .onChanged { movement = $0.translation.width }.onEnded { _ in ends += 1 })
        let window = CameraNativeHostedFixture.hosted(surface)
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 100, y: 50)); router.drag(to: CGPoint(x: 190, y: 50))
        router.release(at: CGPoint(x: 190, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(ends, 1)
        XCTAssertGreaterThan(movement, 60)
    }
    func testCancelledQueuedClickDoesNotActivate() {
        var count = 0
        let window = CameraNativeHostedFixture.hosted(Button("Cancel") { count += 1 })
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 150, y: 50)); router.cancel(); CameraNativeHostedFixture.pump()
        XCTAssertEqual(count, 0)
    }
    func testMessageReplyUsesExistingControllerAndConfirmedDraftRule() {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        let focus = FakeFocus(); focus.isFocused = false
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: focus, now: { Date(timeIntervalSince1970: 2) })
        controller.receive(MessagingFixtures.message(conversation: "camera-fixture-exact-chat", at: 1))
        guard let entry = controller.current else { return XCTFail("Missing fixture") }
        controller.updateDraft("synthetic reply", for: entry)
        let window = CameraNativeHostedFixture.hosted(MessagingReplyComposer(controller: controller, entry: entry).frame(width: 300, height: 100, alignment: .top))
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 278, y: 83)); router.release(at: CGPoint(x: 278, y: 83)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(adapter.sent.count, 1)
        XCTAssertEqual(adapter.sent.first?.1.nativeID, "camera-fixture-exact-chat")
        XCTAssertEqual(controller.draft(for: entry).text, "")
    }
    func testAgentSendButtonNativeHitTarget() {
        var count = 0
        var config = MetalSendConfiguration(); config.enabled = false
        let window = CameraNativeHostedFixture.hosted(MetalSendButton(configuration: config, isEnabled: true) { count += 1 })
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); CameraNativeHostedFixture.pump(); window.close() }
        router.press(at: CGPoint(x: 150, y: 50)); router.release(at: CGPoint(x: 150, y: 50)); CameraNativeHostedFixture.pump()
        XCTAssertEqual(count, 1)
    }
}
