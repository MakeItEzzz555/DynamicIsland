import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Real native button/layout fixtures. No provider or packaged-live claim.
@MainActor
final class WorkspaceNativeEditorTests: XCTestCase {
    func testEditorChromeOnlyMountsInEditModeAndDisabledKindsStayUnavailable() async throws {
        let fixture = try Fixture(editing: false, eligible: [.files, .timer])
        defer { fixture.close() }
        await fixture.settle()
        XCTAssertEqual(nativeHandles(in: fixture.host).count, 0, "Ordinary widgets must have no native drag hit layer")
        XCTAssertFalse(fixture.renderedKinds.contains(.media), "A persisted primary widget cannot re-enable a globally disabled feature")
        fixture.renderedKinds = []
        fixture.state.editing = true
        await fixture.settle()
        let labels = nativeHandles(in: fixture.host).map(\.title)
        XCTAssertTrue(labels.contains(IslandWidget.files.title))
        XCTAssertFalse(labels.contains(IslandWidget.media.title))
        XCTAssertFalse(fixture.renderedKinds.contains(.media))
        XCTAssertNotNil(fixture.frames["add.timer"])
        XCTAssertNil(fixture.frames["add.chat"])
        fixture.state.editing = false
        await fixture.settle()
        XCTAssertEqual(nativeHandles(in: fixture.host).count, 0)
    }

    func testNativeAddCancelDoneAndResetOnlyPersistCommittedTransaction() async throws {
        let fixture = try Fixture(editing: true, eligible: [.media, .timer])
        defer { fixture.close() }
        var publications = 0
        let subscription = fixture.store.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        await fixture.settle()
        try await fixture.click("add.timer")
        await fixture.settle()
        XCTAssertTrue(nativeHandles(in: fixture.host).contains { $0.title == IslandWidget.timer.title })
        XCTAssertFalse(fixture.store.configuration.widgets(on: .media).contains { $0.kind == .timer })
        XCTAssertEqual(fixture.store.persistenceWriteCount, 0)
        XCTAssertEqual(publications, 0, "Draft editing must not republish global layout state")
        try await fixture.click("cancel")
        await fixture.settle()
        XCTAssertFalse(fixture.state.editing)
        XCTAssertFalse(fixture.store.configuration.widgets(on: .media).contains { $0.kind == .timer })
        fixture.state.editing = true
        await fixture.settle()
        try await fixture.click("add.timer")
        await fixture.settle()
        try await fixture.click("done")
        await fixture.settle()
        XCTAssertFalse(fixture.state.editing)
        XCTAssertTrue(fixture.store.configuration.widgets(on: .media).contains { $0.kind == .timer })
        XCTAssertEqual(fixture.store.persistenceWriteCount, 1)
        XCTAssertEqual(publications, 1)
        fixture.state.editing = true
        await fixture.settle()
        try await fixture.click("reset")
        await fixture.settle()
        XCTAssertTrue(fixture.store.configuration.widgets(on: .media).contains { $0.kind == .timer }, "Reset remains a reversible draft until Done")
        try await fixture.click("done")
        await fixture.settle()
        XCTAssertFalse(fixture.store.configuration.widgets(on: .media).contains { $0.kind == .timer })
        XCTAssertEqual(fixture.store.persistenceWriteCount, 2)
    }

    func testNativeDragSourceDismantlingReleasesCallbacksAndUsesDedicatedPayloadType() {
        final class Lifetime {}
        weak var lifetime: Lifetime?
        let view = WorkspaceNativeDragView()
        do {
            let token = Lifetime()
            lifetime = token
            view.began = { _ = token }
            view.ended = { _ = token }
        }
        XCTAssertNotNil(lifetime)
        WorkspaceNativeDragHandle.dismantleNSView(view, coordinator: ())
        XCTAssertNil(lifetime, "Removed handles must not retain editor closures or controllers")
        XCTAssertEqual(WorkspaceNativeDragHandle.type.identifier, "app.dynamicisland.workspace-widget")
        XCTAssertNotEqual(WorkspaceNativeDragHandle.type.identifier, "public.text")
        XCTAssertNil(WorkspaceEditorMotion.reorder(reduceMotion: true))
        XCTAssertEqual(WorkspaceEditorMotion.reorderDuration, 0.25)
        XCTAssertEqual(WorkspaceEditorMotion.resizeDuration, 0.30)
    }

    func testTwoHundredHoverResolutionsNeverPublishOrPersistGlobalState() throws {
        let suite = "DynamicIsland.WorkspaceHover.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkspaceCustomizationStore(defaults: defaults)
        let original = store.configuration
        let placements = original.widgets(on: .media)
        let slots = placements.enumerated().map { index, widget in
            WorkspaceDropSlot(id: widget.id, frame: CGRect(x: index * 208, y: 0, width: 200, height: 240), kind: widget.kind)
        }
        var publications = 0
        let token = store.objectWillChange.sink { publications += 1 }
        defer { token.cancel() }
        var prior: WorkspaceDropTarget?
        let start = ContinuousClock.now
        for index in 0..<200 {
            let point = CGPoint(x: 308 + (index.isMultiple(of: 2) ? -1 : 1), y: 120)
            let target = WorkspaceDropResolver.resolve(point: point, bounds: CGRect(x: 0, y: 0, width: 616, height: 240),
                surface: .media, slots: slots, draggedKind: placements[0].kind, previous: prior)
            if let prior { XCTAssertEqual(target, prior, "Boundary hover should retain its insertion target") }
            let preview = try XCTUnwrap(WorkspaceDropResolver.applying(target, to: original, draggedID: placements[0].id, paletteKind: nil))
            XCTAssertEqual(Set(preview.widgets(on: .media).map(\.id)), Set(placements.map(\.id)))
            prior = target
        }
        let duration = start.duration(to: .now)
        print("Workspace fixture: 200 frozen-slot hover/preview resolutions \(duration), publications=\(publications), writes=\(store.persistenceWriteCount)")
        XCTAssertEqual(store.configuration, original)
        XCTAssertEqual(store.persistenceWriteCount, 0)
        XCTAssertEqual(publications, 0)
    }

    func testRepeatedNativeEditCyclesKeepHandlesBoundedAndReleaseRemovedViews() async throws {
        let fixture = try Fixture(editing: false, eligible: [.files, .timer])
        defer { fixture.close() }
        AgentPerformanceProbe.reset()
        weak var removedHandle: WorkspaceNativeDragView?
        for _ in 0..<20 {
            fixture.state.editing = true
            await fixture.settle()
            let handles = nativeHandles(in: fixture.host)
            XCTAssertEqual(handles.count, 2, "One visible widget and one available palette drag source")
            removedHandle = handles.first
            fixture.state.editing = false
            await fixture.settle()
            XCTAssertEqual(nativeHandles(in: fixture.host).count, 0)
        }
        await fixture.settle()
        XCTAssertNil(removedHandle, "Edit-only native sources must not survive removal")
        XCTAssertEqual(fixture.store.persistenceWriteCount, 0)
        let bodies = AgentPerformanceProbe.snapshot().counters["workspace.editor.body", default: 0]
        print("Workspace fixture: 20 edit/cancel cycles, editor bodies=\(bodies), live drag handles=0, writes=0")
        XCTAssertLessThanOrEqual(bodies, 100, "Geometry measurements must not create a frame-driven render loop")
    }

    private func nativeHandles(in view: NSView) -> [WorkspaceNativeDragView] {
        (view as? WorkspaceNativeDragView).map { [$0] } ?? view.subviews.flatMap { nativeHandles(in: $0) }
    }

    @MainActor
    private final class EditorState: ObservableObject { @Published var editing: Bool; init(_ value: Bool) { editing = value } }
    private struct FixtureView: View {
        @ObservedObject var state: EditorState
        let store: WorkspaceCustomizationStore
        let eligible: [IslandWidget]
        let rendered: (IslandWidget) -> Void
        let frames: ([String: CGRect]) -> Void
        var body: some View {
            IslandWidgetEditor(store: store, surface: .media, editing: $state.editing, eligibleWidgets: eligible, extraMotion: false) { region, height in
                for widget in region.widgets { rendered(widget.kind) }
                return AnyView(Text(region.widgets.map { $0.kind.title }.joined(separator: " + ")).frame(maxWidth: .infinity, maxHeight: .infinity))
            }
            .frame(width: 600, height: 300)
            .onPreferenceChange(WorkspaceEditorActionFrames.self, perform: frames)
        }
    }
    @MainActor
    private final class Fixture {
        let store: WorkspaceCustomizationStore
        let state: EditorState
        let window: NSWindow
        var host: NSHostingView<FixtureView>!
        var frames: [String: CGRect] = [:]
        var renderedKinds: [IslandWidget] = []
        let defaults: UserDefaults
        let suite: String
        init(editing: Bool, eligible: [IslandWidget]) throws {
            _ = NSApplication.shared
            suite = "DynamicIsland.WorkspaceNativeEditorTests.\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            store = WorkspaceCustomizationStore(defaults: defaults)
            state = EditorState(editing)
            window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 600, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host = NSHostingView(rootView: FixtureView(state: state, store: store, eligible: eligible,
                rendered: { [weak self] in self?.renderedKinds.append($0) }, frames: { [weak self] in self?.frames = $0 }))
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
        }
        func settle() async {
            for _ in 0..<8 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(2))
                host.layoutSubtreeIfNeeded()
            }
        }
        func click(_ action: String) async throws {
            let frame = try XCTUnwrap(frames[action], "Missing native button layout: \(action)")
            let point = host.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            }
            // AppKit-backed buttons (.borderedProminent) track the mouse until a
            // queued mouse-up arrives, so it must be queued before mouse-down.
            NSApp.postEvent(try event(.leftMouseUp), atStart: false)
            window.sendEvent(try event(.leftMouseDown))
            try await Task.sleep(for: .milliseconds(20))
            // SwiftUI plain buttons do not track; deliver the queued up if unconsumed.
            if let pending = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                window.sendEvent(pending)
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        func close() {
            window.orderOut(nil)
            window.contentView = nil
            host = nil
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
