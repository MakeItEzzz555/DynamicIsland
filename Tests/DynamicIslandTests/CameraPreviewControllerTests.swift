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

    /// One-shot hook run inside stop(), to interleave a racing call.
    var onNextStop: (() async -> Void)?

    func stop() async {
        stopCount += 1
        activitiesAtStop.append(activities?.activities.map(\.kind) ?? [])
        isRunning = false
        if let hook = onNextStop {
            onNextStop = nil
            await hook()
        }
    }

    func stopImmediately() {
        immediateStopCount += 1
        isRunning = false
    }
}

/// Capture session whose start suspends until the test releases it, to model
/// the real AVCaptureSession startup window.
@MainActor
private final class GatedCaptureSession: CameraCaptureSessionControlling {
    var previewSession: AVCaptureSession? { nil }
    var onUnexpectedStop: ((String) -> Void)?
    private(set) var isRunning = false
    private var pendingStart: CheckedContinuation<Void, Never>?

    var hasPendingStart: Bool { pendingStart != nil }

    func releasePendingStart() {
        let continuation = pendingStart
        pendingStart = nil
        continuation?.resume()
    }

    func start(deviceID: String) async throws {
        await withCheckedContinuation { pendingStart = $0 }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func stopImmediately() {
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

    // MARK: Preview consumers

    func testAppearingNeverStartsCaptureEvenWhenAuthorized() async {
        let fixture = makeFixture(authorized: true)
        await fixture.controller.attachPreviewConsumer()
        XCTAssertTrue(fixture.session.startedDeviceIDs.isEmpty, "view lifecycle is not intent")
        XCTAssertFalse(fixture.controller.isRunning)
        await fixture.controller.attachPreviewConsumer()
        await fixture.controller.detachPreviewConsumer()
        await fixture.controller.detachPreviewConsumer()
        XCTAssertEqual(fixture.session.stopCount, 0)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testExplicitStartSharesTheSessionAndStopsWithLastConsumer() async throws {
        let fixture = makeFixture(authorized: true)
        let first = CameraMirrorConsumerLease(controller: fixture.controller)
        try await first.startExplicitly()
        XCTAssertEqual(fixture.session.startedDeviceIDs, ["builtin"])
        let second = CameraMirrorConsumerLease(controller: fixture.controller)
        await second.acquire()
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1, "second consumer shares the session")
        await first.release()
        XCTAssertTrue(fixture.controller.isRunning)
        await second.release()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.stopCount, 1)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertEqual(fixture.controller.userIntent, .undecided, "the request ends with the last mirror")
    }

    func testConsumerNeverPromptsForPermission() async {
        let fixture = makeFixture()
        await fixture.controller.attachPreviewConsumer()
        XCTAssertEqual(fixture.devices.requestCount, 0)
        XCTAssertTrue(fixture.session.startedDeviceIDs.isEmpty)
        await fixture.controller.detachPreviewConsumer()
        XCTAssertEqual(fixture.session.stopCount, 0)
    }

    func testConsumerLeavesExplicitlyOpenedPreviewRunning() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()
        await fixture.controller.attachPreviewConsumer()
        await fixture.controller.detachPreviewConsumer()
        XCTAssertTrue(fixture.controller.isRunning)
    }

    func testExplicitMirrorOpenCloseAndReopenReleasesOwnedCapture() async throws {
        let fixture = makeFixture()

        try await fixture.controller.startPreviewConsumer()
        XCTAssertEqual(fixture.devices.requestCount, 1)
        XCTAssertTrue(fixture.controller.isRunning)
        XCTAssertEqual(fixture.controller.activePreviewConsumers, 1)

        await fixture.controller.detachPreviewConsumer()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.controller.activePreviewConsumers, 0)
        XCTAssertEqual(fixture.session.stopCount, 1)

        try await fixture.controller.startPreviewConsumer()
        XCTAssertEqual(fixture.devices.requestCount, 1, "permission remains granted after closing the mirror")
        XCTAssertTrue(fixture.controller.isRunning)
        await fixture.controller.detachPreviewConsumer()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.stopCount, 2)
    }

    // MARK: Mirror lease lifecycle (Close Mirror / reopen / independent owner)

    func testCloseMirrorReleasesConsumerAndStopsOwnedCapture() async throws {
        let fixture = makeFixture(authorized: true)
        let lease = CameraMirrorConsumerLease(controller: fixture.controller)
        try await lease.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning)
        XCTAssertEqual(fixture.controller.activePreviewConsumers, 1)

        await lease.release()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.controller.activePreviewConsumers, 0)
        XCTAssertEqual(fixture.session.stopCount, 1)
        XCTAssertTrue(fixture.activities.activities.isEmpty)

        // Close Mirror followed by onDisappear releases only once.
        await lease.release()
        XCTAssertEqual(fixture.controller.activePreviewConsumers, 0)
        XCTAssertEqual(fixture.session.stopCount, 1)
    }

    func testReopenedMirrorStaysOffUntilStartAndNeverPrompts() async throws {
        let fixture = makeFixture(authorized: true)
        let first = CameraMirrorConsumerLease(controller: fixture.controller)
        try await first.startExplicitly()
        await first.release()
        XCTAssertFalse(fixture.controller.isRunning)

        let reopened = CameraMirrorConsumerLease(controller: fixture.controller)
        await reopened.acquire()
        XCTAssertFalse(fixture.controller.isRunning, "showing the mirror again is not a request")
        try await reopened.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning)
        XCTAssertEqual(fixture.devices.requestCount, 0, "restarting never prompts")
        XCTAssertEqual(fixture.session.startedDeviceIDs, ["builtin", "builtin"])
        await reopened.release()
        XCTAssertFalse(fixture.controller.isRunning)
    }

    func testConcurrentAcquiresCountOneConsumer() async {
        let fixture = makeFixture(authorized: true)
        let lease = CameraMirrorConsumerLease(controller: fixture.controller)
        async let a: Void = lease.acquire()
        async let b: Void = lease.acquire()
        _ = await (a, b)
        XCTAssertEqual(fixture.controller.activePreviewConsumers, 1)
        await lease.release()
        XCTAssertEqual(fixture.controller.activePreviewConsumers, 0)
        XCTAssertFalse(fixture.controller.isRunning)
    }

    /// Regression: leaving the mirror while its explicit start is still in
    /// flight must stop the late-starting capture and leak no consumer.
    func testReleaseRacingInFlightStartStopsCaptureAndLeaksNoConsumer() async {
        let devices = FakeCameraDevices()
        devices.permissionState = .authorized
        let session = GatedCaptureSession()
        let controller = CameraPreviewController(
            liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry(),
            deviceProvider: devices,
            session: session
        )
        let lease = CameraMirrorConsumerLease(controller: controller)
        let start = Task { try? await lease.startExplicitly() }
        while !session.hasPendingStart { await Task.yield() }
        XCTAssertEqual(controller.phase, .starting)

        let close = Task { await lease.release() }
        await Task.yield()
        session.releasePendingStart()
        await start.value
        await close.value

        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.activePreviewConsumers, 0)
        XCTAssertFalse(session.isRunning, "capture started late must be stopped")
    }

    func testMirrorCloseNeverStopsIndependentOwnerThatStartedFirst() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()
        let lease = CameraMirrorConsumerLease(controller: fixture.controller)
        await lease.acquire()
        try await lease.startExplicitly()
        await lease.release()
        XCTAssertTrue(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.stopCount, 0)
    }

    func testMirrorCloseNeverStopsIndependentOwnerThatJoinedLater() async throws {
        let fixture = makeFixture(authorized: true)
        let lease = CameraMirrorConsumerLease(controller: fixture.controller)
        try await lease.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning)
        try await fixture.controller.open()
        XCTAssertTrue(fixture.controller.hasExplicitOwner)

        await lease.release()
        XCTAssertTrue(fixture.controller.isRunning, "explicit owner keeps the shared session")
        XCTAssertEqual(fixture.session.stopCount, 0)

        await fixture.controller.close()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertFalse(fixture.controller.hasExplicitOwner)
    }

    func testSwitchingCameraKeepsMirrorOwnershipSoCloseStillStops() async throws {
        let fixture = makeFixture(authorized: true)
        let lease = CameraMirrorConsumerLease(controller: fixture.controller)
        try await lease.startExplicitly()
        try await fixture.controller.selectDevice(id: "ext")
        XCTAssertEqual(fixture.controller.phase, .running(deviceID: "ext"))
        XCTAssertFalse(fixture.controller.hasExplicitOwner)
        await lease.release()
        XCTAssertFalse(fixture.controller.isRunning)
    }

    func testMirrorRetryAfterUnexpectedStopOfExplicitSessionIsReleasedOnClose() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()
        let lease = CameraMirrorConsumerLease(controller: fixture.controller)
        await lease.acquire()
        fixture.session.onUnexpectedStop?("The camera was disconnected.")
        for _ in 0..<20 where fixture.controller.isRunning || fixture.controller.phase == .stopping {
            await Task.yield()
        }
        guard case .failed = fixture.controller.phase else {
            return XCTFail("expected failed phase, got \(fixture.controller.phase)")
        }
        XCTAssertFalse(fixture.controller.hasExplicitOwner)

        try await lease.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning)
        await lease.release()
        XCTAssertFalse(fixture.controller.isRunning, "mirror-owned retry is released on close")
    }

    // MARK: User intent (passive lifecycle never starts or restarts capture)

    /// A remount is modelled as a brand-new lease (new view identity).
    func testExplicitCloseThenSwiftUIRemountNeverRestarts() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning)

        await mirror.closeByUser()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertTrue(fixture.controller.isMirrorDismissed)

        let remounted = CameraMirrorConsumerLease(controller: fixture.controller)
        await remounted.acquire()
        XCTAssertFalse(fixture.controller.isRunning, "remount after close must not restart")
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1)
        await remounted.release()
        XCTAssertEqual(fixture.controller.activePreviewConsumers, 0)
    }

    func testOpenCloseThenRemountNeverRestarts() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()
        await fixture.controller.close()

        await fixture.controller.attachPreviewConsumer()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1)
    }

    func testLeavingTheMirrorPageStopsAndComingBackStaysOff() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        // Another right-workspace page: the mounted mirror releases.
        await mirror.release()
        XCTAssertFalse(fixture.controller.isRunning)
        // Back to the mirror page: passive re-acquire.
        await mirror.acquire()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1)
    }

    /// The user's rule: collapse stops the camera, re-expanding never restarts
    /// it - even when SwiftUI keeps the mirror mounted through the collapse.
    func testCollapseStopsCaptureAndReexpandStaysOff() async throws {
        let fixture = makeFixture(authorized: true)
        var mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning)
        for cycle in 1...5 {
            await fixture.controller.islandDidCollapse()
            XCTAssertFalse(fixture.controller.isRunning, "cycle \(cycle): collapse stops capture")
            XCTAssertFalse(fixture.session.isRunning)
            XCTAssertEqual(fixture.controller.userIntent, .undecided)
            // Expand: the same mirror re-acquires, or a remount mounts a new one.
            await mirror.release()
            mirror = CameraMirrorConsumerLease(controller: fixture.controller)
            await mirror.acquire()
            XCTAssertFalse(fixture.controller.isRunning, "cycle \(cycle): re-expand stays off")
            try await mirror.startExplicitly()
            XCTAssertTrue(fixture.controller.isRunning, "cycle \(cycle): explicit Start works again")
        }
        await fixture.controller.islandDidCollapse()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    /// Collapse while an explicit start is still in flight: the stale start
    /// must not leave the camera running.
    func testCollapseRacingInFlightStartLeavesCameraOff() async {
        let devices = FakeCameraDevices()
        devices.permissionState = .authorized
        let session = GatedCaptureSession()
        let controller = CameraPreviewController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry(),
                                                 deviceProvider: devices, session: session)
        let mirror = CameraMirrorConsumerLease(controller: controller)
        let start = Task { try? await mirror.startExplicitly() }
        while !session.hasPendingStart { await Task.yield() }
        let collapse = Task { await controller.islandDidCollapse() }
        await Task.yield()
        session.releasePendingStart()
        await start.value
        await collapse.value
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(session.isRunning, "a stale start completing after collapse is stopped")
        XCTAssertEqual(controller.phase, .idle)
    }

    func testCollapseLeavesAnExplicitSettingsOwnerAlone() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()
        await fixture.controller.islandDidCollapse()
        XCTAssertTrue(fixture.controller.isRunning, "the Settings preview is outside the island")
    }

    func testCloseThenTabSwitchAwayAndBackNeverRestarts() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        // Deactivated from Settings / Live Activity while the mirror stays mounted.
        await fixture.controller.close()
        await mirror.release()
        await mirror.acquire()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1)
    }

    func testCloseThenCollapseExpandNeverRestarts() async throws {
        let fixture = makeFixture(authorized: true)
        var mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        await mirror.closeByUser()
        for _ in 0..<5 {
            await fixture.controller.islandDidCollapse()
            await mirror.release()
            mirror = CameraMirrorConsumerLease(controller: fixture.controller)
            await mirror.acquire()
            XCTAssertFalse(fixture.controller.isRunning)
        }
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1)
    }

    func testSettingsDisableAndReenableNeverRestarts() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        await fixture.controller.setEnabled(false)
        await fixture.controller.setEnabled(true)
        await mirror.release()
        await mirror.acquire()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1)
    }

    func testNewExplicitActionReopensAfterClose() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        await mirror.closeByUser()

        fixture.controller.requestMirror()
        XCTAssertFalse(fixture.controller.isMirrorDismissed)
        let reopened = CameraMirrorConsumerLease(controller: fixture.controller)
        try await reopened.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning, "Start is a new explicit request")

        await reopened.closeByUser()
        try await reopened.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning, "Start/Retry is a new explicit request")
        await reopened.closeByUser()
        XCTAssertFalse(fixture.controller.isRunning)
    }

    func testRepeatedOpenCloseCyclesNeverSelfReactivate() async throws {
        let fixture = makeFixture(authorized: true)
        for cycle in 1...50 {
            let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
            try await mirror.startExplicitly()
            XCTAssertTrue(fixture.controller.isRunning, "cycle \(cycle)")
            await mirror.closeByUser()
            // Every passive event after close.
            await mirror.acquire()
            await mirror.release()
            let remount = CameraMirrorConsumerLease(controller: fixture.controller)
            await remount.acquire()
            await fixture.controller.islandDidCollapse()
            await remount.release()
            XCTAssertFalse(fixture.controller.isRunning, "cycle \(cycle)")
            XCTAssertEqual(fixture.controller.activePreviewConsumers, 0)
        }
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 50)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testCloseRacingInFlightExplicitStartLeavesCameraOffAndClosed() async {
        let devices = FakeCameraDevices()
        devices.permissionState = .authorized
        let session = GatedCaptureSession()
        let controller = CameraPreviewController(
            liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry(),
            deviceProvider: devices,
            session: session
        )
        let mirror = CameraMirrorConsumerLease(controller: controller)
        let start = Task { try? await mirror.startExplicitly() }
        while !session.hasPendingStart { await Task.yield() }

        let close = Task { await mirror.closeByUser() }
        await Task.yield()
        session.releasePendingStart()
        await start.value
        await close.value

        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.isMirrorDismissed)

        await mirror.acquire()
        XCTAssertFalse(session.hasPendingStart, "passive acquire after close must not start")
        XCTAssertFalse(controller.isRunning)
    }

    func testPreviewConsumerPlusExplicitOwnerCloseStopsBothAndStaysClosed() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        try await fixture.controller.open()

        await fixture.controller.close()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertFalse(fixture.controller.hasExplicitOwner)

        await mirror.release()
        await mirror.acquire()
        XCTAssertFalse(fixture.controller.isRunning)
    }

    func testPassiveSurfaceMayJoinRunningSessionAfterMirrorClose() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        await mirror.closeByUser()
        // An independent explicit owner (Settings preview) starts capture.
        try await fixture.controller.open()
        let remount = CameraMirrorConsumerLease(controller: fixture.controller)
        await remount.acquire()
        XCTAssertTrue(fixture.controller.isRunning, "showing an already running explicit session is allowed")
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 2)
        await remount.release()
        XCTAssertTrue(fixture.controller.isRunning, "explicit owner keeps capture")
    }

    func testSettingsPreviewDisappearReleasesOnlyItsOwnership() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()
        await fixture.controller.releaseExplicitPreview()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertFalse(fixture.controller.isMirrorDismissed, "leaving Settings is not a user close")

        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        await mirror.acquire()
        try await fixture.controller.open()
        await fixture.controller.releaseExplicitPreview()
        XCTAssertTrue(fixture.controller.isRunning, "a visible mirror inherits the session")
        await mirror.release()
        XCTAssertFalse(fixture.controller.isRunning, "and releases it when it goes away")
    }

    func testUnexpectedStopIsNotRestartedByPassiveLifecycle() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        fixture.session.onUnexpectedStop?("The camera was interrupted by the system.")
        for _ in 0..<50 where fixture.controller.isRunning || fixture.controller.phase == .stopping {
            await Task.yield()
        }
        await mirror.release()
        await mirror.acquire()
        let remount = CameraMirrorConsumerLease(controller: fixture.controller)
        await remount.acquire()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1)

        try await remount.startExplicitly()
        XCTAssertTrue(fixture.controller.isRunning, "explicit Retry restarts")
    }

    func testCloseDuringDeviceSwitchDoesNotRestartCapture() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.open()
        let controller = fixture.controller
        fixture.session.onNextStop = { await controller.close() }

        try await fixture.controller.selectDevice(id: "ext")

        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertFalse(fixture.session.isRunning)
        XCTAssertEqual(fixture.session.startedDeviceIDs, ["builtin"])
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testTerminationIsAnExplicitCloseForPassiveLifecycle() async throws {
        let fixture = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: fixture.controller)
        try await mirror.startExplicitly()
        fixture.controller.terminate()
        await mirror.release()
        await mirror.acquire()
        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.session.startedDeviceIDs.count, 1)
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

/// Opt-in real camera acceptance (DYNAMIC_ISLAND_LIVE_CAMERA=1): the
/// production controller and AVFoundation session, attached as the mirror
/// consumer, must run capture, mirror the preview connection, and stop
/// when the last consumer detaches.
@MainActor
final class CameraMirrorLiveTests: XCTestCase {
    func testRealCameraMirrorStartsMirrorsAndStops() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_CAMERA"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_CAMERA=1 to use the real camera.")
        }
        let controller = CameraPreviewController(
            liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry()
        )
        guard controller.permissionState == .authorized else {
            throw XCTSkip("Camera access is \(controller.permissionState) for this process")
        }
        try await controller.startPreviewConsumer()
        XCTAssertTrue(controller.isRunning, controller.statusText)
        let session = try XCTUnwrap(controller.previewSession)
        for _ in 0..<30 where !session.isRunning { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(session.isRunning)

        let view = CameraPreviewLayerView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        view.isMirrored = true
        view.session = session
        view.layout()
        let layer = try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.first)
        let connection = try XCTUnwrap(layer.connection)
        print("LIVE camera: device=\(controller.activeDeviceName ?? "-") mirroringSupported=\(connection.isVideoMirroringSupported) mirrored=\(connection.isVideoMirrored)")
        if connection.isVideoMirroringSupported {
            XCTAssertTrue(connection.isVideoMirrored)
        }
        view.session = nil

        await controller.detachPreviewConsumer()
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(session.isRunning)
    }

    /// Explicit Close Mirror, then every passive lifecycle event (tab away/back,
    /// collapse/expand remount) over a few seconds: real capture stays off.
    func testRealCameraNeverReactivatesAfterExplicitClose() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_CAMERA"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_CAMERA=1 to use the real camera.")
        }
        let controller = CameraPreviewController(
            liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry()
        )
        guard controller.permissionState == .authorized else {
            throw XCTSkip("Camera access is \(controller.permissionState) for this process")
        }
        var mirror = CameraMirrorConsumerLease(controller: controller)
        try await mirror.startExplicitly()
        let session = try XCTUnwrap(controller.previewSession)
        XCTAssertTrue(session.isRunning)
        await mirror.closeByUser()
        XCTAssertFalse(session.isRunning)

        for _ in 0..<10 {
            await mirror.release()
            mirror = CameraMirrorConsumerLease(controller: controller)
            await mirror.acquire()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(controller.isRunning)
            XCTAssertNil(controller.previewSession)
        }
        await mirror.release()
        print("LIVE camera close+remount: running=\(controller.isRunning) intent=\(controller.userIntent)")
    }

    /// Close Mirror stops real capture, reopening restarts it without a
    /// prompt, and closing the mirror never terminates an independent
    /// explicit camera owner.
    func testRealCameraMirrorCloseReopenAndIndependentOwner() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_CAMERA"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_CAMERA=1 to use the real camera.")
        }
        let controller = CameraPreviewController(
            liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry()
        )
        guard controller.permissionState == .authorized else {
            throw XCTSkip("Camera access is \(controller.permissionState) for this process")
        }

        // Open mirror -> Close Mirror.
        let first = CameraMirrorConsumerLease(controller: controller)
        try await first.startExplicitly()
        XCTAssertTrue(controller.isRunning, controller.statusText)
        let firstSession = try XCTUnwrap(controller.previewSession)
        XCTAssertTrue(firstSession.isRunning)
        await first.release()
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(firstSession.isRunning, "Close Mirror stops mirror-owned capture")
        XCTAssertEqual(controller.activePreviewConsumers, 0)

        // Reopen -> capture restarts, still authorized (no prompt path).
        let reopened = CameraMirrorConsumerLease(controller: controller)
        await reopened.acquire()
        XCTAssertFalse(controller.isRunning, "showing the mirror again is not a request")
        try await reopened.startExplicitly()
        XCTAssertEqual(controller.permissionState, .authorized)
        XCTAssertTrue(controller.isRunning, controller.statusText)
        let reopenedSession = try XCTUnwrap(controller.previewSession)
        XCTAssertTrue(reopenedSession.isRunning)

        // An independent explicit owner joins; closing the mirror keeps it.
        try await controller.open()
        await reopened.release()
        XCTAssertTrue(controller.isRunning, "independent owner is not terminated")
        XCTAssertTrue(reopenedSession.isRunning)
        print("LIVE camera close/reopen: device=\(controller.activeDeviceName ?? "-") explicitOwnerKeptCapture=\(reopenedSession.isRunning)")

        await controller.close()
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(reopenedSession.isRunning)
    }
}
