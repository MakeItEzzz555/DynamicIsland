import AgentBridgeShared
import Foundation
import XCTest
@testable import DynamicIsland

/// Opt-in live acceptance for managed approval authority. Drives the real
/// Claude Code CLI (stream-json, host permission prompts over stdio)
/// through `AgentManagedSessionController`, and answers each real
/// `can_use_tool` request through `AgentApprovalController.resolve` — the
/// same call the Allow/Deny buttons make. No auto-approve policy is used.
///
/// Turn 1 is denied: the file must not exist afterwards.
/// Turn 2 is allowed: the file must exist with the exact contents.
///
/// Uses real provider quota. Enable with
/// DYNAMIC_ISLAND_LIVE_APPROVAL_E2E=1 and DYNAMIC_ISLAND_LIVE_AGENT_ROOT=<dir>.
final class AgentLiveApprovalEndToEndTests: XCTestCase {
    @MainActor
    func testClaudeLiveDenyThenAllowThroughApprovalController() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DYNAMIC_ISLAND_LIVE_APPROVAL_E2E"] == "1",
              let root = environment["DYNAMIC_ISLAND_LIVE_AGENT_ROOT"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_APPROVAL_E2E=1 and DYNAMIC_ISLAND_LIVE_AGENT_ROOT to run.")
        }
        let folder = URL(fileURLWithPath: root)
            .appendingPathComponent("approval-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        log("folder \(folder.path)")

        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let controller = AgentManagedSessionController(
            providers: [try ClaudeInteractiveProvider.makeDefault()],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
        controller.startObserving()
        defer { controller.stop() }
        await controller.refreshPersistentSnapshot()
        XCTAssertTrue(controller.selectNewSessionModel("haiku", for: .claude))

        let started: AgentManagedStartedSession
        switch await controller.startManagedSession(provider: .claude, cwd: folder.path) {
        case .success(let value): started = value
        case .failure(let failure): return XCTFail("start failed: \(failure.message)")
        }
        let instance = started.instance
        log("session …\(instance.sessionID.nativeID.suffix(8)) gen=\(instance.generation.rawValue)")
        XCTAssertEqual(approvals.approvalPolicy(for: instance), .askEveryTime)

        // Turn 1 — DENY.
        let denied = folder.appendingPathComponent("approval-denied.txt")
        let denyEvidence = try await runTurn(
            prompt: "Use the Write tool to create a file named approval-denied.txt in the current directory containing exactly: denied-check. If permission is denied, do not retry with any tool; reply with the single word REFUSED.",
            decision: .deny,
            controller: controller,
            store: store,
            approvals: approvals,
            instance: instance
        )
        XCTAssertFalse(denyEvidence.isEmpty, "no real approval request reached the controller")
        let deniedExists = FileManager.default.fileExists(atPath: denied.path)
        log("DENY file check approval-denied.txt exists=\(deniedExists)")
        XCTAssertFalse(deniedExists, "denied write must not create the file")
        for requestID in denyEvidence {
            let state = store.session(for: instance)?.approvals[requestID]?.state
            log("DENY request …\(requestID.rawValue.suffix(8)) store state=\(state.map { "\($0)" } ?? "-")")
            XCTAssertEqual(state, .denied)
        }

        // Turn 2 — ALLOW.
        let allowed = folder.appendingPathComponent("approval-allowed.txt")
        let allowEvidence = try await runTurn(
            prompt: "Use the Write tool to create a file named approval-allowed.txt in the current directory containing exactly: allowed-check. Then reply with the single word DONE.",
            decision: .allow,
            controller: controller,
            store: store,
            approvals: approvals,
            instance: instance
        )
        XCTAssertFalse(allowEvidence.isEmpty, "no real approval request reached the controller")
        let contents = try? String(contentsOf: allowed, encoding: .utf8)
        log("ALLOW file check approval-allowed.txt contents=\(contents.map { "\"\($0.trimmingCharacters(in: .whitespacesAndNewlines))\"" } ?? "missing")")
        XCTAssertEqual(contents?.trimmingCharacters(in: .whitespacesAndNewlines), "allowed-check")
        for requestID in allowEvidence {
            let state = store.session(for: instance)?.approvals[requestID]?.state
            log("ALLOW request …\(requestID.rawValue.suffix(8)) store state=\(state.map { "\($0)" } ?? "-")")
            XCTAssertEqual(state, .approved)
        }
        let final = try XCTUnwrap(store.session(for: instance))
        log("final state=\(final.state.rawValue) interaction=\(controller.interactionState(for: final))")
        XCTAssertEqual(final.state, .completed)
        XCTAssertNil(approvals.presentedRequest(for: instance))
    }

    /// Regression for the 75 s wall-clock expiry: a decision made long after
    /// the request appeared still reaches the exact real request, and the
    /// turn continues. Opt in with DYNAMIC_ISLAND_LIVE_APPROVAL_LONG_WAIT=1.
    @MainActor
    func testClaudeLiveApprovalAfterLongWaitStillUnblocksExactTurn() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DYNAMIC_ISLAND_LIVE_APPROVAL_LONG_WAIT"] == "1",
              let root = environment["DYNAMIC_ISLAND_LIVE_AGENT_ROOT"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_APPROVAL_LONG_WAIT=1 and DYNAMIC_ISLAND_LIVE_AGENT_ROOT to run.")
        }
        let folder = URL(fileURLWithPath: root)
            .appendingPathComponent("approval-wait-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let controller = AgentManagedSessionController(
            providers: [try ClaudeInteractiveProvider.makeDefault()],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
        controller.startObserving()
        defer { controller.stop() }
        await controller.refreshPersistentSnapshot()
        XCTAssertTrue(controller.selectNewSessionModel("haiku", for: .claude))
        guard case .success(let started) = await controller.startManagedSession(provider: .claude, cwd: folder.path) else {
            return XCTFail("start failed")
        }
        let target = folder.appendingPathComponent("approval-late.txt")
        let evidence = try await runTurn(
            prompt: "Use the Write tool to create a file named approval-late.txt in the current directory containing exactly: late-check. Then reply with the single word DONE.",
            decision: .allow,
            controller: controller,
            store: store,
            approvals: approvals,
            instance: started.instance,
            decisionDelay: .seconds(90)
        )
        XCTAssertFalse(evidence.isEmpty)
        let contents = try? String(contentsOf: target, encoding: .utf8)
        log("LATE ALLOW (90 s) contents=\(contents ?? "missing")")
        XCTAssertEqual(contents?.trimmingCharacters(in: .whitespacesAndNewlines), "late-check")
        for requestID in evidence {
            XCTAssertEqual(store.session(for: started.instance)?.approvals[requestID]?.state, .approved)
        }
    }

    /// Submits one turn and answers every real approval request of that
    /// turn with `decision`, through the public resolve API only. Returns
    /// the exact request ids that were answered.
    @MainActor
    private func runTurn(
        prompt: String,
        decision: AgentBridgePermissionDecision,
        controller: AgentManagedSessionController,
        store: AgentEventStore,
        approvals: AgentApprovalController,
        instance: AgentSessionInstanceID,
        decisionDelay: Duration = .zero
    ) async throws -> [AgentCorrelationID] {
        var firstSeen: ContinuousClock.Instant?
        let label = decision == .allow ? "ALLOW" : "DENY"
        let session = try XCTUnwrap(store.session(for: instance))
        let accepted = await controller.submit(prompt, for: session)
        XCTAssertTrue(accepted, "submit refused: \(controller.lastTransportError ?? "-")")
        var answered: [AgentCorrelationID] = []
        var sawWorking = false
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            if let pending = approvals.pendingRequest(for: instance) {
                let seen = firstSeen ?? ContinuousClock.now
                firstSeen = seen
                if ContinuousClock.now - seen < decisionDelay {
                    // The provider is still blocked; the island must keep the
                    // exact request actionable and send nothing on its own.
                    XCTAssertEqual(approvals.deliveryState(for: pending.key), .awaitingDecision)
                    try await Task.sleep(for: .milliseconds(500))
                    continue
                }
                firstSeen = nil
                XCTAssertEqual(pending.key.session, instance, "request bound to another session")
                let turn = controller.activeManagedSessionIDs.contains(instance.sessionID)
                log("\(label) request …\(pending.key.requestID.rawValue.suffix(8)) session=…\(pending.key.session.sessionID.nativeID.suffix(8)) gen=\(pending.key.session.generation.rawValue) activeTurn=\(turn) summary=\"\(pending.summary)\"")
                // For Allow, only the requested file write is approved.
                let choice: AgentBridgePermissionDecision =
                    decision == .allow && pending.summary.contains("Write") ? .allow : .deny
                let result = approvals.resolve(
                    session: pending.key.session,
                    requestID: pending.key.requestID,
                    decision: choice
                )
                log("\(label) resolve(\(choice == .allow ? "allow" : "deny")) → \(result)")
                XCTAssertEqual(result, .accepted)
                // One-shot: a second click is refused.
                XCTAssertEqual(
                    approvals.resolve(session: pending.key.session, requestID: pending.key.requestID, decision: .allow),
                    .missing
                )
                answered.append(pending.key.requestID)
            }
            if let current = store.session(for: instance) {
                switch controller.interactionState(for: current) {
                case .working, .submitting, .stopping:
                    sawWorking = true
                case .ready, .failed:
                    if sawWorking || !answered.isEmpty {
                        log("\(label) turn finished state=\(current.state.rawValue)")
                        return answered
                    }
                default:
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("\(label) turn did not finish")
        return answered
    }

    private func log(_ message: String) {
        print("LIVE-APPROVAL[claude] \(message)")
    }
}
