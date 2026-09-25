import Foundation
import XCTest
@testable import ClaudeHookShared

final class ClaudeHookNormalizerTests: XCTestCase {
    func testSessionStartProducesLifecycleAndObservedCapabilities() throws {
        let input = Data("""
        {"session_id":"claude-1","transcript_path":"/tmp/private.jsonl","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"SessionStart","source":"startup","model":"claude-opus"}
        """.utf8)
        let output = try ClaudeHookNormalizer.normalize(input, now: Date(timeIntervalSince1970: 1_800_000_000))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: output) as? [String: Any])
        let events = try XCTUnwrap(root["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0]["provider"] as? String, "claude")
        XCTAssertEqual(events[0]["eventType"] as? String, "sessionStarted")
        XCTAssertEqual(events[0]["continuityIdentity"] as? String, "claude-1")
        XCTAssertEqual(events[1]["eventType"] as? String, "capabilitiesUpdated")
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("private.jsonl"))
    }

    func testUserPromptContentIsNotForwarded() throws {
        let input = Data("""
        {"session_id":"claude-1","prompt_id":"prompt-1","transcript_path":null,"cwd":"/tmp/project","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"TOP SECRET"}
        """.utf8)
        let output = try ClaudeHookNormalizer.normalize(input)
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(text.contains("sessionResumed"))
        XCTAssertTrue(text.contains("agentWorking"))
        XCTAssertFalse(text.contains("TOP SECRET"))
    }

    func testToolLifecycleDropsInputsAndResults() throws {
        let start = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/private/secret"},"tool_use_id":"tool-1"}
        """.utf8)
        let end = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/private/secret"},"tool_response":{"content":"PRIVATE"},"tool_use_id":"tool-1"}
        """.utf8)
        let startOutput = try ClaudeHookNormalizer.normalize(start)
        let endOutput = try ClaudeHookNormalizer.normalize(end)
        XCTAssertTrue(String(decoding: startOutput, as: UTF8.self).contains("toolStarted"))
        XCTAssertTrue(String(decoding: endOutput, as: UTF8.self).contains("toolCompleted"))
        XCTAssertFalse(String(decoding: startOutput, as: UTF8.self).contains("/private/secret"))
        XCTAssertFalse(String(decoding: endOutput, as: UTF8.self).contains("PRIVATE"))
    }

    func testPostToolFailureIsSafeCompletion() throws {
        let input = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"secret command"},"tool_use_id":"tool-1","error":"PRIVATE FAILURE","is_interrupt":false}
        """.utf8)
        let output = try ClaudeHookNormalizer.normalize(input)
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(text.contains("commandCompleted"))
        XCTAssertTrue(text.contains("\"success\":false"))
        XCTAssertFalse(text.contains("secret command"))
        XCTAssertFalse(text.contains("PRIVATE FAILURE"))
    }

    func testPermissionRequestIsObservationOnly() throws {
        let input = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"secret command"},"permission_suggestions":[]}
        """.utf8)
        let output = try ClaudeHookNormalizer.normalize(input)
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(text.contains("approvalRequested"))
        XCTAssertFalse(text.contains("approvalControl"))
        XCTAssertFalse(text.contains("secret command"))
    }

    func testStopCompletesOnlyWithoutBackgroundWork() throws {
        let complete = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"PRIVATE","background_tasks":[],"session_crons":[]}
        """.utf8)
        let completeOutput = try ClaudeHookNormalizer.normalize(complete)
        XCTAssertTrue(String(decoding: completeOutput, as: UTF8.self).contains("taskCompleted"))
        XCTAssertFalse(String(decoding: completeOutput, as: UTF8.self).contains("PRIVATE"))

        let background = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"PRIVATE","background_tasks":[{"id":"bg"}],"session_crons":[]}
        """.utf8)
        let backgroundOutput = try ClaudeHookNormalizer.normalize(background)
        XCTAssertTrue(String(decoding: backgroundOutput, as: UTF8.self).contains("agentWorking"))
        XCTAssertFalse(String(decoding: backgroundOutput, as: UTF8.self).contains("taskCompleted"))
    }

    func testStopFailureKeepsOnlyBoundedErrorCategory() throws {
        let input = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"StopFailure","error":"rate_limit","error_details":"PRIVATE ERROR DETAILS","last_assistant_message":"PRIVATE"}
        """.utf8)
        let output = try ClaudeHookNormalizer.normalize(input)
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(text.contains("taskFailed"))
        XCTAssertTrue(text.contains("rate_limit"))
        XCTAssertFalse(text.contains("PRIVATE ERROR DETAILS"))
    }

    func testElicitationLifecycleCorrelatesWithoutResponseContent() throws {
        let request = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"Elicitation","elicitation_id":"ask-1","message":"PRIVATE QUESTION"}
        """.utf8)
        let result = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/project","permission_mode":"default","hook_event_name":"ElicitationResult","elicitation_id":"ask-1","result":"PRIVATE ANSWER"}
        """.utf8)
        let requestOutput = try ClaudeHookNormalizer.normalize(request)
        let resultOutput = try ClaudeHookNormalizer.normalize(result)
        XCTAssertTrue(String(decoding: requestOutput, as: UTF8.self).contains("waitingForUser"))
        XCTAssertTrue(String(decoding: resultOutput, as: UTF8.self).contains("userInputResolved"))
        XCTAssertFalse(String(decoding: requestOutput, as: UTF8.self).contains("PRIVATE QUESTION"))
        XCTAssertFalse(String(decoding: resultOutput, as: UTF8.self).contains("PRIVATE ANSWER"))
    }

    func testCwdChangedEmitsOnlySafeProjectContext() throws {
        let input = Data("""
        {"session_id":"claude-1","prompt_id":"p1","cwd":"/tmp/old","permission_mode":"default","hook_event_name":"CwdChanged","old_cwd":"/tmp/old","new_cwd":"/tmp/new-project"}
        """.utf8)
        let output = try ClaudeHookNormalizer.normalize(input)
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(text.contains("projectContextUpdated"))
        XCTAssertTrue(text.contains("new-project"))
    }

    func testInputBoundIsEnforced() {
        let data = Data(repeating: 0x20, count: ClaudeHookNormalizer.maximumInputBytes + 1)
        XCTAssertThrowsError(try ClaudeHookNormalizer.normalize(data)) { error in
            XCTAssertEqual(error as? ClaudeHookNormalizationError, .inputTooLarge)
        }
    }
}
