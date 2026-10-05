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

    static let majorTickHeight: CGFloat = 28
    static let minuteTickHeight: CGFloat = 14
    static let tickBaseline: CGFloat = 44
    static let rulerHeight: CGFloat = 62

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

/// Persist exact seconds; older minute preferences migrate without changing
/// the selected duration. These values never own an active countdown.
enum TimerDurationSelection {
    static let maximumSeconds = 180 * 60
    static func seconds(_ value: Double) -> Int {
        guard value.isFinite else { return 25 * 60 }
        return Int(min(Double(maximumSeconds), max(1, value)).rounded())
    }
    static func restored(seconds stored: Int, legacyMinutes: Int) -> Int {
        stored > 0 ? seconds(Double(stored)) : TimerRulerScale.minutes(Double(legacyMinutes)) * 60
    }
}

enum TimerRulerResolution: String, CaseIterable {
    case seconds, minutes
    var stepSeconds: Int { self == .seconds ? 1 : 60 }
    var pointsPerTick: CGFloat { 9 }
    var pointsPerSecond: CGFloat { pointsPerTick / CGFloat(stepSeconds) }
    var title: String { self == .seconds ? "1s" : "1m" }
}

/// Captured once per drag. Translation is always relative to the original
/// duration/scale, so a mode or scale change cannot compound each delta.
struct TimerRulerDragSelection: Equatable {
    let originSeconds: Int
    let resolution: TimerRulerResolution
    private(set) var previousValue: Double
    init(seconds: Int, resolution: TimerRulerResolution) {
        originSeconds = TimerDurationSelection.seconds(Double(seconds))
        self.resolution = resolution
        previousValue = Double(originSeconds)
    }
    struct Change: Equatable {
        var value: Double
        var selectedSeconds: Int
        var crossedTicks: [Int]
    }
    mutating func update(translation: Double) -> Change {
        guard translation.isFinite else {
            return Change(value: previousValue, selectedSeconds: TimerDurationSelection.seconds(previousValue), crossedTicks: [])
        }
        let value = min(Double(TimerDurationSelection.maximumSeconds), max(1,
            Double(originSeconds) - translation / Double(resolution.pointsPerSecond)))
        let ticks = TimerRulerInteractionGeometry.crossedTicks(from: previousValue, to: value, resolution: resolution)
        previousValue = value
        return Change(value: value, selectedSeconds: TimerDurationSelection.seconds(value), crossedTicks: ticks)
    }
}

enum TimerRulerInteractionGeometry {
    static func x(forTick tick: Int, valueSeconds: Double, center: CGFloat, resolution: TimerRulerResolution) -> CGFloat {
        center + CGFloat(Double(tick * resolution.stepSeconds) - valueSeconds) * resolution.pointsPerSecond
    }
    static func visibleTicks(valueSeconds: Double, width: CGFloat, resolution: TimerRulerResolution) -> ClosedRange<Int> {
        let value = min(Double(TimerDurationSelection.maximumSeconds), max(0, valueSeconds.isFinite ? valueSeconds : 0))
        let center = value / Double(resolution.stepSeconds)
        let safeWidth = width.isFinite ? max(0, width) : 0
        let span = min(Double(TimerDurationSelection.maximumSeconds / resolution.stepSeconds),
                       Double(safeWidth / resolution.pointsPerTick / 2) + 1)
        let lower = max(0, Int((center - span).rounded(.down)))
        let upper = min(TimerDurationSelection.maximumSeconds / resolution.stepSeconds, Int((center + span).rounded(.up)))
        return lower...max(lower, upper)
    }
    static func tick(_ index: Int, resolution: TimerRulerResolution) -> TimerRulerScale.Tick {
        if resolution == .minutes { return TimerRulerScale.tick(forMinute: index) }
        if index.isMultiple(of: 60) { return .init(height: 32, labelled: true) }
        if index.isMultiple(of: 15) { return .init(height: 28, labelled: true) }
        if index.isMultiple(of: 5) { return .init(height: 22, labelled: false) }
        return .init(height: 14, labelled: false)
    }
    /// Excludes the starting boundary, includes the newly reached boundary.
    /// Fast deltas enumerate every crossed tick once; repeated deltas enumerate none.
    static func crossedTicks(from previous: Double, to current: Double, resolution: TimerRulerResolution) -> [Int] {
        guard previous.isFinite, current.isFinite, previous != current else { return [] }
        let limit = Double(TimerDurationSelection.maximumSeconds)
        let old = min(limit, max(1, previous)) / Double(resolution.stepSeconds)
        let new = min(limit, max(1, current)) / Double(resolution.stepSeconds)
        if new > old {
            let first = Int(old.rounded(.down)) + 1
            let last = Int(new.rounded(.down))
            return first <= last ? Array(first...last) : []
        }
        let first = Int(old.rounded(.up)) - 1
        let last = Int(new.rounded(.up))
        return first >= last ? Array(stride(from: first, through: last, by: -1)) : []
    }
}

extension TimerCountdownPresentation {
    static func rulerSeconds(snapshot: TimerTimingSnapshot, now: Duration, selectedSeconds: Int) -> Double {
        isCountingDown(snapshot) ? remainingSeconds(snapshot, now: now) : Double(TimerDurationSelection.seconds(Double(selectedSeconds)))
    }
    static func accessibilityValue(snapshot: TimerTimingSnapshot, now: Duration, selectedSeconds: Int) -> String {
        if isCountingDown(snapshot) {
            return accessibilityValue(snapshot: snapshot, now: now, selectedMinutes: 0)
        }
        let value = TimerDurationSelection.seconds(Double(selectedSeconds))
        return "\(value / 60) minutes \(value % 60) seconds selected"
    }
    static func frameInterval(snapshot: TimerTimingSnapshot, displayScale: CGFloat, resolution: TimerRulerResolution) -> Double? {
        guard snapshot.isRunning else { return nil }
        let pixelsPerSecond = Double(resolution.pointsPerSecond * max(1, displayScale))
        return min(0.25, max(1.0 / 30, 0.5 / pixelsPerSecond))
    }
}

// Scoped input ownership shared with the island's navigation arbiter.
import SwiftUI

struct TimerRulerInteractionRegistration {
    var enabled: Bool
    var report: @MainActor (UUID, CGRect?) -> Void
    init(enabled: Bool = true, _ report: @escaping @MainActor (UUID, CGRect?) -> Void = { _, _ in }) {
        self.enabled = enabled; self.report = report
    }
}
private struct TimerRulerInteractionRegistrationKey: EnvironmentKey {
    static var defaultValue: TimerRulerInteractionRegistration { .init() }
}
extension EnvironmentValues {
    var timerRulerInteractionRegistration: TimerRulerInteractionRegistration {
        get { self[TimerRulerInteractionRegistrationKey.self] }
        set { self[TimerRulerInteractionRegistrationKey.self] = newValue }
    }
}
struct TimerRulerInteractionFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
final class TimerRulerMeasuredFrame { var frame: CGRect = .zero }
