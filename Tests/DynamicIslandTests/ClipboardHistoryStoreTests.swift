import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
private final class FakeClipboardPasteboardClient: ClipboardPasteboardClient {
    var changeCount = 0
    var readResult: ClipboardPasteboardReadResult = .empty
    var writeSucceeds = true
    var writtenPayloads: [ClipboardHistoryPayload] = []

    func readSupportedPayload(
        limits: ClipboardHistoryLimits,
        capturesImages: Bool
    ) -> ClipboardPasteboardReadResult {
        if !capturesImages, case .payload(.imagePNG) = readResult {
            return .unsupported
        }
        return readResult
    }

    func write(_ payload: ClipboardHistoryPayload) -> ClipboardPasteboardWriteResult {
        guard writeSucceeds else {
            return .init(succeeded: false, resultingChangeCount: changeCount)
        }
        writtenPayloads.append(payload)
        changeCount += 1
        return .init(succeeded: true, resultingChangeCount: changeCount)
    }
}

private final class MemoryClipboardPersistence: ClipboardHistoryPersistence, @unchecked Sendable {
    let archiveURL = URL(fileURLWithPath: "/memory/clipboard-history.json")
    private let lock = NSLock()
    private var storage: Data?

    init(data: Data? = nil) {
        storage = data
    }

    func loadData() -> Data? {
        lock.withLock { storage }
    }

    func saveDataAtomically(_ data: Data) throws {
        lock.withLock { storage = data }
    }

    func deleteArchive() throws {
        lock.withLock { storage = nil }
    }

    var data: Data? {
        lock.withLock { storage }
    }
}

private enum ControlledClipboardPersistenceError: Error {
    case requestedFailure
}

private final class ControlledClipboardPersistence: ClipboardHistoryPersistence, @unchecked Sendable {
    let archiveURL = URL(fileURLWithPath: "/controlled/clipboard-history.json")

    private let lock = NSLock()
    private let blockedSaveStarted = DispatchSemaphore(value: 0)
    private let allowBlockedSave = DispatchSemaphore(value: 0)
    private let failsSave: Bool
    private let failsDelete: Bool
    private var blocksNextSave: Bool
    private var storage: Data?
    private var saveOperations = 0
    private var deleteOperations = 0

    init(
        data: Data? = nil,
        blocksNextSave: Bool = false,
        failsSave: Bool = false,
        failsDelete: Bool = false
    ) {
        storage = data
        self.blocksNextSave = blocksNextSave
        self.failsSave = failsSave
        self.failsDelete = failsDelete
    }

    func loadData() -> Data? {
        lock.withLock { storage }
    }

    func saveDataAtomically(_ data: Data) throws {
        let shouldBlock = lock.withLock { () -> Bool in
            saveOperations += 1
            guard blocksNextSave else { return false }
            blocksNextSave = false
            return true
        }
        if shouldBlock {
            blockedSaveStarted.signal()
            allowBlockedSave.wait()
        }
        if failsSave { throw ControlledClipboardPersistenceError.requestedFailure }
        lock.withLock { storage = data }
    }

    func deleteArchive() throws {
        lock.withLock { deleteOperations += 1 }
        if failsDelete { throw ControlledClipboardPersistenceError.requestedFailure }
        lock.withLock { storage = nil }
    }

    func waitForBlockedSaveToStart(timeout: TimeInterval = 1) -> Bool {
        blockedSaveStarted.wait(timeout: .now() + timeout) == .success
    }

    func unblockSave() {
        allowBlockedSave.signal()
    }

    var data: Data? {
        lock.withLock { storage }
    }

    var saveCount: Int {
        lock.withLock { saveOperations }
    }

    var deleteCount: Int {
        lock.withLock { deleteOperations }
    }
}

final class ClipboardHistoryStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "ClipboardHistoryStoreTests-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    @MainActor
    func testMonitoringBaselinesAndDoesNotImportExistingContent() {
        let settings = AppSettings(defaults: defaults)
        let pasteboard = FakeClipboardPasteboardClient()
        pasteboard.changeCount = 7
        pasteboard.readResult = .payload(text("existing"))
        let store = makeStore(settings: settings, pasteboard: pasteboard)

        settings.clipboardHistoryEnabled = true
        store.pollNow()

        XCTAssertTrue(store.isMonitoring)
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testChangedTextURLFilesAndImageAreCaptured() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard)
        let payloads: [ClipboardHistoryPayload] = [
            text("text"),
            .url(URL(string: "https://example.com")!),
            .files([URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]),
            .imagePNG(Data([1, 2, 3]))
        ]

        for payload in payloads {
            pasteboard.changeCount += 1
            pasteboard.readResult = .payload(payload)
            store.pollNow()
        }

        XCTAssertEqual(store.entries.map(\.payload), payloads.reversed())
    }

    @MainActor
    func testUnchangedChangeCountAndDisabledMonitoringCaptureNothing() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard)
        pasteboard.readResult = .payload(text("ignored"))

        store.pollNow()
        settings.clipboardHistoryEnabled = false
        pasteboard.changeCount += 1
        store.pollNow()

        XCTAssertFalse(store.isMonitoring)
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testReenableCreatesFreshBaseline() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard)

        settings.clipboardHistoryEnabled = false
        pasteboard.changeCount = 10
        pasteboard.readResult = .payload(text("while disabled"))
        settings.clipboardHistoryEnabled = true
        store.pollNow()
        XCTAssertTrue(store.entries.isEmpty)

        pasteboard.changeCount += 1
        pasteboard.readResult = .payload(text("after reenable"))
        store.pollNow()
        XCTAssertEqual(store.entries.map(\.payload), [text("after reenable")])
    }

    @MainActor
    func testImageCaptureSettingAndFilteredResultsAreRespected() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryCaptureImagesEnabled = false
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard)

        for result: ClipboardPasteboardReadResult in [.payload(.imagePNG(Data([1]))), .oversized, .sensitive, .empty] {
            pasteboard.changeCount += 1
            pasteboard.readResult = result
            store.pollNow()
        }

        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testDuplicateMovesToFrontPreservesIDAndUpdatesTimestamp() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        var dates = [
            Date(timeIntervalSince1970: 1),
            Date(timeIntervalSince1970: 2),
            Date(timeIntervalSince1970: 3)
        ]
        let store = makeStore(settings: settings, pasteboard: pasteboard, now: { dates.removeFirst() })

        capture(text("A"), with: pasteboard, store: store)
        let originalID = store.entries[0].id
        capture(text("B"), with: pasteboard, store: store)
        capture(text("A"), with: pasteboard, store: store)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].id, originalID)
        XCTAssertEqual(store.entries[0].createdAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(store.entries.map(\.payload), [text("A"), text("B")])
    }

    @MainActor
    func testItemAndTotalByteRetentionPruneOldest() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryMaximumItems = 10
        let pasteboard = FakeClipboardPasteboardClient()
        let limits = ClipboardHistoryLimits(
            maximumPlainTextBytes: 100,
            maximumRichTextBytesPerRepresentation: 100,
            maximumImageBytes: 100,
            maximumFilesPerEntry: 10,
            maximumURLStringBytes: 100,
            maximumTotalHistoryPayloadBytes: 12
        )
        let store = makeStore(settings: settings, pasteboard: pasteboard, limits: limits)

        for index in 0..<12 {
            capture(text("v\(index)-xx"), with: pasteboard, store: store)
        }

        XCTAssertLessThanOrEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.payload, text("v11-xx"))
        XCTAssertLessThanOrEqual(store.entries.reduce(0) { $0 + $1.payload.byteCount }, 12)
    }

    @MainActor
    func testReducingMaximumItemsPrunesImmediately() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryMaximumItems = 20
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard)
        for index in 0..<15 {
            capture(text("\(index)"), with: pasteboard, store: store)
        }

        settings.clipboardHistoryMaximumItems = 10

        XCTAssertEqual(store.entries.count, 10)
        XCTAssertEqual(store.entries.first?.payload, text("14"))
    }

    @MainActor
    func testCopyBackForEveryKindPromotesOnceAndSuppressesNextPoll() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        var tick: TimeInterval = 0
        let store = makeStore(settings: settings, pasteboard: pasteboard) {
            tick += 1
            return Date(timeIntervalSince1970: tick)
        }
        let payloads: [ClipboardHistoryPayload] = [
            text("copy"),
            .url(URL(string: "mailto:test@example.com")!),
            .files([URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]),
            .imagePNG(Data([1, 2]))
        ]
        for payload in payloads {
            capture(payload, with: pasteboard, store: store)
        }

        for payload in payloads {
            let id = store.entries.first(where: { $0.payload == payload })!.id
            let count = store.entries.count
            XCTAssertTrue(store.copyEntryToPasteboard(id: id))
            XCTAssertEqual(store.entries.count, count)
            XCTAssertEqual(store.entries.first?.id, id)
            store.pollNow()
            XCTAssertEqual(store.entries.count, count)
        }
        XCTAssertEqual(pasteboard.writtenPayloads, payloads)
    }

    @MainActor
    func testFailedCopyBackDoesNotPromote() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard)
        capture(text("A"), with: pasteboard, store: store)
        capture(text("B"), with: pasteboard, store: store)
        let original = store.entries
        pasteboard.writeSucceeds = false

        XCTAssertFalse(store.copyEntryToPasteboard(id: original[1].id))
        XCTAssertEqual(store.entries, original)
    }

    @MainActor
    func testRemoveAndClearAreSafeAndDoNotStopMonitoring() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let persistence = MemoryClipboardPersistence()
        let store = makeStore(
            settings: settings,
            pasteboard: pasteboard,
            persistence: persistence
        )
        capture(text("A"), with: pasteboard, store: store)
        capture(text("B"), with: pasteboard, store: store)
        store.waitForPendingPersistenceForTesting()
        XCTAssertNotNil(persistence.data)

        store.removeEntry(id: UUID())
        XCTAssertEqual(store.entries.count, 2)
        store.removeEntry(id: store.entries[0].id)
        XCTAssertEqual(store.entries.count, 1)
        store.clearHistory()
        store.waitForPendingPersistenceForTesting()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.isMonitoring)
        XCTAssertNil(persistence.data)
    }

    @MainActor
    func testPersistenceRoundTripAndDisablePreservesMemoryButDeletesArchive() throws {
        let persistence = MemoryClipboardPersistence()
        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.clipboardHistoryEnabled = true
        firstSettings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let first = makeStore(
            settings: firstSettings,
            pasteboard: pasteboard,
            persistence: persistence
        )
        capture(text("persisted"), with: pasteboard, store: first)
        first.waitForPendingPersistenceForTesting()
        XCTAssertNotNil(persistence.data)

        let secondSettings = AppSettings(defaults: defaults)
        let second = makeStore(
            settings: secondSettings,
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: persistence
        )
        XCTAssertEqual(second.entries.map(\.payload), [text("persisted")])

        secondSettings.clipboardHistoryPersistenceEnabled = false
        second.waitForPendingPersistenceForTesting()
        XCTAssertEqual(second.entries.map(\.payload), [text("persisted")])
        XCTAssertNil(persistence.data)
    }

    @MainActor
    func testEnablingPersistenceWritesCurrentMemoryWithoutReplacingIt() {
        let persistence = MemoryClipboardPersistence(data: Data("stale".utf8))
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(
            settings: settings,
            pasteboard: pasteboard,
            persistence: persistence
        )
        capture(text("current"), with: pasteboard, store: store)

        settings.clipboardHistoryPersistenceEnabled = true
        store.waitForPendingPersistenceForTesting()

        XCTAssertEqual(store.entries.map(\.payload), [text("current")])
        XCTAssertNoThrow(try JSONDecoder().decode(ClipboardHistoryArchive.self, from: persistence.data!))
    }

    @MainActor
    func testCorruptAndUnknownSchemaArchivesLoadAsEmpty() throws {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryPersistenceEnabled = true
        let corrupt = makeStore(
            settings: settings,
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: MemoryClipboardPersistence(data: Data("bad".utf8))
        )
        XCTAssertTrue(corrupt.entries.isEmpty)

        let unknown = ClipboardHistoryArchive(schemaVersion: 999, entries: [])
        let unknownStore = makeStore(
            settings: settings,
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: MemoryClipboardPersistence(data: try JSONEncoder().encode(unknown))
        )
        XCTAssertTrue(unknownStore.entries.isEmpty)
    }

    @MainActor
    func testLoadedEntriesAreRevalidatedDeduplicatedAndPruned() throws {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryPersistenceEnabled = true
        settings.clipboardHistoryMaximumItems = 10
        var entries: [ClipboardHistoryEntry] = []
        for index in 0..<12 {
            let payload = text(index == 11 ? "10" : "\(index)")
            entries.append(
                .init(
                    id: UUID(),
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    payload: payload,
                    fingerprint: "untrusted"
                )
            )
        }
        entries.append(
            .init(
                id: UUID(),
                createdAt: .distantFuture,
                payload: text(" \n"),
                fingerprint: "invalid"
            )
        )
        let archive = ClipboardHistoryArchive(schemaVersion: 1, entries: entries)
        let store = makeStore(
            settings: settings,
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: MemoryClipboardPersistence(data: try JSONEncoder().encode(archive))
        )

        XCTAssertEqual(store.entries.count, 10)
        XCTAssertFalse(store.entries.contains { $0.payload == text(" \n") })
        XCTAssertEqual(Set(store.entries.map(\.fingerprint)).count, store.entries.count)
    }

    @MainActor
    func testOversizedPersistedImageIsDiscarded() throws {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryPersistenceEnabled = true
        let payload = ClipboardHistoryPayload.imagePNG(Data(repeating: 1, count: 9))
        let archive = ClipboardHistoryArchive(
            schemaVersion: 1,
            entries: [
                .init(id: UUID(), createdAt: Date(), payload: payload, fingerprint: "bad")
            ]
        )
        let limits = ClipboardHistoryLimits(
            maximumPlainTextBytes: 100,
            maximumRichTextBytesPerRepresentation: 100,
            maximumImageBytes: 8,
            maximumFilesPerEntry: 10,
            maximumURLStringBytes: 100,
            maximumTotalHistoryPayloadBytes: 100
        )

        let store = makeStore(
            settings: settings,
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: MemoryClipboardPersistence(data: try JSONEncoder().encode(archive)),
            limits: limits
        )

        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testRapidPersistenceGenerationsLeaveNewestArchive() throws {
        let persistence = MemoryClipboardPersistence()
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(
            settings: settings,
            pasteboard: pasteboard,
            persistence: persistence
        )

        for value in ["old", "middle", "newest"] {
            capture(text(value), with: pasteboard, store: store)
        }
        store.waitForPendingPersistenceForTesting()

        let archive = try JSONDecoder().decode(
            ClipboardHistoryArchive.self,
            from: XCTUnwrap(persistence.data)
        )
        XCTAssertEqual(archive.entries.map(\.payload), store.entries.map(\.payload))
        XCTAssertEqual(archive.entries.first?.payload, text("newest"))
    }

    @MainActor
    func testClearHistoryThenImmediateTerminationDoesNotRestoreEntries() {
        let persistence = MemoryClipboardPersistence()
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard, persistence: persistence)
        capture(text("persisted"), with: pasteboard, store: store)
        store.waitForPendingPersistenceForTesting()

        store.clearHistory()
        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 1),
            .completed
        )

        let restarted = makeStore(
            settings: AppSettings(defaults: defaults),
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: persistence
        )
        XCTAssertNil(persistence.data)
        XCTAssertTrue(restarted.entries.isEmpty)
    }

    @MainActor
    func testDisablePersistenceThenImmediateTerminationDeletesArchiveBeforeRestart() {
        let persistence = MemoryClipboardPersistence()
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard, persistence: persistence)
        capture(text("persisted"), with: pasteboard, store: store)
        store.waitForPendingPersistenceForTesting()

        settings.clipboardHistoryPersistenceEnabled = false
        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 1),
            .completed
        )
        settings.clipboardHistoryPersistenceEnabled = true

        let restarted = makeStore(
            settings: AppSettings(defaults: defaults),
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: persistence
        )
        XCTAssertNil(persistence.data)
        XCTAssertTrue(restarted.entries.isEmpty)
    }

    @MainActor
    func testTerminationPersistsLatestPendingStateBeforeRestart() {
        let persistence = MemoryClipboardPersistence()
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard, persistence: persistence)
        capture(text("older"), with: pasteboard, store: store)
        capture(text("latest"), with: pasteboard, store: store)

        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 1),
            .completed
        )

        let restarted = makeStore(
            settings: AppSettings(defaults: defaults),
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: persistence
        )
        XCTAssertEqual(restarted.entries.map(\.payload), [text("latest"), text("older")])
    }

    @MainActor
    func testOlderInFlightSaveCannotRecreateArchiveAfterNewerDelete() {
        let persistence = ControlledClipboardPersistence(blocksNextSave: true)
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard, persistence: persistence)
        capture(text("obsolete"), with: pasteboard, store: store)
        XCTAssertTrue(persistence.waitForBlockedSaveToStart())

        store.clearHistory()
        persistence.unblockSave()
        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 1),
            .completed
        )

        XCTAssertNil(persistence.data)
        XCTAssertGreaterThanOrEqual(persistence.deleteCount, 1)
    }

    @MainActor
    func testMultiplePendingSavesFinalizeNewestArchive() throws {
        let persistence = ControlledClipboardPersistence()
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard, persistence: persistence)
        for value in ["first", "second", "third"] {
            capture(text(value), with: pasteboard, store: store)
        }

        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 1),
            .completed
        )
        let archive = try JSONDecoder().decode(
            ClipboardHistoryArchive.self,
            from: XCTUnwrap(persistence.data)
        )
        XCTAssertEqual(archive.entries.map(\.payload), store.entries.map(\.payload))
        XCTAssertEqual(archive.entries.first?.payload, text("third"))
    }

    @MainActor
    func testBlockedWriterTimesOutWithoutWaitingIndefinitely() {
        let persistence = ControlledClipboardPersistence(blocksNextSave: true)
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard, persistence: persistence)
        capture(text("blocked"), with: pasteboard, store: store)
        XCTAssertTrue(persistence.waitForBlockedSaveToStart())

        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 0),
            .timedOut
        )

        persistence.unblockSave()
        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 1),
            .completed
        )
        XCTAssertNotNil(persistence.data)
    }

    @MainActor
    func testFinalPersistenceFailuresReturnFailureWithoutCrashing() {
        let saveFailure = ControlledClipboardPersistence(failsSave: true)
        let saveSettings = AppSettings(defaults: defaults)
        saveSettings.clipboardHistoryEnabled = true
        saveSettings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let saveStore = makeStore(
            settings: saveSettings,
            pasteboard: pasteboard,
            persistence: saveFailure
        )
        capture(text("fails"), with: pasteboard, store: saveStore)
        XCTAssertEqual(
            saveStore.finalizePersistenceForTermination(timeout: 1),
            .failed
        )

        let deleteFailure = ControlledClipboardPersistence(
            data: Data("existing".utf8),
            failsDelete: true
        )
        let deleteSettings = AppSettings(defaults: defaults)
        let deleteStore = makeStore(
            settings: deleteSettings,
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: deleteFailure
        )
        XCTAssertEqual(
            deleteStore.finalizePersistenceForTermination(timeout: 1),
            .failed
        )
    }

    @MainActor
    func testTerminationWithNoPendingWorkCompletesAndDeletesAuthoritatively() {
        let persistence = ControlledClipboardPersistence()
        let store = makeStore(
            settings: AppSettings(defaults: defaults),
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: persistence
        )

        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 1),
            .completed
        )
        XCTAssertEqual(persistence.saveCount, 0)
        XCTAssertEqual(persistence.deleteCount, 1)
    }

    @MainActor
    func testMonitoringCannotEnqueueNewPersistenceAfterTerminationBegins() {
        let persistence = ControlledClipboardPersistence()
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard, persistence: persistence)

        XCTAssertEqual(
            store.finalizePersistenceForTermination(timeout: 1),
            .completed
        )
        pasteboard.changeCount += 1
        pasteboard.readResult = .payload(text("late"))
        store.startMonitoring()
        store.pollNow()

        XCTAssertFalse(store.isMonitoring)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(persistence.saveCount, 0)
        XCTAssertEqual(persistence.deleteCount, 1)
    }

    @MainActor
    func testSourceApplicationIsCapturedAtPasteboardChangeTime() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = FakeClipboardPasteboardClient()
        let source = ClipboardSourceApplication(name: "Example", bundleIdentifier: "com.example.app")
        let store = makeStore(
            settings: settings,
            pasteboard: pasteboard,
            sourceApplicationProvider: { source }
        )

        capture(text("source-aware"), with: pasteboard, store: store)

        XCTAssertEqual(store.entries.first?.sourceApplication, source)
    }

    @MainActor
    func testExcludedSourceApplicationIsRejectedBeforeCapture() {
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryExcludedAppBundleIDs = ["com.secret.app"]
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(
            settings: settings,
            pasteboard: pasteboard,
            sourceApplicationProvider: {
                ClipboardSourceApplication(name: "Secret", bundleIdentifier: "com.secret.app")
            }
        )

        capture(text("must never persist"), with: pasteboard, store: store)

        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testFavoriteSurvivesOrdinaryHistoryTrimAndMetadataRoundTrip() throws {
        let persistence = MemoryClipboardPersistence()
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryPersistenceEnabled = true
        settings.clipboardHistoryMaximumItems = 10
        let pasteboard = FakeClipboardPasteboardClient()
        let store = makeStore(settings: settings, pasteboard: pasteboard, persistence: persistence)
        capture(text("keep"), with: pasteboard, store: store)
        let favoriteID = try XCTUnwrap(store.entries.first?.id)
        store.toggleFavorite(id: favoriteID)
        store.renameEntry(id: favoriteID, title: "Pinned note")
        let tag = try XCTUnwrap(store.addTag(name: "Work", color: .blue))
        store.setTag(tag.id, on: favoriteID, enabled: true)

        for index in 0..<16 { capture(text("ordinary-\(index)"), with: pasteboard, store: store) }
        store.waitForPendingPersistenceForTesting()

        let favorite = try XCTUnwrap(store.entries.first(where: { $0.id == favoriteID }))
        XCTAssertTrue(favorite.isFavorite)
        XCTAssertEqual(favorite.customTitle, "Pinned note")
        XCTAssertEqual(favorite.tagIDs, [tag.id])
        XCTAssertLessThanOrEqual(store.entries.filter { !$0.isFavorite }.count, 10)

        let reloadedSettings = AppSettings(defaults: defaults)
        let reloaded = makeStore(
            settings: reloadedSettings,
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: persistence
        )
        let persistedFavorite = try XCTUnwrap(reloaded.entries.first(where: { $0.id == favoriteID }))
        XCTAssertTrue(persistedFavorite.isFavorite)
        XCTAssertEqual(persistedFavorite.customTitle, "Pinned note")
        XCTAssertEqual(reloaded.tags.first?.name, "Work")
    }

    @MainActor
    func testSchemaOneArchiveMigratesWithSafeMetadataDefaults() throws {
        struct LegacyEntry: Codable {
            let id: UUID
            let createdAt: Date
            let payload: ClipboardHistoryPayload
            let fingerprint: String
        }
        struct LegacyArchive: Codable {
            let schemaVersion: Int
            let entries: [LegacyEntry]
        }

        let payload = text("legacy")
        let legacy = LegacyArchive(
            schemaVersion: 1,
            entries: [LegacyEntry(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 1),
                payload: payload,
                fingerprint: ClipboardHistoryFingerprint.make(for: payload)
            )]
        )
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryPersistenceEnabled = true
        let store = makeStore(
            settings: settings,
            pasteboard: FakeClipboardPasteboardClient(),
            persistence: MemoryClipboardPersistence(data: try JSONEncoder().encode(legacy))
        )

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertFalse(store.entries[0].isFavorite)
        XCTAssertNil(store.entries[0].sourceApplication)
        XCTAssertTrue(store.entries[0].tagIDs.isEmpty)
        XCTAssertTrue(store.tags.isEmpty)
    }

    @MainActor
    private func makeStore(
        settings: AppSettings,
        pasteboard: FakeClipboardPasteboardClient,
        persistence: ClipboardHistoryPersistence = MemoryClipboardPersistence(),
        limits: ClipboardHistoryLimits = .standard,
        now: @escaping () -> Date = Date.init,
        sourceApplicationProvider: @escaping () -> ClipboardSourceApplication? = { nil }
    ) -> ClipboardHistoryStore {
        ClipboardHistoryStore(
            settings: settings,
            pasteboard: pasteboard,
            persistence: persistence,
            limits: limits,
            now: now,
            automaticallySchedulesTimer: false,
            sourceApplicationProvider: sourceApplicationProvider
        )
    }

    @MainActor
    private func capture(
        _ payload: ClipboardHistoryPayload,
        with pasteboard: FakeClipboardPasteboardClient,
        store: ClipboardHistoryStore
    ) {
        pasteboard.changeCount += 1
        pasteboard.readResult = .payload(payload)
        store.pollNow()
    }

    private func text(_ value: String) -> ClipboardHistoryPayload {
        .text(.init(plainText: value, rtfData: nil, htmlData: nil))
    }
}
