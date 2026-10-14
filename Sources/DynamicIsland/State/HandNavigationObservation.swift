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
        guard input.x.isFinite, input.y.isFinite, time.isFinite else { return point ?? .zero }
        if let timestamp, time <= timestamp { return point ?? input }
        guard let prior = point, let previousTime = timestamp, time > previousTime, time - previousTime < 0.65 else {
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

/// Stabilizes fingertip deformation; intentional drags follow calibrated palm translation.
struct HandPinchPointerStabilizer {
    private(set) var anchor: CGPoint?
    private(set) var isDragging = false
    private var previous: HandNavigationObservation?
    private var approachPoint: CGPoint?
    private var approachCount = 0
    private var anchorAt: TimeInterval?
    private var pressPalm: CGPoint?
    private var pressPalmRaw: CGPoint?
    private var releaseOffset = CGPoint.zero
    private var releaseAt: TimeInterval?
    private var wasPressed = false

    mutating func reset() { self = Self() }

    mutating func update(_ hand: HandNavigationObservation, input: CGPoint, palm: CGPoint,
                         filtered: CGPoint?, phase: HandNavigationStateMachine.Phase,
                         pinchSensitivity: Double) -> CGPoint {
        let prior = previous; previous = hand
        let threshold = 0.18 + min(max(pinchSensitivity, 0), 1) * 0.16
        let pressed = phase == .pressed || phase == .dragging
        if let prior, hand.timestamp > prior.timestamp, hand.timestamp - prior.timestamp <= 0.15,
           hand.confidence >= 0.65, hand.pose != .openPalm, hand.pose != .twoFinger,
           prior.pinchRatio - hand.pinchRatio >= max(0.015, 1.2 * (hand.timestamp - prior.timestamp)),
           hand.pinchRatio < threshold + 0.4 {
            if approachCount == 0 { approachPoint = filtered ?? input }
            approachCount += 1
            if approachCount >= 2, anchor == nil {
                anchor = approachPoint; anchorAt = hand.timestamp
            }
        } else if anchor == nil { approachCount = 0; approachPoint = nil }
        if phase == .pinchCandidate || pressed, anchor == nil {
            anchor = filtered ?? input; anchorAt = hand.timestamp
        }
        if pressed, !wasPressed { pressPalm = palm; pressPalmRaw = hand.palm }
        if let anchor {
            let ended = wasPressed && !pressed || hand.pinchRatio > threshold + 0.4 ||
                (!pressed && phase != .pinchCandidate && hand.timestamp - (anchorAt ?? hand.timestamp) > 0.16)
            if ended {
                let last = filtered ?? anchor
                releaseOffset = CGPoint(x: last.x - input.x, y: last.y - input.y)
                releaseAt = hand.timestamp
                self.anchor = nil; pressPalm = nil; pressPalmRaw = nil
                isDragging = false
                approachCount = 0; approachPoint = nil
            } else {
                wasPressed = pressed
                if pressed, phase == .dragging, let pressPalm, let pressPalmRaw {
                    if hypot(hand.palm.x - pressPalmRaw.x, hand.palm.y - pressPalmRaw.y) >= max(0.012, hand.handScale * 0.12) { isDragging = true }
                    guard isDragging else { return anchor }
                    return CGPoint(x: anchor.x + palm.x - pressPalm.x, y: anchor.y + palm.y - pressPalm.y)
                }
                return anchor
            }
        }
        wasPressed = pressed
        if let releaseAt {
            let elapsed = hand.timestamp - releaseAt
            if elapsed < 0.4 {
                let weight = exp(-max(0, elapsed) / 0.08)
                return CGPoint(x: input.x + releaseOffset.x * weight, y: input.y + releaseOffset.y * weight)
            }
            self.releaseAt = nil; releaseOffset = .zero
        }
        return input
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
    private var lastPointerAt: TimeInterval?
    private var twoFingerFrames = 0
    private var pointerFrames = 0

    static func hasOpenHandEvidence(_ hand: HandNavigationObservation) -> Bool {
        let fingers = hand.fingers
        return fingers.index && fingers.middle &&
            (fingers.ring == true || fingers.little == true ||
             ((fingers.ring == nil || fingers.little == nil) && hand.pinchRatio >= 0.8))
    }

    mutating func update(_ hand: HandNavigationObservation, releaseThreshold: Double) {
        pointerFrames = hand.pose == .pointer ? pointerFrames + 1 : 0
        let candidate = hand.pinchRatio > releaseThreshold &&
            (hand.pose == .openPalm || Self.hasOpenHandEvidence(hand))
        if candidate {
            if candidateAt == nil { candidateAt = hand.timestamp }
            accepted += 1; degradedFrames = 0; lastPalmAt = hand.timestamp; palmCandidate = true
            pose = accepted >= 2 && hand.timestamp - (candidateAt ?? hand.timestamp) >= 0.08 ? .openPalm
                : lastPointerAt.map { hand.timestamp - $0 <= 0.15 } == true ? .pointer : .other
        } else if palmCandidate, let lastPalmAt, hand.timestamp - lastPalmAt <= 0.12, degradedFrames < 2,
                  hand.pinchRatio > releaseThreshold, hand.pose != .pointer || pointerFrames < 2 {
            degradedFrames += 1
        } else if !palmCandidate, hand.pose == .twoFinger {
            twoFingerFrames += 1
            pose = twoFingerFrames >= 2 || lastPointerAt == nil ? .twoFinger : .pointer
        } else {
            let pointerAt = lastPointerAt
            self = Self()
            lastPointerAt = pointerAt
            if hand.pose == .pointer { pose = .pointer; lastPointerAt = hand.timestamp }
            else if hand.pose == .other, let pointerAt, hand.timestamp - pointerAt <= 0.15 {
                pose = .pointer
            } else { pose = hand.pose == .openPalm ? .other : hand.pose }
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
        return actions
    }

    mutating func update(_ observation: HandNavigationObservation?, pinchSensitivity: Double = 0.5,
                         pageSwipe: Bool = true, scroll: Bool = false, expanded: Bool = true,
                         interactionAvailable: Bool = true, expandOnPinch: Bool = true,
                         collapsedGestureAvailable: Bool = true,
                         navigationAvailable: Bool? = nil, calibrating: Bool = false,
                         leftAction: IslandGestureAction = .nextTab, rightAction: IslandGestureAction = .previousTab,
                         downAction: IslandGestureAction = .none) -> [HandNavigationAction] {
        guard let current = observation, current.isValid else { return reset() }
        if let previous, current.timestamp <= previous.timestamp { return [] }
        let pressThreshold = 0.18 + min(max(pinchSensitivity, 0), 1) * 0.16
        let releaseThreshold = pressThreshold + 0.13
        if let previous, (previous.side != .unknown && current.side != .unknown && previous.side != current.side) ||
            current.timestamp - previous.timestamp > 0.3 ||
            hypot(current.palm.x - previous.palm.x, current.palm.y - previous.palm.y) > 0.35 {
            let cancellation = reset(); self.previous = current
            classifier.update(current, releaseThreshold: releaseThreshold)
            return cancellation
        }
        let last = previous; previous = current
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
            guard calibrating else {
                phase = .tracking; candidateAt = nil; pressPoint = nil; needsRelease = true
                return cancellation
            }
            let pinch = updatePinch(current, pressThreshold: pressThreshold, releaseThreshold: releaseThreshold)
            // Calibration consumes a private confirmation; collapsed input never expands or clicks.
            return cancellation + (calibrating ? pinch.filter { $0 == .press } : [])
        }

        if classifier.palmCandidate {
            if swipeOrigin == nil { swipeOrigin = current.palm; swipeAt = current.timestamp }
            if classifier.pose == .pointer, !navigationOwnsHand, !isPressed {
                mode = .pointer
                return cancellation
            }
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
            guard navigationAvailable ?? interactionAvailable else { return cancellation }
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
                if current.timestamp - (neutralAt ?? current.timestamp) >= 0.15 - 0.000001 {
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
