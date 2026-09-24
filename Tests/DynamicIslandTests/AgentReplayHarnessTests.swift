import XCTest
@testable import DynamicIsland

@MainActor
final class AgentReplayHarnessTests: XCTestCase {
    func testCodexNormalFixtureProducesExpectedIntermediateAndFinalSnapshots() throws {
        let result = AgentReplayHarness().replay(AgentTestFixture.codexNormal)

        XCTAssertEqual(result.steps.count, AgentTestFixture.codexNormal.events.count)
        XCTAssertEqual(result.steps[2].sessions.first?.state, .thinking)
        XCTAssertEqual(result.steps[4].sessions.first?.state, .runningCommand)
        XCTAssertEqual(result.steps[8].sessions.first?.state, .planReady)
        XCTAssertEqual(result.steps[9].sessions.first?.state, .waitingForApproval)
        XCTAssertEqual(result.steps[10].sessions.first?.state, .planReady)
        XCTAssertEqual(result.finalSessions.first?.state, .completed)
        XCTAssertEqual(result.finalSessions.first?.commands.count, 2)
        XCTAssertEqual(result.finalAttentionEvents.map(\.reason), [
            .approvalRequired, .planReady, .completed
        ])
    }

    func testClaudeNormalFixtureTracksToolPermissionAndSubagent() throws {
        let result = AgentReplayHarness().replay(AgentTestFixture.claudeNormal)
        let session = try XCTUnwrap(result.finalSessions.first)

        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.tools[AgentTestFixture.correlation("tool-1")]?.status, .completed)
        XCTAssertEqual(session.approvals[AgentTestFixture.correlation("permission-1")]?.state, .approved)
        XCTAssertEqual(session.subagents[AgentTestFixture.correlation("subagent-1")]?.status, .completed)
    }

    func testConcurrentProvidersReplayThroughOneStoreWithoutCrossTalk() {
        let events = AgentReplayHarness.interleaving([
            AgentTestFixture.codexNormal.events,
            AgentTestFixture.claudeNormal.events
        ])
        let result = AgentReplayHarness().replay(events)

        XCTAssertEqual(result.finalSessions.count, 2)
        XCTAssertEqual(Set(result.finalSessions.map(\.id.sessionID.provider)), [.codex, .claude])
        XCTAssertTrue(result.finalSessions.allSatisfy { $0.state == .completed })
    }

    func testSameProjectMultiSessionReplayKeepsNativeIdentity() {
        let project = AgentTestFixture.project()
        let first = AgentTestFixture.sessionID(.codex, "same-project-a")
        let second = AgentTestFixture.sessionID(.codex, "same-project-b")
        let fixture = AgentReplayFixture(name: "same project", events: [
            start("start-a", id: first, project: project, offset: 0),
            start("start-b", id: second, project: project, offset: 1)
        ])

        let result = AgentReplayHarness().replay(fixture)

        XCTAssertEqual(Set(result.finalSessions.map(\.id.sessionID)), [first, second])
        XCTAssertEqual(Set(result.finalSessions.compactMap(\.project.workingDirectory)), [project.workingDirectory])
    }

    func testGenerationReplacementFixtureRejectsDelayedOldEvent() {
        let id = AgentTestFixture.sessionID(.codex, "generation-replay")
        let fixture = AgentReplayFixture(name: "generation replacement", events: [
            start("generation-1", id: id, generation: 1, offset: 0),
            start("generation-2", id: id, generation: 2, offset: 1),
            AgentTestFixture.event(
                "stale-work",
                sessionID: id,
                generation: 1,
                type: .agentWorking,
                offset: 2,
                payload: .activity(AgentActivityDescriptor(title: "Stale", summary: nil))
            )
        ])

        let result = AgentReplayHarness().replay(fixture)

        XCTAssertEqual(result.steps.last?.application, .staleGeneration)
        XCTAssertEqual(result.finalSessions.first?.id.generation, AgentTestFixture.generation(2))
        XCTAssertFalse(result.finalSessions.contains { $0.recentActivity.contains { $0.title == "Stale" } })
    }

    func testDuplicateInjectionIsDeterministic() {
        let events = AgentReplayHarness.duplicating(
            eventAt: 2,
            in: AgentTestFixture.codexNormal.events
        )
        let result = AgentReplayHarness().replay(events)

        XCTAssertEqual(result.steps[3].application, .duplicate)
        XCTAssertEqual(result.finalSessions.first?.state, .completed)
    }

    func testReorderedCommandCompletionReconcilesWithLaterStart() throws {
        let original = AgentTestFixture.codexNormal.events
        let reordered = AgentReplayHarness.moving(eventAt: 5, to: 4, in: original)
        let result = AgentReplayHarness().replay(reordered)
        let command = try XCTUnwrap(
            result.finalSessions.first?.commands[AgentTestFixture.correlation("command-1")]
        )

        XCTAssertEqual(command.status, .completed)
        XCTAssertEqual(command.exitCode, 0)
        XCTAssertEqual(command.completedAt, AgentTestFixture.baseDate.addingTimeInterval(5))
    }

    func testMalformedAndUnknownNormalizedInputsDoNotCorruptSnapshot() {
        let id = AgentTestFixture.sessionID(.codex, "malformed-replay")
        let validStart = start("start", id: id, offset: 0)
        let wrongSchema = AgentTestFixture.event(
            "wrong-schema",
            sessionID: id,
            type: .heartbeat,
            offset: 1,
            schemaVersion: 99
        )
        let unknown = AgentTestFixture.event(
            "unknown",
            sessionID: id,
            type: .unsupported("future-event"),
            offset: 2,
            payload: .unsupported("future-payload")
        )

        let result = AgentReplayHarness().replay([validStart, wrongSchema, unknown])

        XCTAssertEqual(result.steps[1].application, .rejected(.validation(.unsupportedSchema)))
        XCTAssertEqual(result.steps[2].application, .rejected(.validation(.unsupportedEventType)))
        XCTAssertEqual(result.finalSessions.count, 1)
        XCTAssertEqual(result.finalSessions[0].state, .idle)
    }

    func testReplayIsDeterministicAcrossFreshHarnesses() {
        let first = AgentReplayHarness().replay(AgentTestFixture.codexNormal)
        let second = AgentReplayHarness().replay(AgentTestFixture.codexNormal)

        XCTAssertEqual(first, second)
    }

    func testDelayedEventHelperMovesOnlyRequestedEvent() {
        let events = AgentTestFixture.claudeNormal.events
        let delayed = AgentReplayHarness.delaying(eventAt: 3, untilAfter: 7, in: events)

        XCTAssertEqual(delayed.count, events.count)
        XCTAssertEqual(delayed[7].eventID, events[3].eventID)
        XCTAssertEqual(Set(delayed.map(\.eventID)), Set(events.map(\.eventID)))
    }

    private func start(
        _ name: String,
        id: AgentSessionID,
        generation: UInt64 = 1,
        project: AgentProjectContext? = nil,
        offset: TimeInterval
    ) -> AgentEvent {
        AgentTestFixture.event(
            name,
            sessionID: id,
            generation: generation,
            type: .sessionStarted,
            offset: offset,
            payload: .sessionMetadata(AgentSessionMetadata(project: project))
        )
    }
}
