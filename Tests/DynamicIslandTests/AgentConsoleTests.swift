import AppKit
import XCTest
@testable import DynamicIsland

final class AgentConsoleTests: XCTestCase {
    func testObservedAndInteractiveModesExposeOnlySupportedControls() {
        XCTAssertFalse(AgentConsoleMode.observed.showsComposer)
        XCTAssertFalse(AgentConsoleMode.observed.canInterrupt)
        XCTAssertTrue(AgentConsoleMode.interactive(canInterrupt: false).showsComposer)
        XCTAssertFalse(AgentConsoleMode.interactive(canInterrupt: false).canInterrupt)
        XCTAssertTrue(AgentConsoleMode.interactive(canInterrupt: true).canInterrupt)
    }

    func testSubmissionRejectsEmptyAndBoundsPromptLength() {
        XCTAssertNil(AgentPromptDraftPolicy.submission(from: " \n\t "))
        XCTAssertEqual(AgentPromptDraftPolicy.submission(from: "  hello\n"), "hello")

        let oversized = String(repeating: "a", count: AgentPromptDraftPolicy.maximumLength + 12)
        XCTAssertEqual(
            AgentPromptDraftPolicy.submission(from: oversized)?.count,
            AgentPromptDraftPolicy.maximumLength
        )
    }

    func testCommandReturnSubmitsWhileShiftReturnRemainsNativeNewline() {
        XCTAssertTrue(AgentPromptDraftPolicy.submitsReturn(with: [.command]))
        XCTAssertTrue(AgentPromptDraftPolicy.submitsReturn(with: [.command, .shift]))
        XCTAssertFalse(AgentPromptDraftPolicy.submitsReturn(with: [.shift]))
        XCTAssertFalse(AgentPromptDraftPolicy.submitsReturn(with: []))
    }

    func testConsoleProjectionMapsMessagesAndSafeOperationsAndStaysBounded() {
        let transcript = [
            AgentManagedTranscriptEntry(
                id: "u1", nativeSessionID: "thread", turnID: "turn",
                role: .user, text: "Fix it", timestamp: Date(timeIntervalSince1970: 1)
            ),
            AgentManagedTranscriptEntry(
                id: "a1", nativeSessionID: "thread", turnID: "turn",
                role: .agent, text: "Done", timestamp: Date(timeIntervalSince1970: 3)
            ),
            AgentManagedTranscriptEntry(
                id: "h1", nativeSessionID: "thread", turnID: "turn",
                role: .tool, text: "Updated 2 files", timestamp: Date(timeIntervalSince1970: 2.5)
            )
        ]
        let operations = [
            AgentOperationSummary(
                id: "command:1", symbol: "terminal", title: "Run tests", detail: "Exit 0",
                status: .completed, count: 1, date: Date(timeIntervalSince1970: 2),
                isCommand: true
            )
        ]

        let entries = AgentConsoleEntry.make(
            transcript: transcript,
            operations: operations,
            limit: 2
        )

        XCTAssertEqual(entries.map(\.kind), [.tool, .agent])
        XCTAssertEqual(entries.map(\.id), ["message:h1", "message:a1"])
        XCTAssertFalse(entries.contains { ($0.text ?? "").contains("raw") })
    }

    func testConsoleProjectionClassifiesApprovalPlanAndError() {
        let date = Date()
        let operations = [
            AgentOperationSummary(
                id: "approval:1", symbol: "checkmark.shield", title: "Approval requested",
                detail: "Run tests", status: .pending, count: 1, date: date, isCommand: false
            ),
            AgentOperationSummary(
                id: "plan:1", symbol: "list.bullet", title: "Plan ready",
                detail: nil, status: .completed, count: 1, date: date, isCommand: false
            ),
            AgentOperationSummary(
                id: "failure:1", symbol: "exclamationmark.triangle", title: "Failed",
                detail: "Safe error", status: .failed, count: 1, date: date, isCommand: false
            )
        ]

        XCTAssertEqual(
            Set(AgentConsoleEntry.make(transcript: [], operations: operations).map(\.kind)),
            Set([.approval, .plan, .error])
        )
    }


    func testResolvedApprovalKeepsApprovalKindAndExactIdentity() {
        let operations = [
            AgentOperationSummary(
                id: "approval:a", symbol: "checkmark.shield", title: "Approved",
                detail: "Run migration", status: .resolved, count: 1,
                date: Date(timeIntervalSince1970: 1), isCommand: false
            ),
            AgentOperationSummary(
                id: "approval:b", symbol: "checkmark.shield", title: "Denied",
                detail: "Delete files", status: .resolved, count: 1,
                date: Date(timeIntervalSince1970: 2), isCommand: false
            )
        ]
        let entries = AgentConsoleEntry.make(transcript: [], operations: operations)
        XCTAssertEqual(entries.map(\.kind), [.approval, .approval])
        XCTAssertEqual(entries.map(\.correlationID), ["approval:a", "approval:b"])
    }

    func testAgentTranscriptUsesSelectedProviderIdentity() {
        let transcript = [AgentManagedTranscriptEntry(
            id: "a1", nativeSessionID: "same", turnID: "turn",
            role: .agent, text: "Hello", timestamp: Date()
        )]

        XCTAssertEqual(
            AgentConsoleEntry.make(
                transcript: transcript,
                operations: [],
                provider: .claude
            ).first?.title,
            "Claude"
        )
    }

    func testAgentsPresentationGenerationRetriggersAndRejectsStaleReveal() {
        var state = AgentsPagePresentationState()
        let first = state.begin()
        XCTAssertEqual(state.phase, .entering)
        XCTAssertTrue(state.revealChrome(generation: first))
        XCTAssertTrue(state.chromeVisible)

        state.cancel()
        XCTAssertEqual(state.phase, .inactive)
        XCTAssertFalse(state.revealTranscript(generation: first))

        let second = state.begin()
        XCTAssertNotEqual(second, first)
        XCTAssertTrue(state.revealChrome(generation: second))
        XCTAssertTrue(state.revealTranscript(generation: second))
        XCTAssertTrue(state.transcriptReady)
    }

    func testLeavingAgentsCancelsPresentationLifecycle() {
        var state = AgentsPagePresentationState()
        let generation = state.begin()
        XCTAssertTrue(state.revealChrome(generation: generation))

        state.cancel()

        XCTAssertEqual(state.phase, .inactive)
        XCTAssertFalse(state.chromeVisible)
        XCTAssertFalse(state.transcriptReady)
        XCTAssertFalse(state.revealTranscript(generation: generation))
    }

    func testManagedControlStateAllowsPromptOnlyWhileIdleAndReady() {
        var state = AgentManagedControlState(
            nativeSessionID: "thread",
            activeTurnID: nil,
            isSubmitting: false,
            isInterrupting: false,
            lastError: nil,
            acceptsDirectInput: true
        )
        XCTAssertTrue(state.canSubmit)

        state.activeTurnID = "turn"
        XCTAssertFalse(state.canSubmit)
        XCTAssertTrue(state.canInterrupt)

        state.isInterrupting = true
        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.canInterrupt)
    }

    func testDeferredTranscriptLoadCancellationRejectsDelayedCompletion() {
        let session = sessionID("first")
        var gate = AgentTranscriptLoadGate()
        let generation = gate.begin(for: session)

        gate.cancel()

        XCTAssertFalse(gate.complete(for: session, generation: generation))
        XCTAssertFalse(gate.isReady(for: session))
    }

    func testSelectedSessionChangeCancelsStaleTranscriptCompletion() {
        let first = sessionID("first")
        let second = sessionID("second")
        var gate = AgentTranscriptLoadGate()
        let firstGeneration = gate.begin(for: first)
        let secondGeneration = gate.begin(for: second)

        XCTAssertFalse(gate.complete(for: first, generation: firstGeneration))
        XCTAssertTrue(gate.complete(for: second, generation: secondGeneration))
        XCTAssertFalse(gate.isReady(for: first))
        XCTAssertTrue(gate.isReady(for: second))
    }

    func testLeavingAgentsClearsReadyTranscriptState() {
        let session = sessionID("selected")
        var gate = AgentTranscriptLoadGate()
        let generation = gate.begin(for: session)
        XCTAssertTrue(gate.complete(for: session, generation: generation))

        gate.cancel()

        XCTAssertFalse(gate.isReady(for: session))
        XCTAssertNil(gate.requestedSessionID)
        XCTAssertNil(gate.readySessionID)
    }

    private func sessionID(_ nativeID: String) -> AgentSessionInstanceID {
        AgentSessionInstanceID(
            sessionID: AgentSessionID(provider: .codex, nativeID: nativeID),
            generation: AgentSessionGeneration(rawValue: 1)
        )
    }
}
