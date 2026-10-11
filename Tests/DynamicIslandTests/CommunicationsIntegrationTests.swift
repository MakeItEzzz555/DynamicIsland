import AppKit
import SwiftUI
import ApplicationServices
import XCTest
@testable import DynamicIsland

@MainActor
final class FaceTimeAccessibilityTests: XCTestCase {
    private func record(bundle: String = "com.apple.FaceTime", id: Int64 = 1) -> SystemNotificationRecord {
        .init(recordID: id, bundleIdentifier: bundle, title: "Private caller", subtitle: "Private recipient",
              body: "Private message", deliveredAt: Date())
    }

    func testOptInAndPermissionAbsentNeverPromptOrInspectProcess() {
        let provider = FaceTimeAccessibilityProvider(liveActivities: LiveActivityStore(),
            notifications: SystemNotificationMonitor(fullDiskAccess: { .denied }), trusted: { false },
            running: { XCTFail("Cannot inspect FaceTime without trust"); return nil })
        XCTAssertEqual(provider.state, .disabled)
        provider.checkAgain()
        XCTAssertEqual(provider.state, .disabled)
        provider.setEnabled(true)
        XCTAssertEqual(provider.state, .permissionRequired)
        XCTAssertNil(provider.snapshot)
        provider.setEnabled(false)
        XCTAssertEqual(provider.state, .disabled)
    }

    func testProcessAbsentAndWrongProcessCannotEstablishCallAuthority() {
        for running in [{ () -> NSRunningApplication? in nil }, { NSRunningApplication.current }] {
            let provider = FaceTimeAccessibilityProvider(liveActivities: LiveActivityStore(),
                notifications: SystemNotificationMonitor(fullDiskAccess: { .denied }), trusted: { true }, running: running)
            provider.setEnabled(true)
            XCTAssertEqual(provider.state, .processAbsent)
            XCTAssertNil(provider.snapshot)
            provider.stop()
        }
    }

    func testUnverifiedIncomingConnectedAndStaleTreesNeverExposeControls() {
        for ids in [["Answer", "Decline"], ["End", "Mute"], ["stale"]] {
            let nodes = ids.map { FaceTimeAXNode(depth: 1, role: kAXButtonRole, subrole: nil,
                identifierSHA256: $0, actions: [kAXPressAction], enabled: true) }
            let snapshot = FaceTimeAXSnapshot(nodes: nodes, readStatus: 0, truncated: false)
            XCTAssertFalse(snapshot.hasVerifiedCall, "Press + a guessed identifier is not an active-call proof")
            XCTAssertTrue(snapshot.verifiedControls.isEmpty)
        }
        let unsupported = FaceTimeAXSnapshot(nodes: [], readStatus: AXError.invalidUIElement.rawValue, truncated: true)
        XCTAssertFalse(unsupported.hasVerifiedCall)
        XCTAssertTrue(unsupported.verifiedControls.isEmpty)
    }

    func testNotificationIsOnlyAnExpiringPreviewNeverConnectedAndDisableRemovesIt() throws {
        let activities = LiveActivityStore()
        let provider = FaceTimeAccessibilityProvider(liveActivities: activities,
            notifications: SystemNotificationMonitor(fullDiskAccess: { .denied }), trusted: { false })
        provider.receive(record())
        XCTAssertTrue(activities.activities.isEmpty)
        provider.setEnabled(true)
        provider.receive(record(bundle: "com.apple.MobileSMS"))
        XCTAssertTrue(activities.activities.isEmpty)
        provider.receive(record())
        provider.receive(record(id: 2))
        XCTAssertEqual(activities.activities.count, 1)
        let activity = try XCTUnwrap(activities.activities.first)
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(activity.title, "FaceTime notification")
        XCTAssertFalse(String(describing: activity).contains("Private"))
        XCTAssertEqual(CollapsedActivityHoverPolicy.resolve(kind: activity.kind), .none)
        XCTAssertNil(provider.snapshot)
        provider.setEnabled(false)
        XCTAssertTrue(activities.activities.isEmpty)
    }

    func testNativeDiagnosticsAreInertAndFitTheSettingsContentWidth() throws {
        _ = NSApplication.shared
        let provider = FaceTimeAccessibilityProvider(liveActivities: LiveActivityStore(),
            trusted: { XCTFail("Preview cannot check AX trust"); return false },
            running: { XCTFail("Preview cannot read FaceTime"); return nil })
        let view = CommunicationsIntegrationView(faceTime: provider,
            messaging: MessagingController(adapters: [], liveActivities: LiveActivityStore(), focus: FakeFocus())).padding(20).frame(width: 620)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: 100, y: 100, width: 620, height: 740),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 620)
        XCTAssertLessThanOrEqual(host.fittingSize.height, 740)
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/dynamicisland-communications-settings.png"))
        XCTAssertEqual(provider.state, .disabled)
        XCTAssertNil(provider.snapshot)
    }

    func testDisabledMessagingObservationDoesNotClaimMissingPermission() {
        XCTAssertEqual(CommunicationsIntegrationView.messageObservationStatus(.disabled), "Not Verified")
        XCTAssertEqual(CommunicationsIntegrationView.messageObservationStatus(.permissionRequired), "Permission Required")
        XCTAssertEqual(CommunicationsIntegrationView.messageObservationStatus(.running), "Available")
        XCTAssertEqual(CommunicationsIntegrationView.messageObservationStatus(.unavailable("unsupported schema")), "Unsupported")
        XCTAssertEqual(CommunicationsIntegrationView.messageObservationStatus(nil), "Unsupported")
    }

    func testProbeSerializationHasOnlyStructuralMetadata() throws {
        let snapshot = FaceTimeAXSnapshot(nodes: [.init(depth: 0, role: kAXWindowRole, subrole: nil,
            identifierSHA256: nil, actions: [], enabled: false)], readStatus: 0, truncated: false)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
        for attribute in ["title", "description", "value", "caller", "body"] {
            XCTAssertFalse(json.contains("\"\(attribute)\""))
        }
        XCTAssertFalse(NativeCallAuthority.canControl)
    }
}

private final class WakeupNotificationSource: SystemNotificationSource, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [SystemNotificationRecord] = []
    private var reads = 0
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    var blockFirstRead = false
    var watchedPaths: [String] { [] }
    func latestRecordID() throws -> Int64 { 0 }
    func waitForRead() { _ = entered.wait(timeout: .now() + 2) }
    func append(id: Int64) {
        lock.lock(); defer { lock.unlock() }
        rows.append(.init(recordID: id, bundleIdentifier: "com.apple.MobileSMS", title: nil,
            subtitle: nil, body: nil, deliveredAt: Date()))
    }
    func records(after id: Int64, limit: Int) throws -> [SystemNotificationRecord] {
        lock.lock()
        reads += 1
        let result = Array(rows.filter { $0.recordID > id }.prefix(limit))
        let shouldBlock = reads == 1 && blockFirstRead
        lock.unlock()
        if shouldBlock { entered.signal(); _ = release.wait(timeout: .now() + 2) }
        return result
    }
}

@MainActor
final class NotificationWakeupTests: XCTestCase {
    func testDarwinAndFileHintCoalesceAndDeliverTheSameRecordOnce() async throws {
        let source = WakeupNotificationSource()
        let monitor = SystemNotificationMonitor(makeSource: { source }, fullDiskAccess: { .granted })
        var delivered: [Int64] = []
        monitor.onRecord = { delivered.append($0.recordID) }
        monitor.start()
        defer { monitor.stop() }
        source.append(id: 1)
        NotificationCenter.default.post(name: .init("DynamicIsland.NotificationDatabaseHint"), object: nil)
        monitor.fetch() // Same database change from the file watcher.
        for _ in 0..<100 where delivered.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        monitor.fetch()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(delivered, [1])
    }

    func testHintDuringFetchIsNotLostAndUnavailableDarwinKeepsFetchAndPoll() async throws {
        let source = WakeupNotificationSource()
        source.blockFirstRead = true
        source.append(id: 1)
        let monitor = SystemNotificationMonitor(makeSource: { source }, fullDiskAccess: { .granted }, useDarwinHints: false)
        var delivered: [Int64] = []
        monitor.onRecord = { delivered.append($0.recordID) }
        monitor.start()
        defer { monitor.stop() }
        monitor.fetch()
        await Task.detached { source.waitForRead() }.value
        source.append(id: 2)
        monitor.fetch()
        monitor.fetch()
        source.release.signal()
        for _ in 0..<100 where delivered.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(delivered, [1, 2])
        XCTAssertEqual(monitor.state, .running)
        XCTAssertEqual(SystemNotificationMonitor.pollInterval, 4)
    }

    func testFullBatchDrainsWithoutAnotherHintAndStopRejectsPendingDelivery() async throws {
        let source = WakeupNotificationSource()
        for id in 1...51 { source.append(id: Int64(id)) }
        let monitor = SystemNotificationMonitor(makeSource: { source }, fullDiskAccess: { .granted }, useDarwinHints: false)
        var delivered: [Int64] = []
        monitor.onRecord = { delivered.append($0.recordID) }
        monitor.start()
        monitor.fetch()
        for _ in 0..<100 where delivered.count < 51 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(delivered, Array(1...51).map(Int64.init))
        monitor.stop()
        source.append(id: 52)
        NotificationCenter.default.post(name: .init("DynamicIsland.NotificationDatabaseHint"), object: nil)
        monitor.fetch()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(delivered.count, 51)
    }
}
