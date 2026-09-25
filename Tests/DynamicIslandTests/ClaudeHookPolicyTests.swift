import XCTest
@testable import DynamicIsland

final class ClaudeHookPolicyTests: XCTestCase {
    func testClaudeHookPolicyIsProviderAndSourceScoped() {
        let policy = AgentProducerPolicy.claudeOfficialHook
        XCTAssertTrue(policy.permits(provider: .claude))
        XCTAssertFalse(policy.permits(provider: .codex))
        XCTAssertTrue(policy.permits(source: .unknown))
        XCTAssertFalse(policy.permits(source: .terminal))
        XCTAssertTrue(policy.allowedSourceKinds.contains(.officialHook))
        XCTAssertFalse(policy.allowedCapabilities.contains(.approvalControl))
        XCTAssertFalse(policy.allowedCapabilities.contains(.verifiedSourceIdentity))
    }

    func testClaudeHookPolicyAllowsObservedLifecycleOnly() {
        let policy = AgentProducerPolicy.claudeOfficialHook
        XCTAssertTrue(policy.allowedCapabilities.contains(.sessionLifecycle))
        XCTAssertTrue(policy.allowedCapabilities.contains(.toolLifecycle))
        XCTAssertTrue(policy.allowedCapabilities.contains(.commandLifecycle))
        XCTAssertTrue(policy.allowedCapabilities.contains(.approvalObservation))
        XCTAssertTrue(policy.allowedCapabilities.contains(.userInputObservation))
        XCTAssertTrue(policy.allowedCapabilities.contains(.subagentLifecycle))
        XCTAssertTrue(policy.allowedCapabilities.contains(.taskLifecycle))
        XCTAssertFalse(policy.allowedCapabilities.contains(.tokenUsage))
        XCTAssertFalse(policy.allowedCapabilities.contains(.quotaUsage))
    }
}
