import Foundation
import ServiceManagement
import XCTest
@testable import DynamicIsland

private final class LoginStatusQueryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private var queriedMain = false
    private let gates: [DispatchSemaphore]
    init(gates: [DispatchSemaphore] = []) { self.gates = gates }
    var count: Int { lock.withLock { reads } }
    var usedMainThread: Bool { lock.withLock { queriedMain } }
    func query() -> SMAppService.Status {
        let index = lock.withLock {
            let index = reads; reads += 1; queriedMain = queriedMain || Thread.isMainThread
            return index
        }
        if gates.indices.contains(index) { _ = gates[index].wait(timeout: .now() + 5) }
        else { Thread.sleep(forTimeInterval: 0.05) }
        return .notRegistered
    }
}

@MainActor
final class LoginItemStatusReaderTests: XCTestCase {
    func testConcurrentReadsShareOneBackgroundQueryAndDoNotCachePermissionState() async throws {
        let probe = LoginStatusQueryProbe()
        let reader = LoginItemStatusReader(query: probe.query)
        let first = Task { await reader.read() }
        let second = Task { await reader.read() }
        let firstResult = await first.value, secondResult = await second.value
        XCTAssertEqual(firstResult, .notRegistered); XCTAssertEqual(secondResult, .notRegistered)
        XCTAssertEqual(probe.count, 1)
        XCTAssertFalse(probe.usedMainThread, "ServiceManagement's synchronous XPC must not block Settings layout")
        _ = await reader.read()
        XCTAssertEqual(probe.count, 2, "Completed reads are not cached as granted permission")
    }

    func testInvalidationKeepsNewQueryOwnedUntilCompletion() async throws {
        let firstGate = DispatchSemaphore(value: 0), newerGate = DispatchSemaphore(value: 0)
        let probe = LoginStatusQueryProbe(gates: [firstGate, newerGate])
        let reader = LoginItemStatusReader(query: probe.query)
        let first = Task { await reader.read() }
        for _ in 0..<1_000 where probe.count == 0 { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(probe.count, 1)
        reader.invalidate()
        let second = Task { await reader.read() }
        for _ in 0..<1_000 where probe.count < 2 { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(probe.count, 2)
        firstGate.signal(); _ = await first.value
        let release = Task { newerGate.signal() }
        _ = await reader.read()
        _ = await second.value; _ = await release.value
        XCTAssertEqual(probe.count, 2, "A stale query cannot discard the newer in-flight query")
    }
}
