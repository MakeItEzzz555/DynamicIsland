import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class CollapsedCommunicationTests: XCTestCase {
    func testStaticActivitiesNeverGrowAndInteractiveFramesKeepTheirTopAnchor() {
        let base = CGRect(x: 500, y: 900, width: 240, height: 34)
        for kind in [DynamicIslandLiveActivityKind.media, .timer, .battery, .agent, .screenRecording,
                     .voiceRecording, .fileTray, .call] {
            let policy = CollapsedActivityHoverPolicy.resolve(kind: kind)
            XCTAssertEqual(policy, .none)
            XCTAssertEqual(policy.frame(from: base), base)
        }
        let reply = CollapsedActivityHoverPolicy.resolve(kind: .message, exactMessageReply: true)
        let permission = CollapsedActivityHoverPolicy.resolve(kind: .agent, exactAgentApproval: true)
        let call = CollapsedActivityHoverPolicy.resolve(kind: .call, authorizedCallControls: true)
        XCTAssertEqual(reply, .interactive(requiredHeight: 128))
        XCTAssertEqual(permission, .interactive(requiredHeight: 68))
        XCTAssertEqual(call, permission)
        for policy in [reply, permission, call, .peek] {
            XCTAssertEqual(policy.frame(from: base).maxY, base.maxY)
            XCTAssertEqual(policy.frame(from: base).midX, base.midX)
        }
        XCTAssertEqual(CollapsedActivityHoverPolicy.resolve(kind: .message), .peek)
    }

    func testNativeCallObservationAndControlsAreUnavailableAndPreviewsRemainSamples() {
        XCTAssertFalse(NativeCallAuthority.canObserve)
        XCTAssertFalse(NativeCallAuthority.canControl)
        for scenario in [LiveActivityLayoutPreviewScenario.activeCall, .connectedCall] {
            let sample = LiveActivityPreviewCatalog.activities(for: scenario)
            XCTAssertEqual(sample.count, 1)
            XCTAssertEqual(sample.first?.kind, .call)
            XCTAssertTrue(sample.first?.subtitle?.contains("sample") == true)
        }
        XCTAssertEqual(AudioVisualizerPalette.call, .call)
    }

    func testHoverUsesPresentedMessageRatherThanAFocusHeldNewArrival() throws {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        let focus = FakeFocus()
        let store = LiveActivityStore()
        let controller = MessagingController(adapters: [adapter], liveActivities: store, focus: focus)
        adapter.deliver(MessagingFixtures.message(conversation: "visible", at: 1))
        focus.isFocused = true
        adapter.deliver(MessagingFixtures.message(conversation: "held", at: 2))
        XCTAssertEqual(controller.current?.conversation.id?.nativeID, "held")
        XCTAssertEqual(controller.collapsedEntry?.conversation.id?.nativeID, "visible")
        XCTAssertEqual(store.activities.first?.id, MessagingController.activityID)
    }

    func testDoubleSubmitSendsOnceAndFailureKeepsDraft() async throws {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        adapter.outcomes = [.uncertain(reason: "Await confirmation")]
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "exact", at: 1))
        let entry = try XCTUnwrap(controller.collapsedEntry)
        controller.updateDraft("Reply", for: entry)
        async let first: Void = controller.send(for: entry)
        async let second: Void = controller.send(for: entry)
        _ = await (first, second)
        XCTAssertEqual(adapter.sent.count, 1)
        XCTAssertEqual(controller.draft(for: entry).text, "Reply")
    }

    func testNativeComposerOwnsItsInputRegionAndReleasesItOnUnmount() async throws {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "native", at: 1))
        let entry = try XCTUnwrap(controller.collapsedEntry)
        let layout = IslandLayoutStore()
        _ = NSApplication.shared
        var reportedFrames: [CGRect?] = []
        let composer = MessagingReplyComposer(controller: controller, entry: entry)
            .environment(\.timerRulerInteractionRegistration, TimerRulerInteractionRegistration { owner, frame in
                reportedFrames.append(frame)
                layout.setNativeControlRegion(frame, owner: owner)
            })
            .frame(width: 320, height: 100)
            .coordinateSpace(name: IslandCanvasCoordinateSpace.name)
        let host = NSHostingView(rootView: AnyView(composer))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 320, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.orderOut(nil) }
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        for _ in 0..<50 where layout.nativeControlRegions.isEmpty {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let region = try XCTUnwrap(layout.nativeControlRegions.values.first, "Reported: \(reportedFrames), host bounds: \(host.bounds), visible: \(window.isVisible)")
        XCTAssertTrue(layout.containsNativeControlPoint(CGPoint(x: region.midX, y: region.midY)))
        XCTAssertGreaterThanOrEqual(region.width, 300)
        host.rootView = AnyView(EmptyView())
        host.layoutSubtreeIfNeeded()
        for _ in 0..<50 where !layout.nativeControlRegions.isEmpty {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(layout.nativeControlRegions.isEmpty)
    }

    func testNativeReturnSendsOnceAndEscapeReleasesFocus() async throws {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "native-keyboard", at: 1))
        let entry = try XCTUnwrap(controller.collapsedEntry)
        controller.updateDraft("Fixture reply", for: entry)
        let layout = IslandLayoutStore()
        var dismissed = false
        let view = MessagingReplyComposer(controller: controller, entry: entry,
            onFocus: { layout.setTextInputFocused($0) }, onDismiss: { dismissed = true })
            .frame(width: 320, height: 100)
        let host = NSHostingView(rootView: view)
        let window = CommunicationTestPanel(contentRect: CGRect(x: 100, y: 100, width: 320, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
        func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        let input = try XCTUnwrap(field(in: host))
        window.makeKey()
        XCTAssertTrue(window.makeFirstResponder(input))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(layout.isTextInputFocused)
        func key(_ code: UInt16, _ characters: String) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code))
            window.sendEvent(event)
        }
        try key(36, "\r")
        for _ in 0..<50 where adapter.sent.isEmpty || controller.draft(for: entry).state.isSending {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(adapter.sent.count, 1)
        XCTAssertEqual(adapter.sent.first?.1.nativeID, "native-keyboard")
        XCTAssertEqual(controller.draft(for: entry).text, "")
        try key(36, "\r")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(adapter.sent.count, 1)
        window.makeFirstResponder(input)
        try await Task.sleep(for: .milliseconds(50))
        try key(53, "\u{1b}")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(dismissed)
        XCTAssertFalse(layout.isTextInputFocused)
    }

    func testAllNewSettingsScenariosUseNativeFramesAndInertMessaging() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        for scenario in [LiveActivityLayoutPreviewScenario.activeCall, .connectedCall, .message,
                         .messageReply, .recording, .permissionHover] {
            let display = LiveActivityLayoutSettingsPreview.presentation(settings: settings, scenario: scenario)
            XCTAssertGreaterThan(display.composite.primaryFrame.height, 0)
            XCTAssertGreaterThan(display.canvasSize.height, display.composite.primaryFrame.height)
        }
        let preview = CommunicationPreviewMessages()
        XCTAssertEqual(preview.controller.adapters.count, 1)
        let entry = try XCTUnwrap(preview.controller.collapsedEntry)
        XCTAssertTrue(preview.controller.canReply(to: entry))
        XCTAssertFalse(preview.controller.open(entry))
    }
}

@MainActor
private final class CommunicationTestPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
