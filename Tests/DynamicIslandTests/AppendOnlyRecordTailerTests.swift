import Darwin
import Foundation
import XCTest
@testable import DynamicIsland

final class AppendOnlyRecordTailerTests: XCTestCase {
    func testFromEndIgnoresExistingContentAndReadsOnlyAppend() async throws {
        let fixture = try Fixture(existing: "old\n")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)

        await tailer.start()
        try fixture.append("new\n")
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["new"])
        await tailer.stop()
    }

    func testBoundedCatchUpReadsSmallExistingFile() async throws {
        let fixture = try Fixture(existing: "one\ntwo\n")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .boundedCatchUp, sink: sink)

        await tailer.start()

        XCTAssertEqual(sink.strings, ["one", "two"])
        await tailer.stop()
    }

    func testCatchUpRetainsOnlyMostRecentTwoThousandRecords() async throws {
        let lines = (0..<2_105).map(String.init).joined(separator: "\n") + "\n"
        let fixture = try Fixture(existing: lines)
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .boundedCatchUp, sink: sink)

        await tailer.start()

        XCTAssertEqual(sink.strings.count, AppendOnlyRecordLimits.maximumCatchUpRecords)
        XCTAssertEqual(sink.strings.first, "105")
        XCTAssertEqual(sink.strings.last, "2104")
        await tailer.stop()
    }

    func testCatchUpLargerThanByteBudgetDiscardsInitialPartialRecord() async throws {
        var bytes = Data(repeating: 0x41, count: AppendOnlyRecordLimits.maximumCatchUpBytes + 128)
        bytes.append(contentsOf: Data("\nrecent\n".utf8))
        let fixture = try Fixture(data: bytes)
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .boundedCatchUp, sink: sink)

        await tailer.start()

        XCTAssertEqual(sink.strings, ["recent"])
        let health = await tailer.healthSnapshot()
        XCTAssertLessThanOrEqual(health.bytesRead, UInt64(AppendOnlyRecordLimits.maximumCatchUpBytes))
        await tailer.stop()
    }

    func testCatchUpPreservesPartialEOFUntilLaterAppend() async throws {
        let fixture = try Fixture(existing: "complete\npart")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .boundedCatchUp, sink: sink)

        await tailer.start()
        XCTAssertEqual(sink.strings, ["complete"])
        try fixture.append("ial\n")
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["complete", "partial"])
        await tailer.stop()
    }

    func testLivePartialRecordCompletesAcrossMultipleAppendBursts() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)
        await tailer.start()

        try fixture.append("first-")
        await tailer.reconcile()
        try fixture.append("second-")
        await tailer.reconcile()
        XCTAssertTrue(sink.strings.isEmpty)
        try fixture.append("third\n")
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["first-second-third"])
        await tailer.stop()
    }

    func testAppendReadsOnlyDeltaRatherThanExistingFileAgain() async throws {
        let fixture = try Fixture(data: Data(repeating: 0x41, count: 512 * 1_024))
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)
        await tailer.start()
        let initialHealth = await tailer.healthSnapshot()
        XCTAssertEqual(initialHealth.bytesRead, 0)

        try fixture.append("new\n")
        await tailer.reconcile()
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["new"])
        let finalHealth = await tailer.healthSnapshot()
        XCTAssertEqual(finalHealth.bytesRead, 4)
        await tailer.stop()
    }

    func testMultipleAppendBurstsAreEmittedOnceInOrder() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)

        await tailer.start()
        try fixture.append("one\ntwo\n")
        await tailer.reconcile()
        try fixture.append("three\n")
        await tailer.reconcile()
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["one", "two", "three"])
        await tailer.stop()
    }

    func testSameInodeTruncationClearsOldPartialBytes() async throws {
        let fixture = try Fixture(existing: "old-part")
        defer { fixture.remove() }
        let sink = RecordSink()
        let notices = NoticeSink()
        let tailer = fixture.tailer(policy: .boundedCatchUp, sink: sink, notices: notices)
        await tailer.start()
        let originalIdentity = await tailer.currentFileIdentity()

        try fixture.truncateAndWrite("fresh\n")
        await tailer.reconcile()

        let currentIdentity = await tailer.currentFileIdentity()
        XCTAssertEqual(currentIdentity, originalIdentity)
        XCTAssertEqual(sink.strings, ["fresh"])
        XCTAssertTrue(notices.values.contains { if case .truncated = $0 { true } else { false } })
        await tailer.stop()
    }

    func testReplacementChangesIdentityAndNeverJoinsOldPartial() async throws {
        let fixture = try Fixture(existing: "old-part")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .boundedCatchUp, sink: sink)
        await tailer.start()
        let oldIdentity = await tailer.currentFileIdentity()

        try fixture.replace(with: "fresh\n")
        await tailer.reconcile()

        let newIdentity = await tailer.currentFileIdentity()
        XCTAssertNotEqual(newIdentity, oldIdentity)
        XCTAssertEqual(sink.strings, ["fresh"])
        let health = await tailer.healthSnapshot()
        XCTAssertEqual(health.rotations, 1)
        await tailer.stop()
    }

    func testDeleteThenRecreateResumesCleanly() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, replacementPolicy: .boundedCatchUp, sink: sink)
        await tailer.start()

        try FileManager.default.removeItem(at: fixture.fileURL)
        await tailer.reconcile()
        let missingHealth = await tailer.healthSnapshot()
        XCTAssertEqual(missingHealth.status, .waitingForFile)
        try Data("recreated\n".utf8).write(to: fixture.fileURL)
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["recreated"])
        let recreatedHealth = await tailer.healthSnapshot()
        XCTAssertEqual(recreatedHealth.status, .tailing)
        await tailer.stop()
    }

    func testMissingFileCanAppearLater() async throws {
        let fixture = try Fixture(missing: true)
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, replacementPolicy: .boundedCatchUp, sink: sink)

        await tailer.start()
        let waitingHealth = await tailer.healthSnapshot()
        XCTAssertEqual(waitingHealth.status, .waitingForFile)
        try Data("appeared\n".utf8).write(to: fixture.fileURL)
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["appeared"])
        await tailer.stop()
    }

    func testStopPreventsLaterReconcileFromEmitting() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)
        await tailer.start()
        await tailer.stop()

        try fixture.append("ignored\n")
        await tailer.reconcile()

        XCTAssertTrue(sink.strings.isEmpty)
        let stoppedHealth = await tailer.healthSnapshot()
        XCTAssertEqual(stoppedHealth.status, .stopped)
    }

    func testStartStopStartCreatesFreshLifecycle() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)
        await tailer.start()
        await tailer.stop()
        try fixture.append("existing-before-restart\n")

        await tailer.start()
        try fixture.append("after-restart\n")
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["after-restart"])
        await tailer.stop()
    }

    func testSymlinkIsRejected() async throws {
        let fixture = try Fixture(missing: true)
        defer { fixture.remove() }
        let target = fixture.directory.appendingPathComponent("target.log")
        try Data("content\n".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fixture.fileURL, withDestinationURL: target)
        let tailer = fixture.tailer(policy: .fromEnd, sink: RecordSink())

        await tailer.start()

        let health = await tailer.healthSnapshot()
        XCTAssertEqual(health.status, .failed)
        XCTAssertEqual(health.lastFailure, .symlinkRejected)
        await tailer.stop()
    }

    func testFilesystemWatcherReceivesAppendWithoutPolling() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let expectation = expectation(description: "watcher emitted appended record")
        let sink = RecordSink { value in
            if value == "watched" { expectation.fulfill() }
        }
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)
        await tailer.start()

        try fixture.append("watched\n")
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(sink.strings, ["watched"])
        await tailer.stop()
    }

    func testParentWatcherDetectsReplacementWithoutPolling() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let expectation = expectation(description: "parent watcher observed replacement")
        let sink = RecordSink { value in
            if value == "replacement" { expectation.fulfill() }
        }
        let tailer = fixture.tailer(
            policy: .fromEnd,
            replacementPolicy: .boundedCatchUp,
            sink: sink
        )
        await tailer.start()

        try fixture.replace(with: "replacement\n")
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(sink.strings, ["replacement"])
        let replacementHealth = await tailer.healthSnapshot()
        XCTAssertEqual(replacementHealth.rotations, 1)
        await tailer.stop()
    }

    func testParentWatcherDetectsDeleteAndRecreateWithoutPolling() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let expectation = expectation(description: "parent watcher observed recreation")
        let sink = RecordSink { value in
            if value == "recreated" { expectation.fulfill() }
        }
        let tailer = fixture.tailer(
            policy: .fromEnd,
            replacementPolicy: .boundedCatchUp,
            sink: sink
        )
        await tailer.start()

        try FileManager.default.removeItem(at: fixture.fileURL)
        try Data("recreated\n".utf8).write(to: fixture.fileURL)
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(sink.strings, ["recreated"])
        await tailer.stop()
    }

    func testStaleFileSignalCannotAffectRestartedTailer() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)
        await tailer.start()
        let staleToken = await tailer.currentFileSignalToken()
        await tailer.stop()
        try fixture.append("ignored-existing\n")
        await tailer.start()
        try fixture.append("new")
        await tailer.reconcile()
        let bytesBeforeStaleSignal = (await tailer.healthSnapshot()).bytesRead

        await tailer.reconcile(fileSignal: staleToken)
        let bytesAfterStaleSignal = (await tailer.healthSnapshot()).bytesRead
        XCTAssertTrue(sink.strings.isEmpty)
        XCTAssertEqual(bytesAfterStaleSignal, bytesBeforeStaleSignal)
        try fixture.append("\n")
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["new"])
        await tailer.stop()
    }

    func testRapidRecordFloodPreservesOrderAndBounds() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)
        await tailer.start()
        let expected = (0..<1_000).map { "record-\($0)" }

        try fixture.append(expected.joined(separator: "\n") + "\n")
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, expected)
        let floodHealth = await tailer.healthSnapshot()
        XCTAssertEqual(floodHealth.recordsEmitted, 1_000)
        await tailer.stop()
    }

    func testOversizedRecordIsDroppedAndLaterRecordRecovers() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)
        await tailer.start()
        var payload = Data(repeating: 0x41, count: AppendOnlyRecordLimits.maximumRecordBytes + 1)
        payload.append(contentsOf: Data("\nrecovered\n".utf8))

        try fixture.append(payload)
        await tailer.reconcile()

        XCTAssertEqual(sink.strings, ["recovered"])
        let recoveryHealth = await tailer.healthSnapshot()
        XCTAssertEqual(recoveryHealth.oversizeRecordsDropped, 1)
        await tailer.stop()
    }

    func testMissingFileAppearanceIsDetectedByParentWatcher() async throws {
        let fixture = try Fixture(missing: true)
        defer { fixture.remove() }
        let expectation = expectation(description: "parent watcher observed file creation")
        let sink = RecordSink { value in
            if value == "created" { expectation.fulfill() }
        }
        let tailer = fixture.tailer(
            policy: .fromEnd,
            replacementPolicy: .boundedCatchUp,
            sink: sink
        )
        await tailer.start()

        try Data("created\n".utf8).write(to: fixture.fileURL)
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(sink.strings, ["created"])
        await tailer.stop()
    }

    func testRepeatedStartRotateStopDoesNotLeakDescriptors() async throws {
        let fixture = try Fixture(existing: "")
        defer { fixture.remove() }
        let baseline = openDescriptorCount()
        let sink = RecordSink()
        let tailer = fixture.tailer(policy: .fromEnd, sink: sink)

        for index in 0..<10 {
            await tailer.start()
            try fixture.append("\(index)\n")
            await tailer.reconcile()
            try fixture.replace(with: "rotated-\(index)\n")
            await tailer.reconcile()
            await tailer.stop()
        }

        XCTAssertLessThanOrEqual(openDescriptorCount(), baseline)
    }
}

private final class RecordSink: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [Data] = []
    private let observer: @Sendable (String) -> Void

    init(observer: @escaping @Sendable (String) -> Void = { _ in }) {
        self.observer = observer
    }

    func append(_ data: Data) {
        let string = String(decoding: data, as: UTF8.self)
        lock.lock()
        records.append(data)
        lock.unlock()
        observer(string)
    }

    var strings: [String] {
        lock.lock()
        defer { lock.unlock() }
        return records.map { String(decoding: $0, as: UTF8.self) }
    }
}

private final class NoticeSink: @unchecked Sendable {
    private let lock = NSLock()
    private var notices: [AppendOnlyRecordTailerNotice] = []

    func append(_ notice: AppendOnlyRecordTailerNotice) {
        lock.lock()
        notices.append(notice)
        lock.unlock()
    }

    var values: [AppendOnlyRecordTailerNotice] {
        lock.lock()
        defer { lock.unlock() }
        return notices
    }
}

private final class Fixture {
    let directory: URL
    let fileURL: URL

    init(existing: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland-Tailer-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("records.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(existing.utf8).write(to: fileURL)
    }

    init(data: Data) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland-Tailer-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("records.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    init(missing: Bool) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland-Tailer-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("records.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !missing { try Data().write(to: fileURL) }
    }

    func tailer(
        policy: AppendOnlyRecordStartPolicy,
        replacementPolicy: AppendOnlyRecordStartPolicy = .boundedCatchUp,
        sink: RecordSink,
        notices: NoticeSink? = nil
    ) -> AppendOnlyRecordTailer {
        AppendOnlyRecordTailer(
            fileURL: fileURL,
            initialPolicy: policy,
            replacementPolicy: replacementPolicy,
            onRecord: sink.append,
            onNotice: { notices?.append($0) }
        )
    }

    func append(_ string: String) throws {
        try append(Data(string.utf8))
    }

    func append(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    func truncateAndWrite(_ string: String) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(string.utf8))
        try handle.synchronize()
    }

    func replace(with string: String) throws {
        let replacement = directory.appendingPathComponent("replacement.log")
        try Data(string.utf8).write(to: replacement)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: replacement, to: fileURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func openDescriptorCount() -> Int {
    let maximum = min(Int(getdtablesize()), 16_384)
    return (0..<maximum).reduce(into: 0) { count, descriptor in
        errno = 0
        if fcntl(Int32(descriptor), F_GETFD) != -1 || errno != EBADF {
            count += 1
        }
    }
}
