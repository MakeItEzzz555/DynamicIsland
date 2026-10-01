import XCTest
@testable import DynamicIsland

final class BackgroundOperationRealWorldTests: XCTestCase {
    func testRunningDittoCanBeCancelledAndCleansOwnedArtifacts() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_REAL_COMPRESSION_STRESS"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_REAL_COMPRESSION_STRESS=1 for real compression cancellation.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland-RealCompression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("random.bin")
        try makeRandomFile(source, megabytes: 96)
        let originalSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize

        let executor = ZipCompressionExecutor()
        let operationID = UUID()
        let task = Task {
            try await executor.compress(operationID: operationID, sources: [source])
        }

        try await Task.sleep(for: .milliseconds(120))
        executor.cancel(operationID: operationID)

        do {
            _ = try await task.value
            XCTFail("Expected running compression to be cancelled")
        } catch let error as ZipCompressionError {
            XCTAssertEqual(error, .cancelled)
        } catch is CancellationError {
            // CancellationError is also an acceptable transport-level cancellation.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, originalSize)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("random.bin.zip").path))

        let owned = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("BackgroundOperations", isDirectory: true)
            .appendingPathComponent(operationID.uuidString, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }

    func testConcurrentRealCompressionsRemainIndependent() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_REAL_COMPRESSION_STRESS"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_REAL_COMPRESSION_STRESS=1 for concurrent compression.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland-ConcurrentCompression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first.bin")
        let second = root.appendingPathComponent("second.bin")
        try makeRandomFile(first, megabytes: 16)
        try makeRandomFile(second, megabytes: 16)

        let executor = ZipCompressionExecutor()
        async let firstOutput = executor.compress(operationID: UUID(), sources: [first])
        async let secondOutput = executor.compress(operationID: UUID(), sources: [second])
        let outputs = try await [firstOutput, secondOutput]

        XCTAssertEqual(Set(outputs.map(\.lastPathComponent)), ["first.bin.zip", "second.bin.zip"])
        XCTAssertTrue(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    private func makeRandomFile(_ url: URL, megabytes: Int) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/dd")
        process.arguments = [
            "if=/dev/urandom",
            "of=\(url.path)",
            "bs=1048576",
            "count=\(megabytes)"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw NSError(
                domain: "BackgroundOperationRealWorldTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)]
            )
        }
    }
}

