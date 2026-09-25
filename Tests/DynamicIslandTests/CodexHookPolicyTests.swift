import XCTest
@testable import DynamicIsland

final class CodexHookPolicyTests: XCTestCase {
    func testCodexHookPolicyIsProviderAndSourceScoped() {
        let policy = AgentProducerPolicy.codexOfficialHook
        XCTAssertTrue(policy.permits(provider: .codex))
        XCTAssertFalse(policy.permits(provider: .claude))
        XCTAssertTrue(policy.permits(source: .unknown))
        XCTAssertFalse(policy.permits(source: .terminal))
        XCTAssertTrue(policy.allowedSourceKinds.contains(.officialHook))
        XCTAssertFalse(policy.allowedCapabilities.contains(.approvalControl))
        XCTAssertFalse(policy.allowedCapabilities.contains(.verifiedSourceIdentity))
    }

    func testCodexHookPolicyAllowsOnlyObservedHookCapabilities() {
        let policy = AgentProducerPolicy.codexOfficialHook
        XCTAssertTrue(policy.allowedCapabilities.contains(.sessionLifecycle))
        XCTAssertTrue(policy.allowedCapabilities.contains(.toolLifecycle))
        XCTAssertTrue(policy.allowedCapabilities.contains(.commandLifecycle))
        XCTAssertTrue(policy.allowedCapabilities.contains(.approvalObservation))
        XCTAssertTrue(policy.allowedCapabilities.contains(.subagentLifecycle))
        XCTAssertTrue(policy.allowedCapabilities.contains(.taskLifecycle))
        XCTAssertFalse(policy.allowedCapabilities.contains(.tokenUsage))
        XCTAssertFalse(policy.allowedCapabilities.contains(.quotaUsage))
    }
}
