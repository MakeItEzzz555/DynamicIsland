import XCTest
@testable import DynamicIsland

final class SystemStatsFormattingTests: XCTestCase {
    @MainActor
    func testPollingLifecycleIsDemandDrivenAndIdempotent() {
        let controller = SystemStatsController()

        XCTAssertFalse(controller.isPolling)
        controller.startPolling()
        XCTAssertTrue(controller.isPolling)
        controller.startPolling()
        XCTAssertTrue(controller.isPolling)
        controller.stopPolling()
        XCTAssertFalse(controller.isPolling)
        controller.stopPolling()
        XCTAssertFalse(controller.isPolling)
    }

    @MainActor
    func testRefreshIntervalChangePreservesStoppedState() {
        let controller = SystemStatsController()

        controller.setRefreshInterval(3)

        XCTAssertFalse(controller.isPolling)
    }

    @MainActor
    func testRefreshIntervalChangePreservesPollingState() {
        let controller = SystemStatsController()
        controller.startPolling()

        controller.setRefreshInterval(3)

        XCTAssertTrue(controller.isPolling)
        controller.stopPolling()
    }

    func testFormatBytesUsesBinaryUnits() {
        XCTAssertEqual(SystemStatsFormatting.formatBytes(1024), "1.0 KB")
        XCTAssertEqual(SystemStatsFormatting.formatBytes(1_048_576), "1.0 MB")
        XCTAssertEqual(SystemStatsFormatting.formatBytes(1_073_741_824), "1.0 GB")
    }

    func testClampedFractionBoundsValues() {
        XCTAssertEqual(SystemStatsFormatting.clampedFraction(-0.4), 0)
        XCTAssertEqual(SystemStatsFormatting.clampedFraction(0.42), 0.42)
        XCTAssertEqual(SystemStatsFormatting.clampedFraction(1.8), 1)
    }

    func testMemoryUsedBytesExcludesReclaimableCacheInputs() {
        let used = SystemStatsFormatting.memoryUsedBytes(
            active: 2_000,
            wired: 3_000,
            compressed: 4_000
        )

        XCTAssertEqual(used, 9_000)
    }

    func testHistoryCapsSamplesAndClampsValues() {
        var history = SystemStatsHistory(limit: 3)

        history.append(-1)
        history.append(0.25)
        history.append(0.5)
        history.append(2)

        XCTAssertEqual(history.samples, [0.25, 0.5, 1])
    }
}
