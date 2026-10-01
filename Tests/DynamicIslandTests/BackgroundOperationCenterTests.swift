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

