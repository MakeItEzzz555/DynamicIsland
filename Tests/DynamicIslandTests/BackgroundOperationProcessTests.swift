import XCTest
@testable import DynamicIsland

final class BackgroundOperationProcessTests: XCTestCase {
    func testLargeStderrAndStdoutCompleteWithBoundedFailureDiagnostic() async {
        let executor = ZipCompressionExecutor()
        let id = UUID()
        let finished = expectation(description: "Child with more than pipe capacity on both streams exits")
        let task = Task.detached {
            defer { finished.fulfill(); executor.clearExecutionState(id) }
            // Only shell builtins: cancellation terminates the one owned child,
            // never leaves a pipe-owning grandchild behind after a timeout.
            let script = "i=0; while [ \"$i\" -lt 8192 ]; do printf 'stderr diagnostic payload 0123456789abcdefghijklmnopqrstuvwxyz\\n' >&2; printf 'stdout listing payload 0123456789abcdefghijklmnopqrstuvwxyz\\n'; i=$((i+1)); done; exit 7"
            do {
                _ = try executor.run(operationID: id, executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], captureOutput: true)
                XCTFail("Expected synthetic status 7")
            } catch let error as ZipCompressionError {
                guard case .processFailed(let diagnostic) = error else {
                    return XCTFail("Process must exit before deadline, got \(error)")
                }
                XCTAssertTrue(diagnostic.hasPrefix("stderr diagnostic payload"))
                XCTAssertLessThanOrEqual(diagnostic.utf8.count, 64 * 1024)
            } catch { XCTFail("Unexpected \(error)") }
        }
        // The deadline actively cancels this test's child, so the old pipe
        // deadlock becomes a bounded failure rather than hanging the suite.
        let deadline = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { executor.cancel(operationID: id) }
        }
        await fulfillment(of: [finished], timeout: 5)
        deadline.cancel()
        await task.value
        assertNoDiagnostics(for: id)
    }

    func testDiagnosticFilesAreRemovedOnSuccessAndLaunchFailure() throws {
        let executor = ZipCompressionExecutor()
        let id = UUID()
        defer { executor.clearExecutionState(id) }
        let output = try executor.run(operationID: id, executable: URL(fileURLWithPath: "/bin/sh"),
                                      arguments: ["-c", "printf diagnostic >&2; printf captured"], captureOutput: true)
        XCTAssertEqual(output, Data("captured".utf8))
        assertNoDiagnostics(for: id)
        XCTAssertThrowsError(try executor.run(operationID: id,
                                             executable: URL(fileURLWithPath: "/DynamicIsland-Synthetic-Missing-\(UUID())"), arguments: [])) {
            guard case ZipCompressionError.launchFailed = $0 else { return XCTFail("Unexpected \($0)") }
        }
        assertNoDiagnostics(for: id)
    }

    func testRunningProcessCancellationRemovesDiagnosticFile() async throws {
        let executor = ZipCompressionExecutor()
        let id = UUID()
        let ready = FileManager.default.temporaryDirectory.appendingPathComponent("OperationProcessReady-\(id)")
        defer { try? FileManager.default.removeItem(at: ready); executor.clearExecutionState(id) }
        let finished = expectation(description: "Cancelled child exits")
        let task = Task.detached {
            defer { finished.fulfill() }
            do {
                try executor.run(operationID: id, executable: URL(fileURLWithPath: "/bin/sh"),
                                 arguments: ["-c", "printf ready > \"$1\"; while :; do :; done", "synthetic-child", ready.path])
                XCTFail("Expected cancellation")
            } catch let error as ZipCompressionError { XCTAssertEqual(error, .cancelled) }
            catch { XCTFail("Unexpected \(error)") }
        }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: ready.path) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path), "The owned child must be running before cancellation")
        executor.cancel(operationID: id)
        await fulfillment(of: [finished], timeout: 3)
        await task.value
        assertNoDiagnostics(for: id)
    }

    private func assertNoDiagnostics(for id: UUID, file: StaticString = #filePath, line: UInt = #line) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        XCTAssertFalse(names.contains { $0.hasPrefix("DynamicIsland-ArchiveDiagnostics-\(id.uuidString)-") },
                       "No owned stderr file may survive execution", file: file, line: line)
    }
}
