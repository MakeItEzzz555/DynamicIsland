import Combine
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentActivityGlowCoordinatorTests: XCTestCase {
    func testActivityGlowLingersAfterActivityStopsThenClears() async throws {
        let coordinator = AgentActivityGlowCoordinator(lingerDuration: 0.05)

        coordinator.update(activeProvider: .codex)
        XCTAssertEqual(coordinator.provider, .codex)

        let cleared = expectation(description: "Activity glow clears after its linger task finishes")
        let observation = coordinator.$provider
            .dropFirst()
            .first(where: { $0 == nil })
            .sink { _ in cleared.fulfill() }
        defer { observation.cancel() }

        coordinator.update(activeProvider: nil)
        XCTAssertEqual(coordinator.provider, .codex)

        await fulfillment(of: [cleared], timeout: 1)
        XCTAssertNil(coordinator.provider)
    }

    func testNewActivityCancelsPendingClearAndUpdatesProvider() async throws {
        let coordinator = AgentActivityGlowCoordinator(lingerDuration: 0.05)

        coordinator.update(activeProvider: .codex)
        coordinator.update(activeProvider: nil)
        try await Task.sleep(for: .milliseconds(20))
        coordinator.update(activeProvider: .claude)

        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(coordinator.provider, .claude)
    }

    func testStopClearsImmediately() {
        let coordinator = AgentActivityGlowCoordinator(lingerDuration: 4)
        coordinator.update(activeProvider: .codex)
        coordinator.stop()
        XCTAssertNil(coordinator.provider)
    }
}
