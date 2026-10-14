import XCTest
@testable import DynamicIsland

@MainActor
final class SystemVolumeWriteCoordinatorTests: XCTestCase {
    func testRapidSliderWritesKeepOnlyLatestPendingAndOneVerifiedReply() async throws {
        let gate = VolumeWriteTestGate()
        let coordinator = SystemVolumeWriteCoordinator { value, device in await gate.write(value, device: device) }
        var replies: [Double] = []
        coordinator.request(0.1, device: 7) { if let value = $0?.value { replies.append(value) } }
        let startDeadline = Date().addingTimeInterval(2)
        while await gate.values.isEmpty, Date() < startDeadline { await Task.yield() }
        let started = await gate.values
        XCTAssertFalse(started.isEmpty, "writer must start within the bounded test window")
        for n in 2...100 { coordinator.request(Double(n) / 100, device: 7) { if let value = $0?.value { replies.append(value) } } }
        await gate.release()
        let replyDeadline = Date().addingTimeInterval(2)
        while replies.isEmpty, Date() < replyDeadline { await Task.yield() }
        let values = await gate.values
        XCTAssertEqual(values, [0.1, 1]); XCTAssertEqual(replies, [1])
        coordinator.cancel()
    }

    func testCancelRejectsStaleCompletionAndInvalidInputNeverWrites() async {
        let gate = VolumeWriteTestGate()
        let coordinator = SystemVolumeWriteCoordinator { value, device in await gate.write(value, device: device) }
        var replies = 0
        coordinator.request(0.5, device: 7) { _ in replies += 1 }
        let startDeadline = Date().addingTimeInterval(2)
        while await gate.values.isEmpty, Date() < startDeadline { await Task.yield() }
        let started = await gate.values
        XCTAssertFalse(started.isEmpty, "writer must start within the bounded test window")
        coordinator.cancel(); await gate.release()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(replies, 0)
        coordinator.request(.nan, device: 8) { XCTAssertNil($0); replies += 1 }
        let values = await gate.values
        XCTAssertEqual(values, [0.5]); XCTAssertEqual(replies, 1)
    }

    func testEchoSuppressionDoesNotSuppressExternalVolumeOrMuteChanges() {
        var tracker = SystemVolumeChangeTracker()
        let now = Date()
        func state(_ value: Double, _ muted: Bool, _ t: Double) -> SystemHUDSnapshot {
            .init(kind: .volume, value: value, isMuted: muted, updatedAt: now.addingTimeInterval(t))
        }
        XCTAssertFalse(tracker.observed(state(0.2, false, 0)))
        tracker.verifiedWrite(state(0.5, false, 0.1))
        XCTAssertFalse(tracker.observed(state(0.5, false, 0.2)))
        XCTAssertTrue(tracker.observed(state(0.7, false, 0.25)))
        XCTAssertTrue(tracker.observed(state(0.7, true, 0.3)))
        XCTAssertFalse(tracker.observed(state(0.7, true, 0.4)))
    }

    func testFineVolumeStepIsOneQuarterWithoutChangingDefaultStep() {
        XCTAssertEqual(SystemVolumeKeyStep.value(fine: false), 1 / 16)
        XCTAssertEqual(SystemVolumeKeyStep.value(fine: true), 1 / 64)
    }
}

private actor VolumeWriteTestGate {
    var values: [Double] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private var released = false
    func write(_ value: Double, device: UInt32) async -> SystemHUDSnapshot? {
        values.append(value)
        if !released { await withCheckedContinuation { waiter = $0 } }
        return .init(kind: .volume, value: value, isMuted: false, updatedAt: Date())
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}
