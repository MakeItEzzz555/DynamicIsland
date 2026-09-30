import AppKit
@preconcurrency import AVFoundation
import Foundation

enum CameraPermissionState: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

struct CameraDeviceDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let isBuiltIn: Bool
}

enum CameraPreviewPhase: Equatable, Sendable {
    case idle
    case starting
    case running(deviceID: String)
    case stopping
    case failed(String)
}

enum CameraPreviewError: LocalizedError, Equatable {
    case disabled
    case permissionRequired
    case noDevices
    case deviceUnavailable
    case sessionFailed(String)
    case unsupportedAction(IslandCapabilityAction)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "Camera preview is disabled."
        case .permissionRequired:
            "Camera access is required."
        case .noDevices:
            "No camera is available."
        case .deviceUnavailable:
            "The selected camera is no longer available."
        case .sessionFailed(let message):
            "Camera preview failed: \(message)"
        case .unsupportedAction(let action):
            "Camera preview does not support \(action.rawValue)."
        }
    }
}

@MainActor
protocol CameraDeviceProviding: AnyObject {
    var permissionState: CameraPermissionState { get }
    func requestAccess() async -> CameraPermissionState
    func availableDevices() -> [CameraDeviceDescriptor]
}

/// Preview-only capture: no outputs are attached, so no frames are recorded
/// or persisted.
@MainActor
protocol CameraCaptureSessionControlling: AnyObject {
    /// The running session for an `AVCaptureVideoPreviewLayer`; nil in tests.
    var previewSession: AVCaptureSession? { get }
    /// Called when the system stops the session (disconnect, runtime error).
    var onUnexpectedStop: ((String) -> Void)? { get set }
    /// Resolves only after the capture session reports running.
    func start(deviceID: String) async throws
    /// Resolves after the session stopped and inputs were released. Idempotent.
    func stop() async
    /// Synchronous teardown for application termination. Idempotent.
    func stopImmediately()
}

// MARK: - AVFoundation implementations

@MainActor
final class SystemCameraDeviceProvider: CameraDeviceProviding {
    var permissionState: CameraPermissionState {
        Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestAccess() async -> CameraPermissionState {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return permissionState
    }

    func availableDevices() -> [CameraDeviceDescriptor] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map {
            CameraDeviceDescriptor(
                id: $0.uniqueID,
                name: $0.localizedName,
                isBuiltIn: $0.deviceType == .builtInWideAngleCamera
            )
        }
    }

    nonisolated static func map(_ status: AVAuthorizationStatus) -> CameraPermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .denied
        }
    }
}

@MainActor
final class AVFoundationCameraSession: CameraCaptureSessionControlling {
    private(set) var previewSession: AVCaptureSession?
    var onUnexpectedStop: ((String) -> Void)?

    private let queue = DispatchQueue(label: "DynamicIsland.CameraPreview.session")
    private var observers: [NSObjectProtocol] = []

    func start(deviceID: String) async throws {
        await stop()
        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            throw CameraPreviewError.deviceUnavailable
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraPreviewError.sessionFailed(error.localizedDescription)
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraPreviewError.sessionFailed("The camera input could not be attached.")
        }
        session.addInput(input)
        session.commitConfiguration()

        let box = SessionBox(session)
        let running = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                box.session.startRunning()
                continuation.resume(returning: box.session.isRunning)
            }
        }
        guard running else {
            await Self.stop(box, on: queue)
            throw CameraPreviewError.sessionFailed("The capture session did not start.")
        }
        previewSession = session
        installObservers(for: session, device: device)
    }

    func stop() async {
        removeObservers()
        guard let session = previewSession else { return }
        previewSession = nil
        await Self.stop(SessionBox(session), on: queue)
    }

    func stopImmediately() {
        removeObservers()
        guard let session = previewSession else { return }
        previewSession = nil
        let box = SessionBox(session)
        queue.sync {
            Self.teardown(box.session)
        }
    }

    private static func stop(_ box: SessionBox, on queue: DispatchQueue) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                teardown(box.session)
                continuation.resume()
            }
        }
    }

    nonisolated private static func teardown(_ session: AVCaptureSession) {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
    }

    private func installObservers(for session: AVCaptureSession, device: AVCaptureDevice) {
        let center = NotificationCenter.default
        let sessionID = ObjectIdentifier(session)
        let handler: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self,
                      self.previewSession.map(ObjectIdentifier.init) == sessionID else { return }
                self.onUnexpectedStop?(message)
            }
        }
        observers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { _ in
                handler("The camera stopped because of a capture error.")
            },
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { _ in
                handler("The camera was interrupted by the system.")
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { _ in
                handler("The camera was disconnected.")
            }
        ]
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

private final class SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

// MARK: - Mirror consumer lease

/// One visible Camera Mirror's claim on the preview consumer count. The claim
/// is taken synchronously before any await, so a Close Mirror / page change /
/// disappear that races an in-flight attach always detaches exactly once and
/// can never leak a consumer (which would keep capture running after close).
/// A reference type so SwiftUI view identity changes cannot lose the claim.
@MainActor
final class CameraMirrorConsumerLease {
    private let controller: CameraPreviewController
    private(set) var isHeld = false

    init(controller: CameraPreviewController) {
        self.controller = controller
    }

    /// Mirror appeared / page became active. Never prompts for permission.
    func acquire() async {
        guard !isHeld else { return }
        isHeld = true
        await controller.attachPreviewConsumer()
    }

    /// Explicit Allow / Start / Retry from the mirror UI; may prompt.
    func startExplicitly() async throws {
        if !isHeld {
            isHeld = true
            await controller.attachPreviewConsumer()
        }
        try await controller.startPreviewConsumer()
    }

    /// Close Mirror, page deactivation or disappearance.
    func release() async {
        guard isHeld else { return }
        isHeld = false
        await controller.detachPreviewConsumer()
    }
}

// MARK: - Controller

@MainActor
final class CameraPreviewController: ObservableObject, IslandCapabilityAdapter {
    static let activityID = "camera.preview"

    let capabilityID: IslandCapabilityID = .camera

    @Published private(set) var phase: CameraPreviewPhase = .idle
    @Published private(set) var permissionState: CameraPermissionState
    @Published private(set) var devices: [CameraDeviceDescriptor] = []
    @Published var selectedDeviceID: String?
    @Published private(set) var isEnabled = true

    private let deviceProvider: CameraDeviceProviding
    private let session: CameraCaptureSessionControlling
    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let now: () -> Date
    private var generation = 0

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        deviceProvider: CameraDeviceProviding = SystemCameraDeviceProvider(),
        session: CameraCaptureSessionControlling = AVFoundationCameraSession(),
        now: @escaping () -> Date = Date.init
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.deviceProvider = deviceProvider
        self.session = session
        self.now = now
        self.permissionState = deviceProvider.permissionState
        if permissionState == .authorized {
            // Enumeration does not prompt once access was granted.
            reloadDevices()
        }
        session.onUnexpectedStop = { [weak self] message in
            self?.handleUnexpectedStop(message)
        }
        publishState()
    }

    var previewSession: AVCaptureSession? {
        if case .running = phase { return session.previewSession }
        return nil
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var activeDeviceName: String? {
        guard case .running(let id) = phase else { return nil }
        return devices.first(where: { $0.id == id })?.name
    }

    var snapshot: IslandCapabilitySnapshot {
        let mapping = Self.capabilityMapping(permission: permissionState, hasDevices: !devices.isEmpty || permissionState != .authorized)
        let health: IslandCapabilityHealth
        if case .failed(let message) = phase {
            health = .failed(message: message)
        } else {
            health = .healthy
        }
        return IslandCapabilitySnapshot(
            id: .camera,
            isEnabled: isEnabled,
            permission: mapping.permission,
            availability: mapping.availability,
            health: health,
            supportedActions: isRunning ? [.stop, .openSettings, .test] : [.start, .openSettings, .test],
            isActive: isEnabled && isRunning,
            progress: nil,
            statusText: statusText
        )
    }

    var statusText: String {
        guard isEnabled else { return "Disabled" }
        switch phase {
        case .idle:
            switch permissionState {
            case .notDetermined: return "Permission not requested"
            case .denied: return "Permission denied"
            case .restricted: return "Camera restricted"
            case .authorized: return devices.isEmpty ? "No camera found" : "Ready"
            }
        case .starting: return "Starting camera"
        case .running: return activeDeviceName.map { "Previewing \($0)" } ?? "Previewing"
        case .stopping: return "Stopping camera"
        case .failed(let message): return message
        }
    }

    static func capabilityMapping(
        permission: CameraPermissionState,
        hasDevices: Bool
    ) -> (permission: IslandCapabilityPermissionState, availability: IslandCapabilityAvailability) {
        switch permission {
        case .notDetermined:
            return (.notDetermined, .available)
        case .denied:
            return (.denied, .available)
        case .restricted:
            return (.denied, .unsupported(reason: "Camera access is restricted on this Mac."))
        case .authorized:
            return (.granted, hasDevices ? .available : .temporarilyUnavailable(reason: "No camera is connected."))
        }
    }

    /// Deterministic device choice: the requested device when present,
    /// otherwise the first built-in camera, otherwise the first by name.
    static func resolveDevice(
        preferredID: String?,
        in devices: [CameraDeviceDescriptor]
    ) -> CameraDeviceDescriptor? {
        let ordered = sortedDevices(devices)
        if let preferredID, let match = ordered.first(where: { $0.id == preferredID }) {
            return match
        }
        return ordered.first(where: \.isBuiltIn) ?? ordered.first
    }

    static func sortedDevices(_ devices: [CameraDeviceDescriptor]) -> [CameraDeviceDescriptor] {
        devices.sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            if order == .orderedSame { return $0.id < $1.id }
            return order == .orderedAscending
        }
    }

    // MARK: Lifecycle

    /// Explicit user action. Requests camera access only if undetermined.
    /// The caller becomes an explicit owner: closing the Camera Mirror (a
    /// preview consumer) never stops capture an explicit owner relies on,
    /// even when the mirror started the session first.
    func open() async throws {
        explicitOwnerActive = true
        do {
            try await startCapture()
        } catch {
            explicitOwnerActive = false
            throw error
        }
    }

    private func startCapture() async throws {
        guard isEnabled else { throw CameraPreviewError.disabled }
        if case .running = phase { return }
        if phase == .starting { return }

        generation += 1
        let token = generation
        phase = .starting
        publishState()

        if deviceProvider.permissionState == .notDetermined {
            permissionState = await deviceProvider.requestAccess()
        } else {
            permissionState = deviceProvider.permissionState
        }
        guard token == generation else { return }

        do {
            guard permissionState == .authorized else {
                throw CameraPreviewError.permissionRequired
            }
            reloadDevices()
            guard let device = Self.resolveDevice(preferredID: selectedDeviceID, in: devices) else {
                throw CameraPreviewError.noDevices
            }
            selectedDeviceID = device.id
            do {
                try await session.start(deviceID: device.id)
            } catch let error as CameraPreviewError {
                throw error
            } catch {
                throw CameraPreviewError.sessionFailed(error.localizedDescription)
            }
            guard token == generation else {
                await session.stop()
                return
            }
            phase = .running(deviceID: device.id)
            publishActivity(device: device)
            publishState()
        } catch {
            guard token == generation else { return }
            await session.stop()
            liveActivities.remove(id: Self.activityID)
            phase = .failed(error.localizedDescription)
            publishState()
            throw error
        }
    }

    /// Idempotent. The activity is removed only after the session stopped.
    /// Stops capture for every owner and clears all ownership claims.
    func close() async {
        explicitOwnerActive = false
        consumerStartedSession = false
        await stopCapture()
    }

    private func stopCapture() async {
        generation += 1
        guard phase != .idle else {
            await session.stop()
            return
        }
        phase = .stopping
        publishState()
        await session.stop()
        liveActivities.remove(id: Self.activityID)
        phase = .idle
        publishState()
    }

    // MARK: Preview consumers (Droppy CameraManager.previewDidAppear/Disappear)

    private var previewConsumers = 0
    private var consumerStartedSession = false
    private var explicitOwnerActive = false

    /// A visible preview surface appeared. Starts capture only when access
    /// was already granted, so appearing never prompts for permission.
    func attachPreviewConsumer() async {
        previewConsumers += 1
        guard previewConsumers == 1,
              isEnabled,
              deviceProvider.permissionState == .authorized,
              !isRunning,
              phase != .starting else { return }
        consumerStartedSession = true
        do {
            try await startCapture()
        } catch {
            consumerStartedSession = false
        }
    }

    /// Explicit action from the mirror UI. Unlike attachPreviewConsumer(),
    /// this is allowed to request camera permission and guarantees that this
    /// preview consumer owns the session it starts, so closing the mirror can
    /// release capture resources without affecting another explicit camera use.
    func startPreviewConsumer() async throws {
        if previewConsumers == 0 {
            previewConsumers = 1
        }
        guard isEnabled else { throw CameraPreviewError.disabled }
        if isRunning {
            // The running capture may belong to another explicit consumer.
            // This mirror observes it but must not claim ownership or stop it.
            return
        }
        consumerStartedSession = true
        do {
            try await startCapture()
        } catch {
            consumerStartedSession = false
            throw error
        }
    }

    /// The last visible preview surface disappeared: stop capture that a
    /// surface started. An explicit user-opened preview is left alone.
    func detachPreviewConsumer() async {
        previewConsumers = max(0, previewConsumers - 1)
        guard previewConsumers == 0, consumerStartedSession else { return }
        consumerStartedSession = false
        // An explicit owner that joined the mirror's session keeps it.
        guard !explicitOwnerActive else { return }
        await stopCapture()
    }

    var activePreviewConsumers: Int { previewConsumers }
    /// True while capture was requested by an explicit owner (`open()`).
    var hasExplicitOwner: Bool { explicitOwnerActive }

    /// Switches camera; restarts the preview when it is running.
    func selectDevice(id: String) async throws {
        selectedDeviceID = id
        guard isRunning else { return }
        // Restart keeps the existing ownership (mirror consumer vs explicit).
        await stopCapture()
        try await startCapture()
    }

    func setEnabled(_ enabled: Bool) async {
        if !enabled {
            await close()
        }
        isEnabled = enabled
        publishState()
    }

    /// Synchronous teardown for application termination.
    func terminate() {
        generation += 1
        explicitOwnerActive = false
        consumerStartedSession = false
        session.stopImmediately()
        liveActivities.remove(id: Self.activityID)
        phase = .idle
        publishState()
    }

    // MARK: IslandCapabilityAdapter

    /// Reads permission and devices without prompting.
    func refresh() async {
        permissionState = deviceProvider.permissionState
        if permissionState == .authorized {
            reloadDevices()
        } else {
            devices = []
        }
        publishState()
    }

    func perform(_ action: IslandCapabilityAction) async throws {
        switch action {
        case .start:
            try await open()
        case .stop:
            await close()
        case .test:
            await refresh()
        case .openSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        case .configureShortcut:
            throw CameraPreviewError.unsupportedAction(action)
        }
    }

    // MARK: Private

    private func reloadDevices() {
        devices = Self.sortedDevices(deviceProvider.availableDevices())
        if let selectedDeviceID, !devices.contains(where: { $0.id == selectedDeviceID }) {
            self.selectedDeviceID = nil
        }
    }

    private func handleUnexpectedStop(_ message: String) {
        guard isRunning else { return }
        generation += 1
        // The explicit owner's session is gone; a later mirror retry must be
        // able to own (and on close, release) the capture it restarts.
        explicitOwnerActive = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.session.stop()
            self.liveActivities.remove(id: Self.activityID)
            self.phase = .failed(message)
            self.publishState()
        }
    }

    private func publishActivity(device: CameraDeviceDescriptor) {
        liveActivities.update(Self.makeActivity(deviceName: device.name, updatedAt: now()))
    }

    /// Production activity shape; also used by Settings previews.
    static func makeActivity(deviceName: String, updatedAt: Date) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: activityID,
            kind: .camera,
            title: "Camera",
            subtitle: deviceName,
            symbolName: "camera.fill",
            priority: 94,
            isActive: true,
            progress: nil,
            updatedAt: updatedAt,
            lifecycle: LiveActivityLifecycleMetadata(
                authority: .avFoundation,
                startEvidence: "AVCaptureSession reported isRunning",
                progressEvidence: nil,
                completionEvidence: "AVCaptureSession stopped and inputs were removed",
                dismissPolicy: .untilSourceEnds,
                supportsCancellation: true
            )
        )
    }

    private func publishState() {
        capabilities.update(snapshot)
    }
}
