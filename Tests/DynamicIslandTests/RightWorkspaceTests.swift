import XCTest
@testable import DynamicIsland

final class RightWorkspaceTests: XCTestCase {
    // MARK: Swipe recognizer (Droppy semantics + one page per gesture)

    func testHorizontalSwipePastThresholdPagesOnceEvenWithMomentum() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(deltaX: -12, deltaY: 1, phase: .began, at: 0), .consumed)
        XCTAssertEqual(recognizer.handle(deltaX: -12, deltaY: 0, phase: .changed, at: 0.01), .consumed)
        XCTAssertEqual(recognizer.handle(deltaX: -12, deltaY: 0, phase: .changed, at: 0.02), .next)
        // Continued movement and momentum in the same gesture never page again.
        XCTAssertEqual(recognizer.handle(deltaX: -60, deltaY: 0, phase: .changed, at: 0.03), .consumed)
        XCTAssertEqual(recognizer.handle(deltaX: -80, deltaY: 0, phase: .momentum, at: 0.05), .consumed)
        XCTAssertEqual(recognizer.handle(deltaX: -80, deltaY: 0, phase: .momentum, at: 0.2), .consumed)
    }

    func testRightSwipeIsPreviousAndThresholdIsThirty() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(deltaX: 30, deltaY: 0, phase: .began, at: 0), .consumed, "exactly 30 is not past threshold")
        XCTAssertEqual(recognizer.handle(deltaX: 1, deltaY: 0, phase: .changed, at: 0.01), .previous)
    }

    func testVerticalScrollLocksToContentForWholeGesture() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(deltaX: 3, deltaY: -20, phase: .began, at: 0), .passThrough)
        XCTAssertEqual(recognizer.owner, .verticalContent)
        XCTAssertEqual(
            recognizer.handle(deltaX: 24, deltaY: 4, phase: .changed, at: 0.01),
            .passThrough,
            "Once vertical owns the gesture, later horizontal noise cannot retarget it"
        )
        XCTAssertEqual(
            recognizer.handle(deltaX: -40, deltaY: -2, phase: .momentum, at: 0.02),
            .passThrough,
            "Momentum remains with the ScrollView"
        )
    }

    func testStrongHorizontalLocksOutVerticalDrift() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(deltaX: -18, deltaY: 5, phase: .began, at: 0), .consumed)
        XCTAssertEqual(recognizer.owner, .horizontalPaging)
        XCTAssertEqual(
            recognizer.handle(deltaX: 1, deltaY: 40, phase: .changed, at: 0.01),
            .consumed,
            "Once horizontal owns the gesture, vertical drift cannot hand it to content"
        )
    }

    func testTinyFirstFramePassesThroughWithoutLeakingToGlobalGestureRouter() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(deltaX: 0.4, deltaY: 0.5, phase: .began, at: 0), .passThrough)
        XCTAssertNil(recognizer.owner)
        XCTAssertEqual(recognizer.handle(deltaX: -12, deltaY: 2, phase: .changed, at: 0.01), .consumed)
        XCTAssertEqual(recognizer.owner, .horizontalPaging)
    }

    func testQuietGapStartsANewGestureThatCanPageAgain() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(deltaX: -40, deltaY: 0, phase: .none, at: 0), .next)
        XCTAssertEqual(recognizer.handle(deltaX: -40, deltaY: 0, phase: .none, at: 0.2), .consumed)
        XCTAssertEqual(recognizer.handle(deltaX: -40, deltaY: 0, phase: .none, at: 0.55), .next,
                       "more than 0.3 s of quiet is a new gesture")
    }

    /// A vertical scroll that reaches the ScrollView edge keeps producing
    /// deltas (overscroll, diagonal drift, momentum). None of it may turn
    /// into a page swipe, however large the horizontal component becomes.
    func testScrollEdgeOvershootNeverBecomesPageSwipe() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        var outcomes: [RightWorkspaceSwipeRecognizer.Outcome] = []
        outcomes.append(recognizer.handle(deltaX: 0, deltaY: -14, phase: .began, at: 0))
        var time = 0.0
        for step in 0..<40 {
            time += 0.016
            // Edge reached: user drifts sideways hard while still dragging.
            let dx: CGFloat = step < 10 ? -1 : -45
            outcomes.append(recognizer.handle(deltaX: dx, deltaY: -2, phase: .changed, at: time))
        }
        outcomes.append(recognizer.handle(deltaX: -60, deltaY: 0, phase: .ended, at: time + 0.016))
        for step in 0..<20 {
            outcomes.append(recognizer.handle(deltaX: -80, deltaY: -1, phase: .momentum, at: time + 0.032 + Double(step) * 0.016))
        }
        XCTAssertTrue(outcomes.allSatisfy { $0 == .passThrough }, "\(outcomes)")
        XCTAssertEqual(recognizer.owner, .verticalContent)
    }

    /// Horizontal paging over the Productivity page with the Camera Mirror
    /// active: the recognizer is consulted before the mirror scroll policy,
    /// and one physical swipe pages exactly once.
    func testHorizontalSwipeOverMirrorPagesExactlyOnce() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        var pageChanges = 0
        var time = 0.0
        let first = recognizer.handle(deltaX: -8, deltaY: 1, phase: .began, at: time)
        if first == .next || first == .previous { pageChanges += 1 }
        for _ in 0..<30 {
            time += 0.016
            let outcome = recognizer.handle(deltaX: -9, deltaY: 0.5, phase: .changed, at: time)
            if outcome == .next || outcome == .previous { pageChanges += 1 }
        }
        for _ in 0..<30 {
            time += 0.016
            let outcome = recognizer.handle(deltaX: -20, deltaY: 0, phase: .momentum, at: time)
            if outcome == .next || outcome == .previous { pageChanges += 1 }
        }
        XCTAssertEqual(pageChanges, 1)
        XCTAssertFalse(CameraMirrorScrollRoutingPolicy.shouldPassThroughToContent(
            mirrorActive: true, pointerInsideRightWorkspace: true, deltaX: -9, deltaY: 0.5
        ), "strong horizontal input is never swallowed by the mirror vertical policy")
    }

    func testMomentumAloneNeverPages() {
        var recognizer = RightWorkspaceSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(deltaX: -10, deltaY: 0, phase: .began, at: 0), .consumed)
        XCTAssertEqual(recognizer.handle(deltaX: -10, deltaY: 0, phase: .ended, at: 0.01), .consumed)
        XCTAssertEqual(recognizer.handle(deltaX: -90, deltaY: 0, phase: .momentum, at: 0.02), .consumed)
    }

    // MARK: Configuration

    func testNormalizationRemovesDuplicatesAddsMissingAndKeepsAVisiblePage() {
        var config = RightWorkspaceConfiguration.default
        config.pageOrder = [.productivity, .productivity]
        config.hiddenPages = Set(RightWorkspacePage.allCases)
        config.defaultPage = .appsMedia
        config.toolOrder = [.voice, .voice, .camera]
        let normalized = config.normalized

        XCTAssertEqual(normalized.pageOrder, [.productivity, .overview, .appsMedia])
        XCTAssertEqual(normalized.visiblePages, [.overview])
        XCTAssertEqual(normalized.defaultPage, .overview)
        XCTAssertEqual(normalized.toolOrder.count, RightWorkspaceTool.allCases.count)
        XCTAssertEqual(Array(normalized.toolOrder.prefix(2)), [.voice, .camera])
    }

    func testRelativePageOffsetsAreStableAcrossSwitches() {
        let pages: [RightWorkspacePage] = [.overview, .productivity, .appsMedia]
        func relative(_ page: RightWorkspacePage, current: RightWorkspacePage) -> Int {
            let pageIndex = pages.firstIndex(of: page)!
            let currentIndex = pages.firstIndex(of: current)!
            return pageIndex - currentIndex
        }
        XCTAssertEqual(relative(.overview, current: .productivity), -1)
        XCTAssertEqual(relative(.productivity, current: .productivity), 0)
        XCTAssertEqual(relative(.appsMedia, current: .productivity), 1)
        XCTAssertEqual(relative(.productivity, current: .appsMedia), -1)
    }

    @MainActor
    func testStorePersistsOrderPagesWithoutWrappingAndDirection() throws {
        let suite = "RightWorkspaceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RightWorkspaceStore(defaults: defaults)
        XCTAssertEqual(store.currentPage, .overview)
        XCTAssertFalse(store.showPrevious(), "no wrap at the first page")
        XCTAssertTrue(store.showNext())
        XCTAssertEqual(store.currentPage, .productivity)
        XCTAssertEqual(store.transitionDirection, 1)
        XCTAssertTrue(store.showPrevious())
        XCTAssertEqual(store.transitionDirection, -1)

        store.update {
            $0.move(\.pageOrder, item: .appsMedia, by: -2)
            $0.hiddenSections.insert(.calendar)
            $0.defaultPage = .appsMedia
        }
        let reloaded = RightWorkspaceStore(defaults: defaults)
        XCTAssertEqual(reloaded.configuration.pageOrder, [.appsMedia, .overview, .productivity])
        XCTAssertEqual(reloaded.configuration.visibleSections, [.appLibrary, .spotify])
        XCTAssertEqual(reloaded.currentPage, .appsMedia)

        reloaded.update { $0.hiddenPages.insert(.appsMedia) }
        XCTAssertEqual(reloaded.currentPage, reloaded.configuration.defaultPage)
        XCTAssertNotEqual(reloaded.currentPage, .appsMedia)

        reloaded.resetToDefaults()
        XCTAssertEqual(reloaded.configuration, .default)
    }
}
