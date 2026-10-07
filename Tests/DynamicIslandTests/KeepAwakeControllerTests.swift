import XCTest
@testable import DynamicIsland

private final class FakeKeepAwakeAssertionProvider: KeepAwakeAssertionProviding {
    var acquireCount = 0
    var releaseCount = 0
    var error: Error?

    func acquire(reason: String) throws -> KeepAwakeAssertionLease {
        if let error { throw error }
        acquireCount += 1
        return KeepAwakeAssertionLease { [weak self] in
            self?.releaseCount += 1
        }
    }
}

@MainActor
final class KeepAwakeControllerTests: XCTestCase {
    func testIndefiniteStartPublishesAuthoritativeActivityAndCapabilityState() throws {
        let fixture = makeFixture()

        try fixture.controller.startIndefinite()

        XCTAssertTrue(fixture.controller.isActive)
        XCTAssertNil(fixture.controller.expiresAt)
        XCTAssertEqual(fixture.provider.acquireCount, 1)
        XCTAssertEqual(fixture.activities.activities.first?.kind, .keepAwake)
        XCTAssertEqual(fixture.activities.activities.first?.subtitle, "Indefinite")
        XCTAssertEqual(fixture.activities.activities.first?.lifecycle.authority, .systemAPI)
        XCTAssertEqual(fixture.registry.snapshot(for: .keepAwake)?.isActive, true)
    }

    func testTimedStartExpiresAndReleasesAssertion() throws {
        var current = Date(timeIntervalSince1970: 1_000)
        let fixture = makeFixture(now: { current })

        try fixture.controller.start(customDuration: 60)
        XCTAssertEqual(fixture.controller.expiresAt, current.addingTimeInterval(60))
        XCTAssertEqual(fixture.activities.activities.first?.subtitle, "1:00")

        current = current.addingTimeInterval(60)
        fixture.controller.tick(at: current)

        XCTAssertFalse(fixture.controller.isActive)
        XCTAssertEqual(fixture.provider.releaseCount, 1)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertEqual(fixture.registry.snapshot(for: .keepAwake)?.isActive, false)
    }

    func testReplacingActiveAssertionReleasesPreviousLeaseWithoutLeak() throws {
        let fixture = makeFixture()

        try fixture.controller.start(preset: .fifteenMinutes)
        try fixture.controller.start(preset: .thirtyMinutes)

        XCTAssertEqual(fixture.provider.acquireCount, 2)
        XCTAssertEqual(fixture.provider.releaseCount, 1)

        fixture.controller.stop()
        XCTAssertEqual(fixture.provider.releaseCount, 2)
    }

    func testDisablingWhileActiveStopsAndMarksCapabilityDisabled() throws {
        let fixture = makeFixture()
        try fixture.controller.startIndefinite()

        fixture.controller.setEnabled(false)

        XCTAssertFalse(fixture.controller.isActive)
        XCTAssertEqual(fixture.provider.releaseCount, 1)
        XCTAssertEqual(fixture.registry.snapshot(for: .keepAwake)?.isEnabled, false)
        XCTAssertFalse(fixture.registry.snapshot(for: .keepAwake)?.isOperational ?? true)
    }

    func testInvalidCustomDurationDoesNotAcquireAssertion() {
        let fixture = makeFixture()

        XCTAssertThrowsError(try fixture.controller.start(customDuration: 0))
        XCTAssertEqual(fixture.provider.acquireCount, 0)
        XCTAssertFalse(fixture.controller.isActive)
    }

    func testFailedAssertionPublishesFailedHealthWithoutLiveActivity() {
        let fixture = makeFixture()
        fixture.provider.error = KeepAwakeControllerError.assertionCreationFailed(-1)

        XCTAssertThrowsError(try fixture.controller.startIndefinite())
        XCTAssertTrue(fixture.activities.activities.isEmpty)

        guard case .failed = fixture.registry.snapshot(for: .keepAwake)?.health else {
            return XCTFail("Expected failed capability health")
        }
    }

    func testControllerTeardownReleasesLease() throws {
        let provider = FakeKeepAwakeAssertionProvider()
        let activities = LiveActivityStore()
        let registry = IslandCapabilityRegistry()
        var controller: KeepAwakeController? = KeepAwakeController(
            liveActivities: activities,
            capabilities: registry,
            assertionProvider: provider
        )

        try controller?.startIndefinite()
        XCTAssertEqual(provider.releaseCount, 0)

        controller = nil
        XCTAssertEqual(provider.releaseCount, 1)
    }

    private func makeFixture(
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) -> (
        controller: KeepAwakeController,
        provider: FakeKeepAwakeAssertionProvider,
        activities: LiveActivityStore,
        registry: IslandCapabilityRegistry
    ) {
        let provider = FakeKeepAwakeAssertionProvider()
        let activities = LiveActivityStore()
        let registry = IslandCapabilityRegistry()
        let controller = KeepAwakeController(
            liveActivities: activities,
            capabilities: registry,
            assertionProvider: provider,
            now: now
        )
        return (controller, provider, activities, registry)
    }
}
