import AppKit
import Combine
import SwiftUI

struct CameraNavigationPreferences: Codable, Equatable {
    var showPointer = true
    var magneticControls = false
    var horizontalPageSwipe = true
    var twoFingerScroll = false
    var sensitivity = 0.5
    var smoothing = 0.65
    var pinchSensitivity = 0.5
    var calibration = HandNavigationCalibration()
}

struct CameraPointerPresentation: Equatable {
    var point: CGPoint
    var phase: HandNavigationStateMachine.Phase
    var overControl: Bool
}

@MainActor
final class CameraNavigationController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isTracking = false
    @Published private(set) var status = "Camera navigation is off"
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
    private var calibrationSamples: [Double] = []
    private weak var window: NSWindow?
    private var layout: IslandLayoutStore?
    private var router: CameraInteractionRouter?
    private var isExpanded: () -> Bool = { false }
    private var canInteract: () -> Bool = { false }
    private var expand: () -> Void = {}
    private var page: (Bool) -> Void = { _ in }
    private var collapsedPress = false
    private lazy var mailbox = HandPoseResultMailbox { [weak self] result in self?.consume(result) }

    init(camera: CameraPreviewController, defaults: UserDefaults = .standard) {
        self.camera = camera; self.defaults = defaults
        lease = CameraNavigationLease(controller: camera)
        preferences = defaults.data(forKey: Self.preferenceKey).flatMap { try? JSONDecoder().decode(CameraNavigationPreferences.self, from: $0) } ?? .init()
        phaseSubscription = camera.$phase.dropFirst().sink { [weak self] phase in
            guard let self, self.isEnabled else { return }
            switch phase {
            case .starting, .stopping:
                if self.processor != nil { self.generation += 1 }
                self.processor?.stop(); self.processor = nil; self.outputGeneration = nil
                self.loseTracking(immediately: true)
            case .running:
                Task { @MainActor [weak self] in await self?.attachOutput() }
            case .failed, .idle:
                Task { @MainActor [weak self] in
                    guard let self, self.isEnabled, self.camera.phase == phase else { return }
                    let status = self.camera.statusText
                    await self.stop(); self.status = status
                }
            }
        }
    }

    func connect(window: NSWindow, layout: IslandLayoutStore, isExpanded: @escaping () -> Bool,
                 canInteract: @escaping () -> Bool, expand: @escaping () -> Void, page: @escaping (Bool) -> Void) {
        router?.shutdown()
        self.window = window; self.layout = layout; self.isExpanded = isExpanded
        self.canInteract = canInteract; self.expand = expand; self.page = page
        router = CameraInteractionRouter(window: window)
        router?.allowsCameraInput = { [weak self] in
            guard let self else { return false }
            return self.isEnabled && self.canInteract() && self.camera.isRunning
        }
        router?.onPhysicalInput = { [weak self] in
            guard let self, self.isEnabled else { return }
            self.loseTracking(immediately: true)
        }
    }

    /// Only called by the explicit Settings toggle, never by view appearance.
    func start() async {
        guard !isEnabled else { return }
        generation += 1; let token = generation
        isEnabled = true; status = "Starting camera…"
        do {
            try await lease.acquire()
            guard token == generation, isEnabled else { return }
            if camera.isRunning { await attachOutput() }
        } catch {
            guard token == generation else { return }
            await stop(); status = error.localizedDescription
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
            hasReceivedFrame = false; status = "Preparing hand tracking…"
            metricsStartedAt = ProcessInfo.processInfo.systemUptime; metricCount = 0; latencySamples = []
            if renderTimer == nil {
                let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.render() }
                }
                renderTimer = timer; RunLoop.main.add(timer, forMode: .common)
            }
        } catch {
            guard token == generation else { return }
            await stop(); status = error.localizedDescription
        }
    }

    func stop() async {
        invalidate()
        try? await camera.setNavigationProcessor(nil)
        await lease.release()
    }

    func terminate() {
        invalidate(); router?.shutdown()
    }

    func physicalTouchSession(active: Bool) { router?.physicalTouchSession(active: active) }

    private func invalidate() {
        generation += 1; isEnabled = false; outputGeneration = nil
        hasReceivedFrame = false
        processor?.stop(); processor = nil
        renderTimer?.invalidate(); renderTimer = nil
        calibrationStep = nil; calibrationSamples = []
        loseTracking(immediately: true); status = "Camera navigation is off"
    }

    func consume(_ result: HandPoseFrameResult) {
        let time = ProcessInfo.processInfo.systemUptime
        if isEnabled, result.generation == generation, !hasReceivedFrame {
            hasReceivedFrame = true
            metricsStartedAt = time; metricCount = 0; latencySamples = []
        }
        if isEnabled, result.generation == generation, result.failed {
            loseTracking(immediately: true)
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, result.generation == self.generation else { return }
                await self.stop(); self.status = "Hand tracking is unavailable. Try enabling it again."
            }
            return
        }
        if isEnabled, result.generation == generation {
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
        guard isEnabled, result.generation == generation, canInteract(), router?.physicalOwnsInput != true,
              let observation = result.observation, observation.isValid,
              time - observation.timestamp >= 0, time - observation.timestamp < 0.25 else {
            if isEnabled, result.generation == generation { loseTracking(immediately: false) }
            return
        }
        lastTrackedAt = time
        if !isTracking { isTracking = true; status = "Tracking" }
        target = filter.update(preferences.calibration.map(observation.fingertip, sensitivity: preferences.sensitivity),
                               at: observation.timestamp, smoothing: preferences.smoothing)
        if rendered == nil { rendered = target }
        let actions = machine.update(observation, pinchSensitivity: preferences.pinchSensitivity,
                                     pageSwipe: preferences.horizontalPageSwipe, scroll: preferences.twoFingerScroll)
        render()
        for action in actions {
            if calibrationStep != nil {
                if action == .press { recordCalibration(observation.fingertip) }
                continue
            }
            guard let point = windowPoint else { continue }
            switch action {
            case .press:
                collapsedPress = !isExpanded() && !isOverNativeControl && router?.isInteractive(at: point) != true
                if !collapsedPress { router?.press(at: point) }
            case .drag:
                if !collapsedPress { router?.drag(to: point) }
            case .release:
                if collapsedPress { collapsedPress = false; expand() }
                else { router?.release(at: point) }
            case .cancel: collapsedPress = false; router?.cancel()
            case .page(let forward):
                page(forward)
            case .scroll(let delta): if isExpanded() { router?.scroll(at: point, delta: delta) }
            }
        }

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
    private func windowPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y + (window?.contentView?.bounds.height ?? 0) - (layout?.canvasSize.height ?? 0))
    }
    private var windowPoint: CGPoint? { canvasPoint.map(windowPoint(fromCanvas:)) }
    private var isOverNativeControl: Bool { canvasPoint.map { layout?.containsNativeControlPoint(CGPoint(x: $0.x, y: (layout?.canvasSize.height ?? 0) - $0.y)) ?? false } ?? false }

    private func render() {
        guard isEnabled, hasReceivedFrame else { return }
        let time = ProcessInfo.processInfo.systemUptime
        if time - lastTrackedAt > 0.65 { loseTracking(immediately: true); return }
        guard isTracking, canInteract(), router?.physicalOwnsInput != true, let target, let layout else { return }
        let previous = rendered ?? target
        // Linear display-rate interpolation; no spring, including Reduce Motion.
        rendered = CGPoint(x: previous.x + (target.x - previous.x) * 0.5, y: previous.y + (target.y - previous.y) * 0.5)
        layout.setTransientInteraction(isExpanded(), owner: holdOwner)
        if let point = canvasPoint, preferences.showPointer {
            let next = CameraPointerPresentation(point: point, phase: machine.phase, overControl: isOverNativeControl || windowPoint.map { router?.isInteractive(at: $0) ?? false } == true)
            if layout.cameraPointerStore.presentation != next { layout.cameraPointerStore.presentation = next }
        } else if layout.cameraPointerStore.presentation != nil { layout.cameraPointerStore.presentation = nil }
    }

    private func loseTracking(immediately: Bool) {
        _ = machine.reset(); router?.cancel(); collapsedPress = false
        filter.reset(); target = nil; rendered = nil
        if isTracking { isTracking = false }
        if layout?.cameraPointerStore.presentation != nil {
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.12)) {
                layout?.cameraPointerStore.presentation = nil
            }
        }
        let nextStatus = !hasReceivedFrame ? "Preparing hand tracking…" : router?.physicalOwnsInput == true
            ? "Using mouse, trackpad or keyboard" : !canInteract() ? "Waiting for the island" : "No hand"
        if isEnabled, status != nextStatus { status = nextStatus }
        if immediately || ProcessInfo.processInfo.systemUptime - lastTrackedAt > 0.65 {
            layout?.setTransientInteraction(false, owner: holdOwner)
        }
    }

    func beginCalibration() {
        guard isEnabled else { return }
        router?.cancel(); _ = machine.reset(); calibrationStep = 0; calibrationSamples = []
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
        else { calibrationSamples = []; calibrationStep = 0; status = "Calibration bounds were too close. Try again." }
    }
}
