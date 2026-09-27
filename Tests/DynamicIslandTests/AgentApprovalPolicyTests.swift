import XCTest
@testable import DynamicIsland

final class AgentApprovalPolicyTests: XCTestCase {
    private let session = AgentSessionInstanceID(
        sessionID: AgentSessionID(provider: .codex, nativeID: "session"),
        generation: AgentSessionGeneration(rawValue: 4)
    )

    func testDefaultWithoutPolicyIsManual() {
        XCTAssertEqual(
            AgentApprovalPolicyEvaluator.decision(
                policy: nil,
                provider: .codex,
                session: session,
                turnID: "turn",
                supportsApprovalControl: true,
                requestIsCurrent: true
            ),
            .manual
        )
    }

    func testTurnPolicyMatchesOnlyExactTurnSessionGenerationAndProvider() {
        let state = AgentApprovalPolicyState(
            key: AgentApprovalPolicyKey(session: session),
            mode: .allowTurn(turnID: "turn-a")
        )
        XCTAssertEqual(decision(state, session: session, turnID: "turn-a"), .allowAutomatically)
        XCTAssertEqual(decision(state, session: session, turnID: "turn-b"), .manual)

        let nextGeneration = AgentSessionInstanceID(
            sessionID: session.sessionID,
            generation: AgentSessionGeneration(rawValue: 5)
        )
        XCTAssertEqual(decision(state, session: nextGeneration, turnID: "turn-a"), .manual)
        XCTAssertEqual(
            AgentApprovalPolicyEvaluator.decision(
                policy: state,
                provider: .claude,
                session: session,
                turnID: "turn-a",
                supportsApprovalControl: true,
                requestIsCurrent: true
            ),
            .manual
        )
    }

    func testSessionPolicyRequiresCurrentVerifiedApprovalControl() {
        let state = AgentApprovalPolicyState(
            key: AgentApprovalPolicyKey(session: session),
            mode: .allowSession
        )
        XCTAssertEqual(decision(state, session: session, turnID: "turn"), .allowAutomatically)
        XCTAssertEqual(
            AgentApprovalPolicyEvaluator.decision(
                policy: state,
                provider: .codex,
                session: session,
                turnID: "turn",
                supportsApprovalControl: false,
                requestIsCurrent: true
            ),
            .manual
        )
        XCTAssertEqual(
            AgentApprovalPolicyEvaluator.decision(
                policy: state,
                provider: .codex,
                session: session,
                turnID: "turn",
                supportsApprovalControl: true,
                requestIsCurrent: false
            ),
            .manual
        )
    }

    func testAskPolicyNeverAutoAllows() {
        let state = AgentApprovalPolicyState(
            key: AgentApprovalPolicyKey(session: session),
            mode: .askEveryTime
        )
        XCTAssertEqual(decision(state, session: session, turnID: "turn"), .manual)
    }
    private func decision(
        _ policy: AgentApprovalPolicyState?,
        session: AgentSessionInstanceID,
        turnID: String
    ) -> AgentApprovalPolicyDecision {
        AgentApprovalPolicyEvaluator.decision(
            policy: policy,
            provider: .codex,
            session: session,
            turnID: turnID,
            supportsApprovalControl: true,
            requestIsCurrent: true
        )
    }
}
