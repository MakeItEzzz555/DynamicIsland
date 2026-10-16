import AppKit
import SwiftUI

// MARK: - Live adapter

/// Maps the coordinator's privacy-projected state onto the data-driven views.
/// The Settings preview renders the same views with labeled sample data.
struct LockScreenSurfaceView: View {
    let kind: LockScreenSurfaceKind
    @ObservedObject var coordinator: LockScreenCoordinator

    var body: some View {
        Group {
            switch kind {
            case .hud:
                LockScreenIslandHUD(phase: coordinator.hudPhase, notchWidth: coordinator.notchRect?.width,
                                    showsActivity: coordinator.content.media?.isPlaying == true)
            case .nowPlaying:
                if let media = coordinator.content.media {
                    LockScreenNowPlayingCard(media: media, artwork: coordinator.artwork,
                                             size: coordinator.settings.lockScreenPreferences.mediaSize,
                                             actions: coordinator.mediaActions)
                }
            case .status:
                LockScreenRadialRow(items: coordinator.radialItems, onTimerToggle: coordinator.toggleTimer)
            case .alert:
                if let alert = coordinator.content.alert { LockScreenAlertCard(alert: alert) }
            case .sideHUD:
                LockScreenSideSliders(volume: coordinator.settings.lockScreenPreferences.sideVolume ? coordinator.outputVolume : nil,
                                      brightness: coordinator.settings.lockScreenPreferences.sideBrightness ? coordinator.displayBrightness : nil,
                                      showsVolume: coordinator.settings.lockScreenPreferences.sideVolume,
                                      showsBrightness: coordinator.settings.lockScreenPreferences.sideBrightness,
                                      setVolume: coordinator.setVolume, setBrightness: coordinator.setBrightness)
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Island

/// The island on the lock screen: the same notch-shell silhouette as the
/// desktop island, widened by two wings so content is not hidden behind the
/// camera housing. Unlock opens the lock and narrows back to the notch.
struct LockScreenIslandHUD: View {
    let phase: LockScreenHUDPhase
    /// Hardware notch width in points; nil on notchless displays (floating pill).
    let notchWidth: CGFloat?
    let showsActivity: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let unlocking = phase == .unlocking
        GeometryReader { proxy in
            let full = proxy.size.width
            let width = unlocking ? (notchWidth ?? full * 0.6) : full
            let wing = max((full - (notchWidth ?? 0)) / 2, 0)
            ZStack(alignment: .top) {
                Group {
                    if notchWidth != nil {
                        IslandShellShape(topCornerRadius: 6, bottomCornerRadius: 12).fill(.black)
                    } else {
                        Capsule(style: .continuous).fill(.black)
                    }
                }
                .frame(width: width, height: proxy.size.height)
                HStack(spacing: 0) {
                    Image(systemName: unlocking ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: notchWidth == nil ? full : wing)
                    if let notchWidth {
                        Spacer().frame(width: notchWidth)
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                            .symbolEffect(.variableColor.iterative, isActive: showsActivity && !reduceMotion)
                            .opacity(showsActivity && !unlocking ? 1 : 0)
                            .frame(width: wing)
                    }
                }
                .frame(height: proxy.size.height)
                .opacity(unlocking ? 0 : 1)
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: phase)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocking ? "Unlocked" : "Locked")
    }
}

// MARK: - Shared material

private struct LockScreenCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .foregroundStyle(.white)
    }
}

// MARK: - Now Playing

/// One control's lock-screen state: enabled only when the backend really
/// supports it; `help` explains a disabled control.
struct LockScreenControlState: Equatable {
    var enabled: Bool
    var isOn = false
    var help = ""
    static let unavailable = LockScreenControlState(enabled: false)
}

/// Everything the player can do while locked. Pickers (queue, output) are
/// deliberately absent: they need the unlocked desktop.
struct LockScreenMediaActions {
    var previous: () -> Void
    var playPause: () -> Void
    var next: () -> Void
    var seek: (Double) -> Void
    /// (position, duration) in seconds when the source reports real progress.
    var timing: () -> (Double, Double)?
    var favorite: LockScreenControlState
    var toggleFavorite: () -> Void
    var mode: LockScreenControlState
    var modeSymbol: String
    var cycleMode: () -> Void
    var volume: () -> Double?
    var setVolume: (Double) -> Void
    /// Artwork click; nil when "Open source on artwork click" is off.
    var openSource: (() -> Void)?
    var openPending: Bool

    /// Inert actions for the Settings preview: nothing runs, nothing opens.
    static var preview: LockScreenMediaActions {
        LockScreenMediaActions(
            previous: {}, playPause: {}, next: {}, seek: { _ in }, timing: { (64, 214) },
            favorite: .init(enabled: true, isOn: true), toggleFavorite: {},
            mode: .init(enabled: true), modeSymbol: "shuffle", cycleMode: {},
            volume: { 0.6 }, setVolume: { _ in }, openSource: nil, openPending: false)
    }
}

struct LockScreenNowPlayingCard: View {
    let media: LockScreenContent.Media
    let artwork: NSImage?
    let size: LockScreenMediaSize
    let actions: LockScreenMediaActions

    var body: some View {
        LockScreenCard(cornerRadius: size == .large ? 26 : 22) {
            switch size {
            case .standard: standard
            case .large: large
            }
        }
    }

    /// Clone of the desktop Standard player: artwork + text + visualizer,
    /// scrubber, then the seven-slot control row.
    private var standard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                artworkButton(side: 56, radius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    title(15); artist(13)
                    if let source = media.source { Text(source).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55)) }
                }
                Spacer(minLength: 4)
                visualizer
            }
            scrubber
            HStack(spacing: 0) {
                control("list.bullet", "Queue", .init(enabled: false, help: "Unlock to view the queue"), {})
                control(actions.favorite.isOn ? "heart.fill" : "heart", "Favorite", actions.favorite, actions.toggleFavorite)
                control("backward.fill", "Previous track", .init(enabled: media.canSkip), actions.previous)
                control(media.isPlaying ? "pause.fill" : "play.fill", media.isPlaying ? "Pause" : "Play", .init(enabled: true), actions.playPause, size: 22)
                control("forward.fill", "Next track", .init(enabled: media.canSkip), actions.next)
                control(actions.modeSymbol, "Shuffle and repeat", actions.mode, actions.cycleMode)
                control("airplayaudio", "Output", .init(enabled: false, help: "Unlock to change the output"), {})
            }
        }
    }

    /// Large: artwork-first, centered text, provider row, transport, scrubber, volume.
    private var large: some View {
        VStack(spacing: 8) {
            artworkButton(side: 150, radius: 18)
            VStack(spacing: 2) {
                title(17); artist(14)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                if let source = media.source { Text(source).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6)) }
                visualizer
            }
            HStack(spacing: 0) {
                control(actions.favorite.isOn ? "heart.fill" : "heart", "Favorite", actions.favorite, actions.toggleFavorite)
                control("backward.fill", "Previous track", .init(enabled: media.canSkip), actions.previous, size: 18)
                control(media.isPlaying ? "pause.fill" : "play.fill", media.isPlaying ? "Pause" : "Play", .init(enabled: true), actions.playPause, size: 26)
                control("forward.fill", "Next track", .init(enabled: media.canSkip), actions.next, size: 18)
                control("airplayaudio", "Output", .init(enabled: false, help: "Unlock to change the output"), {})
            }
            scrubber
            if let volume = actions.volume() {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    Slider(value: Binding(get: { actions.volume() ?? volume }, set: actions.setVolume)).controlSize(.mini).tint(.white)
                        .accessibilityLabel("Volume")
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func title(_ size: CGFloat) -> some View {
        Text(media.title).font(.system(size: size, weight: .semibold)).lineLimit(1)
    }

    @ViewBuilder private func artist(_ size: CGFloat) -> some View {
        if !media.artist.isEmpty { Text(media.artist).font(.system(size: size)).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
    }

    private var visualizer: some View {
        AudioVisualizerView(isPlaying: media.isPlaying, accentColor: .white, variant: .compact)
            .accessibilityHidden(true)
    }

    /// Elapsed - scrubber - remaining; seek only where the source supports it.
    private var scrubber: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let (position, duration) = actions.timing() {
                HStack(spacing: 8) {
                    Text(Self.clock(position)).frame(width: 34, alignment: .leading)
                    Slider(value: Binding(get: { duration > 0 ? position / duration : 0 }, set: actions.seek))
                        .controlSize(.mini).tint(.white).disabled(!media.canSeek)
                        .accessibilityLabel("Playback position")
                    Text("-" + Self.clock(max(duration - position, 0))).frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private func artworkButton(side: CGFloat, radius: CGFloat) -> some View {
        let image = Group {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: side * 0.36)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.08))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(alignment: .bottom) {
            if actions.openPending {
                Text("Opens after unlock").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule()).padding(4)
            }
        }
        return Group {
            if let open = actions.openSource {
                Button(action: open) { image }.buttonStyle(.plain)
                    .accessibilityLabel("Open the player after unlocking")
            } else {
                image.accessibilityHidden(true)
            }
        }
    }

    private func control(_ symbol: String, _ label: String, _ state: LockScreenControlState,
                         _ action: @escaping () -> Void, size: CGFloat = 15) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.enabled)
        .opacity(state.enabled ? 1 : 0.35)
        .help(state.help)
        .accessibilityLabel(label)
        .accessibilityHint(state.enabled ? "" : state.help)
    }

    static func clock(_ seconds: Double) -> String {
        Duration.seconds(max(seconds.isFinite ? seconds : 0, 0)).formatted(.time(pattern: .minuteSecond))
    }
}

// MARK: - Radial secondary widgets

/// One radial widget. `progress` is nil when the activity has no real
/// fraction (indefinite Keep Awake): the ring is then drawn plain, unfilled.
struct LockScreenRadialItem: Identifiable, Equatable {
    var id: LockScreenRadialKind { kind }
    let kind: LockScreenRadialKind
    let symbol: String
    let value: String
    let progress: Double?
    let tint: Color
    let accessibilityLabel: String

    static func items(for content: LockScreenContent, order: [LockScreenRadialKind]) -> [LockScreenRadialItem] {
        order.compactMap { kind in
            switch kind {
            case .battery:
                guard let battery = content.battery else { return nil }
                let tint: Color = battery.isCharging ? .green : battery.percent <= 10 ? .red : battery.percent <= 20 ? .orange : .white
                return .init(kind: kind, symbol: battery.isCharging ? "bolt.fill" : "battery.75", value: "\(battery.percent)",
                             progress: Double(battery.percent) / 100, tint: tint,
                             accessibilityLabel: "Battery \(battery.percent) percent\(battery.isCharging ? ", charging" : "")")
            case .timer:
                guard let timer = content.timer else { return nil }
                return .init(kind: kind, symbol: timer.isRunning ? "timer" : "pause.fill",
                             value: Duration.seconds(timer.remainingSeconds).formatted(.time(pattern: .minuteSecond)),
                             progress: timer.progress, tint: .orange,
                             accessibilityLabel: "Timer \(timer.remainingSeconds) seconds remaining\(timer.isRunning ? "" : ", paused")")
            case .keepAwake:
                guard let keepAwake = content.keepAwake else { return nil }
                let minutes = keepAwake.expiresAt.map { max(Int(($0.timeIntervalSinceNow / 60).rounded(.up)), 0) }
                return .init(kind: kind, symbol: "cup.and.saucer.fill", value: minutes.map { "\($0)m" } ?? "On",
                             progress: keepAwake.progress, tint: .cyan,
                             accessibilityLabel: minutes.map { "Keep Awake, \($0) minutes left" } ?? "Keep Awake on")
            }
        }
    }
}

struct LockScreenRadialGauge: View {
    let item: LockScreenRadialItem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 4)
            if let progress = item.progress {
                Circle()
                    .inset(by: 2)
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(item.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: progress)
            }
            VStack(spacing: 1) {
                Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold))
                Text(item.value).font(.system(size: 10, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(6)
        }
        .frame(width: LockScreenLayout.radialDiameter, height: LockScreenLayout.radialDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
    }
}

struct LockScreenRadialRow: View {
    let items: [LockScreenRadialItem]
    let onTimerToggle: () -> Void

    var body: some View {
        HStack(spacing: LockScreenLayout.radialSpacing) {
            ForEach(items) { item in
                if item.kind == .timer {
                    Button(action: onTimerToggle) { LockScreenRadialGauge(item: item) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Pauses or resumes the timer")
                } else {
                    LockScreenRadialGauge(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Alert and side controls

struct LockScreenAlertCard: View {
    let alert: LockScreenContent.Alert
    var body: some View {
        LockScreenCard(cornerRadius: 16) {
            Label(alert.label, systemImage: alert.symbolName).font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
    }
}

struct LockScreenSideSliders: View {
    let volume: Double?
    let brightness: Double?
    let showsVolume: Bool
    let showsBrightness: Bool
    let setVolume: (Double) -> Void
    let setBrightness: (Double) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if showsVolume { slider("speaker.wave.2.fill", "Volume", volume, setVolume) }
            if showsBrightness { slider("sun.max.fill", "Brightness", brightness, setBrightness) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Vertical capsule slider; drag sets 0...100%. Unavailable stays visibly inert.
    private func slider(_ symbol: String, _ label: String, _ value: Double?, _ set: @escaping (Double) -> Void) -> some View {
        GeometryReader { proxy in
            let level = value ?? 0
            ZStack(alignment: .bottom) {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(.white.opacity(0.9)).frame(height: proxy.size.height * level)
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(level > 0.15 ? .black : .white).padding(.bottom, 8)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard value != nil else { return }
                set(min(max(1 - Double(drag.location.y / proxy.size.height), 0), 1))
            })
            .opacity(value == nil ? 0.4 : 1)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(value.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Unavailable")
            .accessibilityAdjustableAction { direction in
                guard let value else { return }
                set(min(max(value + (direction == .increment ? 0.0625 : -0.0625), 0), 1))
            }
        }
        .frame(width: 44)
    }
}
