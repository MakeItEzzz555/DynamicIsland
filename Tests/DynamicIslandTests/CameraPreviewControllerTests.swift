import AVFoundation
import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
private final class FakeCameraDevices: CameraDeviceProviding {
    var permissionState: CameraPermissionState = .notDetermined
    var grant: CameraPermissionState = .authorized
    var devices: [CameraDeviceDescriptor] = [
        CameraDeviceDescriptor(id: "ext", name: "Desk Camera", isBuiltIn: false),
        CameraDeviceDescriptor(id: "builtin", name: "FaceTime HD Camera", isBuiltIn: true)
    ]
    var requestCount = 0

    func requestAccess() async -> CameraPermissionState {
        requestCount += 1
        permissionState = grant
        return permissionState
    }

    func availableDevices() -> [CameraDeviceDescriptor] { devices }
}

@MainActor
private final class FakeCaptureSession: CameraCaptureSessionControlling {
    var previewSession: AVCaptureSession? { nil }
    var onUnexpectedStop: ((String) -> Void)?
    var startError: Error?
    var isRunning = false
    var startedDeviceIDs: [String] = []
    var stopCount = 0
    var immediateStopCount = 0
    var activitiesAtStop: [[DynamicIslandLiveActivityKind]] = []
    weak var activities: LiveActivityStore?

    func start(deviceID: String) async throws {
        if let startError { throw startError }
        startedDeviceIDs.append(deviceID)
        isRunning = true
    }

    func stop() async {
        stopCount += 1
        activitiesAtStop.append(activities?.activities.map(\.kind) ?? [])
        isRunning = false
    }

    func stopImmediately() {
        immediateStopCount += 1
        isRunning = false
    }
}

@MainActor
final class CameraPreviewControllerTests: XCTestCase {
    func testPermissionMapping() {
        XCTAssertEqual(SystemCameraDeviceProvider.map(.notDetermined), .notDetermined)
        XCTAssertEqual(SystemCameraDeviceProvider.map(.denied), .denied)
        XCTAssertEqual(SystemCameraDeviceProvider.map(.restricted), .restricted)
        XCTAssertEqual(SystemCameraDeviceProvider.map(.authorized), .authorized)

        XCTAssertEqual(CameraPreviewController.capabilityMapping(permission: .notDetermined, hasDevices: true).permission, .notDetermined)
        XCTAssertEqual(CameraPreviewController.capabilityMapping(permission: .denied, hasDevices: true).permission, .denied)
        XCTAssertEqual(CameraPreviewController.capabilityMapping(permission: .authorized, hasDevices: true).permission, .granted)
        guard case .unsupported = CameraPreviewController.capabilityMapping(permission: .restricted, hasDevices: true).availability else {
            return XCTFail("Restricted camera must be unsupported")
        }
        guard case .temporarilyUnavailable = CameraPreviewController.capabilityMapping(permission: .authorized, hasDevices: false).availability else {
            return XCTFail("No devices must be unavailable")
        }
    }

    func testConstructionAndRefreshNeverPrompt() async {
        let fixture = makeFixture()
        await fixture.controller.refresh()
        XCTAssertEqual(fixture.devices.requestCount, 0)
        XCTAssertTrue(fixture.session.startedDeviceIDs.isEmpty)
    }

    func testDeniedPermissionFailsClosed() async {
        let fixture = makeFixture()
        fixture.devices.grant = .denied

        await assertThrows(.permissionRequired) { try await fixture.controller.open() }

        XCTAssertEqual(fixture.devices.requestCount, 1)
        XCTAssertTrue(fixture.session.startedDeviceIDs.isEmpty)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertEqual(fixture.registry.snapshot(for: .camera)?.permission, .denied)
    }

    func testNoDevicesFails() async {
        let fixture = makeFixture(authorized: true)
        fixture.devices.devices = []

        await assertThrows(.noDevices) { try await fixture.controller.open() }
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testDefaultFallbackPrefersBuiltInCamera() async throws {
        let fixture = makeFixture(authorized: true)

        try await fixture.controller.open()

        XCTAssertEqual(fixture.session.startedDeviceIDs, ["builtin"])
        XCTAssertEqual(fixture.controller.selectedDeviceID, "builtin")
    }

    func testSelectedDeviceIsUsedAndStaleSelectionFallsBack() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.controller.selectedDeviceID = "ext"
        try await fixture.controller.open()
        XCTAssertEqual(fixture.session.startedDeviceIDs, ["ext"])

        await fixture.controller.close()
        fixture.controller.selectedDeviceID = "gone"
        try await fixture.controller.open()
        XCTAssertEqual(fixture.session.startedDeviceIDs.last, "builtin")
    }

    func testResolverIsDeterministic() {
        let devices = [
            CameraDeviceDescriptor(id: "b", name: "Zeta", isBuiltIn: false),
            CameraDeviceDescriptor(id: "a", name: "Alpha", isBuiltIn: false)
        ]
        XCTAssertEqual(CameraPreviewController.resolveDevice(preferredID: nil, in: devices)?.id, "a")
        XCTAssertEqual(CameraPreviewController.resolveDevice(preferredID: "b", in: devices)?.id, "b")
        XCTAssertNil(CameraPreviewController.resolveDevice(preferredID: nil, in: []))
    }

    func testActivityPublishedOnlyAfterSessionRuns() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.session.startError = CameraPreviewError.sessionFailed("busy")

        await assertThrows(.sessionFailed("busy")) { try await fixture.controller.open() }
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        guard case .failed = fixture.registry.snapshot(for: .camera)?.health else {
            return XCTFail("Expected failed health")
        }

        fixture.session.startError = nil
        try await fixture.controller.open()
        let activity = fixture.activities.activities.first
        XCTAssertEqual(activity?.kind, .camera)
        XCTAssertEqual(activity?.lifecycle.authority, .avFoundation)
        XCTAssertNil(activity?.progress)
        XCTAssertTrue(fixture.registry.snapshot(for: .camera)?.isActive ?? false)
    }

    func testCloseStopsSessionBeforeRemovingActivityAndIsIdempotent() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()

        await fixture.controller.close()
        await fixture.controller.close()

        XCTAssertFalse(fixture.session.isRunning)
        XCTAssertEqual(fixture.session.activitiesAtStop.first, [.camera])
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertFalse(fixture.registry.snapshot(for: .camera)?.isActive ?? true)
    }

    func testDisableWhileActiveTearsDown() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()

        await fixture.controller.setEnabled(false)

        XCTAssertFalse(fixture.session.isRunning)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        await assertThrows(.disabled) { try await fixture.controller.open() }
    }

    func testTerminationTearsDownSynchronously() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()

        fixture.controller.terminate()

        XCTAssertEqual(fixture.session.immediateStopCount, 1)
        XCTAssertFalse(fixture.session.isRunning)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testUnexpectedStopFailsAndRemovesActivity() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()

        fixture.session.onUnexpectedStop?("The camera was disconnected.")
        for _ in 0..<50 where !fixture.activities.activities.isEmpty {
            await Task.yield()
        }

        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertEqual(fixture.controller.phase, .failed("The camera was disconnected."))
    }

    func testSwitchingDeviceWhileRunningRestarts() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()

        try await fixture.controller.selectDevice(id: "ext")

        XCTAssertEqual(fixture.session.startedDeviceIDs, ["builtin", "ext"])
        XCTAssertEqual(fixture.controller.phase, .running(deviceID: "ext"))
        XCTAssertEqual(fixture.activities.activities.count, 1)
    }

    // MARK: Fixture

    private struct Fixture {
        let controller: CameraPreviewController
        let devices: FakeCameraDevices
        let session: FakeCaptureSession
        let activities: LiveActivityStore
        let registry: IslandCapabilityRegistry
    }

    private func makeFixture(authorized: Bool = false) -> Fixture {
        let devices = FakeCameraDevices()
        if authorized { devices.permissionState = .authorized }
        let session = FakeCaptureSession()
        let activities = LiveActivityStore()
        session.activities = activities
        let registry = IslandCapabilityRegistry()
        let controller = CameraPreviewController(
            liveActivities: activities,
            capabilities: registry,
            deviceProvider: devices,
            session: session,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        return Fixture(controller: controller, devices: devices, session: session, activities: activities, registry: registry)
    }

    private func assertThrows(
        _ expected: CameraPreviewError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CameraPreviewError, expected, file: file, line: line)
        }
    }
}
