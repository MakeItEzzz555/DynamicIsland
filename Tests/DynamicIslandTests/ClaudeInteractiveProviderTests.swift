import Foundation
import XCTest
@testable import DynamicIsland

final class ClaudeInteractiveProviderTests: XCTestCase {
    func testCapabilitiesExposeOnlyAuthoritativeCLIControl() async throws {
        let provider = try ClaudeInteractiveProvider(
            client: ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )

        XCTAssertEqual(provider.provider, .claude)
        XCTAssertEqual(provider.interactiveCapabilities, [
            .startSession, .resumeSession, .submitPrompt, .interrupt, .selectModel,
            .resolveApprovals, .accountUsage, .contextUsage, .streamMessages, .streamToolActivity
        ])
        XCTAssertFalse(provider.interactiveCapabilities.contains(.loadHistory))
        // Model is chosen at session start only; no in-place switching claimed.
        XCTAssertNil(provider.modelSelectionScope)
    }

    func testResumePreservesExactClaudeNativeSessionIdentity() async throws {
        let provider = try ClaudeInteractiveProvider(
            client: ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )

        let resumed = try await provider.resumeSession(
            nativeSessionID: "claude-session-123",
            cwd: "/tmp/project"
        )

        XCTAssertEqual(resumed.provider, .claude)
        XCTAssertEqual(resumed.nativeSessionID, "claude-session-123")
        XCTAssertEqual(resumed.cwd, "/tmp/project")
        XCTAssertTrue(resumed.acceptsDirectInput)
    }

    func testKnownClaudeSessionsAreActuallyBoundedInProviderState() async throws {
        let provider = try ClaudeInteractiveProvider(
            client: ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )

        for index in 0..<(ClaudeInteractiveProvider.maximumKnownSessions + 7) {
            _ = try await provider.resumeSession(nativeSessionID: "claude-\(index)", cwd: nil)
        }

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, ClaudeInteractiveProvider.maximumKnownSessions)
        XCTAssertEqual(Set(sessions.map { $0.session.nativeSessionID }).count, sessions.count)
    }

    func testVisibleAgentTextAndSafeToolAreProjectedButReasoningIsIgnored() async throws {
        let provider = try ClaudeInteractiveProvider(
            client: ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )
        let envelope = ClaudeCodeStreamEnvelope(
            nativeSessionID: "session-1",
            turnID: "turn-1",
            message: .object([
                "type": .string("assistant"),
                "message": .object([
                    "id": .string("message-1"),
                    "content": .array([
                        .object(["type": .string("thinking"), "thinking": .string("private")]),
                        .object(["type": .string("text"), "text": .string("Visible answer")]),
                        .object([
                            "type": .string("tool_use"),
                            "id": .string("tool-1"),
                            "name": .string("Bash"),
                            "input": .object(["command": .string("echo SECRET")])
                        ])
                    ])
                ])
            ])
        )

        let events = await provider.project(envelope)
        let entries = events.compactMap { event -> AgentManagedTranscriptEntry? in
            guard case .transcript(let entry) = event else { return nil }
            return entry
        }

        XCTAssertEqual(entries.map(\.role), [.agent, .command])
        XCTAssertEqual(entries.map(\.text), ["Visible answer", "Run command"])
        XCTAssertFalse(entries.contains { $0.text.contains("private") || $0.text.contains("SECRET") })
    }

    func testStreamingDeltaAndCompletedMessageShareStableIdentity() async throws {
        let provider = try ClaudeInteractiveProvider(
            client: ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )
        _ = await provider.project(envelope(type: "stream_event", event: .object([
            "type": .string("message_start"),
            "message": .object(["id": .string("message-1")])
        ])))
        let delta = await provider.project(envelope(type: "stream_event", event: .object([
            "type": .string("content_block_delta"),
            "index": .integer(0),
            "delta": .object(["type": .string("text_delta"), "text": .string("Hello")])
        ])))
        let completed = await provider.project(ClaudeCodeStreamEnvelope(
            nativeSessionID: "session-1",
            turnID: "turn-1",
            message: .object([
                "type": .string("assistant"),
                "message": .object([
                    "id": .string("message-1"),
                    "content": .array([
                        .object(["type": .string("text"), "text": .string("Hello world")])
                    ])
                ])
            ])
        ))

        guard case .transcriptDelta(_, _, let deltaID, _) = try XCTUnwrap(delta.first),
              case .transcript(let final) = try XCTUnwrap(completed.first) else {
            return XCTFail("Expected delta and completed transcript")
        }
        XCTAssertEqual(deltaID, final.id)
        XCTAssertEqual(final.text, "Hello world")
    }

    /// Verified shape from Claude Code 2.1.285 with --include-partial-messages:
    /// one `assistant` event per block, whose content holds only that block,
    /// while stream deltas use the real block index (text after thinking = 1).
    func testPerBlockAssistantEventsDoNotDuplicateStreamedText() async throws {
        let provider = try ClaudeInteractiveProvider(
            client: ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )
        _ = await provider.project(envelope(type: "stream_event", event: .object([
            "type": .string("message_start"),
            "message": .object(["id": .string("msg-1")])
        ])))
        _ = await provider.project(envelope(type: "stream_event", event: .object([
            "type": .string("content_block_start"), "index": .integer(0),
            "content_block": .object(["type": .string("thinking")])
        ])))
        let thinking = await provider.project(assistant(messageID: "msg-1", block: .object([
            "type": .string("thinking"), "thinking": .string("private")
        ])))
        XCTAssertTrue(thinking.isEmpty)
        _ = await provider.project(envelope(type: "stream_event", event: .object([
            "type": .string("content_block_start"), "index": .integer(1),
            "content_block": .object(["type": .string("text")])
        ])))
        let delta = await provider.project(envelope(type: "stream_event", event: .object([
            "type": .string("content_block_delta"), "index": .integer(1),
            "delta": .object(["type": .string("text_delta"), "text": .string("DONE")])
        ])))
        let completed = await provider.project(assistant(messageID: "msg-1", block: .object([
            "type": .string("text"), "text": .string("DONE")
        ])))

        guard case .transcriptDelta(_, _, let deltaID, _) = try XCTUnwrap(delta.first),
              case .transcript(let final) = try XCTUnwrap(completed.first) else {
            return XCTFail("Expected delta and completed transcript")
        }
        XCTAssertEqual(deltaID, final.id, "streamed and completed text must be one entry")
    }

    private func assistant(messageID: String, block: CodexJSONValue) -> ClaudeCodeStreamEnvelope {
        ClaudeCodeStreamEnvelope(
            nativeSessionID: "session-1",
            turnID: "turn-1",
            message: .object([
                "type": .string("assistant"),
                "message": .object(["id": .string(messageID), "content": .array([block])])
            ])
        )
    }

    func testResultMapsToIdleTurnCompletionWithoutEndingThreadIdentity() async throws {
        let provider = try ClaudeInteractiveProvider(
            client: ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )
        let events = await provider.project(envelope(type: "result", extra: [
            "subtype": .string("success"),
            "is_error": .bool(false)
        ]))

        guard case .turnCompleted(let turn, let state, _) = try XCTUnwrap(events.first) else {
            return XCTFail("Expected completion")
        }
        XCTAssertEqual(turn.nativeSessionID, "session-1")
        XCTAssertEqual(state, .completed)
    }

    func testManagedPolicyPermitsExactApprovalControlForClaudeOnly() {
        XCTAssertTrue(AgentProducerPolicy.claudeManagedCLI.permitsApprovalControl)
        XCTAssertTrue(AgentProducerPolicy.claudeManagedCLI.allowedCapabilities.contains(.approvalControl))
        XCTAssertTrue(AgentProducerPolicy.claudeManagedCLI.allowedEventTypes.contains(.approvalRequested))
        XCTAssertEqual(AgentProducerPolicy.claudeManagedCLI.allowedProviders, [.claude])
        XCTAssertFalse(AgentProducerPolicy.claudeStructuredRecovery.permitsApprovalControl)
    }

    private func envelope(
        type: String,
        event: CodexJSONValue? = nil,
        extra: [String: CodexJSONValue] = [:]
    ) -> ClaudeCodeStreamEnvelope {
        var message = extra
        message["type"] = .string(type)
        if let event { message["event"] = event }
        return ClaudeCodeStreamEnvelope(
            nativeSessionID: "session-1",
            turnID: "turn-1",
            message: .object(message)
        )
    }
}
