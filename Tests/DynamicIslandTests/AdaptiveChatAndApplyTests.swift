import XCTest
@testable import DynamicIsland

/// Content-adaptive Agent Chat height and Apply -> collapse semantics.
@MainActor
final class AdaptiveChatHeightTests: XCTestCase {
    private let metrics = ResolvedIslandMetrics.fallback
    private var cap: CGFloat { IslandWidget.chat.layoutTraits.preferred.height * metrics.expandedCardScale }

    func testPreferredCellIsChromePlusContentAndQuantized() {
        // 360 pt cell, 230 pt transcript viewport -> 130 pt chrome.
        XCTAssertEqual(AgentChatHeightPolicy.preferredCellHeight(cellHeight: 360, viewportHeight: 230, contentHeight: 0), 140)
        XCTAssertEqual(AgentChatHeightPolicy.preferredCellHeight(cellHeight: 360, viewportHeight: 230, contentHeight: 41), 180,
                       "one short message: 130 + 41 + 8 rounded up to the 4 pt quantum")
        XCTAssertEqual(AgentChatHeightPolicy.preferredCellHeight(cellHeight: 360, viewportHeight: 230, contentHeight: 600), 740,
                       "long transcripts exceed the cap; callers clamp")
        XCTAssertNil(AgentChatHeightPolicy.preferredCellHeight(cellHeight: 0, viewportHeight: 230, contentHeight: 10))
        XCTAssertNil(AgentChatHeightPolicy.preferredCellHeight(cellHeight: 360, viewportHeight: .nan, contentHeight: 10))
    }

    func testMeasurementIsStableWhileTheShellAnimates() {
        // Cell and viewport shrink together; content (same width) is unchanged.
        let values = stride(from: 360.0, through: 190.0, by: -10).map { cell in
            AgentChatHeightPolicy.preferredCellHeight(cellHeight: cell, viewportHeight: cell - 130, contentHeight: 52)
        }
        XCTAssertEqual(Set(values.compactMap { $0 }).count, 1, "no oscillation: the preferred height never depends on the animating cell")
    }

    func testStreamingGrowthPublishesOnlyOnQuantizedChanges() {
        var published: [CGFloat] = []
        var last: CGFloat?
        var reachedCap = false
        for content in stride(from: 40.0, through: 400.0, by: 0.7) { // token-sized growth
            let raw = AgentChatHeightPolicy.preferredCellHeight(cellHeight: 360, viewportHeight: 230, contentHeight: content)!
            let next: CGFloat? = raw < cap ? raw : nil // reporter contract
            if AgentChatHeightPolicy.shouldPublish(previous: last, next: next) {
                if let next { published.append(next) } else { reachedCap = true }
                last = next
            }
        }
        XCTAssertLessThan(published.count, 120, "hundreds of deltas collapse into quantized steps")
        XCTAssertTrue(reachedCap, "at the cap the hint is cleared: previous fixed geometry, transcript scrolls")
        XCTAssertEqual(published, published.sorted(), "monotonic growth, no back-and-forth")
        XCTAssertFalse(AgentChatHeightPolicy.shouldPublish(previous: 200, next: 202))
        XCTAssertTrue(AgentChatHeightPolicy.shouldPublish(previous: 200, next: nil), "Terminal page clears the hint")
    }

    private func agents(_ kinds: [IslandWidget], stack: Bool = false) -> WorkspaceConfiguration {
        var config = WorkspaceConfiguration(placements: kinds.enumerated().map { .init(kind: $0.element, surface: .agents, order: $0.offset) },
                                            customizedSurfaces: [.agents]).normalized()
        if stack { config.combineTerminalWithChat() }
        return config
    }

    func testShortChatShrinksTheShellAndLongChatCapsAtThePreviousHeight() {
        // Chat defines the row (the user's layout: usage band + Chat). A taller
        // neighbour such as Feed legitimately keeps its own row height.
        let config = agents([.agentUsage, .chat])
        let maximum = CGSize(width: 1180, height: 800)
        let fixed = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: config.regions(on: .agents), maximumSize: maximum, metrics: metrics)
        let short = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: config.regions(on: .agents), maximumSize: maximum,
                                                                          metrics: metrics, chatHeightHint: 210)
        let long = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: config.regions(on: .agents), maximumSize: maximum,
                                                                         metrics: metrics, chatHeightHint: 5_000)
        let tiny = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: config.regions(on: .agents), maximumSize: maximum,
                                                                         metrics: metrics, chatHeightHint: 20)
        XCTAssertLessThan(short.height, fixed.height - 80, "no giant black transcript region for a short chat")
        XCTAssertEqual(long.height, fixed.height, accuracy: 0.5, "never taller than the previous fixed size")
        XCTAssertGreaterThanOrEqual(tiny.height, AgentChatHeightPolicy.minimumCellHeight * metrics.expandedCardScale - 0.5,
                                    "readable floor keeps composer and status visible")
    }

    func testHintAppliesToTheChatTerminalStackAndIsIgnoredWhileEditing() {
        let config = agents([.chat, .terminal], stack: true)
        let regions = config.regions(on: .agents)
        XCTAssertEqual(regions.count, 1)
        let size = CGSize(width: 900, height: 600)
        let terminalPage = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: size, metrics: metrics)
        let chatPage = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: size, metrics: metrics, chatHeightHint: 220)
        let editing = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: size, metrics: metrics, editing: true, chatHeightHint: 220)
        XCTAssertLessThan(chatPage.contentSize.height, terminalPage.contentSize.height + 0.5)
        XCTAssertLessThan(chatPage.frames[0].frame.height, terminalPage.frames[0].frame.height - 50,
                          "Chat page contracts; Terminal page keeps its native height")
        XCTAssertEqual(editing.frames[0].frame.height,
                       WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: size, metrics: metrics, editing: true).frames[0].frame.height,
                       accuracy: 0.5, "edit mode uses trait geometry")
    }
}

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
