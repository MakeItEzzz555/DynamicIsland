import XCTest
@testable import DynamicIsland

/// Spatial reorder intent, column composition, trait-driven fill/solo sizing
/// and the usage widgets. Pure model/projection evidence (no pointer sleeps).
final class WorkspaceSpatialLayoutTests: XCTestCase {
    private let metrics = ResolvedIslandMetrics.fallback

    private func configuration(_ kinds: [IslandWidget], surface: WorkspaceSurface = .media) -> WorkspaceConfiguration {
        var configuration = WorkspaceConfiguration(placements: kinds.enumerated().map {
            .init(kind: $0.element, surface: surface, order: $0.offset)
        })
        if surface == .media { configuration.placements += [.init(kind: .chat, surface: .agents, order: 0)] }
        return configuration.normalized()
    }
    private func slot(_ id: String, _ kind: IslandWidget, x: CGFloat, y: CGFloat = 0, w: CGFloat = 200, h: CGFloat = 160) -> WorkspaceDropSlot {
        .init(id: WidgetID(id), frame: .init(x: x, y: y, width: w, height: h), kind: kind)
    }
    private func frame(_ projection: WorkspaceWidgetLayoutProjection, _ kind: IslandWidget, surface: WorkspaceSurface = .media) -> CGRect? {
        projection.frames.first { $0.id == WidgetID("\(surface.rawValue).\(kind.rawValue)") }?.frame
    }

    // MARK: Directional intent

    func testPointerOffsetFromHoveredCenterSelectsLeftRightAboveBelow() {
        let slots = [slot("media.media", .media, x: 0), slot("media.timer", .timer, x: 210)]
        let bounds = CGRect(x: 0, y: 0, width: 410, height: 160)
        func intent(_ point: CGPoint) -> WorkspaceDropIntent {
            WorkspaceDropResolver.resolveIntent(point: point, bounds: bounds, surface: .media, slots: slots,
                                                draggedKind: .files, draggedID: nil)
        }
        let right = intent(.init(x: 395, y: 80))
        XCTAssertEqual(right.edge, .trailing)
        XCTAssertEqual(right.target, .insert(surface: .media, before: nil), "right of the last widget inserts after it")
        let left = intent(.init(x: 220, y: 80))
        XCTAssertEqual(left.edge, .leading)
        XCTAssertEqual(left.target, .insert(surface: .media, before: WidgetID("media.timer")))
        let above = intent(.init(x: 310, y: 5))
        XCTAssertEqual(above.target, .stack(surface: .media, onto: WidgetID("media.timer"), below: false))
        XCTAssertEqual(above.edge, .top)
        let below = intent(.init(x: 310, y: 155))
        XCTAssertEqual(below.target, .stack(surface: .media, onto: WidgetID("media.timer"), below: true))
        XCTAssertEqual(below.hovered, WidgetID("media.timer"))
    }

    func testAxisHysteresisPreventsFlickerAroundTheCenterDiagonal() {
        let slots = [slot("media.timer", .timer, x: 0, w: 200, h: 200)]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let vertical = WorkspaceDropResolver.resolveIntent(point: .init(x: 100, y: 190), bounds: bounds, surface: .media,
                                                           slots: slots, draggedKind: .files, draggedID: nil)
        XCTAssertEqual(vertical.edge, .bottom)
        // Slightly more horizontal than vertical: stays vertical inside the bias band.
        let near = WorkspaceDropResolver.resolveIntent(point: .init(x: 185, y: 182), bounds: bounds, surface: .media,
                                                       slots: slots, draggedKind: .files, draggedID: nil, previous: vertical)
        XCTAssertEqual(near.edge, .bottom)
        // Clearly horizontal: switches.
        let switched = WorkspaceDropResolver.resolveIntent(point: .init(x: 195, y: 110), bounds: bounds, surface: .media,
                                                           slots: slots, draggedKind: .files, draggedID: nil, previous: near)
        XCTAssertEqual(switched.edge, .trailing)
    }

    func testLargePrimarySurfacesNeverShareAColumn() {
        let slots = [slot("agents.chat", .chat, x: 0, w: 500, h: 300)]
        let intent = WorkspaceDropResolver.resolveIntent(point: .init(x: 250, y: 295), bounds: .init(x: 0, y: 0, width: 500, height: 300),
                                                         surface: .agents, slots: slots, draggedKind: .feed, draggedID: nil)
        XCTAssertNotEqual(intent.edge, .bottom)
        if case .stack = intent.target { XCTFail("Chat/Feed never stack vertically") }
    }

    func testOutsideDropIsInvalidAndCommitsNothing() {
        let slots = [slot("media.media", .media, x: 0)]
        let intent = WorkspaceDropResolver.resolveIntent(point: .init(x: 900, y: 900), bounds: .init(x: 0, y: 0, width: 200, height: 160),
                                                         surface: .media, slots: slots, draggedKind: .timer, draggedID: nil)
        XCTAssertEqual(intent.target, .invalid)
        XCTAssertNil(WorkspaceDropResolver.applying(intent.target, to: configuration([.media]), draggedID: nil, paletteKind: .timer))
    }

    // MARK: Columns

    func testStackBelowAndAboveCommitExactlyThePreviewedColumn() throws {
        let base = configuration([.media, .timer, .shortcuts])
        let below = try XCTUnwrap(WorkspaceDropResolver.applying(.stack(surface: .media, onto: WidgetID("media.timer"), below: true),
                                                                 to: base, draggedID: WidgetID("media.shortcuts"), paletteKind: nil))
        let regions = below.regions(on: .media)
        XCTAssertEqual(regions.map(\.id.rawValue), ["media.media", "media.timer", "media.shortcuts"])
        XCTAssertEqual(regions.map(\.stacksBelowPrevious), [false, false, true])
        let above = try XCTUnwrap(WorkspaceDropResolver.applying(.stack(surface: .media, onto: WidgetID("media.timer"), below: false),
                                                                 to: base, draggedID: WidgetID("media.shortcuts"), paletteKind: nil))
        XCTAssertEqual(above.regions(on: .media).map(\.id.rawValue), ["media.media", "media.shortcuts", "media.timer"])
        XCTAssertEqual(above.regions(on: .media).map(\.stacksBelowPrevious), [false, false, true])
        // The column renders as one unit: same x, stacked y.
        let projection = WorkspaceWidgetLayoutProjection.make(regions: below.regions(on: .media),
            availableSize: .init(width: 1100, height: 500), metrics: metrics)
        let timer = try XCTUnwrap(frame(projection, .timer)), shortcuts = try XCTUnwrap(frame(projection, .shortcuts))
        XCTAssertEqual(timer.minX, shortcuts.minX, accuracy: 0.5)
        XCTAssertGreaterThan(shortcuts.minY, timer.maxY - 0.5)
    }

    func testMovingOutOfAColumnPromotesTheWidgetBelowAndPersists() throws {
        var stacked = try XCTUnwrap(WorkspaceDropResolver.applying(.stack(surface: .media, onto: WidgetID("media.timer"), below: true),
                                                                   to: configuration([.media, .timer, .shortcuts]),
                                                                   draggedID: WidgetID("media.shortcuts"), paletteKind: nil))
        let data = try JSONEncoder().encode(stacked)
        XCTAssertEqual(WorkspaceConfiguration.decoded(data), stacked, "column relation persists")
        stacked.move(WidgetID("media.timer"), before: WidgetID("media.media"), on: .media)
        let regions = stacked.regions(on: .media)
        XCTAssertEqual(regions.map(\.id.rawValue), ["media.timer", "media.media", "media.shortcuts"])
        XCTAssertTrue(regions.allSatisfy { !$0.stacksBelowPrevious }, "first region can never stack; the follower is promoted")
    }

    func testLegacyPlacementsWithoutColumnFlagDecodeStandalone() throws {
        let json = #"{"schemaVersion":1,"placements":[{"id":"media.media","kind":"media","surface":"media","order":0},{"id":"media.timer","kind":"timer","surface":"media","order":1}]}"#
        let decoded = WorkspaceConfiguration.decoded(Data(json.utf8))
        XCTAssertEqual(decoded.regions(on: .media).map(\.stacksBelowPrevious), [false, false])
    }

    // MARK: Trait-driven dimensions

    func testRowNeighboursShareHeightAndTimerFillsTheMediaRow() throws {
        let projection = WorkspaceWidgetLayoutProjection.make(regions: configuration([.media, .timer]).regions(on: .media),
            availableSize: .init(width: 1100, height: 500), metrics: metrics)
        let media = try XCTUnwrap(frame(projection, .media)), timer = try XCTUnwrap(frame(projection, .timer))
        XCTAssertEqual(media.minY, timer.minY, accuracy: 0.5)
        XCTAssertEqual(media.maxY, timer.maxY, accuracy: 0.5, "Timer's bottom aligns with Media's")
    }

    func testSameRowWidgetsShareTheGridRowHeight() throws {
        let projection = WorkspaceWidgetLayoutProjection.make(regions: configuration([.media, .shortcuts]).regions(on: .media),
            availableSize: .init(width: 1100, height: 500), metrics: metrics)
        let media = try XCTUnwrap(frame(projection, .media)), shortcuts = try XCTUnwrap(frame(projection, .shortcuts))
        XCTAssertEqual(shortcuts.height, media.height, accuracy: 0.5, "one grid row height: no ragged row")
        XCTAssertEqual(shortcuts.minY, media.minY, accuracy: 0.5)
    }

    func testTwoCompactWidgetsStackBesideALargeAnchor() throws {
        var config = configuration([.calendar, .shortcuts, .activities])
        config.setSize(.large, for: try XCTUnwrap(config.placement(kind: .calendar, on: .media)).id)
        config.setSize(.compact, for: try XCTUnwrap(config.placement(kind: .shortcuts, on: .media)).id)
        config.setSize(.compact, for: try XCTUnwrap(config.placement(kind: .activities, on: .media)).id)
        // Three columns: the two Compacts form the third column beside the 2x2 Large.
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .media),
            availableSize: .init(width: grid.length(3), height: 600), metrics: metrics, editing: false)
        let shortcuts = try XCTUnwrap(frame(projection, .shortcuts)), activities = try XCTUnwrap(frame(projection, .activities))
        let calendar = try XCTUnwrap(frame(projection, .calendar))
        XCTAssertEqual(shortcuts.minX, activities.minX, accuracy: 0.5, "compact widgets form one column")
        XCTAssertGreaterThanOrEqual(activities.minY, shortcuts.maxY - 0.5)
        XCTAssertEqual(activities.maxY, calendar.maxY, accuracy: 0.5, "the column matches the Large height")
        XCTAssertEqual(projection.rows, 2)
    }

    func testMediaStandardFootprintIsAtLeastThirtyPercentSmallerThanTheOldTraits() {
        let solo = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: configuration([.media]).regions(on: .media),
            maximumSize: .init(width: 1200, height: 800), metrics: metrics)
        let old = 360 * 220 * metrics.expandedCardScale * metrics.expandedCardScale
        XCTAssertLessThanOrEqual(solo.width * solo.height, old * 0.72, "Standard Media ~30% smaller than the old 360x220 card")
        let shared = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: configuration([.media, .timer]).regions(on: .media),
            maximumSize: .init(width: 1200, height: 800), metrics: metrics)
        XCTAssertGreaterThan(shared.width, solo.width)
    }

    func testCompositionsStayFiniteAndInsideNarrowBudgets() {
        let kinds: [[IslandWidget]] = [[.media], [.media, .timer], [.media, .timer, .files], [.calendar, .codexUsage, .claudeUsage],
                                       [.media, .files, .clipboard, .timer, .calendar, .shortcuts, .activities, .agentUsage]]
        for widgets in kinds {
            for width in [420.0, 640, 900, 1300] {
                let projection = WorkspaceWidgetLayoutProjection.make(regions: configuration(widgets).regions(on: .media),
                    availableSize: .init(width: width, height: 420), metrics: metrics)
                XCTAssertEqual(projection.frames.count, widgets.count)
                for item in projection.frames {
                    XCTAssertTrue(item.frame.minX >= -0.5 && item.frame.maxX <= width + 0.5, "\(widgets) @\(width) clipped horizontally")
                    XCTAssertTrue(item.frame.width.isFinite && item.frame.height > 0)
                }
                let sorted = projection.frames.map(\.frame)
                for (i, a) in sorted.enumerated() { for b in sorted.dropFirst(i + 1) {
                    XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(b.insetBy(dx: 1, dy: 1)), "\(widgets) @\(width) overlapped")
                } }
            }
        }
    }

    // MARK: Usage widgets

    func testUsageWidgetsAreRealCustomizableAgentsAndMediaWidgets() throws {
        for kind in [IslandWidget.agentUsage, .codexUsage, .claudeUsage] {
            XCTAssertTrue(kind.isEligible(on: .agents))
            XCTAssertTrue(kind.isEligible(on: .media))
            XCTAssertTrue(kind.isUsage)
        }
        var configuration = WorkspaceConfiguration.initial
        configuration.add(.codexUsage, on: .agents)
        configuration.add(.claudeUsage, on: .agents)
        configuration.add(.codexUsage, on: .agents) // singleton
        let data = try JSONEncoder().encode(configuration.normalized())
        let decoded = WorkspaceConfiguration.decoded(data)
        XCTAssertEqual(decoded.widgets(on: .agents).filter { $0.kind == .codexUsage }.count, 1)
        XCTAssertTrue(decoded.widgets(on: .agents).contains { $0.kind == .claudeUsage })
        XCTAssertEqual(AgentUsageWidgetView.Scope(widget: .agentUsage), .combined)
        XCTAssertEqual(AgentUsageWidgetView.Scope(widget: .codexUsage)?.providers, [.codex])
        XCTAssertEqual(AgentUsageWidgetView.Scope(widget: .claudeUsage)?.providers, [.claude])
        XCTAssertNil(AgentUsageWidgetView.Scope(widget: .timer))
    }

    func testProviderGroupsKeepEachProvidersQuotaAndOmitContext() {
        let groups = AgentWorkspaceUsageProjection.providerGroups(accountUsage: [:])
        XCTAssertEqual(groups[.codex]?.map(\.kind), [.fiveHour, .week])
        XCTAssertEqual(groups[.claude]?.map(\.kind), [.fiveHour, .week])
        XCTAssertTrue(groups.values.joined().allSatisfy { $0.kind != .context })
        XCTAssertTrue(groups[.codex]!.allSatisfy { $0.provider == .codex })
    }
}
