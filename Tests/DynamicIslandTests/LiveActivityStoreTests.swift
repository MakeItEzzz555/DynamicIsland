import XCTest
@testable import DynamicIsland

@MainActor
final class LiveActivityStoreTests: XCTestCase {
    func testActivitiesSortByPriorityUpdatedAtThenTitle() {
        let store = LiveActivityStore()
        let now = Date(timeIntervalSince1970: 1_000)

        store.update(activity(id: "low", title: "A", priority: 10, updatedAt: now.addingTimeInterval(100)))
        store.update(activity(id: "older", title: "B", priority: 80, updatedAt: now))
        store.update(activity(id: "newer", title: "C", priority: 80, updatedAt: now.addingTimeInterval(1)))
        store.update(activity(id: "title", title: "A", priority: 80, updatedAt: now.addingTimeInterval(1)))

        XCTAssertEqual(store.activities.map(\.id), ["title", "newer", "older", "low"])
    }

    func testPrimaryActivityUsesSortedFirstActivity() {
        let store = LiveActivityStore()

        store.update(activity(id: "media", priority: 80))
        store.update(activity(id: "timer", priority: 90))

        XCTAssertEqual(store.primaryActivity?.id, "timer")
    }

    func testUpdatingSameIDReplacesPreviousActivity() {
        let store = LiveActivityStore()

        store.update(activity(id: "timer", title: "Timer", subtitle: "5:00", priority: 90))
        store.update(activity(id: "timer", title: "Timer", subtitle: "Paused", priority: 70))

        XCTAssertEqual(store.activities.count, 1)
        XCTAssertEqual(store.activities.first?.subtitle, "Paused")
        XCTAssertEqual(store.activities.first?.priority, 70)
    }

    func testRemovingActivityWorks() {
        let store = LiveActivityStore()

        store.update(activity(id: "timer"))
        store.update(activity(id: "media"))
        store.remove(id: "timer")

        XCTAssertEqual(store.activities.map(\.id), ["media"])
    }

    func testClampedProgressBoundsValues() {
        XCTAssertEqual(LiveActivityStore.clampedProgress(-0.4), 0)
        XCTAssertEqual(LiveActivityStore.clampedProgress(1.4), 1)
        XCTAssertEqual(LiveActivityStore.clampedProgress(0.42), 0.42)
        XCTAssertNil(LiveActivityStore.clampedProgress(.infinity))
        XCTAssertNil(LiveActivityStore.clampedProgress(nil))
    }

    private func activity(
        id: String,
        title: String = "Activity",
        subtitle: String? = nil,
        priority: Int = 50,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: id,
            kind: .system,
            title: title,
            subtitle: subtitle,
            symbolName: "sparkles",
            priority: priority,
            isActive: true,
            progress: nil,
            updatedAt: updatedAt
        )
    }
}

extension LiveActivityStoreTests {
    func testLifecycleMetadataDefaultsToLegacyAuthority() {
        let value = DynamicIslandLiveActivity(
            id: "legacy",
            kind: .media,
            title: "Media",
            subtitle: nil,
            symbolName: "music.note",
            priority: 80,
            isActive: true,
            progress: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(value.lifecycle.authority, .applicationState)
        XCTAssertEqual(value.lifecycle.dismissPolicy, .automatic)
        XCTAssertFalse(value.lifecycle.supportsCancellation)
    }

    func testLifecycleMetadataPreservesTruthfulSourceEvidence() {
        let metadata = LiveActivityLifecycleMetadata(
            authority: .process,
            startEvidence: "child process started",
            progressEvidence: "streaming process state",
            completionEvidence: "process exit status",
            dismissPolicy: .untilSourceEnds,
            supportsCancellation: true
        )
        let value = DynamicIslandLiveActivity(
            id: "terminal",
            kind: .terminalTask,
            title: "Build",
            subtitle: "Running",
            symbolName: "terminal",
            priority: 88,
            isActive: true,
            progress: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            lifecycle: metadata
        )

        XCTAssertEqual(value.lifecycle, metadata)
    }
}
