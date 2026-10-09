import AppKit

/// Owns a precise horizontal page sequence across remounts and shell morphs.
/// A new physical beginning, never distance or a quiet gap, permits another page.
struct IslandPageScrollGesture {
    enum Phase { case began, changed, ended, cancelled, momentum, momentumEnded, ordinary }
    enum Outcome: Equatable { case ignored, consumed, next, previous }
    enum State: Equatable { case idle, tracking, content, consumed(IslandTouchPageAction) }

    static let directionLockDistance: CGFloat = 6
    static let pageThreshold: CGFloat = 18
    static let horizontalDominance: CGFloat = 1.5
    private(set) var state: State = .idle
    private var delta = CGSize.zero
    private var direction: IslandTouchPageAction?

    /// Point displacement of the fingers, independent of Natural Scrolling.
    /// Device scroll deltas use the opposite sign; AppKit may already invert them.
    static func fingerDelta(_ scrollDelta: CGFloat, invertedFromDevice: Bool) -> CGFloat {
        invertedFromDevice ? scrollDelta : -scrollDelta
    }

    static func phase(_ event: NSEvent) -> Phase {
        phase(precise: event.hasPreciseScrollingDeltas, physical: event.phase, momentum: event.momentumPhase)
    }

    static func phase(precise: Bool, physical: NSEvent.Phase, momentum: NSEvent.Phase) -> Phase {
        guard precise else { return .ordinary }
        if momentum.contains(.ended) || momentum.contains(.cancelled) { return .momentumEnded }
        if !momentum.isEmpty { return .momentum }
        if physical.contains(.began) { return .began }
        if physical.contains(.cancelled) { return .cancelled }
        if physical.contains(.ended) { return .ended }
        if physical.contains(.changed) { return .changed }
        return .ordinary
    }

    mutating func update(deltaX: CGFloat, deltaY: CGFloat, phase: Phase, canBegin: Bool,
                         leftAllowed: Bool = true, rightAllowed: Bool = true,
                         inputStillAllowed: Bool = true) -> Outcome {
        guard phase != .ordinary else { return .ignored }
        if phase == .began {
            self = Self()
            state = canBegin ? .tracking : .content
        }
        let owns: Bool
        switch state {
        case .consumed: owns = true
        case .tracking: owns = direction != nil
        case .idle, .content: owns = false
        }
        if phase == .momentumEnded || phase == .cancelled {
            self = Self()
            return owns ? .consumed : .ignored
        }
        // Physical ended may precede momentum. Keep ownership until its end
        // or the next physical began; neither can fire from a momentum sample.
        if phase == .momentum || phase == .ended { return owns ? .consumed : .ignored }
        if case .consumed = state { return .consumed }
        guard state == .tracking else { return .ignored }
        guard inputStillAllowed else { state = .content; return .ignored }
        guard deltaX.isFinite, deltaY.isFinite else { state = .content; return .ignored }
        delta.width += deltaX
        delta.height += deltaY
        guard delta.width.isFinite, delta.height.isFinite else { state = .content; return .ignored }
        if direction == nil {
            guard max(abs(delta.width), abs(delta.height)) >= Self.directionLockDistance else { return .consumed }
            guard abs(delta.width) > abs(delta.height) * Self.horizontalDominance else {
                state = .content; return .ignored
            }
            direction = delta.width < 0 ? .next : .previous
            guard direction == .next ? leftAllowed : rightAllowed else { state = .content; return .ignored }
        }
        guard let direction else { return .consumed }
        let sign: CGFloat = direction == .next ? -1 : 1
        guard delta.width * sign >= Self.pageThreshold,
              abs(delta.width) > abs(delta.height) * Self.horizontalDominance else { return .consumed }
        state = .consumed(direction)
        return direction == .next ? .next : .previous
    }
}
