import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
private final class WorkspaceEditorHostedView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Real native button/layout fixtures. No provider or packaged-live claim.
@MainActor
final class WorkspaceNativeEditorTests: XCTestCase {
    func testNativeDragCallbacksHoldFootprintAndExternalEditExitReleasesIt() async throws {
        let fixture = try Fixture(editing: true, eligible: [.media, .timer])
        defer { fixture.close() }
        await fixture.settle()
        let footprint = fixture.layout.expandedSize
        let handle = try XCTUnwrap(nativeHandles(in: fixture.host).first)
        handle.began()
        await fixture.settle()
        XCTAssertEqual(fixture.layout.workspacePresentationSize(.init(width: 900, height: 500)), footprint)
        XCTAssertEqual(fixture.layout.workspacePresentationSize(.init(width: 300, height: 180)), footprint)
        handle.ended()
        await fixture.settle()
        XCTAssertNil(fixture.layout.workspaceDragSize)

        let replacement = try XCTUnwrap(nativeHandles(in: fixture.host).first)
        replacement.began()
        await fixture.settle()
        fixture.state.editing = false
        await fixture.settle()
        XCTAssertNil(fixture.layout.workspaceDragSize, "Leaving edit mode must release even when AppKit retires the drag source")
        XCTAssertNil(fixture.layout.workspaceLayoutPreview)
        XCTAssertEqual(fixture.store.persistenceWriteCount, 0)
    }

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

    func testHostedHoverKeepsEveryOccupiedSlotFixedAndDropUpdatesOnlyDraft() async throws {
        let fixture = try Fixture(editing: true, eligible: [.media, .timer])
        defer { fixture.close() }
        await fixture.settle()
        try await fixture.click("add.timer")
        await fixture.settle()
        let original = fixture.layout.workspaceLayoutPreview
        let frames = fixture.widgetFrames
        _ = try XCTUnwrap(frames[WidgetID("__editor.canvas")])
        let handle = try XCTUnwrap(nativeHandles(in: fixture.host).first { $0.title == IslandWidget.media.title })
        handle.began()
        await fixture.settle()
        let callbacks = try XCTUnwrap(fixture.dropInteraction)
        let timerID = try XCTUnwrap(original?.configuration.widgets(on: .media).first { $0.kind == .timer }?.id)
        let timer = try XCTUnwrap(frames[timerID], "Measured slots: \(frames)")
        let point = CGPoint(x: timer.maxX - 4, y: timer.midY)
        for _ in 0..<12 {
            XCTAssertTrue(callbacks.updated(point))
            await fixture.settle()
            XCTAssertEqual(fixture.widgetFrames, frames, "Hover must not move, resize or scale any occupied slot")
            XCTAssertEqual(fixture.layout.workspaceLayoutPreview, original, "Hover must not publish prospective layouts")
            XCTAssertEqual(fixture.store.persistenceWriteCount, 0)
        }
        XCTAssertTrue(callbacks.dropped(point))
        await fixture.settle()
        XCTAssertNotEqual(fixture.layout.workspaceLayoutPreview, original, "Release commits one draft reorder")
        XCTAssertNil(fixture.layout.workspaceDragSize)
        XCTAssertEqual(fixture.store.persistenceWriteCount, 0, "Drop is reversible until Done")
        try await fixture.click("cancel")
        await fixture.settle()
        XCTAssertFalse(fixture.state.editing, "The native Cancel button must end the editing session")
        XCTAssertNil(fixture.layout.workspaceLayoutPreview)
        XCTAssertEqual(fixture.store.persistenceWriteCount, 0)
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
        XCTAssertEqual(WorkspaceEditorMotion.reorderDuration, 0.32)
        XCTAssertEqual(WorkspaceEditorMotion.resizeDuration, 0.36)
        XCTAssertNil(WorkspaceEditorMotion.resize(reduceMotion: true))
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
        let layout: IslandLayoutStore
        let eligible: [IslandWidget]
        let rendered: (IslandWidget) -> Void
        let frames: ([String: CGRect]) -> Void
        let widgetFrames: ([WidgetID: CGRect]) -> Void
        let dropInteraction: (WorkspaceEditorDropInteraction?) -> Void
        let actionAnchor: (String, NSView) -> Void
        var body: some View {
            IslandWidgetEditor(store: store, surface: .media, editing: $state.editing, eligibleWidgets: eligible, extraMotion: false,
                onLayoutPreview: { layout.setWorkspaceLayoutPreview($0, surface: .media) },
                onDragActive: { layout.setWorkspaceDragActive($0) }, onDropInteraction: dropInteraction,
                onNativeActionAnchor: actionAnchor) { region, height in
                for widget in region.widgets { rendered(widget.kind) }
                return AnyView(Text(region.widgets.map { $0.kind.title }.joined(separator: " + ")).frame(maxWidth: .infinity, maxHeight: .infinity))
            }
            .frame(width: 600, height: 300)
            .onPreferenceChange(WorkspaceEditorActionFrames.self, perform: frames)
            .onPreferenceChange(WorkspaceEditorFrameKey.self, perform: widgetFrames)
        }
    }
    @MainActor
    private final class Fixture {
        let store: WorkspaceCustomizationStore
        let state: EditorState
        let layout = IslandLayoutStore()
        let window: CameraHostedWindow
        var host: NSHostingView<FixtureView>!
        var router: CameraInteractionRouter!
        var frames: [String: CGRect] = [:]
        var widgetFrames: [WidgetID: CGRect] = [:]
        var dropInteraction: WorkspaceEditorDropInteraction?
        let actionAnchors = NSMapTable<NSString, NSView>(keyOptions: .strongMemory, valueOptions: .weakMemory)
        var renderedKinds: [IslandWidget] = []
        let defaults: UserDefaults
        let suite: String
        init(editing: Bool, eligible: [IslandWidget]) throws {
            _ = NSApplication.shared
            suite = "DynamicIsland.WorkspaceNativeEditorTests.\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            store = WorkspaceCustomizationStore(defaults: defaults)
            state = EditorState(editing)
            window = CameraHostedWindow(contentRect: CGRect(x: -1500, y: -1500, width: 600, height: 300),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.becomesKeyOnlyIfNeeded = false
            window.hidesOnDeactivate = false
            layout.expandedSize = CGSize(width: 600, height: 300)
            host = WorkspaceEditorHostedView(rootView: FixtureView(state: state, store: store, layout: layout, eligible: eligible,
                rendered: { [weak self] in self?.renderedKinds.append($0) }, frames: { [weak self] in self?.frames = $0 },
                widgetFrames: { [weak self] in self?.widgetFrames = $0 },
                dropInteraction: { [weak self] in self?.dropInteraction = $0 },
                actionAnchor: { [weak self] action, view in self?.actionAnchors.setObject(view, forKey: action as NSString) }))
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        }
        func settle() async {
            for _ in 0..<12 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(5))
                host.layoutSubtreeIfNeeded()
            }
            CameraNativeHostedFixture.pump()
            host.layoutSubtreeIfNeeded()
        }
        func click(_ action: String) async throws {
            await settle()
            window.makeKey()
            window.makeFirstResponder(host)
            let anchor = try XCTUnwrap(actionAnchors.object(forKey: action as NSString), "Missing native button anchor: \(action)")
            XCTAssertTrue(anchor.window === window)
            let point = anchor.convert(CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
            XCTAssertTrue(window.isVisible, "Native fixture must remain visible")
            XCTAssertFalse(router.physicalOwnsInput, "Fixture must isolate external physical input")
            var delivered: [NSEvent.EventType] = []
            let gate = window.cameraEventGate
            window.cameraEventGate = { event in
                let accepted = gate?(event) != false
                if accepted && CameraInteractionRouter.isCameraEvent(event) { delivered.append(event.type) }
                return accepted
            }
            defer { window.cameraEventGate = gate }
            CameraNativeHostedFixture.click(router, at: point)
            XCTAssertEqual(delivered, [.leftMouseDown, .leftMouseUp], "Exactly one native lifecycle must reach \(action) at \(point), anchor bounds \(anchor.bounds)")
        }
        func close() {
            router.shutdown()
            CameraNativeHostedFixture.pump()
            router = nil
            dropInteraction = nil
            window.orderOut(nil)
            window.contentView = nil
            host = nil
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
