import AppKit
import Combine
import SwiftUI

/// HUD lifecycle: appears on a confirmed lock, plays the unlock morph, then hides.
enum LockScreenHUDPhase: Equatable, Sendable { case hidden, locked, unlocking }

/// Owns the experimental lock-screen feature: lock state, the privacy-projected
/// content, sounds and the surface windows. Off unless the user enabled it.
@MainActor
final class LockScreenCoordinator: ObservableObject {
    @Published private(set) var content = LockScreenContent.empty
    @Published private(set) var hudPhase = LockScreenHUDPhase.hidden
    @Published private(set) var availability = LockScreenSpaceAvailability.unavailable(reason: "Off")
    @Published private(set) var outputVolume: Double?
    @Published private(set) var displayBrightness: Double?

    let settings: AppSettings
    let media: MediaController
    let timer: TimerController
    let keepAwake: KeepAwakeController
    let systemHUD: SystemHUDController
    let monitor: LockStateMonitor
    private let makeSpace: () -> LockScreenSpaceProviding
    private let readBattery: () -> BatteryActivitySnapshot?
    private let playSound: @MainActor (String, Double) -> Void
    private let unlockDuration: Duration
    private var surfaces: LockScreenSurfaceController?
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var transitionGeneration: UInt64 = 0
    private var wasLocked = false
    /// Sounds belong to real lock/unlock transitions, not to wake or screensaver.
    private var lastState = LockState.unknown

    init(settings: AppSettings, media: MediaController, timer: TimerController, keepAwake: KeepAwakeController,
         systemHUD: SystemHUDController, monitor: LockStateMonitor = LockStateMonitor(),
         makeSpace: @escaping () -> LockScreenSpaceProviding = { SkyLightLockScreenSpace() },
         readBattery: @escaping () -> BatteryActivitySnapshot? = { BatteryActivityProvider().snapshot() },
         playSound: @escaping @MainActor (String, Double) -> Void = { LockScreenCoordinator.playSystemSound($0, volume: $1) },
         unlockDuration: Duration = .milliseconds(650)) {
        self.settings = settings; self.media = media; self.timer = timer; self.keepAwake = keepAwake
        self.systemHUD = systemHUD; self.monitor = monitor; self.makeSpace = makeSpace
        self.readBattery = readBattery; self.playSound = playSound; self.unlockDuration = unlockDuration
    }

    private var preferences: LockScreenPreferences { settings.lockScreenPreferences }
    var visibleSurfaces: Set<LockScreenSurfaceKind> { surfaces?.visible ?? [] }

    func start() {
        settings.$lockScreenPreferences.map(\.enabled).removeDuplicates()
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
            .store(in: &cancellables)
        settings.$lockScreenPreferences.dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }
            .store(in: &cancellables)
        monitor.$state.removeDuplicates()
            .sink { [weak self] state in Task { @MainActor in self?.handle(state) } }
            .store(in: &cancellables)
        Publishers.MergeMany(media.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                             timer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                             keepAwake.objectWillChange.map { _ in () }.eraseToAnyPublisher())
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
    }

    /// Quit: hide and release every lock-screen window and the private space.
    func terminate() {
        cancellables.removeAll()
        setEnabled(false)
    }

    // MARK: Actions (allowlisted, non-privileged)

    func playPause() { media.playPause() }
    func nextTrack() { media.nextTrack() }
    func previousTrack() { media.previousTrack() }
    func seek(to fraction: Double) {
        guard media.isSeekControlAvailable, media.duration > 0 else { return }
        media.seek(to: min(max(fraction, 0), 1) * media.duration)
    }
    func toggleTimer() { timer.isRunning ? timer.pause() : timer.resume() }
    func setVolume(_ value: Double) { outputVolume = systemHUD.setOutputVolume(value)?.value ?? outputVolume }
    func setBrightness(_ value: Double) { displayBrightness = systemHUD.setDisplayBrightness(value)?.value ?? displayBrightness }
    var mediaProgress: Double { media.duration > 0 ? min(max(media.playbackPosition / media.duration, 0), 1) : 0 }
    var artwork: NSImage? { content.media?.artworkRevision == nil ? nil : media.artworkImage }

    // MARK: Lifecycle

    private func setEnabled(_ enabled: Bool) {
        transitionGeneration &+= 1
        if enabled {
            guard surfaces == nil else { return }
            let space = makeSpace()
            availability = space.availability
            surfaces = LockScreenSurfaceController(space: space, frame: { [weak self] in self?.frame(for: $0) },
                                                   content: { [weak self] in self?.view(for: $0) ?? AnyView(EmptyView()) })
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.surfaces?.relayout() }
            }
            monitor.start()
        } else {
            monitor.stop()
            surfaces?.stop()
            surfaces = nil
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            stopRefreshTimer()
            hudPhase = .hidden
            content = .empty
            wasLocked = false
            availability = .unavailable(reason: "Off")
        }
    }

    private func handle(_ state: LockState) {
        guard surfaces != nil else { return }
        let previous = lastState
        lastState = state
        let locked = state.isConfirmedLocked
        if locked && !wasLocked {
            transitionGeneration &+= 1
            wasLocked = true
            hudPhase = .locked
            outputVolume = SystemHUDController.readSystemVolume()?.value
            displayBrightness = SystemHUDController.readDisplayBrightness()
            // A real lock (also the first one after launch), never a wake or screensaver end.
            if preferences.hud && (previous == .unlocked || previous == .unknown) {
                playSound(preferences.lockSound, preferences.soundVolume)
            }
            startRefreshTimer()
            refresh()
        } else if !locked && wasLocked {
            wasLocked = false
            stopRefreshTimer()
            if state == .unlocked && previous.isConfirmedLocked && preferences.hud {
                playSound(preferences.unlockSound, preferences.soundVolume)
                beginUnlockMorph()
            } else {
                // Uncertain ownership (sleep, user switch, unknown): hide at once.
                transitionGeneration &+= 1
                hudPhase = .hidden
                content = .empty
                surfaces?.update(state: state, requested: [])
            }
        } else {
            refresh()
        }
    }

    /// Widgets leave immediately; only the click-through HUD morphs, then hides.
    private func beginUnlockMorph() {
        transitionGeneration &+= 1
        let token = transitionGeneration
        content = .empty
        hudPhase = .unlocking
        surfaces?.update(state: .locked, requested: [.hud])
        Task { [weak self, unlockDuration] in
            try? await Task.sleep(for: unlockDuration)
            guard let self, self.transitionGeneration == token else { return }
            self.hudPhase = .hidden
            self.surfaces?.update(state: self.monitor.state, requested: [])
        }
    }

    private func refresh() {
        guard let surfaces, hudPhase != .unlocking else { return }
        let state = monitor.state
        let showOnScreensaver = preferences.keepVisibleDuringScreensaver
        let effective: LockState = state == .screensaver(locked: true) && !showOnScreensaver ? .unknown : state
        content = LockScreenPrivacyProjector.project(sources(), disclosure: preferences.disclosure, state: effective)
        surfaces.update(state: effective, requested: requestedSurfaces())
    }

    private func requestedSurfaces() -> Set<LockScreenSurfaceKind> {
        var kinds: Set<LockScreenSurfaceKind> = []
        if preferences.hud && hudPhase != .hidden { kinds.insert(.hud) }
        if content.media != nil { kinds.insert(.nowPlaying) }
        if content.timer != nil { kinds.insert(.timer) }
        if content.alert != nil { kinds.insert(.alert) }
        if content.battery != nil || content.keepAwake != nil { kinds.insert(.status) }
        if preferences.sideVolume || preferences.sideBrightness { kinds.insert(.sideHUD) }
        return kinds
    }

    private func sources() -> LockScreenSources {
        let battery = readBattery()
        let lowBattery = battery.map { ($0.percentage ?? 100) <= 10 && !$0.isCharging } ?? false
        let keepAwakeEnding = keepAwake.expiresAt.map { $0.timeIntervalSinceNow < 60 && $0.timeIntervalSinceNow > 0 } ?? false
        return LockScreenSources(
            mediaTitle: media.hasActiveMediaSource ? media.title : nil, mediaArtist: media.artist,
            mediaArtworkRevision: media.artworkImage == nil ? nil : media.artworkImageRevision,
            mediaIsPlaying: media.isPlaying, mediaCanSkip: media.isTransportControlAvailable,
            mediaCanSeek: media.isSeekControlAvailable && media.hasPlaybackProgress,
            timerRemainingSeconds: timer.totalSeconds > 0 ? timer.remainingSeconds : nil,
            timerTotalSeconds: timer.totalSeconds, timerIsRunning: timer.isRunning,
            keepAwakeExpiresAt: keepAwake.expiresAt, keepAwakeActive: keepAwake.isActive,
            batteryPercent: battery?.percentage, batteryCharging: battery?.isCharging ?? false,
            alertCategory: lowBattery ? .lowBattery : keepAwakeEnding ? .keepAwakeEnding : nil)
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() { refreshTimer?.invalidate(); refreshTimer = nil }

    // MARK: Geometry and views

    /// The display the lock screen is on: the built-in notched panel when present.
    private var lockScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    func frame(for kind: LockScreenSurfaceKind) -> CGRect? {
        guard let screen = lockScreen else { return nil }
        let full = screen.frame
        let notch = max(screen.safeAreaInsets.top, 32)
        let columnTop = full.maxY - 280 - CGFloat(preferences.mediaVerticalOffset)
        let width: CGFloat = 380
        let x = full.midX - width / 2
        switch kind {
        case .hud: return CGRect(x: full.midX - 160, y: full.maxY - notch - 8, width: 320, height: notch + 8)
        case .status: return CGRect(x: full.midX - 160, y: full.maxY - 228, width: 320, height: 34)
        case .nowPlaying: return CGRect(x: x, y: columnTop - 150, width: width, height: 150)
        case .timer: return CGRect(x: x, y: columnTop - 150 - 12 - 64, width: width, height: 64)
        case .alert: return CGRect(x: x, y: columnTop - 150 - 12 - 64 - 12 - 44, width: width, height: 44)
        case .sideHUD: return CGRect(x: full.minX + 20, y: full.midY - 110, width: 52, height: 220)
        }
    }

    private func view(for kind: LockScreenSurfaceKind) -> AnyView {
        AnyView(LockScreenSurfaceView(kind: kind, coordinator: self))
    }

    /// Retained while it plays; NSSound may stop if released.
    private static var playing: NSSound?

    static func playSystemSound(_ name: String, volume: Double) {
        guard name != "None", SettingsLockSoundModel.availableNames.contains(name) else { return }
        guard let sound = NSSound(contentsOf: SettingsLockSoundModel.soundURL(name == "Default" ? "Glass" : name),
                                  byReference: true) else { return }
        sound.volume = Float(min(max(volume, 0), 1))
        playing?.stop()
        playing = sound
        sound.play()
    }
}
