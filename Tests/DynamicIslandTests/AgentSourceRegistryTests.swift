import XCTest
@testable import DynamicIsland

final class AgentSourceRegistryTests: XCTestCase {
    func testRegistrationStartsHealthAndReplacementAdvancesEpoch() throws {
        var registry = AgentSourceRegistry()
        let descriptor = AgentIngestionTestSupport.descriptor("hook")
        let policy = AgentIngestionTestSupport.policy(kinds: [.officialLifecycleProtocol])
        let first = try registry.register(descriptor: descriptor, policy: policy, authenticatedProducerID: "first")
        let second = try registry.register(descriptor: descriptor, policy: policy, authenticatedProducerID: "second")

        XCTAssertEqual(first.epoch.rawValue, 1)
        XCTAssertEqual(second.epoch.rawValue, 2)
        XCTAssertEqual(registry.activeHealth.single?.state, .starting)
        XCTAssertEqual(registry.healthHistory.single?.state, .stopped)
        XCTAssertThrowsError(try registry.registration(for: first))
    }

    func testAcceptedRejectedFailureAndStopHealthAreIndependentOfAgentState() throws {
        var registry = AgentSourceRegistry()
        let descriptor = AgentIngestionTestSupport.descriptor("health")
        let policy = AgentIngestionTestSupport.policy(kinds: [.officialLifecycleProtocol])
        let handle = try registry.register(descriptor: descriptor, policy: policy, authenticatedProducerID: "health")
        try registry.recordAccepted(2, at: AgentIngestionTestSupport.now, for: handle)
        XCTAssertEqual(registry.activeHealth.single?.state, .healthy)
        XCTAssertEqual(registry.activeHealth.single?.acceptedCount, 2)
        try registry.recordRejected(.policyRejected, dropped: 3, for: handle)
        XCTAssertEqual(registry.activeHealth.single?.state, .degraded)
        XCTAssertEqual(registry.activeHealth.single?.dropCount, 3)
        try registry.updateHealth(.failed, error: .producerFailure, for: handle)
        XCTAssertEqual(registry.activeHealth.single?.state, .failed)
        try registry.unregister(handle)
        XCTAssertTrue(registry.activeHealth.isEmpty)
        XCTAssertEqual(registry.healthHistory.last?.state, .stopped)
        XCTAssertThrowsError(try registry.updateHealth(.healthy, error: nil, for: handle))
    }

    func testRegistryBoundRejectsNoiseWithoutEvictingActiveSources() throws {
        var registry = AgentSourceRegistry()
        let policy = AgentIngestionTestSupport.policy(kinds: [.officialHook])
        for index in 0..<AgentIngestionLimits.maximumRegisteredProducers {
            _ = try registry.register(
                descriptor: AgentIngestionTestSupport.descriptor("source-\(index)", kind: .officialHook),
                policy: policy,
                authenticatedProducerID: "auth-\(index)"
            )
        }
        XCTAssertThrowsError(try registry.register(
            descriptor: AgentIngestionTestSupport.descriptor("overflow", kind: .officialHook),
            policy: policy,
            authenticatedProducerID: "overflow"
        ))
        XCTAssertEqual(registry.activeHealth.count, AgentIngestionLimits.maximumRegisteredProducers)
    }

    func testRegistrationRejectsDescriptorPolicySourceKindMismatch() {
        var registry = AgentSourceRegistry()
        XCTAssertThrowsError(try registry.register(
            descriptor: AgentIngestionTestSupport.descriptor("mismatch", kind: .structuredTelemetry),
            policy: AgentIngestionTestSupport.policy(kinds: [.officialHook]),
            authenticatedProducerID: "mismatch"
        ))
        XCTAssertTrue(registry.activeHealth.isEmpty)
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
