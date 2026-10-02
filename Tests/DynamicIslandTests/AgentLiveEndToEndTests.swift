import Combine
import Foundation
import XCTest
@testable import DynamicIsland

/// Opt-in live acceptance for the embedded agent console. Drives the same
/// controller path as the Agents page against the installed Claude Code
/// and Codex CLIs in a freshly created scratch folder:
/// new folder → start → submit → streamed reply → file created in that
/// folder → Stop → resume the exact session from a fresh controller.
///
/// Uses real provider quota. Enable with
/// DYNAMIC_ISLAND_LIVE_AGENT_E2E=1 and DYNAMIC_ISLAND_LIVE_AGENT_ROOT=<dir>
/// (optionally DYNAMIC_ISLAND_LIVE_AGENT_PROVIDERS=claude,codex).
final class AgentLiveEndToEndTests: XCTestCase {
    @MainActor
    func testClaudeLiveEndToEnd() async throws {
        try await runLive(.claude, model: "haiku")
    }

    @MainActor
    func testCodexLiveEndToEnd() async throws {
        try await runLive(.codex, model: nil)
    }

    @MainActor
    private func runLive(_ provider: AgentProvider, model: String?) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DYNAMIC_ISLAND_LIVE_AGENT_E2E"] == "1",
              let root = environment["DYNAMIC_ISLAND_LIVE_AGENT_ROOT"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_AGENT_E2E=1 and DYNAMIC_ISLAND_LIVE_AGENT_ROOT to run live agents.")
        }
        if let only = environment["DYNAMIC_ISLAND_LIVE_AGENT_PROVIDERS"],
           !only.split(separator: ",").contains(Substring(provider.stableName)) {
            throw XCTSkip("\(provider.stableName) not selected")
        }

        // New Folder… equivalent: a brand-new, empty, non-Git folder.
        let folder = URL(fileURLWithPath: root)
            .appendingPathComponent("new-\(provider.stableName)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        log(provider, "folder \(folder.path)")

        // 1. Start in that folder.
        let first = try makeController()
        let firstObservation = observeRuntime(first.store, provider: provider, cwd: folder.path)
        defer { firstObservation.cancel(); first.controller.stop() }
        await first.controller.refreshPersistentSnapshot()
        if let model {
            XCTAssertTrue(first.controller.selectNewSessionModel(model, for: provider), "model \(model) not offered")
        }
        let started: AgentManagedStartedSession
        switch await first.controller.startManagedSession(provider: provider, cwd: folder.path) {
        case .success(let value): started = value
        case .failure(let failure): return XCTFail("start failed: \(failure.message)")
        }
        XCTAssertEqual(started.descriptor.cwd, folder.path)
        XCTAssertEqual(first.controller.selectedSessionID, started.instance)
        let session = try XCTUnwrap(first.store.session(for: started.instance))
        XCTAssertTrue(first.controller.mode(for: session).showsComposer)
        XCTAssertEqual(first.controller.interactionState(for: session), .ready)
        log(provider, "started …\(started.instance.sessionID.nativeID.suffix(6)) composer=ready")

        // 2. Submit; the agent writes a file in the exact cwd.
        first.approvals.setAutoApprove(true, for: started.instance)
        let accepted = await first.controller.submit(
            "Create hello.txt in the current directory. Its entire contents must be the text between the delimiters below, excluding the delimiters, with no punctuation or other text added.\n<contents>hi from \(provider.stableName)</contents>\nThen reply with the single word DONE.",
            for: session
        )
        XCTAssertTrue(accepted, "submit refused: \(first.controller.lastTransportError ?? "-")")
        let sawWorking = try await waitUntilIdle(first.controller, first.store, started.instance, timeout: 240)
        XCTAssertTrue(sawWorking)
        let transcript = first.controller.transcript(for: try XCTUnwrap(first.store.session(for: started.instance)))
        for entry in transcript {
            log(provider, "entry role=\(entry.role.rawValue) id=\(entry.id.prefix(48)) turn=\(entry.turnID?.suffix(6) ?? "-") text=\(entry.text.prefix(40))")
        }
        let agentText = transcript.filter { $0.role == .agent }.map(\.text).joined(separator: " ")
        log(provider, "reply: \(agentText.prefix(120))")
        XCTAssertFalse(agentText.isEmpty, "no streamed agent text")
        let written = try? String(contentsOf: folder.appendingPathComponent("hello.txt"), encoding: .utf8)
        log(provider, "hello.txt=\(written.map { "\"\($0.trimmingCharacters(in: .whitespacesAndNewlines))\"" } ?? "missing")")
        XCTAssertEqual(written?.trimmingCharacters(in: .whitespacesAndNewlines), "hi from \(provider.stableName)")
        first.approvals.setAutoApprove(false, for: started.instance)
        let afterTurn = try XCTUnwrap(first.store.session(for: started.instance))
        log(provider, "after turn state=\(afterTurn.state.rawValue) orb=\(AgentOrbStateMapper.state(for: afterTurn).rawValue)")
        XCTAssertEqual(afterTurn.state, .completed)
        let context = AgentUsageIndicatorPresentation.make(
            provider: provider,
            accountUsage: first.controller.accountUsageByProvider[provider] ?? AgentUsage(),
            selectedSession: afterTurn
        )
        log(provider, "usage " + context.map { "\($0.label)=\($0.valueText)(\($0.authority.rawValue))" }.joined(separator: " "))

        // 3. Stop a running turn.
        let longTurn = await first.controller.submit(
            "Write the numbers from 1 to 400, one per line, with no other text.",
            for: try XCTUnwrap(first.store.session(for: started.instance))
        )
        XCTAssertTrue(longTurn)
        try await waitFor(timeout: 60) {
            guard let current = first.store.session(for: started.instance) else { return false }
            return first.controller.mode(for: current).canInterrupt
        }
        try await Task.sleep(for: .seconds(2))
        first.controller.interrupt(try XCTUnwrap(first.store.session(for: started.instance)))
        _ = try await waitUntilIdle(first.controller, first.store, started.instance, timeout: 60)
        let afterStop = try XCTUnwrap(first.store.session(for: started.instance))
        log(provider, "after Stop state=\(afterStop.state.rawValue) interaction=\(first.controller.interactionState(for: afterStop))")
        XCTAssertEqual(afterStop.state, .interrupted)
        XCTAssertTrue(first.controller.mode(for: afterStop).showsComposer, "composer must remain after Stop")
        first.controller.stop()
        try await Task.sleep(for: .seconds(1))

        // 4. Resume the exact session from a fresh controller (as after relaunch).
        let second = try makeController()
        let secondObservation = observeRuntime(second.store, provider: provider, cwd: folder.path)
        defer { secondObservation.cancel(); second.controller.stop() }
        await second.controller.refreshPersistentSnapshot()
        let resumable = try XCTUnwrap(
            second.store.sessions.first { $0.id.sessionID == started.instance.sessionID },
            "exact session not rediscovered"
        )
        XCTAssertTrue(second.controller.canConnect(resumable), "Resume not offered")
        second.controller.connect(resumable)
        try await waitFor(timeout: 60) {
            second.store.sessions.contains {
                $0.id.sessionID == started.instance.sessionID && second.controller.isManaged($0)
            }
        }
        let resumed = try XCTUnwrap(second.store.sessions.first {
            $0.id.sessionID == started.instance.sessionID && second.controller.isManaged($0)
        })
        XCTAssertEqual(resumed.id.sessionID.nativeID, started.instance.sessionID.nativeID)
        XCTAssertTrue(second.controller.mode(for: resumed).showsComposer)
        let followUp = await second.controller.submit(
            "What is the name of the file you created earlier in this conversation? Reply with only the file name.",
            for: resumed
        )
        XCTAssertTrue(followUp, "resume submit refused: \(second.controller.lastTransportError ?? "-")")
        _ = try await waitUntilIdle(second.controller, second.store, resumed.id, timeout: 180)
        let resumedText = second.controller.transcript(for: resumed)
            .filter { $0.role == .agent }.map(\.text).joined(separator: " ")
        log(provider, "resume reply: \(resumedText.suffix(80))")
        XCTAssertTrue(resumedText.localizedCaseInsensitiveContains("hello.txt"))
        second.controller.stop()
    }

    // MARK: Helpers

    @MainActor
    private func makeController() throws -> (controller: AgentManagedSessionController, store: AgentEventStore, approvals: AgentApprovalController) {
        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let controller = AgentManagedSessionController(
            providers: [try ClaudeInteractiveProvider.makeDefault(), try CodexAppServerProvider.makeDefault()],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
        controller.startObserving()
        return (controller, store, approvals)
    }

    /// Observe production publications so short-lived tool states are not
    /// lost between polling intervals. This never injects presentation hints.
    @MainActor
    private func observeRuntime(_ store: AgentEventStore, provider: AgentProvider, cwd: String) -> AnyCancellable {
        var previous: [AgentSessionInstanceID: String] = [:]
        let canonicalCWD = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path
        return store.$sessions.sink { [weak self] sessions in
            for session in sessions where session.project.workingDirectory.map({
                URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
            }) == canonicalCWD {
                let orb = AgentOrbStateMapper.state(for: session)
                let activity = session.recentActivity.last
                let detail = "state=\(session.state.rawValue) orb=\(orb.rawValue) activity=\(String(describing: activity?.kind)) status=\(String(describing: activity?.status))"
                guard previous[session.id] != detail else { continue }
                previous[session.id] = detail
                self?.log(provider, "runtime id=\(session.id) \(detail)")
            }
        }
    }

    /// Waits for a submitted turn to start and finish. Returns whether a
    /// working state was observed.
    @MainActor
    private func waitUntilIdle(
        _ controller: AgentManagedSessionController,
        _ store: AgentEventStore,
        _ instance: AgentSessionInstanceID,
        timeout: TimeInterval
    ) async throws -> Bool {
        var sawWorking = false
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let session = store.sessions.first(where: { $0.id.sessionID == instance.sessionID }) {
                switch controller.interactionState(for: session) {
                case .working, .submitting, .stopping:
                    sawWorking = true
                case .ready, .failed:
                    if sawWorking { return true }
                default:
                    break
                }
                if !sawWorking, controller.activeManagedSessionIDs.contains(instance.sessionID) {
                    sawWorking = true
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTFail("turn did not finish within \(Int(timeout))s")
        return sawWorking
    }

    @MainActor
    private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("condition not met within \(Int(timeout))s")
    }

    private func log(_ provider: AgentProvider, _ message: String) {
        print("LIVE[\(provider.stableName)] \(message)")
    }
}
