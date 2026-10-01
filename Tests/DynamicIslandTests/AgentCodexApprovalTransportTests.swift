import AgentBridgeShared
import Foundation
import XCTest
@testable import DynamicIsland

/// End-to-end managed Codex approval over a real stdio JSON-RPC transport:
/// the production CodexAppServerClient, CodexAppServerProvider and
/// AgentManagedSessionController drive a fake app-server process that
/// follows the v2 protocol (server request -> client response ->
/// `serverRequest/resolved` -> turn continues). Every wire response is
/// logged by the server, so the test proves exactly what reached it.
final class AgentCodexApprovalTransportTests: XCTestCase {
    @MainActor
    func testApproveAndDenyReachExactRequestAndStaleOrDuplicateNeverDo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DI-CodexApproval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let wireLog = directory.appendingPathComponent("wire.log")
        let server = directory.appendingPathComponent("fake-codex")
        try #"""
        #!/usr/bin/env python3
        import json, sys
        LOG = sys.argv[-1] if False else "\#(wireLog.path)"
        THREAD = {"id": "thread-1", "cwd": "/tmp", "canAcceptDirectInput": True,
                  "status": {"type": "idle"}, "updatedAt": 1}
        turn = [0]
        def send(obj): print(json.dumps(obj), flush=True)
        def note(text):
            with open(LOG, "a") as handle: handle.write(text + "\n")
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            rid = message.get("id")
            if method is None and rid == 0:
                # Response to our approval request (id 0 is reused per turn,
                # like JSON-RPC ids after a reconnect).
                note("turn-%d:%s" % (turn[0], message.get("result", {}).get("decision")))
                send({"method": "serverRequest/resolved", "params": {"threadId": "thread-1", "requestId": 0}})
                send({"method": "turn/completed", "params": {"threadId": "thread-1",
                      "turn": {"id": "turn-%d" % turn[0], "status": "completed"}}})
                continue
            if method == "initialize": send({"id": rid, "result": {}})
            elif method == "initialized": pass
            elif method == "thread/start":
                send({"id": rid, "result": {"thread": THREAD, "model": "gpt-test"}})
            elif method in ("thread/read", "thread/resume"):
                send({"id": rid, "result": {"thread": THREAD}})
            elif method == "thread/list": send({"id": rid, "result": {"data": [THREAD]}})
            elif method == "turn/start":
                turn[0] += 1
                tid = "turn-%d" % turn[0]
                send({"id": rid, "result": {"turn": {"id": tid, "status": "inProgress"}}})
                send({"method": "turn/started", "params": {"threadId": "thread-1", "turn": {"id": tid}}})
                request = {"id": 0, "method": "item/fileChange/requestApproval",
                           "params": {"threadId": "thread-1", "turnId": tid, "itemId": "item-%d" % turn[0]}}
                send(request)
                if turn[0] == 1:
                    send(request)  # duplicated provider request
            elif rid is not None:
                send({"id": rid, "result": {"data": []}})
        """#.write(to: server, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)

        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let provider = CodexAppServerProvider(
            client: try CodexAppServerClient(executableURL: server, requestTimeout: .seconds(5))
        )
        let controller = AgentManagedSessionController(
            providers: [provider],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
        controller.startObserving()
        defer { controller.stop() }

        guard case .success(let started) = await controller.startManagedSession(provider: .codex, cwd: directory.path) else {
            return XCTFail("start failed: \(controller.lastTransportError ?? "-")")
        }
        let instance = started.instance

        // Turn 1: Approve.
        let first = try await submitAndAwaitRequest(controller, store, approvals, instance, prompt: "one")
        XCTAssertEqual(approvals.resolve(session: first.key.session, requestID: first.key.requestID, decision: .allow), .accepted)
        XCTAssertEqual(approvals.resolve(session: first.key.session, requestID: first.key.requestID, decision: .allow), .missing)
        try await waitFor { store.session(for: instance)?.approvals[first.key.requestID]?.state == .approved }
        XCTAssertEqual(store.session(for: instance)?.approvals[first.key.requestID]?.state, .approved)
        try await waitFor { controller.activeManagedSessionIDs.isEmpty }

        // Turn 2 reuses JSON-RPC id 0: a stale Turn 1 button cannot answer it.
        let second = try await submitAndAwaitRequest(controller, store, approvals, instance, prompt: "two")
        XCTAssertNotEqual(second.key, first.key)
        XCTAssertEqual(approvals.resolve(session: first.key.session, requestID: first.key.requestID, decision: .allow), .missing)
        XCTAssertEqual(approvals.resolve(session: second.key.session, requestID: second.key.requestID, decision: .deny), .accepted)
        try await waitFor { store.session(for: instance)?.approvals[second.key.requestID]?.state == .denied }
        XCTAssertEqual(store.session(for: instance)?.approvals[second.key.requestID]?.state, .denied)
        // Resolved history from Turn 1 is still there.
        XCTAssertEqual(store.session(for: instance)?.approvals[first.key.requestID]?.state, .approved)

        try await waitFor { (try? String(contentsOf: wireLog, encoding: .utf8))?.contains("turn-2") == true }
        let wire = try String(contentsOf: wireLog, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        XCTAssertEqual(wire, ["turn-1:accept", "turn-2:decline"], "exactly one wire answer per exact request")
    }

    @MainActor
    private func submitAndAwaitRequest(
        _ controller: AgentManagedSessionController,
        _ store: AgentEventStore,
        _ approvals: AgentApprovalController,
        _ instance: AgentSessionInstanceID,
        prompt: String
    ) async throws -> AgentApprovalControlRequest {
        let session = try XCTUnwrap(store.session(for: instance))
        let accepted = await controller.submit(prompt, for: session)
        XCTAssertTrue(accepted)
        try await waitFor { approvals.pendingRequest(for: instance) != nil }
        return try XCTUnwrap(approvals.pendingRequest(for: instance))
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
