import Foundation
import XCTest
@testable import DynamicIsland

private final class ResilienceSource: SystemNotificationSource, @unchecked Sendable {
    private let lock = NSLock()
    private var failure: ReadOnlySQLiteError?
    private var rows: [SystemNotificationRecord] = []
    var watchedPaths: [String] { [] }
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private var block = false
    func setFailure(_ error: ReadOnlySQLiteError?) { lock.withLock { failure = error } }
    func append(_ id: Int64) { lock.withLock { rows.append(.init(recordID: id, bundleIdentifier: "fixture.app", title: nil, subtitle: nil, body: nil, deliveredAt: nil)) } }
    func blockNext() { lock.withLock { block = true } }
    func latestRecordID() throws -> Int64 { try lock.withLock { if let failure { throw failure }; return rows.last?.recordID ?? 0 } }
    func records(after: Int64, limit: Int) throws -> [SystemNotificationRecord] { [] }
    func snapshot(after: Int64, limit: Int) throws -> NotificationStoreSnapshot {
        let (result, shouldBlock) = try lock.withLock {
            if let failure { throw failure }
            let result = NotificationStoreSnapshot(fileIdentity: nil, maxRecordID: rows.last?.recordID ?? 0,
                records: Array(rows.filter { $0.recordID > after }.prefix(limit)))
            let shouldBlock = block; block = false
            return (result, shouldBlock)
        }
        if shouldBlock { entered.signal(); _ = release.wait(timeout: .now() + 2) }
        return result
    }
}

@MainActor
final class SystemNotificationMonitorResilienceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotificationResilience-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func database(_ directory: URL, name: String = "db", uuid: Bool = false) throws -> FixtureSQLite {
        let db = try FixtureSQLite(directory: directory, name: name)
        db.exec("CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT)")
        db.exec("CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB\(uuid ? ", uuid BLOB" : ""))")
        db.exec("INSERT INTO app VALUES (1, 'fixture.app')")
        return db
    }
    private func insert(_ db: FixtureSQLite, id: Int64, uuid: Data? = nil) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["titl": "Synthetic title", "body": "Synthetic body"], format: .binary, options: 0)
        if let uuid { db.insert("INSERT INTO record VALUES (?, 1, ?, ?)", [id, data, uuid]) }
        else { db.insert("INSERT INTO record VALUES (?, 1, ?)", [id, data]) }
    }
    private func monitor(_ source: SystemNotificationSource) -> SystemNotificationMonitor {
        SystemNotificationMonitor(makeSource: { source }, fullDiskAccess: { .granted }, useDarwinHints: false)
    }
    private func wait(_ condition: @escaping @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true within 2 seconds", file: file, line: line)
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(80)) }

    func testA1ReplacementRearmsAndNextRowArrivesThroughWatcher() async throws {
        let dir = try directory(), old = try database(dir)
        try insert(old, id: 10)
        let mon = monitor(NotificationCenterDatabaseSource(path: old.path)); var received: [Int64] = []
        mon.onRecord = { received.append($0.recordID) }; mon.start(); defer { mon.stop() }
        let replacement = try database(dir, name: "replacement"); try insert(replacement, id: 1)
        try FileManager.default.removeItem(atPath: old.path)
        try FileManager.default.moveItem(atPath: replacement.path, toPath: old.path)
        try await wait { mon.diagnostics.cursorRebases == 1 && mon.diagnostics.installedWatchPaths.contains(old.path) }
        XCTAssertTrue(received.isEmpty)
        let writer = try FixtureSQLite(directory: dir, name: "db"); try insert(writer, id: 2)
        try await wait { received == [2] }
        XCTAssertGreaterThanOrEqual(mon.diagnostics.watcherRearms, 1)
    }

    func testA2LateWALIsArmedAndWritesWakeMonitor() async throws {
        let dir = try directory(), db = try database(dir)
        let mon = monitor(NotificationCenterDatabaseSource(path: db.path)); var received: [Int64] = []
        mon.onRecord = { received.append($0.recordID) }; mon.start(); defer { mon.stop() }
        db.exec("PRAGMA journal_mode=WAL"); try insert(db, id: 1)
        mon.pollTick()
        try await wait { mon.diagnostics.installedWatchPaths.contains(db.path + "-wal") && received == [1] }
        try insert(db, id: 2)
        try await wait { received == [1, 2] }
    }

    func testA3RecordIDRegressionRebasesWithoutReplayingHistory() async throws {
        let dir = try directory(), db = try database(dir); try insert(db, id: 80)
        let mon = monitor(NotificationCenterDatabaseSource(path: db.path)); var received: [Int64] = []
        mon.onRecord = { received.append($0.recordID) }; mon.start(); defer { mon.stop() }
        db.exec("DELETE FROM record"); try insert(db, id: 1); mon.fetch()
        try await wait { mon.diagnostics.cursorRebases == 1 }
        XCTAssertTrue(received.isEmpty)
        try insert(db, id: 2); mon.fetch(); try await wait { received == [2] }
    }

    func testA4RenumberedReplacementDoesNotReplay() async throws {
        let dir = try directory(), db = try database(dir); try insert(db, id: 1)
        let mon = monitor(NotificationCenterDatabaseSource(path: db.path)); var received: [Int64] = []
        mon.onRecord = { received.append($0.recordID) }; mon.start(); defer { mon.stop() }
        let replacement = try database(dir, name: "copy"); try insert(replacement, id: 100)
        try FileManager.default.removeItem(atPath: db.path); try FileManager.default.moveItem(atPath: replacement.path, toPath: db.path)
        mon.pollTick(); try await wait { mon.diagnostics.cursorRebases == 1 }
        XCTAssertTrue(received.isEmpty)
        let writer = try FixtureSQLite(directory: dir, name: "db"); try insert(writer, id: 101)
        mon.fetch(); try await wait { received == [101] }
    }

    func testA4bStableUUIDProvesContinuityAcrossReplacement() async throws {
        let dir = try directory(), db = try database(dir, uuid: true), stable = Data([1, 2, 3])
        try insert(db, id: 4, uuid: stable)
        let mon = monitor(NotificationCenterDatabaseSource(path: db.path)); var received: [Int64] = []
        mon.onRecord = { received.append($0.recordID) }; mon.start(); defer { mon.stop() }
        let replacement = try database(dir, name: "copy", uuid: true)
        try insert(replacement, id: 4, uuid: stable); try insert(replacement, id: 5, uuid: Data([5]))
        try FileManager.default.removeItem(atPath: db.path); try FileManager.default.moveItem(atPath: replacement.path, toPath: db.path)
        mon.pollTick(); try await wait { received == [5] }
        XCTAssertEqual(mon.diagnostics.cursorRebases, 0)
    }

    func testA5MidRunPermissionLossStopsMonitoring() async throws {
        let source = ResilienceSource(), mon = monitor(source); mon.start(); defer { mon.stop() }
        source.setFailure(.notPermitted); mon.fetch()
        try await wait { mon.state == .permissionRequired }
        XCTAssertTrue(mon.diagnostics.installedWatchPaths.isEmpty)
    }

    func testA6UnsupportedSchemaAtStartAndMidRunFailsClosed() async throws {
        let dir = try directory(), db = try database(dir), mon = monitor(NotificationCenterDatabaseSource(path: db.path))
        mon.start(); defer { mon.stop() }; db.exec("DROP TABLE record"); mon.fetch()
        try await wait { if case .unavailable = mon.state { return true }; return false }
        mon.start()
        guard case .unavailable = mon.state else { return XCTFail("Invalid schema must stay unavailable") }
    }

    func testA7IdenticalContentDistinctRecordsBothDeliverAndHintsDoNotRepeat() async throws {
        let dir = try directory(), db = try database(dir), mon = monitor(NotificationCenterDatabaseSource(path: db.path))
        var records: [SystemNotificationRecord] = []; mon.onRecord = { records.append($0) }; mon.start(); defer { mon.stop() }
        try insert(db, id: 1); try insert(db, id: 2); mon.fetch()
        try await wait { records.count == 2 }; mon.fetch(); try await settle()
        XCTAssertEqual(records.map(\.recordID), [1, 2]); XCTAssertEqual(records[0].body, records[1].body)
    }

    func testA8UnknownDeliveryTimestampHasIndependentObservationTime() async throws {
        let dir = try directory(), db = try database(dir); try insert(db, id: 1)
        let before = Date(), record = try XCTUnwrap(NotificationCenterDatabaseSource(path: db.path).records(after: 0, limit: 50).first)
        XCTAssertNil(record.deliveredAt); XCTAssertGreaterThanOrEqual(record.observedAt, before)
        let source = ResilienceSource(), mon = monitor(source); mon.start(); defer { mon.stop() }
        source.append(1); mon.fetch(); try await wait { mon.diagnostics.unknownTimestampCount == 1 }
        XCTAssertNotNil(mon.lastEventAt)
    }

    func testA9VanishedDatabaseBecomesUnavailableAndExplicitRestartRecovers() async throws {
        let dir = try directory(), db = try database(dir), mon = monitor(NotificationCenterDatabaseSource(path: db.path))
        mon.start(); defer { mon.stop() }; try FileManager.default.removeItem(atPath: db.path)
        mon.fetch(); try await wait { mon.diagnostics.transientFailures >= 1 }
        mon.fetch(); try await wait { if case .unavailable = mon.state { return true }; return false }
        let replacement = try database(dir); try insert(replacement, id: 20); mon.start()
        XCTAssertEqual(mon.state, .running)
    }

    func testA10CancelledWatcherAndOldGenerationSnapshotCannotDeliver() async throws {
        let source = ResilienceSource(), mon = monitor(source); var received: [Int64] = []
        mon.onRecord = { received.append($0.recordID) }; mon.start()
        let oldToken = mon.armToken; mon.rearmWatchers()
        source.append(1); mon.watcherEvent(token: oldToken, replaced: false); try await settle()
        XCTAssertTrue(received.isEmpty)
        source.blockNext(); mon.fetch(); XCTAssertEqual(source.entered.wait(timeout: .now() + 1), .success)
        mon.stop(); mon.start(); source.release.signal(); try await settle()
        XCTAssertTrue(received.isEmpty); mon.stop()
    }

    func testA11MessagesAndFaceTimeFollowMonitorFailures() async throws {
        let source = ResilienceSource(), mon = monitor(source)
        let adapter = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/fixture/Messages.app") },
            monitor: mon, store: FakeMessagesStore(), automation: FakeMessagesAutomation())
        adapter.setObservationEnabled(true); XCTAssertEqual(adapter.observationState, .running)
        source.setFailure(.notPermitted); mon.fetch()
        try await wait { adapter.observationState == .permissionRequired }
        source.setFailure(nil); adapter.setObservationEnabled(true)
        source.setFailure(.unsupportedSchema("fixture")); mon.fetch()
        try await wait { adapter.observationState == .unavailable("Unsupported Notification Center database: fixture") }
        adapter.setObservationEnabled(false); XCTAssertEqual(adapter.observationState, .disabled)
        let faceMon = monitor(ResilienceSource())
        let face = FaceTimeAccessibilityProvider(liveActivities: LiveActivityStore(), notifications: faceMon, trusted: { false })
        face.setEnabled(true); XCTAssertEqual(face.notificationMonitoringState, .running)
        face.stop(); XCTAssertEqual(face.notificationMonitoringState, .stopped)
    }

    func testA12HundredRearmsCloseEveryObsoleteDescriptorAndRetainOnlyBoundedIDs() async throws {
        let dir = try directory(), db = try database(dir), mon = monitor(NotificationCenterDatabaseSource(path: db.path))
        let keysBefore = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let filesBefore = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        mon.start()
        for _ in 0..<100 { mon.rearmWatchers() }
        try await wait { mon.diagnostics.watchersClosed == mon.diagnostics.watchersOpened - mon.diagnostics.installedWatchPaths.count }
        XCTAssertEqual(mon.diagnostics.installedWatchPaths, [db.path])
        let source = ResilienceSource(), bounded = monitor(source); bounded.start()
        for id in 1...550 { source.append(Int64(id)) }; bounded.fetch()
        try await wait { bounded.diagnostics.deduplicationCount == 512 }
        bounded.stop(); mon.stop()
        try await wait { mon.diagnostics.watchersClosed == mon.diagnostics.watchersOpened }
        XCTAssertEqual(keysBefore, Set(UserDefaults.standard.dictionaryRepresentation().keys))
        XCTAssertEqual(filesBefore, Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)))
        XCTAssertEqual(SystemNotificationMonitor.pollInterval, 4)
        XCTAssertEqual(SystemNotificationMonitor.batchLimit, 50)
    }
    func testSharedConsumersHaveOneEpochAndIndependentObservationOwnership() async throws {
        let source = ResilienceSource(), mon = monitor(source), first = UUID(), second = UUID()
        var firstReceived: [Int64] = [], secondReceived: [Int64] = []
        mon.observeRecords(owner: first) { firstReceived.append($0.recordID) }
        mon.observeRecords(owner: second) { secondReceived.append($0.recordID) }
        mon.setObservationEnabled(true, owner: first)
        let epoch = mon.diagnostics.epoch
        source.append(1)
        mon.setObservationEnabled(true, owner: second)
        mon.setObservationEnabled(true, owner: second)
        XCTAssertEqual(mon.diagnostics.epoch, epoch)
        XCTAssertEqual(mon.observationOwnerCount, 2)
        mon.fetch(); try await wait { firstReceived == [1] && secondReceived == [1] }
        mon.setObservationEnabled(false, owner: first)
        XCTAssertEqual(mon.state, .running)
        source.append(2); mon.fetch(); try await wait { secondReceived == [1, 2] }
        XCTAssertEqual(firstReceived, [1])
        mon.removeObserver(owner: second)
        XCTAssertEqual(mon.state, .stopped)
        XCTAssertEqual(mon.observationOwnerCount, 0)
        mon.removeObserver(owner: first)
    }

    func testA8AdapterUsesObservedTimeForExactResolutionWhenDeliveryTimeIsUnknown() async throws {
        let time = Date(timeIntervalSinceReferenceDate: 800_000_000), source = ResilienceSource(), mon = monitor(source)
        let store = FakeMessagesStore()
        store.incoming = [.init(rowID: 1, chatGUID: "fixture-chat", isGroup: false, service: "iMessage",
            text: "Synthetic body", date: time, isFromMe: false)]
        let adapter = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/fixture/Messages.app") },
            monitor: mon, store: store, automation: FakeMessagesAutomation())
        var message: MessagingMessage?
        adapter.onIncoming = { message = $0 }; adapter.setObservationEnabled(true)
        adapter.handle(.init(recordID: 1, bundleIdentifier: "com.apple.MobileSMS", title: "Synthetic title",
            subtitle: nil, body: "Synthetic body", deliveredAt: nil, observedAt: time))
        try await wait { message != nil }
        XCTAssertEqual(message?.receivedAt, time)
        XCTAssertEqual(message?.conversation.id?.nativeID, "fixture-chat")
        adapter.setObservationEnabled(false)
    }

    func testMalformedRowDoesNotBlockNextBatchAndEmptyUUIDCannotDropDistinctRecords() async throws {
        let dir = try directory(), db = try database(dir, uuid: true), mon = monitor(NotificationCenterDatabaseSource(path: db.path))
        var received: [Int64] = []; mon.onRecord = { received.append($0.recordID) }; mon.start(); defer { mon.stop() }
        for id in 1...50 { db.insert("INSERT INTO record VALUES (?, 1, ?, ?)", [id, Data([0]), Data()]) }
        let payload = try PropertyListSerialization.data(fromPropertyList: ["body": "Synthetic body"], format: .binary, options: 0)
        db.insert("INSERT INTO record VALUES (51, 1, ?, ?)", [payload, Data()])
        db.insert("INSERT INTO record VALUES (52, 1, ?, ?)", [payload, Data()])
        mon.fetch(); try await wait { received == [51, 52] }
        XCTAssertEqual(mon.diagnostics.deduplicationCount, 2)
    }

    func testSyntheticSnapshotLatencyAndWatcherResourceMeasurements() throws {
        let dir = try directory(), db = try database(dir), source = NotificationCenterDatabaseSource(path: db.path)
        for id in 1...50 { try insert(db, id: Int64(id)) }
        var milliseconds: [Double] = []
        for _ in 0..<100 {
            let start = ProcessInfo.processInfo.systemUptime
            XCTAssertEqual(try source.snapshot(after: 0, limit: 50).records.count, 50)
            milliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        milliseconds.sort()
        print("NotificationSyntheticSnapshot: samples=100 rows=50 meanMs=\(milliseconds.reduce(0,+)/100) p95Ms=\(milliseconds[94])")
    }

    func testPollSupersedingPendingWatcherRearmCannotLeaveFutureRearmsBlocked() async throws {
        let mon = monitor(ResilienceSource()); mon.start(); defer { mon.stop() }
        let before = mon.diagnostics.watcherRearms
        mon.watcherEvent(token: mon.armToken, replaced: true)
        mon.rearmWatchers() // Poll wins before the old event's queued task executes.
        mon.watcherEvent(token: mon.armToken, replaced: true)
        try await wait { mon.diagnostics.watcherRearms == before + 2 }
        mon.watcherEvent(token: mon.armToken, replaced: true)
        try await wait { mon.diagnostics.watcherRearms == before + 3 }
    }

    func testFaceTimeCheckAgainRecoversNotificationSourceIndependentlyOfAXPermission() async throws {
        let source = ResilienceSource(), mon = monitor(source)
        let face = FaceTimeAccessibilityProvider(liveActivities: LiveActivityStore(), notifications: mon, trusted: { false })
        face.setEnabled(true); defer { face.stop() }
        source.setFailure(.notPermitted); mon.fetch()
        try await wait { face.notificationMonitoringState == .permissionRequired }
        source.setFailure(nil); face.checkAgain()
        XCTAssertEqual(face.notificationMonitoringState, .running)
        XCTAssertEqual(face.state, .permissionRequired)
        XCTAssertEqual(mon.observationOwnerCount, 1)
    }

    func testA9RelocationPrefersExistingDatabaseOverAnObsoleteParentDirectory() async throws {
        let dir = try directory(), old = try database(dir), replacement = try database(dir, name: "new-db")
        try insert(old, id: 10); try insert(replacement, id: 40)
        let candidates = [old.path, replacement.path]
        let mon = SystemNotificationMonitor(makeSource: { NotificationCenterDatabaseSource.locate(candidates: candidates) },
            fullDiskAccess: { .granted }, useDarwinHints: false)
        var received: [Int64] = []; mon.onRecord = { received.append($0.recordID) }; mon.start(); defer { mon.stop() }
        try FileManager.default.removeItem(atPath: old.path)
        XCTAssertEqual(NotificationCenterDatabaseSource.locate(candidates: candidates)?.path, replacement.path)
        mon.fetch(); try await wait { mon.diagnostics.transientFailures >= 1 }
        mon.fetch(); try await wait { mon.diagnostics.installedWatchPaths.contains(replacement.path) }
        XCTAssertEqual(mon.state, .running); XCTAssertTrue(received.isEmpty)
        try insert(replacement, id: 41); mon.fetch(); try await wait { received == [41] }
    }

    func testMessagesMonitoringFailureInvalidatesControllerCapabilitiesImmediately() async throws {
        let source = ResilienceSource(), mon = monitor(source)
        let adapter = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/fixture/Messages.app") },
            monitor: mon, store: FakeMessagesStore(), automation: FakeMessagesAutomation())
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore())
        adapter.setObservationEnabled(true)
        var changes = 0
        let observation = controller.objectWillChange.sink { changes += 1 }
        source.setFailure(.notPermitted); mon.fetch()
        try await wait { changes == 1 }
        XCTAssertEqual(adapter.observationState, .permissionRequired)
        XCTAssertFalse(controller.capabilities(for: .messages).contains(.sendReply))
        mon.fetch(); try await settle(); XCTAssertEqual(changes, 1)
        observation.cancel(); adapter.setObservationEnabled(false)
    }

}
