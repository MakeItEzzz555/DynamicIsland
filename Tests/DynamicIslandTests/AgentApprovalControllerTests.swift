import AgentBridgeShared
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentApprovalControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_100_000_000)

    func testAllowAndDenyResolveExactPendingRequestOnce() async {
        for decision in [AgentBridgePermissionDecision.allow, .deny] {
            let current = now
            let controller = AgentApprovalController(now: { current })
            let request = makeRequest(id: decision.rawValue)
            let waiter = Task { await controller.request(request, maximumWait: .seconds(1)) }
            await Task.yield()

            XCTAssertEqual(controller.pendingRequest(for: request.key.session), request)
            XCTAssertEqual(
                controller.resolve(
                    session: request.key.session,
                    requestID: request.key.requestID,
                    decision: decision
                ),
                .accepted
            )
            let result = await waiter.value
            XCTAssertEqual(result, decision)
            XCTAssertNil(controller.pendingRequest(for: request.key.session))
            XCTAssertEqual(
                controller.resolve(
                    session: request.key.session,
                    requestID: request.key.requestID,
                    decision: decision
                ),
                .missing
            )
        }
    }

    func testDuplicateRegistrationAndStaleGenerationAreRejected() async {
        let current = now
        let controller = AgentApprovalController(now: { current })
        let request = makeRequest(id: "exact")
        let waiter = Task { await controller.request(request, maximumWait: .seconds(1)) }
        await Task.yield()

        let duplicate = await controller.request(request, maximumWait: .zero)
        XCTAssertNil(duplicate)
        let stale = AgentSessionInstanceID(
            sessionID: request.key.session.sessionID,
            generation: AgentSessionGeneration(rawValue: request.key.session.generation.rawValue + 1)
        )
        XCTAssertEqual(
            controller.resolve(session: stale, requestID: request.key.requestID, decision: .allow),
            .missing
        )
        XCTAssertNotNil(controller.pendingRequest(for: request.key.session))
        controller.cancelAll()
        let result = await waiter.value
        XCTAssertNil(result)
    }

    func testExpiredRequestAndTimeoutNeverApprove() async {
        let current = now
        let controller = AgentApprovalController(now: { current })
        let expired = makeRequest(id: "expired", expiresAt: now.addingTimeInterval(-1))
        let expiredResult = await controller.request(expired, maximumWait: .seconds(1))
        XCTAssertNil(expiredResult)
        XCTAssertEqual(
            controller.resolve(
                session: expired.key.session,
                requestID: expired.key.requestID,
                decision: .allow
            ),
            .missing
        )

        let pending = makeRequest(id: "timeout")
        let result = await controller.request(pending, maximumWait: .milliseconds(1))
        XCTAssertNil(result)
        XCTAssertNil(controller.pendingRequest(for: pending.key.session))
    }

    func testBridgeShutdownReturnsNoDecision() async {
        let current = now
        let controller = AgentApprovalController(now: { current })
        let request = makeRequest(id: "shutdown")
        let waiter = Task { await controller.request(request, maximumWait: .seconds(1)) }
        await Task.yield()
        controller.cancelAll()
        let result = await waiter.value
        XCTAssertNil(result)
    }

    func testResolvedChoiceRemainsPresentedUntilProviderDeliveryIsConfirmed() async {
        let current = now
        let controller = AgentApprovalController(now: { current })
        let request = makeRequest(id: "delivery")
        let waiter = Task { await controller.request(request, maximumWait: .seconds(1)) }
        await Task.yield()

        XCTAssertEqual(
            controller.resolve(
                session: request.key.session,
                requestID: request.key.requestID,
                decision: .allow
            ),
            .accepted
        )
        let decision = await waiter.value
        XCTAssertEqual(decision, .allow)
        XCTAssertNil(controller.pendingRequest(for: request.key.session))
        XCTAssertEqual(controller.presentedRequest(for: request.key.session), request)
        XCTAssertEqual(controller.deliveryState(for: request.key), .submitting(.allow))
        XCTAssertEqual(
            controller.resolve(
                session: request.key.session,
                requestID: request.key.requestID,
                decision: .allow
            ),
            .missing
        )

        controller.confirmDelivery(request.key)
        XCTAssertNil(controller.presentedRequest(for: request.key.session))
    }

    func testWithdrawReturnsNoDecisionAndStaysOneShot() async {
        let current = now
        let controller = AgentApprovalController(now: { current })
        let request = makeRequest(id: "withdrawn")
        let waiter = Task { await controller.request(request, maximumWait: .seconds(1)) }
        await Task.yield()

        XCTAssertEqual(controller.withdraw(session: request.key.session, requestID: request.key.requestID), .accepted)
        let decision = await waiter.value
        XCTAssertNil(decision, "Withdrawal is never a decision")
        XCTAssertNil(controller.deliveryState(for: request.key))
        XCTAssertNil(controller.presentedRequest(for: request.key.session))
        XCTAssertEqual(
            controller.resolve(session: request.key.session, requestID: request.key.requestID, decision: .allow),
            .missing
        )
        XCTAssertEqual(controller.withdraw(session: request.key.session, requestID: request.key.requestID), .missing)
        XCTAssertTrue(controller.hasHandled(request.key))
        let replay = await controller.request(request, maximumWait: .seconds(1))
        XCTAssertNil(replay)

        controller.forgetHandledRequests(for: request.key.session.sessionID)
        XCTAssertFalse(controller.hasHandled(request.key))
    }

    private func makeRequest(
        id: String,
        expiresAt: Date? = nil
    ) -> AgentApprovalControlRequest {
        let session = AgentSessionInstanceID(
            sessionID: AgentSessionID(provider: .codex, nativeID: "session"),
            generation: AgentSessionGeneration(rawValue: 4)
        )
        return AgentApprovalControlRequest(
            key: AgentApprovalControlKey(
                session: session,
                requestID: AgentCorrelationID(rawValue: id)
            ),
            summary: "$ git push origin feature/agents-ui-overhaul",
            expiresAt: expiresAt ?? now.addingTimeInterval(75)
        )
    }
}
