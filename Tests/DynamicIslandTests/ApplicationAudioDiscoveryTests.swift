import XCTest
@testable import DynamicIsland

@MainActor
final class ApplicationAudioDiscoveryTests: XCTestCase {
    func testOutputIOIsDistinctFromAudibilityAndNeverAdvertisesGainAuthority() async {
        let discovery = ApplicationAudioDiscovery()
        XCTAssertTrue(discovery.outputs.isEmpty)
        discovery.apply([
            .init(objectID: 1, pid: 999998, bundleIdentifier: "test.one", outputIORunning: true),
            .init(objectID: 1, pid: 999998, bundleIdentifier: "test.one", outputIORunning: true),
            .init(objectID: 2, pid: 999997, bundleIdentifier: "test.two", outputIORunning: true),
            .init(objectID: 3, pid: 999996, bundleIdentifier: "test.silent", outputIORunning: false)
        ], generation: 1)
        XCTAssertEqual(discovery.outputs.count, 2)
        for output in discovery.outputs {
            XCTAssertEqual(output.activity, .outputIOActive); XCTAssertNil(output.gain); XCTAssertFalse(output.controlAvailable)
            let result = await discovery.requestGain(0.5, application: output.identity)
            XCTAssertEqual(result, .unsupported)
        }
    }

    func testPIDReuseRefreshAndShutdownInvalidateRequestsWithoutWritingHardware() async throws {
        let discovery = ApplicationAudioDiscovery()
        let process = ApplicationAudioProcess(objectID: 1, pid: 999998, bundleIdentifier: "test.one", outputIORunning: true)
        discovery.apply([process], generation: 1)
        let old = try XCTUnwrap(discovery.outputs.first?.identity)
        discovery.apply([process], generation: 2)
        let stale = await discovery.requestGain(0.2, application: old)
        XCTAssertEqual(stale, .failed(.staleIdentity))
        let current = try XCTUnwrap(discovery.outputs.first?.identity)
        let invalid = await discovery.requestGain(.nan, application: current)
        XCTAssertEqual(invalid, .failed(.invalidValue))
        await discovery.disableRouting()
        let stopped = await discovery.requestGain(0.2, application: current)
        XCTAssertEqual(stopped, .failed(.staleIdentity)); XCTAssertTrue(discovery.outputs.isEmpty)
    }
}
