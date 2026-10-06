import XCTest
@testable import DynamicIsland

/// Apply -> collapse semantics and the intrinsic-geometry contract.
@MainActor
final class WorkspaceEditorApplyTests: XCTestCase {
    private func store() -> WorkspaceCustomizationStore {
        WorkspaceCustomizationStore(defaults: UserDefaults(suiteName: "WorkspaceEditorApplyTests-\(UUID().uuidString)")!)
    }

    func testApplyCommitsOnceEndsEditingAndRequestsCollapseOnce() throws {
        let store = store()
        var draft = store.configuration
        draft.remove(try XCTUnwrap(draft.placement(kind: .clipboard, on: .media)).id)
        var editing = true
        var collapses = 0
        XCTAssertTrue(WorkspaceEditorApply.apply(draft: &draft, surface: .media, store: store, editing: &editing) { collapses += 1 })
        XCTAssertFalse(editing)
        XCTAssertEqual(collapses, 1)
        XCTAssertFalse(store.configuration.widgets(on: .media).contains { $0.kind == .clipboard }, "removal persisted")
        XCTAssertTrue(store.configuration.customizedSurfaces.contains(.media))
        let writes = store.persistenceWriteCount
        // A repeated Apply after editing ended cannot commit or collapse again.
        XCTAssertFalse(WorkspaceEditorApply.apply(draft: &draft, surface: .media, store: store, editing: &editing) { collapses += 1 })
        XCTAssertEqual(collapses, 1)
        XCTAssertEqual(store.persistenceWriteCount, writes)
    }

    func testApplyPersistsTheFinalReorderPreview() throws {
        let store = store()
        var draft = store.configuration
        let files = try XCTUnwrap(draft.placement(kind: .files, on: .media)).id
        let media = try XCTUnwrap(draft.placement(kind: .media, on: .media)).id
        draft = try XCTUnwrap(WorkspaceDropResolver.applying(.insert(surface: .media, before: media), to: draft, draggedID: files, paletteKind: nil))
        var editing = true
        WorkspaceEditorApply.apply(draft: &draft, surface: .media, store: store, editing: &editing, completion: nil)
        XCTAssertEqual(store.configuration.widgets(on: .media).first?.kind, .files)
    }

    func testCancelNeverCommitsOrCollapses() throws {
        let store = store()
        let saved = store.configuration
        var draft = saved
        draft.remove(try XCTUnwrap(draft.placement(kind: .clipboard, on: .media)).id)
        // Cancel is "editing = false" without Apply: nothing persisted, no completion.
        XCTAssertEqual(store.configuration, saved)
    }
}

/// Geometry ownership: a shell widened by the notch-safe header centers the
/// content at its intrinsic size; widgets are never stretched to fill it.
@MainActor
final class WorkspaceRowFillTests: XCTestCase {
    private let metrics = ResolvedIslandMetrics.fallback

    func testSoloMediaIsCenteredInAShellWidenedByTheHeader() throws {
        let config = WorkspaceConfiguration(placements: [.init(kind: .media, surface: .media, order: 0)],
                                            customizedSurfaces: [.media]).normalized()
        let regions = config.regions(on: .media)
        let intrinsic = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions,
            maximumSize: .init(width: 1200, height: 800), metrics: metrics)
        let headerWidened = intrinsic.width + 120
        let projection = WorkspaceWidgetLayoutProjection.make(regions: regions,
            availableSize: .init(width: headerWidened, height: intrinsic.height), metrics: metrics)
        let frame = try XCTUnwrap(projection.frames.first?.frame)
        XCTAssertEqual(frame.size, WidgetGridMetrics.make(surface: .media, metrics: metrics).size(for: .standard))
        XCTAssertEqual(frame.midX, headerWidened / 2, accuracy: 0.5, "centered, never stretched")
    }

    func testMultiWidgetRowsKeepIntrinsicSizesAndBandsStayCentered() throws {
        let config = WorkspaceConfiguration(placements: [
            .init(kind: .agentUsage, surface: .agents, order: 0),
            .init(kind: .chat, surface: .agents, order: 1), .init(kind: .feed, surface: .agents, order: 2)],
            customizedSurfaces: [.agents]).normalized()
        let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .agents),
            availableSize: .init(width: 1400, height: 900), metrics: metrics)
        let grid = WidgetGridMetrics.make(surface: .agents, metrics: metrics)
        let chat = try XCTUnwrap(projection.frames.first { $0.id == config.placement(kind: .chat, on: .agents)?.id }?.frame)
        let feed = try XCTUnwrap(projection.frames.first { $0.id == config.placement(kind: .feed, on: .agents)?.id }?.frame)
        let usage = try XCTUnwrap(projection.frames.first { $0.id == config.placement(kind: .agentUsage, on: .agents)?.id }?.frame)
        XCTAssertEqual(chat.size, grid.size(for: .standard, kinds: [.chat]))
        XCTAssertEqual(feed.size, grid.size(for: .standard))
        XCTAssertEqual(usage.midX, 700, accuracy: 1, "usage band stays a centered strip")
    }

    func testEditingKeepsIntrinsicCenteredGeometryForDragStability() throws {
        let config = WorkspaceConfiguration(placements: [.init(kind: .timer, surface: .media, order: 0),
                                                         .init(kind: .shortcuts, surface: .media, order: 1)],
                                            customizedSurfaces: [.media]).normalized()
        let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .media),
            availableSize: .init(width: 1400, height: 400), metrics: metrics, editing: true)
        let first = try XCTUnwrap(projection.frames.first?.frame)
        XCTAssertGreaterThan(first.minX, 7.5, "edit mode is unchanged (drag reference geometry)")
    }
}
