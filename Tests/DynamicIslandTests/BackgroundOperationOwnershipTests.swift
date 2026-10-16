import XCTest
@testable import DynamicIsland

@MainActor
final class BackgroundOperationOwnershipTests: XCTestCase {
    @MainActor private struct Fixture {
        let root: URL
        let source: URL
        let ownership: TemporaryFileOwnershipLedger

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("OperationOwnership-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            source = root.appendingPathComponent("promised.txt")
            try Data("Promised source".utf8).write(to: source)
            ownership = TemporaryFileOwnershipLedger(temporaryRoots: [root])
            ownership.retain([source], by: .shelf)
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    func testCancellationAndClearingKeepSourceUntilSuspendedBackendUnwinds() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore(), ownership: fixture.ownership)
        let gate = OperationReadGate()
        let read = expectation(description: "Backend can still read after cancellation")
        let settled = expectation(description: "Cancelled backend unwound")
        let source = fixture.source
        let id = try XCTUnwrap(controller.start(
            kind: .imageConversion, title: "Synthetic suspended reader", sources: [source], destination: nil,
            onCompleted: { _ in XCTFail("Cancelled work must not publish success") },
            onFailed: { _ in settled.fulfill() }
        ) { _ in
            await gate.wait()
            _ = try Data(contentsOf: source)
            read.fulfill()
            return source
        })
        // BasketManager owns this public-id claim; the controller needs its own lease.
        fixture.ownership.retain([source], by: .operation(id))
        fixture.ownership.release([source], by: .shelf)
        for _ in 0..<200 {
            if await gate.hasEntered { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let entered = await gate.hasEntered
        XCTAssertTrue(entered, "Backend must be suspended before cancellation")
        controller.cancel(id)
        controller.clearFinished()
        fixture.ownership.release([source], by: .operation(id))
        XCTAssertNil(controller.operation(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "UI cancellation/clear cannot end a backend's source lease")
        await gate.release()
        await fulfillment(of: [read, settled], timeout: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(fixture.ownership.owners(of: source).isEmpty)
    }

    func testCancellationBeforeSchedulingReleasesSourceWithoutRunningBackend() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore(), ownership: fixture.ownership)
        let settled = expectation(description: "Queued cancellation settled")
        let source = fixture.source
        let id = try XCTUnwrap(controller.start(
            kind: .imageConversion, title: "Queued reader", sources: [source], destination: nil,
            onCompleted: nil, onFailed: { _ in settled.fulfill() }
        ) { _ in
            XCTFail("Cancellation before scheduling must not run the backend")
            return source
        })
        controller.cancel(id)
        fixture.ownership.release([source], by: .shelf)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Lease is retained synchronously at intake")
        await fulfillment(of: [settled], timeout: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(fixture.ownership.owners(of: source).isEmpty)
    }

    func testBackendFailureReleasesSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let controller = BackgroundOperationController(liveActivities: LiveActivityStore(), ownership: fixture.ownership)
        let settled = expectation(description: "Failed backend settled")
        var failure: String?
        let source = fixture.source
        let id = try XCTUnwrap(controller.start(
            kind: .imageConversion, title: "Failing reader", sources: [source], destination: nil,
            onCompleted: nil, onFailed: { failure = $0; settled.fulfill() }
        ) { _ in
            _ = try Data(contentsOf: source)
            throw ZipCompressionError.processFailed("Synthetic failure")
        })
        fixture.ownership.release([source], by: .shelf)
        await fulfillment(of: [settled], timeout: 3)
        XCTAssertEqual(controller.operation(id)?.state, .failed)
        XCTAssertEqual(failure, "Compression failed: Synthetic failure")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(fixture.ownership.owners(of: source).isEmpty)
    }

    func testControllerReleasedBeforeSchedulingStillReleasesSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var controller: BackgroundOperationController? = BackgroundOperationController(liveActivities: LiveActivityStore(), ownership: fixture.ownership)
        weak var weakController = controller
        let source = fixture.source
        _ = controller?.start(kind: .imageConversion, title: "Abandoned reader", sources: [source], destination: nil,
                              onCompleted: nil, onFailed: nil) { _ in
            XCTFail("An abandoned queued controller must not start work")
            return source
        }
        controller = nil
        XCTAssertNil(weakController)
        fixture.ownership.release([source], by: .shelf)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        for _ in 0..<200 {
            if !FileManager.default.fileExists(atPath: source.path) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(fixture.ownership.owners(of: source).isEmpty)
    }
}

private actor OperationReadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasEntered = false

    func wait() async {
        await withCheckedContinuation {
            continuation = $0
            hasEntered = true
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
