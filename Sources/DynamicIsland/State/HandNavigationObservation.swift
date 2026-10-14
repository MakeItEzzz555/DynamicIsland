import Foundation

enum HandNavigationPose: String, Codable, Sendable {
    case pointer, openPalm, twoFinger, other
}

enum HandNavigationSide: Sendable { case unknown, left, right }

struct HandFingerExtensions: Sendable, Equatable {
    var index = false
    var middle = false
    var ring: Bool?
    var little: Bool?
}

enum HandNavigationGeometry {
    static func distance(_ a: CGPoint, _ b: CGPoint, aspectRatio: Double) -> Double {
        hypot((a.x - b.x) * aspectRatio, a.y - b.y)
    }
    static func measure(thumb: CGPoint, index: CGPoint, wrist: CGPoint, middleMCP: CGPoint,
                        indexMCP: CGPoint, littleMCP: CGPoint, aspectRatio: Double) -> (scale: Double, pinch: Double) {
        let scale = max(distance(wrist, middleMCP, aspectRatio: aspectRatio),
                        distance(indexMCP, littleMCP, aspectRatio: aspectRatio))
        return (scale, scale > 0 ? distance(thumb, index, aspectRatio: aspectRatio) / scale : .infinity)
    }
}

struct HandNavigationObservation: Sendable, Equatable {
    var fingertip: CGPoint
    var palm: CGPoint
    var handScale: Double
    var pinchRatio: Double
    var pose: HandNavigationPose
    var confidence: Double
    var timestamp: TimeInterval
    var palmVelocity = CGPoint.zero
    var fingers = HandFingerExtensions()
    var side: HandNavigationSide = .unknown

    var isValid: Bool {
        [fingertip.x, fingertip.y, palm.x, palm.y, handScale, pinchRatio, confidence, timestamp].allSatisfy(\.isFinite)
            && confidence >= 0.5 && handScale >= 0.025 && pinchRatio >= 0
    }
}

struct HandNavigationCalibration: Codable, Equatable, Sendable {
    var left = 0.15
    var right = 0.85
    var bottom = 0.15
    var top = 0.85

    var isValid: Bool {
        [left, right, bottom, top].allSatisfy { $0.isFinite && (0...1).contains($0) }
            && right - left >= 0.2 && top - bottom >= 0.2
    }

    func map(_ point: CGPoint, sensitivity: Double) -> CGPoint {
        let bounds = isValid ? self : Self()
        let gain = 0.7 + min(max(sensitivity, 0), 1) * 0.6
        return CGPoint(x: ((point.x - bounds.left) / (bounds.right - bounds.left) - 0.5) * gain + 0.5,
                       y: ((point.y - bounds.bottom) / (bounds.top - bounds.bottom) - 0.5) * gain + 0.5)
    }
}

enum HandNavigationCoordinates {
    /// Vision supplies lower-left coordinates. Camera samples are unmirrored;
    /// a user-facing camera needs exactly one horizontal mirror.
    static func oriented(_ point: CGPoint, quarterTurns: Int = 0, mirrored: Bool = true) -> CGPoint {
        var result = point
        for _ in 0..<((quarterTurns % 4 + 4) % 4) { result = CGPoint(x: 1 - result.y, y: result.x) }
        if mirrored { result.x = 1 - result.x }
        return result
    }

    static func islandPoint(_ point: CGPoint, frame: CGRect) -> CGPoint {
        let insetX = min(0.5, frame.width / 2), insetY = min(0.5, frame.height / 2)
        return CGPoint(x: min(max(frame.minX + point.x * frame.width, frame.minX + insetX), frame.maxX - insetX),
                       y: min(max(frame.minY + point.y * frame.height, frame.minY + insetY), frame.maxY - insetY))
    }
}

struct HandPointerFilter {
    private(set) var point: CGPoint?
    private var timestamp: TimeInterval?

    mutating func reset() { point = nil; timestamp = nil }

    mutating func update(_ input: CGPoint, at time: TimeInterval, smoothing: Double) -> CGPoint {
        guard let prior = point, let previousTime = timestamp, time > previousTime, time - previousTime < 0.3 else {
            point = input; timestamp = time; return input
        }
        let dt = min(time - previousTime, 0.1)
        let distance = hypot(input.x - prior.x, input.y - prior.y)
        let speed = distance / dt
        let cutoff = 1.5 + (1 - min(max(smoothing, 0), 1)) * 8 + speed * 12
        let alpha = 1 / (1 + 1 / (2 * Double.pi * cutoff * dt))
        let next = distance < 0.0015 ? prior : CGPoint(x: prior.x + (input.x - prior.x) * alpha,
                                                     y: prior.y + (input.y - prior.y) * alpha)
        point = next; timestamp = time
        return next
    }
}

/// Optional fingertips may be absent; two explicitly folded fingers remain a scroll pose.
struct NavigationPoseClassifier {
    private(set) var pose: HandNavigationPose = .other
    private(set) var palmCandidate = false
    private var candidateAt: TimeInterval?
    private var accepted = 0
    private var lastPalmAt: TimeInterval?
    private var degradedFrames = 0

    static func hasOpenHandEvidence(_ hand: HandNavigationObservation) -> Bool {
        let fingers = hand.fingers
        return fingers.index && fingers.middle &&
            (fingers.ring == true || fingers.little == true ||
             ((fingers.ring == nil || fingers.little == nil) && hand.pinchRatio >= 0.8))
    }

    mutating func update(_ hand: HandNavigationObservation, releaseThreshold: Double) {
        let candidate = hand.pinchRatio > releaseThreshold &&
            (hand.pose == .openPalm || Self.hasOpenHandEvidence(hand))
        if candidate {
            if candidateAt == nil { candidateAt = hand.timestamp }
            accepted += 1; degradedFrames = 0; lastPalmAt = hand.timestamp; palmCandidate = true
            pose = accepted >= 2 && hand.timestamp - (candidateAt ?? hand.timestamp) >= 0.08 ? .openPalm : .other
        } else if palmCandidate, let lastPalmAt, hand.timestamp - lastPalmAt <= 0.12, degradedFrames < 2,
                  hand.pinchRatio > releaseThreshold {
            degradedFrames += 1
        } else {
            self = Self(); pose = hand.pose == .openPalm ? .other : hand.pose
        }
    }
}

enum HandNavigationAction: Equatable {
    case press, drag, release, cancel
    case expandIsland, collapseIsland
    case page(forward: Bool)
    case scroll(Double)
}

struct HandNavigationStateMachine {
    enum Phase: String { case tracking, pinchCandidate, pressed, dragging }
    enum Mode: String { case collapsedGesture, pointer, navigation, rearming }
    private(set) var phase: Phase = .tracking
    private(set) var mode: Mode = .pointer
    private(set) var classifier = NavigationPoseClassifier()
    private(set) var swipeArmed = true
    private(set) var swipeDisplacement = CGPoint.zero
    private(set) var swipeVelocity = 0.0
    private var candidateAt: TimeInterval?
    private var pressPoint: CGPoint?
    private var previous: HandNavigationObservation?
    private var needsRelease = true
    private var swipeOrigin: CGPoint?
    private var swipeAt: TimeInterval?
    private var neutralAt: TimeInterval?
    private var scrollAt: TimeInterval?
    private var navigationOwnsHand = false
    private var wasExpanded: Bool?
    private var palmStillAt: TimeInterval?
    private var collapsedPinchPending = false

    var hasPrecisionInteraction: Bool {
        mode == .pointer && (classifier.pose == .pointer || isPressed || phase == .pinchCandidate)
    }
    var isPressed: Bool { phase == .pressed || phase == .dragging }

    mutating func reset() -> [HandNavigationAction] {
        let actions: [HandNavigationAction] = isPressed ? [.cancel] : []
        let rearmRequired = !swipeArmed
        self = Self()
        if rearmRequired { swipeArmed = false; navigationOwnsHand = true; mode = .rearming }
        return actions
    }

    /// Suspending injection must not erase a valid hand, filter or navigation lifecycle.
    mutating func suspendInteraction() -> [HandNavigationAction] {
        let actions: [HandNavigationAction] = isPressed ? [.cancel] : []
        phase = .tracking; candidateAt = nil; pressPoint = nil; needsRelease = true
        collapsedPinchPending = false
        return actions
    }

    mutating func update(_ observation: HandNavigationObservation?, pinchSensitivity: Double = 0.5,
                         pageSwipe: Bool = true, scroll: Bool = false, expanded: Bool = true,
                         interactionAvailable: Bool = true, expandOnPinch: Bool = true,
                         collapsedGestureAvailable: Bool = true,
                         leftAction: IslandGestureAction = .nextTab, rightAction: IslandGestureAction = .previousTab,
                         downAction: IslandGestureAction = .none) -> [HandNavigationAction] {
        guard let current = observation, current.isValid else { return reset() }
        if let previous, current.timestamp <= previous.timestamp { return [] }
        if let previous, (previous.side != .unknown && current.side != .unknown && previous.side != current.side) ||
            current.timestamp - previous.timestamp > 0.3 ||
            hypot(current.palm.x - previous.palm.x, current.palm.y - previous.palm.y) > 0.35 {
            let cancellation = reset(); self.previous = current; return cancellation
        }
        let last = previous; previous = current
        let pressThreshold = 0.18 + min(max(pinchSensitivity, 0), 1) * 0.16
        let releaseThreshold = pressThreshold + 0.13
        var cancellation: [HandNavigationAction] = []
        if let wasExpanded, wasExpanded != expanded {
            cancellation = suspendInteraction()
            navigationOwnsHand = true; neutralAt = nil
            palmStillAt = nil
        }
        wasExpanded = expanded
        if current.pinchRatio > releaseThreshold { needsRelease = false }
        classifier.update(current, releaseThreshold: releaseThreshold)
        if expanded, !interactionAvailable, isPressed || phase == .pinchCandidate {
            cancellation += suspendInteraction()
        }

        if !expanded {
            mode = .collapsedGesture; swipeOrigin = nil; swipeAt = nil; scrollAt = nil
            if current.pinchRatio > releaseThreshold || !expandOnPinch { collapsedPinchPending = false }
            let pinch = updatePinch(current, pressThreshold: pressThreshold, releaseThreshold: releaseThreshold)
            if pinch.contains(.press) {
                phase = .tracking; pressPoint = nil; needsRelease = true
                collapsedPinchPending = expandOnPinch
            }
            if collapsedPinchPending, collapsedGestureAvailable {
                collapsedPinchPending = false
                return cancellation + [.expandIsland]
            }
            return cancellation
        }

        if classifier.palmCandidate {
            mode = .navigation; navigationOwnsHand = true; neutralAt = nil; scrollAt = nil
            if swipeOrigin == nil { swipeOrigin = current.palm; swipeAt = current.timestamp }
            if isPressed {
                swipeArmed = false
                return cancellation + suspendInteraction()
            }
            phase = .tracking; candidateAt = nil
            if !swipeArmed {
                // Moving returns are ignored; a still palm starts the next independent stroke.
                let dt = current.timestamp - (last?.timestamp ?? current.timestamp)
                let speed = dt > 0 ? hypot(current.palm.x - (last?.palm.x ?? current.palm.x),
                    current.palm.y - (last?.palm.y ?? current.palm.y)) / dt / current.handScale : .infinity
                if classifier.pose == .openPalm, speed < 0.45 {
                    if palmStillAt == nil { palmStillAt = current.timestamp }
                    if current.timestamp - (palmStillAt ?? current.timestamp) >= 0.15 - 0.000001 {
                        swipeArmed = true; palmStillAt = nil
                        swipeOrigin = current.palm; swipeAt = current.timestamp
                        swipeDisplacement = .zero; swipeVelocity = 0
                    }
                } else { palmStillAt = nil }
                return cancellation
            }
            guard classifier.pose == .openPalm, swipeArmed,
                  let origin = swipeOrigin, let started = swipeAt else { return cancellation }
            let dx = current.palm.x - origin.x, dy = current.palm.y - origin.y
            let duration = current.timestamp - started
            swipeDisplacement = CGPoint(x: dx, y: dy)
            swipeVelocity = duration > 0 ? hypot(dx, dy) / duration : 0
            if duration > 0.85 { swipeOrigin = current.palm; swipeAt = current.timestamp; return cancellation }
            // Palm travel scales with hand size, with a minimum that rejects camera jitter.
            let travel = max(0.08, min(0.16, current.handScale * 0.65))
            guard duration >= 0.08, swipeVelocity >= 0.25 else { return cancellation }
            let action: IslandGestureAction
            if pageSwipe, abs(dx) >= travel, abs(dx) > abs(dy) * 1.6 { action = dx < 0 ? leftAction : rightAction }
            else if -dy >= travel, -dy > abs(dx) * 1.6 { action = downAction }
            else { return cancellation }
            swipeArmed = false
            palmStillAt = nil
            guard interactionAvailable else { return cancellation }
            return cancellation + semanticAction(action)
        }

        // A held pinch retains precision ownership; two-finger scrolling cannot steal its drag.
        if isPressed {
            mode = .pointer
            return cancellation + updatePinch(current, pressThreshold: pressThreshold, releaseThreshold: releaseThreshold)
        }
        if classifier.pose == .twoFinger, current.pinchRatio > releaseThreshold {
            mode = .navigation; navigationOwnsHand = true; neutralAt = nil
            swipeOrigin = nil; swipeAt = nil; candidateAt = nil; phase = .tracking
            guard scroll, interactionAvailable else { return cancellation }
            if scrollAt == nil { scrollAt = current.timestamp }
            guard current.timestamp - (scrollAt ?? current.timestamp) >= 0.12,
                  let last, last.pose == .twoFinger else { return cancellation }
            let dy = current.palm.y - last.palm.y, dx = current.palm.x - last.palm.x
            return cancellation + (abs(dy) > abs(dx) * 1.5 && abs(dy) > 0.001 ? [.scroll(dy * 600)] : [])
        }
        scrollAt = nil; swipeOrigin = nil; swipeAt = nil; palmStillAt = nil
        if navigationOwnsHand {
            mode = .rearming
            if classifier.pose == .pointer, current.pinchRatio > releaseThreshold {
                if neutralAt == nil { neutralAt = current.timestamp }
                if current.timestamp - (neutralAt ?? current.timestamp) >= 0.15 {
                    navigationOwnsHand = false; swipeArmed = true; neutralAt = nil
                }
            } else { neutralAt = nil }
            if navigationOwnsHand { return cancellation }
        }
        mode = .pointer
        guard interactionAvailable else { return cancellation }
        return cancellation + updatePinch(current, pressThreshold: pressThreshold, releaseThreshold: releaseThreshold)
    }

    private func semanticAction(_ action: IslandGestureAction) -> [HandNavigationAction] {
        switch action {
        case .nextTab: [.page(forward: true)]
        case .previousTab: [.page(forward: false)]
        case .collapse: [.collapseIsland]
        default: []
        }
    }

    private mutating func updatePinch(_ current: HandNavigationObservation, pressThreshold: Double,
                                      releaseThreshold: Double) -> [HandNavigationAction] {
        if isPressed {
            if current.pinchRatio > releaseThreshold {
                phase = .tracking; pressPoint = nil; return [.release]
            }
            if let pressPoint, hypot(current.fingertip.x - pressPoint.x, current.fingertip.y - pressPoint.y) > 0.025 { phase = .dragging }
            return phase == .dragging ? [.drag] : []
        }
        guard !needsRelease, current.pinchRatio < pressThreshold else {
            phase = .tracking; candidateAt = nil; return []
        }
        if candidateAt == nil { candidateAt = current.timestamp; phase = .pinchCandidate }
        guard current.timestamp - (candidateAt ?? current.timestamp) >= 0.06 else { return [] }
        phase = .pressed; pressPoint = current.fingertip; candidateAt = nil
        return [.press]
    }
}
