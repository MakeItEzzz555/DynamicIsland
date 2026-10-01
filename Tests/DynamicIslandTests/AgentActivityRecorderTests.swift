import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentActivityRecorderTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentActivity-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRecordingIsOffByDefaultInSettingsAndRecordsNothing() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AgentActivity-\(UUID().uuidString)"))
        XCTAssertFalse(AppSettings(defaults: defaults).agentActivityRecordingEnabled, "explicit opt-in")

        let (store, recorder, log) = makeRecorder()
        XCTAssertFalse(recorder.isRecording)
        ingestSampleActivity(into: store)
        recorder.flushForTermination()
        XCTAssertTrue(log.readAll().isEmpty)
        XCTAssertEqual(log.summary().fileCount, 0)
    }

    func testOptInPersistsNormalizedActivityAsJSONLines() throws {
        let (store, recorder, log) = makeRecorder()
        recorder.setRecording(true)
        ingestSampleActivity(into: store)
        recorder.setRecording(false) // stopping flushes
        log.appendSynchronously([])

        let records = log.readAll()
        XCTAssertEqual(records.map(\.event), [
            "sessionStarted", "agentWorking", "toolStarted", "commandCompleted",
            "approvalRequested", "approvalResolved", "usageUpdated", "planUpdated", "taskCompleted"
        ])
        XCTAssertTrue(records.allSatisfy { $0.provider == "codex" && $0.session == "thread-7" && $0.generation == 1 })
        XCTAssertEqual(records.first { $0.event == "toolStarted" }?.tool, "Bash")
        let command = try XCTUnwrap(records.first { $0.event == "commandCompleted" })
        XCTAssertEqual(command.executable, "git")
        XCTAssertEqual(command.exitCode, 1)
        XCTAssertEqual(command.success, false)
        XCTAssertEqual(records.first { $0.event == "approvalResolved" }?.approval, "denied")
        XCTAssertEqual(records.first { $0.event == "sessionStarted" }?.project, "storefront")
        let usage = try XCTUnwrap(records.first { $0.event == "usageUpdated" }?.usage?.first)
        XCTAssertEqual(usage.value, 42)
        XCTAssertEqual(usage.limit, 100)
        XCTAssertEqual(records.last?.state, AgentState.completed.rawValue)
    }

    func testSensitiveFieldsAreNeverWritten() throws {
        let (store, recorder, log) = makeRecorder()
        recorder.setRecording(true)
        ingestSampleActivity(into: store)
        recorder.flushForTermination()

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let raw = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        XCTAssertFalse(raw.isEmpty)
        for secret in [
            "sk-live-SECRET", "Authorization", "rm -rf", "--token", "/usr/bin", "/Users/someone",
            "PROMPT-TEXT", "PLAN-TEXT", "SUMMARY-TEXT", "TERMINAL-TEXT", "APPROVAL-TEXT"
        ] {
            XCTAssertFalse(raw.contains(secret), "\(secret) leaked into the activity log")
        }
    }

    func testFilesAndDirectoryArePrivateToTheUser() throws {
        let (store, recorder, log) = makeRecorder()
        recorder.setRecording(true)
        ingestSampleActivity(into: store)
        recorder.flushForTermination()
        let directoryMode = try FileManager.default.attributesOfItem(atPath: log.directory.path)[.posixPermissions] as? Int
        XCTAssertEqual(directoryMode, 0o700)
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
            XCTAssertEqual(mode, 0o600, file.lastPathComponent)
        }
    }

    func testRetentionIsBoundedByFileSizeTotalSizeAndAge() throws {
        final class Clock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 1_790_000_000) }
        let clock = Clock()
        let retention = AgentActivityRetention(maximumAge: 2 * 24 * 60 * 60, maximumTotalBytes: 4_000, maximumFileBytes: 1_000)
        let log = AgentActivityLog(directory: directory, retention: retention, now: { clock.date })
        let record = AgentActivityRecord(
            occurredAt: clock.date, provider: "codex", session: "s", generation: 1,
            event: "agentWorking", state: "working", source: "terminal", correlation: nil
        )
        for _ in 0..<200 { log.appendSynchronously([record]) }
        var summary = log.summary()
        XCTAssertLessThanOrEqual(summary.totalBytes, 4_000 + 1_000, "total size is bounded")
        XCTAssertGreaterThan(summary.fileCount, 1, "files roll at the per-file cap")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        for file in files {
            XCTAssertLessThanOrEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 1_000)
        }

        // Age out: everything older than the window is removed on the next write.
        for file in files {
            try FileManager.default.setAttributes([.modificationDate: clock.date.addingTimeInterval(-3 * 24 * 60 * 60)], ofItemAtPath: file.path)
        }
        clock.date = clock.date.addingTimeInterval(60)
        log.appendSynchronously([record])
        summary = log.summary()
        XCTAssertEqual(summary.fileCount, 1, "only the new file survives")
    }

    func testClearRemovesRecordedActivity() throws {
        let (store, recorder, log) = makeRecorder()
        recorder.setRecording(true)
        ingestSampleActivity(into: store)
        recorder.flushForTermination()
        XCTAssertGreaterThan(log.summary().fileCount, 0)
        let cleared = expectation(description: "cleared")
        log.clear { cleared.fulfill() }
        wait(for: [cleared], timeout: 2)
        XCTAssertEqual(log.summary().fileCount, 0)
        XCTAssertTrue(log.readAll().isEmpty)
    }

    func testProjectionKeepsOnlyLeadingIdentifiers() {
        XCTAssertEqual(AgentActivityRecordProjection.identifier("Bash(rm -rf /)"), "Bash")
        XCTAssertEqual(AgentActivityRecordProjection.identifier("mcp__github__create_issue"), "mcp__github__create_issue")
        XCTAssertNil(AgentActivityRecordProjection.identifier(" leading-space"))
        XCTAssertEqual(AgentActivityRecordProjection.projectName("/Users/someone/code/storefront"), "storefront")
        XCTAssertNil(AgentActivityRecordProjection.projectName("/"))
    }

    // MARK: Fixtures

    private func makeRecorder() -> (AgentEventStore, AgentActivityRecorder, AgentActivityLog) {
        let store = AgentEventStore()
        let log = AgentActivityLog(directory: directory)
        let recorder = AgentActivityRecorder(log: log)
        store.appliedEventObserver = { [weak recorder] event, session in
            recorder?.handleApplied(event, session: session)
        }
        return (store, recorder, log)
    }

    private func ingestSampleActivity(into store: AgentEventStore) {
        var offset: TimeInterval = 0
        func ingest(_ type: AgentEventType, _ payload: AgentEventPayload = .none, correlation: String? = nil) {
            offset += 1
            let application = store.ingest(AgentEvent(
                eventID: AgentEventID(rawValue: "e-\(offset)"),
                sessionID: AgentSessionID(provider: .codex, nativeID: "thread-7"),
                generation: AgentSessionGeneration(rawValue: 1),
                source: .terminal,
                type: type,
                receivedTimestamp: Date(timeIntervalSince1970: 1_790_000_000 + offset),
                correlationID: correlation.map(AgentCorrelationID.init(rawValue:)),
                payload: payload
            ))
            XCTAssertEqual(application, .applied, "\(type)")
        }
        ingest(.sessionStarted, .sessionMetadata(AgentSessionMetadata(project: AgentProjectContext(
            displayName: "storefront",
            workingDirectory: "/Users/someone/code/storefront",
            model: "gpt-5.6"
        ))))
        ingest(.agentWorking, .activity(AgentActivityDescriptor(title: "Working", summary: "SUMMARY-TEXT sk-live-SECRET")))
        ingest(.toolStarted, .tool(AgentToolEvent(name: "Bash(rm -rf /tmp/x --token abc)", category: nil, summary: "PROMPT-TEXT", success: nil)), correlation: "tool-1")
        ingest(.commandCompleted, .command(AgentCommandEvent(executable: "/usr/bin/git push --token=sk-live-SECRET", success: false, exitCode: 1)), correlation: "cmd-1")
        ingest(.approvalRequested, .approvalRequest(AgentApprovalRequest(summary: "APPROVAL-TEXT Authorization: Bearer sk-live-SECRET", operationCorrelationID: nil, expiresAt: nil)), correlation: "req-1")
        ingest(.approvalResolved, .approvalResolution(AgentApprovalResolution(state: .denied)), correlation: "req-1")
        ingest(.usageUpdated, .usage(AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                value: 42, limit: 100, unit: .fraction, scope: "5h", source: "codex", observedAt: Date(timeIntervalSince1970: 1_790_000_000)
            )
        ])))
        ingest(.planUpdated, .plan(AgentPlanEvent(summary: "PLAN-TEXT")))
        ingest(.taskCompleted, .terminal(AgentTerminalEvent(summary: "TERMINAL-TEXT")))
    }
}
