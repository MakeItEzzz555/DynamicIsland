import AppKit
import Combine
import os
import SwiftUI

private let lockScreenLog = Logger(subsystem: "com.local.dynamicisland", category: "LockScreen")

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
    /// An artwork click while locked; the source opens only after a confirmed unlock.
    @Published private(set) var sourceOpenPending = false
    private var sourceOpenRequestedAt: Date?
    static let sourceOpenTimeout: TimeInterval = 120

    let settings: AppSettings
    let media: MediaController
    let timer: TimerController
    let keepAwake: KeepAwakeController
    let systemHUD: SystemHUDController
    let mediaAdvanced: MediaAdvancedController?
    let monitor: LockStateMonitor
    private let makeSpace: () -> LockScreenSpaceProviding
    private let readBattery: () -> BatteryActivitySnapshot?
    private let playSound: @MainActor (String, Double) -> Void
    private let unlockDuration: Duration
    private let openMediaSource: @MainActor (MediaController) -> Bool
    private var surfaces: LockScreenSurfaceController?
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var transitionGeneration: UInt64 = 0
    private var wasLocked = false
    /// Sounds belong to real lock/unlock transitions, not to wake or screensaver.
    private var lastState = LockState.unknown

    init(settings: AppSettings, media: MediaController, timer: TimerController, keepAwake: KeepAwakeController,
         systemHUD: SystemHUDController, mediaAdvanced: MediaAdvancedController? = nil,
         monitor: LockStateMonitor = LockStateMonitor(),
         makeSpace: @escaping () -> LockScreenSpaceProviding = { SkyLightLockScreenSpace() },
         readBattery: @escaping () -> BatteryActivitySnapshot? = { BatteryActivityProvider().snapshot() },
         playSound: @escaping @MainActor (String, Double) -> Void = { LockScreenCoordinator.playSystemSound($0, volume: $1) },
         unlockDuration: Duration = .milliseconds(650),
         openMediaSource: @escaping @MainActor (MediaController) -> Bool = { $0.openActiveMediaSource() }) {
        self.settings = settings; self.media = media; self.timer = timer; self.keepAwake = keepAwake
        self.systemHUD = systemHUD; self.mediaAdvanced = mediaAdvanced; self.monitor = monitor; self.makeSpace = makeSpace
        self.readBattery = readBattery; self.playSound = playSound; self.unlockDuration = unlockDuration
        self.openMediaSource = openMediaSource
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

    /// Artwork click while locked: never opens anything over the secure screen;
    /// it remembers one request and fulfils it after a confirmed unlock.
    func requestSourceOpenAfterUnlock() {
        guard settings.openSourceOnArtworkClick, monitor.state.isConfirmedLocked, content.media != nil else { return }
        sourceOpenRequestedAt = Date()
        sourceOpenPending = true
    }

    private func cancelSourceOpen() { sourceOpenRequestedAt = nil; sourceOpenPending = false }

    /// Test hook: age the pending request to exercise the timeout.
    func ageSourceOpenRequest(by seconds: TimeInterval) { sourceOpenRequestedAt?.addTimeInterval(-seconds) }

    /// Real, supported controls only; pickers (queue, output) need the desktop.
    var mediaActions: LockScreenMediaActions {
        let caps = mediaAdvanced?.capabilities ?? MediaControlCapabilities()
        let source = media.sourceName
        func state(_ availability: MediaCapabilityAvailability, isOn: Bool = false) -> LockScreenControlState {
            .init(enabled: availability == .supported && mediaAdvanced != nil, isOn: isOn,
                  help: MediaControlCapabilities.reason(availability, source: source) ?? "")
        }
        return LockScreenMediaActions(
            previous: { [weak self] in self?.previousTrack() }, playPause: { [weak self] in self?.playPause() },
            next: { [weak self] in self?.nextTrack() }, seek: { [weak self] in self?.seek(to: $0) },
            timing: { [weak self] in
                guard let self, self.media.hasPlaybackProgress, self.media.duration > 0 else { return nil }
                return (self.media.playbackPosition, self.media.duration)
            },
            favorite: state(caps.favorite, isOn: mediaAdvanced?.isFavorite ?? false),
            toggleFavorite: { [weak self] in Task { await self?.mediaAdvanced?.toggleFavorite() } },
            mode: state(caps.playbackMode), modeSymbol: mediaAdvanced?.mode.symbol ?? "shuffle",
            cycleMode: { [weak self] in Task { await self?.mediaAdvanced?.cycleMode() } },
            volume: { [weak self] in self?.outputVolume }, setVolume: { [weak self] in self?.setVolume($0) },
            openSource: settings.openSourceOnArtworkClick ? { [weak self] in self?.requestSourceOpenAfterUnlock() } : nil,
            openPending: sourceOpenPending)
    }
    var artwork: NSImage? { content.media?.artworkRevision == nil ? nil : media.artworkImage }

    // MARK: Lifecycle

    private func setEnabled(_ enabled: Bool) {
        transitionGeneration &+= 1
        if enabled {
            guard surfaces == nil else { return }
            let space = makeSpace()
            availability = space.availability
            lockScreenLog.notice("enabled; space \(String(describing: space.availability), privacy: .public)")
            surfaces = LockScreenSurfaceController(space: space, frame: { [weak self] in self?.frame(for: $0) },
                                                   content: { [weak self] in self?.view(for: $0) ?? AnyView(EmptyView()) })
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.surfaces?.relayout() }
            }
            surfaces?.prepare(Set(LockScreenSurfaceKind.allCases))
            monitor.start()
        } else {
            monitor.stop()
            cancelSourceOpen()
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
        lockScreenLog.notice("state \(String(describing: previous), privacy: .public) -> \(String(describing: state), privacy: .public)")
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
            if state == .unlocked && previous.isConfirmedLocked, let requested = sourceOpenRequestedAt,
               Date().timeIntervalSince(requested) < Self.sourceOpenTimeout {
                _ = openMediaSource(media)
            }
            cancelSourceOpen()
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
        let before = surfaces.visible
        surfaces.update(state: effective, requested: requestedSurfaces())
        surfaces.relayout() // frames depend on content (row attaches to media)
        if surfaces.visible != before {
            lockScreenLog.notice("surfaces \(surfaces.visible.map(\.rawValue).sorted().joined(separator: ","), privacy: .public) space=\(String(describing: surfaces.availability), privacy: .public)")
        }
    }

    private func requestedSurfaces() -> Set<LockScreenSurfaceKind> {
        var kinds: Set<LockScreenSurfaceKind> = []
        if preferences.hud && hudPhase != .hidden { kinds.insert(.hud) }
        if content.media != nil { kinds.insert(.nowPlaying) }
        if content.alert != nil { kinds.insert(.alert) }
        if !radialItems.isEmpty { kinds.insert(.status) }
        if preferences.sideVolume || preferences.sideBrightness { kinds.insert(.sideHUD) }
        return kinds
    }

    /// Radial widgets for the current content, in the user's order.
    var radialItems: [LockScreenRadialItem] {
        LockScreenRadialItem.items(for: content, order: preferences.radialOrder)
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
            mediaSource: media.hasActiveMediaSource ? media.sourceName : nil,
            timerRemainingSeconds: timer.totalSeconds > 0 ? timer.remainingSeconds : nil,
            timerTotalSeconds: timer.totalSeconds, timerIsRunning: timer.isRunning,
            keepAwakeExpiresAt: keepAwake.expiresAt, keepAwakeTotalSeconds: keepAwake.configuredDuration,
            keepAwakeActive: keepAwake.isActive,
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

    var notchRect: CGRect? {
        guard let screen = lockScreen, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              left.maxX < right.minX else { return nil }
        return CGRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                      width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    var layout: LockScreenLayout? {
        guard let screen = lockScreen else { return nil }
        return LockScreenLayout.resolve(screen: screen.frame, notch: notchRect, preferences: preferences,
                                        hasMedia: content.media != nil, radialCount: radialItems.count,
                                        hasAlert: content.alert != nil)
    }

    func frame(for kind: LockScreenSurfaceKind) -> CGRect? {
        guard let layout else { return nil }
        // Prepared windows need a real frame before any content exists.
        let media = layout.media ?? CGRect(origin: .zero, size: preferences.mediaSize.cardSize)
        switch kind {
        case .hud: return layout.island
        case .nowPlaying: return layout.media ?? media
        case .status: return layout.secondary ?? CGRect(x: media.minX, y: media.minY, width: LockScreenLayout.secondaryWidth(count: 3),
                                                        height: LockScreenLayout.radialDiameter)
        case .alert: return layout.alert ?? CGRect(origin: .zero, size: LockScreenLayout.alertSize)
        case .sideHUD: return layout.side
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
