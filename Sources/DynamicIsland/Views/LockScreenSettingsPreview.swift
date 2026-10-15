import AppKit
import SwiftUI

/// Settings-only miniature lock screen. Uses the real `LockScreenLayout` and
/// the real surface views, so what you arrange here is what the lock screen
/// shows. Current media is shown when something is playing; inactive
/// activities use clearly labeled sample values. Never creates a private space.
struct LockScreenSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    let liveMedia: MediaController?
    let timer: TimerController?
    let keepAwake: KeepAwakeController?

    /// A 14" MacBook Pro screen in points, with its notch.
    static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let notch = CGRect(x: 756 - 92, y: 982 - 32, width: 184, height: 32)

    @State private var dragStartOffset: Double?
    @State private var reorderDrag: (kind: LockScreenRadialKind, dx: CGFloat)?

    private var preferences: LockScreenPreferences { settings.lockScreenPreferences }

    var body: some View {
        let sample = sampleContent()
        let items = LockScreenRadialItem.items(for: sample.content, order: preferences.radialOrder)
        let layout = LockScreenLayout.resolve(screen: Self.screen, notch: Self.notch, preferences: preferences,
                                              hasMedia: sample.content.media != nil, radialCount: items.count, hasAlert: false)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let scale = proxy.size.width / Self.screen.width
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(red: 0.42, green: 0.22, blue: 0.55), Color(red: 0.12, green: 0.14, blue: 0.36)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 0) {
                        Text("Thursday, 15 October").font(.system(size: 30 * scale, weight: .semibold))
                        Text("9:41").font(.system(size: 120 * scale, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: proxy.size.width)
                    .offset(y: 110 * scale)

                    place(layout.island, scale) {
                        LockScreenIslandHUD(phase: .locked, notchWidth: Self.notch.width,
                                            showsActivity: sample.content.media?.isPlaying == true)
                    }
                    if let media = sample.content.media, let rect = layout.media {
                        place(rect, scale) {
                            LockScreenNowPlayingCard(media: media, artwork: sample.artwork, progress: { 0.35 },
                                                     onPrevious: {}, onPlayPause: {}, onNext: {}, onSeek: { _ in })
                                .allowsHitTesting(false)
                        }
                        .gesture(mediaDrag(scale: scale))
                        .help("Drag to move Now Playing")
                    }
                    if let rect = layout.secondary {
                        place(rect, scale) {
                            HStack(spacing: LockScreenLayout.radialSpacing) {
                                ForEach(items) { item in
                                    LockScreenRadialGauge(item: item)
                                        .offset(x: reorderDrag?.kind == item.kind ? reorderDrag!.dx : 0)
                                        .gesture(reorder(item.kind, scale: scale))
                                        .help("Drag sideways to reorder")
                                }
                            }
                        }
                    }
                }
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .aspectRatio(Self.screen.width / Self.screen.height, contentMode: .fit)
            .frame(maxWidth: 520)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Lock Screen preview")

            Text(sample.caption).font(.caption).foregroundStyle(.secondary)
            Picker("Secondary widgets", selection: binding(\.secondaryPlacement)) {
                ForEach(LockScreenSecondaryPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            LabeledContent("Gap to media") {
                Slider(value: binding(\.secondaryGap), in: 0...60).frame(maxWidth: 220)
            }
            Button("Reset Positions") {
                var prefs = preferences
                prefs.mediaVerticalOffset = 0; prefs.secondaryGap = LockScreenPreferences.defaults.secondaryGap
                prefs.secondaryPlacement = .below; prefs.radialOrder = LockScreenRadialKind.allCases
                settings.lockScreenPreferences = prefs
            }
        }
    }

    private func place<Content: View>(_ rect: CGRect, _ scale: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: rect.width, height: rect.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: rect.width * scale, height: rect.height * scale, alignment: .topLeading)
            .offset(x: rect.minX * scale, y: (Self.screen.maxY - rect.maxY) * scale)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<LockScreenPreferences, T>) -> Binding<T> {
        Binding(get: { settings.lockScreenPreferences[keyPath: keyPath] },
                set: { var prefs = settings.lockScreenPreferences; prefs[keyPath: keyPath] = $0; settings.lockScreenPreferences = prefs })
    }

    /// Dragging down moves the whole media column down (larger offset).
    private func mediaDrag(scale: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { drag in
                let start = dragStartOffset ?? preferences.mediaVerticalOffset
                dragStartOffset = start
                var prefs = preferences
                prefs.mediaVerticalOffset = start + Double(drag.translation.height / scale)
                settings.lockScreenPreferences = prefs
            }
            .onEnded { _ in dragStartOffset = nil }
    }

    private func reorder(_ kind: LockScreenRadialKind, scale: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { reorderDrag = (kind, $0.translation.width / scale) }
            .onEnded { drag in
                reorderDrag = nil
                let step = Int((drag.translation.width / scale / (LockScreenLayout.radialDiameter + LockScreenLayout.radialSpacing)).rounded())
                var order = preferences.radialOrder
                guard step != 0, let index = order.firstIndex(of: kind) else { return }
                order.remove(at: index)
                order.insert(kind, at: min(max(index + step, 0), order.count))
                var prefs = preferences
                prefs.radialOrder = order
                settings.lockScreenPreferences = prefs
            }
    }

    /// Real values where an activity is live; labeled samples otherwise.
    private func sampleContent() -> (content: LockScreenContent, artwork: NSImage?, caption: String) {
        var content = LockScreenContent()
        var samples: [String] = []
        var artwork: NSImage?
        if preferences.nowPlaying {
            if let media = liveMedia, media.hasActiveMediaSource {
                let details = preferences.showTrackDetails
                content.media = .init(title: details ? media.title : "Now Playing", artist: details ? media.artist : "",
                                      artworkRevision: nil, isPlaying: media.isPlaying,
                                      canSkip: media.isTransportControlAvailable, canSeek: false)
                artwork = details ? media.artworkImage : nil
            } else {
                content.media = .init(title: "Sample Song", artist: "Sample Artist", artworkRevision: nil,
                                      isPlaying: true, canSkip: true, canSeek: false)
                samples.append("Now Playing")
            }
        }
        if preferences.battery {
            if let battery = BatteryActivityProvider().snapshot(), let percent = battery.percentage {
                content.battery = .init(percent: percent, isCharging: battery.isCharging)
            } else {
                content.battery = .init(percent: 76, isCharging: false); samples.append("Battery")
            }
        }
        if preferences.timer {
            if let timer, timer.totalSeconds > 0 {
                content.timer = .init(remainingSeconds: timer.remainingSeconds,
                                      progress: Double(timer.remainingSeconds) / Double(max(timer.totalSeconds, 1)), isRunning: timer.isRunning)
            } else {
                content.timer = .init(remainingSeconds: 754, progress: 0.62, isRunning: true); samples.append("Timer")
            }
        }
        if preferences.keepAwake {
            if let keepAwake, keepAwake.isActive {
                let progress = keepAwake.expiresAt.flatMap { expires in
                    keepAwake.configuredDuration.map { min(max(expires.timeIntervalSinceNow / $0, 0), 1) }
                }
                content.keepAwake = .init(expiresAt: keepAwake.expiresAt, progress: progress)
            } else {
                content.keepAwake = .init(expiresAt: Date().addingTimeInterval(45 * 60), progress: 0.75); samples.append("Keep Awake")
            }
        }
        let caption = samples.isEmpty
            ? "Preview shows your current activities. Drag Now Playing to move it; drag a ring sideways to reorder."
            : "Sample values shown for: \(samples.joined(separator: ", ")). Drag Now Playing to move it; drag a ring sideways to reorder."
        return (content, artwork, caption)
    }
}
