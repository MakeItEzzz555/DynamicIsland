import XCTest
@testable import DynamicIsland

@MainActor
final class GeneralNotificationQueueTests: XCTestCase {
    private let time = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func record(_ id: Int64, bundle: String = "fixture.app", epoch: Int = 1, stable: Data? = nil,
                        delivered: Date? = nil, observed: Date? = nil) -> SystemNotificationRecord {
        var record = SystemNotificationRecord(recordID: id, bundleIdentifier: bundle, title: "Synthetic title",
            subtitle: nil, body: "Synthetic body", deliveredAt: delivered, observedAt: observed ?? time, stableID: stable)
        record.epoch = epoch
        return record
    }
    private func receive(_ record: SystemNotificationRecord, in queue: inout GeneralNotificationQueue, content: Bool = false) {
        queue.receive(record, enabled: true, allowedApplications: ["fixture.app"], includeContent: content, now: time)
    }
    func testDisabledFilteredAndProviderSpecificNotificationsAreNeverGeneralPreviews() {
        var queue = GeneralNotificationQueue()
        for bundle in ["fixture.app", "com.apple.MobileSMS", "com.apple.FaceTime"] {
            queue.receive(record(1, bundle: bundle), enabled: false, allowedApplications: [bundle], includeContent: true, now: time)
        }
        receive(record(2, bundle: "other.app"), in: &queue)
        for bundle in ["com.apple.MobileSMS", "com.apple.FaceTime"] {
            queue.receive(record(3, bundle: bundle), enabled: true, allowedApplications: [bundle], includeContent: true, now: time)
        }
        XCTAssertTrue(queue.events.isEmpty)
    }
    func testDistinctIdenticalContentBothDeliverWithoutHistoricalOrDuplicateReplay() {
        var queue = GeneralNotificationQueue()
        receive(record(1), in: &queue, content: true); receive(record(2), in: &queue, content: true)
        receive(record(1), in: &queue, content: true)
        XCTAssertEqual(queue.events.count, 2)
        XCTAssertEqual(queue.events[0].body, queue.events[1].body)
        queue.dismiss(queue.events[0].id)
        receive(record(1), in: &queue)
        XCTAssertEqual(queue.events.count, 1)
        receive(record(1, epoch: 2), in: &queue)
        XCTAssertEqual(queue.events.count, 2)
    }
    func testStableIdentityDeduplicatesAcrossEpochsAndPrivacyStripsContent() {
        var queue = GeneralNotificationQueue()
        receive(record(1, stable: Data([1])), in: &queue)
        receive(record(99, epoch: 2, stable: Data([1])), in: &queue)
        XCTAssertEqual(queue.events.count, 1)
        XCTAssertNil(queue.events[0].title); XCTAssertNil(queue.events[0].body)
        XCTAssertNil(queue.events[0].deliveredAt)
        XCTAssertEqual(queue.events[0].observedAt, time)
    }
    func testQueueIsBoundedAndDeadlineDoesNotPauseForProtectedOwnership() {
        var queue = GeneralNotificationQueue()
        for id in 1...20 { receive(record(Int64(id)), in: &queue) }
        XCTAssertEqual(queue.events.count, 10)
        var gate = GeneralNotificationPresentationGate(focusActive: false, sourceAvailable: true)
        XCTAssertNotNil(queue.current(gate: gate))
        gate.protectedInteraction = true; XCTAssertNil(queue.current(gate: gate))
        queue.expire(now: time.addingTimeInterval(8)); gate.protectedInteraction = false
        XCTAssertNil(queue.current(gate: gate))
    }
    func testFocusUnknownDeactivationAndUnavailableSourceNeverPresent() {
        var queue = GeneralNotificationQueue(); receive(record(1), in: &queue)
        for focus in [nil, true] as [Bool?] {
            XCTAssertNil(queue.current(gate: .init(focusActive: focus, sourceAvailable: true)))
        }
        XCTAssertNil(queue.current(gate: .init(focusActive: false, applicationActive: false, sourceAvailable: true)))
        XCTAssertNil(queue.current(gate: .init(focusActive: false, sourceAvailable: false)))
    }
    func testOldOrFutureTimestampIsRejectedAndClearRemovesContent() {
        var queue = GeneralNotificationQueue()
        receive(record(1, delivered: time.addingTimeInterval(-31)), in: &queue)
        receive(record(2, observed: time.addingTimeInterval(-9)), in: &queue)
        receive(record(3, observed: time.addingTimeInterval(1)), in: &queue)
        XCTAssertTrue(queue.events.isEmpty)
        receive(record(4), in: &queue, content: true); queue.clear()
        XCTAssertTrue(queue.events.isEmpty)
    }
}
