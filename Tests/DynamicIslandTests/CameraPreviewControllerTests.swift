import AVFoundation
import Foundation
import SwiftUI
import Combine
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
    var permissionGate: CheckedContinuation<Void, Never>?
    var delayPermission = false

    func requestAccess() async -> CameraPermissionState {
        requestCount += 1
        if delayPermission { await withCheckedContinuation { permissionGate = $0 } }
        permissionState = grant
        return permissionState
    }

    func availableDevices() -> [CameraDeviceDescriptor] { devices }
}

@MainActor
private final class FakeCaptureSession: CameraCaptureSessionControlling {
    var outputAttached = false
    var outputAttachCount = 0
    func setNavigationProcessor(_ processor: HandPoseFrameProcessor?) async throws {
        outputAttached = processor != nil
        if processor != nil { outputAttachCount += 1 }
    }
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
    var outputAttached = false
    func setNavigationProcessor(_ processor: HandPoseFrameProcessor?) async throws { outputAttached = processor != nil }
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
    private func navigation(_ camera: CameraPreviewController, settings: AppSettings? = nil,
                            timeout: Duration = .seconds(2), deliversInput: Bool = true, instances: @escaping () -> Int = { 1 },
                            now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> CameraNavigationController {
        CameraNavigationController(camera: camera, defaults: UserDefaults(suiteName: "camera-repair-\(UUID())")!,
                                   settings: settings, frameTimeout: timeout, deliversInput: deliversInput, instanceCount: instances, now: now)
    }
    private func settle(_ controller: CameraNavigationController) async {
        await controller.waitForReconciliation()
        for _ in 0..<20 { await Task.yield() }
        await controller.waitForReconciliation()
    }
    func testV4PointerCoastsThroughFlickerButUnreliableTrackingCancelsPress() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, deliversInput: false, now: { time })
        let layout = IslandLayoutStore(), window = NSWindow()
        layout.expandedSurfaceFrame = CGRect(x: 0, y: 0, width: 640, height: 360)
        controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { true }, expand: {}, page: { _ in })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        func inject(_ pose: HandNavigationPose?, pinch: Double = 1) {
            let h = pose.map { HandNavigationObservation(fingertip: CGPoint(x: 0.5, y: 0.5), palm: CGPoint(x: 0.5, y: 0.4),
                handScale: 0.2, pinchRatio: pinch, pose: $0, confidence: 0.9, timestamp: time) }
            controller.consume(.init(observation: h, generation: controller.trackingGeneration, latency: 0.01))
            time += 0.05
        }
        var visible = 0
        for pose in [HandNavigationPose.pointer, .other, .pointer, .twoFinger, .pointer, .pointer] {
            inject(pose); if layout.cameraPointerStore.presentation != nil { visible += 1 }
        }
        XCTAssertEqual(visible, 6)
        inject(.pointer, pinch: 0.1); inject(.pointer, pinch: 0.1); inject(.pointer, pinch: 0.1)
        XCTAssertEqual(layout.cameraPointerStore.presentation?.phase, .pressed)
        controller.consume(.init(observation: .init(fingertip: .zero, palm: .zero, handScale: 0.2,
            pinchRatio: 0.1, pose: .pointer, confidence: 0.9, timestamp: time - 0.2),
            generation: controller.trackingGeneration, latency: 0.2))
        XCTAssertEqual(layout.cameraPointerStore.presentation?.phase, .tracking, "Delayed Vision results invalidate press authority")
        inject(nil)
        XCTAssertNotNil(layout.cameraPointerStore.presentation)
        XCTAssertEqual(layout.cameraPointerStore.presentation?.phase, .tracking)
        for _ in 0..<3 { inject(.pointer, pinch: 0.1) }
        XCTAssertEqual(layout.cameraPointerStore.presentation?.phase, .tracking, "Loss invalidates press until release")
        inject(.pointer); inject(nil); time += 0.2; inject(nil)
        XCTAssertNil(layout.cameraPointerStore.presentation)
        inject(.pointer)
        XCTAssertNotNil(layout.cameraPointerStore.presentation)
        print("CAMERA_V4_VISIBILITY validFlicker=6/6 dropoutTolerance=180ms recovery=nextValidObservation")
        await controller.shutdown()
    }

    func testV4SemanticPalmPagingAcrossAgentsAndTrayWithNoPointerFrame() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let layout = IslandLayoutStore(), window = NSWindow(), navigation = IslandNavigationStore()
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.agentActivityEnabled = true; settings.showAgentsTab = true
        settings.trayEnabled = true; settings.showTrayTab = true
        let pages = navigation.availablePages(using: settings)
        XCTAssertTrue(pages.contains(.agents)); XCTAssertTrue(pages.contains(.tray))
        var deliveries: [ExpandedIslandPage] = []
        controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { false }, expand: {},
            page: { forward in
                if forward { navigation.selectNextPage(using: settings) } else { navigation.selectPreviousPage(using: settings) }
                deliveries.append(navigation.selectedPage)
            }, canNavigate: { !layout.isShellMorphing })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        for forward in [true, false] {
            navigation.select(forward ? .agents : .tray)
            for _ in 0..<3 {
                let before = navigation.selectedPage
                let index = pages.firstIndex(of: before)!
                let expected = pages[(index + (forward ? 1 : pages.count - 1)) % pages.count]
                let xs = forward ? [0.5, 0.35, 0.18, 0.05, 0.2, 0.35, 0.5, 0.5, 0.5, 0.5, 0.5]
                    : [0.5, 0.65, 0.82, 0.95, 0.8, 0.65, 0.5, 0.5, 0.5, 0.5, 0.5]
                for (i, x) in xs.enumerated() {
                    layout.isShellMorphing = (3...7).contains(i)
                    controller.consume(.init(observation: .init(fingertip: CGPoint(x: x, y: 0.5), palm: CGPoint(x: x, y: 0.5),
                        handScale: 0.2, pinchRatio: 1, pose: .openPalm, confidence: 0.9, timestamp: time),
                        generation: controller.trackingGeneration, latency: 0.01))
                    time += 0.05
                    XCTAssertNil(layout.cameraPointerStore.presentation)
                }
                XCTAssertEqual(navigation.selectedPage, expected)
            }
        }
        XCTAssertEqual(deliveries.count, 6)
        print("CAMERA_V4_PAGING Agents/Tray bothDirections=6/6 strokes reverseDuringReturn=0 precisionFrame=empty")
        await controller.shutdown()
    }

    func testV4FocusedComposerAndExactOwnerBlockSemanticPaging() async {
        for protected in 0...2 {
            var time = 100.0
            let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
            let layout = IslandLayoutStore(), window = NSWindow()
            if protected == 0 { layout.setTextInputFocused(true) }
            if protected == 1 { layout.collapsedMessageInteractionProtected = true }
            if protected == 2 { layout.setTransientInteraction(true, owner: .workspaceEditor) }
            controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { false },
                expand: { XCTFail("Camera expansion forbidden") }, page: { _ in XCTFail("Protected owner cannot be bypassed") }, canNavigate: { true })
            controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
            for x in [0.8, 0.65, 0.48, 0.3] {
                controller.consume(.init(observation: .init(fingertip: CGPoint(x: x, y: 0.5), palm: CGPoint(x: x, y: 0.5),
                    handScale: 0.2, pinchRatio: 1, pose: .openPalm, confidence: 0.9, timestamp: time),
                    generation: controller.trackingGeneration, latency: 0.01))
                time += 0.05
            }
            XCTAssertEqual(controller.lastGestureAction, "None")
            await controller.shutdown()
        }
    }

    func testV4CollapsedCalibrationStillConfirmsWithoutExpansion() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let layout = IslandLayoutStore(), window = NSWindow()
        controller.connect(window: window, layout: layout, isExpanded: { false }, canInteract: { false },
            expand: { XCTFail("Calibration cannot expand") }, page: { _ in XCTFail("Calibration cannot page") })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        controller.beginCalibration()
        for point in [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5), CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.5, y: 0.2)] {
            for ratio in [1.0, 0.1, 0.1, 0.1] {
                controller.consume(.init(observation: .init(fingertip: point, palm: CGPoint(x: 0.5, y: 0.5), handScale: 0.2,
                    pinchRatio: ratio, pose: .pointer, confidence: 0.9, timestamp: time), generation: controller.trackingGeneration, latency: 0.01))
                time += 0.05
            }
        }
        XCTAssertNil(controller.calibrationStep)
        XCTAssertEqual(controller.preferences.calibration, .init(left: 0.2, right: 0.8, bottom: 0.2, top: 0.8))
        XCTAssertNil(layout.cameraPointerStore.presentation)
        await controller.shutdown()
    }

    func testV4PinchFormationClicksNativeButtonAtAnchorOnceAndLossCannotClick() async throws {
        var time = 100.0, clicks = 0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let size = CGSize(width: 640, height: 360)
        let window = CameraNativeHostedFixture.hosted(Button("Anchored native click") { clicks += 1 }, size: size)
        defer { controller.terminate(); window.close() }
        let layout = IslandLayoutStore(); layout.canvasSize = size
        layout.expandedSurfaceFrame = CGRect(origin: .zero, size: size)
        controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { true }, expand: {}, page: { _ in })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        let gateWindow = try XCTUnwrap(window as? CameraHostedWindow), gate = gateWindow.cameraEventGate
        var downs = 0
        gateWindow.cameraEventGate = { event in
            let accepted = gate?(event) != false
            if accepted, CameraInteractionRouter.isCameraEvent(event), !CameraInteractionRouter.isCancellationEvent(event) {
                if event.type == .leftMouseDown { downs += 1 }
            }
            return accepted
        }
        func inject(_ ratio: Double?, y: Double = 0.5) {
            let h = ratio.map { HandNavigationObservation(fingertip: CGPoint(x: 0.5, y: y), palm: CGPoint(x: 0.5, y: 0.4),
                handScale: 0.2, pinchRatio: $0, pose: .pointer, confidence: 0.9, timestamp: time) }
            controller.consume(.init(observation: h, generation: controller.trackingGeneration, latency: 0.01)); time += 0.05
        }
        let pointerBefore = NSEvent.mouseLocation
        for (ratio, y) in [(1.0,0.5),(0.62,0.5),(0.45,0.498),(0.24,0.48),(0.18,0.46),(0.12,0.44),(0.1,0.43),(1.0,0.5)] { inject(ratio, y: y) }
        CameraNativeHostedFixture.pump()
        XCTAssertEqual(clicks, 1); XCTAssertEqual(downs, 1)
        let posted = controller.postedPointerEventCounts
        XCTAssertEqual(posted[.leftMouseDown], 1); XCTAssertEqual(posted[.leftMouseUp], 1)
        XCTAssertNil(posted[.leftMouseDragged], "Fingertip closure must not queue a ghost drag")
        for ratio in [1.0,0.1,0.1,0.1] { inject(ratio) }
        inject(nil); inject(0.1)
        CameraNativeHostedFixture.pump()
        XCTAssertEqual(clicks, 1, "Cancellation invalidates the queued down before native tracking starts")
        for ratio in [1.0,0.1,0.1,0.1] { inject(ratio) }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        inject(1)
        XCTAssertEqual(controller.runtimeState, .suspendedPhysicalInput)
        CameraNativeHostedFixture.pump()
        XCTAssertEqual(clicks, 1, "Deactivation cancels queued input")
        time += 0.75; inject(1)
        XCTAssertNotNil(layout.cameraPointerStore.presentation, "Valid pointing recovers after physical grace")
        XCTAssertEqual(NSEvent.mouseLocation, pointerBefore)
        print("CAMERA_V4_NATIVE_CLICK clicks=\(clicks) postedDown=\(posted[.leftMouseDown] ?? 0) postedUp=\(posted[.leftMouseUp] ?? 0) cancelledClick=0 globalCursorMoved=false")
        await controller.shutdown()
    }

    func testV4AnchoredPinchDragUsesExistingNativeSliderAndCommitsOnce() async {
        var time = 100.0, value = 0.5, edits: [Bool] = []
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let size = CGSize(width: 640, height: 360)
        let window = CameraNativeHostedFixture.hosted(Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...1)
            .frame(width: 500).background(CameraSliderEditingBridge(onEditingChanged: { edits.append($0) }, onCancel: {})), size: size)
        defer { controller.terminate(); window.close() }
        let layout = IslandLayoutStore(); layout.canvasSize = size
        layout.expandedSurfaceFrame = CGRect(origin: .zero, size: size)
        controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { true }, expand: {}, page: { _ in })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        func inject(_ ratio: Double, tip: CGPoint, palm: CGPoint) {
            controller.consume(.init(observation: .init(fingertip: tip, palm: palm, handScale: 0.2, pinchRatio: ratio,
                pose: .pointer, confidence: 0.9, timestamp: time), generation: controller.trackingGeneration, latency: 0.01)); time += 0.05
        }
        for ratio in [1.0,0.62,0.45,0.24,0.18,0.12] { inject(ratio, tip: .init(x: 0.5, y: 0.5), palm: .init(x: 0.5, y: 0.4)) }
        XCTAssertEqual(edits, [true])
        XCTAssertEqual(value, 0.5, accuracy: 0.02)
        for i in 1...5 { inject(0.1, tip: .init(x: 0.5 + Double(i) * 0.03, y: 0.5), palm: .init(x: 0.5 + Double(i) * 0.03, y: 0.4)) }
        inject(1, tip: .init(x: 0.65, y: 0.5), palm: .init(x: 0.65, y: 0.4))
        CameraNativeHostedFixture.pump()
        XCTAssertGreaterThan(value, 0.7)
        XCTAssertEqual(edits, [true, false], "Existing editing bridge owns exactly one commit")
        print("CAMERA_V4_NATIVE_DRAG value=\(value) editingStarts=1 editingEnds=1")
        await controller.shutdown()
    }

    func testV4SteadyPointerPublicationsAndConsumeCostAreBounded() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, deliversInput: false, now: { time })
        let layout = IslandLayoutStore(), window = NSWindow()
        layout.expandedSurfaceFrame = CGRect(x: 0, y: 0, width: 640, height: 360)
        controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { true }, expand: {}, page: { _ in })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        var pointerChanges = 0, diagnosticsChanges = 0, costs: [Double] = []
        let pointerObserver = layout.cameraPointerStore.$presentation.dropFirst().sink { _ in pointerChanges += 1 }
        let diagnosticObserver = controller.objectWillChange.sink { diagnosticsChanges += 1 }
        for _ in 0..<120 {
            let started = ProcessInfo.processInfo.systemUptime
            controller.consume(.init(observation: .init(fingertip: CGPoint(x: 0.5, y: 0.5), palm: CGPoint(x: 0.5, y: 0.4), handScale: 0.2,
                pinchRatio: 1, pose: .pointer, confidence: 0.9, timestamp: time), generation: controller.trackingGeneration, latency: 0.01))
            costs.append((ProcessInfo.processInfo.systemUptime - started) * 1000); time += 0.05
        }
        XCTAssertEqual(pointerChanges, 1)
        XCTAssertLessThan(diagnosticsChanges, 60)
        let sorted = costs.sorted()
        print(String(format: "CAMERA_V4_UPDATE observations=120 pointerPublications=%d diagnosticPublications=%d mean=%.4fms p95=%.4fms scope=model-not-display", pointerChanges, diagnosticsChanges, costs.reduce(0,+)/120, sorted[114]))
        let beforeNoHand = diagnosticsChanges
        for _ in 0..<120 {
            controller.consume(.init(observation: nil, generation: controller.trackingGeneration, latency: 0.01)); time += 0.05
        }
        XCTAssertLessThan(diagnosticsChanges - beforeNoHand, 60, "No-hand frames must not republish identical diagnostics")
        print("CAMERA_V4_NO_HAND observations=120 diagnosticPublications=\(diagnosticsChanges - beforeNoHand)")
        controller.physicalTouchSession(active: true)
        XCTAssertNil(layout.cameraPointerStore.presentation)
        pointerObserver.cancel(); diagnosticObserver.cancel()
        await controller.shutdown()
    }

    func testAuthorizedCameraSelectionStartsOneOwnerAndOutput() async {
        let f = makeFixture(authorized: true)
        let controller = navigation(f.controller)
        controller.reconcile(gesturesEnabled: true, inputSource: .camera)
        await settle(controller)
        for _ in 0..<20 { controller.reconcile(gesturesEnabled: true, inputSource: .camera) }
        await settle(controller)
        XCTAssertTrue(controller.desiredCameraNavigation)
        XCTAssertTrue(f.controller.isRunning)
        XCTAssertEqual(f.controller.activeNavigationOwners, 1)
        XCTAssertEqual(f.session.startedDeviceIDs.count, 1)
        XCTAssertEqual(f.session.outputAttachCount, 1)
        XCTAssertEqual(f.devices.requestCount, 0)
        await controller.shutdown()
    }
    func testCameraSelectionNeverPromptsUntilExplicitAllow() async {
        let f = makeFixture(), controller = navigation(f.controller)
        controller.reconcile(gesturesEnabled: true, inputSource: .camera)
        await settle(controller)
        XCTAssertEqual(controller.runtimeState, .permissionRequired)
        XCTAssertEqual(f.devices.requestCount, 0)
        XCTAssertEqual(f.controller.activeNavigationOwners, 0)
        XCTAssertFalse(f.session.outputAttached)
        await controller.allowCamera(); await settle(controller)
        XCTAssertEqual(f.devices.requestCount, 1)
        XCTAssertTrue(f.controller.isRunning)
        XCTAssertTrue(f.session.outputAttached)
        await controller.shutdown()
    }
    func testSourceSwitchAndDisableReleaseCapture() async {
        for source in [GestureInputSource.trackpad, .none, .camera] {
            let f = makeFixture(authorized: true)
            let nav = navigation(f.controller)
            nav.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(nav)
            nav.reconcile(gesturesEnabled: source != .camera, inputSource: source)
            XCTAssertFalse(nav.isEnabled, "Input authority ends synchronously")
            await settle(nav)
            XCTAssertFalse(f.controller.isRunning)
            XCTAssertFalse(f.session.outputAttached)
            XCTAssertEqual(f.controller.activeNavigationOwners, 0)
            XCTAssertEqual(nav.runtimeState, .off)
            await nav.shutdown()
        }
    }
    func testPersistedAuthorizedCameraSourceResumesAndObservedChangesStop() async {
        let defaults = UserDefaults(suiteName: "camera-launch-\(UUID())")!
        defaults.set(true, forKey: "gesturesEnabled"); defaults.set("camera", forKey: "gestureInputSource")
        let settings = AppSettings(defaults: defaults), f = makeFixture(authorized: true)
        let controller = navigation(f.controller, settings: settings)
        await settle(controller)
        XCTAssertTrue(controller.desiredCameraNavigation)
        XCTAssertTrue(f.controller.isRunning)
        settings.gestureInputSource = .trackpad; await settle(controller)
        XCTAssertFalse(f.controller.isRunning)
        settings.gestureInputSource = .camera; await settle(controller)
        XCTAssertTrue(f.controller.isRunning)
        settings.gesturesEnabled = false; await settle(controller)
        XCTAssertFalse(f.controller.isRunning)
        await controller.shutdown()
    }
    func testStalePermissionCompletionCannotAcquireNavigation() async {
        let f = makeFixture(), controller = navigation(f.controller)
        f.devices.delayPermission = true
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        let allow = Task { await controller.allowCamera() }
        while f.devices.permissionGate == nil { await Task.yield() }
        controller.reconcile(gesturesEnabled: true, inputSource: .trackpad)
        f.devices.permissionGate?.resume(); f.devices.permissionGate = nil
        await allow.value; await settle(controller)
        XCTAssertFalse(f.controller.isRunning)
        XCTAssertTrue(f.session.startedDeviceIDs.isEmpty)
        XCTAssertFalse(f.session.outputAttached)
        XCTAssertEqual(f.controller.activeNavigationOwners, 0)
        await controller.shutdown()
    }
    func testRapidSourceReenableSerializesOldStartupAndLease() async {
        let devices = FakeCameraDevices(); devices.permissionState = .authorized
        let session = GatedCaptureSession()
        let camera = CameraPreviewController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry(),
                                             deviceProvider: devices, session: session)
        let controller = navigation(camera)
        controller.reconcile(gesturesEnabled: true, inputSource: .camera)
        while !session.hasPendingStart { await Task.yield() }
        controller.reconcile(gesturesEnabled: true, inputSource: .none)
        controller.reconcile(gesturesEnabled: true, inputSource: .camera)
        session.releasePendingStart()
        while !session.hasPendingStart { await Task.yield() }
        session.releasePendingStart(); await settle(controller)
        XCTAssertEqual(camera.activeNavigationOwners, 1)
        XCTAssertTrue(camera.isRunning)
        await controller.shutdown()
        XCTAssertFalse(camera.isRunning)
    }
    func testDuplicateInstanceWarningDoesNotTakeDownCapture() async {
        let f = makeFixture(authorized: true)
        var instances = 2
        let controller = navigation(f.controller, instances: { instances })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        XCTAssertEqual(controller.duplicateInstanceWarning, "Another DynamicIsland instance is running")
        XCTAssertTrue(f.controller.isRunning)
        instances = 1; controller.refreshInstanceDiagnostic()
        XCTAssertNil(controller.duplicateInstanceWarning)
        await controller.shutdown()
    }
    func testNoFrameWatchdogReportsFailureWithoutRestarting() async throws {
        let f = makeFixture(authorized: true)
        let nav = navigation(f.controller, timeout: .milliseconds(15))
        nav.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(nav)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(nav.runtimeState, .noFrames)
        nav.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(nav)
        XCTAssertEqual(f.session.startedDeviceIDs.count, 1)
        XCTAssertEqual(f.session.outputAttachCount, 1)
        await nav.shutdown()
        XCTAssertEqual(nav.runtimeState, .off)
    }
    func testFirstSampleCancelsWatchdogBeforeVisionCompletes() async throws {
        let f = makeFixture(authorized: true), controller = navigation(f.controller, timeout: .milliseconds(15))
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        controller.submit(.init(observation: nil, generation: controller.trackingGeneration, latency: 0, isSampleReceipt: true))
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(controller.firstFrameReceived)
        XCTAssertEqual(controller.runtimeState, .preparing)
        XCTAssertEqual(controller.recognitionFPS, 0)
        await controller.shutdown()
    }
    func testMailboxToFilterToPointerStoreHidesCollapsedAndRecoversExpandedThenLoss() async {
        let f = makeFixture(authorized: true), controller = navigation(f.controller)
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        let window = NSWindow(), layout = IslandLayoutStore()
        layout.collapsedSurfaceFrame = CGRect(x: 20, y: 20, width: 200, height: 36)
        layout.updateCollapsedSidecars(.init(leadingSidecarFrame: nil, primaryFrame: layout.collapsedSurfaceFrame, trailingSidecarFrame: nil, interactionFrame: layout.collapsedSurfaceFrame))
        layout.expandedSurfaceFrame = CGRect(x: 20, y: 20, width: 500, height: 260)
        var expanded = false
        controller.connect(window: window, layout: layout, isExpanded: { expanded }, canInteract: { true }, expand: {}, page: { _ in })
        for value in [false, true] {
            expanded = value
            for _ in 0..<5 {
                let hand = HandNavigationObservation(fingertip: CGPoint(x: 0.5, y: 0.5), palm: CGPoint(x: 0.5, y: 0.5),
                    handScale: 0.2, pinchRatio: 1, pose: .pointer, confidence: 0.9, timestamp: ProcessInfo.processInfo.systemUptime)
                controller.submit(.init(observation: hand, generation: controller.trackingGeneration, latency: 0.02))
                for _ in 0..<20 { await Task.yield() }
                try? await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(layout.cameraPointerStore.presentation != nil, value)
            XCTAssertEqual(controller.pointerPresentationProduced, value)
            XCTAssertEqual(controller.runtimeState, .tracking)
        }
        controller.submit(.init(observation: nil, generation: controller.trackingGeneration, latency: 0.02))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNotNil(layout.cameraPointerStore.presentation, "Brief invalid observations retain only the visual pointer")
        try? await Task.sleep(for: .milliseconds(220))
        XCTAssertNil(layout.cameraPointerStore.presentation)
        XCTAssertEqual(controller.runtimeState, .noHand)
        await controller.shutdown(); controller.terminate()
    }
    func testDeviceChangeReattachesOutputAndRejectsOldFrameWatchdog() async throws {
        let f = makeFixture(authorized: true), controller = navigation(f.controller, timeout: .milliseconds(25))
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        let old = controller.trackingGeneration
        try await f.controller.selectDevice(id: "ext"); await settle(controller)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(f.controller.isRunning)
        XCTAssertEqual(f.controller.activeNavigationOwners, 1)
        XCTAssertEqual(f.session.outputAttachCount, 2)
        XCTAssertGreaterThan(controller.trackingGeneration, old)
        controller.submit(.init(observation: nil, generation: old, latency: 0, isSampleReceipt: true))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(controller.firstFrameReceived)
        controller.submit(.init(observation: nil, generation: controller.trackingGeneration, latency: 0, isSampleReceipt: true))
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(controller.runtimeState, .preparing)
        await controller.shutdown()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(controller.runtimeState, .off)
    }
    func testMirrorAndRuntimeNavigationReleaseIndependently() async throws {
        let f = makeFixture(authorized: true), controller = navigation(f.controller)
        let mirror = CameraMirrorConsumerLease(controller: f.controller)
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        await mirror.acquire(); try await mirror.startExplicitly()
        await mirror.closeByUser()
        XCTAssertTrue(f.controller.isRunning)
        XCTAssertTrue(f.session.outputAttached)
        await mirror.acquire(); try await mirror.startExplicitly()
        controller.reconcile(gesturesEnabled: true, inputSource: .trackpad); await settle(controller)
        XCTAssertTrue(f.controller.isRunning)
        XCTAssertFalse(f.session.outputAttached)
        XCTAssertEqual(f.controller.activeNavigationOwners, 0)
        await mirror.release()
        XCTAssertFalse(f.controller.isRunning)
        await controller.shutdown()
    }
    func testReadOnlyAcceptanceProducesPointerWithoutExecutingPinchActions() async {
        let f = makeFixture(authorized: true), controller = navigation(f.controller, deliversInput: false)
        let layout = IslandLayoutStore(), window = NSWindow()
        layout.expandedSurfaceFrame = CGRect(x: 20, y: 20, width: 500, height: 260)
        layout.collapsedSurfaceFrame = CGRect(x: 20, y: 20, width: 200, height: 36)
        layout.updateCollapsedSidecars(.init(leadingSidecarFrame: nil, primaryFrame: layout.collapsedSurfaceFrame,
            trailingSidecarFrame: nil, interactionFrame: layout.collapsedSurfaceFrame))
        var expanded = 0
        controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { true },
                           expand: { expanded += 1 }, page: { _ in XCTFail("Read-only probe cannot navigate") })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        let base = ProcessInfo.processInfo.systemUptime - 0.2
        for (offset, pinch) in [(0.0, 1.0), (0.02, 0.1), (0.09, 0.1), (0.12, 1.0)] {
            let hand = HandNavigationObservation(fingertip: CGPoint(x: 0.5, y: 0.5), palm: CGPoint(x: 0.5, y: 0.5),
                handScale: 0.2, pinchRatio: pinch, pose: .pointer, confidence: 0.9, timestamp: base + offset)
            controller.consume(.init(observation: hand, generation: controller.trackingGeneration, latency: 0.01))
        }
        XCTAssertTrue(controller.pointerPresentationProduced)
        XCTAssertNotNil(layout.cameraPointerStore.presentation)
        XCTAssertEqual(expanded, 0)
        await controller.shutdown()
    }
    func testCameraCollapsedPinchIsDisabledRegardlessOfFrameAndMouseExpansionPreference() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let settings = AppSettings(defaults: UserDefaults(suiteName: "camera-no-click-\(UUID())")!)
        settings.expandOnClick = false
        let layout = IslandLayoutStore(), window = NSWindow()
        layout.collapsedSurfaceFrame = CGRect(x: 20, y: 20, width: 20, height: 20)
        layout.updateCollapsedSidecars(.init(leadingSidecarFrame: nil, primaryFrame: layout.collapsedSurfaceFrame,
            trailingSidecarFrame: nil, interactionFrame: layout.collapsedSurfaceFrame))
        layout.updateCollapsedSidecars(.init(leadingSidecarFrame: nil, primaryFrame: .zero,
            trailingSidecarFrame: nil, interactionFrame: .zero))
        layout.collapsedPreviewActive = true
        var expansions = 0
        controller.connect(window: window, layout: layout, isExpanded: { false }, canInteract: { false },
            expand: {
                XCTAssertTrue(layout.isTransientInteractionActive, "Camera hold precedes expansion authority")
                expansions += 1
            }, page: { _ in XCTFail("Collapsed pinch cannot page") })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        for pinch in [1.0, 0.1, 0.1, 0.1, 0.1, 0.1] {
            controller.consume(.init(observation: .init(fingertip: CGPoint(x: -2, y: 2), palm: CGPoint(x: -2, y: 2),
                handScale: 0.2, pinchRatio: pinch, pose: .pointer, confidence: 0.9,
                timestamp: time), generation: controller.trackingGeneration, latency: 0.01))
            XCTAssertNil(layout.cameraPointerStore.presentation)
            time += 0.05
        }
        XCTAssertFalse(settings.expandOnClick)
        XCTAssertEqual(expansions, 0)
        XCTAssertEqual(controller.lastGestureAction, "None")
        await controller.shutdown()
    }

    func testCameraProtectedCompactControlDoesNotExpandOrClick() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let layout = IslandLayoutStore(), window = NSWindow()
        layout.collapsedSurfaceFrame = CGRect(x: 20, y: 20, width: 200, height: 36)
        layout.updateCollapsedSidecars(.init(leadingSidecarFrame: nil, primaryFrame: layout.collapsedSurfaceFrame,
            trailingSidecarFrame: nil, interactionFrame: layout.collapsedSurfaceFrame))
        controller.connect(window: window, layout: layout, isExpanded: { false }, canInteract: { true },
            expand: { XCTFail("Exact compact authority blocks expansion") }, page: { _ in }, canExpand: { false })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        for pinch in [1.0, 0.1, 0.1, 0.1] {
            controller.consume(.init(observation: .init(fingertip: .zero, palm: .zero, handScale: 0.2,
                pinchRatio: pinch, pose: .pointer, confidence: 0.9, timestamp: time),
                generation: controller.trackingGeneration, latency: 0.01))
            XCTAssertNil(layout.cameraPointerStore.presentation)
            time += 0.05
        }
        XCTAssertEqual(controller.lastGestureAction, "None")
        await controller.shutdown()
    }

    func testCameraPageMorphHidesPointerWithoutLosingHandAndRemapsOnRecovery() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let layout = IslandLayoutStore(), window = NSWindow()
        layout.expandedSurfaceFrame = CGRect(x: 20, y: 20, width: 500, height: 260)
        var available = true, pages = 0
        controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { available },
            expand: {}, page: { _ in pages += 1; available = false })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        func inject(_ pose: HandNavigationPose, x: Double) {
            controller.consume(.init(observation: .init(fingertip: CGPoint(x: x, y: 0.5), palm: CGPoint(x: x, y: 0.5),
                handScale: 0.2, pinchRatio: 1, pose: pose, confidence: 0.9,
                timestamp: time), generation: controller.trackingGeneration, latency: 0.01))
            time += 0.05
        }
        inject(.pointer, x: 0.7)
        XCTAssertNotNil(layout.cameraPointerStore.presentation)
        for i in 0...6 { inject(.openPalm, x: 0.7 - Double(i) * 0.03) }
        XCTAssertEqual(pages, 1)
        XCTAssertTrue(controller.isTracking)
        XCTAssertNil(layout.cameraPointerStore.presentation)
        for _ in 0..<8 { inject(.pointer, x: 0.52) }
        XCTAssertTrue(controller.isTracking, "A shell morph is not hand loss")
        XCTAssertNil(layout.cameraPointerStore.presentation)
        layout.expandedSurfaceFrame = CGRect(x: 10, y: 0, width: 640, height: 500)
        available = true
        inject(.pointer, x: 0.52)
        XCTAssertNotNil(layout.cameraPointerStore.presentation)
        XCTAssertTrue(layout.expandedSurfaceFrame.contains(layout.cameraPointerStore.presentation!.point))
        controller.preferences.showPointer = false
        inject(.pointer, x: 0.52)
        XCTAssertNil(layout.cameraPointerStore.presentation)
        controller.preferences.showPointer = true
        controller.physicalTouchSession(active: true)
        inject(.pointer, x: 0.52)
        XCTAssertNil(layout.cameraPointerStore.presentation)
        XCTAssertTrue(controller.isTracking)
        controller.physicalTouchSession(active: false)
        for _ in 0..<16 { inject(.pointer, x: 0.52) }
        XCTAssertNotNil(layout.cameraPointerStore.presentation, "Physical ownership ending automatically restores pointing")
        await controller.shutdown()
    }

    func testCameraDownSwipeRespectsTextAndTransientOwnership() async {
        for protection in 0...3 {
            var time = 100.0
            let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
            let layout = IslandLayoutStore(), window = NSWindow()
            layout.expandedSurfaceFrame = CGRect(x: 0, y: 0, width: 640, height: 400)
            if protection == 1 { layout.setTextInputFocused(true) }
            if protection == 2 { layout.setTransientInteraction(true, owner: .workspaceEditor) }
            var collapses = 0
            controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { true },
                expand: {}, page: { _ in XCTFail("Vertical palm cannot page") },
                canCollapse: { protection != 3 }, collapse: { collapses += 1 })
            controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
            for i in 0...7 {
                let point = CGPoint(x: 0.5, y: 0.7 - Double(i) * 0.03)
                controller.consume(.init(observation: .init(fingertip: point, palm: point, handScale: 0.2,
                    pinchRatio: 1, pose: .openPalm, confidence: 0.9, timestamp: time),
                    generation: controller.trackingGeneration, latency: 0.01))
                XCTAssertNil(layout.cameraPointerStore.presentation)
                time += 0.05
            }
            XCTAssertEqual(collapses, protection == 0 ? 1 : 0)
            await controller.shutdown()
        }
    }
    func testCameraExpansionProtectionAllowsPassivePreviewAndRejectsExactOwners() {
        let layout = IslandLayoutStore()
        layout.collapsedPreviewActive = true
        func allowed(approval: Bool = false, hud: Bool = false, native: Bool = false, drag: Bool = false) -> Bool {
            layout.cameraExpansionAllowed(exactApproval: approval, interactiveHUD: hud, nativeInteraction: native, fileDrag: drag)
        }
        XCTAssertTrue(allowed(), "Passive preview does not own input")
        let cameraOwner = TransientInteractionOwner.cameraNavigation(UUID())
        layout.setTransientInteraction(true, owner: cameraOwner)
        XCTAssertTrue(allowed(), "Camera's own hold must not block its expansion")
        XCTAssertFalse(allowed(approval: true))
        XCTAssertFalse(allowed(hud: true))
        XCTAssertFalse(allowed(native: true))
        XCTAssertFalse(allowed(drag: true))
        layout.setTextInputFocused(true); XCTAssertFalse(allowed())
        layout.setTextInputFocused(false)
        layout.collapsedMessageInteractionProtected = true; XCTAssertFalse(allowed())
        layout.collapsedMessageInteractionProtected = false
        layout.setTransientInteraction(true, owner: .workspaceEditor); XCTAssertFalse(allowed())
        layout.setTransientInteraction(false, owner: .workspaceEditor); XCTAssertTrue(allowed())
    }

    func testCameraCollapsedPinchCannotStealFocusedOrPinnedComposer() async {
        for pinned in [false, true] {
            var time = 100.0
            let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
            let layout = IslandLayoutStore(), window = NSWindow()
            if pinned { layout.collapsedMessageInteractionProtected = true }
            else { layout.setTextInputFocused(true) }
            controller.connect(window: window, layout: layout, isExpanded: { false }, canInteract: { false },
                expand: { XCTFail("Composer authority cannot be stolen") }, page: { _ in })
            controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
            for pinch in [1.0, 0.1, 0.1, 0.1] {
                controller.consume(.init(observation: .init(fingertip: .zero, palm: .zero, handScale: 0.2,
                    pinchRatio: pinch, pose: .pointer, confidence: 0.9, timestamp: time),
                    generation: controller.trackingGeneration, latency: 0.01))
                time += 0.05
            }
            XCTAssertNil(layout.cameraPointerStore.presentation)
            XCTAssertEqual(controller.lastGestureAction, "None")
            await controller.shutdown()
        }
    }

    func testCameraPinchDuringCollapseAndRecoveryNeverExpandsOrClaimsExpansionHold() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let layout = IslandLayoutStore(), window = NSWindow()
        var expanded = true
        layout.isExpandedContentExiting = true; layout.isShellMorphing = true
        controller.preferences.collapsedPinchAction = .expand
        controller.connect(window: window, layout: layout, isExpanded: { expanded }, canInteract: { false },
            expand: { XCTFail("Legacy expansion is inactive at dispatch") }, page: { _ in })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        for i in 0..<24 {
            if i == 4 { expanded = false; layout.isExpandedContentExiting = false; layout.isCollapseShellOnly = true }
            if i == 6 { layout.isCollapseShellOnly = false; layout.isShellMorphing = false }
            let hand = i % 8 == 5 ? nil : HandNavigationObservation(fingertip: .zero, palm: .zero, handScale: 0.2,
                pinchRatio: i % 8 == 0 ? 1 : 0.1, pose: .pointer, confidence: 0.9, timestamp: time)
            controller.consume(.init(observation: hand, generation: controller.trackingGeneration, latency: 0.01))
            time += 0.05
            XCTAssertNil(layout.cameraPointerStore.presentation)
            XCTAssertFalse(layout.isTransientInteractionActive)
        }
        XCTAssertEqual(controller.lastGestureAction, "None")
        await controller.shutdown()
        XCTAssertFalse(layout.isTransientInteractionActive)
    }

    func testProductionControllerRepeatedPalmPagesSurviveMorphWithoutPointer() async {
        var time = 100.0
        let f = makeFixture(authorized: true), controller = navigation(f.controller, now: { time })
        let layout = IslandLayoutStore(), window = NSWindow()
        var available = true, pages: [Bool] = []
        controller.connect(window: window, layout: layout, isExpanded: { true }, canInteract: { available },
            expand: {}, page: { pages.append($0); available = false; layout.isShellMorphing = true })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        for stroke in 0..<3 {
            for (i, x) in [0.8, 0.65, 0.48, 0.3, 0.4, 0.6, 0.8, 0.8, 0.8, 0.8, 0.8].enumerated() {
                if i == 10 { available = true; layout.isShellMorphing = false }
                controller.consume(.init(observation: .init(fingertip: CGPoint(x: x, y: 0.5), palm: CGPoint(x: x, y: 0.5),
                    handScale: 0.2, pinchRatio: 1, pose: .openPalm, confidence: 0.9, timestamp: time),
                    generation: controller.trackingGeneration, latency: 0.01))
                time += 0.05
                XCTAssertNil(layout.cameraPointerStore.presentation)
                XCTAssertTrue(controller.isTracking)
            }
            XCTAssertEqual(pages.count, stroke + 1)
        }
        XCTAssertEqual(pages, [true, true, true])
        XCTAssertEqual(controller.gestureMode, "navigation")
        await controller.shutdown()
    }

    func testDeniedPermissionCheckAgainDoesNotPrompt() async {
        let f = makeFixture(), controller = navigation(f.controller)
        f.devices.permissionState = .denied
        await f.controller.refresh()
        controller.reconcile(gesturesEnabled: true, inputSource: .camera); await settle(controller)
        await controller.checkAgain(); await settle(controller)
        XCTAssertEqual(controller.runtimeState, .permissionRequired)
        XCTAssertEqual(f.devices.requestCount, 0)
        f.devices.permissionState = .authorized
        await controller.checkAgain(); await settle(controller)
        XCTAssertTrue(f.controller.isRunning)
        await controller.shutdown()
    }
    func testCameraNavigationReportsPreparationUntilFirstVisionResult() async {
        let f = makeFixture(authorized: true)
        let controller = CameraNavigationController(camera: f.controller, defaults: UserDefaults(suiteName: "camera-prepare-\(UUID())")!)
        controller.reconcile(gesturesEnabled: true, inputSource: .camera)
        await controller.waitForReconciliation()
        XCTAssertEqual(controller.status, "Preparing hand tracking…")
        controller.consume(.init(observation: nil, generation: controller.trackingGeneration, latency: 0.02))
        XCTAssertEqual(controller.status, "Waiting for the island")
        await controller.shutdown(); controller.terminate()
    }
    func testFrameMailboxCoalescesWithoutRetainingFramesOrTasks() async {
        var received: [Int] = []
        let mailbox = HandPoseResultMailbox { received.append($0.generation) }
        for i in 0..<500 { mailbox.submit(.init(observation: nil, generation: i, latency: 0.001)) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(received, [499])
    }
    func testNavigationControllerRejectsStaleFramesAndHoldsOnlyExpandedInteraction() async {
        let f = makeFixture(authorized: true)
        let defaults = UserDefaults(suiteName: "camera-navigation-tests-\(UUID())")!
        let controller = CameraNavigationController(camera: f.controller, defaults: defaults)
        let layout = IslandLayoutStore()
        layout.expandedSurfaceFrame = CGRect(x: 0, y: 0, width: 640, height: 200)
        layout.collapsedSurfaceFrame = CGRect(x: 200, y: 160, width: 240, height: 36)
        layout.updateCollapsedSidecars(.init(leadingSidecarFrame: nil, primaryFrame: layout.collapsedSurfaceFrame,
            trailingSidecarFrame: nil, interactionFrame: layout.collapsedSurfaceFrame))
        var expanded = false
        let window = NSWindow()
        controller.connect(window: window, layout: layout, isExpanded: { expanded }, canInteract: { true }, expand: {}, page: { _ in })
        controller.reconcile(gesturesEnabled: true, inputSource: .camera)
        await controller.waitForReconciliation()
        let time = ProcessInfo.processInfo.systemUptime
        let hand = HandNavigationObservation(fingertip: CGPoint(x: 0.5, y: 0.5), palm: CGPoint(x: 0.5, y: 0.5),
            handScale: 0.2, pinchRatio: 1, pose: .pointer, confidence: 0.9, timestamp: time)
        controller.consume(.init(observation: hand, generation: controller.trackingGeneration - 1, latency: 0.01))
        XCTAssertFalse(controller.isTracking)
        controller.consume(.init(observation: hand, generation: controller.trackingGeneration, latency: 0.01))
        XCTAssertTrue(controller.isTracking)
        XCTAssertFalse(layout.isTransientInteractionActive)
        expanded = true
        controller.consume(.init(observation: hand, generation: controller.trackingGeneration, latency: 0.01))
        XCTAssertTrue(layout.isTransientInteractionActive)
        controller.consume(.init(observation: nil, generation: controller.trackingGeneration, latency: 0.01))
        XCTAssertFalse(controller.isTracking)
        XCTAssertTrue(layout.isTransientInteractionActive, "Tracking loss keeps only the bounded grace hold")
        await controller.shutdown()
        XCTAssertFalse(layout.isTransientInteractionActive)
        XCTAssertFalse(f.session.outputAttached)
        controller.consume(.init(observation: hand, generation: controller.trackingGeneration - 1, latency: 0.01))
        XCTAssertFalse(controller.isTracking)
        controller.terminate()
    }
    func testNavigationAndMirrorShareOneSession() async throws {
        let f = makeFixture(authorized: true)
        let navigation = CameraNavigationLease(controller: f.controller)
        let mirror = CameraMirrorConsumerLease(controller: f.controller)
        try await navigation.acquire()
        await mirror.acquire(); try await mirror.startExplicitly()
        XCTAssertEqual(f.session.startedDeviceIDs.count, 1)
        await mirror.closeByUser()
        XCTAssertTrue(f.controller.isRunning)
        await f.controller.islandDidCollapse()
        XCTAssertTrue(f.controller.isRunning)
        await navigation.release()
        XCTAssertFalse(f.controller.isRunning)
        XCTAssertEqual(f.controller.activeNavigationOwners, 0)
    }
    func testNavigationReleaseTransfersToVisibleMirror() async throws {
        let f = makeFixture(authorized: true)
        let navigation = CameraNavigationLease(controller: f.controller)
        let mirror = CameraMirrorConsumerLease(controller: f.controller)
        try await navigation.acquire(); await mirror.acquire(); try await mirror.startExplicitly()
        await navigation.release()
        XCTAssertTrue(f.controller.isRunning)
        await mirror.release()
        XCTAssertFalse(f.controller.isRunning)
    }
    func testMirrorFirstNavigationOutlivesMirrorCollapse() async throws {
        let f = makeFixture(authorized: true)
        let mirror = CameraMirrorConsumerLease(controller: f.controller)
        await mirror.acquire(); try await mirror.startExplicitly()
        let navigation = CameraNavigationLease(controller: f.controller)
        try await navigation.acquire()
        await f.controller.islandDidCollapse(); await mirror.release()
        XCTAssertTrue(f.controller.isRunning)
        XCTAssertEqual(f.session.startedDeviceIDs.count, 1)
        await navigation.release(); XCTAssertFalse(f.controller.isRunning)
    }
    func testNavigationExplicitPermissionAndDeniedCleanup() async throws {
        let f = makeFixture()
        f.devices.grant = .denied
        let navigation = CameraNavigationLease(controller: f.controller)
        XCTAssertEqual(f.devices.requestCount, 0)
        do { try await navigation.acquire(); XCTFail("Expected permission gate") } catch {}
        XCTAssertEqual(f.devices.requestCount, 1)
        XCTAssertEqual(f.controller.activeNavigationOwners, 0)
        XCTAssertFalse(navigation.isHeld)
    }
    func testMultipleNavigationOwnersReleaseIndependently() async throws {
        let f = makeFixture(authorized: true)
        let first = CameraNavigationLease(controller: f.controller), second = CameraNavigationLease(controller: f.controller)
        try await first.acquire(); try await second.acquire()
        await first.release(); await first.release()
        XCTAssertEqual(f.controller.activeNavigationOwners, 1)
        XCTAssertTrue(f.controller.isRunning)
        await second.release(); XCTAssertFalse(f.controller.isRunning)
    }
    func testNavigationDeviceSwitchRetainsOwnershipDespiteMirrorClose() async throws {
        let f = makeFixture(authorized: true)
        let navigation = CameraNavigationLease(controller: f.controller)
        try await navigation.acquire(); f.controller.recordUserClose()
        try await f.controller.selectDevice(id: "ext")
        XCTAssertTrue(f.controller.isRunning)
        XCTAssertEqual(f.controller.activeNavigationOwners, 1)
        XCTAssertEqual(f.session.startedDeviceIDs, ["builtin", "ext"])
        await navigation.release()
    }
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
