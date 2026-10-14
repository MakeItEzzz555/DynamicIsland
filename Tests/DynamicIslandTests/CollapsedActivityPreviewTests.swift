import XCTest
@testable import DynamicIsland

/// Contextual collapsed previews read existing state only, stay small, keep
/// agent commands private, and never outrank approvals or message replies.
@MainActor
final class CollapsedActivityPreviewTests: XCTestCase {
    private func activity(_ kind: DynamicIslandLiveActivityKind, title: String = "T", subtitle: String? = nil,
                          progress: Double? = nil, battery: BatteryLiveActivityState? = nil) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(id: kind.rawValue, kind: kind, title: title, subtitle: subtitle, symbolName: "circle",
                                  priority: 1, isActive: true, progress: progress, updatedAt: Date(), batteryState: battery)
    }

    func testMediaPreviewShowsTimesOnlyWhenTheSourceReportsProgress() {
        let timed = CollapsedActivityPreview.make(kind: .media, activity: activity(.media),
            media: .init(title: "Versatile", artist: "Kodak Black", position: 79, duration: 418, hasProgress: true),
            agent: nil, deviceName: "Mac")
        XCTAssertEqual(timed, .media(title: "Versatile", artist: "Kodak Black", elapsed: "1:19", remaining: "-5:39"))
        let untimed = CollapsedActivityPreview.make(kind: .media, activity: activity(.media),
            media: .init(title: "Live Radio", artist: "Station", position: 0, duration: 1, hasProgress: false),
            agent: nil, deviceName: "Mac")
        XCTAssertEqual(untimed, .media(title: "Live Radio", artist: "Station", elapsed: nil, remaining: nil))
    }

    func testBatteryAndTimerUseTheLiveActivityAsIs() {
        XCTAssertEqual(CollapsedActivityPreview.make(kind: .battery, activity: activity(.battery, progress: 0.42, battery: .charging),
                                                     media: nil, agent: nil, deviceName: "Studio Mac"),
                       .battery(device: "Studio Mac", percentage: 42, state: .charging))
        XCTAssertNil(CollapsedActivityPreview.make(kind: .battery, activity: activity(.battery), media: nil, agent: nil, deviceName: "Mac"),
                     "no battery state, no preview")
        XCTAssertEqual(CollapsedActivityPreview.make(kind: .timer, activity: activity(.timer, title: "Focus", subtitle: "12:30"),
                                                     media: nil, agent: nil, deviceName: "Mac"),
                       .timer(title: "Focus", detail: "12:30"))
        XCTAssertNil(CollapsedActivityPreview.make(kind: .fileTray, activity: activity(.fileTray), media: nil, agent: nil, deviceName: "Mac"))
    }

    func testAgentPreviewShowsOnlyTheExecutableNameNeverArgumentsOrPaths() {
        var session = SettingsPreviewFixtures.agentSession(provider: .codex)
        let id = AgentCorrelationID(rawValue: "cmd")
        session.commands[id] = AgentCommand(correlationID: id, displaySummary: "/usr/bin/curl -H 'Authorization: Bearer sk-secret' https://x",
                                            status: .active, startedAt: Date())
        XCTAssertEqual(CollapsedActivityPreview.safeActivity(of: session), "curl")
        guard case let .agent(name, provider, _, activity)? = CollapsedActivityPreview.make(
            kind: .agent, activity: activity(.agent), media: nil, agent: session, deviceName: "Mac") else { return XCTFail() }
        XCTAssertEqual(name, "Preview project")
        XCTAssertEqual(provider, .codex)
        XCTAssertEqual(activity, "curl")
        // No running command: the running tool's name; nothing running: nil.
        session.commands = [:]
        XCTAssertEqual(CollapsedActivityPreview.safeActivity(of: session), "Read")
        session.tools = [:]
        XCTAssertNil(CollapsedActivityPreview.safeActivity(of: session))
    }

    func testPolicyGrowsByThePreviewAndApprovalsAndRepliesStillWin() {
        let preview = CollapsedActivityPreview.timer(title: "Focus", detail: "1:00")
        let policy = CollapsedActivityHoverPolicy.resolve(kind: .timer, activityPreview: preview)
        XCTAssertEqual(policy, .activityPreview(height: preview.height))
        let base = CGRect(x: 100, y: 500, width: 220, height: 32)
        XCTAssertEqual(policy.frame(from: base).height, 32 + preview.height)
        XCTAssertEqual(policy.frame(from: base).maxY, base.maxY, "grows downward from the notch")
        XCTAssertFalse(policy.allowsAutomaticExpansion(enabled: true), "a preview replaces whole-island hover expansion")
        XCTAssertEqual(CollapsedActivityHoverPolicy.resolve(kind: .timer, exactAgentApproval: true, activityPreview: preview),
                       .interactive(requiredHeight: CollapsedActivityHoverPolicy.agentApprovalHeight))
        XCTAssertEqual(CollapsedActivityHoverPolicy.resolve(kind: .message, activityPreview: preview), .peek)
        XCTAssertEqual(CollapsedActivityHoverPolicy.resolve(kind: .media), .none, "previews disabled keeps the old behavior")
    }

    func testPreviewHitAreaCoversTheSidecarsSoHoveringThemCannotCloseIt() {
        let policy = CollapsedActivityHoverPolicy.activityPreview(height: 48)
        let base = CGRect(x: 400, y: 500, width: 200, height: 32)
        let composite = CGRect(x: 300, y: 500, width: 420, height: 32)
        let frame = policy.frame(from: base, including: composite)
        XCTAssertEqual(frame.minX, 300); XCTAssertEqual(frame.maxX, 720)
        XCTAssertEqual(frame.height, 80); XCTAssertEqual(frame.maxY, base.maxY)
        XCTAssertTrue(frame.contains(CGPoint(x: 310, y: 520)), "a pointer on the leading sidecar stays inside")
        XCTAssertEqual(policy.frame(from: base, including: .zero), policy.frame(from: base))
        XCTAssertEqual(CollapsedActivityHoverPolicy.peek.frame(from: base, including: composite),
                       CollapsedActivityHoverPolicy.peek.frame(from: base), "message peeks keep their geometry")
    }

    func testPreviewsStaySmall() {
        for preview: CollapsedActivityPreview in [
            .media(title: "a", artist: "b", elapsed: nil, remaining: nil), .timer(title: "t", detail: nil),
            .battery(device: "d", percentage: 1, state: .low), .agent(name: "n", provider: .claude, status: "s", activity: nil),
        ] {
            XCTAssertLessThanOrEqual(preview.height, 70)
        }
    }

    func testRoutineAgentPillIsOrbsOnly() throws {
        let one = SettingsPreviewFixtures.agentSession(provider: .codex)
        let single = try XCTUnwrap(AgentCompactPresentation.make(sessions: [one]))
        XCTAssertEqual(AgentCompactOrbMetrics.trailingWidth(for: single), 16, "one session: a single state glyph")
        let profile = try XCTUnwrap(AgentCollapsedShellPresentation.routine(sessions: [one], enabled: true)?.contentProfile)
        XCTAssertEqual(profile.leftContentWidth, AgentCompactOrbMetrics.leadingWidth)
        XCTAssertLessThan(profile.leftContentWidth, 62, "narrower than the old name-based minimum")
        XCTAssertLessThan(profile.rightContentWidth, 62, "narrower than the old state-label minimum")
    }
}
