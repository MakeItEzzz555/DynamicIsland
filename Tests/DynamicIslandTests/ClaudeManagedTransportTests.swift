import Foundation
import XCTest
@testable import DynamicIsland

private func json(_ text: String) -> CodexJSONValue {
    try! JSONDecoder().decode(CodexJSONValue.self, from: Data(text.utf8))
}

private final class FixedUsageProbe: ClaudeUsageProbing, @unchecked Sendable {
    var result: ClaudeUsageProbeResult
    var calls = 0
    init(_ result: ClaudeUsageProbeResult) { self.result = result }
    func probe() async throws -> ClaudeUsageProbeResult {
        calls += 1
        return result
    }
}

private struct EmptyCatalog: ClaudeSessionCataloging {
    func recentSessions(limit: Int) throws -> [ClaudeCatalogEntry] { [] }
    func session(nativeSessionID: String) throws -> ClaudeCatalogEntry? { nil }
}

final class ClaudeLaunchSpecTests: XCTestCase {
    func testNewSessionUsesExactSessionIDAndHostPermissions() {
        let spec = ClaudeLaunchSpec(nativeSessionID: "abc", mode: .new, cwd: "/p", model: "sonnet", agent: "code-reviewer")
        XCTAssertEqual(spec.arguments, [
            "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--permission-prompts", "host", "--permission-prompt-tool", "stdio",
            "--session-id", "abc", "--model", "sonnet", "--agent", "code-reviewer"
        ])
        XCTAssertFalse(spec.arguments.contains { $0.contains("dangerously") || $0 == "bypassPermissions" })
    }

    func testResumeKeepsExactSessionID() {
        let spec = ClaudeLaunchSpec(nativeSessionID: "abc", mode: .resume, cwd: nil, model: nil, agent: nil)
        XCTAssertTrue(spec.arguments.suffix(2).elementsEqual(["--resume", "abc"]))
        XCTAssertFalse(spec.arguments.contains("--model"))
    }

    func testEnvironmentAddsUserToolPaths() {
        let path = ClaudeCodeStreamingClient.environment(base: ["PATH": "/usr/bin"])["PATH"] ?? ""
        XCTAssertTrue(path.hasPrefix("/usr/bin"))
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertEqual(path.components(separatedBy: ":").filter { $0 == "/usr/bin" }.count, 1)
    }
}

final class ClaudeUsageParserTests: XCTestCase {
    /// Captured (sanitized) from Claude Code 2.1.285 `/usage`.
    static let usageText = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 17% used · resets Sep 30 at 11:59am (Asia/Nicosia)
        Current week (all models): 16% used · resets Oct 4 at 8:59pm (Asia/Nicosia)

        What's contributing to your limits usage?
        """

    func testUsageTextParsesSessionAndWeek() {
        let windows = ClaudeUsageTextParser.parse(Self.usageText)
        XCTAssertEqual(windows?.fiveHourUsedPercent, 17)
        XCTAssertEqual(windows?.weekUsedPercent, 16)
    }

    func testUnrecognizedUsageTextYieldsNothing() {
        XCTAssertNil(ClaudeUsageTextParser.parse("Usage is not available for API keys"))
        XCTAssertNil(ClaudeUsageTextParser.parse("Current session: lots used"))
        XCTAssertNil(ClaudeUsageTextParser.parse("Current session: 140% used"))
    }

    func testRateLimitInfoParsesUnifiedWindowsAsPercentUsed() {
        let info = json(#"{"status":"allowed","resetsAt":1790758800,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.16,"resetsAt":1790758800},"seven_day":{"utilization":0.15,"resetsAt":1791136800}}}"#)
        let windows = ClaudeRateLimitParser.parse(info)
        XCTAssertEqual(windows?.fiveHourUsedPercent ?? -1, 16, accuracy: 0.0001)
        XCTAssertEqual(windows?.weekUsedPercent ?? -1, 15, accuracy: 0.0001)
        XCTAssertEqual(windows?.fiveHourResetsAt, Date(timeIntervalSince1970: 1790758800))
        XCTAssertNil(ClaudeRateLimitParser.parse(json(#"{"status":"allowed"}"#)))
        XCTAssertNil(ClaudeRateLimitParser.parse(json(#"{"unifiedWindows":{"five_hour":{"utilization":7}}}"#)))
    }

    func testProbeOutputParsesInitAgentsAndUsage() {
        let lines = [
            #"{"type":"system","subtype":"init","model":"claude-opus-5-5","claude_code_version":"2.1.285","agents":["general-purpose","code-reviewer"]}"#,
            #"{"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"Current session: 40% used · resets x\nCurrent week (all models): 9% used · resets y"}]}}"#,
            #"{"type":"result","subtype":"success","total_cost_usd":0}"#
        ].joined(separator: "\n")
        let result = ClaudeUsageCommandProbe.parse(Data(lines.utf8))
        XCTAssertEqual(result.windows?.fiveHourUsedPercent, 40)
        XCTAssertEqual(result.windows?.weekUsedPercent, 9)
        XCTAssertEqual(result.availableAgents, ["general-purpose", "code-reviewer"])
        XCTAssertEqual(result.cliVersion, "2.1.285")
        XCTAssertTrue(ClaudeUsageCommandProbe.arguments.contains("--no-session-persistence"))
    }

    func testClaudeWindowsBecomeRemainingIndicatorsWithTruthfulAuthority() {
        let windows = ClaudeUsageWindows(fiveHourUsedPercent: 16, weekUsedPercent: 15)
        let now = Date()
        for (source, authority) in [
            (ClaudeUsageSource.rateLimitEvent, AgentUsageIndicator.Authority.providerEvent),
            (ClaudeUsageSource.usageCommand, .providerCLI)
        ] {
            let indicators = AgentUsageIndicatorPresentation.make(
                provider: .claude,
                accountUsage: windows.usage(source: source, observedAt: now),
                selectedSession: nil,
                now: now
            )
            XCTAssertEqual(indicators[0].fraction ?? -1, 0.84, accuracy: 0.0001)
            XCTAssertEqual(indicators[0].direction, .remaining)
            XCTAssertEqual(indicators[0].authority, authority)
            XCTAssertEqual(indicators[1].fraction ?? -1, 0.85, accuracy: 0.0001)
        }
    }
}

final class ClaudeProviderProtocolTests: XCTestCase {
    private func makeProvider(probe: ClaudeUsageProbing? = nil) throws -> ClaudeInteractiveProvider {
        ClaudeInteractiveProvider(
            client: try ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true")),
            usageProbe: probe,
            catalog: EmptyCatalog()
        )
    }

    private func envelope(_ text: String, turn: String = "turn-1") -> ClaudeCodeStreamEnvelope {
        ClaudeCodeStreamEnvelope(nativeSessionID: "s1", turnID: turn, message: json(text))
    }

    func testInitPublishesThreadWithActualModelAndCachesAgents() async throws {
        let provider = try makeProvider()
        let events = await provider.project(envelope(#"{"type":"system","subtype":"init","cwd":"/repo/app","model":"claude-haiku-4-5-20251001","agents":["b-agent","a-agent"]}"#))
        guard case .threadAvailable(let descriptor) = try XCTUnwrap(events.first) else { return XCTFail() }
        XCTAssertEqual(descriptor.nativeSessionID, "s1")
        XCTAssertEqual(descriptor.model, "claude-haiku-4-5-20251001")
        XCTAssertEqual(descriptor.cwd, "/repo/app")
        let agents = try await provider.listAgents()
        XCTAssertEqual(agents.map(\.name), ["a-agent", "b-agent"])
    }

    func testPermissionRequestIsOneShotAndBoundToExactSessionAndTurn() async throws {
        let provider = try makeProvider()
        let events = await provider.project(envelope(#"{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"rm -rf /tmp/x"},"tool_use_id":"tool-9"}}"#))
        guard case .approvalRequested(let request) = try XCTUnwrap(events.first) else { return XCTFail() }
        XCTAssertEqual(request.requestID, "req-1")
        XCTAssertEqual(request.threadID, "s1")
        XCTAssertEqual(request.turnID, "turn-1")
        XCTAssertEqual(request.itemID, "tool-9")
        XCTAssertEqual(request.kind, .command)
        XCTAssertFalse(request.summary.contains("rm"), "Command text is never shown in the summary")

        let foreign = AgentManagedApprovalRequest(
            requestToken: .string("req-1"), requestID: "req-1", kind: .command,
            threadID: "other-session", turnID: "turn-1", itemID: "tool-9", summary: "x"
        )
        do {
            try await provider.resolveApproval(foreign, allow: true)
            XCTFail("Cross-session approval must be refused")
        } catch {}
        // The client has no running process here, so the matching answer
        // fails at transport — but the request is consumed exactly once.
        do { try await provider.resolveApproval(request, allow: false) } catch {}
        do {
            try await provider.resolveApproval(request, allow: true)
            XCTFail("A request can only be answered once")
        } catch {}
    }

    func testSameRequestIDInTwoSessionsStaysBoundToEachExactSession() async throws {
        let provider = try makeProvider()
        let line = #"{"type":"control_request","request_id":"req-shared","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"a.txt"},"tool_use_id":"tool-1"}}"#
        let first = await provider.project(ClaudeCodeStreamEnvelope(nativeSessionID: "s1", turnID: "t1", message: json(line)))
        _ = await provider.project(ClaudeCodeStreamEnvelope(nativeSessionID: "s2", turnID: "t2", message: json(line)))
        guard case .approvalRequested(let request) = try XCTUnwrap(first.first) else { return XCTFail() }
        // s2's request must not overwrite s1's: answering s1 reaches the
        // transport (no process here) instead of being refused as unknown.
        do {
            try await provider.resolveApproval(request, allow: false)
            XCTFail("No process is running")
        } catch let error as ClaudeCodeStreamingError {
            XCTAssertEqual(error, .sessionNotRunning)
        }
    }

    func testControlCancelRequestWithdrawsExactPendingPermission() async throws {
        let provider = try makeProvider()
        let events = await provider.project(envelope(#"{"type":"control_request","request_id":"req-c","request":{"subtype":"can_use_tool","tool_name":"Write","input":{},"tool_use_id":"tool-c"}}"#))
        guard case .approvalRequested(let request) = try XCTUnwrap(events.first) else { return XCTFail() }
        let unknown = await provider.project(envelope(#"{"type":"control_cancel_request","request_id":"nope"}"#))
        XCTAssertTrue(unknown.isEmpty)
        let cancelled = await provider.project(envelope(#"{"type":"control_cancel_request","request_id":"req-c"}"#))
        XCTAssertEqual(cancelled, [.approvalCancelled(nativeSessionID: "s1", requestID: "req-c")])
        do {
            try await provider.resolveApproval(request, allow: true)
            XCTFail("A cancelled request can never be answered")
        } catch let error as ClaudeCodeStreamingError {
            XCTAssertEqual(error, .malformedMessage)
        }
    }

    func testToolResultForAnsweredPermissionIsTheExactAcknowledgement() async throws {
        let provider = try makeProvider()
        let events = await provider.project(envelope(#"{"type":"control_request","request_id":"req-ack","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{},"tool_use_id":"toolu_ack"}}"#))
        guard case .approvalRequested(let request) = try XCTUnwrap(events.first) else { return XCTFail() }
        // A tool_result before any answer is not an acknowledgement.
        let early = await provider.project(envelope(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ack","content":"x"}]}}"#))
        XCTAssertTrue(early.isEmpty)
        // Answering reaches the transport (no process here) but is recorded.
        do { try await provider.resolveApproval(request, allow: true) } catch {}
        let other = await provider.project(envelope(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_other","content":"x"}]}}"#))
        XCTAssertTrue(other.isEmpty)
        let ack = await provider.project(envelope(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ack","content":"done","is_error":false}]}}"#))
        XCTAssertEqual(ack, [.approvalAcknowledged(nativeSessionID: "s1", requestToken: .string("req-ack"))])
        let replay = await provider.project(envelope(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ack","content":"done"}]}}"#))
        XCTAssertTrue(replay.isEmpty, "acknowledged once")
    }

    func testRateLimitEventUpdatesAccountUsage() async throws {
        let provider = try makeProvider()
        let events = await provider.project(envelope(#"{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.25,"resetsAt":1},"seven_day":{"utilization":0.5,"resetsAt":2}}}}"#))
        XCTAssertEqual(events, [.accountUsageChanged])
        let usage = try await provider.readAccountUsage()
        let five = usage.samples(for: .quotaUsed).first { $0.scope == "5h" }
        XCTAssertEqual(five?.value ?? -1, 25, accuracy: 0.0001)
        XCTAssertEqual(five?.source, ClaudeUsageSource.rateLimitEvent)
    }

    func testUsageProbeRunsWhenStaleAndIsThrottled() async throws {
        let probe = FixedUsageProbe(ClaudeUsageProbeResult(
            windows: ClaudeUsageWindows(fiveHourUsedPercent: 10, weekUsedPercent: 20),
            availableAgents: ["general-purpose"],
            defaultModel: nil,
            cliVersion: "2.1.285"
        ))
        let provider = try makeProvider(probe: probe)
        let first = try await provider.readAccountUsage()
        _ = try await provider.readAccountUsage()
        XCTAssertEqual(probe.calls, 1, "Probe is throttled")
        XCTAssertEqual(first.samples(for: .quotaUsed).first { $0.scope == "weekly" }?.source, ClaudeUsageSource.usageCommand)
        let agents = try await provider.listAgents()
        XCTAssertEqual(agents.map(\.name), ["general-purpose"])
    }

    func testResultProjectsInterruptedAndAuthoritativeContextWindow() async throws {
        let provider = try makeProvider()
        _ = await provider.project(envelope(#"{"type":"assistant","parent_tool_use_id":null,"message":{"id":"m1","content":[],"usage":{"input_tokens":10,"cache_creation_input_tokens":18956,"cache_read_input_tokens":12413}}}"#))
        let completed = await provider.project(envelope(#"{"type":"result","subtype":"success","is_error":false,"modelUsage":{"claude-haiku-4-5":{"contextWindow":200000}}}"#))
        guard case .normalized(let usageEvent) = try XCTUnwrap(completed.first),
              case .usage(let usage) = usageEvent.payload else { return XCTFail("\(completed)") }
        XCTAssertEqual(usage[.contextUsed]?.value, 31379)
        XCTAssertEqual(usage[.contextUsed]?.limit, 200000)
        guard case .turnCompleted(_, .completed, _) = try XCTUnwrap(completed.last) else { return XCTFail() }

        let aborted = await provider.project(envelope(#"{"type":"result","subtype":"error_during_execution","is_error":true,"terminal_reason":"aborted_streaming"}"#))
        guard case .turnCompleted(_, .interrupted, _) = try XCTUnwrap(aborted.last) else { return XCTFail("\(aborted)") }
    }

    func testSubagentStreamingIsNotProjectedIntoMainTranscript() async throws {
        let provider = try makeProvider()
        _ = await provider.project(envelope(#"{"type":"stream_event","parent_tool_use_id":null,"event":{"type":"message_start","message":{"id":"m1"}}}"#))
        let sub = await provider.project(envelope(#"{"type":"stream_event","parent_tool_use_id":"tool-1","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"sub"}}}"#))
        XCTAssertTrue(sub.isEmpty)
    }

    func testModelAndAgentValidationAndNoInPlaceModelChange() async throws {
        let provider = try makeProvider()
        do {
            _ = try await provider.startSession(cwd: "/p", model: "gpt-5", agent: nil)
            XCTFail("Unknown model must be rejected")
        } catch {}
        let session = try await provider.startSession(cwd: "/p", model: "sonnet", agent: nil)
        XCTAssertNotNil(UUID(uuidString: session.nativeSessionID), "New sessions get an exact UUID")
        XCTAssertEqual(session.cwd, "/p")
        do {
            _ = try await provider.submit(prompt: "hi", nativeSessionID: session.nativeSessionID, model: "opus")
            XCTFail("Model cannot change inside a session")
        } catch let error as ClaudeCodeStreamingError {
            XCTAssertEqual(error, .unsupported)
        }
        let models = try await provider.listModels()
        XCTAssertEqual(models.map(\.model), ["fable", "opus", "sonnet", "haiku"])
    }
}

final class ClaudeSessionCatalogTests: XCTestCase {
    func testRecentSessionsAreSortedBoundedAndReadCwd() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeCatalog-\(UUID().uuidString)")
        let project = root.appendingPathComponent("-Users-me-repo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let older = UUID().uuidString.lowercased()
        let newer = UUID().uuidString.lowercased()
        try Data(#"{"type":"user","cwd":"/Users/me/repo"}"#.utf8).write(to: project.appendingPathComponent("\(older).jsonl"))
        try Data(#"{"type":"user","cwd":"/Users/me/repo/app"}"#.utf8).write(to: project.appendingPathComponent("\(newer).jsonl"))
        try Data("x".utf8).write(to: project.appendingPathComponent("not-a-session.jsonl"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: project.appendingPathComponent("\(older).jsonl").path)

        let catalog = ClaudeSessionCatalog(root: root)
        let recent = try catalog.recentSessions(limit: 5)
        XCTAssertEqual(recent.map(\.nativeSessionID), [newer, older])
        XCTAssertEqual(recent.first?.cwd, "/Users/me/repo/app")
        XCTAssertEqual(try catalog.session(nativeSessionID: older)?.cwd, "/Users/me/repo")
        XCTAssertNil(try catalog.session(nativeSessionID: "../../etc/passwd"))
        XCTAssertEqual(try catalog.recentSessions(limit: 1).count, 1)
    }
}

/// End-to-end process transport against a fake `claude` script: verifies
/// arguments, working directory, stdin turns, stdout parsing and exit.
final class ClaudeStreamingClientProcessTests: XCTestCase {
    func testFakeCLIRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FakeClaude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("claude")
        let argsFile = directory.appendingPathComponent("args.txt")
        try """
            #!/bin/sh
            echo "$@" > "\(argsFile.path)"
            pwd >> "\(argsFile.path)"
            read line
            echo '{"type":"system","subtype":"init","model":"fake-model","cwd":"'$(pwd)'"}'
            echo '{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"Hello from fake"}]}}'
            echo '{"type":"result","subtype":"success","is_error":false}'
            """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let client = try ClaudeCodeStreamingClient(executableURL: script)
        let events = await client.events()
        let spec = ClaudeLaunchSpec(nativeSessionID: "sess-1", mode: .new, cwd: directory.path, model: "haiku", agent: nil)
        let turn = try await client.submit(prompt: "hi", spec: spec)

        var received: [ClaudeCodeStreamEvent] = []
        for await event in events {
            received.append(event)
            if case .sessionExited = event { break }
            if received.count > 10 { break }
        }
        let types = received.compactMap { event -> String? in
            if case .message(let envelope) = event { return envelope.message["type"]?.stringValue }
            return nil
        }
        XCTAssertEqual(types, ["system", "assistant", "result"])
        if case .message(let first) = received[0] { XCTAssertEqual(first.turnID, turn.turnID) }
        let args = try String(contentsOf: argsFile, encoding: .utf8)
        XCTAssertTrue(args.contains("--session-id sess-1"))
        XCTAssertTrue(args.contains("--model haiku"))
        XCTAssertTrue(args.contains(directory.lastPathComponent), "Process runs in the selected folder")
    }
}
