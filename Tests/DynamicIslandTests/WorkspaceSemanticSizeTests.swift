import XCTest
@testable import DynamicIsland

/// Apple-style semantic sizes: Compact 1x1, Standard 2x1, Large 2x2 on one
/// per-surface grid unit, deterministic packing, and size-specific content.
final class WorkspaceSemanticSizeTests: XCTestCase {
    private let metrics = ResolvedIslandMetrics.fallback
    private typealias Spec = (kind: IslandWidget, size: WidgetPresentationSize)

    private func config(_ specs: [Spec], surface: WorkspaceSurface, below: Set<Int> = []) -> WorkspaceConfiguration {
        var value = WorkspaceConfiguration(placements: specs.enumerated().map {
            .init(kind: $0.element.kind, surface: surface, order: $0.offset, size: $0.element.size,
                  stacksBelowPrevious: below.contains($0.offset))
        }).normalized()
        value.markCustomized(surface)
        return value
    }

    private func layout(_ specs: [Spec], surface: WorkspaceSurface = .media, columns: Int? = nil,
                        width: CGFloat? = nil, editing: Bool = true, below: Set<Int> = []) -> WorkspaceWidgetLayoutProjection {
        let grid = WidgetGridMetrics.make(surface: surface, metrics: metrics)
        let available = width ?? grid.length(columns ?? 4)
        let inset: CGFloat = editing ? 14 : 0
        return WorkspaceWidgetLayoutProjection.make(regions: config(specs, surface: surface, below: below).regions(on: surface),
            availableSize: .init(width: available + inset, height: 2_000), metrics: metrics, editing: editing)
    }

    private func assertNoOverlap(_ projection: WorkspaceWidgetLayoutProjection, file: StaticString = #filePath, line: UInt = #line) {
        let frames = projection.frames.map(\.frame)
        for (index, a) in frames.enumerated() {
            for b in frames.dropFirst(index + 1) {
                XCTAssertFalse(a.insetBy(dx: 0.5, dy: 0.5).intersects(b.insetBy(dx: 0.5, dy: 0.5)), "\(a) overlaps \(b)", file: file, line: line)
            }
        }
    }

    // MARK: Grid metrics

    func testGridMetricsDeriveEveryShapeFromOneUnit() {
        for surface in [WorkspaceSurface.media, .agents] {
            let grid = WidgetGridMetrics.make(surface: surface, metrics: metrics)
            let s = grid.side, g = grid.gutter
            XCTAssertEqual(grid.size(for: .compact), CGSize(width: s, height: s), "Compact is square")
            XCTAssertEqual(grid.size(for: .standard), CGSize(width: 2 * s + g, height: s), "Standard is 2x1")
            XCTAssertEqual(grid.size(for: .large), CGSize(width: 2 * s + g, height: 2 * s + g), "Large is 2x2")
        }
        XCTAssertGreaterThan(WidgetGridMetrics.make(surface: .agents, metrics: metrics).side,
                             WidgetGridMetrics.make(surface: .media, metrics: metrics).side,
                             "Agents Standard must hold a functional transcript + composer")
        XCTAssertTrue(WidgetPresentationSize.compact.span == (1, 1))
        XCTAssertTrue(WidgetPresentationSize.standard.span == (2, 1))
        XCTAssertTrue(WidgetPresentationSize.large.span == (2, 2))
    }

    func testGridUnitAdaptsToDisplayScaleAndNarrowHosts() {
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        XCTAssertEqual(grid.side, WidgetGridMetrics.mediaBaseSide * metrics.expandedCardScale, accuracy: 0.001)
        let narrow = grid.fitted(to: grid.length(2) - 40)
        XCTAssertLessThan(narrow.side, grid.side, "a host narrower than a Standard shrinks the unit instead of overlapping")
        XCTAssertEqual(narrow.length(2), grid.length(2) - 40, accuracy: 0.001)
        XCTAssertEqual(grid.columns(fitting: grid.length(4)), 4)
        XCTAssertEqual(grid.columns(fitting: grid.length(4) - 1), 3)
        XCTAssertEqual(grid.columns(fitting: 10), 2, "never fewer than the two columns a Standard needs")
    }

    func testSemanticRawValuesArePersistedUnchanged() throws {
        XCTAssertEqual(WidgetPresentationSize.allCases.map(\.rawValue), ["compact", "standard", "large"])
        XCTAssertEqual(WidgetPresentationSize.allCases.map(\.title), ["Compact", "Standard", "Large"])
        // A narrow display wraps; it never rewrites the saved sizes.
        let value = config([(.media, .standard), (.timer, .standard), (.calendar, .large)], surface: .media)
        _ = WorkspaceWidgetLayoutProjection.make(regions: value.regions(on: .media), availableSize: .init(width: 300, height: 400), metrics: metrics)
        let decoded = WorkspaceConfiguration.decoded(try JSONEncoder().encode(value))
        XCTAssertEqual(decoded.widgets(on: .media).map(\.size), [.standard, .standard, .large])
    }

    // MARK: Grid matrix

    func testFourCompactFormOneRowAndWrapToTwoOnNarrowHosts() {
        let specs: [Spec] = [(.media, .compact), (.timer, .compact), (.files, .compact), (.clipboard, .compact)]
        let wide = layout(specs, columns: 4)
        XCTAssertEqual(wide.rows, 1)
        XCTAssertEqual(Set(wide.frames.map { $0.frame.minY.rounded() }).count, 1)
        let narrow = layout(specs, columns: 2)
        XCTAssertEqual(narrow.rows, 2)
        XCTAssertEqual(narrow.frames.map(\.id), wide.frames.map(\.id), "order is preserved while wrapping")
        assertNoOverlap(wide); assertNoOverlap(narrow)
    }

    func testTwoStandardsShareARowOrStack() {
        let specs: [Spec] = [(.media, .standard), (.timer, .standard)]
        XCTAssertEqual(layout(specs, columns: 4).rows, 1)
        let stacked = layout(specs, columns: 3)
        XCTAssertEqual(stacked.rows, 2, "a Standard never splits across a row")
        XCTAssertEqual(stacked.frames[0].frame.minX, stacked.frames[1].frame.minX, accuracy: 0.5)
        assertNoOverlap(stacked)
    }

    func testOneLargeIsTwoByTwo() throws {
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        let projection = layout([(.calendar, .large)], columns: 4)
        let frame = try XCTUnwrap(projection.frames.first?.frame)
        XCTAssertEqual(frame.size.width, grid.size(for: .large).width, accuracy: 0.5)
        XCTAssertEqual(frame.size.height, grid.size(for: .large).height, accuracy: 0.5)
        XCTAssertEqual(projection.rows, 2)
    }

    func testStandardPlusTwoCompactsFillOneFourColumnRow() {
        let projection = layout([(.media, .standard), (.timer, .compact), (.files, .compact)], columns: 4)
        XCTAssertEqual(projection.rows, 1)
        XCTAssertEqual(projection.columns, 4)
        let xs = projection.frames.map(\.frame.minX)
        XCTAssertEqual(xs, xs.sorted(), "user order reads left to right")
        assertNoOverlap(projection)
    }

    func testLargePlusCompactSitsBesideTheLarge() throws {
        let projection = layout([(.calendar, .large), (.timer, .compact)], columns: 4)
        let large = try XCTUnwrap(projection.frames.first?.frame), compact = try XCTUnwrap(projection.frames.last?.frame)
        XCTAssertEqual(compact.minY, large.minY, accuracy: 0.5)
        XCTAssertGreaterThan(compact.minX, large.maxX)
        XCTAssertEqual(compact.width, compact.height, accuracy: 0.5)
    }

    func testMediaStandardPlusTimerCompactIsAThreeColumnRow() throws {
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        let projection = layout([(.media, .standard), (.timer, .compact)], columns: 4)
        XCTAssertEqual(projection.rows, 1)
        XCTAssertEqual(projection.columns, 3)
        let size = WorkspaceWidgetLayoutProjection.preferredContentSize(
            regions: config([(.media, .standard), (.timer, .compact)], surface: .media).regions(on: .media),
            maximumSize: .init(width: 2_000, height: 2_000), metrics: metrics)
        XCTAssertEqual(size.width, grid.length(3), accuracy: 0.5, "the shell hugs the grid")
        XCTAssertEqual(size.height, grid.side, accuracy: 0.5)
    }

    func testChatLargePlusFeedStandardOnAgents() throws {
        let projection = layout([(.chat, .large), (.feed, .standard)], surface: .agents, columns: 4)
        let chat = try XCTUnwrap(projection.frames.first?.frame), feed = try XCTUnwrap(projection.frames.last?.frame)
        XCTAssertEqual(feed.minY, chat.minY, accuracy: 0.5)
        XCTAssertGreaterThan(feed.minX, chat.maxX)
        XCTAssertEqual(projection.rows, 2)
        assertNoOverlap(projection)
    }

    func testTerminalStandardPlusUsageCompactBandIsASeparateStrip() throws {
        let projection = layout([(.terminal, .standard), (.agentUsage, .compact)], surface: .agents, columns: 4)
        let terminal = try XCTUnwrap(projection.frames.first { $0.id == WidgetID("agents.terminal") }?.frame)
        let usage = try XCTUnwrap(projection.frames.first { $0.id == WidgetID("agents.agentUsage") }?.frame)
        XCTAssertTrue(usage.maxY <= terminal.minY + 0.5 || usage.minY >= terminal.maxY - 0.5, "the usage strip owns its own row")
        XCTAssertEqual(usage.height, WidgetGridMetrics.bandSize(.agentUsage, .compact, metrics: metrics).height, accuracy: 0.5)
        XCTAssertLessThan(WidgetGridMetrics.bandSize(.agentUsage, .compact, metrics: metrics).height,
                          WidgetGridMetrics.bandSize(.agentUsage, .large, metrics: metrics).height)
    }

    func testStackBelowPlacesARegionUnderItsAnchor() throws {
        let projection = layout([(.media, .standard), (.timer, .compact), (.files, .compact)], columns: 4, below: [2])
        let timer = projection.frames[1].frame, files = projection.frames[2].frame
        XCTAssertEqual(files.minX, timer.minX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(files.minY, timer.maxY - 0.5)
        assertNoOverlap(projection)
    }

    func testStackBelowDoesNotStrandCellsBesideItsAnchor() throws {
        // The stored user layout: Compact Media, Standard Timer stacked below
        // it, then Standard Workspace. Workspace fills the space beside Media.
        let projection = layout([(.media, .compact), (.timer, .standard), (.workspace, .standard)], columns: 6, below: [1])
        let media = projection.frames[0].frame, timer = projection.frames[1].frame, workspace = projection.frames[2].frame
        XCTAssertGreaterThanOrEqual(timer.minY, media.maxY - 0.5)
        XCTAssertEqual(workspace.minY, media.minY, accuracy: 0.5)
        XCTAssertGreaterThan(workspace.minX, media.maxX)
        XCTAssertEqual(projection.columns, 3, "3 columns instead of 4 with an empty row of cells")
        assertNoOverlap(projection)
    }

    func testFillingAWideShellKeepsCompactSquareAndStandardTwoByOne() throws {
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        let header: CGFloat = 441
        let compact = config([(.media, .compact)], surface: .media).regions(on: .media)
        let square = try XCTUnwrap(WorkspaceWidgetLayoutProjection.make(regions: compact,
            availableSize: .init(width: header, height: 600), metrics: metrics).frames.first?.frame)
        XCTAssertEqual(square.width, square.height, accuracy: 0.01, "Compact stays a true square")
        XCTAssertEqual(square.width, grid.side * WorkspaceWidgetLayoutProjection.fillScaleCap, accuracy: 0.01, "and never balloons")
        XCTAssertEqual(square.midX, header / 2, accuracy: 0.5)
        let standard = config([(.media, .standard)], surface: .media).regions(on: .media)
        let preferred = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: standard,
            maximumSize: .init(width: 1_200, height: 800), metrics: metrics, minimumWidth: header)
        let filled = WorkspaceWidgetLayoutProjection.make(regions: standard, availableSize: preferred, metrics: metrics)
        let frame = try XCTUnwrap(filled.frames.first?.frame)
        XCTAssertEqual(frame.minX, 0, accuracy: 0.5); XCTAssertEqual(frame.maxX, header, accuracy: 0.5)
        XCTAssertEqual(frame.height, (frame.width - grid.gutter) / 2, accuracy: 0.5, "Standard keeps its 2:1 shape")
        XCTAssertFalse(filled.requiresScrolling, "the resolver and the projection agree on the filled height")
        XCTAssertEqual(frame.height, preferred.height, accuracy: 0.5)
    }

    // MARK: Orphan rows

    private func centered(_ frame: CGRect, in projection: WorkspaceWidgetLayoutProjection,
                          file: StaticString = #filePath, line: UInt = #line) {
        let others = projection.frames.map(\.frame).filter { $0 != frame }
        let minX = (others + [frame]).map(\.minX).min()!, maxX = (others + [frame]).map(\.maxX).max()!
        XCTAssertEqual(frame.midX, (minX + maxX) / 2, accuracy: 0.5, "orphan is centered in its section", file: file, line: line)
    }

    func testAWrappedSingletonIsCenteredWithoutChangingItsSize() throws {
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        // [A][B] / [ C ] at four columns: two Standards then a Standard.
        let projection = layout([(.media, .standard), (.timer, .standard), (.calendar, .standard)], columns: 4)
        let c = try XCTUnwrap(projection.frames.last?.frame)
        XCTAssertEqual(c.width, grid.size(for: .standard).width, accuracy: 0.5, "size unchanged, not stretched")
        centered(c, in: projection)
        assertNoOverlap(projection)
    }

    func testSingletonCentersAcrossCompactAndLargeMixes() throws {
        // Three Compacts at two columns: [A][B] / [C]
        let three = layout([(.media, .compact), (.timer, .compact), (.files, .compact)], columns: 2)
        centered(try XCTUnwrap(three.frames.last?.frame), in: three)
        // Standard + Compact + Compact at three columns: [S S][C] / [C]
        let mixed = layout([(.media, .standard), (.timer, .compact), (.files, .compact)], columns: 3)
        centered(try XCTUnwrap(mixed.frames.last?.frame), in: mixed)
        // Large + Compact at two columns: the Compact wraps below the Large.
        let large = layout([(.calendar, .large), (.timer, .compact)], columns: 2)
        centered(try XCTUnwrap(large.frames.last?.frame), in: large)
        // Rows with two widgets keep their positions.
        XCTAssertEqual(three.frames[0].frame.minX, three.frames.map(\.frame.minX).min()!, accuracy: 0.5)
        XCTAssertEqual(mixed.columns, 3, "a width of exactly three units fits three columns")
    }

    func testChatTerminalStackAndFeedAloneCenterAsOneItem() throws {
        var value = config([(.feed, .standard), (.chat, .standard), (.terminal, .standard)], surface: .agents)
        value.combineTerminalWithChat()
        let grid = WidgetGridMetrics.make(surface: .agents, metrics: metrics)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: value.regions(on: .agents),
            availableSize: .init(width: grid.length(3) + 14, height: 2_000), metrics: metrics, editing: true)
        XCTAssertEqual(projection.frames.count, 2, "the stack is one placement item")
        for frame in projection.frames.map(\.frame) { centered(frame, in: projection) }
    }

    func testTimerAloneAfterWrapIsCenteredButStackBelowKeepsItsColumn() throws {
        let wrapped = layout([(.media, .standard), (.files, .compact), (.timer, .standard)], columns: 3)
        centered(try XCTUnwrap(wrapped.frames.last?.frame), in: wrapped)
        let stacked = layout([(.media, .compact), (.timer, .standard), (.workspace, .standard)], columns: 6, below: [1])
        XCTAssertEqual(stacked.frames[1].frame.minX, stacked.frames[0].frame.minX, accuracy: 0.5, "column relation preserved")
    }

    func testDragPreviewAndCommittedLayoutPlaceTheOrphanIdentically() throws {
        // The editor previews with the same projection it commits with.
        let specs: [Spec] = [(.media, .standard), (.timer, .standard), (.calendar, .standard)]
        let preview = layout(specs, columns: 4, editing: true)
        let committed = layout(specs, columns: 4, editing: true)
        XCTAssertEqual(preview, committed)
        let draft = config(specs, surface: .media)
        let decoded = WorkspaceConfiguration.decoded(try JSONEncoder().encode(draft))
        let afterCommit = WorkspaceWidgetLayoutProjection.make(regions: decoded.regions(on: .media),
            availableSize: .init(width: WidgetGridMetrics.make(surface: .media, metrics: metrics).length(4) + 14, height: 2_000),
            metrics: metrics, editing: true)
        XCTAssertEqual(afterCommit.frames, preview.frames, "commit equals the previewed geometry")
    }

    func testPackingIsDeterministicAndNeverReshufflesOrder() {
        let specs: [Spec] = [(.media, .compact), (.calendar, .large), (.timer, .standard), (.files, .compact),
                             (.clipboard, .compact), (.shortcuts, .standard), (.activities, .compact)]
        for columns in 2...5 {
            let a = layout(specs, columns: columns), b = layout(specs, columns: columns)
            XCTAssertEqual(a, b)
            assertNoOverlap(a)
            // Row-major order of the top-left corners follows the user order.
            let keys = a.frames.map { ($0.frame.minY.rounded(), $0.frame.minX.rounded()) }
            for (first, second) in zip(keys, keys.dropFirst()) {
                XCTAssertTrue(first.0 < second.0 || (first.0 == second.0 && first.1 < second.1),
                              "\(columns) columns: cursor never moves backwards")
            }
        }
    }

    func testSizeChangeMovesNeighboursWithoutChangingIdentityOrOrder() {
        var value = config([(.media, .standard), (.timer, .compact), (.files, .compact)], surface: .media)
        let before = WorkspaceWidgetLayoutProjection.make(regions: value.regions(on: .media),
            availableSize: .init(width: 1_200, height: 900), metrics: metrics, editing: true)
        value.setSize(.compact, for: value.placement(kind: .media, on: .media)!.id)
        let after = WorkspaceWidgetLayoutProjection.make(regions: value.regions(on: .media),
            availableSize: .init(width: 1_200, height: 900), metrics: metrics, editing: true)
        XCTAssertEqual(before.frames.map(\.id), after.frames.map(\.id))
        XCTAssertLessThan(after.frames[1].frame.minX, before.frames[1].frame.minX, "the neighbour slides into the freed column")
    }

    func testCompactChatIgnoresTheAdaptiveHeightHint() {
        let value = config([(.chat, .compact)], surface: .agents)
        let plain = WorkspaceWidgetLayoutProjection.make(regions: value.regions(on: .agents), availableSize: .init(width: 900, height: 600), metrics: metrics)
        let hinted = WorkspaceWidgetLayoutProjection.make(regions: value.regions(on: .agents), availableSize: .init(width: 900, height: 600),
                                                          metrics: metrics, chatHeightHint: 120)
        XCTAssertEqual(plain.frames[0].frame.height, hinted.frames[0].frame.height, accuracy: 0.5)
    }

    // MARK: Media

    func testMediaSlidersAreSeventyPercentOfTheCellAndClamped() {
        XCTAssertEqual(MediaWidgetMetrics.sliderWidth(cellWidth: 300), 210, accuracy: 0.001)
        XCTAssertEqual(MediaWidgetMetrics.sliderWidth(cellWidth: 1_000), MediaWidgetMetrics.sliderMaximumWidth)
        XCTAssertEqual(MediaWidgetMetrics.sliderWidth(cellWidth: 100), 84, accuracy: 0.001, "never wider than the cell minus insets")
        XCTAssertEqual(MediaWidgetMetrics.sliderWidth(cellWidth: .nan), MediaWidgetMetrics.sliderMinimumWidth)
        // Previously the volume track spanned the cell (313 pt in a 330 pt cell).
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        XCTAssertLessThanOrEqual(MediaWidgetMetrics.sliderWidth(cellWidth: grid.size(for: .standard).width), 313 * 0.75)
    }

    func testMediaArtworkIsNotShrunkWithTheSliders() {
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        XCTAssertGreaterThanOrEqual(MediaWidgetMetrics.artworkSide(.standard, cellHeight: grid.side), 40, "Standard keeps the 44 pt baseline art")
        XCTAssertGreaterThan(MediaWidgetMetrics.artworkSide(.compact, cellHeight: grid.side), 44, "Compact leads with artwork")
        XCTAssertGreaterThan(MediaWidgetMetrics.artworkSide(.large, cellHeight: grid.length(2)),
                             MediaWidgetMetrics.artworkSide(.compact, cellHeight: grid.side))
    }

    func testMediaStandardFootprintShrinksAtLeastThirtyPercent() {
        let grid = WidgetGridMetrics.make(surface: .media, metrics: metrics)
        let old = 360 * 220 * metrics.expandedCardScale * metrics.expandedCardScale
        let standard = grid.size(for: .standard)
        XCTAssertLessThanOrEqual(standard.width * standard.height / old, 0.70)
        let compact = grid.size(for: .compact)
        XCTAssertLessThanOrEqual(compact.width * compact.height / old, 0.35)
    }

    // MARK: Feed density

    func testFeedDensityKeepsPendingApprovalsVisibleInCompact() {
        let session = AgentSessionInstanceID(sessionID: AgentSessionID(provider: .codex, nativeID: "s"), generation: AgentSessionGeneration(rawValue: 1))
        func item(_ id: String, _ status: AgentOperationStatus, _ time: TimeInterval) -> AgentWorkspaceFeedItem {
            AgentWorkspaceFeedItem(id: .init(session: session, eventID: .init(rawValue: id)), kind: .approval, correlationID: nil,
                                   timestamp: Date(timeIntervalSince1970: time), updatedAt: Date(timeIntervalSince1970: time),
                                   title: id, status: status, processingKind: nil, approvalState: nil)
        }
        let items = [item("latest", .completed, 30), item("approval", .pending, 20)] + (0..<20).map { item("old\($0)", .completed, Double($0)) }
        let compact = AgentWorkspaceFeedDensity.visible(items, size: .compact)
        XCTAssertEqual(compact.items.map(\.title), ["approval"])
        XCTAssertEqual(compact.hidden, items.count - 1)
        XCTAssertEqual(AgentWorkspaceFeedDensity.visible(items, size: .standard).items.count, AgentWorkspaceFeedDensity.standardLimit)
        XCTAssertEqual(AgentWorkspaceFeedDensity.visible(items, size: .large).items.count, items.count)
        XCTAssertEqual(AgentWorkspaceFeedDensity.visible(items, size: nil).items.count, items.count, "non-grid hosts show everything")
        XCTAssertEqual(AgentWorkspaceFeedDensity.visible([item("only", .completed, 1)], size: .compact).items.map(\.title), ["only"])
    }

    // MARK: Performance

    func testProjectionIsCheapEnoughForLivePreview() {
        let specs: [Spec] = [(.media, .compact), (.calendar, .large), (.timer, .standard), (.files, .compact),
                             (.clipboard, .compact), (.shortcuts, .standard), (.activities, .compact), (.workspace, .standard)]
        let regions = config(specs, surface: .media).regions(on: .media)
        let start = Date()
        for index in 0..<2_000 {
            _ = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: .init(width: 700 + CGFloat(index % 300), height: 900),
                                                     metrics: metrics, editing: index.isMultiple(of: 2))
        }
        let perCall = Date().timeIntervalSince(start) / 2_000
        XCTAssertLessThan(perCall, 0.001, "projection runs per drag sample and per size preview")
    }
}
