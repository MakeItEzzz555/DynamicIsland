import XCTest
@testable import DynamicIsland

final class CodexRolloutSessionMonitorTests: XCTestCase {
    func testRecentRolloutDiscoveryUsesFiveMinuteWindowNewestFirst() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("DynamicIsland-CodexDiscovery-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("2026/09/28", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let newest = nested.appendingPathComponent("rollout-newest.jsonl")
        let recent = nested.appendingPathComponent("rollout-recent.jsonl")
        let stale = nested.appendingPathComponent("rollout-stale.jsonl")
        let unrelated = nested.appendingPathComponent("notes.jsonl")
        for url in [newest, recent, stale, unrelated] {
            try Data("{}\n".utf8).write(to: url)
        }
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-5)], ofItemAtPath: newest.path)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-120)], ofItemAtPath: recent.path)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-301)], ofItemAtPath: stale.path)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: unrelated.path)

        let result = CodexRolloutSessionDiscovery.recentRollouts(
            in: root,
            now: now,
            recentWindow: 300,
            limit: 32,
            fileManager: fm
        )

        XCTAssertEqual(result.map { $0.lastPathComponent }, [
            "rollout-newest.jsonl",
            "rollout-recent.jsonl"
        ])
    }


    func testRecentRolloutCandidatesRetainModificationFreshness() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("DynamicIsland-CodexFreshness-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let file = root.appendingPathComponent("rollout-live.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let modified = now.addingTimeInterval(-7)
        try fm.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)

        let candidate = try XCTUnwrap(
            CodexRolloutSessionDiscovery.recentRolloutCandidates(
                in: root,
                now: now,
                recentWindow: 300,
                fileManager: fm
            ).first
        )

        XCTAssertEqual(
            candidate.url.standardizedFileURL.path,
            file.standardizedFileURL.path
        )
        XCTAssertEqual(candidate.modifiedAt.timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor
    func testMonitorIngestsRecentVSCodeRolloutAsObservedExactSession() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("DynamicIsland-CodexMonitor-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("2026/09/28", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let file = nested.appendingPathComponent("rollout-live.jsonl")
        let records = [
            #"{"type":"session_meta","payload":{"id":"vscode-live","cwd":"/tmp/DynamicIsland","source":"vscode","originator":"codex_vscode"}}"#,
            #"{"type":"event_msg","payload":{"type":"turn_started","turn_id":"turn-live"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"swift test\"}","call_id":"call-live","internal_chat_message_metadata_passthrough":{"turn_id":"turn-live"}}}"#
        ]
        try Data((records.joined(separator: "\n") + "\n").utf8).write(to: file)

        let store = AgentEventStore()
        let coordinator = AgentIngestionCoordinator(eventStore: store)
        let monitor = CodexRolloutSessionMonitor(
            coordinator: coordinator,
            sessionsDirectory: root,
            scanInterval: .seconds(60),
            recentWindow: 300
        )
        await monitor.start()
        defer { Task { await monitor.stop() } }

        for _ in 0..<100 {
            if store.sessions.first?.commands[AgentCorrelationID(rawValue: "call-live")] != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let session = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(session.id.sessionID.nativeID, "vscode-live")
        XCTAssertEqual(session.source, .vscode)
        XCTAssertEqual(session.project.sourceApplication?.displayName, "Visual Studio Code")
        XCTAssertEqual(session.state, .runningCommand)
        XCTAssertNotNil(session.commands[AgentCorrelationID(rawValue: "call-live")])
        let watched = await monitor.watchedURLs()
        XCTAssertEqual(watched.count, 1)

        await monitor.stop()
    }

    @MainActor
    func testMonitorFileAppendRefreshesSessionLivenessEvenForUnsupportedRecord() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("DynamicIsland-CodexAppendFreshness-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let file = root.appendingPathComponent("rollout-live.jsonl")
        let records = [
            #"{"type":"session_meta","payload":{"id":"vscode-freshness","cwd":"/tmp/DynamicIsland","source":"vscode","originator":"codex_vscode"}}"#,
            #"{"type":"event_msg","payload":{"type":"turn_started","turn_id":"turn-live"}}"#
        ]
        try Data((records.joined(separator: "\n") + "\n").utf8).write(to: file)

        let store = AgentEventStore()
        let coordinator = AgentIngestionCoordinator(eventStore: store)
        let monitor = CodexRolloutSessionMonitor(
            coordinator: coordinator,
            sessionsDirectory: root,
            scanInterval: .seconds(60),
            recentWindow: 300
        )
        await monitor.start()
        defer { Task { await monitor.stop() } }

        for _ in 0..<100 where store.sessions.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let before = try XCTUnwrap(store.sessions.first?.lastUpdatedAt)

        let observedAt = before.addingTimeInterval(20)
        let unsupported = #"{"type":"response_item","payload":{"type":"reasoning","text":"not ingested"}}"# + "\n"
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(unsupported.utf8))
        try handle.close()
        try fm.setAttributes([.modificationDate: observedAt], ofItemAtPath: file.path)

        await monitor.scanNow(now: observedAt)

        let refreshed = try XCTUnwrap(store.sessions.first)
        let after = refreshed.lastUpdatedAt
        XCTAssertGreaterThan(after, before)
        XCTAssertEqual(after.timeIntervalSince1970, observedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(refreshed.activityEvidenceAt).timeIntervalSince1970,
            observedAt.timeIntervalSince1970,
            accuracy: 0.001
        )

        await monitor.stop()
    }

}
