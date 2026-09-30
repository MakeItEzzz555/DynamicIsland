import Foundation
import XCTest
@testable import DynamicIsland

final class AgentUsageTelemetryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)

    private var codexAccount: AgentUsage {
        AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): sample(38, limit: 100, scope: "5h", source: "codex-account-rate-limits"),
            AgentUsageKey(metric: .quotaUsed, scope: "weekly"): sample(71, limit: 100, scope: "weekly", source: "codex-account-rate-limits")
        ])
    }

    func testCodexAccountWindowsAreRemainingAndAccountScoped() {
        let indicators = AgentUsageIndicatorPresentation.make(
            provider: .codex, accountUsage: codexAccount, selectedSession: nil, now: now
        )
        let fiveHour = indicators[0]
        let week = indicators[1]

        XCTAssertEqual(fiveHour.kind, .fiveHour)
        XCTAssertEqual(fiveHour.direction, .remaining)
        XCTAssertEqual(fiveHour.scope, .account)
        XCTAssertEqual(fiveHour.fraction!, 0.62, accuracy: 0.0001)
        XCTAssertEqual(fiveHour.valueText, "62%")
        XCTAssertEqual(fiveHour.authority, .providerAPI)
        XCTAssertEqual(week.fraction!, 0.29, accuracy: 0.0001)
        XCTAssertEqual(week.direction, .remaining)
    }

    func testCodexContextIsSelectedThreadUsedAndWindowsIgnoreSelection() {
        let threadA = session("a", provider: .codex, contextUsed: 50_000, limit: 200_000)
        let threadB = session("b", provider: .codex, contextUsed: 150_000, limit: 200_000)

        let withA = AgentUsageIndicatorPresentation.make(provider: .codex, accountUsage: codexAccount, selectedSession: threadA, now: now)
        let withB = AgentUsageIndicatorPresentation.make(provider: .codex, accountUsage: codexAccount, selectedSession: threadB, now: now)

        XCTAssertEqual(withA[0], withB[0], "5h does not change with thread selection")
        XCTAssertEqual(withA[1], withB[1], "Week does not change with thread selection")
        XCTAssertEqual(withA[2].scope, .thread)
        XCTAssertEqual(withA[2].direction, .used)
        XCTAssertEqual(withA[2].fraction!, 0.25, accuracy: 0.0001)
        XCTAssertEqual(withB[2].fraction!, 0.75, accuracy: 0.0001)
    }

    func testClaudeShowsOnlyAuthoritativeContextAndMarksAccountWindowsUnavailable() {
        let claude = session("c", provider: .claude, contextUsed: 490_583, limit: nil, source: "claude-transcript")
        let indicators = AgentUsageIndicatorPresentation.make(
            provider: .claude, accountUsage: AgentUsage(), selectedSession: claude, now: now
        )

        XCTAssertEqual(indicators[0].authority, .unavailable)
        XCTAssertEqual(indicators[0].unavailableReason, AgentUsageIndicatorPresentation.claudeAccountUnavailableReason)
        XCTAssertNil(indicators[0].fraction)
        XCTAssertEqual(indicators[0].valueText, "—")
        XCTAssertEqual(indicators[1].authority, .unavailable)

        let context = indicators[2]
        XCTAssertEqual(context.authority, .providerTranscript)
        XCTAssertNil(context.fraction, "No context-window limit is reported, so no percentage")
        XCTAssertEqual(context.absoluteValue, 490_583)
        XCTAssertEqual(context.valueText, "491k")
        XCTAssertEqual(context.direction, .used)
    }

    func testProvidersNeverCrossContaminate() {
        let codexThread = session("a", provider: .codex, contextUsed: 50_000, limit: 200_000)
        let claudeView = AgentUsageIndicatorPresentation.make(
            provider: .claude, accountUsage: AgentUsage(), selectedSession: codexThread, now: now
        )
        XCTAssertTrue(claudeView.allSatisfy { !$0.isAvailable })
        XCTAssertTrue(claudeView.allSatisfy { $0.provider == .claude })

        let claudeThread = session("c", provider: .claude, contextUsed: 1_000, limit: nil, source: "claude-transcript")
        let codexView = AgentUsageIndicatorPresentation.make(
            provider: .codex, accountUsage: codexAccount, selectedSession: claudeThread, now: now
        )
        XCTAssertFalse(codexView[2].isAvailable, "Claude context never appears under Codex")
    }

    func testUnavailableIsNeverZeroOrFull() {
        let indicators = AgentUsageIndicatorPresentation.make(
            provider: .codex, accountUsage: AgentUsage(), selectedSession: nil, now: now
        )
        for indicator in indicators {
            XCTAssertNil(indicator.fraction)
            XCTAssertNil(indicator.absoluteValue)
            XCTAssertEqual(indicator.freshness, .unavailable)
            XCTAssertEqual(indicator.valueText, "—")
            XCTAssertTrue(indicator.accessibilityDescription.contains("unavailable"))
        }
    }

    func testQuotaWithoutLimitIsUnavailable() {
        let usage = AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): sample(38, limit: nil, scope: "5h", source: "x")
        ])
        let indicators = AgentUsageIndicatorPresentation.make(provider: .codex, accountUsage: usage, selectedSession: nil, now: now)
        XCTAssertFalse(indicators[0].isAvailable)
    }

    func testFreshnessTransitions() {
        XCTAssertEqual(AgentUsageIndicatorPresentation.freshness(observedAt: now, scope: .account, now: now), .live)
        XCTAssertEqual(AgentUsageIndicatorPresentation.freshness(observedAt: now.addingTimeInterval(-600), scope: .account, now: now), .recent)
        XCTAssertEqual(AgentUsageIndicatorPresentation.freshness(observedAt: now.addingTimeInterval(-3_600), scope: .account, now: now), .stale)
        XCTAssertEqual(AgentUsageIndicatorPresentation.freshness(observedAt: now.addingTimeInterval(-60), scope: .thread, now: now), .live)
        XCTAssertEqual(AgentUsageIndicatorPresentation.freshness(observedAt: now.addingTimeInterval(-600), scope: .thread, now: now), .recent)
        XCTAssertEqual(AgentUsageIndicatorPresentation.freshness(observedAt: now.addingTimeInterval(-3_600), scope: .thread, now: now), .stale)

        var old = codexAccount
        old = AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                value: 10, limit: 100, unit: .fraction, scope: "5h", source: "codex", observedAt: now.addingTimeInterval(-7_200)
            )
        ])
        let stale = AgentUsageIndicatorPresentation.make(provider: .codex, accountUsage: old, selectedSession: nil, now: now)[0]
        XCTAssertEqual(stale.freshness, .stale)
        XCTAssertTrue(stale.accessibilityDescription.hasSuffix("stale"))
    }

    func testCompactTokenFormatting() {
        XCTAssertEqual(AgentUsageIndicator.compactTokens(950), "950")
        XCTAssertEqual(AgentUsageIndicator.compactTokens(84_200), "84k")
        XCTAssertEqual(AgentUsageIndicator.compactTokens(1_260_000), "1.3M")
    }

    func testClaudeTranscriptContextExcludesSidechains() {
        let object: [String: Any] = [
            "input_tokens": 2,
            "cache_creation_input_tokens": 2_406,
            "cache_read_input_tokens": 488_175,
            "output_tokens": 945
        ]
        let main = ClaudeTranscriptRecoveryParser.usage(object, observedAt: now)
        XCTAssertEqual(main?[.contextUsed]?.value, 490_583)
        XCTAssertNil(main?[.contextUsed]?.limit)
        XCTAssertEqual(main?[.contextUsed]?.source, "claude-transcript")

        let sidechain = ClaudeTranscriptRecoveryParser.usage(object, observedAt: now, isSidechain: true)
        XCTAssertNil(sidechain?[.contextUsed])
        XCTAssertEqual(sidechain?[.outputTokens]?.value, 945)
    }

    // MARK: Helpers

    private func sample(_ value: Double, limit: Double?, scope: String, source: String) -> AgentUsageSample {
        AgentUsageSample(value: value, limit: limit, unit: .fraction, scope: scope, source: source, observedAt: now)
    }

    private func session(
        _ nativeID: String,
        provider: AgentProvider,
        contextUsed: Double,
        limit: Double?,
        source: String = "codex-thread-token-usage"
    ) -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: provider, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: .working,
            project: AgentProjectContext(displayName: "p"),
            capabilities: AgentCapabilities(),
            usage: AgentUsage(scopedSamples: [
                AgentUsageKey(metric: .contextUsed, scope: "context"): AgentUsageSample(
                    value: contextUsed, limit: limit, unit: .tokens, scope: "context", source: source, observedAt: now
                )
            ]),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: now,
            endedAt: nil,
            lastUpdatedAt: now,
            availability: .loaded
        )
    }
}
