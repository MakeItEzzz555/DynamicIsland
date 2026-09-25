import Foundation
import XCTest
@testable import DynamicIsland

final class CodexRolloutRecoveryTests: XCTestCase {
    func testSessionMetaCreatesBoundedRecoverySessionAndCapabilities() throws {
        var parser = CodexRolloutRecoveryParser()
        let record = Data("""
        {"timestamp":"2026-09-25T09:00:00.000Z","ordinal":1,"type":"session_meta","payload":{"session_id":"s-1","id":"s-1","cwd":"/tmp/project","git":{"branch":"main","commit_hash":"abc123"},"creator_account_id":"DO-NOT-STORE"}}
        """.utf8)
        let events = try parser.parse(record, receivedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].provider, .codex)
        XCTAssertEqual(events[0].type, .sessionStarted)
        XCTAssertEqual(events[0].continuity?.immutableIdentity, "s-1")
        XCTAssertEqual(events[0].authority, .localStructuredRecord)
        XCTAssertEqual(events[1].type, .capabilitiesUpdated)
        if case .sessionMetadata(let metadata) = events[0].payload {
            XCTAssertEqual(metadata.project?.displayName, "project")
            XCTAssertEqual(metadata.project?.gitBranch, "main")
            XCTAssertEqual(metadata.project?.gitCommit, "abc123")
        } else {
            XCTFail("expected session metadata")
        }
    }

    func testTurnContextEnrichesModelAndCwdWithoutPromptContent() throws {
        var parser = CodexRolloutRecoveryParser()
        _ = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:00:00Z","ordinal":1,"type":"session_meta","payload":{"session_id":"s-1","id":"s-1","cwd":"/tmp/project"}}
        """.utf8))
        let events = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:01:00Z","ordinal":2,"type":"turn_context","payload":{"turn_id":"turn-1","cwd":"/tmp/project","model":"gpt-5.6-sol","instructions":"PRIVATE"}}
        """.utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .sessionMetadataUpdated)
        XCTAssertEqual(events[0].correlationID?.rawValue, "turn-1")
        if case .sessionMetadata(let metadata) = events[0].payload {
            XCTAssertEqual(metadata.project?.model, "gpt-5.6-sol")
        } else {
            XCTFail("expected metadata")
        }
    }

    func testTokenUsageRecordUsesAggregateCountsOnly() throws {
        var parser = CodexRolloutRecoveryParser()
        _ = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:00:00Z","ordinal":1,"type":"session_meta","payload":{"session_id":"s-1","id":"s-1","cwd":"/tmp/project"}}
        """.utf8))
        let events = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:02:00Z","ordinal":3,"type":"token_usage_record","payload":{"session_id":"s-1","turn_id":"turn-1","thread_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":40,"reasoning_output_tokens":5,"total_tokens":145},"response_id":"private-response-id"}}
        """.utf8))
        XCTAssertEqual(events.first?.type, .usageUpdated)
        if case .usage(let usage) = events[0].payload {
            XCTAssertEqual(usage[.inputTokens]?.value, 100)
            XCTAssertEqual(usage[.cachedInputTokens]?.value, 20)
            XCTAssertEqual(usage[.outputTokens]?.value, 40)
            XCTAssertEqual(usage[.reasoningTokens]?.value, 5)
            XCTAssertEqual(usage[.contextUsed]?.value, 145)
        } else {
            XCTFail("expected usage")
        }
    }

    func testTokenCountAddsObservedContextLimit() throws {
        var parser = CodexRolloutRecoveryParser()
        _ = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:00:00Z","ordinal":1,"type":"session_meta","payload":{"session_id":"s-1","id":"s-1","cwd":"/tmp/project"}}
        """.utf8))
        let events = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:03:00Z","ordinal":4,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120,"cached_input_tokens":30,"output_tokens":50,"reasoning_output_tokens":8,"total_tokens":178},"last_token_usage":{},"model_context_window":258000},"rate_limits":{"secret":"ignored"}}}
        """.utf8))
        if case .usage(let usage) = events[0].payload {
            XCTAssertEqual(usage[.contextUsed]?.value, 178)
            XCTAssertEqual(usage[.contextUsed]?.limit, 258000)
            XCTAssertEqual(usage[.contextLimit]?.value, 258000)
        } else {
            XCTFail("expected usage")
        }
    }

    func testRecoveryTaskLifecycleUsesLowerAuthority() throws {
        var parser = CodexRolloutRecoveryParser()
        _ = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:00:00Z","ordinal":1,"type":"session_meta","payload":{"session_id":"s-1","id":"s-1","cwd":"/tmp/project"}}
        """.utf8))
        let start = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:04:00Z","ordinal":5,"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1","message":"PRIVATE"}}
        """.utf8))
        let end = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:05:00Z","ordinal":6,"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"PRIVATE"}}
        """.utf8))
        XCTAssertEqual(start[0].type, .agentWorking)
        XCTAssertEqual(end[0].type, .taskCompleted)
        XCTAssertEqual(start[0].authority, .localStructuredRecord)
        XCTAssertEqual(end[0].authority, .localStructuredRecord)
    }

    func testUnsupportedRawResponseContentIsIgnoredByParser() throws {
        var parser = CodexRolloutRecoveryParser()
        _ = try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:00:00Z","ordinal":1,"type":"session_meta","payload":{"session_id":"s-1","id":"s-1","cwd":"/tmp/project"}}
        """.utf8))
        XCTAssertThrowsError(try parser.parse(Data("""
        {"timestamp":"2026-09-25T09:06:00Z","ordinal":7,"type":"response_item","payload":{"type":"message","content":"PRIVATE SOURCE OR PROMPT"}}
        """.utf8))) { error in
            XCTAssertEqual(error as? CodexRolloutRecoveryError, .unsupportedRecord)
        }
    }

    func testSecondaryRecoveryProducerDoesNotCreateNewGenerationAfterHookTerminal() async throws {
        let store = await MainActor.run { AgentEventStore() }
        let coordinator = await MainActor.run { AgentIngestionCoordinator(eventStore: store) }

        let hook = await coordinator.registerProducer(
            descriptor: AgentProducerDescriptor(
                sourceInstanceID: AgentSourceInstanceID(rawValue: "test.codex.hook"),
                sourceKind: .officialHook
            ),
            policy: .codexOfficialHook
        )
        let recovery = await coordinator.registerProducer(
            descriptor: AgentProducerDescriptor(
                sourceInstanceID: AgentSourceInstanceID(rawValue: "test.codex.recovery"),
                sourceKind: .structuredRecovery
            ),
            policy: .codexStructuredRecovery
        )
        guard case .success(let hookHandle) = hook,
              case .success(let recoveryHandle) = recovery else {
            return XCTFail("registration failed")
        }

        let now = Date()
        let start = AgentIngestionEvent(
            schemaVersion: 1,
            eventID: AgentEventID(rawValue: "hook-start"),
            provider: .codex,
            source: .unknown,
            nativeSessionID: "same-session",
            assertedGeneration: nil,
            type: .sessionStarted,
            providerTimestamp: now,
            receivedTimestamp: now,
            correlationID: nil,
            sequence: 1,
            authority: .lifecycle,
            payload: .none,
            continuity: AgentSessionContinuity(immutableIdentity: "same-session")
        )
        let done = AgentIngestionEvent(
            schemaVersion: 1,
            eventID: AgentEventID(rawValue: "hook-done"),
            provider: .codex,
            source: .unknown,
            nativeSessionID: "same-session",
            assertedGeneration: nil,
            type: .taskCompleted,
            providerTimestamp: now,
            receivedTimestamp: now,
            correlationID: AgentCorrelationID(rawValue: "turn-1"),
            sequence: 2,
            authority: .lifecycle,
            payload: .terminal(AgentTerminalEvent(summary: nil)),
            continuity: AgentSessionContinuity(immutableIdentity: "same-session")
        )
        _ = await coordinator.ingest(start, from: hookHandle)
        _ = await coordinator.ingest(done, from: hookHandle)

        let recoveryStart = AgentIngestionEvent(
            schemaVersion: 1,
            eventID: AgentEventID(rawValue: "recovery-start"),
            provider: .codex,
            source: .unknown,
            nativeSessionID: "same-session",
            assertedGeneration: nil,
            type: .sessionStarted,
            providerTimestamp: now,
            receivedTimestamp: now,
            correlationID: nil,
            sequence: 1,
            authority: .localStructuredRecord,
            payload: .none,
            continuity: AgentSessionContinuity(immutableIdentity: "same-session")
        )
        _ = await coordinator.ingest(recoveryStart, from: recoveryHandle)

        let leases = await coordinator.sessionLeases()
        XCTAssertEqual(leases.count, 1)
        XCTAssertEqual(leases.first?.instanceID.generation.rawValue, 1)
    }
}
