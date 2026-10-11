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

enum HandNavigationAction: Equatable {
    case press, drag, release, cancel
    case page(forward: Bool)
    case scroll(Double)
}

struct HandNavigationStateMachine {
    enum Phase: String { case tracking, pinchCandidate, pressed, dragging }
    private(set) var phase: Phase = .tracking
    private var candidateAt: TimeInterval?
    private var pressPoint: CGPoint?
    private var previous: HandNavigationObservation?
    private var needsRelease = true
    private var swipeOrigin: CGPoint?
    private var swipeAt: TimeInterval?
    private var swipeArmed = true
    private var neutralAt: TimeInterval?
    private var scrollAt: TimeInterval?

    mutating func reset() -> [HandNavigationAction] {
        let actions: [HandNavigationAction] = phase == .pressed || phase == .dragging ? [.cancel] : []
        let rearmRequired = !swipeArmed
        self = Self()
        if rearmRequired { swipeArmed = false }
        return actions
    }

    mutating func update(_ observation: HandNavigationObservation?, pinchSensitivity: Double = 0.5,
                         pageSwipe: Bool = true, scroll: Bool = false) -> [HandNavigationAction] {
        guard let current = observation, current.isValid else { return reset() }
        if let previous, current.timestamp <= previous.timestamp { return [] }
        if let previous, (previous.side != .unknown && current.side != .unknown && previous.side != current.side) ||
            current.timestamp - previous.timestamp > 0.3 ||
            hypot(current.palm.x - previous.palm.x, current.palm.y - previous.palm.y) > 0.35 {
            let cancellation = reset()
            self.previous = current
            return cancellation
        }
        let last = previous
        previous = current
        let pressThreshold = 0.18 + min(max(pinchSensitivity, 0), 1) * 0.16
        let releaseThreshold = pressThreshold + 0.13
        if current.pinchRatio > releaseThreshold { needsRelease = false }
        if current.pose == .openPalm {
            let cancellation: [HandNavigationAction] = phase == .pressed || phase == .dragging ? [.cancel] : []
            phase = .tracking; candidateAt = nil; pressPoint = nil; scrollAt = nil
            if !cancellation.isEmpty { needsRelease = true; swipeArmed = false; neutralAt = nil; return cancellation }
            guard pageSwipe, current.pinchRatio > releaseThreshold else { return [] }
            if swipeOrigin == nil { swipeOrigin = current.palm; swipeAt = current.timestamp }
            let dt = last.map { max(current.timestamp - $0.timestamp, 0.001) } ?? 0.05
            let speed = last.map { hypot(current.palm.x - $0.palm.x, current.palm.y - $0.palm.y) / dt } ?? 0
            if !swipeArmed {
                if speed < 0.15 {
                    if neutralAt == nil { neutralAt = current.timestamp }
                    if current.timestamp - (neutralAt ?? current.timestamp) >= 0.35 {
                        swipeArmed = true; swipeOrigin = current.palm; swipeAt = current.timestamp
                    }
                } else { neutralAt = nil }
                return []
            }
            if let origin = swipeOrigin, let started = swipeAt {
                let dx = current.palm.x - origin.x, dy = current.palm.y - origin.y
                if current.timestamp - started > 0.7 { swipeOrigin = current.palm; swipeAt = current.timestamp }
                else if abs(dx) > 0.22, abs(dx) > abs(dy) * 1.8, speed > 0.45 {
                    swipeArmed = false; neutralAt = nil
                    return [.page(forward: dx < 0)]
                }
            }
            return []
        }
        swipeOrigin = nil; swipeAt = nil
        if !swipeArmed {
            if neutralAt == nil { neutralAt = current.timestamp }
            if current.timestamp - (neutralAt ?? current.timestamp) >= 0.2 { swipeArmed = true }
        } else { neutralAt = nil }
        if phase == .pressed || phase == .dragging {
            if current.pinchRatio > releaseThreshold {
                phase = .tracking; pressPoint = nil; return [.release]
            }
            if let pressPoint, hypot(current.fingertip.x - pressPoint.x, current.fingertip.y - pressPoint.y) > 0.025 {
                phase = .dragging
            }
            return phase == .dragging ? [.drag] : []
        }
        if current.pose == .twoFinger, current.pinchRatio > releaseThreshold {
            candidateAt = nil; phase = .tracking
            guard scroll else { return [] }
            if scrollAt == nil { scrollAt = current.timestamp }
            guard current.timestamp - (scrollAt ?? current.timestamp) >= 0.12,
                  let last, last.pose == .twoFinger else { return [] }
            let dy = current.palm.y - last.palm.y, dx = current.palm.x - last.palm.x
            return abs(dy) > abs(dx) * 1.5 && abs(dy) > 0.001 ? [.scroll(dy * 600)] : []
        }
        scrollAt = nil
        guard !needsRelease, current.pinchRatio < pressThreshold else {
            phase = .tracking; candidateAt = nil; return []
        }
        if candidateAt == nil { candidateAt = current.timestamp; phase = .pinchCandidate }
        guard current.timestamp - (candidateAt ?? current.timestamp) >= 0.06 else { return [] }
        phase = .pressed; pressPoint = current.fingertip; candidateAt = nil
        return [.press]
    }
}
