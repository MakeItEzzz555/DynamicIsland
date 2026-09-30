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

    func testFullPlanOrdersOutgoingHandoffIncomingInsideShellMorph() {
        let plan = ExpandedIslandMotion.plan(inputs())

        XCTAssertEqual(plan.kind, .full)
        XCTAssertEqual(plan.shellDuration, 0.40, accuracy: 0.0001, "shell timing is never retuned")
        XCTAssertEqual(plan.outgoingDuration, 0.136, accuracy: 0.0001)
        // The incoming page mounts before the outgoing page has fully left
        // (no empty-shell gap) but only after the geometry has been committed.
        XCTAssertGreaterThan(plan.handoffDelay, 0)
        XCTAssertLessThan(plan.handoffDelay, plan.outgoingDuration)
        XCTAssertLessThan(plan.handoffDelay, plan.shellDuration / 2)
        // Opacity resolves before the shell lands.
        XCTAssertLessThanOrEqual(plan.handoffDelay + plan.incomingFadeDuration, plan.shellDuration)
    }

    func testFullPlanCompressesIncomingAndShrinksOutgoingFromTheTop() {
        let plan = ExpandedIslandMotion.plan(inputs())

        XCTAssertEqual(plan.outgoingScale, 0.96, accuracy: 0.0001)
        XCTAssertEqual(plan.incomingScale, 0.90, accuracy: 0.0001)
        XCTAssertEqual(plan.outgoingBlur, 6)
        XCTAssertEqual(plan.incomingBlur, 6)
    }

    func testIncomingSpringBouncesAndPeaksAsTheShellLands() throws {
        let plan = ExpandedIslandMotion.plan(inputs())
        let spring = try XCTUnwrap(plan.incomingSpring)

        XCTAssertGreaterThan(spring.dampingRatio, 0.5, "premium, not wobbly")
        XCTAssertLessThan(spring.dampingRatio, 1, "must be underdamped to bounce")
        let peak = plan.handoffDelay + spring.peakTime
        XCTAssertEqual(peak, plan.shellDuration, accuracy: 0.06, "bounce peak coincides with the shell landing, not late")
        XCTAssertLessThan(spring.overshoot, 0.05)
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
        for plan in [subtle, normal, slow] {
            XCTAssertLessThan(plan.handoffDelay, plan.outgoingDuration)
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
        XCTAssertLessThan(plan.handoffDelay, plan.outgoingDuration)
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
        XCTAssertGreaterThan(try XCTUnwrap(mount.outgoing).opacity, 0, "outgoing still visible at handoff: no empty-shell gap")

        var previousOutgoing = 1.0
        var previousShell = 0.0
        var maxScale: CGFloat = 0
        for step in 0...300 {
            let time = Double(step) / 300 * 0.8
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
        XCTAssertGreaterThan(maxScale, 1, "incoming expansion has a visible spring overshoot")
        XCTAssertLessThan(maxScale, 1.006, "overshoot stays subtle")

        let landed = ExpandedIslandMotion.sample(plan, at: plan.shellDuration)
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
