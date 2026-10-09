import XCTest
@testable import DynamicIsland

@MainActor
final class AgentPriorityRegressionTests: XCTestCase {
    func testOrdinaryAgentPriorityFlowsThroughSelectorAndPresentationPolicy() {
        let activities = [activity(.agent), activity(.media), activity(.timer)]
        let toggles = CollapsedLiveActivitySourceToggles(liveActivitiesEnabled: true, timerEnabled: true,
            mediaEnabled: true, fileTrayEnabled: true, batteryEnabled: true, agentEnabled: true)
        var priorities = CollapsedLiveActivityPrioritySettings.defaults
        func ordered() -> [DynamicIslandLiveActivity] {
            CollapsedLiveActivitySelector.previewActivities(activities: activities, priorities: priorities,
                toggles: toggles, maxCount: 3)
        }
        func primary(_ kinds: Set<DynamicIslandLiveActivityKind>) -> DynamicIslandLiveActivityKind? {
            LiveActivityLayoutResolver.resolve(activities: ordered().filter { kinds.contains($0.kind) },
                context: LiveActivityLayoutContext(availableWidth: 900, hasHardwareNotch: true,
                    hardwareNotchWidth: 186)).primary?.activity.kind
        }
        XCTAssertEqual(priorities.agent, 130)
        XCTAssertEqual(primary([.agent, .media]), .agent)
        XCTAssertEqual(ordered().map(\.kind), [.agent, .timer, .media])
        priorities.agent = 100
        XCTAssertEqual(primary([.agent, .media]), .agent, "Configured Agent 100 beats Media 90")
        priorities.agent = 80
        XCTAssertEqual(ordered().map(\.kind), [.timer, .media, .agent])
        XCTAssertEqual(primary([.agent, .media]), .media)
        XCTAssertEqual(primary([.agent, .timer]), .timer)
        priorities.agent = 160
        let projected = ordered()
        XCTAssertEqual(projected.map(\.kind), [.agent, .timer, .media])
        XCTAssertEqual(projected.first?.priority, 160)
        XCTAssertEqual(primary([.agent, .timer]), .agent)
        XCTAssertEqual(primary([.media, .timer]), .media, "Existing Media/Timer coexistence is preserved")
        XCTAssertEqual(CollapsedLiveActivitySelector.select(activities: activities, priorities: priorities,
            toggles: toggles), .agent(activities[0]))
        var disabled = toggles
        disabled.agentEnabled = false
        XCTAssertFalse(CollapsedLiveActivitySelector.previewActivities(activities: activities,
            priorities: priorities, toggles: disabled).contains { $0.kind == .agent })
        XCTAssertFalse(LiveActivityRuntimeProjection.activities(stored: activities, priorities: priorities,
            toggles: toggles, agentSessions: [], agentEnabled: false).contains { $0.kind == .agent })
    }

    func testPriorityPersistsNormalizesAndResetsWithoutEnablingAgents() throws {
        let suite = "AgentPriorityRegression-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.agentActivityEnabled = false
        settings.collapsedPriorityAgent = 80
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.collapsedPriorityAgent, 80)
        XCTAssertFalse(restored.agentActivityEnabled)
        restored.collapsedPriorityAgent = -1
        XCTAssertEqual(restored.collapsedPriorityAgent, 0)
        restored.collapsedPriorityAgent = 301
        XCTAssertEqual(restored.collapsedPriorityAgent, CollapsedLiveActivityPrioritySettings.range.upperBound)
        restored.resetCollapsedLiveActivityPrioritySettings()
        XCTAssertEqual(restored.collapsedPriorityAgent, 130)
        XCTAssertFalse(restored.agentActivityEnabled)
        XCTAssertEqual(AppSettings(defaults: defaults).collapsedPriorityAgent, 130)
        XCTAssertEqual(CollapsedLiveActivityPrioritySource.agent.displayName, "Agent Activity")
    }

    private func activity(_ kind: DynamicIslandLiveActivityKind) -> DynamicIslandLiveActivity {
        .init(id: kind.rawValue, kind: kind, title: kind.rawValue, subtitle: nil, symbolName: "cpu",
            priority: 0, isActive: true, progress: nil, updatedAt: Date(timeIntervalSince1970: 1000))
    }
}
