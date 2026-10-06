import XCTest
@testable import DynamicIsland

final class AgentProcessingSemanticTests: XCTestCase {
    private let id = AgentTestFixture.sessionID(.codex, "semantic-thread")

    private func item(_ type: String, _ key: String, completed: Bool = false,
                      extra: [String: CodexJSONValue] = [:]) -> [AgentInteractiveProviderEvent] {
        var value = extra
        value["type"] = .string(type); value["id"] = .string(key)
        return CodexAppServerProvider.normalizedEvents(.notification(
            method: completed ? "item/completed" : "item/started",
            params: .object(["threadId": .string(id.nativeID), "turnId": .string("turn"), "item": .object(value)])))
    }

    private func apply(_ values: [AgentInteractiveProviderEvent], to session: inout AgentSession,
                       at offset: Double) throws {
        for (index, value) in values.enumerated() {
            guard case .normalized(let normalized) = value else { continue }
            let event = AgentTestFixture.event("event-\(offset)-\(index)", sessionID: id,
                type: normalized.type, offset: offset + Double(index) / 100,
                correlationID: normalized.correlationID?.rawValue, payload: normalized.payload)
            let result = AgentEventReducer.reduce(session: session, event: event)
            XCTAssertEqual(result.application, .applied)
            session = try XCTUnwrap(result.session)
        }
    }

    private func started() throws -> AgentSession {
        let event = AgentTestFixture.event("start", sessionID: id, type: .sessionStarted, offset: 0,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil)))
        return try XCTUnwrap(AgentEventReducer.reduce(session: nil, event: event).session)
    }

    func testRealItemVocabularyFollowsNestedOperationsAndReturnsToReasoning() throws {
        var session = try started()
        try apply(item("reasoning", "reason"), to: &session, at: 1)
        XCTAssertEqual(session.state, .thinking)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .solving)
        try apply(item("commandExecution", "search", extra: ["command": .string("rg pattern private-path"),
            "commandActions": .array([.object(["type": .string("search")])])]), to: &session, at: 2)
        XCTAssertEqual(session.state, .runningCommand)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .searching)
        try apply(item("commandExecution", "search", completed: true), to: &session, at: 3)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .solving)
        try apply(item("collabAgentToolCall", "connect", extra: ["tool": .string("spawnAgent")]), to: &session, at: 4)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .connecting)
        try apply(item("collabAgentToolCall", "connect", completed: true), to: &session, at: 5)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .solving)
        try apply(item("commandExecution", "execute", extra: ["command": .string("swift test")]), to: &session, at: 6)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .working)
        try apply(item("commandExecution", "execute", completed: true), to: &session, at: 7)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .solving)
        try apply(item("reasoning", "reason", completed: true), to: &session, at: 8)
        try apply(item("agentMessage", "answer"), to: &session, at: 9)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .composing)
        try apply(item("agentMessage", "answer", completed: true, extra: ["text": .string("Searching is prose, not search evidence")]), to: &session, at: 10)
        XCTAssertTrue(session.processingActivities.isEmpty)
        XCTAssertEqual(session.state, .idle)
    }

    func testConcreteToolKindsAndStructuredReadingOverrideMisleadingNames() throws {
        var session = try started()
        let cases: [(String, [String: CodexJSONValue], AgentOrbVisualState)] = [
            ("webSearch", [:], .searching),
            ("mcpToolCall", ["tool": .string("searching_prose_is_not_evidence")], .working),
            ("dynamicToolCall", ["tool": .string("draft")], .working),
            ("fileChange", [:], .working),
            ("commandExecution", ["commandActions": .array([.object(["type": .string("read")])])], .listening),
            ("commandExecution", ["commandActions": .array([.object(["type": .string("listFiles")])])], .searching),
            ("commandExecution", ["command": .string("echo Searching...")], .working),
            ("collabAgentToolCall", ["tool": .string("wait")], .listening)
        ]
        for (index, value) in cases.enumerated() {
            let key = "tool-\(index)"
            try apply(item(value.0, key, extra: value.1), to: &session, at: Double(index * 2 + 1))
            XCTAssertEqual(AgentOrbStateMapper.state(for: session), value.2)
            try apply(item(value.0, key, completed: true), to: &session, at: Double(index * 2 + 2))
        }
    }

    func testPlanningUsesShapingAndAllTypedKindsMapWithoutForcingProviderStates() throws {
        var session = try started()
        try apply(item("plan", "plan"), to: &session, at: 1)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .shaping)
        try apply(item("plan", "plan", completed: true, extra: ["text": .string("A plan")]), to: &session, at: 2)
        XCTAssertFalse(session.isPlanning)
        XCTAssertTrue(session.processingActivities.isEmpty)
        XCTAssertEqual(session.recentActivity.first(where: { $0.title == "Plan updated" })?.summary, "A plan")
        func plan(_ steps: [CodexJSONValue]) -> [AgentInteractiveProviderEvent] {
            CodexAppServerProvider.normalizedEvents(.notification(method: "turn/plan/updated",
                params: .object(["threadId": .string(id.nativeID), "turnId": .string("turn"), "plan": .array(steps)])))
        }
        try apply(plan([.object(["status": .string("inProgress")])]), to: &session, at: 3)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .shaping)
        try apply(plan([]), to: &session, at: 4)
        XCTAssertEqual(session.state, .idle, "A cleared plan has no active planning evidence")
        try apply(plan([.object(["status": .string("completed")])]), to: &session, at: 5)
        XCTAssertTrue(session.processingActivities.isEmpty)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentProcessingKind.synthesizing), .weaving)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentProcessingKind.background), .breathing)
    }

    func testApprovalUserWaitAndTerminalStatesOverrideUnderlyingWork() throws {
        var session = try started()
        try apply(item("reasoning", "reason"), to: &session, at: 1)
        try apply(item("commandExecution", "command"), to: &session, at: 2)
        let approval = AgentTestFixture.event("approval", sessionID: id, type: .approvalRequested, offset: 3,
            correlationID: "request", payload: .approvalRequest(.init(summary: "Approve command", operationCorrelationID: .init(rawValue: "command"), expiresAt: nil)))
        session = try XCTUnwrap(AgentEventReducer.reduce(session: session, event: approval).session)
        XCTAssertEqual(session.state, .waitingForApproval)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .breathing)
        XCTAssertFalse(AgentVisualMotion.animates(session.state))
        XCTAssertNotNil(session.processingActivities[.init(rawValue: "reason")])
        let resolved = AgentTestFixture.event("ack", sessionID: id, type: .approvalResolved, offset: 4,
            correlationID: "request", payload: .approvalResolution(.init(state: .approved)))
        session = try XCTUnwrap(AgentEventReducer.reduce(session: session, event: resolved).session)
        XCTAssertEqual(session.state, .runningCommand)
        for terminal in [AgentEventType.interrupted, .taskCompleted, .taskFailed] {
            let end = AgentTestFixture.event("end", sessionID: id, type: terminal, offset: 5,
                payload: .terminal(AgentTerminalEvent(summary: nil)))
            let ended = try XCTUnwrap(AgentEventReducer.reduce(session: session, event: end).session)
            XCTAssertTrue(ended.processingActivities.isEmpty)
            XCTAssertFalse(AgentVisualMotion.animates(ended.state))
            XCTAssertEqual(AgentOrbStateMapper.state(for: ended), .breathing)
        }
        session.waitingForUserID = .init(rawValue: "user")
        session.state = .waitingForUser
        try apply(item("agentMessage", "new-output"), to: &session, at: 6)
        XCTAssertEqual(session.state, .waitingForUser)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .breathing)
    }

    func testComposedItemPublishesLifecycleAndTranscriptWithoutLeakingReasoning() throws {
        let events = item("agentMessage", "answer", completed: true, extra: ["text": .string("Answer")])
        XCTAssertEqual(events.count, 2)
        guard case .normalized = events.first, case .transcript(let entry) = events.last else { return XCTFail("both streams required") }
        XCTAssertEqual(entry.text, "Answer")
        let reasoning = item("reasoning", "reason", extra: ["text": .string("SECRET"), "summary": .string("SECRET")])
        guard case .normalized(let event) = reasoning.first else { return XCTFail("missing reasoning metadata") }
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(event.payload), as: UTF8.self).contains("SECRET"))
    }

    func testConnectionIsExactSessionScopedAndCannotRemainWorkingAfterReady() throws {
        var session = try started()
        func startup(_ status: String, scoped: Bool) -> [AgentInteractiveProviderEvent] {
            var params: [String: CodexJSONValue] = ["name": .string("server"), "status": .string(status)]
            if scoped { params["threadId"] = .string(id.nativeID) }
            return CodexAppServerProvider.normalizedEvents(.notification(method: "mcpServer/startupStatus/updated", params: .object(params)))
        }
        XCTAssertTrue(startup("starting", scoped: false).isEmpty)
        try apply(startup("starting", scoped: true), to: &session, at: 1)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .connecting)
        try apply(startup("ready", scoped: true), to: &session, at: 2)
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.processingActivities.isEmpty)
    }

    func testOptionalProcessingMetadataDecodesLegacyPayloadsAndBoundsActiveItems() throws {
        let old = try JSONDecoder().decode(AgentActivityDescriptor.self, from: Data(#"{"title":"Working","summary":null}"#.utf8))
        XCTAssertNil(old.processingKind)
        var session = try started()
        try apply(item("reasoning", "first"), to: &session, at: 1)
        let original = session.processingActivities
        try apply(item("reasoning", "first"), to: &session, at: 2)
        XCTAssertEqual(session.processingActivities, original)
        guard case .normalized(let event) = item("reasoning", "second").first else { return XCTFail() }
        var limits = AgentEventStoreLimits.standard; limits.maximumTrackedOperations = 1
        let next = AgentTestFixture.event("over-capacity", sessionID: id, type: event.type, offset: 3,
            correlationID: event.correlationID?.rawValue, payload: event.payload)
        let rejected = AgentEventReducer.reduce(session: session, event: next, limits: limits)
        XCTAssertEqual(rejected.application, .rejected(.operationCapacity))
        XCTAssertEqual(rejected.session, session)
    }

    func testCompactAndExpandedUseSameEvidenceWithoutChangingIdentity() throws {
        var session = try started(); let identity = session.id
        try apply(item("reasoning", "reason"), to: &session, at: 1)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), AgentOrbStateMapper.state(for: .working(canInterrupt: true), session: session))
        try apply(item("webSearch", "search"), to: &session, at: 2)
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), AgentOrbStateMapper.state(for: .observed, session: session))
        XCTAssertEqual(session.id, identity)
        XCTAssertEqual(AgentSessionPresentation.displayedStateLabel(for: session, at: session.lastUpdatedAt), "Searching")
    }

    @MainActor
    func testProcessingEvidenceCannotCrossProviderOrGeneration() throws {
        let store = AgentEventStore()
        let codex = AgentTestFixture.sessionID(.codex, "shared")
        let claude = AgentTestFixture.sessionID(.claude, "shared")
        for (index, providerID) in [codex, claude].enumerated() {
            XCTAssertEqual(store.ingest(AgentTestFixture.event("start-\(index)", sessionID: providerID,
                type: .sessionStarted, offset: 0,
                payload: .sessionMetadata(AgentSessionMetadata(project: nil)))), .applied)
        }
        let processing = AgentActivityDescriptor(title: "Reasoning", summary: nil,
            processingKind: .reasoning, processingStatus: .active)
        XCTAssertEqual(store.ingest(AgentTestFixture.event("reason", sessionID: codex,
            type: .thinkingStarted, offset: 1, correlationID: "same-item", payload: .activity(processing))), .applied)
        let first = AgentSessionInstanceID(sessionID: codex, generation: AgentTestFixture.generation(1))
        let other = AgentSessionInstanceID(sessionID: claude, generation: AgentTestFixture.generation(1))
        XCTAssertEqual(AgentOrbStateMapper.state(for: try XCTUnwrap(store.session(for: first))), .solving)
        XCTAssertTrue(try XCTUnwrap(store.session(for: other)).processingActivities.isEmpty)
        XCTAssertEqual(store.ingest(AgentTestFixture.event("new-generation", sessionID: codex,
            generation: 2, type: .sessionStarted, offset: 2,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil)))), .applied)
        XCTAssertEqual(store.ingest(AgentTestFixture.event("late", sessionID: codex, generation: 1,
            type: .thinkingStarted, offset: 3, correlationID: "same-item", payload: .activity(processing))), .staleGeneration)
        let next = AgentSessionInstanceID(sessionID: codex, generation: AgentTestFixture.generation(2))
        XCTAssertTrue(try XCTUnwrap(store.session(for: next)).processingActivities.isEmpty)
        XCTAssertFalse(AgentVisualMotion.animates(try XCTUnwrap(store.session(for: next)).state))
    }

    @MainActor
    func testLiveCodexSemanticSequence() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_CODEX_SEMANTICS"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_CODEX_SEMANTICS=1 for a real provider task, not packaged UI acceptance.")
        }
        let directory = URL(fileURLWithPath: "/tmp/dynamicisland-phase4/semantic-task-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("func first() -> Int { 7 }\nfunc second() -> Int { 13 }\n".utf8).write(to: directory.appendingPathComponent("sample.swift"))
        let store = AgentEventStore(), approvals = AgentApprovalController()
        let controller = AgentManagedSessionController(providers: [try CodexAppServerProvider.makeDefault()],
            coordinator: AgentIngestionCoordinator(eventStore: store), eventStore: store, approvals: approvals)
        controller.startObserving()
        defer { store.appliedEventObserver = nil; controller.stop() }
        var sequence: [[String: String]] = []
        var target: AgentSessionInstanceID?
        store.appliedEventObserver = { event, session in
            guard session.id == target else { return }
            sequence.append(["event": event.type.stableName, "state": session.state.rawValue,
                "processing": session.currentProcessingKind?.rawValue ?? "none",
                "orb": AgentOrbStateMapper.state(for: session).rawValue,
                "item": event.correlationID?.rawValue ?? "none",
                "session": session.id.sessionID.nativeID,
                "generation": String(session.id.generation.rawValue)])
        }
        await controller.refreshPersistentSnapshot()
        let started: AgentManagedStartedSession
        switch await controller.startManagedSession(provider: .codex, cwd: directory.path) {
        case .success(let value): started = value
        case .failure(let error): return XCTFail(error.message)
        }
        target = started.instance
        // Only this disposable session uses the existing test approval policy.
        approvals.setAutoApprove(true, for: started.instance)
        defer { approvals.setAutoApprove(false, for: started.instance) }
        let session = try XCTUnwrap(store.session(for: started.instance))
        let accepted = await controller.submit("Use your tools to inspect sample.swift without modifying it. First plan the work with update_plan. Search for the function definitions using rg. Then separately read the file using cat. Execute python3 to calculate 7 * 13. Reason about the results, mark the plan completed, and finish with a concise explanation of the two functions and the multiplication result. Do not modify any files or use network access.", for: session)
        XCTAssertTrue(accepted)
        for _ in 0..<600 {
            if let current = store.session(for: started.instance), current.state.isTerminal { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let current = try XCTUnwrap(store.session(for: started.instance))
        let data = try JSONSerialization.data(withJSONObject: sequence, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/dynamicisland-phase4/live-semantic-sequence.json"))
        print("LIVE-CODEX-SEMANTIC " + sequence.map { "\($0["event"]!):\($0["processing"]!):\($0["orb"]!)" }.joined(separator: " → "))
        XCTAssertEqual(current.state, .completed, controller.lastTransportError ?? "turn did not complete")
        XCTAssertTrue(current.processingActivities.isEmpty)
        let observed = Set(sequence.map { $0["orb"]! })
        for required in ["solving", "searching", "working", "composing"] {
            XCTAssertTrue(observed.contains(required), "real provider did not expose \(required); observed \(observed)")
        }
        XCTAssertFalse(AgentVisualMotion.animates(current.state))
    }

    func testCoarseActiveOrbFallbackRotatesButTypedSemanticsWin() throws {
        var session = try started()
        session.state = .working
        session.isWorking = true
        session.processingActivities.removeAll()

        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let states = (0..<7).map {
            AgentOrbStateMapper.liveState(
                for: session,
                at: start.addingTimeInterval(Double($0) * AgentOrbStateMapper.fallbackRotationInterval)
            )
        }
        XCTAssertEqual(
            Set(states),
            Set([.solving, .shaping, .searching, .listening, .working, .weaving, .composing])
        )

        session.processingActivities[AgentCorrelationID(rawValue: "search")] =
            AgentProcessingActivity(kind: .searching, startedAt: start)
        XCTAssertFalse(AgentOrbStateMapper.usesFallbackRotation(for: session))
        XCTAssertEqual(AgentOrbStateMapper.liveState(for: session, at: start), .searching)
        XCTAssertEqual(
            AgentOrbStateMapper.liveState(
                for: session,
                at: start.addingTimeInterval(AgentOrbStateMapper.fallbackRotationInterval * 4)
            ),
            .searching
        )

        XCTAssertEqual(
            AgentOrbStateMapper.liveState(for: .connecting, session: session, at: start),
            .connecting
        )
        XCTAssertEqual(
            AgentOrbStateMapper.liveState(for: .submitting, session: session, at: start),
            .composing
        )
    }

}
