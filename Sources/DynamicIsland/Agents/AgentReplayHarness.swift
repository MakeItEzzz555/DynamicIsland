import Foundation

struct AgentReplayFixture: Sendable {
    let name: String
    let events: [AgentEvent]
}

struct AgentReplayStepResult: Equatable, Sendable {
    let event: AgentEvent
    let application: AgentEventApplication
    let sessions: [AgentSession]
    let attentionEvents: [AgentAttentionEvent]
}

struct AgentReplayResult: Equatable, Sendable {
    let steps: [AgentReplayStepResult]

    var finalSessions: [AgentSession] {
        steps.last?.sessions ?? []
    }

    var finalAttentionEvents: [AgentAttentionEvent] {
        steps.last?.attentionEvents ?? []
    }
}

@MainActor
struct AgentReplayHarness {
    let store: AgentEventStore

    init(limits: AgentEventStoreLimits = .standard) {
        store = AgentEventStore(limits: limits)
    }

    func replay(_ fixture: AgentReplayFixture) -> AgentReplayResult {
        replay(fixture.events)
    }

    func replay(_ events: [AgentEvent]) -> AgentReplayResult {
        var steps: [AgentReplayStepResult] = []
        steps.reserveCapacity(events.count)
        for event in events {
            let application = store.ingest(event)
            steps.append(AgentReplayStepResult(
                event: event,
                application: application,
                sessions: store.sessions,
                attentionEvents: store.attentionEvents
            ))
        }
        return AgentReplayResult(steps: steps)
    }

    static func duplicating(eventAt index: Int, in events: [AgentEvent]) -> [AgentEvent] {
        guard events.indices.contains(index) else { return events }
        var result = events
        result.insert(events[index], at: index + 1)
        return result
    }

    static func moving(eventAt sourceIndex: Int, to destinationIndex: Int, in events: [AgentEvent]) -> [AgentEvent] {
        guard events.indices.contains(sourceIndex), destinationIndex >= 0, destinationIndex <= events.count else {
            return events
        }
        var result = events
        let event = result.remove(at: sourceIndex)
        result.insert(event, at: min(destinationIndex, result.count))
        return result
    }

    static func delaying(eventAt index: Int, untilAfter laterIndex: Int, in events: [AgentEvent]) -> [AgentEvent] {
        guard events.indices.contains(index), events.indices.contains(laterIndex), index < laterIndex else {
            return events
        }
        return moving(eventAt: index, to: laterIndex, in: events)
    }

    static func interleaving(_ sequences: [[AgentEvent]]) -> [AgentEvent] {
        let maximumCount = sequences.map(\.count).max() ?? 0
        return (0..<maximumCount).flatMap { index in
            sequences.compactMap { sequence in
                sequence.indices.contains(index) ? sequence[index] : nil
            }
        }
    }
}
