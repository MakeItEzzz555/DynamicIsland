import CoreGraphics
import Foundation

/// Ruler geometry: a fixed centre pointer over a ruler that slides so the
/// value under the pointer is the selected duration (idle) or the remaining
/// time (active). Pure and deterministic.
extension TimerRulerScale {
    struct Tick: Equatable {
        let height: CGFloat
        let labelled: Bool
    }

    static let majorTickHeight: CGFloat = 22
    static let minuteTickHeight: CGFloat = 13
    static let tickBaseline: CGFloat = 38
    static let rulerHeight: CGFloat = 52

    static func x(forMinute minute: Int, value: Double, center: CGFloat) -> CGFloat {
        center + CGFloat(Double(minute) - value) * pointsPerMinute
    }

    static func tick(forMinute minute: Int) -> Tick {
        minute.isMultiple(of: 5) ? Tick(height: majorTickHeight, labelled: true)
            : Tick(height: minuteTickHeight, labelled: false)
    }

    /// Only ticks that can land inside `width`; bounded by width / spacing.
    static func visibleMinutes(value: Double, width: CGFloat, lowerBound: Int) -> ClosedRange<Int> {
        let span = Double(width / 2 / pointsPerMinute) + 1
        let lower = max(lowerBound, Int((value - span).rounded(.down)))
        let upper = min(180, Int((value + span).rounded(.up)))
        return lower...max(lower, upper)
    }
}

/// Derives the countdown presentation from `TimerTimingSnapshot`. Nothing here
/// owns time: remounting a view recomputes the same position.
enum TimerCountdownPresentation {
    /// Minutes under the pointer.
    static func rulerValue(snapshot: TimerTimingSnapshot, now: Duration, selectedMinutes: Int) -> Double {
        switch snapshot.phase {
        // Ready (after reset) is a fresh selection; play starts from it.
        case .idle, .ready: Double(selectedMinutes)
        case .running, .paused: minutes(snapshot.remaining(at: now))
        }
    }

    static func isCountingDown(_ snapshot: TimerTimingSnapshot) -> Bool {
        switch snapshot.phase {
        case .running, .paused: true
        case .idle, .ready: false
        }
    }

    static func displayText(remaining seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    static func remainingSeconds(_ snapshot: TimerTimingSnapshot, now: Duration) -> Double {
        seconds(snapshot.remaining(at: now))
    }

    /// Redraw cadence while running: fast enough for half-pixel ruler steps and
    /// a timely seconds label, never a display-rate loop. Nil means static.
    static func frameInterval(snapshot: TimerTimingSnapshot, displayScale: CGFloat) -> Double? {
        guard snapshot.isRunning else { return nil }
        let pixelsPerSecond = Double(TimerRulerScale.pointsPerMinute * max(1, displayScale)) / 60
        let halfPixel = 0.5 / max(pixelsPerSecond, 0.0001)
        return min(0.25, max(1.0 / 30, halfPixel))
    }

    static func accessibilityValue(snapshot: TimerTimingSnapshot, now: Duration, selectedMinutes: Int) -> String {
        guard isCountingDown(snapshot) else { return "\(selectedMinutes) minutes selected" }
        let whole = max(0, Int(seconds(snapshot.remaining(at: now)).rounded(.up)))
        let time = "\(whole / 60) minutes \(whole % 60) seconds remaining"
        switch snapshot.phase {
        case .running: return time + ", running"
        case .paused: return time + ", paused"
        default: return time + ", ready"
        }
    }

    private static func minutes(_ duration: Duration) -> Double { seconds(duration) / 60 }
    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
