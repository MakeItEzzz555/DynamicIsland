import Foundation
import XCTest
@testable import CodexHookShared

final class CodexHookNormalizerTests: XCTestCase {
    func testSessionStartProducesLifecycleAndCapabilityEvents() throws {
        let input = Data("""
        {"session_id":"session-1","transcript_path":"/tmp/t.jsonl","cwd":"/tmp/project","hook_event_name":"SessionStart","model":"gpt-5.6-sol","permission_mode":"default","source":"startup"}
        """.utf8)
        let output = try CodexHookNormalizer.normalize(input, now: Date(timeIntervalSince1970: 1_800_000_000))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: output) as? [String: Any])
        let events = try XCTUnwrap(root["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0]["provider"] as? String, "codex")
        XCTAssertEqual(events[0]["eventType"] as? String, "sessionStarted")
        XCTAssertEqual(events[0]["continuityIdentity"] as? String, "session-1")
        XCTAssertEqual(events[1]["eventType"] as? String, "capabilitiesUpdated")
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("transcript_path"))
    }

    func testResumeSessionStartCreatesLocalSessionIncarnation() throws {
        let input = Data("""
        {"session_id":"session-1","transcript_path":null,"cwd":"/tmp/project","hook_event_name":"SessionStart","model":"gpt-5.6-sol","permission_mode":"default","source":"resume"}
        """.utf8)
        let output = try CodexHookNormalizer.normalize(input)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: output) as? [String: Any])
        let events = try XCTUnwrap(root["events"] as? [[String: Any]])
        XCTAssertEqual(events[0]["eventType"] as? String, "sessionStarted")
    }

    func testPromptContentIsNeverForwarded() throws {
        let input = Data("""
        {"session_id":"session-1","turn_id":"turn-1","transcript_path":null,"cwd":"/tmp/project","hook_event_name":"UserPromptSubmit","model":"gpt-5.6-sol","permission_mode":"default","prompt":"SUPER-SECRET-PROMPT"}
        """.utf8)
        let output = try CodexHookNormalizer.normalize(input)
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("SUPER-SECRET-PROMPT"))
    }

    func testBashMapsToCommandLifecycleWithoutArguments() throws {
        let input = Data("""
        {"session_id":"session-1","turn_id":"turn-1","transcript_path":null,"cwd":"/tmp/project","hook_event_name":"PreToolUse","model":"gpt-5.6-sol","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"echo hidden-value"},"tool_use_id":"tool-1"}
        """.utf8)
        let output = try CodexHookNormalizer.normalize(input)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: output) as? [String: Any])
        let event = try XCTUnwrap(root["event"] as? [String: Any])
        XCTAssertEqual(event["eventType"] as? String, "commandStarted")
        XCTAssertEqual(event["correlationID"] as? String, "tool-1")
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("hidden-value"))
    }

    func testPermissionRequestCarriesControlCapabilityWithoutLeakingSecretCommand() throws {
        let input = Data("""
        {"session_id":"session-1","turn_id":"turn-1","transcript_path":null,"cwd":"/tmp/project","hook_event_name":"PermissionRequest","model":"gpt-5.6-sol","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"echo api_token=hidden-value"}}
        """.utf8)
        let output = try CodexHookNormalizer.normalize(input)
        let text = String(decoding: output, as: UTF8.self)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: output) as? [String: Any])
        let events = try XCTUnwrap(root["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        let capability = try XCTUnwrap(events.first)
        XCTAssertEqual(capability["eventType"] as? String, "capabilitiesUpdated")
        let event = try XCTUnwrap(events.last)
        let payload = try XCTUnwrap(event["payload"] as? [String: Any])
        let request = try XCTUnwrap(payload["approvalRequest"] as? [String: Any])
        XCTAssertTrue(text.contains("approvalRequested"))
        XCTAssertEqual(request["operationCorrelationID"] as? String, "operation-bash")
        XCTAssertTrue(text.contains("approvalControl"))
        XCTAssertFalse(text.contains("hidden-value"))
        XCTAssertEqual(request["summary"] as? String, "Bash approval required")
        XCTAssertNotNil(request["expiresAt"] as? Double)
    }

    func testPermissionRequestUsesSafeDescriptionThenSanitizedCommandPreview() throws {
        let described = Data("""
        {"session_id":"session-1","turn_id":"turn-1","cwd":"/tmp/project","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git push origin feature/agents-ui-overhaul","description":"Push the current feature branch"}}
        """.utf8)
        XCTAssertEqual(try permissionSummary(described), "Push the current feature branch")

        let command = Data("""
        {"session_id":"session-1","turn_id":"turn-2","cwd":"/tmp/project","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git push origin feature/agents-ui-overhaul"}}
        """.utf8)
        XCTAssertEqual(try permissionSummary(command), "$ git push origin feature/agents-ui-overhaul")
    }

    func testOfficialPermissionDecisionOutputIsBoundedToAllowOrDeny() throws {
        let allow = try XCTUnwrap(CodexPermissionHookOutput.encode(.allow))
        let deny = try XCTUnwrap(CodexPermissionHookOutput.encode(.deny))
        XCTAssertTrue(String(decoding: allow, as: UTF8.self).contains("allow"))
        XCTAssertTrue(String(decoding: deny, as: UTF8.self).contains("Denied in DynamicIsland"))
    }

    func testStopAndInterruptMapToTerminalEventsWithoutAssistantText() throws {
        let stop = Data("""
        {"session_id":"session-1","turn_id":"turn-1","transcript_path":null,"cwd":"/tmp/project","hook_event_name":"Stop","model":"gpt-5.6-sol","permission_mode":"default","stop_hook_active":false,"last_assistant_message":"private answer"}
        """.utf8)
        let stopOutput = try CodexHookNormalizer.normalize(stop)
        XCTAssertTrue(String(decoding: stopOutput, as: UTF8.self).contains("taskCompleted"))
        XCTAssertFalse(String(decoding: stopOutput, as: UTF8.self).contains("private answer"))

        let interrupt = Data("""
        {"session_id":"session-1","turn_id":"turn-1","transcript_path":null,"cwd":"/tmp/project","hook_event_name":"Interrupt","model":"gpt-5.6-sol","permission_mode":"default"}
        """.utf8)
        let interruptOutput = try CodexHookNormalizer.normalize(interrupt)
        XCTAssertTrue(String(decoding: interruptOutput, as: UTF8.self).contains("interrupted"))
    }

    func testSubagentLifecycleUsesStableAgentIdentifier() throws {
        let input = Data("""
        {"session_id":"session-1","turn_id":"turn-1","transcript_path":null,"cwd":"/tmp/project","hook_event_name":"SubagentStart","model":"gpt-5.6-sol","permission_mode":"default","agent_id":"agent-7","agent_type":"reviewer"}
        """.utf8)
        let output = try CodexHookNormalizer.normalize(input)
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(text.contains("subagentStarted"))
        XCTAssertTrue(text.contains("agent-7"))
        XCTAssertTrue(text.contains("reviewer"))
    }

    func testCompactHooksAreNotPartOfA3Contract() {
        let input = Data("""
        {"session_id":"session-1","turn_id":"turn-1","transcript_path":null,"cwd":"/tmp/project","hook_event_name":"PreCompact","model":"gpt-5.6-sol","trigger":"auto"}
        """.utf8)
        XCTAssertThrowsError(try CodexHookNormalizer.normalize(input)) { error in
            XCTAssertEqual(error as? CodexHookNormalizationError, .unsupportedHook)
        }
    }

    func testInputBoundIsEnforced() {
        let data = Data(repeating: 0x20, count: CodexHookNormalizer.maximumInputBytes + 1)
        XCTAssertThrowsError(try CodexHookNormalizer.normalize(data)) { error in
            XCTAssertEqual(error as? CodexHookNormalizationError, .inputTooLarge)
        }
    }

    private func permissionSummary(_ input: Data) throws -> String? {
        let output = try CodexHookNormalizer.normalize(input)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let events = try XCTUnwrap(root["events"] as? [[String: Any]])
        let payload = try XCTUnwrap(events.last?["payload"] as? [String: Any])
        let request = try XCTUnwrap(payload["approvalRequest"] as? [String: Any])
        return request["summary"] as? String
    }
}
