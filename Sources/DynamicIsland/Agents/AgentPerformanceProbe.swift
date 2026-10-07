import Foundation
import os

/// DEBUG-only Agents page instrumentation. Every call is an `os_signpost`
/// (visible in Instruments under the "AgentsPerformance" category) plus a
/// cheap in-memory counter/duration so the measurement harness can report
/// numbers without Instruments. Release builds compile every call to nothing.
@MainActor
enum AgentPerformanceProbe {
    struct Duration: Equatable, Sendable {
        var count = 0
        var total: TimeInterval = 0
        var maximum: TimeInterval = 0

        var average: TimeInterval { count == 0 ? 0 : total / Double(count) }
    }

    struct Snapshot: Equatable, Sendable {
        var counters: [String: Int] = [:]
        var durations: [String: Duration] = [:]
        var gauges: [String: Int] = [:]
        var marks: [String: TimeInterval] = [:]
    }

#if DEBUG
    private static let signposter = OSSignposter(subsystem: "DynamicIsland", category: "AgentsPerformance")
    private static var state = Snapshot()
    private static let clock = ContinuousClock()
    private static let origin = ContinuousClock.now

    /// Counts one occurrence (a view body evaluation, a publication, ...).
    static func count(_ name: StaticString) {
        state.counters[String(describing: name), default: 0] += 1
    }

    static func countDynamic(_ name: String) {
        state.counters[name, default: 0] += 1
    }

    /// Records the latest value of a quantity (e.g. visible transcript rows).
    static func gauge(_ name: StaticString, _ value: Int) {
        state.gauges[String(describing: name)] = value
    }

    /// Times a synchronous unit of work.
    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval(name, id: id)
        let start = clock.now
        defer {
            signposter.endInterval(name, interval)
            record(name, seconds: (clock.now - start).seconds)
        }
        return try body()
    }

    /// A point in time (e.g. "Agents tab requested"). Stored as seconds since
    /// launch so the harness can compute end-to-end latencies.
    static func mark(_ name: StaticString) {
        signposter.emitEvent(name)
        state.marks[String(describing: name)] = (clock.now - origin).seconds
    }

    static func snapshot() -> Snapshot { state }

    static func reset() { state = Snapshot() }

    private static func record(_ name: StaticString, seconds: TimeInterval) {
        var value = state.durations[String(describing: name), default: Duration()]
        value.count += 1
        value.total += seconds
        value.maximum = max(value.maximum, seconds)
        state.durations[String(describing: name)] = value
    }
#else
    @inline(__always) static func count(_ name: StaticString) {}
    @inline(__always) static func countDynamic(_ name: String) {}
    @inline(__always) static func gauge(_ name: StaticString, _ value: Int) {}
    @inline(__always) static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T { try body() }
    @inline(__always) static func mark(_ name: StaticString) {}
    static func snapshot() -> Snapshot { Snapshot() }
    static func reset() {}
#endif
}

private extension Swift.Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
