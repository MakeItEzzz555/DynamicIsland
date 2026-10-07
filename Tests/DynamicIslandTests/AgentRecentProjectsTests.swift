import Foundation
import XCTest
@testable import DynamicIsland

final class AgentRecentProjectsTests: XCTestCase {
    func testRecordsMostRecentFirstDeduplicatedAndBounded() {
        let suite = "AgentRecentProjectsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentRecentProjects(defaults: defaults)

        store.record("/repo/app/")
        store.record("/other")
        store.record("/repo/app")
        XCTAssertEqual(store.load(), ["/repo/app", "/other"])

        for index in 0..<20 { store.record("/p\(index)") }
        XCTAssertEqual(store.load().count, AgentRecentProjects.maximumCount)
        XCTAssertEqual(store.load().first, "/p19")

        store.record("relative/path")
        XCTAssertFalse(store.load().contains("relative/path"))
        store.remove("/p19")
        XCTAssertFalse(store.load().contains("/p19"))
    }
}
