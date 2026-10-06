import XCTest
@testable import DynamicIsland

final class WorkspaceGeometrySequencingTests: XCTestCase {
    func testChildrenExitBeforeGeometryCanCommitAndRevealRequiresSameGeneration() {
        var transition = WorkspaceGeometryTransition()
        transition.request(.init(width: 440, height: 260))
        let first = transition.generation
        XCTAssertEqual(transition.phase, .childrenExiting)
        transition.complete(generation: first)
        XCTAssertEqual(transition.phase, .childrenExiting)
        XCTAssertTrue(transition.childrenExited(generation: first))
        XCTAssertEqual(transition.phase, .shellResizing)
        transition.complete(generation: first)
        XCTAssertEqual(transition.phase, .idle)
    }

    func testRapidReconfigurationAndCollapseRejectStaleCompletions() {
        var transition = WorkspaceGeometryTransition()
        transition.request(.init(width: 900, height: 500))
        let first = transition.generation
        transition.request(.init(width: 440, height: 260))
        let newest = transition.generation
        XCTAssertEqual(newest, first, "Target changes join the outstanding child exit")
        XCTAssertEqual(transition.targetSize, CGSize(width: 440, height: 260))
        XCTAssertTrue(transition.childrenExited(generation: newest))
        transition.cancel()
        transition.complete(generation: newest)
        XCTAssertEqual(transition.phase, .idle)
        transition.request(.init(width: 700, height: 420))
        XCTAssertFalse(transition.childrenExited(generation: newest))
        XCTAssertEqual(transition.phase, .childrenExiting)
    }

    @MainActor func testSingleWidgetShellShrinksBothAxesAndEditingReservesPalette() {
        let suite = "WorkspaceGeometrySequencingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.timerEnabled = true
        var config = WorkspaceConfiguration(placements: [.init(kind: .timer, surface: .media, order: 0)])
        config.customizedSurfaces.append(.media)
        let profile = ExpandedPresentationProfile.resolve(for: .island)
        let base = CGSize(width: 960, height: 600)
        let one = profile.resolvedSize(from: base, page: .island, configuration: config,
            editing: false, settings: settings, metrics: .fallback)
        let editing = profile.resolvedSize(from: base, page: .island, configuration: config,
            editing: true, settings: settings, metrics: .fallback)
        XCTAssertLessThan(one.width, base.width)
        XCTAssertLessThan(one.height, base.height)
        XCTAssertGreaterThan(editing.height, one.height)
        config.add(.calendar, on: .media)
        let two = profile.resolvedSize(from: base, page: .island, configuration: config,
            editing: false, settings: settings, metrics: .fallback)
        XCTAssertGreaterThan(two.width, one.width, "a second Standard widget adds grid columns")
        XCTAssertGreaterThanOrEqual(two.height, one.height)
    }

    @MainActor func testPreviewAndNativeControlOwnershipAreLocalAndDeduplicated() {
        let store = IslandLayoutStore()
        let owner = UUID(), replacement = UUID()
        store.setNativeControlRegion(.init(x: 100, y: 50, width: 200, height: 60), owner: owner)
        store.setNativeControlRegion(.init(x: 100, y: 50, width: 200, height: 60), owner: replacement)
        store.setNativeControlRegion(nil, owner: owner)
        XCTAssertTrue(store.containsNativeControlPoint(.init(x: 150, y: 75)))
        XCTAssertFalse(store.containsNativeControlPoint(.init(x: 10, y: 75)))
        store.setNativeControlRegion(nil, owner: replacement)
        XCTAssertTrue(store.nativeControlRegions.isEmpty)
        store.setWorkspaceLayoutPreview(.initial, surface: .media)
        XCTAssertEqual(store.workspaceLayoutPreview?.surface, .media)
        store.setWorkspaceLayoutPreview(.initial, surface: .agents)
        store.setWorkspaceLayoutPreview(nil, surface: .media)
        XCTAssertEqual(store.workspaceLayoutPreview?.surface, .agents)
        store.setWorkspaceLayoutPreview(nil, surface: .agents)
        store.setWorkspaceLayoutPreview(nil, surface: .media)
        XCTAssertNil(store.workspaceLayoutPreview)
    }

    @MainActor func testUsageRowHasBoundedHeightRatherThanAbsorbingTranscriptSpace() {
        // Provider-grouped row: ring + metric caption, identity beside the rings.
        XCTAssertEqual(AgentWorkspaceUsageStrip.rowHeight(for: 1000), 64)
        XCTAssertEqual(AgentWorkspaceUsageStrip.rowHeight(for: 500), 56)
    }

    @MainActor func testCollapseAcknowledgementRejectsRetiredAndDuplicateExits() {
        let layout = IslandLayoutStore()
        layout.expandedChildExitGeneration = 1
        layout.expandedChildExitGeneration = 3
        layout.acknowledgeExpandedChildExit(generation: 1)
        XCTAssertEqual(layout.expandedChildExitAcknowledgement, 0)
        layout.acknowledgeExpandedChildExit(generation: 3)
        XCTAssertEqual(layout.expandedChildExitAcknowledgement, 3)
        layout.acknowledgeExpandedChildExit(generation: 1)
        XCTAssertEqual(layout.expandedChildExitAcknowledgement, 3)
    }

    @MainActor func testEditorUnmountCannotShrinkGeometryWhileChildrenExit() {
        let layout = IslandLayoutStore()
        let editing = CGSize(width: 867, height: 362)
        let saved = CGSize(width: 867, height: 294)
        layout.isExpandedContentExiting = true
        // Clearing the transient draft on collapse changes desired size before
        // the removal ends; physical geometry must still retain its edit budget.
        XCTAssertEqual(layout.expandedPresentationSize(desired: saved, committed: editing, isExpanded: true), editing)
        XCTAssertEqual(layout.expandedPresentationSize(desired: saved, committed: editing, isExpanded: false), saved)
        layout.isExpandedContentExiting = false
        XCTAssertEqual(layout.expandedPresentationSize(desired: saved, committed: editing, isExpanded: true), saved)
    }

    @MainActor func testCompactShellIncludesConfiguredNavigationHeader() {
        let defaults = UserDefaults(suiteName: "CompactHeader.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.trayEnabled = true
        settings.fileShelfEnabled = true
        let config = WorkspaceConfiguration(placements: [.init(kind: .files, surface: .media, order: 0)], customizedSurfaces: [.media])
        let header = ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: 7, clipboardEnabled: true)
        let size = ExpandedPresentationProfile.resolve(for: .island).resolvedSize(
            from: .init(width: 960, height: 600), page: .island, configuration: config,
            editing: false, settings: settings, metrics: .fallback, minimumHeaderWidth: header)
        let chrome = IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: ResolvedIslandMetrics.fallback.hasHardwareNotch && settings.respectHardwareNotch) * 2
        XCTAssertGreaterThanOrEqual(size.width - chrome, header)
        XCTAssertLessThan(size.width, 500)
    }
}
