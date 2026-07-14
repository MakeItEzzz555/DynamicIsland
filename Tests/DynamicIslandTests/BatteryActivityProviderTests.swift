import XCTest
@testable import DynamicIsland

final class BatteryActivityProviderTests: XCTestCase {
    func testLowBatterySnapshotCreatesLowBatteryActivity() throws {
        let activity = try XCTUnwrap(
            BatteryActivitySnapshot(
                percentage: 18,
                powerSourceStateDescription: "Battery Power",
                isPluggedIn: false,
                isCharging: false,
                isCharged: false,
                isOnBattery: true
            )
            .liveActivity(updatedAt: Date(timeIntervalSince1970: 1_000))
        )

        XCTAssertEqual(activity.id, LiveActivityStore.batteryActivityID)
        XCTAssertEqual(activity.kind, .battery)
        XCTAssertEqual(activity.batteryState, .low)
        XCTAssertEqual(activity.progress, 0.18)
    }

    func testNormalBatterySnapshotDoesNotCreateActivity() {
        let activity = BatteryActivitySnapshot(
            percentage: 74,
            powerSourceStateDescription: "Battery Power",
            isPluggedIn: false,
            isCharging: false,
            isCharged: false,
            isOnBattery: true
        )
        .liveActivity(updatedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertNil(activity)
    }

    func testChargingBatterySnapshotCreatesChargingActivity() throws {
        let activity = try XCTUnwrap(
            BatteryActivitySnapshot(
                percentage: 74,
                powerSourceStateDescription: "AC Power",
                isPluggedIn: true,
                isCharging: true,
                isCharged: false,
                isOnBattery: false
            )
            .liveActivity(updatedAt: Date(timeIntervalSince1970: 1_000))
        )

        XCTAssertEqual(activity.batteryState, .charging)
        XCTAssertEqual(activity.title, "Charging")
    }

    func testPluggedInBatterySnapshotCreatesActivityWhenNotCharging() throws {
        let activity = try XCTUnwrap(
            BatteryActivitySnapshot(
                percentage: 74,
                powerSourceStateDescription: "AC Power",
                isPluggedIn: true,
                isCharging: false,
                isCharged: false,
                isOnBattery: false
            )
            .liveActivity(updatedAt: Date(timeIntervalSince1970: 1_000))
        )

        XCTAssertEqual(activity.batteryState, .pluggedIn)
        XCTAssertEqual(activity.title, "Plugged In")
        XCTAssertEqual(activity.subtitle, "74%")
    }

    func testFullBatterySnapshotCreatesFullActivity() throws {
        let activity = try XCTUnwrap(
            BatteryActivitySnapshot(
                percentage: 100,
                powerSourceStateDescription: "AC Power",
                isPluggedIn: true,
                isCharging: false,
                isCharged: true,
                isOnBattery: false
            )
            .liveActivity(updatedAt: Date(timeIntervalSince1970: 1_000))
        )

        XCTAssertEqual(activity.batteryState, .full)
        XCTAssertEqual(activity.title, "Battery Full")
    }
}
