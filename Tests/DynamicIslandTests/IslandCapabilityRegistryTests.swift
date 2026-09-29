import XCTest
@testable import DynamicIsland

@MainActor
final class IslandCapabilityRegistryTests: XCTestCase {
    func testOperationalCapabilityRequiresEnabledAvailablePermissionAndNonfailedHealth() {
        var snapshot = IslandCapabilitySnapshot(
            id: .keepAwake,
            permission: .notRequired,
            supportedActions: [.start, .stop, .test]
        )
        XCTAssertTrue(snapshot.isOperational)

        snapshot.isEnabled = false
        XCTAssertFalse(snapshot.isOperational)

        snapshot.isEnabled = true
        snapshot.permission = .required
        XCTAssertFalse(snapshot.isOperational)

        snapshot.permission = .granted
        snapshot.availability = .temporarilyUnavailable(reason: "No focused window")
        XCTAssertFalse(snapshot.isOperational)

        snapshot.availability = .available
        snapshot.health = .failed(message: "Adapter failed")
        XCTAssertFalse(snapshot.isOperational)
    }

    func testPermissionRequiredAndDeniedRemainDistinctStates() {
        let required = IslandCapabilitySnapshot(
            id: .camera,
            permission: .required
        )
        let denied = IslandCapabilitySnapshot(
            id: .camera,
            permission: .denied
        )

        XCTAssertNotEqual(required.permission, denied.permission)
        XCTAssertFalse(required.isOperational)
        XCTAssertFalse(denied.isOperational)
    }

    func testSnapshotClampsFiniteProgressAndRejectsNonFiniteProgress() {
        XCTAssertEqual(
            IslandCapabilitySnapshot(id: .backgroundRemoval, progress: -0.2).progress,
            0
        )
        XCTAssertEqual(
            IslandCapabilitySnapshot(id: .backgroundRemoval, progress: 1.4).progress,
            1
        )
        XCTAssertEqual(
            IslandCapabilitySnapshot(id: .backgroundRemoval, progress: 0.42).progress,
            0.42
        )
        XCTAssertNil(
            IslandCapabilitySnapshot(id: .backgroundRemoval, progress: .infinity).progress
        )
    }

    func testRegistryUpdatesReplacesAndRemovesSnapshotsByCapabilityID() {
        let registry = IslandCapabilityRegistry()
        registry.update(
            IslandCapabilitySnapshot(
                id: .terminal,
                supportedActions: [.start, .stop]
            )
        )
        registry.update(
            IslandCapabilitySnapshot(
                id: .terminal,
                supportedActions: [.start, .stop, .configureShortcut],
                isActive: true,
                statusText: "Running"
            )
        )

        XCTAssertEqual(registry.snapshots.count, 1)
        XCTAssertEqual(registry.snapshot(for: .terminal)?.statusText, "Running")
        XCTAssertTrue(registry.snapshot(for: .terminal)?.isActive == true)

        registry.remove(.terminal)
        XCTAssertNil(registry.snapshot(for: .terminal))
    }
}
