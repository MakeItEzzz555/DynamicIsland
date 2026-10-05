import XCTest
@testable import DynamicIsland

/// Usage widgets own the Agents usage row (band trait + migration), Agents
/// editing stays horizontal, removing usage reserves no height, and no header
/// control can intersect the hardware-notch exclusion.
@MainActor
final class WorkspaceUsageBandAndHeaderTests: XCTestCase {
    private let metrics = ResolvedIslandMetrics.fallback
    private let notched = IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaInsets: .init(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRightArea: CGRect(x: 849, y: 950, width: 663, height: 32),
        backingScaleFactor: 2, displayID: nil, isBuiltIn: true,
        pixelSize: CGSize(width: 3024, height: 1964)))

    private func settings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "WorkspaceUsageBandAndHeaderTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.agentActivityEnabled = true
        settings.agentUsageMetricsEnabled = true
        return settings
    }
    private func frame(_ projection: WorkspaceWidgetLayoutProjection, _ id: WidgetID?) -> CGRect? {
        projection.frames.first { $0.id == id }?.frame
    }

    // MARK: Usage band ownership

    func testDefaultAgentsLayoutOwnsCombinedUsageAsABandAboveAHorizontalPrimaryRow() throws {
        let config = WorkspaceConfiguration.initial
        XCTAssertEqual(config.widgets(on: .agents).map(\.kind), [.agentUsage, .chat, .feed])
        let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .agents),
            availableSize: .init(width: 1180, height: 600), metrics: metrics, editing: true)
        let usage = try XCTUnwrap(frame(projection, config.placement(kind: .agentUsage, on: .agents)?.id))
        let chat = try XCTUnwrap(frame(projection, config.placement(kind: .chat, on: .agents)?.id))
        let feed = try XCTUnwrap(frame(projection, config.placement(kind: .feed, on: .agents)?.id))
        XCTAssertEqual(projection.rows, 2, "usage band + one primary row")
        XCTAssertLessThanOrEqual(usage.maxY, chat.minY, "usage sits above the primary row")
        XCTAssertEqual(chat.minY, feed.minY, accuracy: 0.5, "Chat and Feed stay side by side while editing")
        XCTAssertLessThan(usage.height, 100, "the band keeps its strip height")
    }

    func testRemovingEveryUsageWidgetReservesZeroUsageHeight() throws {
        var config = WorkspaceConfiguration.initial
        config.markCustomized(.agents)
        let maximum = CGSize(width: 1180, height: 800)
        let with = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: config.regions(on: .agents),
            maximumSize: maximum, metrics: metrics)
        config.remove(try XCTUnwrap(config.placement(kind: .agentUsage, on: .agents)).id)
        XCTAssertFalse(config.widgets(on: .agents).contains { $0.kind.isUsage })
        let without = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: config.regions(on: .agents),
            maximumSize: maximum, metrics: metrics)
        let band = IslandWidget.agentUsage.layoutTraits.preferred.height * metrics.expandedCardScale + metrics.spacing(8)
        XCTAssertEqual(with.height - without.height, band, accuracy: 0.5)
        // The shell resolver adds nothing for usage outside the configuration.
        let settings = settings()
        let base = CGSize(width: 900, height: 360)
        let shellWith = ExpandedPresentationProfile.agentsWorkspace.resolvedSize(from: base, page: .agents,
            configuration: WorkspaceConfiguration.initial.customizedCopy(), editing: false, settings: settings, metrics: metrics)
        let shellWithout = ExpandedPresentationProfile.agentsWorkspace.resolvedSize(from: base, page: .agents,
            configuration: config, editing: false, settings: settings, metrics: metrics)
        XCTAssertEqual(shellWith.height - shellWithout.height, band, accuracy: 0.5)
    }

    func testProviderUsageWidgetsShareOneCenteredBandAndReorder() throws {
        var config = WorkspaceConfiguration.initial
        config.remove(try XCTUnwrap(config.placement(kind: .agentUsage, on: .agents)).id)
        config.add(.codexUsage, on: .agents, before: config.placement(kind: .chat, on: .agents)?.id)
        config.add(.claudeUsage, on: .agents, before: config.placement(kind: .chat, on: .agents)?.id)
        let size = CGSize(width: 1180, height: 600)
        var projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .agents), availableSize: size, metrics: metrics)
        let codex = try XCTUnwrap(frame(projection, config.placement(kind: .codexUsage, on: .agents)?.id))
        let claude = try XCTUnwrap(frame(projection, config.placement(kind: .claudeUsage, on: .agents)?.id))
        XCTAssertEqual(codex.minY, claude.minY, accuracy: 0.5)
        XCTAssertLessThan(codex.maxX, claude.minX)
        XCTAssertEqual((codex.minX + claude.maxX) / 2, size.width / 2, accuracy: 1, "band is centered")
        XCTAssertEqual(projection.rows, 2)
        // Reorder: Claude before Codex.
        config.move(try XCTUnwrap(config.placement(kind: .claudeUsage, on: .agents)).id,
                    before: config.placement(kind: .codexUsage, on: .agents)?.id, on: .agents)
        projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .agents), availableSize: size, metrics: metrics)
        let codex2 = try XCTUnwrap(frame(projection, config.placement(kind: .codexUsage, on: .agents)?.id))
        let claude2 = try XCTUnwrap(frame(projection, config.placement(kind: .claudeUsage, on: .agents)?.id))
        XCTAssertLessThan(claude2.maxX, codex2.minX)
        // Persisted through the same configuration as every other widget.
        let decoded = WorkspaceConfiguration.decoded(try JSONEncoder().encode(config))
        XCTAssertEqual(decoded.widgets(on: .agents).map(\.kind).filter(\.isUsage), [.claudeUsage, .codexUsage])
    }

    func testVersionOneLayoutsMigrateTheUsageRowOnceAndRemovalSticks() throws {
        var legacy = WorkspaceConfiguration(schemaVersion: 1, placements: [
            .init(kind: .media, surface: .media, order: 0),
            .init(kind: .chat, surface: .agents, order: 0), .init(kind: .feed, surface: .agents, order: 1)],
            customizedSurfaces: [.agents])
        let migrated = WorkspaceConfiguration.decoded(try JSONEncoder().encode(legacy))
        XCTAssertEqual(migrated.widgets(on: .agents).map(\.kind), [.agentUsage, .chat, .feed])
        XCTAssertEqual(migrated.schemaVersion, 2)
        // A removed (hidden) usage placement is a user choice: never re-added.
        var removed = migrated
        removed.remove(try XCTUnwrap(removed.placement(kind: .agentUsage, on: .agents)).id)
        let reloaded = WorkspaceConfiguration.decoded(try JSONEncoder().encode(removed))
        XCTAssertFalse(reloaded.widgets(on: .agents).contains { $0.kind.isUsage })
        // A v1 layout that already placed a usage widget keeps it as-is.
        legacy.placements.append(.init(kind: .codexUsage, surface: .agents, order: 2))
        let kept = WorkspaceConfiguration.decoded(try JSONEncoder().encode(legacy))
        XCTAssertEqual(kept.widgets(on: .agents).map(\.kind), [.chat, .feed, .codexUsage])
    }

    func testAgentsEditingPrefersWidthOverHeight() throws {
        let settings = settings()
        var config = WorkspaceConfiguration.initial
        config.add(.terminal, on: .agents)
        let base = CGSize(width: 900, height: 360)
        let editing = ExpandedPresentationProfile.agentsWorkspace.resolvedSize(from: base, page: .agents,
            configuration: config, editing: true, settings: settings, metrics: metrics)
        let regions = config.regions(on: .agents)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: .init(width: editing.width - 40,
            height: editing.height), metrics: metrics, editing: true)
        XCTAssertEqual(projection.rows, 2, "Chat, Terminal and Feed stay in one row under the usage band")
        XCTAssertGreaterThan(editing.width, editing.height * 1.6, "edit mode grows horizontally, not into tall blocks")
    }

    func testCompactNotchedDisplayKeepsChatAndTerminalSideBySideWhileEditing() {
        // 1147 x 745 pt notched MacBook (larger-text scaling): measured in GUI.
        let compact = IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
            frame: CGRect(x: 0, y: 0, width: 1147, height: 745),
            visibleFrame: CGRect(x: 0, y: 77, width: 1147, height: 638),
            safeAreaInsets: .init(top: 24, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 721, width: 503, height: 24),
            auxiliaryTopRightArea: CGRect(x: 644, y: 721, width: 503, height: 24),
            backingScaleFactor: 2, displayID: nil, isBuiltIn: true, pixelSize: CGSize(width: 2294, height: 1490)))
        let settings = settings()
        let config = WorkspaceConfiguration(placements: [.init(kind: .chat, surface: .agents, order: 0),
            .init(kind: .terminal, surface: .agents, order: 1)], customizedSurfaces: [.agents]).normalized()
        let size = ExpandedPresentationProfile.agentsWorkspace.resolvedSize(from: settings.expandedSize, page: .agents,
            configuration: config, editing: true, settings: settings, metrics: compact)
        let horizontal = IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true) * 2
        let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .agents),
            availableSize: .init(width: size.width - horizontal, height: 500), metrics: compact, editing: true)
        XCTAssertEqual(projection.rows, 1, "edit mode widens instead of stacking Chat over Terminal")
        XCTAssertGreaterThan(size.width, size.height)
        XCTAssertLessThanOrEqual(size.width, 1147 - 280 + 0.5, "within the safe display width")
    }

    // MARK: Notch-safe header

    func testHeaderControlsNeverIntersectTheHardwareNotchExclusion() {
        let settings = settings()
        let notchWidth: CGFloat = 186
        let horizontal = IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true) * 2
        for pages in 1...9 {
            for clipboard in [false, true] {
                for widgets in [[IslandWidget.media], [.media, .timer], [.media, .files, .clipboard, .timer]] {
                    var config = WorkspaceConfiguration(placements: widgets.enumerated().map {
                        .init(kind: $0.element, surface: .media, order: $0.offset) }, customizedSurfaces: [.media])
                    config = config.normalized()
                    let minimum = ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: pages, clipboardEnabled: clipboard,
                                                                                  hardwareNotchWidth: notchWidth)
                    for editing in [false, true] {
                        let size = ExpandedPresentationProfile.standard.resolvedSize(from: .init(width: 420, height: 200), page: .island,
                            configuration: config, editing: editing, settings: settings, metrics: notched, minimumHeaderWidth: minimum)
                        let inner = size.width - horizontal
                        let frames = ExpandedIslandHeaderMetrics.frames(innerWidth: inner, pageCount: pages,
                            clipboardEnabled: clipboard, hardwareNotchWidth: notchWidth)
                        XCTAssertLessThanOrEqual(frames.leading.upperBound, frames.exclusion.lowerBound + 0.001,
                            "tabs (\(pages)) overlap the notch at width \(inner)")
                        XCTAssertGreaterThanOrEqual(frames.trailing.lowerBound, frames.exclusion.upperBound - 0.001,
                            "actions overlap the notch at width \(inner)")
                        XCTAssertGreaterThanOrEqual(frames.exclusion.upperBound - frames.exclusion.lowerBound, notchWidth)
                    }
                }
            }
        }
        // The non-customized page path honors the header minimum too.
        let plain = ExpandedPresentationProfile.standard.resolvedSize(from: .init(width: 300, height: 200), page: .stats,
            configuration: nil, editing: false, settings: settings, metrics: notched,
            minimumHeaderWidth: ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: 9, clipboardEnabled: true, hardwareNotchWidth: notchWidth))
        XCTAssertGreaterThanOrEqual(plain.width - horizontal,
            ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: 9, clipboardEnabled: true, hardwareNotchWidth: notchWidth) - 0.001)
    }

    func testNotchlessHeaderReservesNoNotchGap() {
        XCTAssertEqual(ExpandedIslandHeaderMetrics.notchExclusionWidth(hardwareNotchWidth: 0), 0)
        XCTAssertEqual(ExpandedIslandHeaderMetrics.notchExclusionWidth(hardwareNotchWidth: .nan), 0)
        XCTAssertEqual(ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: 4, clipboardEnabled: true),
                       ExpandedIslandHeaderMetrics.leadingGroupWidth(pageCount: 4)
                       + ExpandedIslandHeaderMetrics.trailingGroupWidth(clipboardEnabled: true) + 8)
        let frames = ExpandedIslandHeaderMetrics.frames(innerWidth: 400, pageCount: 4, clipboardEnabled: true, hardwareNotchWidth: 0)
        XCTAssertEqual(frames.exclusion.upperBound - frames.exclusion.lowerBound, 0)
    }

    // MARK: Media solo composition

    func testSoloMediaHeaderIsLeftWeightedWithABoundedRightwardStep() {
        XCTAssertEqual(MediaSoloComposition.headerInset(cellWidth: 0), 0)
        XCTAssertEqual(MediaSoloComposition.headerInset(cellWidth: .nan), 0)
        let narrow = MediaSoloComposition.headerInset(cellWidth: 300)
        let wide = MediaSoloComposition.headerInset(cellWidth: 900)
        XCTAssertGreaterThan(narrow, 0)
        XCTAssertGreaterThanOrEqual(wide, narrow)
        XCTAssertLessThanOrEqual(wide, 44, "never drifts toward the center")
        XCTAssertLessThan(wide, 900 / 4)
    }
}

private extension WorkspaceConfiguration {
    func customizedCopy() -> Self { var copy = self; copy.markCustomized(.agents); return copy }
}

final class WorkspaceCombineZoneTests: XCTestCase {
    func testTerminalOverChatCombinesOnlyInTheCenterAndInsertsTowardEdges() {
        let chat = WorkspaceDropSlot(id: WidgetID("agents.chat"), frame: .init(x: 0, y: 0, width: 440, height: 360), kind: .chat)
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 360)
        func intent(_ x: CGFloat) -> WorkspaceDropIntent {
            WorkspaceDropResolver.resolveIntent(point: .init(x: x, y: 180), bounds: bounds, surface: .agents,
                                                slots: [chat], draggedKind: .terminal, draggedID: nil)
        }
        XCTAssertEqual(intent(220).target, .combine(chat: chat.id))
        XCTAssertEqual(intent(70).edge, .leading, "a quarter in from the left inserts before Chat")
        XCTAssertEqual(intent(370).edge, .trailing, "a quarter in from the right inserts after Chat")
        XCTAssertNotEqual(intent(70).target, .combine(chat: chat.id))
    }
}
