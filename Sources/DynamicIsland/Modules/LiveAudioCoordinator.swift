import AppKit
import Combine
import Foundation
import os

/// The single owner of Live Audio intent (contract revision 3). The saved
/// preference is the user's consent; capture runs only while that consent,
/// a visible media visualizer, playback and an awake, unlocked session all
/// hold. Reconciliation happens on edges (preference, leases, playback,
/// session, explicit actions), never per frame, so a failure cannot loop.
@MainActor
final class LiveAudioCoordinator: ObservableObject {
    let controller: AudioSpectrumController
    private let settings: AppSettings
    /// Desired state, distinct from `controller.presentation.availability`.
    @Published private(set) var desiredEnabled: Bool
    /// A confirmed permission denial blocks automatic retries until the user
    /// acts again; other failures retry only on the next eligibility edge.
    @Published private(set) var permissionBlocked = false

    private var leases: Set<UUID> = []
    private var isPlaying: Bool
    private var sessionActive = true
    private var shutDown = false
    private var releaseWork: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    /// Compact↔expanded swaps unmount one visualizer before mounting the next;
    /// the last lease is released only after this grace so the tap survives.
    private let releaseGrace: Duration
    private let resumeDelay: Duration
    #if DEBUG
    private var lastDiagnosticAt: Double = 0
    private static let log = Logger(subsystem: "DynamicIsland", category: "LiveAudio")
    #endif

    init(controller: AudioSpectrumController, settings: AppSettings,
         playback: AnyPublisher<Bool, Never>, initiallyPlaying: Bool = false,
         releaseGrace: Duration = .milliseconds(600), resumeDelay: Duration = .milliseconds(500),
         observeSystemEvents: Bool = true) {
        self.controller = controller
        self.settings = settings
        self.desiredEnabled = settings.liveAudioVisualizerEnabled
        self.isPlaying = initiallyPlaying
        self.releaseGrace = releaseGrace
        self.resumeDelay = resumeDelay
        playback.removeDuplicates().sink { [weak self] playing in
            self?.isPlaying = playing
            self?.reconcile()
        }.store(in: &subscriptions)
        controller.$presentation.map(\.availability).removeDuplicates().sink { [weak self] availability in
            guard let self else { return }
            if case .failed(.permissionDenied) = availability { permissionBlocked = true }
            // Output-device changes suspend capture with no other edge to
            // follow; re-check once shortly after (sleep/lock still win).
            if availability == .suspended {
                Task { @MainActor [weak self, resumeDelay] in
                    try? await Task.sleep(for: resumeDelay)
                    self?.reconcile()
                }
            }
        }.store(in: &subscriptions)
        #if DEBUG
        controller.$presentation.sink { [weak self] in self?.logFrame($0) }.store(in: &subscriptions)
        #endif
        guard observeSystemEvents else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, active) in [(NSWorkspace.willSleepNotification, false), (NSWorkspace.didWakeNotification, true),
                               (NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, true)] {
            workspace.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.setSessionActive(active) } }
                .store(in: &subscriptions)
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, active) in [("com.apple.screenIsLocked", false), ("com.apple.screenIsUnlocked", true)] {
            distributed.publisher(for: Notification.Name(name)).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.setSessionActive(active) } }
                .store(in: &subscriptions)
        }
    }

    // MARK: Explicit user actions

    /// The only path that may trigger the first macOS permission prompt: it
    /// starts capture now, in direct response to the user's choice.
    func userSetEnabled(_ enabled: Bool) {
        settings.liveAudioVisualizerEnabled = enabled
        desiredEnabled = enabled
        guard enabled else { controller.stop(); return }
        permissionBlocked = false
        if controller.presentation.availability != .capturing { controller.startFromUserAction() }
        // Without a visible, playing visualizer the explicit start only
        // settles permission; reconcile stops it again once it has settled.
        reconcileWhenSettled()
    }

    // MARK: Visibility leases

    func acquire(_ id: UUID) {
        releaseWork?.cancel(); releaseWork = nil
        guard leases.insert(id).inserted else { return }
        reconcile()
    }

    func release(_ id: UUID) {
        guard leases.remove(id) != nil else { return }
        guard leases.isEmpty else { return }
        releaseWork?.cancel()
        releaseWork = Task { @MainActor [weak self, releaseGrace] in
            try? await Task.sleep(for: releaseGrace)
            guard !Task.isCancelled else { return }
            self?.releaseWork = nil
            self?.reconcile()
        }
    }

    var activeLeaseCount: Int { leases.count }

    func setSessionActive(_ active: Bool) {
        guard sessionActive != active else { return }
        sessionActive = active
        reconcile()
    }

    /// Termination: no further automatic starts after the controller's shutdown.
    func prepareForShutdown() { shutDown = true; releaseWork?.cancel() }

    // MARK: Reconcile

    var isEligible: Bool {
        desiredEnabled && !leases.isEmpty && isPlaying && sessionActive && !permissionBlocked && !shutDown
    }

    func reconcile() {
        let availability = controller.presentation.availability
        let running = availability == .starting || availability == .capturing
        if isEligible, !running {
            controller.startFromUserAction()
        } else if !isEligible, running, releaseWork == nil {
            controller.stop()
        }
    }

    private func reconcileWhenSettled() {
        Task { @MainActor [weak self] in
            for _ in 0..<200 {
                guard let self, self.controller.presentation.availability == .starting else { break }
                try? await Task.sleep(for: .milliseconds(25))
            }
            self?.reconcile()
        }
    }

    #if DEBUG
    /// Rate-limited (1/s): sequence, signal and rounded bands only; never samples.
    private func logFrame(_ presentation: AudioSpectrumPresentation) {
        guard let frame = presentation.frame else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDiagnosticAt >= 1 else { return }
        lastDiagnosticAt = now
        let bands = (0..<8).map { String(format: "%.2f", frame.bands[$0]) }.joined(separator: " ")
        Self.log.debug("frame seq=\(frame.sequence) signal=\(frame.hasSignal) bands=[\(bands, privacy: .public)]")
    }
    #endif
}
