import XCTest
@testable import DynamicIsland

final class WorkspaceDropResolverTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 300)
    private var slots: [WorkspaceDropSlot] {
        [.init(id: WidgetID("agents.chat"), frame: CGRect(x: 0, y: 0, width: 290, height: 300), kind: .chat),
         .init(id: WidgetID("agents.feed"), frame: CGRect(x: 310, y: 0, width: 290, height: 300), kind: .feed)]
    }
    func testMidpointInsertionIndependentOfSlotInputOrder() {
        let before = WorkspaceDropResolver.resolve(point: .init(x: 15, y: 10), bounds: bounds,
            surface: .agents, slots: slots.reversed(), draggedKind: .timer)
        XCTAssertEqual(before, .insert(surface: .agents, before: WidgetID("agents.chat")))
        let between = WorkspaceDropResolver.resolve(point: .init(x: 300, y: 10), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .timer)
        XCTAssertEqual(between, .insert(surface: .agents, before: WidgetID("agents.feed")))
        let after = WorkspaceDropResolver.resolve(point: .init(x: 590, y: 10), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .timer)
        XCTAssertEqual(after, .insert(surface: .agents, before: nil))
    }
    func testBoundaryHysteresisDoesNotOscillate() {
        let prior = WorkspaceDropTarget.insert(surface: .agents, before: WidgetID("agents.chat"))
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 149, y: 5), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .timer, previous: prior), prior)
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 156, y: 5), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .timer, previous: prior),
                       .insert(surface: .agents, before: WidgetID("agents.feed")))
    }
    func testAppendAndCombineTargetsAlsoUseBoundaryHysteresis() {
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 450, y: 5), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .timer,
            previous: .insert(surface: .agents, before: nil)), .insert(surface: .agents, before: nil))
        // Combine is Chat's center (x 87...203 here); hysteresis keeps it 8 pt beyond.
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 82, y: 150), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .terminal,
            previous: .combine(chat: WidgetID("agents.chat"))), .combine(chat: WidgetID("agents.chat")))
        XCTAssertNotEqual(WorkspaceDropResolver.resolve(point: .init(x: 82, y: 150), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .terminal), .combine(chat: WidgetID("agents.chat")))
    }

    func testCenterCombinesTerminalAndEdgeInsertsBesideChat() {
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 145, y: 150), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .terminal), .combine(chat: WidgetID("agents.chat")))
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 10, y: 150), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .terminal),
                       .insert(surface: .agents, before: WidgetID("agents.chat")))
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 145, y: 150), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .timer),
                       .insert(surface: .agents, before: WidgetID("agents.feed")))
    }
    func testOutsideOrUnsupportedDropIsInvalidAndNeverMutatesOriginal() {
        let original = WorkspaceConfiguration.initial
        let target = WorkspaceDropResolver.resolve(point: .init(x: -1, y: 100), bounds: bounds,
            surface: .agents, slots: slots, draggedKind: .terminal)
        XCTAssertEqual(target, .invalid)
        XCTAssertNil(WorkspaceDropResolver.applying(target, to: original, draggedID: nil, paletteKind: .terminal))
        XCTAssertEqual(original, .initial)
        XCTAssertEqual(WorkspaceDropResolver.resolve(point: .init(x: 100, y: 100), bounds: bounds,
            surface: .media, slots: [], draggedKind: .terminal), .invalid)
    }
    func testAddPreviewCommitsOneSingletonAndDoesNotAffectOriginal() throws {
        let original = WorkspaceConfiguration.initial
        let target = WorkspaceDropTarget.insert(surface: .agents, before: WidgetID("agents.feed"))
        let preview = try XCTUnwrap(WorkspaceDropResolver.applying(target, to: original, draggedID: nil, paletteKind: .terminal))
        XCTAssertEqual(preview.widgets(on: .agents).map(\.kind), [.agentUsage, .chat, .terminal, .feed])
        XCTAssertFalse(original.widgets(on: .agents).contains { $0.kind == .terminal })
        let repeated = try XCTUnwrap(WorkspaceDropResolver.applying(target, to: preview, draggedID: nil, paletteKind: .terminal))
        XCTAssertEqual(repeated, preview)
    }
    func testCombinePreviewAndSeparateToValidSlotKeepIDs() throws {
        var original = WorkspaceConfiguration.initial
        original.add(.terminal, on: .agents)
        let terminal = original.placement(kind: .terminal, on: .agents)!.id
        let chat = original.placement(kind: .chat, on: .agents)!.id
        let combined = try XCTUnwrap(WorkspaceDropResolver.applying(.combine(chat: chat), to: original,
            draggedID: terminal, paletteKind: nil))
        XCTAssertEqual(combined.groups.count, 1)
        XCTAssertEqual(combined.placement(kind: .terminal, on: .agents)?.id, terminal)
        let separated = try XCTUnwrap(WorkspaceDropResolver.applying(.insert(surface: .agents, before: nil),
            to: combined, draggedID: terminal, paletteKind: nil))
        XCTAssertTrue(separated.groups.isEmpty)
        XCTAssertEqual(separated.placement(kind: .terminal, on: .agents)?.id, terminal)
        XCTAssertEqual(separated.placement(kind: .chat, on: .agents)?.id, chat)
    }
    func testCrossSurfaceTimerMoveKeepsIdentityAndRejectsAmbiguousSingleton() throws {
        var original = WorkspaceConfiguration.initial
        original.add(.timer, on: .media)
        let timer = original.placement(kind: .timer, on: .media)!.id
        let moved = try XCTUnwrap(WorkspaceDropResolver.applying(.insert(surface: .agents, before: nil),
            to: original, draggedID: timer, paletteKind: nil))
        XCTAssertEqual(moved.placement(kind: .timer, on: .agents)?.id, timer)
        XCTAssertFalse(moved.widgets(on: .media).contains { $0.kind == .timer })
        original.add(.timer, on: .agents)
        XCTAssertNil(WorkspaceDropResolver.applying(.insert(surface: .agents, before: nil),
            to: original, draggedID: timer, paletteKind: nil))
        XCTAssertNil(WorkspaceDropResolver.applying(.insert(surface: .media, before: nil),
            to: original, draggedID: WidgetID("agents.chat"), paletteKind: nil))
        XCTAssertNil(WorkspaceDropResolver.applying(.insert(surface: .agents, before: WidgetID("missing")),
            to: original, draggedID: timer, paletteKind: nil))
    }

}
