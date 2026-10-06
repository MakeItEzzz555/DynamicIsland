import XCTest
@testable import DynamicIsland

/// Agents top lane: the usage band stays centered at intrinsic size; a
/// Compact widget configured directly before / after it occupies the left /
/// right wing. Notch lane: centered top content rises to sit exactly
/// `notchContentClearance` below the physical notch.
@MainActor
final class WorkspaceTopLaneTests: XCTestCase {
    private let notched = IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaInsets: .init(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRightArea: CGRect(x: 849, y: 950, width: 663, height: 32),
        backingScaleFactor: 2, displayID: nil, isBuiltIn: true,
        pixelSize: CGSize(width: 3024, height: 1964)))
    private var lane: WorkspaceNotchLane {
        ExpandedIslandLayoutMetrics.workspaceNotchLane(metrics: notched, isNotchIntegrated: true,
            pageCount: 4, clipboardEnabled: false, hardwareNotchWidth: 186)
    }
    private let available = CGSize(width: 1100, height: 600)

    private func region(_ kind: IslandWidget, _ size: WidgetPresentationSize, order: Int) -> WorkspaceWidgetRegion {
        let placement = WidgetPlacement(kind: kind, surface: .agents, order: order, size: size)
        return WorkspaceWidgetRegion(id: placement.id, widgets: [placement])
    }
    private func frames(_ regions: [WorkspaceWidgetRegion], editing: Bool = false, lane: WorkspaceNotchLane = .none,
                        size: CGSize? = nil) -> [IslandWidget: CGRect] {
        let projection = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: size ?? available,
            metrics: notched, editing: editing, lane: lane)
        var result: [IslandWidget: CGRect] = [:]
        for frame in projection.frames {
            if let kind = regions.first(where: { $0.id == frame.id })?.widgets.first?.kind { result[kind] = frame.frame }
        }
        return result
    }
    private var grid: WidgetGridMetrics { WidgetGridMetrics.make(surface: .agents, metrics: notched) }

    func testDefaultLayoutIsUnchanged() throws {
        let regions = WorkspaceConfiguration.initial.regions(on: .agents)
        let f = frames(regions)
        let usage = try XCTUnwrap(f[.agentUsage]), chat = try XCTUnwrap(f[.chat]), feed = try XCTUnwrap(f[.feed])
        XCTAssertEqual(feed.minY, chat.minY, accuracy: 0.01, "Feed follows a Standard Chat, so it is not a wing")
        XCTAssertGreaterThan(chat.minY, usage.maxY)
    }

    /// Live regression (2026-10-06): [usage, feed, chat] made Feed a wing, so
    /// the lane became a full unit tall and left ~125 pt blank above Chat.
    func testAWingThatWouldMakeTheContentTallerIsNotUsed() throws {
        let regions = [region(.agentUsage, .standard, order: 0), region(.feed, .compact, order: 1),
                       region(.chat, .standard, order: 2)]
        let f = frames(regions)
        let usage = try XCTUnwrap(f[.agentUsage]), feed = try XCTUnwrap(f[.feed]), chat = try XCTUnwrap(f[.chat])
        XCTAssertEqual(feed.minY, chat.minY, accuracy: 0.01, "Feed stays beside Chat")
        XCTAssertEqual(chat.minY, usage.maxY + grid.gutter, accuracy: 0.01, "no blank band above Chat")
    }

    func testCompactNeighboursOfTheBandBecomeWings() throws {
        let regions = [region(.timer, .compact, order: 0), region(.agentUsage, .standard, order: 1),
                       region(.feed, .compact, order: 2), region(.terminal, .standard, order: 3)]
        let f = frames(regions)
        let usage = try XCTUnwrap(f[.agentUsage]), timer = try XCTUnwrap(f[.timer])
        let feed = try XCTUnwrap(f[.feed]), chat = try XCTUnwrap(f[.terminal])
        XCTAssertEqual(timer.minY, usage.minY, accuracy: 0.01, "wings are top-aligned with the band")
        XCTAssertEqual(feed.minY, usage.minY, accuracy: 0.01)
        XCTAssertLessThanOrEqual(timer.maxX + grid.gutter, usage.minX + 0.01, "left wing")
        XCTAssertGreaterThanOrEqual(feed.minX, usage.maxX + grid.gutter - 0.01, "right wing")
        XCTAssertEqual(timer.width, grid.length(1), accuracy: 0.01, "wings keep their intrinsic Compact cell")
        XCTAssertEqual(usage.width, WidgetGridMetrics.bandSize(.agentUsage, .standard, metrics: notched).width, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(chat.minY, max(timer.maxY, feed.maxY) + grid.gutter - 0.01, "grid continues below the lane")
        let all = Array(f.values)
        for (i, a) in all.enumerated() { for b in all.dropFirst(i + 1) { XCTAssertFalse(a.insetBy(dx: 0.5, dy: 0.5).intersects(b)) } }
    }

    func testASingleWingKeepsTheBandCentered() throws {
        let regions = [region(.agentUsage, .standard, order: 0), region(.feed, .compact, order: 1)]
        let f = frames(regions)
        let usage = try XCTUnwrap(f[.agentUsage]), feed = try XCTUnwrap(f[.feed])
        XCTAssertEqual(feed.minY, usage.minY, accuracy: 0.01)
        XCTAssertEqual(usage.midX, available.width / 2, accuracy: 0.5, "band centered under the notch")
    }

    func testOnlyPlainCompactWidgetsAreWingCandidates() {
        XCTAssertTrue(WorkspaceWidgetLayoutProjection.isLaneWingCandidate(region(.feed, .compact, order: 0), grid: grid))
        XCTAssertFalse(WorkspaceWidgetLayoutProjection.isLaneWingCandidate(region(.feed, .standard, order: 0), grid: grid))
        XCTAssertFalse(WorkspaceWidgetLayoutProjection.isLaneWingCandidate(region(.agentUsage, .compact, order: 0), grid: grid))
        var stacked = region(.timer, .compact, order: 0)
        stacked.widgets[0].stacksBelowPrevious = true
        XCTAssertFalse(WorkspaceWidgetLayoutProjection.isLaneWingCandidate(stacked, grid: grid))
    }

    func testWingsFallBackToTheGridWhenTheLaneDoesNotFit() throws {
        let regions = [region(.agentUsage, .standard, order: 0), region(.feed, .compact, order: 1)]
        let narrow = CGSize(width: WidgetGridMetrics.bandSize(.agentUsage, .standard, metrics: notched).width + grid.length(1), height: 600)
        let f = frames(regions, size: narrow)
        XCTAssertGreaterThan(try XCTUnwrap(f[.feed]).minY, try XCTUnwrap(f[.agentUsage]).maxY, "no wing: Feed wraps below")
    }

    func testEditorPreviewMatchesTheCommittedArrangement() throws {
        let regions = [region(.timer, .compact, order: 0), region(.agentUsage, .standard, order: 1),
                       region(.feed, .compact, order: 2), region(.terminal, .standard, order: 3)]
        let committed = frames(regions), editing = frames(regions, editing: true)
        let c0 = try XCTUnwrap(committed[.agentUsage]).origin, e0 = try XCTUnwrap(editing[.agentUsage]).origin
        for kind in committed.keys {
            let c = try XCTUnwrap(committed[kind]), e = try XCTUnwrap(editing[kind])
            XCTAssertEqual(c.minX - c0.x, e.minX - e0.x, accuracy: 0.01, "\(kind)")
            XCTAssertEqual(c.minY - c0.y, e.minY - e0.y, accuracy: 0.01, "\(kind)")
            XCTAssertEqual(c.size, e.size)
        }
    }

    // MARK: Notch clearance

    func testVerticalNotchClearanceMatchesTheHorizontalToken() throws {
        let clearance = ExpandedIslandLayoutMetrics.notchContentClearance(metrics: notched)
        XCTAssertEqual(clearance, ExpandedIslandHeaderMetrics.notchClearance * notched.spacingScale, accuracy: 0.001)
        let chrome = ExpandedIslandLayoutMetrics(containerSize: .zero, horizontalPadding: 0, displayMetrics: notched)
        let contentTop = chrome.topPadding + chrome.tabSwitcherHeight + chrome.tabToPageSpacing
        XCTAssertEqual(notched.hardwareNotchHeight, 32)
        XCTAssertGreaterThan(lane.rise, 0)
        XCTAssertEqual(contentTop - lane.rise - notched.hardwareNotchHeight, clearance, accuracy: 0.01,
                       "content top sits exactly one clearance token below the notch")
        let regions = WorkspaceConfiguration.initial.regions(on: .agents)
        let usage = try XCTUnwrap(frames(regions, lane: lane)[.agentUsage])
        XCTAssertEqual(usage.minY, -lane.rise, accuracy: 0.01, "the centered band rises into the notch lane")
        let free = available.width / 2 - lane.headerGroupWidth - lane.clearance
        XCTAssertGreaterThanOrEqual(usage.minX, available.width / 2 - free - 0.01, "clear of the header groups")
        let plain = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions, maximumSize: available, metrics: notched)
        let risen = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions, maximumSize: available,
                                                                         metrics: notched, lane: lane)
        XCTAssertEqual(plain.height - risen.height, lane.rise, accuracy: 0.01, "the shell hugs the risen content")
    }

    func testNoRiseWhileEditingWithWingsOrWithoutANotch() throws {
        let regions = WorkspaceConfiguration.initial.regions(on: .agents)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames(regions, editing: true, lane: lane)[.agentUsage]).minY, 0,
                                    "edit chrome never enters the header")
        let winged = [region(.agentUsage, .standard, order: 0), region(.feed, .compact, order: 1)]
        let withLane = frames(winged, lane: lane), without = frames(winged)
        XCTAssertEqual(try XCTUnwrap(withLane[.agentUsage]).minY, try XCTUnwrap(without[.agentUsage]).minY,
                       accuracy: 0.01, "wings sit under the header groups, so the lane does not rise")
        XCTAssertEqual(try XCTUnwrap(withLane[.feed]).minY, try XCTUnwrap(withLane[.agentUsage]).minY, accuracy: 0.01)
        XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(metrics: .fallback, isNotchIntegrated: true,
            pageCount: 4, clipboardEnabled: false, hardwareNotchWidth: 0), .none)
        XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(metrics: notched, isNotchIntegrated: false,
            pageCount: 4, clipboardEnabled: false, hardwareNotchWidth: 186), .none)
    }
}
