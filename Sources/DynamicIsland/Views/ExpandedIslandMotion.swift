// Portions adapted from Droppy (https://github.com/1of1Adam/Droppy) at commit
// dd2d16ccbdc6aa22b456e199442b43a07aa446af:
// - Droppy/AppKitMotion.swift: animateIn (initial scale 0.9, CASpringAnimation
//   mass 1 / stiffness 260 / damping 24, fade on the (0.22, 1, 0.36, 1) curve),
//   animateOut (target scale 0.96 on the (0.4, 0, 0.2, 1) curve) and their
//   reduced-motion caps (0.16 s in, 0.14 s out, no scale).
// - Droppy/DroppyAnimation.swift: display-refresh motion scale, lightweight
//   (no-blur) effects at <= 60 Hz / Low Power, NotchBlurModifier's
//   scale(anchor: .top) + blur(6) + opacity treatment.
// Droppy is licensed GPL-3.0 with the Commons Clause; reused here for a
// private, personal build only. See research/SOURCE_PARITY_MANIFEST.md.

import AppKit
import SwiftUI

/// An in-place configuration handoff keeps the page/controllers mounted. The
/// child animation acknowledges its exit before the existing shell resolver
/// commits new bounds; generation checks reject rapid/stale reconfigurations.
struct WorkspaceGeometryTransition: Equatable {
    enum Phase { case idle, childrenExiting, shellResizing }
    private(set) var generation = 0
    private(set) var phase: Phase = .idle
    private(set) var targetSize: CGSize = .zero

    mutating func request(_ size: CGSize) {
        targetSize = size
        // A changed target during exit joins the same removal transaction.
        // Once hidden, newer geometry can resize directly without replaying it.
        if phase == .childrenExiting { return }
        generation &+= 1
        if phase == .idle { phase = .childrenExiting }
    }
    mutating func childrenExited(generation expected: Int) -> Bool {
        guard expected == generation, phase == .childrenExiting else { return false }
        phase = .shellResizing
        return true
    }
    mutating func complete(generation expected: Int) {
        guard expected == generation, phase == .shellResizing else { return }
        phase = .idle
    }
    mutating func cancel() { generation &+= 1; phase = .idle }
}

/// Single source of truth for expanded tab-to-tab content choreography.
///
/// Sequence (Normal preset, 0.40 s shell, 120 Hz):
/// 1. t = 0: the outgoing page is unmounted and plays its removal: shrinks
///    toward the top (0.96), blurs and fades over `outgoingDuration`.
/// 2. t ~ 1 run-loop turn: `OverlayWindowController` commits the target
///    geometry and the shell morphs top-pinned (`ExpandedShellMorph`). The
///    shell timing is owned there and is never retuned here.
/// 3. t = `handoffDelay`: the incoming page is mounted, already laid out at the
///    target metrics, from a compressed (0.90, top anchor), blurred, transparent
///    state. Blur/opacity resolve on Droppy's open curve; scale expands on an
///    underdamped spring whose single small overshoot peaks as the shell lands.
///
/// The outer shell is never scaled; only inner page content is.
enum ExpandedIslandMotion {
    enum Kind: Equatable {
        case full
        case reduced
        case instant
    }

    struct Inputs: Equatable {
        var shellDuration: TimeInterval
        /// Instant preset or content animation disabled.
        var isInstant: Bool
        var reduceMotion: Bool
        var useBlurTransitions: Bool
        var useScaleTransitions: Bool
        var prefersLightweightEffects: Bool
        var refreshRate: Int
    }

    /// Damped harmonic spring (same parameters as CASpringAnimation).
    struct Spring: Equatable {
        var mass: Double
        var stiffness: Double
        var damping: Double

        var naturalFrequency: Double { (stiffness / mass).squareRoot() }
        var dampingRatio: Double { damping / (2 * (stiffness * mass).squareRoot()) }
        private var dampedFrequency: Double {
            naturalFrequency * max(1 - dampingRatio * dampingRatio, 0).squareRoot()
        }
        /// Time of the first (and only visible) overshoot peak.
        var peakTime: Double { .pi / dampedFrequency }
        /// Fractional overshoot of the first peak.
        var overshoot: Double {
            let ratio = dampingRatio
            guard ratio < 1 else { return 0 }
            return exp(-ratio * .pi / (1 - ratio * ratio).squareRoot())
        }

        var animation: Animation {
            .interpolatingSpring(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: 0)
        }
    }

    struct Plan: Equatable {
        var kind: Kind
        var shellDuration: TimeInterval
        var outgoingDuration: TimeInterval
        var outgoingScale: CGFloat
        var outgoingBlur: CGFloat
        var handoffDelay: TimeInterval
        var incomingFadeDuration: TimeInterval
        var incomingScale: CGFloat
        var incomingBlur: CGFloat
        /// Nil when the incoming page does not scale.
        var incomingSpring: Spring?

        var outgoingAnimation: Animation? {
            guard kind != .instant else { return nil }
            return .timingCurve(
                closeCurve.c0x, closeCurve.c0y, closeCurve.c1x, closeCurve.c1y,
                duration: outgoingDuration
            )
        }

        var incomingFadeAnimation: Animation? {
            guard kind != .instant else { return nil }
            return .timingCurve(
                openCurve.c0x, openCurve.c0y, openCurve.c1x, openCurve.c1y,
                duration: incomingFadeDuration
            )
        }

        var incomingScaleAnimation: Animation? {
            incomingSpring?.animation
        }
    }

    // MARK: Source-backed constants

    /// Droppy AppKitMotion `openTiming`.
    static let openCurve = (c0x: 0.22, c0y: 1.0, c1x: 0.36, c1y: 1.0)
    /// Droppy AppKitMotion `closeTiming`.
    static let closeCurve = (c0x: 0.4, c0y: 0.0, c1x: 0.2, c1y: 1.0)
    /// Droppy AppKitMotion.animateIn `initialScale`.
    static let incomingScale: CGFloat = 0.90
    /// Droppy AppKitMotion.animateOut `targetScale`.
    static let outgoingScale: CGFloat = 0.96
    /// Droppy notch view transition blur.
    static let blurRadius: CGFloat = 6
    /// Droppy starts from AppKitMotion's k=260/c=24 spring. DynamicIsland keeps
    /// the same stiffness but deliberately lowers damping so a 0.90 -> 1.00
    /// entrance produces one clearly visible ~2% overshoot instead of reading
    /// as a monotonic scale. The physical shell never uses this spring.
    static let incomingSpring = Spring(mass: 1, stiffness: 260, damping: 14.5)
    /// Reference shell duration used to scale the child spring with the user's
    /// motion-speed/preset choice. `shellDuration` already contains both.
    static let referenceShellDuration: TimeInterval = 0.40
    static let minimumChildTimeScale: Double = 0.65
    static let maximumChildTimeScale: Double = 4.0
    /// Droppy AppKitMotion reduced-motion caps.
    static let reducedOutgoingDuration: TimeInterval = 0.14
    static let reducedIncomingDuration: TimeInterval = 0.16

    // MARK: DynamicIsland timing (derived from the shell, unchanged ratios)

    /// Outgoing removal: the pre-existing `shell * 0.34`, floored at 0.12 s.
    static let outgoingDurationRatio: TimeInterval = 0.34
    static let outgoingMinimumDuration: TimeInterval = 0.12
    /// The incoming page mounts when the outgoing page is ~3/4 gone, so the
    /// shell is never empty but the two pages barely overlap.
    static let handoffFractionOfOutgoing: TimeInterval = 0.75
    /// Incoming blur/opacity resolve over half the shell morph (floor 0.16 s).
    static let incomingFadeRatio: TimeInterval = 0.5
    static let incomingFadeMinimumDuration: TimeInterval = 0.16

    static func plan(_ inputs: Inputs) -> Plan {
        if inputs.isInstant {
            return Plan(
                kind: .instant,
                shellDuration: inputs.shellDuration,
                outgoingDuration: 0,
                outgoingScale: 1,
                outgoingBlur: 0,
                handoffDelay: 0,
                incomingFadeDuration: 0,
                incomingScale: 1,
                incomingBlur: 0,
                incomingSpring: nil
            )
        }

        if inputs.reduceMotion {
            // Top-pinned geometry still morphs; content is a short cross-fade
            // with no blur, scale or bounce.
            return Plan(
                kind: .reduced,
                shellDuration: inputs.shellDuration,
                outgoingDuration: reducedOutgoingDuration,
                outgoingScale: 1,
                outgoingBlur: 0,
                // Incoming content waits for the shell to reach its target.
                handoffDelay: max(reducedOutgoingDuration * 0.5, inputs.shellDuration),
                incomingFadeDuration: reducedIncomingDuration,
                incomingScale: 1,
                incomingBlur: 0,
                incomingSpring: nil
            )
        }

        let displayTuning = WorkspaceMotion.motionScale(refreshRate: inputs.refreshRate)
        // The user's preset/speed is already represented by shellDuration.
        // Apply the same temporal intent to child materialization so a slow
        // shell cannot be followed by an imperceptibly fast fixed spring.
        let userTimeScale = min(
            max(inputs.shellDuration / referenceShellDuration, minimumChildTimeScale),
            maximumChildTimeScale
        )
        let springTimeScale = displayTuning * userTimeScale
        let outgoing = max(inputs.shellDuration * outgoingDurationRatio, outgoingMinimumDuration) * displayTuning
        let fade = max(inputs.shellDuration * incomingFadeRatio, incomingFadeMinimumDuration) * displayTuning
        let blur = inputs.useBlurTransitions && !inputs.prefersLightweightEffects ? blurRadius : 0
        let scales = inputs.useScaleTransitions
        // Lengthen the spring period for both display refresh and user-selected
        // motion speed while preserving damping ratio/overshoot.
        let spring = Spring(
            mass: incomingSpring.mass,
            stiffness: incomingSpring.stiffness / (springTimeScale * springTimeScale),
            damping: incomingSpring.damping / springTimeScale
        )

        return Plan(
            kind: .full,
            shellDuration: inputs.shellDuration,
            outgoingDuration: outgoing,
            outgoingScale: scales ? outgoingScale : 1,
            outgoingBlur: blur,
            // Incoming content mounts only once the shell has reached its
            // target size; the outgoing page still leaves immediately.
            handoffDelay: max(outgoing * handoffFractionOfOutgoing, inputs.shellDuration),
            incomingFadeDuration: fade,
            incomingScale: scales ? incomingScale : 1,
            incomingBlur: blur,
            incomingSpring: scales ? spring : nil
        )
    }

    @MainActor
    static func plan(settings: AppSettings, reduceMotion: Bool) -> Plan {
        plan(inputs(settings: settings, reduceMotion: reduceMotion))
    }

    /// Collapse choreography from the same settings and shell SSOT.
    @MainActor
    static func collapsePlan(settings: AppSettings, reduceMotion: Bool) -> ContractionPlan {
        collapsePlan(inputs(settings: settings, reduceMotion: reduceMotion))
    }

    @MainActor
    static func inputs(settings: AppSettings, reduceMotion: Bool) -> Inputs {
        let reduces = reduceMotion || settings.reduceExtraMotion
        return Inputs(
            shellDuration: IslandContentTransitionTiming.shellDuration(settings: settings, reduceMotion: reduces),
            isInstant: settings.animationPreset == .instant || !settings.contentAnimationEnabled,
            reduceMotion: reduces,
            useBlurTransitions: settings.useBlurTransitions,
            useScaleTransitions: settings.useScaleTransitions,
            prefersLightweightEffects: WorkspaceMotion.prefersLightweightEffects,
            refreshRate: WorkspaceMotion.currentRefreshRate
        )
    }

    /// Removal transition for the outgoing page.
    static func outgoingTransition(_ plan: Plan) -> AnyTransition {
        guard let animation = plan.outgoingAnimation else { return .identity }
        return .asymmetric(
            insertion: .identity,
            removal: .modifier(
                active: ExpandedPageMorphModifier(opacity: 0, blur: plan.outgoingBlur, scale: plan.outgoingScale),
                identity: ExpandedPageMorphModifier(opacity: 1, blur: 0, scale: 1)
            )
            .animation(animation)
        )
    }
}

// MARK: - Deterministic sampling (renders and tests)

extension ExpandedIslandMotion {
    struct ContentSample: Equatable {
        var opacity: Double
        var blur: CGFloat
        var scale: CGFloat

        static let identity = ContentSample(opacity: 1, blur: 0, scale: 1)
    }

    struct FrameSample: Equatable {
        /// Eased shell progress (panel and canvas share this curve).
        var shellProgress: Double
        /// Nil once the outgoing page has finished its removal.
        var outgoing: ContentSample?
        /// Nil until the handoff mounts the incoming page.
        var incoming: ContentSample?
    }

    /// Evaluates a cubic-bezier timing curve (control points c1, c2) at `x`.
    static func bezier(_ x: Double, _ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double) -> Double {
        let x = min(max(x, 0), 1)
        let cx = 3 * c0x, bx = 3 * (c1x - c0x) - cx, ax = 1 - cx - bx
        let cy = 3 * c0y, by = 3 * (c1y - c0y) - cy, ay = 1 - cy - by
        func curveX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func curveY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
        func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
        var t = x
        for _ in 0..<8 {
            let error = curveX(t) - x
            if abs(error) < 1e-7 { break }
            let slope = slopeX(t)
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        if abs(curveX(t) - x) > 1e-5 {
            var low = 0.0, high = 1.0
            t = x
            for _ in 0..<40 {
                if curveX(t) < x { low = t } else { high = t }
                t = (low + high) / 2
            }
        }
        return curveY(min(max(t, 0), 1))
    }

    /// Unit step response of an underdamped (or critically damped) spring.
    static func springProgress(_ spring: Spring, at time: Double) -> Double {
        guard time > 0 else { return 0 }
        let zeta = spring.dampingRatio
        let omega = spring.naturalFrequency
        guard zeta < 1 else {
            return 1 - exp(-omega * time) * (1 + omega * time)
        }
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * time)
        return 1 - decay * (cos(omegaD * time) + (zeta * omega / omegaD) * sin(omegaD * time))
    }

    static func sample(_ plan: Plan, at time: TimeInterval) -> FrameSample {
        let shellDuration = max(plan.shellDuration, 0.0001)
        let shell = ExpandedShellMorph.controlPoints
        let shellProgress = bezier(time / shellDuration, shell.c0x, shell.c0y, shell.c1x, shell.c1y)

        guard plan.kind != .instant else {
            return FrameSample(shellProgress: time > 0 ? 1 : 0, outgoing: nil, incoming: .identity)
        }

        var outgoing: ContentSample?
        if time < plan.outgoingDuration {
            let p = bezier(time / plan.outgoingDuration, closeCurve.c0x, closeCurve.c0y, closeCurve.c1x, closeCurve.c1y)
            outgoing = ContentSample(
                opacity: 1 - p,
                blur: plan.outgoingBlur * CGFloat(p),
                scale: 1 + (plan.outgoingScale - 1) * CGFloat(p)
            )
        }

        var incoming: ContentSample?
        if time >= plan.handoffDelay {
            let local = time - plan.handoffDelay
            let fade = bezier(local / max(plan.incomingFadeDuration, 0.0001), openCurve.c0x, openCurve.c0y, openCurve.c1x, openCurve.c1y)
            let scaleProgress = plan.incomingSpring.map { springProgress($0, at: local) } ?? 1
            incoming = ContentSample(
                opacity: fade,
                blur: plan.incomingBlur * CGFloat(1 - fade),
                scale: plan.incomingScale + (1 - plan.incomingScale) * CGFloat(scaleProgress)
            )
        }

        return FrameSample(shellProgress: shellProgress, outgoing: outgoing, incoming: incoming)
    }
}

/// Generation-guarded page mounting for expanded tab switches.
///
/// The outgoing page is unmounted as soon as the selection changes; the
/// incoming page is mounted only when its handoff generation is still the
/// newest, so it is never visible (or laid out) before the shell has committed
/// its geometry, and stale handoffs from rapid switching are dropped.
struct ExpandedPageTransitionState: Equatable {
    enum SelectionEffect: Equatable {
        case none
        case swapImmediately
        case scheduleHandoff(generation: Int, delay: TimeInterval)
    }

    private(set) var mountedPage: ExpandedIslandPage?
    private(set) var targetPage: ExpandedIslandPage
    private(set) var generation = 0
    /// Identity of the mounted page view; a re-mount always gets a new one.
    private(set) var mountGeneration = 0
    /// True only when the mounted page arrived through an animated handoff;
    /// initial, snapped and instant mounts must not replay the entrance.
    private(set) var animatesEntrance = false

    init(page: ExpandedIslandPage) {
        mountedPage = page
        targetPage = page
    }

    var isHandoffPending: Bool { mountedPage == nil }

    /// `handoffDelay` overrides the plan's handoff (shrinking page changes
    /// mount the incoming page only after the shell has contracted).
    mutating func select(
        _ page: ExpandedIslandPage,
        plan: ExpandedIslandMotion.Plan,
        handoffDelay: TimeInterval? = nil
    ) -> SelectionEffect {
        guard page != targetPage else { return .none }
        generation += 1
        targetPage = page
        if plan.kind == .instant {
            mountedPage = page
            mountGeneration = generation
            animatesEntrance = false
            return .swapImmediately
        }
        mountedPage = nil
        return .scheduleHandoff(generation: generation, delay: handoffDelay ?? plan.handoffDelay)
    }

    @discardableResult
    mutating func completeHandoff(generation expected: Int) -> Bool {
        guard expected == generation, mountedPage == nil else { return false }
        mountedPage = targetPage
        mountGeneration = generation
        animatesEntrance = true
        return true
    }

    /// Settles on `page` without animation, cancelling any pending handoff.
    mutating func snap(to page: ExpandedIslandPage) {
        guard mountedPage != page || targetPage != page else { return }
        generation += 1
        targetPage = page
        mountedPage = page
        mountGeneration = generation
        animatesEntrance = false
    }
}

/// Outgoing page treatment: top-anchored shrink + blur + fade.
struct ExpandedPageMorphModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .top)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// Incoming page entrance, driven on appear so each channel keeps its own
/// curve: scale on the spring, blur/opacity on the open curve.
struct ExpandedPageEntranceModifier: ViewModifier {
    let plan: ExpandedIslandMotion.Plan
    @State private var hasEntered: Bool

    init(plan: ExpandedIslandMotion.Plan, animatesEntrance: Bool) {
        self.plan = plan
        _hasEntered = State(initialValue: !animatesEntrance || plan.kind == .instant)
    }

    func body(content: Content) -> some View {
        content
            .animation(plan.incomingScaleAnimation) { view in
                view.scaleEffect(hasEntered ? 1 : plan.incomingScale, anchor: .top)
            }
            .animation(plan.incomingFadeAnimation) { view in
                view
                    .blur(radius: hasEntered ? 0 : plan.incomingBlur)
                    .opacity(hasEntered ? 1 : 0)
            }
            .onAppear {
                guard !hasEntered else { return }
                hasEntered = true
            }
    }
}

extension View {
    /// Shared expanded-page choreography for every primary tab.
    /// Identity is part of the contract: every mount gets a fresh identity so
    /// a quickly re-selected page never merges with its own removing copy.
    func expandedPageMotion(
        _ plan: ExpandedIslandMotion.Plan,
        animatesEntrance: Bool,
        mountID: ExpandedPageMountID
    ) -> some View {
        modifier(ExpandedPageEntranceModifier(plan: plan, animatesEntrance: animatesEntrance))
            .id(mountID)
            .transition(ExpandedIslandMotion.outgoingTransition(plan))
    }
}

struct ExpandedPageMountID: Hashable {
    let page: ExpandedIslandPage
    let generation: Int
}

// MARK: - Contraction (collapse and shrinking page changes)

extension ExpandedIslandMotion {
    /// Mirror of expansion. Expansion: shell grows, then children materialize.
    /// Contraction: children exit (shrink, blur, fade), and only once they are
    /// hidden does the shell commit its smaller geometry, top-pinned. The
    /// shell itself is never scaled.
    struct ContractionPlan: Equatable {
        enum ExitCurve: Equatable {
            /// InnerBlurScaleCleanModifier removal (collapse).
            case easeIn
            /// Droppy close curve (outgoing page).
            case close
        }

        var childExitDuration: TimeInterval
        var childExitScale: CGFloat
        var childExitBlur: CGFloat
        var exitCurve: ExitCurve
        /// Delay between the contraction request and the shell's geometry commit.
        var shellCommitDelay: TimeInterval
        var shellDuration: TimeInterval
        /// Page changes only: when the incoming page mounts.
        var incomingHandoffDelay: TimeInterval?

        var totalDuration: TimeInterval { shellCommitDelay + shellDuration }
    }

    struct ContractionSample: Equatable {
        var shellFrame: CGRect
        /// Nil once the outgoing children are hidden.
        var outgoing: ContentSample?
    }

    static func collapsePlan(_ inputs: Inputs) -> ContractionPlan {
        if inputs.isInstant {
            return ContractionPlan(
                childExitDuration: 0, childExitScale: 1, childExitBlur: 0, exitCurve: .easeIn,
                shellCommitDelay: 0, shellDuration: inputs.shellDuration, incomingHandoffDelay: nil
            )
        }
        let exit = inputs.reduceMotion
            ? IslandContentTransitionTiming.reducedCollapseExitDuration
            : IslandContentTransitionTiming.collapseContentDuration(shellDuration: inputs.shellDuration)
                + IslandContentTransitionTiming.collapseExitStaggerAllowance
        let decorative = !inputs.reduceMotion
        return ContractionPlan(
            childExitDuration: exit,
            childExitScale: decorative && inputs.useScaleTransitions ? IslandContentTransitionTiming.collapseExitScale : 1,
            childExitBlur: decorative && inputs.useBlurTransitions && !inputs.prefersLightweightEffects
                ? IslandContentTransitionTiming.collapseExitBlur : 0,
            exitCurve: .easeIn,
            // Children are hidden before the shell contracts around them.
            shellCommitDelay: exit,
            shellDuration: inputs.shellDuration,
            incomingHandoffDelay: nil
        )
    }

    /// Expanded page change whose target shell is smaller.
    static func shrinkingPagePlan(_ plan: Plan) -> ContractionPlan {
        ContractionPlan(
            childExitDuration: plan.outgoingDuration,
            childExitScale: plan.outgoingScale,
            childExitBlur: plan.outgoingBlur,
            exitCurve: .close,
            shellCommitDelay: plan.outgoingDuration,
            shellDuration: plan.shellDuration,
            // The incoming page waits for the shell to land at the smaller size.
            incomingHandoffDelay: plan.kind == .instant ? 0 : plan.outgoingDuration + plan.shellDuration
        )
    }

    /// Whether switching pages contracts the expanded shell (per-page
    /// presentation profiles applied to the user's expanded size).
    static func pageChangeShrinksShell(
        from source: ExpandedIslandPage,
        to target: ExpandedIslandPage,
        expandedSize: CGSize
    ) -> Bool {
        shellShrinks(
            from: ExpandedPresentationProfile.resolve(for: source).resolvedSize(from: expandedSize),
            to: ExpandedPresentationProfile.resolve(for: target).resolvedSize(from: expandedSize)
        )
    }

    /// True when the target shell is smaller in either dimension, so the
    /// outgoing content must leave before the shell contracts around it.
    static func shellShrinks(from source: CGSize, to target: CGSize) -> Bool {
        target.width < source.width - 0.5 || target.height < source.height - 0.5
    }

    static func sampleContraction(
        _ plan: ContractionPlan,
        at time: TimeInterval,
        from source: CGRect,
        to target: CGRect
    ) -> ContractionSample {
        var outgoing: ContentSample?
        if time < plan.childExitDuration {
            let x = time / max(plan.childExitDuration, 0.0001)
            let p: Double
            switch plan.exitCurve {
            case .easeIn: p = bezier(x, 0.42, 0, 1, 1)
            case .close: p = bezier(x, closeCurve.c0x, closeCurve.c0y, closeCurve.c1x, closeCurve.c1y)
            }
            outgoing = ContentSample(
                opacity: 1 - p,
                blur: plan.childExitBlur * CGFloat(p),
                scale: 1 + (plan.childExitScale - 1) * CGFloat(p)
            )
        }

        let shellTime = time - plan.shellCommitDelay
        guard shellTime > 0 else { return ContractionSample(shellFrame: source, outgoing: outgoing) }
        let shell = ExpandedShellMorph.controlPoints
        let progress = shellTime >= plan.shellDuration
            ? 1
            : bezier(shellTime / max(plan.shellDuration, 0.0001), shell.c0x, shell.c0y, shell.c1x, shell.c1y)
        let frame = progress >= 1
            ? target
            : ExpandedShellMorph.interpolatedFrame(from: source, to: target, progress: CGFloat(progress))
        return ContractionSample(shellFrame: frame, outgoing: outgoing)
    }
}

/// Presentation-local clock edge used to guarantee that every child-exit
/// generation owns a real animatable value change. Expansion deliberately does
/// not reset this value: rapid resume/expand/collapse cycles can otherwise make
/// a fixed 1 -> 0 clock a no-op before SwiftUI renders the reset.
enum ExpandedChildExitVisualClock {
    static func next(after current: Double) -> Double {
        current < 0.5 ? 1 : 0
    }
}

/// Root-side child-exit bookkeeping for a pending collapse. The overlay
/// publishes a monotonic collapse generation; the root answers with "children
/// are hidden as of generation N". Driving from the generation (not from a
/// Bool edge SwiftUI may coalesce) and acknowledging the *current* generation
/// from the actual visual state means no exit can wait for an
/// acknowledgement that can no longer arrive.
struct ExpandedChildExitTracker: Equatable {
    enum Action: Equatable {
        /// Start (or restart) the child exit animation.
        case beginExit
        /// Children are already hidden and nothing is animating: acknowledge now.
        case acknowledge(Int)
        case none
    }

    /// Identity of the newest exit animation; older completions are ignored.
    private(set) var animationToken = 0
    private(set) var exitInFlight = false
    /// Collapse generation the in-flight exit animation was started for.
    private var exitGeneration: Int?

    /// Called whenever the collapse generation or exiting flag changes.
    mutating func drive(generation: Int, isExiting: Bool, childrenHidden: Bool) -> Action {
        guard isExiting else { return .none }
        if exitInFlight {
            // A *newer* collapse request while the children are already hidden
            // recovers immediately: if every completion of the in-flight exit
            // was lost, waiting on it would hold the shell forever.
            if let exitGeneration, generation != exitGeneration, childrenHidden {
                exitInFlight = false
                animationToken &+= 1
                return .acknowledge(generation)
            }
            return .none // its completion acknowledges the current generation
        }
        if childrenHidden { return .acknowledge(generation) }
        return .beginExit
    }

    /// Marks a new exit animation; returns its token.
    mutating func beginAnimation(generation: Int? = nil) -> Int {
        animationToken &+= 1
        exitInFlight = true
        exitGeneration = generation
        return animationToken
    }

    /// The exit animation finished. Only the newest animation counts, and it
    /// acknowledges whichever collapse generation is current right now.
    mutating func animationFinished(token: Int, currentGeneration: Int, isExiting: Bool) -> Int? {
        guard token == animationToken else { return nil }
        exitInFlight = false
        return isExiting ? currentGeneration : nil
    }

    /// An expansion cancelled the exit or the shell finished collapsing.
    mutating func reset() {
        animationToken &+= 1
        exitInFlight = false
    }
}

/// Generation-guarded pending collapse. The island stays expanded while its
/// children exit; the collapse commits only if it is still the newest request
/// and was not cancelled by an expansion in the meantime.
struct IslandCollapseRequest: Equatable {
    private(set) var generation = 0
    private var pending: Int?

    var isPending: Bool { pending != nil }

    mutating func begin() -> Int {
        generation += 1
        pending = generation
        return generation
    }

    /// Cancels a pending collapse (an expansion arrived). Returns true when one was pending.
    @discardableResult
    mutating func cancel() -> Bool {
        guard pending != nil else { return false }
        pending = nil
        generation += 1
        return true
    }

    /// The child-exit phase belongs to the expanded state only: committing
    /// either state ends it. (Expanded: a cancelled collapse; collapsed: the
    /// children already exited and the shell is contracting.)
    static func exitPhaseEnds(at state: IslandPresentationState) -> Bool {
        switch state {
        case .expanded, .collapsed: true
        }
    }

    /// Consumes the pending collapse if `expected` is still current.
    mutating func commit(_ expected: Int) -> Bool {
        guard pending == expected else { return false }
        pending = nil
        return true
    }
}
