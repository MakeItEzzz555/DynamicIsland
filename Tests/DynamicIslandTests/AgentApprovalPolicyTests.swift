import AgentBridgeShared
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentApprovalPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_100_000_000)

    func testAskEveryTimeIsDefaultAndAutoApproveIsExactSessionScoped() async {
        let current = now
        let controller = AgentApprovalController(now: { current })
        let session = instance(nativeID: "thread-a", generation: 4)
        let other = instance(nativeID: "thread-b", generation: 4)

        XCTAssertEqual(controller.approvalPolicy(for: session), .askEveryTime)
        controller.setAutoApprove(true, for: session)
        XCTAssertEqual(controller.approvalPolicy(for: session), .autoApprove)
        XCTAssertEqual(controller.approvalPolicy(for: other), .askEveryTime)

        let decision = await controller.request(request(session: session, id: "request-a"))
        XCTAssertEqual(decision, .allow)
        XCTAssertNil(controller.pendingRequest(for: session))
    }

    func testPolicySwitchDoesNotRetroactivelyResolvePendingRequest() async {
        let current = now
        let controller = AgentApprovalController(now: { current })
        let session = instance(nativeID: "thread", generation: 1)
        let pending = request(session: session, id: "pending")
        let waiter = Task { await controller.request(pending, maximumWait: .seconds(1)) }
        await Task.yield()

        controller.setAutoApprove(true, for: session)
        XCTAssertNotNil(controller.pendingRequest(for: session))
        XCTAssertEqual(
            controller.resolve(session: session, requestID: pending.key.requestID, decision: .deny),
            .accepted
        )
        let decision = await waiter.value
        XCTAssertEqual(decision, .deny)
    }

    func testAutoApproveDoesNotCrossGenerationAndResolvesOnce() async {
        let current = now
        let controller = AgentApprovalController(now: { current })
        let allowed = instance(nativeID: "thread", generation: 2)
        let stale = instance(nativeID: "thread", generation: 1)
        controller.setAutoApprove(true, for: allowed)

        let staleRequest = request(session: stale, id: "stale")
        let staleWaiter = Task { await controller.request(staleRequest, maximumWait: .seconds(1)) }
        await Task.yield()
        XCTAssertNotNil(controller.pendingRequest(for: stale))
        controller.cancelAll()
        let staleDecision = await staleWaiter.value
        XCTAssertNil(staleDecision)

        let exact = request(session: allowed, id: "exact")
        let firstDecision = await controller.request(exact)
        let replayedDecision = await controller.request(exact)
        XCTAssertEqual(firstDecision, .allow)
        XCTAssertNil(replayedDecision)
    }

    private func instance(nativeID: String, generation: UInt64) -> AgentSessionInstanceID {
        AgentSessionInstanceID(
            sessionID: AgentSessionID(provider: .codex, nativeID: nativeID),
            generation: AgentSessionGeneration(rawValue: generation)
        )
    }

    private func request(
        session: AgentSessionInstanceID,
        id: String
    ) -> AgentApprovalControlRequest {
        AgentApprovalControlRequest(
            key: AgentApprovalControlKey(
                session: session,
                requestID: AgentCorrelationID(rawValue: id)
            ),
            summary: "Run tests",
            expiresAt: now.addingTimeInterval(75)
        )
    }
}
