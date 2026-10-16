import CoreGraphics
import ImageIO
import zlib
import XCTest
@testable import DynamicIsland

final class BackgroundOperationCompressionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundOperationCompressionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    func testArchiveDestinationUsesFinderLikeNamingAndCollisionSuffix() throws {
        let source = root.appendingPathComponent("Project")
        try Data("source".utf8).write(to: source)

        let first = try ZipCompressionExecutor.archiveDestination(for: [source])
        XCTAssertEqual(first.lastPathComponent, "Project.zip")

        try Data().write(to: first)
        let second = try ZipCompressionExecutor.archiveDestination(for: [source])
        XCTAssertEqual(second.lastPathComponent, "Project 2.zip")

        let another = root.appendingPathComponent("Other")
        try Data().write(to: another)
        let multi = try ZipCompressionExecutor.archiveDestination(for: [source, another])
        XCTAssertEqual(multi.lastPathComponent, "Archive.zip")
    }

    func testRealSingleFileCompressionProducesValidArchiveAndLeavesSourceUntouched() async throws {
        let source = root.appendingPathComponent("note.txt")
        let original = Data("hello archive".utf8)
        try original.write(to: source)

        let output = try await ZipCompressionExecutor().compress(
            operationID: UUID(),
            sources: [source]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: source), original)
        let entries = try archiveEntries(output)
        XCTAssertTrue(entries.contains("note.txt"))
    }

    func testRealMixedCompressionPreservesFileAndNestedFolderContents() async throws {
        let file = root.appendingPathComponent("first.txt")
        try Data("first".utf8).write(to: file)

        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let nested = folder.appendingPathComponent("nested.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nested)

        let output = try await ZipCompressionExecutor().compress(
            operationID: UUID(),
            sources: [file, folder]
        )

        XCTAssertEqual(output.lastPathComponent, "Archive.zip")
        let entries = try archiveEntries(output)
        XCTAssertTrue(entries.contains("first.txt"))
        XCTAssertTrue(entries.contains("Folder/"))
        XCTAssertTrue(entries.contains("Folder/nested.txt"))
        XCTAssertEqual(try Data(contentsOf: file), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: nested), Data("nested".utf8))
    }

    func testMissingSourceFailsClosedWithoutArchive() async throws {
        let missing = root.appendingPathComponent("missing.txt")
        do {
            _ = try await ZipCompressionExecutor().compress(
                operationID: UUID(),
                sources: [missing]
            )
            XCTFail("Expected missing source failure")
        } catch let error as ZipCompressionError {
            XCTAssertEqual(error, .missingSource("missing.txt"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing.txt.zip").path))
    }

    private func archiveEntries(_ archive: URL) throws -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archive.path]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }
}

@MainActor
final class BackgroundOperationControllerTests: XCTestCase {
    func testSameSourceCreatesDistinctOperationIdentities() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore())

        let first = try XCTUnwrap(controller.startCompression(sources: [fixture.source]))
        let second = try XCTUnwrap(controller.startCompression(sources: [fixture.source]))
        XCTAssertNotEqual(first, second)

        controller.cancel(first)
        controller.cancel(second)
        XCTAssertEqual(controller.operation(first)?.state, .cancelled)
        XCTAssertEqual(controller.operation(second)?.state, .cancelled)
    }

    func testGenerationScopedProgressRejectsStaleAndRegressingUpdates() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore())
        let id = try XCTUnwrap(controller.startCompression(sources: [fixture.source]))
        let generation = try XCTUnwrap(controller.operation(id)?.generation)

        XCTAssertTrue(controller.updateProgress(
            operationID: id,
            generation: generation,
            progress: .determinate(0.5)
        ))
        XCTAssertFalse(controller.updateProgress(
            operationID: id,
            generation: UUID(),
            progress: .determinate(0.8)
        ))
        XCTAssertFalse(controller.updateProgress(
            operationID: id,
            generation: generation,
            progress: .determinate(0.4)
        ))
        XCTAssertEqual(controller.operation(id)?.progress, .determinate(0.5))

        controller.cancel(id)
    }

    func testCancellationIsOperationSpecificAndTerminalStateCannotBeOverwritten() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore())
        let first = try XCTUnwrap(controller.startCompression(sources: [fixture.source]))
        let second = try XCTUnwrap(controller.startCompression(sources: [fixture.source]))

        controller.cancel(first)

        XCTAssertEqual(controller.operation(first)?.state, .cancelled)
        XCTAssertNotEqual(controller.operation(second)?.state, .cancelled)
        let generation = try XCTUnwrap(controller.operation(first)?.generation)
        XCTAssertFalse(controller.updateProgress(
            operationID: first,
            generation: generation,
            progress: .determinate(1)
        ))
        XCTAssertEqual(controller.operation(first)?.state, .cancelled)

        controller.cancel(second)
    }

    func testRealControllerCompletionPublishesResultAndLiveActivity() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let liveActivities = LiveActivityStore()
        let controller = BackgroundOperationController(liveActivities: liveActivities)
        let id = try XCTUnwrap(controller.startCompression(sources: [fixture.source]))

        let terminal = try await waitForTerminal(controller: controller, id: id)
        XCTAssertEqual(terminal.state, .completed)
        let output = try XCTUnwrap(terminal.result?.outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(liveActivities.activities.contains {
            $0.title == terminal.title && $0.kind == .backgroundOperation
        })
    }

    func testImmediateCancellationLeavesNoPublishedArchive() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore())
        let id = try XCTUnwrap(controller.startCompression(sources: [fixture.source]))
        let expected = try XCTUnwrap(controller.operation(id)?.destination)

        controller.cancel(id)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(controller.operation(id)?.state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expected.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testPresentationOrderPrioritizesFailureThenActiveThenCompleted() {
        let now = Date()
        let failed = makeOperation(state: .failed, date: now.addingTimeInterval(-10))
        let running = makeOperation(state: .running, date: now)
        let completed = makeOperation(state: .completed, date: now.addingTimeInterval(10))

        XCTAssertEqual(
            BackgroundOperationController.presentationOrder([completed, running, failed]).map(\.state),
            [.failed, .running, .completed]
        )
    }

    private func makeOperation(state: BackgroundOperationState, date: Date) -> BackgroundOperation {
        BackgroundOperation(
            id: UUID(),
            generation: UUID(),
            kind: .compression,
            title: state.rawValue,
            subtitle: nil,
            sources: [],
            destination: nil,
            state: state,
            progress: .indeterminate,
            createdAt: date,
            startedAt: state == .queued ? nil : date,
            completedAt: state.isTerminal ? date : nil,
            failure: state == .failed
                ? BackgroundOperationFailure(code: .operationFailed, message: "failed")
                : nil,
            result: nil,
            supportsCancellation: state.isActive
        )
    }

    private func waitForTerminal(
        controller: BackgroundOperationController,
        id: UUID
    ) async throws -> BackgroundOperation {
        for _ in 0..<250 {
            if let operation = controller.operation(id), operation.state.isTerminal {
                return operation
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Operation did not reach a terminal state")
        throw CancellationError()
    }

    private struct Fixture {
        let root: URL
        let source: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("BackgroundOperationControllerTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            source = root.appendingPathComponent("source.txt")
            try Data("controller".utf8).write(to: source)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

// MARK: - Extraction and conversion kinds

/// Hand-built stored ZIPs so hostile entry names and symlinks can be tested
/// without a tool that would sanitize them.
enum TestZip {
    struct Entry {
        let name: String
        let data: Data
        var mode: UInt32 = 0o100644
    }

    static func build(_ entries: [Entry]) -> Data {
        var body = Data(), central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let size = UInt32(entry.data.count)
            let crc = UInt32(entry.data.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(entry.data.count)) })
            let offset = UInt32(body.count)
            body.putLE(UInt32(0x04034b50)); body.putLE(UInt16(20)); body.putLE(UInt16(0)); body.putLE(UInt16(0)); body.putLE(UInt16(0)); body.putLE(UInt16(33))
            body.putLE(crc); body.putLE(size); body.putLE(size); body.putLE(UInt16(name.count)); body.putLE(UInt16(0))
            body.append(name); body.append(entry.data)
            central.putLE(UInt32(0x02014b50)); central.putLE(UInt16(3 << 8 | 20)); central.putLE(UInt16(20)); central.putLE(UInt16(0))
            central.putLE(UInt16(0)); central.putLE(UInt16(0)); central.putLE(UInt16(33))
            central.putLE(crc); central.putLE(size); central.putLE(size); central.putLE(UInt16(name.count))
            central.putLE(UInt16(0)); central.putLE(UInt16(0)); central.putLE(UInt16(0)); central.putLE(UInt16(0))
            central.putLE(entry.mode << 16); central.putLE(offset)
            central.append(name)
        }
        var end = Data()
        end.putLE(UInt32(0x06054b50)); end.putLE(UInt16(0)); end.putLE(UInt16(0))
        end.putLE(UInt16(entries.count)); end.putLE(UInt16(entries.count))
        end.putLE(UInt32(central.count)); end.putLE(UInt32(body.count)); end.putLE(UInt16(0))
        return body + central + end
    }
}

extension Data {
    mutating func putLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

@MainActor
final class BackgroundOperationExtractionTests: XCTestCase {
    private var root: URL!
    private var work: URL!   // archives live here; anything outside is "outside"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundOperationExtractionTests-\(UUID().uuidString)", isDirectory: true)
        work = root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeZip(_ name: String, _ entries: [TestZip.Entry]) throws -> URL {
        let url = work.appendingPathComponent(name)
        try TestZip.build(entries).write(to: url)
        return url
    }

    private func names(in directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    private func assertRefused(_ archive: URL, file: StaticString = #filePath, line: UInt = #line) async throws {
        let before = names(in: root)
        do {
            _ = try await ZipCompressionExecutor().extract(operationID: UUID(), archive: archive)
            XCTFail("Hostile archive was extracted", file: file, line: line)
        } catch let error as ZipCompressionError {
            guard case .unsafeArchive = error else { return XCTFail("Unexpected \(error)", file: file, line: line) }
        }
        XCTAssertTrue(names(in: work).allSatisfy { $0.hasSuffix(".zip") }, "No destination or staging left", file: file, line: line)
        XCTAssertEqual(names(in: root), before, "Nothing written outside the work folder", file: file, line: line)
    }

    func testExtractionRoundTripUsesCollisionSafeFolderAndLeavesArchive() async throws {
        let source = work.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("two".utf8).write(to: source.appendingPathComponent("sub/b.txt"))
        let archive = try await ZipCompressionExecutor().compress(operationID: UUID(), sources: [source])
        let archiveData = try Data(contentsOf: archive)
        try FileManager.default.removeItem(at: source)

        let first = try await ZipCompressionExecutor().extract(operationID: UUID(), archive: archive)
        XCTAssertEqual(first.lastPathComponent, "Project")
        XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent("Project/sub/b.txt")), Data("two".utf8))
        let second = try await ZipCompressionExecutor().extract(operationID: UUID(), archive: archive)
        XCTAssertEqual(second.lastPathComponent, "Project 2")
        XCTAssertEqual(try Data(contentsOf: archive), archiveData)
        XCTAssertEqual(names(in: work), ["Project.zip", "Project", "Project 2"])
    }

    func testZipSlipRelativeTraversalIsRefusedWithNothingWritten() async throws {
        let archive = try writeZip("slip.zip", [
            .init(name: "ok.txt", data: Data("ok".utf8)),
            .init(name: "../escaped.txt", data: Data("x".utf8)),
        ])
        try await assertRefused(archive)
    }

    func testAbsolutePathEntryIsRefusedWithNothingWritten() async throws {
        let target = root.appendingPathComponent("abs.txt").path
        let archive = try writeZip("abs.zip", [.init(name: target, data: Data("x".utf8))])
        try await assertRefused(archive)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target))
    }

    func testSymlinkEscapingDestinationIsRefusedAndEntriesUnderLinksAreRefused() async throws {
        let link = UInt32(0o120777)
        // Link pointing outside, nothing nested.
        try await assertRefused(try writeZip("link-out.zip", [.init(name: "out", data: Data("../..".utf8), mode: link)]))
        try await assertRefused(try writeZip("link-abs.zip", [.init(name: "etc", data: Data("/etc".utf8), mode: link)]))
        // Write-through-link attack: link, then a file beneath it.
        try await assertRefused(try writeZip("link-through.zip", [
            .init(name: "dir", data: Data(root.path.utf8), mode: link),
            .init(name: "dir/pwn.txt", data: Data("x".utf8)),
        ]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("pwn.txt").path))
    }

    func testInternalRelativeSymlinkIsAllowed() async throws {
        let archive = try writeZip("inner.zip", [
            .init(name: "real.txt", data: Data("r".utf8)),
            .init(name: "alias", data: Data("real.txt".utf8), mode: 0o120777),
        ])
        let output = try await ZipCompressionExecutor().extract(operationID: UUID(), archive: archive)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: output.appendingPathComponent("alias").path), "real.txt")
    }

    func testUnsafeEntryClassifier() {
        XCTAssertNil(ZipCompressionExecutor.unsafeEntry(names: ["a/", "a/b.txt", "..hidden", "a..b/c"], symlinks: ["a/l"]))
        XCTAssertNotNil(ZipCompressionExecutor.unsafeEntry(names: ["a/../b"], symlinks: []))
        XCTAssertNotNil(ZipCompressionExecutor.unsafeEntry(names: ["a\\..\\b"], symlinks: []))
        XCTAssertNotNil(ZipCompressionExecutor.unsafeEntry(names: ["/etc/x"], symlinks: []))
        XCTAssertNotNil(ZipCompressionExecutor.unsafeEntry(names: ["L", "l/x"], symlinks: ["L"]), "case-insensitive volumes")
    }

    func testNonZipAndMissingArchivesFailClosed() async throws {
        let text = work.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: text)
        do { _ = try await ZipCompressionExecutor().extract(operationID: UUID(), archive: text); XCTFail() }
        catch let error as ZipCompressionError { XCTAssertEqual(error, .notAnArchive) }
        do { _ = try await ZipCompressionExecutor().extract(operationID: UUID(), archive: work.appendingPathComponent("no.zip")); XCTFail() }
        catch let error as ZipCompressionError { XCTAssertEqual(error, .missingSource("no.zip")) }
        let corrupt = work.appendingPathComponent("bad.zip")
        try Data("not a zip".utf8).write(to: corrupt)
        do { _ = try await ZipCompressionExecutor().extract(operationID: UUID(), archive: corrupt); XCTFail() } catch {}
        XCTAssertEqual(names(in: work), ["a.txt", "bad.zip"])
    }

    func testControllerExtractionReportsLifecycleAndLiveActivity() async throws {
        let archive = try writeZip("job.zip", [.init(name: "f.txt", data: Data("f".utf8))])
        let live = LiveActivityStore()
        let controller = BackgroundOperationController(liveActivities: live)
        let id = try XCTUnwrap(controller.startExtraction(archive: archive))
        XCTAssertEqual(controller.operation(id)?.kind, .extraction)
        let done = try await waitForTerminal(controller, id)
        XCTAssertEqual(done.state, .completed)
        XCTAssertEqual(done.result?.outputURL.lastPathComponent, "job")
        XCTAssertTrue(live.activities.contains { $0.title == done.title && $0.kind == .backgroundOperation })
    }

    func testControllerRefusalSurfacesAsFailedOperation() async throws {
        let archive = try writeZip("evil.zip", [.init(name: "../x", data: Data("x".utf8))])
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore())
        let id = try XCTUnwrap(controller.startExtraction(archive: archive))
        let done = try await waitForTerminal(controller, id)
        XCTAssertEqual(done.state, .failed)
        XCTAssertEqual(done.failure?.code, .unsupported)
        XCTAssertEqual(names(in: work), ["evil.zip"])
    }

    func testCancelledExtractionRemovesPartialOutput() async throws {
        // Large stored entry so ditto is still running when cancel lands.
        let archive = try writeZip("big.zip", [.init(name: "big.bin", data: Data(count: 64 * 1024 * 1024))])
        let executor = ZipCompressionExecutor()
        let id = UUID()
        let task = Task { try await executor.extract(operationID: id, archive: archive) }
        // Cancel as soon as the hidden staging folder exists (extraction in flight).
        while !names(in: work).contains(where: { $0.hasPrefix(".DynamicIsland-Extract-") }) { await Task.yield() }
        executor.cancel(operationID: id)
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch let error as ZipCompressionError { XCTAssertEqual(error, .cancelled) }
        catch is CancellationError {}
        XCTAssertEqual(names(in: work), ["big.zip"])
    }

    func testControllerCancelStopsExtractionAndLeavesNoOutput() async throws {
        let archive = try writeZip("c.zip", [.init(name: "big.bin", data: Data(count: 32 * 1024 * 1024))])
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore())
        let id = try XCTUnwrap(controller.startExtraction(archive: archive))
        controller.cancel(id)
        XCTAssertEqual(controller.operation(id)?.state, .cancelled)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(controller.operation(id)?.state, .cancelled)
        XCTAssertEqual(names(in: work), ["c.zip"])
    }

    // MARK: Conversion kinds

    func testImageConversionRunsAsOperationAndKeepsPublicConvertCompatible() async throws {
        let png = try writePNG()
        let live = LiveActivityStore()
        let controller = BackgroundOperationController(liveActivities: live)
        var completed: URL?
        let id = try XCTUnwrap(controller.startImageConversion(png, to: .jpeg) { completed = $0 })
        XCTAssertEqual(controller.operation(id)?.kind, .imageConversion)
        let done = try await waitForTerminal(controller, id)
        XCTAssertEqual(done.state, .completed)
        XCTAssertEqual(completed?.lastPathComponent, "pic.jpg")
        XCTAssertTrue(live.activities.contains { $0.title == done.title && $0.kind == .backgroundOperation })
        // Unchanged entry point still works and stays collision safe.
        let direct = try await FileConversionController.convert(png, to: .jpeg)
        XCTAssertEqual(direct.lastPathComponent, "pic 2.jpg")
    }

    func testImageConversionFailureAndCancelAreReported() async throws {
        let text = work.appendingPathComponent("t.png")
        try Data("not an image".utf8).write(to: text)
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore())
        var reason: String?
        let bad = try XCTUnwrap(controller.startImageConversion(text, to: .jpeg, onFailed: { reason = $0 }))
        let failed = try await waitForTerminal(controller, bad)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertNotNil(reason)

        let png = try writePNG()
        let id = try XCTUnwrap(controller.startImageConversion(png, to: .tiff))
        controller.cancel(id)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.operation(id)?.state, .cancelled)
        XCTAssertFalse(names(in: work).contains { $0.hasPrefix(".DynamicIsland") })
    }

    func testAudioConversionRunsAsOperation() async throws {
        let wav = work.appendingPathComponent("tone.wav")
        try Self.makeWAV().write(to: wav)
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore())
        let id = try XCTUnwrap(controller.startAudioConversion(wav, to: .aiff))
        XCTAssertEqual(controller.operation(id)?.kind, .audioConversion)
        let done = try await waitForTerminal(controller, id)
        XCTAssertEqual(done.state, .completed)
        XCTAssertEqual(done.result?.outputURL.pathExtension, "aiff")

        let cancelled = try XCTUnwrap(controller.startAudioConversion(wav, to: .aiff))
        controller.cancel(cancelled)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.operation(cancelled)?.state, .cancelled)
    }

    private func writePNG() throws -> URL {
        let url = work.appendingPathComponent("pic.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// 0.5 s of 16-bit mono PCM.
    private static func makeWAV() -> Data {
        var samples = Data()
        for index in 0..<4_000 { samples.putLE(Int16(8_000 * sin(Double(index) / 10))) }
        var wav = Data("RIFF".utf8)
        wav.putLE(UInt32(36 + samples.count)); wav.append(Data("WAVEfmt ".utf8))
        wav.putLE(UInt32(16)); wav.putLE(UInt16(1)); wav.putLE(UInt16(1))
        wav.putLE(UInt32(8_000)); wav.putLE(UInt32(16_000)); wav.putLE(UInt16(2)); wav.putLE(UInt16(16))
        wav.append(Data("data".utf8)); wav.putLE(UInt32(samples.count)); wav.append(samples)
        return wav
    }

    private func waitForTerminal(_ controller: BackgroundOperationController, _ id: UUID) async throws -> BackgroundOperation {
        for _ in 0..<500 {
            if let operation = controller.operation(id), operation.state.isTerminal { return operation }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Operation did not reach a terminal state")
        throw CancellationError()
    }
}
