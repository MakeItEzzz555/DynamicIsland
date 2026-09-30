import AppKit
import XCTest
@testable import DynamicIsland

final class ExpandedIslandMotionTests: XCTestCase {
    private func inputs(
        shell: TimeInterval = 0.40,
        instant: Bool = false,
        reduceMotion: Bool = false,
        blur: Bool = true,
        scale: Bool = true,
        lightweight: Bool = false,
        refreshRate: Int = 120
    ) -> ExpandedIslandMotion.Inputs {
        ExpandedIslandMotion.Inputs(
            shellDuration: shell,
            isInstant: instant,
            reduceMotion: reduceMotion,
            useBlurTransitions: blur,
            useScaleTransitions: scale,
            prefersLightweightEffects: lightweight,
            refreshRate: refreshRate
        )
    }

    // MARK: - Plan

    func testFullPlanMountsIncomingOnlyAfterTheShellHasLanded() {
        let plan = ExpandedIslandMotion.plan(inputs())

        XCTAssertEqual(plan.kind, .full)
        XCTAssertEqual(plan.shellDuration, 0.40, accuracy: 0.0001, "shell timing is never retuned")
        XCTAssertEqual(plan.outgoingDuration, 0.136, accuracy: 0.0001)
        // Outgoing leaves immediately; incoming children appear only once the
        // shell has fully reached its target size.
        XCTAssertLessThan(plan.outgoingDuration, plan.shellDuration)
        XCTAssertEqual(plan.handoffDelay, plan.shellDuration, accuracy: 0.0001)
    }

    func testFullPlanCompressesIncomingAndShrinksOutgoingFromTheTop() {
        let plan = ExpandedIslandMotion.plan(inputs())

        XCTAssertEqual(plan.outgoingScale, 0.96, accuracy: 0.0001)
        XCTAssertEqual(plan.incomingScale, 0.90, accuracy: 0.0001)
        XCTAssertEqual(plan.outgoingBlur, 6)
        XCTAssertEqual(plan.incomingBlur, 6)
    }

    func testIncomingSpringBouncesAfterTheShellLands() throws {
        let plan = ExpandedIslandMotion.plan(inputs())
        let spring = try XCTUnwrap(plan.incomingSpring)

        XCTAssertGreaterThan(spring.dampingRatio, 0.40, "premium, not wobbly")
        XCTAssertLessThan(spring.dampingRatio, 0.60, "must be visibly underdamped to bounce")
        let peak = plan.handoffDelay + spring.peakTime
        XCTAssertGreaterThan(peak, plan.shellDuration, "children bounce only inside the landed shell")
        XCTAssertGreaterThan(spring.overshoot, 0.18, "the child entrance must be visibly bouncy")
        XCTAssertLessThan(spring.overshoot, 0.24, "one premium bounce, not cartoon wobble")
    }

    func testPresetChangesScaleContentTimingWithTheShell() {
        let subtle = ExpandedIslandMotion.plan(inputs(shell: 0.28))
        let normal = ExpandedIslandMotion.plan(inputs(shell: 0.40))
        let slow = ExpandedIslandMotion.plan(inputs(shell: 0.54))

        XCTAssertEqual(subtle.outgoingDuration, 0.12, accuracy: 0.0001, "floor")
        XCTAssertLessThan(normal.outgoingDuration, slow.outgoingDuration)
        XCTAssertLessThan(subtle.handoffDelay, normal.handoffDelay)
        XCTAssertLessThan(normal.handoffDelay, slow.handoffDelay)
        XCTAssertLessThan(normal.incomingFadeDuration, slow.incomingFadeDuration)
        let subtleSpring = try! XCTUnwrap(subtle.incomingSpring)
        let normalSpring = try! XCTUnwrap(normal.incomingSpring)
        let slowSpring = try! XCTUnwrap(slow.incomingSpring)
        XCTAssertLessThan(subtleSpring.peakTime, normalSpring.peakTime)
        XCTAssertLessThan(normalSpring.peakTime, slowSpring.peakTime, "slow preset must slow the bounce itself")
        for plan in [subtle, normal, slow] {
            XCTAssertEqual(plan.handoffDelay, plan.shellDuration, accuracy: 0.0001)
        }
    }

    func testLowRefreshDisplaysLengthenContentButNotTheShell() throws {
        let fast = ExpandedIslandMotion.plan(inputs(refreshRate: 120))
        let slow = ExpandedIslandMotion.plan(inputs(refreshRate: 60))

        XCTAssertEqual(slow.shellDuration, fast.shellDuration)
        XCTAssertEqual(slow.outgoingDuration, fast.outgoingDuration * 1.18, accuracy: 0.0001)
        XCTAssertEqual(slow.incomingFadeDuration, fast.incomingFadeDuration * 1.18, accuracy: 0.0001)
        let fastSpring = try XCTUnwrap(fast.incomingSpring)
        let slowSpring = try XCTUnwrap(slow.incomingSpring)
        XCTAssertEqual(slowSpring.dampingRatio, fastSpring.dampingRatio, accuracy: 0.0001)
        XCTAssertEqual(slowSpring.peakTime, fastSpring.peakTime * 1.18, accuracy: 0.0001)
    }

    func testUserSlowMotionLengthensBounceWithoutChangingOvershoot() throws {
        let normal = ExpandedIslandMotion.plan(inputs(shell: 0.40))
        let slowest = ExpandedIslandMotion.plan(inputs(shell: 1.60))
        let normalSpring = try XCTUnwrap(normal.incomingSpring)
        let slowSpring = try XCTUnwrap(slowest.incomingSpring)

        XCTAssertGreaterThan(slowSpring.peakTime, normalSpring.peakTime * 3.9)
        XCTAssertEqual(slowSpring.dampingRatio, normalSpring.dampingRatio, accuracy: 0.0001)
        XCTAssertEqual(slowSpring.overshoot, normalSpring.overshoot, accuracy: 0.0001)
    }

    func testReduceMotionIsShortOpacityOnly() {
        let plan = ExpandedIslandMotion.plan(inputs(shell: 0.24, reduceMotion: true))

        XCTAssertEqual(plan.kind, .reduced)
        XCTAssertEqual(plan.outgoingScale, 1)
        XCTAssertEqual(plan.incomingScale, 1)
        XCTAssertEqual(plan.outgoingBlur, 0)
        XCTAssertEqual(plan.incomingBlur, 0)
        XCTAssertNil(plan.incomingSpring)
        XCTAssertLessThanOrEqual(plan.outgoingDuration, 0.14)
        XCTAssertLessThanOrEqual(plan.incomingFadeDuration, 0.16)
        XCTAssertEqual(plan.handoffDelay, plan.shellDuration, accuracy: 0.0001)
    }

    func testInstantPresetSwapsWithoutAnimation() {
        let plan = ExpandedIslandMotion.plan(inputs(shell: 0.01, instant: true))

        XCTAssertEqual(plan.kind, .instant)
        XCTAssertEqual(plan.handoffDelay, 0)
        XCTAssertEqual(plan.outgoingDuration, 0)
        XCTAssertEqual(plan.incomingFadeDuration, 0)
        XCTAssertNil(plan.incomingSpring)
    }

    func testBlurAndScaleSettingsAndLightweightEffectsAreRespected() {
        let noBlur = ExpandedIslandMotion.plan(inputs(blur: false))
        XCTAssertEqual(noBlur.incomingBlur, 0)
        XCTAssertEqual(noBlur.outgoingBlur, 0)
        XCTAssertNotEqual(noBlur.incomingScale, 1)

        let lightweight = ExpandedIslandMotion.plan(inputs(lightweight: true))
        XCTAssertEqual(lightweight.incomingBlur, 0)
        XCTAssertEqual(lightweight.outgoingBlur, 0)

        let noScale = ExpandedIslandMotion.plan(inputs(scale: false))
        XCTAssertEqual(noScale.incomingScale, 1)
        XCTAssertEqual(noScale.outgoingScale, 1)
        XCTAssertNil(noScale.incomingSpring)
        XCTAssertEqual(noScale.incomingBlur, 6)
    }

    // MARK: - Sampled choreography

    func testSampledSequenceHasNoOpacityPopGapOrLateBounce() throws {
        let plan = ExpandedIslandMotion.plan(inputs())

        let start = ExpandedIslandMotion.sample(plan, at: 0)
        XCTAssertEqual(start.outgoing, .identity)
        XCTAssertNil(start.incoming, "incoming is not mounted at t = 0")
        XCTAssertEqual(start.shellProgress, 0, accuracy: 0.0001)

        let mount = ExpandedIslandMotion.sample(plan, at: plan.handoffDelay)
        let incomingAtMount = try XCTUnwrap(mount.incoming)
        XCTAssertEqual(incomingAtMount.opacity, 0, accuracy: 0.0001, "no opacity pop on mount")
        XCTAssertEqual(incomingAtMount.scale, plan.incomingScale, accuracy: 0.0001)
        XCTAssertEqual(incomingAtMount.blur, plan.incomingBlur, accuracy: 0.0001)
        XCTAssertEqual(mount.shellProgress, 1, accuracy: 0.0001, "incoming mounts only after the shell landed")
        for step in 0..<100 {
            let beforeHandoff = ExpandedIslandMotion.sample(plan, at: plan.handoffDelay * Double(step) / 100)
            XCTAssertNil(beforeHandoff.incoming, "no child content while the shell is still morphing")
        }

        var previousOutgoing = 1.0
        var previousShell = 0.0
        var maxScale: CGFloat = 0
        for step in 0...300 {
            let time = Double(step) / 300 * 1.2
            let frame = ExpandedIslandMotion.sample(plan, at: time)
            XCTAssertGreaterThanOrEqual(frame.shellProgress + 1e-9, previousShell)
            previousShell = frame.shellProgress
            if let outgoing = frame.outgoing {
                XCTAssertLessThanOrEqual(outgoing.opacity, previousOutgoing + 1e-9)
                XCTAssertLessThanOrEqual(outgoing.scale, 1)
                previousOutgoing = outgoing.opacity
            }
            if let incoming = frame.incoming {
                maxScale = max(maxScale, incoming.scale)
                XCTAssertLessThanOrEqual(incoming.opacity, 1 + 1e-9)
                XCTAssertGreaterThanOrEqual(incoming.blur, -1e-9)
            }
        }
        XCTAssertGreaterThan(maxScale, 1.018, "incoming expansion has a perceptible spring overshoot")
        XCTAssertLessThan(maxScale, 1.03, "overshoot stays premium rather than cartoonish")

        let settledAt = plan.handoffDelay + max(plan.incomingFadeDuration, 0.4)
        let landed = ExpandedIslandMotion.sample(plan, at: settledAt)
        XCTAssertEqual(landed.shellProgress, 1, accuracy: 0.0001)
        XCTAssertNil(landed.outgoing)
        let incoming = try XCTUnwrap(landed.incoming)
        XCTAssertEqual(incoming.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(incoming.blur, 0, accuracy: 0.01)
        XCTAssertEqual(incoming.scale, 1, accuracy: 0.006)
    }

    func testReducedSamplesNeverScaleOrBlur() {
        let plan = ExpandedIslandMotion.plan(inputs(shell: 0.24, reduceMotion: true))
        for step in 0...60 {
            let frame = ExpandedIslandMotion.sample(plan, at: Double(step) / 60 * 0.3)
            for content in [frame.outgoing, frame.incoming].compactMap({ $0 }) {
                XCTAssertEqual(content.scale, 1)
                XCTAssertEqual(content.blur, 0)
            }
        }
    }

    func testBezierMatchesEndpointsAndEaseInOutSymmetry() {
        let c = ExpandedShellMorph.controlPoints
        XCTAssertEqual(ExpandedIslandMotion.bezier(0, c.c0x, c.c0y, c.c1x, c.c1y), 0, accuracy: 1e-6)
        XCTAssertEqual(ExpandedIslandMotion.bezier(1, c.c0x, c.c0y, c.c1x, c.c1y), 1, accuracy: 1e-6)
        XCTAssertEqual(ExpandedIslandMotion.bezier(0.5, c.c0x, c.c0y, c.c1x, c.c1y), 0.5, accuracy: 1e-4)
    }

    // MARK: - Page transition state

    func testInitialStateMountsTheSelectedPage() {
        let state = ExpandedPageTransitionState(page: .island)

        XCTAssertEqual(state.mountedPage, .island)
        XCTAssertEqual(state.targetPage, .island)
        XCTAssertFalse(state.isHandoffPending)
        XCTAssertFalse(state.animatesEntrance, "initial mount must not replay a tab entrance")
    }

    func testAnimatedSelectionUnmountsOutgoingThenMountsIncomingOnHandoff() {
        var state = ExpandedPageTransitionState(page: .island)
        let plan = ExpandedIslandMotion.plan(inputs())

        let effect = state.select(.agents, plan: plan)

        guard case let .scheduleHandoff(generation, delay) = effect else {
            return XCTFail("expected a scheduled handoff, got \(effect)")
        }
        XCTAssertEqual(delay, plan.handoffDelay)
        XCTAssertNil(state.mountedPage, "incoming must not be mounted before its generation is active")
        XCTAssertEqual(state.targetPage, .agents)
        XCTAssertTrue(state.isHandoffPending)

        XCTAssertTrue(state.completeHandoff(generation: generation))
        XCTAssertEqual(state.mountedPage, .agents)
        XCTAssertEqual(state.mountGeneration, generation)
        XCTAssertFalse(state.isHandoffPending)
        XCTAssertTrue(state.animatesEntrance)
    }

    func testStaleHandoffIsIgnoredDuringRapidSwitching() {
        var state = ExpandedPageTransitionState(page: .agents)
        let plan = ExpandedIslandMotion.plan(inputs())

        guard case let .scheduleHandoff(toIsland, _) = state.select(.island, plan: plan),
              case let .scheduleHandoff(backToAgents, _) = state.select(.agents, plan: plan) else {
            return XCTFail("expected scheduled handoffs")
        }

        XCTAssertFalse(state.completeHandoff(generation: toIsland), "stale Island handoff must not mount")
        XCTAssertNil(state.mountedPage)
        XCTAssertTrue(state.completeHandoff(generation: backToAgents))
        XCTAssertEqual(state.mountedPage, .agents)
        XCTAssertNotEqual(state.mountGeneration, 0, "re-mounted Agents gets a fresh identity")
        XCTAssertFalse(state.completeHandoff(generation: backToAgents), "handoff is one-shot")
    }

    func testSwitchDuringIncomingEntranceRemovesItAndHandsOffAgain() {
        var state = ExpandedPageTransitionState(page: .island)
        let plan = ExpandedIslandMotion.plan(inputs())
        guard case let .scheduleHandoff(first, _) = state.select(.tray, plan: plan) else {
            return XCTFail("expected a handoff")
        }
        state.completeHandoff(generation: first)

        guard case let .scheduleHandoff(second, _) = state.select(.tools, plan: plan) else {
            return XCTFail("expected a handoff")
        }
        XCTAssertNil(state.mountedPage)
        XCTAssertTrue(state.completeHandoff(generation: second))
        XCTAssertEqual(state.mountedPage, .tools)
    }

    func testReselectingThePendingTargetKeepsTheExistingHandoff() {
        var state = ExpandedPageTransitionState(page: .island)
        let plan = ExpandedIslandMotion.plan(inputs())
        guard case let .scheduleHandoff(generation, _) = state.select(.agents, plan: plan) else {
            return XCTFail("expected a handoff")
        }

        XCTAssertEqual(state.select(.agents, plan: plan), .none)
        XCTAssertTrue(state.completeHandoff(generation: generation))
        XCTAssertEqual(state.select(.agents, plan: plan), .none)
    }

    func testInstantPlanSwapsInPlace() {
        var state = ExpandedPageTransitionState(page: .island)
        let plan = ExpandedIslandMotion.plan(inputs(shell: 0.01, instant: true))

        XCTAssertEqual(state.select(.stats, plan: plan), .swapImmediately)
        XCTAssertEqual(state.mountedPage, .stats)
        XCTAssertFalse(state.isHandoffPending)
        XCTAssertFalse(state.animatesEntrance)
    }

    func testReduceMotionStillHandsOffAfterGeometryCommit() {
        var state = ExpandedPageTransitionState(page: .island)
        let plan = ExpandedIslandMotion.plan(inputs(shell: 0.24, reduceMotion: true))

        guard case let .scheduleHandoff(generation, delay) = state.select(.agents, plan: plan) else {
            return XCTFail("expected a handoff")
        }
        XCTAssertGreaterThan(delay, 0)
        XCTAssertTrue(state.completeHandoff(generation: generation))
        XCTAssertEqual(state.mountedPage, .agents)
    }

    func testSnapCancelsAPendingHandoff() {
        var state = ExpandedPageTransitionState(page: .island)
        let plan = ExpandedIslandMotion.plan(inputs())
        guard case let .scheduleHandoff(generation, _) = state.select(.agents, plan: plan) else {
            return XCTFail("expected a handoff")
        }

        state.snap(to: .agents)

        XCTAssertEqual(state.mountedPage, .agents)
        XCTAssertFalse(state.isHandoffPending)
        XCTAssertFalse(state.completeHandoff(generation: generation), "cancelled handoff must not remount")
        XCTAssertEqual(state.mountedPage, .agents)
        XCTAssertFalse(state.animatesEntrance)
    }

    func testSnapToTheMountedPageIsANoOp() {
        var state = ExpandedPageTransitionState(page: .island)
        let before = state

        state.snap(to: .island)

        XCTAssertEqual(state, before, "snapping to the settled page must not remount it")
    }
}

// MARK: - Contraction: collapse and shrinking page changes mirror expansion
//
// Runtime regression: collapse flipped the island state in the same turn the
// child exit started, so the shell contracted around still-visible children
// (squeeze/clip) and page bodies vanished. Expansion waits for the shell
// before children appear; contraction must wait for children before the shell.

final class IslandContractionMotionTests: XCTestCase {
    private let step: TimeInterval = 1.0 / 120.0

    private func inputs(
        shell: TimeInterval = 0.40,
        instant: Bool = false,
        reduceMotion: Bool = false
    ) -> ExpandedIslandMotion.Inputs {
        ExpandedIslandMotion.Inputs(
            shellDuration: shell,
            isInstant: instant,
            reduceMotion: reduceMotion,
            useBlurTransitions: true,
            useScaleTransitions: true,
            prefersLightweightEffects: false,
            refreshRate: 120
        )
    }

    private func frames(for page: ExpandedIslandPage) -> (expanded: CGRect, collapsed: CGRect) {
        let size = CGSize(width: 1512, height: 982)
        let screen = ScreenSnapshot(
            frame: CGRect(origin: .zero, size: size),
            visibleFrame: CGRect(x: 0, y: 0, width: size.width, height: size.height - 32),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: size.height - 32, width: 666, height: 32),
            auxiliaryTopRightArea: CGRect(x: 846, y: size.height - 32, width: 666, height: 32)
        )
        let expandedSize = ExpandedPresentationProfile.resolve(for: page).resolvedSize(from: CGSize(width: 860, height: 286))
        let geometry = NotchGeometryService().geometry(
            for: screen,
            collapsedSize: CGSize(width: 190, height: 34),
            expandedSize: expandedSize
        )
        return (geometry.expandedFrame, geometry.collapsedFrame)
    }

    /// Samples every frame of a contraction and checks the mirror contract.
    private func assertContraction(
        _ plan: ExpandedIslandMotion.ContractionPlan,
        from source: CGRect,
        to target: CGRect,
        label: String
    ) {
        var sawChildExit = false
        var previous = source
        var t: TimeInterval = 0
        while t <= plan.totalDuration + step {
            let sample = ExpandedIslandMotion.sampleContraction(plan, at: t, from: source, to: target)
            let frame = sample.shellFrame
            if let child = sample.outgoing, child.opacity < 0.999 { sawChildExit = true }
            if frame != source {
                // The shell has started contracting: children are already gone.
                XCTAssertNil(sample.outgoing, "\(label): child visible while shell contracts at t=\(t)")
            }
            XCTAssertEqual(frame.maxY, source.maxY, accuracy: 0.001, "\(label): top edge moved at t=\(t)")
            XCTAssertEqual(frame.midX, source.midX, accuracy: 0.001, "\(label): center moved at t=\(t)")
            XCTAssertLessThanOrEqual(frame.width, previous.width + 0.001, "\(label): shell width bounced at t=\(t)")
            XCTAssertLessThanOrEqual(frame.height, previous.height + 0.001, "\(label): shell height bounced at t=\(t)")
            XCTAssertGreaterThanOrEqual(frame.height, target.height - 0.001, "\(label): shell overshot at t=\(t)")
            previous = frame
            t += step
        }
        XCTAssertTrue(sawChildExit || plan.childExitDuration == 0, "\(label): child exit must be visible")
        let end = ExpandedIslandMotion.sampleContraction(plan, at: plan.totalDuration + step, from: source, to: target)
        XCTAssertEqual(end.shellFrame, target, "\(label): shell lands exactly on the collapsed frame")
    }

    func testEveryPrimaryPageCollapsesChildrenFirstThenShellTopPinned() {
        let plan = ExpandedIslandMotion.collapsePlan(inputs())
        for page in [ExpandedIslandPage.island, .agents, .tray, .timer, .stats, .tools, .messages] {
            let f = frames(for: page)
            assertContraction(plan, from: f.expanded, to: f.collapsed, label: "\(page) -> collapsed")
        }
    }

    func testCollapseChildExitStartsImmediatelyAndMatchesTheRunningExitAnimation() {
        let plan = ExpandedIslandMotion.collapsePlan(inputs())
        // Same duration InnerBlurScaleCleanModifier runs, plus its max stagger.
        XCTAssertEqual(
            plan.childExitDuration,
            IslandContentTransitionTiming.collapseContentDuration(shellDuration: 0.40)
                + IslandContentTransitionTiming.collapseExitStaggerAllowance,
            accuracy: 0.0001
        )
        XCTAssertEqual(plan.shellCommitDelay, plan.childExitDuration, accuracy: 0.0001)
        XCTAssertEqual(plan.shellDuration, 0.40, accuracy: 0.0001, "shell timing is the shared SSOT")
        let early = ExpandedIslandMotion.sampleContraction(plan, at: 0.03, from: .init(x: 0, y: 0, width: 800, height: 300), to: .init(x: 300, y: 256, width: 200, height: 44))
        XCTAssertLessThan(try XCTUnwrap(early.outgoing).opacity, 1)
        XCTAssertEqual(plan.childExitScale, IslandContentTransitionTiming.collapseExitScale)
        XCTAssertEqual(plan.childExitBlur, IslandContentTransitionTiming.collapseExitBlur)
    }

    func testSlowMotionLengthensAndFastShortensTheChildExit() {
        let normal = ExpandedIslandMotion.collapsePlan(inputs(shell: 0.40))
        let slow = ExpandedIslandMotion.collapsePlan(inputs(shell: 0.80))
        let fast = ExpandedIslandMotion.collapsePlan(inputs(shell: 0.25))
        XCTAssertGreaterThan(slow.childExitDuration, normal.childExitDuration * 1.8)
        XCTAssertLessThan(fast.childExitDuration, normal.childExitDuration)
        XCTAssertEqual(slow.shellCommitDelay, slow.childExitDuration, accuracy: 0.0001)
        XCTAssertEqual(slow.shellDuration, 0.80, accuracy: 0.0001)
    }

    func testReduceMotionKeepsTheSequenceButDropsScaleAndBlur() {
        let plan = ExpandedIslandMotion.collapsePlan(inputs(shell: 0.24, reduceMotion: true))
        XCTAssertEqual(plan.childExitScale, 1)
        XCTAssertEqual(plan.childExitBlur, 0)
        XCTAssertEqual(plan.childExitDuration, IslandContentTransitionTiming.reducedCollapseExitDuration, accuracy: 0.0001)
        XCTAssertGreaterThan(plan.shellCommitDelay, 0, "children still leave before the shell contracts")
        let f = frames(for: .agents)
        assertContraction(plan, from: f.expanded, to: f.collapsed, label: "reduce motion agents -> collapsed")
        var t: TimeInterval = 0
        while t < plan.childExitDuration {
            let child = ExpandedIslandMotion.sampleContraction(plan, at: t, from: f.expanded, to: f.collapsed).outgoing
            XCTAssertEqual(child?.scale ?? 1, 1)
            XCTAssertEqual(child?.blur ?? 0, 0)
            t += step
        }
    }

    func testInstantCollapseCommitsTheShellImmediately() {
        let plan = ExpandedIslandMotion.collapsePlan(inputs(shell: 0.01, instant: true))
        XCTAssertEqual(plan.shellCommitDelay, 0)
        XCTAssertEqual(plan.childExitDuration, 0)
    }

    func testShrinkingPageChangeExitsOutgoingBeforeShellAndMountsIncomingAfterIt() {
        let page = ExpandedIslandMotion.plan(inputs())
        let from = frames(for: .agents).expanded
        let to = frames(for: .island).expanded
        XCTAssertTrue(ExpandedIslandMotion.shellShrinks(from: from.size, to: to.size))
        let plan = ExpandedIslandMotion.shrinkingPagePlan(page)
        XCTAssertEqual(plan.childExitDuration, page.outgoingDuration, accuracy: 0.0001)
        XCTAssertEqual(plan.shellCommitDelay, page.outgoingDuration, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(plan.incomingHandoffDelay), page.outgoingDuration + page.shellDuration, accuracy: 0.0001)
        assertContraction(plan, from: from, to: to, label: "agents -> island")
    }

    func testGrowingPageChangeKeepsTheExistingExpansionChoreography() {
        let from = frames(for: .island).expanded
        let to = frames(for: .agents).expanded
        XCTAssertFalse(ExpandedIslandMotion.shellShrinks(from: from.size, to: to.size))
    }

    // MARK: Generation-safe reversal

    func testCollapseInterruptedByExpansionNeverCommits() {
        var request = IslandCollapseRequest()
        let generation = request.begin()
        XCTAssertTrue(request.cancel(), "expansion during the child exit cancels the collapse")
        XCTAssertFalse(request.commit(generation), "stale collapse completion must not hide newer content")
    }

    func testOnlyTheNewestCollapseRequestCommits() {
        var request = IslandCollapseRequest()
        let first = request.begin()
        _ = request.cancel()
        let second = request.begin()
        XCTAssertFalse(request.commit(first))
        XCTAssertTrue(request.commit(second))
        XCTAssertFalse(request.commit(second), "a collapse commits once")
        XCTAssertFalse(request.cancel(), "nothing pending after commit")
    }

    func testExpansionInterruptedByCollapseKeepsChildrenHidden() {
        // Expansion reveal is guarded by `isExpandedContentExiting`; a collapse
        // requested mid-expansion begins the exit and owns the next commit.
        var request = IslandCollapseRequest()
        let generation = request.begin()
        XCTAssertTrue(request.isPending)
        XCTAssertTrue(request.commit(generation))
        XCTAssertFalse(request.isPending)
    }
}
