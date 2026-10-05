import XCTest
@testable import DynamicIsland

final class WorkspaceAdaptiveSizingTests: XCTestCase {
    private let metrics = ResolvedIslandMetrics.fallback
    private func regions(_ kinds: [IslandWidget], surface: WorkspaceSurface = .media) -> [WorkspaceWidgetRegion] {
        WorkspaceConfiguration(placements: kinds.enumerated().map {
            .init(kind: $0.element, surface: surface, order: $0.offset)
        }).normalized().regions(on: surface)
    }
    func testOneTimerHasIntrinsicFootprintAndIsCenteredWithoutOldRowAllocation() throws {
        let widgets = regions([.timer])
        let required = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: widgets,
            maximumSize: .init(width: 1200, height: 800), metrics: metrics)
        XCTAssertLessThan(required.width, 400)
        XCTAssertLessThan(required.height, 200)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: widgets,
            availableSize: .init(width: 900, height: 400), metrics: metrics)
        let frame = try XCTUnwrap(projection.frames.first?.frame)
        XCTAssertEqual(frame.midX, 450, accuracy: 0.01)
        XCTAssertEqual(frame.midY, 200, accuracy: 0.01)
        XCTAssertEqual(frame.width, required.width, accuracy: 0.01)
        XCTAssertEqual(frame.height, required.height, accuracy: 0.01)
        XCTAssertEqual(projection.rows, 1)
        XCTAssertFalse(projection.requiresScrolling)
    }
    func testAddingAndRemovingWidgetsChangesRequiredShellContentBudget() {
        let one = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions([.timer]),
            maximumSize: .init(width: 1200, height: 900), metrics: metrics)
        let two = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions([.timer, .media]),
            maximumSize: .init(width: 1200, height: 900), metrics: metrics)
        let many = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions([.media, .timer, .files, .clipboard, .calendar, .shortcuts, .activities]),
            maximumSize: .init(width: 900, height: 900), metrics: metrics)
        XCTAssertGreaterThan(two.width, one.width)
        XCTAssertGreaterThan(two.height, one.height)
        XCTAssertGreaterThan(many.height, two.height)
        XCTAssertLessThanOrEqual(many.width, 900)
        XCTAssertLessThanOrEqual(many.height, 900)
    }
    func testAllEligibleMediaWidgetsFitStableRowsAcrossDisplayBudgets() {
        let widgets = regions([.media, .timer, .files, .clipboard, .calendar, .shortcuts, .activities, .workspace])
        for width in [CGFloat(360), 520, 860, 1200] {
            for height in [CGFloat(400), 900] {
                let projection = WorkspaceWidgetLayoutProjection.make(regions: widgets,
                    availableSize: .init(width: width, height: height), metrics: metrics)
                XCTAssertEqual(projection.frames.map(\.id), widgets.map(\.id))
                XCTAssertGreaterThan(projection.rows, 1)
                for frame in projection.frames {
                    XCTAssertGreaterThan(frame.frame.width, 0)
                    XCTAssertGreaterThan(frame.frame.height, 0)
                    XCTAssertGreaterThanOrEqual(frame.frame.minX, -0.01)
                    XCTAssertLessThanOrEqual(frame.frame.maxX, width + 0.01)
                    XCTAssertLessThanOrEqual(frame.frame.maxY, projection.contentSize.height + 0.01)
                }
                for (index, first) in projection.frames.enumerated() {
                    for second in projection.frames.dropFirst(index + 1) {
                        XCTAssertFalse(first.frame.intersects(second.frame), "Visible widgets must never overlap")
                    }
                }
            }
        }
    }
    func testChatFeedUseWeightedReadableColumnsAndStackUsesOneRegion() throws {
        let pair = regions([.chat, .feed], surface: .agents)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: pair,
            availableSize: .init(width: 860, height: 400), metrics: metrics)
        XCTAssertEqual(projection.columns, 2)
        let chat = try XCTUnwrap(projection.frames.first { $0.id == WidgetID("agents.chat") })
        let feed = try XCTUnwrap(projection.frames.first { $0.id == WidgetID("agents.feed") })
        XCTAssertGreaterThan(chat.frame.width, feed.frame.width * 1.5)
        XCTAssertGreaterThanOrEqual(chat.frame.width, 480 * metrics.expandedCardScale - 0.01)
        var configuration = WorkspaceConfiguration.initial
        configuration.remove(configuration.placement(kind: .feed, on: .agents)!.id)
        configuration.add(.terminal, on: .agents)
        configuration.combineTerminalWithChat()
        let stack = WorkspaceWidgetLayoutProjection.make(regions: configuration.regions(on: .agents),
            availableSize: .init(width: 860, height: 500), metrics: metrics)
        XCTAssertEqual(stack.frames.count, 1)
        XCTAssertEqual(stack.frames.first?.id, configuration.groups.first?.id)
        XCTAssertGreaterThan(stack.frames[0].frame.height, 360 * metrics.expandedCardScale)
    }
    func testConfiguredSizePersistsAndLegacyOrUnknownSizeDecodesToStandard() throws {
        var configuration = WorkspaceConfiguration.initial
        let id = configuration.placement(kind: .media, on: .media)!.id
        configuration.setSize(.large, for: id)
        let encoded = try JSONEncoder().encode(configuration)
        XCTAssertEqual(WorkspaceConfiguration.decoded(encoded).placement(kind: .media, on: .media)?.size, .large)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var placements = try XCTUnwrap(json["placements"] as? [[String: Any]])
        for index in placements.indices { placements[index].removeValue(forKey: "size") }
        json["placements"] = placements
        let legacy = WorkspaceConfiguration.decoded(try JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.placements.allSatisfy { $0.size == .standard })
        placements[0]["size"] = "future-size"
        json["placements"] = placements
        let unknown = WorkspaceConfiguration.decoded(try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(unknown.placement(kind: .media, on: .media)?.size, .standard)
        XCTAssertEqual(unknown.placements.count, configuration.placements.count)
    }
    func testSizeChangesRequirementsWithoutChangingWidgetOrGroupIdentity() {
        var configuration = WorkspaceConfiguration.initial
        configuration.add(.terminal, on: .agents)
        configuration.combineTerminalWithChat()
        let groupID = configuration.groups[0].id
        let members = configuration.groups[0].members
        let ids = configuration.placements.map(\.id)
        let standard = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: configuration.regions(on: .agents),
            maximumSize: .init(width: 1800, height: 1000), metrics: metrics)
        configuration.setSize(.large, for: groupID)
        let large = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: configuration.regions(on: .agents),
            maximumSize: .init(width: 1800, height: 1000), metrics: metrics)
        XCTAssertGreaterThan(large.width, standard.width)
        XCTAssertGreaterThan(large.height, standard.height)
        XCTAssertEqual(configuration.placements.map(\.id), ids)
        XCTAssertEqual(configuration.groups[0].members, members)
        XCTAssertEqual(configuration.groups[0].id, groupID)
    }
    func testEditChromeReservesSpaceWithoutOverlappingWidgetsOrPalette() {
        let widgets = regions([.media, .timer])
        let normal = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: widgets,
            maximumSize: .init(width: 1200, height: 800), metrics: metrics)
        let edited = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: widgets,
            maximumSize: .init(width: 1200, height: 800), metrics: metrics, editing: true)
        XCTAssertGreaterThan(edited.width, normal.width)
        XCTAssertGreaterThan(edited.height, normal.height)
        let layout = WorkspaceWidgetLayoutProjection.make(regions: widgets,
            availableSize: edited, metrics: metrics, editing: true)
        XCTAssertFalse(layout.requiresScrolling)
        XCTAssertLessThanOrEqual(layout.frames.map { $0.frame.maxY }.max() ?? 0,
            edited.height - 54 - metrics.spacing(8) + 0.01)
    }
    func testMultiRowDropUsesPointerRowAndBoundaryHysteresis() {
        let slots: [WorkspaceDropSlot] = [
            .init(id: WidgetID("a"), frame: .init(x: 0, y: 0, width: 200, height: 150), kind: .media),
            .init(id: WidgetID("b"), frame: .init(x: 210, y: 0, width: 200, height: 150), kind: .files),
            .init(id: WidgetID("c"), frame: .init(x: 0, y: 160, width: 200, height: 150), kind: .timer),
            .init(id: WidgetID("d"), frame: .init(x: 210, y: 160, width: 200, height: 150), kind: .clipboard)]
        let bounds = CGRect(x: 0, y: 0, width: 410, height: 310)
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 10, y: 220), bounds: bounds,
            surface: .media, slots: slots.reversed(), draggedKind: .calendar), .insert(surface: .media, before: WidgetID("c")))
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 400, y: 100), bounds: bounds,
            surface: .media, slots: slots, draggedKind: .calendar), .insert(surface: .media, before: WidgetID("c")))
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 10, y: 153), bounds: bounds,
            surface: .media, slots: slots, draggedKind: .calendar,
            previous: .insert(surface: .media, before: WidgetID("a"))), .insert(surface: .media, before: WidgetID("a")))
    }
    func testInvalidScreenBudgetsRemainFiniteAndRecoverable() {
        let widgets = regions([.timer])
        let projection = WorkspaceWidgetLayoutProjection.make(regions: widgets,
            availableSize: .init(width: CGFloat.nan, height: CGFloat.infinity), metrics: metrics)
        XCTAssertTrue(projection.contentSize.width.isFinite)
        XCTAssertTrue(projection.contentSize.height.isFinite)
        XCTAssertEqual(projection.frames.count, 1)
        XCTAssertGreaterThan(projection.frames[0].frame.width, 0)
    }
}
