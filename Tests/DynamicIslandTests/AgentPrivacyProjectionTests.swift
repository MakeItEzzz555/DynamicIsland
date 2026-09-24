import XCTest
@testable import DynamicIsland

final class AgentPrivacyProjectionTests: XCTestCase {
    func testSummaryNormalizesWhitespaceAndBoundsHugeInput() {
        XCTAssertEqual(AgentPrivacyProjection.summary("  hello\n\tworld  "), "hello world")

        let projected = AgentPrivacyProjection.summary(String(repeating: "x", count: 20_000))

        XCTAssertEqual(projected?.count, AgentDomainLimits.summaryLength)
        XCTAssertTrue(projected?.hasSuffix("…") == true)
    }

    func testCommandProjectionRetainsOnlyExecutableBasename() {
        let projected = AgentPrivacyProjection.commandSummary(
            executable: "/usr/bin/curl https://example.com?token=secret --header Authorization:secret"
        )

        XCTAssertEqual(projected, "curl")
        XCTAssertFalse(projected.contains("secret"))
        XCTAssertFalse(projected.contains("example.com"))
    }

    func testMissingCommandNameUsesNonSensitiveFallback() {
        XCTAssertEqual(AgentPrivacyProjection.commandSummary(executable: nil), "Running command")
        XCTAssertEqual(AgentPrivacyProjection.commandSummary(executable: "   "), "Running command")
    }

    func testDisplayProjectOmitsPathRepositoryAndCommit() {
        let raw = AgentProjectContext(
            displayName: "DynamicIsland",
            workingDirectory: "/Users/private/secret-project",
            repositoryIdentity: "private/repository",
            gitBranch: "feature",
            gitCommit: "deadbeef",
            model: "model",
            sourceApplication: AgentSourceApplication(
                displayName: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )
        )

        let projected = AgentPrivacyProjection.displayProject(raw)

        XCTAssertEqual(projected.displayName, "DynamicIsland")
        XCTAssertEqual(projected.gitBranch, "feature")
        XCTAssertEqual(projected.model, "model")
        XCTAssertEqual(projected.sourceApplicationName, "Terminal")
        XCTAssertFalse(String(reflecting: projected).contains("/Users/private"))
        XCTAssertFalse(String(reflecting: projected).contains("deadbeef"))
    }

    func testProjectProjectionRejectsRelativePathAndBoundsMetadata() {
        let projected = AgentPrivacyProjection.project(AgentProjectContext(
            displayName: String(repeating: "p", count: 2_000),
            workingDirectory: "relative/private/path",
            repositoryIdentity: String(repeating: "r", count: 2_000)
        ))

        XCTAssertNil(projected.workingDirectory)
        XCTAssertEqual(projected.displayName?.count, AgentDomainLimits.titleLength)
        XCTAssertEqual(projected.repositoryIdentity?.count, AgentDomainLimits.identifierLength)
    }

    func testReducerStoresBoundedToolMetadataWithoutOutputFields() throws {
        let id = AgentTestFixture.sessionID(.codex, "privacy-tool")
        let start = AgentTestFixture.event(
            "start",
            sessionID: id,
            type: .sessionStarted,
            offset: 0,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil))
        )
        let started = try XCTUnwrap(AgentEventReducer.reduce(session: nil, event: start).session)
        let huge = String(repeating: "sensitive-output-", count: 2_000)
        let tool = AgentTestFixture.event(
            "tool",
            sessionID: id,
            type: .toolStarted,
            offset: 1,
            correlationID: "tool",
            payload: .tool(AgentToolEvent(
                name: String(repeating: "n", count: 2_000),
                category: "filesystem",
                summary: huge,
                success: nil
            ))
        )

        let reduced = try XCTUnwrap(AgentEventReducer.reduce(session: started, event: tool).session)
        let stored = try XCTUnwrap(reduced.tools[AgentTestFixture.correlation("tool")])

        XCTAssertEqual(stored.name.count, AgentDomainLimits.titleLength)
        XCTAssertEqual(stored.summary?.count, AgentDomainLimits.summaryLength)
        XCTAssertFalse(String(reflecting: stored).contains(huge))
    }

    func testOutOfOrderPendingOperationIsSanitizedBeforeRetention() throws {
        let id = AgentTestFixture.sessionID(.codex, "pending-privacy")
        let start = AgentTestFixture.event(
            "start-pending",
            sessionID: id,
            type: .sessionStarted,
            offset: 0,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil))
        )
        let started = try XCTUnwrap(AgentEventReducer.reduce(session: nil, event: start).session)
        let huge = String(repeating: "private-output-", count: 2_000)
        let completion = AgentTestFixture.event(
            "early-completion",
            sessionID: id,
            type: .toolCompleted,
            offset: 1,
            correlationID: "pending-tool",
            payload: .tool(AgentToolEvent(name: nil, category: nil, summary: huge, success: true))
        )

        let reduced = try XCTUnwrap(AgentEventReducer.reduce(session: started, event: completion).session)
        let pendingKey = AgentPendingOperationKey(
            kind: .tool,
            correlationID: AgentTestFixture.correlation("pending-tool")
        )
        guard case .tool(let pending, _)? = reduced.pendingOperations[pendingKey] else {
            return XCTFail("Expected bounded pending tool completion")
        }
        XCTAssertEqual(pending.summary?.count, AgentDomainLimits.summaryLength)
        XCTAssertFalse(String(reflecting: pending).contains(huge))
    }

    func testUsageKeepsOnlyExplicitSamplesAndDoesNotInventLimit() {
        let sample = AgentUsageSample(
            value: 12,
            limit: nil,
            unit: .tokens,
            scope: "turn",
            source: "protocol",
            observedAt: AgentTestFixture.baseDate
        )
        let usage = AgentUsage(samples: [.inputTokens: sample])

        XCTAssertEqual(usage[.inputTokens]?.value, 12)
        XCTAssertNil(usage[.inputTokens]?.limit)
        XCTAssertNil(usage[.contextLimit])
        XCTAssertNil(usage[.quotaLimit])
        XCTAssertNil(usage[.cost])
    }

    func testInvalidUsageIsRejectedBeforeStorage() {
        let id = AgentTestFixture.sessionID(.codex, "invalid-usage")
        let invalid = AgentUsageSample(
            value: .infinity,
            limit: nil,
            unit: .tokens,
            scope: "turn",
            source: "provider",
            observedAt: AgentTestFixture.baseDate
        )
        let event = AgentTestFixture.event(
            "invalid",
            sessionID: id,
            type: .usageUpdated,
            offset: 0,
            payload: .usage(AgentUsage(samples: [.inputTokens: invalid]))
        )

        XCTAssertEqual(event.validationError(), .invalidUsage)
    }

    func testUsageProvenanceStringsAreBoundedBeforeStorage() throws {
        let huge = String(repeating: "sensitive ", count: 1_000)
        let usage = AgentUsage(samples: [
            .inputTokens: AgentUsageSample(
                value: 42,
                limit: nil,
                unit: .tokens,
                scope: huge,
                source: huge,
                observedAt: AgentTestFixture.baseDate
            )
        ])
        let sessionID = AgentTestFixture.sessionID(.codex, "privacy-usage")
        let start = AgentTestFixture.event(
            "start",
            sessionID: sessionID,
            type: .sessionStarted,
            offset: 0,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil))
        )
        let event = AgentTestFixture.event(
            "usage",
            sessionID: sessionID,
            type: .usageUpdated,
            offset: 1,
            payload: .usage(usage)
        )

        var session = try XCTUnwrap(AgentEventReducer.reduce(session: nil, event: start).session)
        session = try XCTUnwrap(AgentEventReducer.reduce(session: session, event: event).session)
        let sample = try XCTUnwrap(session.usage[.inputTokens])

        XCTAssertLessThanOrEqual(sample.scope.count, AgentDomainLimits.titleLength)
        XCTAssertLessThanOrEqual(sample.source.count, AgentDomainLimits.titleLength)
        XCTAssertFalse(sample.scope.contains(huge))
        XCTAssertFalse(sample.source.contains(huge))
    }

    func testInvalidNestedApprovalCorrelationIsRejected() {
        let event = AgentTestFixture.event(
            "approval",
            sessionID: AgentTestFixture.sessionID(.codex, "privacy-approval"),
            type: .approvalRequested,
            offset: 1,
            correlationID: "request",
            payload: .approvalRequest(AgentApprovalRequest(
                summary: "Approve?",
                operationCorrelationID: AgentCorrelationID(rawValue: String(repeating: "x", count: 300)),
                expiresAt: nil
            ))
        )

        XCTAssertEqual(event.validationError(), .invalidCorrelationID)
    }
}
