import AppKit
import Combine
import SwiftUI

struct CameraNavigationPreferences: Codable, Equatable {
    var showPointer = true
    var magneticControls = false
    var collapsedPinchAction: IslandGestureAction = .expand
    var swipeLeftAction: IslandGestureAction = .nextTab
    var swipeRightAction: IslandGestureAction = .previousTab
    var swipeDownAction: IslandGestureAction = .collapse
    var twoFingerScroll = false
    var sensitivity = 0.5
    var smoothing = 0.65
    var pinchSensitivity = 0.5
    var calibration = HandNavigationCalibration()

    init() {}
    private enum CodingKeys: String, CodingKey {
        case showPointer, magneticControls, collapsedPinchAction, swipeLeftAction, swipeRightAction, swipeDownAction
        case horizontalPageSwipe, twoFingerScroll, sensitivity, smoothing, pinchSensitivity, calibration
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPointer = try c.decodeIfPresent(Bool.self, forKey: .showPointer) ?? showPointer
        magneticControls = try c.decodeIfPresent(Bool.self, forKey: .magneticControls) ?? magneticControls
        let legacySwipe = try c.decodeIfPresent(Bool.self, forKey: .horizontalPageSwipe) ?? true
        collapsedPinchAction = try c.decodeIfPresent(IslandGestureAction.self, forKey: .collapsedPinchAction) ?? .expand
        swipeLeftAction = try c.decodeIfPresent(IslandGestureAction.self, forKey: .swipeLeftAction) ?? (legacySwipe ? .nextTab : .none)
        swipeRightAction = try c.decodeIfPresent(IslandGestureAction.self, forKey: .swipeRightAction) ?? (legacySwipe ? .previousTab : .none)
        swipeDownAction = try c.decodeIfPresent(IslandGestureAction.self, forKey: .swipeDownAction) ?? .collapse
        twoFingerScroll = try c.decodeIfPresent(Bool.self, forKey: .twoFingerScroll) ?? twoFingerScroll
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? sensitivity
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? smoothing
        pinchSensitivity = try c.decodeIfPresent(Double.self, forKey: .pinchSensitivity) ?? pinchSensitivity
        calibration = try c.decodeIfPresent(HandNavigationCalibration.self, forKey: .calibration) ?? calibration
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(showPointer, forKey: .showPointer); try c.encode(magneticControls, forKey: .magneticControls)
        try c.encode(collapsedPinchAction, forKey: .collapsedPinchAction)
        try c.encode(swipeLeftAction, forKey: .swipeLeftAction); try c.encode(swipeRightAction, forKey: .swipeRightAction)
        try c.encode(swipeDownAction, forKey: .swipeDownAction); try c.encode(twoFingerScroll, forKey: .twoFingerScroll)
        try c.encode(sensitivity, forKey: .sensitivity); try c.encode(smoothing, forKey: .smoothing)
        try c.encode(pinchSensitivity, forKey: .pinchSensitivity); try c.encode(calibration, forKey: .calibration)
    }
}

struct CameraPointerPresentation: Equatable {
    var point: CGPoint
    var phase: HandNavigationStateMachine.Phase
    var overControl: Bool
}

enum CameraNavigationRuntimeState: Equatable {
    case off, starting, preparing, tracking, noHand, suspendedPhysicalInput, waitingForIsland
    case permissionRequired, noFrames, unavailable(String)

    var message: String {
        switch self {
        case .off: "Camera navigation is off"
        case .starting: "Starting camera…"
        case .preparing: "Preparing hand tracking…"
        case .tracking: "Tracking"
        case .noHand: "Camera active · No hand"
        case .suspendedPhysicalInput: "Using mouse/trackpad/keyboard"
        case .waitingForIsland: "Waiting for the island"
        case .permissionRequired: "Camera access is required"
        case .noFrames: "No camera frames received"
        case .unavailable(let reason): "Camera unavailable · \(reason)"
        }
    }
}

@MainActor
final class CameraNavigationController: ObservableObject {
    // Runtime capture intent, derived only from reconciliation; never persisted.
    private var captureRequested = false
    var isEnabled: Bool { captureRequested }
    @Published private(set) var desiredCameraNavigation = false
    @Published private(set) var configuredInputSource: GestureInputSource = .none
    @Published private(set) var runtimeState: CameraNavigationRuntimeState = .off
    var status: String { runtimeState.message }
    @Published private(set) var duplicateDynamicIslandInstances = 0
    var duplicateInstanceWarning: String? {
        duplicateDynamicIslandInstances > 1 ? "Another DynamicIsland instance is running" : nil
    }
    @Published private(set) var firstFrameReceived = false
    @Published private(set) var videoOutputAttached = false
    @Published private(set) var validHandObserved = false
    @Published private(set) var pointerPresentationProduced = false
    @Published private(set) var detectedPose = "other"
    @Published private(set) var gestureMode = "pointer"
    @Published private(set) var gestureCandidate = "None"
    @Published private(set) var gestureRearm = "Ready"
    @Published private(set) var lastGestureAction = "None"
    @Published private(set) var lastGestureTimestamp = 0.0
    @Published private(set) var swipeDisplacement = CGPoint.zero
    @Published private(set) var swipeVelocity = 0.0
    @Published private(set) var calibrationError: String?
    @Published private(set) var isTracking = false
    @Published private(set) var recognitionFPS = 0.0
    @Published private(set) var meanLatencyMS = 0.0
    @Published private(set) var p95LatencyMS = 0.0
    @Published private(set) var calibrationStep: Int?
    @Published var preferences: CameraNavigationPreferences {
        didSet { if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferenceKey) } }
    }
    let camera: CameraPreviewController
    private let lease: CameraNavigationLease
    private let defaults: UserDefaults
    private static let preferenceKey = "cameraNavigation.preferences.v1"
    private let holdOwner = TransientInteractionOwner.cameraNavigation(UUID())
    private var generation = 0
    var trackingGeneration: Int { generation }
    private var processor: HandPoseFrameProcessor?
    private var outputGeneration: Int?
    private var phaseSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    private var instanceSubscription: AnyCancellable?
    private let instanceCount: () -> Int
    private let frameTimeout: Duration
    private let deliversInput: Bool
    private var transitionTask: Task<Void, Never>?
    private var frameWatchdog: Task<Void, Never>?
    private var reconciled = false
    private var renderTimer: Timer?
    private var machine = HandNavigationStateMachine()
    private var filter = HandPointerFilter()
    private var target: CGPoint?
    private var rendered: CGPoint?
    private var lastTrackedAt: TimeInterval = 0
    private var latencySamples: [Double] = []
    private var metricsStartedAt: TimeInterval = 0
    private var metricCount = 0
    private var hasReceivedFrame = false
    var visionHasProducedResult: Bool { hasReceivedFrame }
    private var calibrationSamples: [Double] = []
    private weak var window: NSWindow?
    private var layout: IslandLayoutStore?
    private var router: CameraInteractionRouter?
    private var isExpanded: () -> Bool = { false }
    private var canInteract: () -> Bool = { false }
    private var expand: () -> Void = {}
    private var page: (Bool) -> Void = { _ in }
    private var collapse: () -> Void = {}
    private var canExpand: () -> Bool = { true }
    private var canCollapse: () -> Bool = { true }
    private lazy var mailbox = HandPoseResultMailbox { [weak self] result in self?.consume(result) }

    init(camera: CameraPreviewController, defaults: UserDefaults = .standard,
         settings: AppSettings? = nil, frameTimeout: Duration = .seconds(2), deliversInput: Bool = true,
         instanceCount: @escaping () -> Int = { CameraNavigationController.normalInstanceCount() }) {
        self.camera = camera; self.defaults = defaults
        self.frameTimeout = frameTimeout; self.instanceCount = instanceCount; self.deliversInput = deliversInput
        lease = CameraNavigationLease(controller: camera)
        preferences = defaults.data(forKey: Self.preferenceKey).flatMap { try? JSONDecoder().decode(CameraNavigationPreferences.self, from: $0) } ?? .init()
        phaseSubscription = camera.$phase.dropFirst().sink { [weak self] phase in
            guard let self, self.isEnabled else { return }
            switch phase {
            case .starting, .stopping:
                if self.processor != nil { self.generation += 1 }
                self.resetOutputState()
                self.runtimeState = .starting
                self.loseTracking(immediately: true)
            case .running:
                Task { @MainActor [weak self] in await self?.attachOutput() }
            case .failed(let message):
                self.queueFailure(message)
            case .idle:
                let token = self.generation
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.isEnabled, self.camera.phase == .idle else { return }
                    self.queueFailure("Camera session stopped")
                }
            }
        }
        instanceSubscription = Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
        ).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshInstanceDiagnostic() }
        }
        refreshInstanceDiagnostic()
        if let settings {
            settingsSubscription = settings.$gesturesEnabled.combineLatest(settings.$gestureInputSource)
                .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
                .sink { [weak self] enabled, source in self?.reconcile(gesturesEnabled: enabled, inputSource: source) }
        }
    }

    static func normalInstanceCount() -> Int {
        let probe = CommandLine.arguments.dropFirst().contains { $0.hasPrefix("--validate-") || $0.hasPrefix("--probe-") }
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.local.dynamicisland")
            .filter { !$0.isTerminated && (!probe || $0.processIdentifier != ProcessInfo.processInfo.processIdentifier) }.count
    }

    func refreshInstanceDiagnostic() { duplicateDynamicIslandInstances = instanceCount() }

    /// AppSettings is the sole durable authority; initial publication also resumes an authorized launch.
    func reconcile(gesturesEnabled: Bool, inputSource: GestureInputSource) {
        configuredInputSource = inputSource
        let desired = gesturesEnabled && inputSource == .camera
        guard !reconciled || desired != desiredCameraNavigation else { return }
        reconciled = true; desiredCameraNavigation = desired
        queueReconciliation(requestPermission: false)
    }

    func allowCamera() async {
        guard desiredCameraNavigation, camera.permissionState == .notDetermined else { return }
        queueReconciliation(requestPermission: true)
        await waitForReconciliation()
    }

    func checkAgain() async {
        await camera.refresh(); refreshInstanceDiagnostic()
        if desiredCameraNavigation, !isEnabled || runtimeState == .noFrames {
            queueReconciliation(requestPermission: false)
            await waitForReconciliation()
        }
    }

    func waitForReconciliation() async { await transitionTask?.value }

    private func queueReconciliation(requestPermission: Bool) {
        let previous = transitionTask
        invalidate()
        let token = generation
        if desiredCameraNavigation {
            runtimeState = camera.permissionState == .authorized || requestPermission ? .starting : .permissionRequired
        }
        transitionTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            // Serialize release and reacquisition of the same lease, including rapid source changes.
            await self.releaseCapture()
            guard token == self.generation, self.desiredCameraNavigation else { return }
            if requestPermission { await self.camera.requestNavigationAccess() }
            guard token == self.generation, self.desiredCameraNavigation else { return }
            guard self.camera.permissionState == .authorized else { self.runtimeState = .permissionRequired; return }
            await self.startRuntime()
        }
    }

    private func queueFailure(_ message: String) {
        let previous = transitionTask
        invalidate(); runtimeState = .unavailable(message)
        transitionTask = Task { @MainActor [weak self] in
            await previous?.value
            await self?.releaseCapture()
        }
    }

    func connect(window: NSWindow, layout: IslandLayoutStore, isExpanded: @escaping () -> Bool,
                 canInteract: @escaping () -> Bool, expand: @escaping () -> Void, page: @escaping (Bool) -> Void,
                 canExpand: @escaping () -> Bool = { true }, canCollapse: @escaping () -> Bool = { true },
                 collapse: @escaping () -> Void = {}) {
        loseTracking(immediately: true)
        router?.shutdown()
        self.window = window; self.layout = layout; self.isExpanded = isExpanded
        self.canInteract = canInteract; self.expand = expand; self.page = page
        self.canExpand = canExpand; self.canCollapse = canCollapse; self.collapse = collapse
        router = CameraInteractionRouter(window: window)
        router?.allowsCameraInput = { [weak self] in
            guard let self else { return false }
            return self.isEnabled && self.isExpanded() && self.canInteract() && self.camera.isRunning
        }
        router?.onPhysicalInput = { [weak self] in
            guard let self, self.isEnabled else { return }
            _ = self.machine.suspendInteraction()
            self.hidePointer()
            self.layout?.setTransientInteraction(false, owner: self.holdOwner)
        }
    }

    private func startRuntime() async {
        guard !isEnabled else { return }
        let token = generation
        captureRequested = true; runtimeState = .starting
        do {
            try await lease.acquire(requestPermission: false)
            guard token == generation, isEnabled else { return }
            if camera.isRunning { await attachOutput() }
        } catch {
            guard token == generation else { return }
            queueFailure(error.localizedDescription)
        }
    }

    private func attachOutput() async {
        guard isEnabled, camera.isRunning, outputGeneration != generation else { return }
        let token = generation
        outputGeneration = token
        let mailbox = self.mailbox
        let processor = HandPoseFrameProcessor(generation: token) { mailbox.submit($0) }
        self.processor = processor
        do {
            try await camera.setNavigationProcessor(processor)
            guard token == generation, isEnabled else { processor.stop(); return }
            videoOutputAttached = true
            if !hasReceivedFrame { runtimeState = .preparing }
            if !firstFrameReceived {
                frameWatchdog = Task { @MainActor [weak self, frameTimeout] in
                    do { try await Task.sleep(for: frameTimeout) } catch { return }
                    guard let self, self.generation == token, self.isEnabled,
                          self.videoOutputAttached, !self.firstFrameReceived else { return }
                    self.runtimeState = .noFrames
                }
            }
            metricsStartedAt = ProcessInfo.processInfo.systemUptime; metricCount = 0; latencySamples = []
            if renderTimer == nil {
                let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.render() }
                }
                renderTimer = timer; RunLoop.main.add(timer, forMode: .common)
            }
        } catch {
            guard token == generation else { return }
            queueFailure(error.localizedDescription)
        }
    }

    private func releaseCapture() async {
        try? await camera.setNavigationProcessor(nil)
        await lease.release()
    }

    func shutdown() async {
        settingsSubscription?.cancel()
        desiredCameraNavigation = false
        queueReconciliation(requestPermission: false)
        await waitForReconciliation()
    }

    func terminate() {
        settingsSubscription?.cancel(); instanceSubscription?.cancel()
        invalidate(); router?.shutdown()
    }

    func physicalTouchSession(active: Bool) { router?.physicalTouchSession(active: active) }

    private func invalidate() {
        generation += 1; captureRequested = false
        resetOutputState()
        renderTimer?.invalidate(); renderTimer = nil
        calibrationStep = nil; calibrationSamples = []
        loseTracking(immediately: true); runtimeState = .off
    }

    private func resetOutputState() {
        frameWatchdog?.cancel(); frameWatchdog = nil
        firstFrameReceived = false; hasReceivedFrame = false; videoOutputAttached = false
        validHandObserved = false; pointerPresentationProduced = false
        recognitionFPS = 0; meanLatencyMS = 0; p95LatencyMS = 0
        outputGeneration = nil; processor?.stop(); processor = nil
    }

    /// Same bounded mailbox used by the sample delegate and deterministic integration acceptance.
    func submit(_ result: HandPoseFrameResult) { mailbox.submit(result) }

    func consume(_ result: HandPoseFrameResult) {
        guard isEnabled, result.generation == generation else { return }
        if !firstFrameReceived {
            firstFrameReceived = true; frameWatchdog?.cancel(); frameWatchdog = nil
            runtimeState = .preparing
        }
        if result.isSampleReceipt { return }
        if result.observation?.isValid == true { validHandObserved = true }
        let time = ProcessInfo.processInfo.systemUptime
        if !hasReceivedFrame {
            hasReceivedFrame = true
            metricsStartedAt = time; metricCount = 0; latencySamples = []
        }
        if result.failed {
            loseTracking(immediately: true)
            queueFailure("Hand tracking failed. Check Again to retry.")
            return
        }
        do {
            metricCount += 1
            latencySamples.append(result.latency * 1000)
            if latencySamples.count > 120 { latencySamples.removeFirst() }
            if time - metricsStartedAt >= 1 {
                recognitionFPS = Double(metricCount) / (time - metricsStartedAt)
                meanLatencyMS = latencySamples.reduce(0, +) / Double(max(latencySamples.count, 1))
                let sorted = latencySamples.sorted()
                p95LatencyMS = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                metricsStartedAt = time; metricCount = 0
            }
        }
        guard let observation = result.observation, observation.isValid,
              time - observation.timestamp >= 0, time - observation.timestamp < 0.25 else {
            loseTracking(immediately: false)
            return
        }
        lastTrackedAt = time
        if !isTracking { isTracking = true }
        let available = canInteract() && !interactionFrame.isEmpty && router?.physicalOwnsInput != true
        runtimeState = router?.physicalOwnsInput == true ? .suspendedPhysicalInput
            : !available ? .waitingForIsland : .tracking
        target = filter.update(preferences.calibration.map(observation.fingertip, sensitivity: preferences.sensitivity),
                               at: observation.timestamp, smoothing: preferences.smoothing)
        if rendered == nil { rendered = target }
        let actions = machine.update(observation, pinchSensitivity: preferences.pinchSensitivity,
            scroll: preferences.twoFingerScroll, expanded: isExpanded(), interactionAvailable: available,
            expandOnPinch: calibrationStep != nil || (preferences.collapsedPinchAction == .expand && canExpand()),
            leftAction: preferences.swipeLeftAction, rightAction: preferences.swipeRightAction,
            downAction: preferences.swipeDownAction)
        detectedPose = machine.classifier.palmCandidate ? "Open palm" : machine.classifier.pose.rawValue
        gestureMode = machine.mode.rawValue
        gestureCandidate = machine.classifier.palmCandidate ? "Palm swipe" : machine.phase == .pinchCandidate ? "Pinch" : "None"
        gestureRearm = machine.mode == .rearming || !machine.swipeArmed ? "Return to pointing" : "Ready"
        swipeDisplacement = machine.swipeDisplacement; swipeVelocity = machine.swipeVelocity
        if !available { router?.cancel() }
        render()
        guard deliversInput else { return }
        for action in actions {
            if calibrationStep != nil {
                if action == .press || action == .expandIsland { recordCalibration(observation.fingertip) }
                continue
            }
            switch action {
            case .expandIsland:
                guard available, canExpand() else { continue }
                recordGesture("Expand", at: observation.timestamp); hidePointer(); expand()
            case .collapseIsland:
                guard available, !routerIsPressed, !hasProtectedInteraction, canCollapse() else { continue }
                recordGesture("Collapse", at: observation.timestamp); hidePointer(); collapse()
            case .page(let forward):
                guard available else { continue }
                recordGesture(forward ? "Next Page" : "Previous Page", at: observation.timestamp)
                hidePointer(); page(forward)
            case .cancel: router?.cancel()
            case .press:
                if available, isExpanded(), let point = windowPoint { router?.press(at: point) }
            case .drag:
                if available, isExpanded(), let point = windowPoint { router?.drag(to: point) }
            case .release:
                if let point = windowPoint { router?.release(at: point) }
            case .scroll(let delta):
                if available, isExpanded(), let point = windowPoint { router?.scroll(at: point, delta: delta) }
            }
        }
    }

    private func recordGesture(_ action: String, at time: TimeInterval) {
        lastGestureAction = action; lastGestureTimestamp = time
    }

    private func hidePointer() {
        if layout?.cameraPointerStore.presentation != nil { layout?.cameraPointerStore.presentation = nil }
    }

    private var interactionFrame: CGRect {
        guard let layout else { return .zero }
        return isExpanded() ? layout.expandedSurfaceFrame : layout.collapsedPreviewActive
            ? layout.collapsedCompositeInteractionFrame.union(layout.collapsedPreviewSurfaceFrame) : layout.collapsedCompositeInteractionFrame
    }

    private var canvasPoint: CGPoint? {
        guard let rendered, !interactionFrame.isEmpty else { return nil }
        var point = HandNavigationCoordinates.islandPoint(rendered, frame: interactionFrame)
        if preferences.magneticControls, !routerIsPressed, let layout, let window {
            for region in layout.nativeControlRegions.values {
                let frame = IslandCanvasCoordinateSpace.appKitLocalRect(fromSwiftUI: region, canvasHeight: layout.canvasSize.height)
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let radius = min(24, max(frame.width, frame.height) * 0.5 + 8)
                let distance = hypot(point.x - center.x, point.y - center.y)
                guard distance < radius,
                      let target = window.contentView?.hitTest(window.contentView?.superview?.convert(windowPoint(fromCanvas: center), from: nil) ?? windowPoint(fromCanvas: center)) else { continue }
                var candidate: NSView? = target
                var enabledControl = false
                while let view = candidate {
                    if let control = view as? NSControl { enabledControl = control.isEnabled; break }
                    candidate = view.superview
                }
                guard enabledControl else { continue }
                let weight = (1 - distance / radius) * 0.22
                point.x += (center.x - point.x) * weight; point.y += (center.y - point.y) * weight
                break
            }
        }
        return point
    }

    private var routerIsPressed: Bool { router?.isPressed ?? false }
    private var hasProtectedInteraction: Bool {
        guard let layout else { return true }
        return layout.isTextInputFocused || layout.transientInteractionOwners.contains { owner in
            if case .cameraNavigation = owner { return false }
            return true
        }
    }
    private func windowPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y + (window?.contentView?.bounds.height ?? 0) - (layout?.canvasSize.height ?? 0))
    }
    private var windowPoint: CGPoint? { canvasPoint.map(windowPoint(fromCanvas:)) }
    private var isOverNativeControl: Bool { canvasPoint.map { layout?.containsNativeControlPoint(CGPoint(x: $0.x, y: (layout?.canvasSize.height ?? 0) - $0.y)) ?? false } ?? false }

    private func render() {
        guard isEnabled, hasReceivedFrame else { return }
        let time = ProcessInfo.processInfo.systemUptime
        if time - lastTrackedAt > 0.65 { loseTracking(immediately: true); return }
        guard isTracking, let target, let layout else { hidePointer(); return }
        guard router?.physicalOwnsInput != true else {
            hidePointer(); layout.setTransientInteraction(false, owner: holdOwner); return
        }
        let previous = rendered ?? target
        // Linear display-rate interpolation; no spring, including Reduce Motion.
        rendered = CGPoint(x: previous.x + (target.x - previous.x) * 0.5, y: previous.y + (target.y - previous.y) * 0.5)
        layout.setTransientInteraction(isExpanded(), owner: holdOwner)
        if let point = canvasPoint, preferences.showPointer, isExpanded(), canInteract(), machine.hasPrecisionInteraction {
            let next = CameraPointerPresentation(point: point, phase: machine.phase, overControl: isOverNativeControl || windowPoint.map { router?.isInteractive(at: $0) ?? false } == true)
            if layout.cameraPointerStore.presentation != next { layout.cameraPointerStore.presentation = next }
            pointerPresentationProduced = true
        } else if layout.cameraPointerStore.presentation != nil { layout.cameraPointerStore.presentation = nil }
    }

    private func loseTracking(immediately: Bool) {
        let expired = immediately || ProcessInfo.processInfo.systemUptime - lastTrackedAt > 0.65
        if expired {
            _ = machine.reset()
            filter.reset(); target = nil; rendered = nil
        } else { _ = machine.suspendInteraction() }
        router?.cancel()
        detectedPose = "No hand"; gestureCandidate = "None"
        gestureRearm = machine.swipeArmed ? "Waiting for hand" : "Return to pointing"
        if isTracking { isTracking = false }
        if layout?.cameraPointerStore.presentation != nil {
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.12)) {
                layout?.cameraPointerStore.presentation = nil
            }
        }
        if isEnabled, hasReceivedFrame {
            let next: CameraNavigationRuntimeState = router?.physicalOwnsInput == true ? .suspendedPhysicalInput
                : !canInteract() || interactionFrame.isEmpty ? .waitingForIsland : .noHand
            if runtimeState != next { runtimeState = next }
        }
        if expired {
            layout?.setTransientInteraction(false, owner: holdOwner)
        }
    }

    func beginCalibration() {
        guard isEnabled else { return }
        router?.cancel(); _ = machine.reset(); calibrationError = nil; calibrationStep = 0; calibrationSamples = []
    }
    func cancelCalibration() { calibrationStep = nil; calibrationSamples = [] }
    func resetCalibration() { cancelCalibration(); preferences.calibration = .init() }
    private func recordCalibration(_ point: CGPoint) {
        guard let step = calibrationStep else { return }
        calibrationSamples.append(step < 2 ? point.x : point.y)
        if step < 3 { calibrationStep = step + 1; return }
        let calibration = HandNavigationCalibration(left: calibrationSamples[0], right: calibrationSamples[1],
                                                     bottom: calibrationSamples[3], top: calibrationSamples[2])
        if calibration.isValid { preferences.calibration = calibration; cancelCalibration() }
        else { calibrationSamples = []; calibrationStep = 0; calibrationError = "Calibration bounds were too close. Try again." }
    }
}
