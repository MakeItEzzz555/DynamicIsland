import Foundation
import XCTest
@testable import DynamicIsland

final class ClaudeTranscriptRecoveryTests: XCTestCase {
    func testFirstRecordStartsRecoverySessionAndDropsMessageContent() throws {
        var parser = ClaudeTranscriptRecoveryParser()
        let line = Data("""
        {"sessionId":"s-1","uuid":"m-1","cwd":"/tmp/project","gitBranch":"main","timestamp":"2026-09-25T10:00:00Z","message":{"role":"user","content":"PRIVATE PROMPT"}}
        """.utf8)
        let events = try parser.parse(line)
        XCTAssertEqual(events.first?.type, .sessionStarted)
        XCTAssertEqual(events.first?.provider, .claude)
        XCTAssertEqual(events.first?.continuity?.immutableIdentity, "s-1")
        XCTAssertEqual(events.first?.authority, .localStructuredRecord)
        XCTAssertTrue(events.contains { $0.type == .capabilitiesUpdated })
    }

    func testThinkingAndToolLifecycleUseStructuralFieldsOnly() throws {
        var parser = ClaudeTranscriptRecoveryParser()
        _ = try parser.parse(Data("""
        {"sessionId":"s-1","uuid":"m-1","cwd":"/tmp/project","timestamp":"2026-09-25T10:00:00Z","message":{"role":"user","content":[]}}
        """.utf8))
        let line = Data("""
        {"sessionId":"s-1","uuid":"m-2","cwd":"/tmp/project","timestamp":"2026-09-25T10:01:00Z","message":{"role":"assistant","model":"claude-opus","content":[{"type":"thinking","thinking":"PRIVATE THOUGHT"},{"type":"tool_use","id":"tool-1","name":"Read","input":{"file_path":"/private/secret"}}]}}
        """.utf8)
        let events = try parser.parse(line)
        XCTAssertTrue(events.contains { $0.type == .thinkingStarted })
        XCTAssertTrue(events.contains { $0.type == .thinkingEnded })
        XCTAssertTrue(events.contains { $0.type == .toolStarted && $0.correlationID?.rawValue == "tool-1" })
    }

    func testToolResultCompletesKnownOperationWithoutResultBody() throws {
        var parser = ClaudeTranscriptRecoveryParser()
        _ = try parser.parse(Data("""
        {"sessionId":"s-1","uuid":"m-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"SECRET"}}]}}
        """.utf8))
        let events = try parser.parse(Data("""
        {"sessionId":"s-1","uuid":"m-2","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-1","content":"PRIVATE OUTPUT","is_error":false}]}}
        """.utf8))
        XCTAssertTrue(events.contains { $0.type == .commandCompleted && $0.correlationID?.rawValue == "tool-1" })
    }

    func testUsageUsesOnlyObservedAggregateCounters() throws {
        var parser = ClaudeTranscriptRecoveryParser()
        let events = try parser.parse(Data("""
        {"sessionId":"s-1","uuid":"m-1","message":{"role":"assistant","usage":{"input_tokens":100,"output_tokens":40,"cache_read_input_tokens":20,"cache_creation_input_tokens":999},"content":[]}}
        """.utf8))
        let usageEvent = try XCTUnwrap(events.first(where: { $0.type == .usageUpdated }))
        guard case .usage(let usage) = usageEvent.payload else {
            return XCTFail("expected usage")
        }
        XCTAssertEqual(usage[.inputTokens]?.value, 100)
        XCTAssertEqual(usage[.outputTokens]?.value, 40)
        XCTAssertEqual(usage[.cachedInputTokens]?.value, 20)
        XCTAssertNil(usage[.contextLimit])
        XCTAssertNil(usage[.quotaUsed])
    }

    func testEndTurnIsFallbackCompletionAtStructuredRecordAuthority() throws {
        var parser = ClaudeTranscriptRecoveryParser()
        let events = try parser.parse(Data("""
        {"sessionId":"s-1","uuid":"m-1","timestamp":"2026-09-25T10:00:00Z","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"PRIVATE ANSWER"}]}}
        """.utf8))
        let completed = try XCTUnwrap(events.first(where: { $0.type == .taskCompleted }))
        XCTAssertEqual(completed.authority, .localStructuredRecord)
    }

    func testUncorrelatedToolResultDoesNotFabricateOperation() throws {
        var parser = ClaudeTranscriptRecoveryParser()
        let events = try parser.parse(Data("""
        {"sessionId":"s-1","uuid":"m-1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"unknown","content":"PRIVATE"}]}}
        """.utf8))
        XCTAssertFalse(events.contains { $0.type == .toolCompleted || $0.type == .commandCompleted })
    }

    func testSameSessionCanConvergeWithOfficialHookProducer() async {
        let store = await MainActor.run { AgentEventStore() }
        let coordinator = await MainActor.run { AgentIngestionCoordinator(eventStore: store) }

        let hook = await coordinator.registerProducer(
            descriptor: AgentProducerDescriptor(
                sourceInstanceID: AgentSourceInstanceID(rawValue: "test.claude.hook"),
                sourceKind: .officialHook
            ),
            policy: .claudeOfficialHook
        )
        let recovery = await coordinator.registerProducer(
            descriptor: AgentProducerDescriptor(
                sourceInstanceID: AgentSourceInstanceID(rawValue: "test.claude.recovery"),
                sourceKind: .structuredRecovery
            ),
            policy: .claudeStructuredRecovery
        )
        guard case .success(let hookHandle) = hook,
              case .success(let recoveryHandle) = recovery else {
            return XCTFail("registration failed")
        }

        let now = Date()
        let hookStart = AgentIngestionEvent(
            schemaVersion: 1,
            eventID: AgentEventID(rawValue: "hook-start"),
            provider: .claude,
            source: .unknown,
            nativeSessionID: "same-session",
            assertedGeneration: nil,
            type: .sessionStarted,
            providerTimestamp: now,
            receivedTimestamp: now,
            correlationID: nil,
            sequence: nil,
            authority: .lifecycle,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil)),
            continuity: AgentSessionContinuity(immutableIdentity: "same-session")
        )
        let recoveryStart = AgentIngestionEvent(
            schemaVersion: 1,
            eventID: AgentEventID(rawValue: "recovery-start"),
            provider: .claude,
            source: .unknown,
            nativeSessionID: "same-session",
            assertedGeneration: nil,
            type: .sessionStarted,
            providerTimestamp: now,
            receivedTimestamp: now,
            correlationID: nil,
            sequence: nil,
            authority: .localStructuredRecord,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil)),
            continuity: AgentSessionContinuity(immutableIdentity: "same-session")
        )

        _ = await coordinator.ingest(hookStart, from: hookHandle)
        _ = await coordinator.ingest(recoveryStart, from: recoveryHandle)

        let leases = await coordinator.sessionLeases()
        XCTAssertEqual(leases.count, 1)
        XCTAssertEqual(leases.first?.owners.count, 2)
        XCTAssertEqual(leases.first?.instanceID.generation.rawValue, 1)
    }
}
