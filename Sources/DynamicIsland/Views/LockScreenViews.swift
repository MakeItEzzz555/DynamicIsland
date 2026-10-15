import AppKit
import SwiftUI

/// One view per lock-screen surface. Everything rendered comes from the
/// coordinator's privacy-projected `content`; actions are transport, timer and
/// output volume/brightness only.
struct LockScreenSurfaceView: View {
    let kind: LockScreenSurfaceKind
    @ObservedObject var coordinator: LockScreenCoordinator

    var body: some View {
        Group {
            switch kind {
            case .hud: LockScreenHUD(phase: coordinator.hudPhase)
            case .nowPlaying: if let media = coordinator.content.media { LockScreenNowPlayingCard(media: media, coordinator: coordinator) }
            case .timer: if let timer = coordinator.content.timer { LockScreenTimerCard(timer: timer, toggle: coordinator.toggleTimer) }
            case .alert: if let alert = coordinator.content.alert { LockScreenAlertCard(alert: alert) }
            case .status: LockScreenStatusRow(battery: coordinator.content.battery, keepAwake: coordinator.content.keepAwake)
            case .sideHUD: LockScreenSideSliders(coordinator: coordinator)
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shared card material: the system's own translucent material, one hairline.
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

/// Notch-anchored pill: a lock on lock; on unlock it opens and narrows back
/// toward the island's collapsed width before the window is released.
struct LockScreenHUD: View {
    let phase: LockScreenHUDPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let unlocking = phase == .unlocking
        HStack(spacing: 8) {
            Image(systemName: unlocking ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .foregroundStyle(.white)
        .frame(width: unlocking ? 200 : 300, height: 32)
        .background(.black, in: Capsule(style: .continuous))
        .scaleEffect(unlocking && !reduceMotion ? 0.92 : 1)
        .opacity(unlocking ? 0.85 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityLabel(unlocking ? "Unlocked" : "Locked")
    }
}

struct LockScreenNowPlayingCard: View {
    let media: LockScreenContent.Media
    @ObservedObject var coordinator: LockScreenCoordinator

    var body: some View {
        LockScreenCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Group {
                        if let artwork = coordinator.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                        } else {
                            Image(systemName: "music.note").font(.system(size: 22)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.white.opacity(0.08))
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if !media.artist.isEmpty {
                            Text(media.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if media.canSeek {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Slider(value: Binding(get: { coordinator.mediaProgress }, set: { coordinator.seek(to: $0) }))
                            .controlSize(.mini).tint(.white)
                            .accessibilityLabel("Playback position")
                    }
                }
                HStack(spacing: 34) {
                    Spacer()
                    button("backward.fill", "Previous track", enabled: media.canSkip, coordinator.previousTrack)
                    button(media.isPlaying ? "pause.fill" : "play.fill", media.isPlaying ? "Pause" : "Play", enabled: true,
                           coordinator.playPause, size: 22)
                    button("forward.fill", "Next track", enabled: media.canSkip, coordinator.nextTrack)
                    Spacer()
                }
            }
        }
    }

    private func button(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void, size: CGFloat = 16) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(width: 36, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

struct LockScreenTimerCard: View {
    let timer: LockScreenContent.Timer
    let toggle: () -> Void

    var body: some View {
        LockScreenCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.system(size: 16, weight: .semibold)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(Duration.seconds(timer.remainingSeconds).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    ProgressView(value: timer.progress).progressViewStyle(.linear).tint(.white)
                }
                Button(action: toggle) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill").frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(timer.isRunning ? "Pause timer" : "Resume timer")
            }
        }
    }
}

struct LockScreenAlertCard: View {
    let alert: LockScreenContent.Alert
    var body: some View {
        LockScreenCard(cornerRadius: 16) {
            Label(alert.label, systemImage: alert.symbolName).font(.system(size: 13, weight: .semibold))
        }
    }
}

struct LockScreenStatusRow: View {
    let battery: LockScreenContent.Battery?
    let keepAwake: LockScreenContent.KeepAwake?

    var body: some View {
        HStack(spacing: 10) {
            if let battery {
                chip(battery.isCharging ? "battery.100.bolt" : "battery.75", "\(battery.percent)%")
                    .accessibilityLabel("Battery \(battery.percent) percent\(battery.isCharging ? ", charging" : "")")
            }
            if let keepAwake {
                chip("cup.and.saucer.fill", keepAwake.expiresAt.map { "Awake until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Awake")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 10).frame(height: 26)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
    }
}

struct LockScreenSideSliders: View {
    @ObservedObject var coordinator: LockScreenCoordinator

    var body: some View {
        let prefs = coordinator.settings.lockScreenPreferences
        VStack(spacing: 10) {
            if prefs.sideVolume { slider("speaker.wave.2.fill", "Volume", coordinator.outputVolume, coordinator.setVolume) }
            if prefs.sideBrightness { slider("sun.max.fill", "Brightness", coordinator.displayBrightness, coordinator.setBrightness) }
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
