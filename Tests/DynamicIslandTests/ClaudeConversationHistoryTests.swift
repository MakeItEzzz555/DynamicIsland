import Foundation
import XCTest
@testable import DynamicIsland

/// Resumed Claude sessions hydrate their visible conversation from Claude
/// Code's own transcript; only user/assistant text is ever projected.
final class ClaudeConversationHistoryTests: XCTestCase {
    private let session = "4247a939-b86e-4da6-bf79-b9dcc7b70484"

    private func line(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private var fixture: Data {
        let lines = [
            line(["type": "queue-operation", "operation": "enqueue"]),
            line(["type": "user", "uuid": "u1", "timestamp": "2026-10-01T09:32:26.466Z",
                  "message": ["role": "user", "content": "Create hello.txt please"]]),
            line(["type": "assistant", "uuid": "a1", "timestamp": "2026-10-01T09:32:28.159Z",
                  "message": ["id": "msg_1", "content": [["type": "thinking", "thinking": "secret reasoning"]]]]),
            line(["type": "assistant", "uuid": "a2", "timestamp": "2026-10-01T09:32:28.629Z",
                  "message": ["id": "msg_1", "content": [["type": "tool_use", "name": "Bash", "input": ["command": "echo TOKEN=abc"]]]]]),
            line(["type": "user", "uuid": "u2", "timestamp": "2026-10-01T09:32:28.687Z",
                  "message": ["role": "user", "content": [["type": "tool_result", "content": "TOKEN=abc"]]]]),
            line(["type": "user", "uuid": "u3", "isMeta": true, "timestamp": "2026-10-01T09:32:29.000Z",
                  "message": ["role": "user", "content": "Caveat: meta"]]),
            line(["type": "user", "uuid": "u4", "timestamp": "2026-10-01T09:32:29.100Z",
                  "message": ["role": "user", "content": "<command-name>/clear</command-name>"]]),
            line(["type": "assistant", "uuid": "a3", "timestamp": "2026-10-01T09:32:30.979Z",
                  "message": ["id": "msg_2", "content": [["type": "text", "text": "Created hello.txt."]]]]),
            line(["type": "assistant", "uuid": "a4", "isSidechain": true, "timestamp": "2026-10-01T09:32:31.000Z",
                  "message": ["id": "msg_side", "content": [["type": "text", "text": "subagent chatter"]]]]),
            line(["type": "user", "uuid": "u5", "timestamp": "2026-10-01T09:33:00.000Z",
                  "message": ["role": "user", "content": [["type": "text", "text": "Thanks"], ["type": "image", "source": [:]]]]])
        ]
        return Data(lines.joined(separator: "\n").utf8)
    }

    func testProjectsOnlyConversationTextInOrder() {
        let entries = ClaudeConversationHistory.entries(from: fixture, nativeSessionID: session, limit: 50)
        XCTAssertEqual(entries.map(\.role), [.user, .agent, .user])
        XCTAssertEqual(entries.map(\.text), ["Create hello.txt please", "Created hello.txt.", "Thanks"])
        XCTAssertTrue(entries.allSatisfy { $0.nativeSessionID == session })
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "stable unique ids")
        let rendered = entries.map(\.text).joined()
        XCTAssertFalse(rendered.contains("TOKEN"), "tool input/output never projected")
        XCTAssertFalse(rendered.contains("secret"), "thinking never projected")
        XCTAssertFalse(rendered.contains("command-name"), "slash-command plumbing skipped")
        XCTAssertFalse(rendered.contains("subagent"), "sidechains skipped")
        XCTAssertEqual(entries.first?.timestamp, ISO8601DateFormatter.withFractionalSeconds.date(from: "2026-10-01T09:32:26.466Z"))
    }

    func testLimitKeepsTheMostRecentEntries() {
        let entries = ClaudeConversationHistory.entries(from: fixture, nativeSessionID: session, limit: 2)
        XCTAssertEqual(entries.map(\.text), ["Created hello.txt.", "Thanks"])
    }

    func testTailReadDropsAPartialFirstLineAndToleratesGarbage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("\(session).jsonl")
        var data = Data(String(repeating: "x", count: 5_000).utf8) // a huge older line
        data.append(Data("\nnot json\n".utf8))
        data.append(fixture)
        try data.write(to: file)
        let entries = try ClaudeConversationHistory.read(file: file, nativeSessionID: session, limit: 10, maximumBytes: 2_048)
        XCTAssertEqual(entries.last?.text, "Thanks")
        XCTAssertFalse(entries.contains { $0.text.hasPrefix("x") })
    }

    func testProviderDeclaresAndServesHistoryFromTheCatalogRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-root-\(UUID().uuidString)")
        let project = root.appendingPathComponent("-tmp-project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try fixture.write(to: project.appendingPathComponent("\(session).jsonl"))
        let provider = ClaudeInteractiveProvider(
            client: try ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/bin/echo")),
            catalog: ClaudeSessionCatalog(root: root))
        XCTAssertTrue(provider.interactiveCapabilities.contains(.loadHistory))
        let entries = try await provider.readTranscript(nativeSessionID: session, limit: 80)
        XCTAssertEqual(entries.map(\.text), ["Create hello.txt please", "Created hello.txt.", "Thanks"])
        let missing = try await provider.readTranscript(nativeSessionID: UUID().uuidString.lowercased(), limit: 80)
        XCTAssertTrue(missing.isEmpty, "unknown sessions hydrate nothing, never fail")
    }
}
