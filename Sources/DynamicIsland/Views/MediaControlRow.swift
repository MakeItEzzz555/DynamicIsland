import AppKit
import SwiftUI

/// Slots of the Now Playing control row (reference order).
enum MediaControlSlot: CaseIterable, Equatable {
    case queue, favorite, previous, playPause, next, mode, output

    static let standardOrder: [MediaControlSlot] = [.queue, .favorite, .previous, .playPause, .next, .mode, .output]
}

/// Control sizes per presentation: Play/Pause is the strongest element,
/// Previous/Next strong, secondary controls lighter.
struct MediaControlRowMetrics: Equatable {
    var secondary: CGFloat
    var transport: CGFloat
    var play: CGFloat

    static let standard = Self(secondary: 22, transport: 28, play: 36)
    static let large = Self(secondary: 26, transport: 32, play: 42)

    func size(of slot: MediaControlSlot) -> CGFloat {
        switch slot {
        case .playPause: play
        case .previous, .next: transport
        case .queue, .favorite, .mode, .output: secondary
        }
    }

    /// Space-between distribution across `width`; symmetric sizes keep
    /// Play/Pause exactly on the row's center.
    func centers(width: CGFloat, slots: [MediaControlSlot] = MediaControlSlot.standardOrder) -> [CGFloat] {
        let sizes = slots.map(size(of:))
        let spacing = slots.count > 1 ? max(0, (width - sizes.reduce(0, +)) / CGFloat(slots.count - 1)) : 0
        var x: CGFloat = 0
        return sizes.map { size in
            defer { x += size + spacing }
            return x + size / 2
        }
    }
}

/// Queue - Favorite - Previous - Play/Pause - Next - Mode - Output.
/// Every control acts on a real provider backend (MediaAdvancedController);
/// unavailable controls keep their slot, dimmed, with the reason as help.
struct MediaControlRow: View {
    @ObservedObject var media: MediaController
    let advanced: MediaAdvancedController?
    let metrics: MediaControlRowMetrics

    var body: some View {
        GeometryReader { proxy in
            let centers = metrics.centers(width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(Array(MediaControlSlot.standardOrder.enumerated()), id: \.offset) { index, slot in
                    control(slot)
                        .frame(width: metrics.size(of: slot), height: metrics.size(of: slot))
                        .position(x: centers[index], y: proxy.size.height / 2)
                }
            }
        }
        .task(id: media.title) { await advanced?.refresh() }
    }

    @ViewBuilder
    private func control(_ slot: MediaControlSlot) -> some View {
        switch slot {
        case .previous:
            MediaRowButton(symbol: "backward.fill", label: "Previous track", size: metrics.transport,
                           weight: .bold, enabled: media.isTransportControlAvailable, action: media.previousTrack)
        case .next:
            MediaRowButton(symbol: "forward.fill", label: "Next track", size: metrics.transport,
                           weight: .bold, enabled: media.isTransportControlAvailable, action: media.nextTrack)
        case .playPause:
            MediaRowButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", label: "Play or pause",
                           size: metrics.play, weight: .bold, enabled: media.isTransportControlAvailable,
                           emphasized: true, action: media.playPause)
        case .queue, .favorite, .mode, .output:
            if let advanced {
                MediaAdvancedSlot(slot: slot, advanced: advanced, size: metrics.secondary)
            } else {
                MediaRowButton(symbol: Self.placeholderSymbol(slot), label: Self.label(slot), size: metrics.secondary,
                               enabled: false, help: "Not available here") {}
            }
        }
    }

    static func placeholderSymbol(_ slot: MediaControlSlot) -> String {
        switch slot {
        case .queue: "list.bullet"
        case .favorite: "star"
        case .mode: "shuffle"
        case .output: "airplay.audio"
        default: "circle"
        }
    }

    static func label(_ slot: MediaControlSlot) -> String {
        switch slot {
        case .queue: "Up Next"
        case .favorite: "Favorite"
        case .mode: "Shuffle and repeat"
        case .output: "Audio output"
        case .previous: "Previous track"
        case .next: "Next track"
        case .playPause: "Play or pause"
        }
    }
}

private struct MediaAdvancedSlot: View {
    let slot: MediaControlSlot
    @ObservedObject var advanced: MediaAdvancedController
    let size: CGFloat
    @State private var showsQueue = false

    private var source: String { advanced.media.sourceName }

    var body: some View {
        switch slot {
        case .queue:
            MediaRowButton(symbol: "list.bullet", label: "Up Next", size: size,
                           enabled: advanced.capabilities.queue.isEnabled,
                           help: MediaControlCapabilities.reason(advanced.capabilities.queue, source: source)) {
                showsQueue.toggle()
            }
            .popover(isPresented: $showsQueue, arrowEdge: .bottom) {
                MediaQueueList(items: advanced.queue)
            }
        case .favorite:
            MediaRowButton(symbol: advanced.isFavorite ? "star.fill" : "star", label: "Favorite", size: size,
                           enabled: advanced.capabilities.favorite.isEnabled && !advanced.isBusy,
                           selected: advanced.isFavorite,
                           help: MediaControlCapabilities.reason(advanced.capabilities.favorite, source: source)) {
                Task { await advanced.toggleFavorite() }
            }
            .accessibilityValue(advanced.isFavorite ? "On" : "Off")
        case .mode:
            MediaRowButton(symbol: advanced.mode.symbol, label: "Shuffle and repeat", size: size,
                           enabled: advanced.capabilities.playbackMode.isEnabled && !advanced.isBusy,
                           selected: advanced.mode.isActive,
                           help: MediaControlCapabilities.reason(advanced.capabilities.playbackMode, source: source)) {
                Task { await advanced.cycleMode() }
            }
            .accessibilityValue(advanced.mode.accessibilityValue)
            .contextMenu {
                if advanced.capabilities.playbackMode.isEnabled {
                    Toggle("Shuffle", isOn: Binding(get: { advanced.mode.shuffle },
                                                    set: { value in Task { await advanced.setShuffle(value) } }))
                    Picker("Repeat", selection: Binding(get: { advanced.mode.repeatMode },
                                                        set: { value in Task { await advanced.setRepeat(value) } })) {
                        Text("Off").tag(MediaRepeatMode.off)
                        Text("All").tag(MediaRepeatMode.all)
                        if advanced.capabilities.supportsRepeatOne { Text("One").tag(MediaRepeatMode.one) }
                    }
                }
            }
        case .output:
            Menu {
                ForEach(advanced.outputDevices) { device in
                    Button {
                        advanced.selectOutput(device)
                    } label: {
                        if device.id == advanced.currentOutputID { Label(device.name, systemImage: "checkmark") }
                        else { Text(device.name) }
                    }
                }
            } label: {
                Image(systemName: "airplay.audio")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(.white.opacity(advanced.capabilities.output.isEnabled ? 0.82 : 0.32))
                    .frame(width: size, height: size)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!advanced.capabilities.output.isEnabled)
            .help("Audio output")
            .accessibilityLabel("Audio output")
            .onAppear { advanced.refreshOutputDevices() }
        default:
            EmptyView()
        }
    }
}

/// A Now Playing control with native feedback: hover tint, press scale on
/// Droppy's press/release springs, a fixed frame so symbol changes (play/
/// pause, star fill, shuffle/repeat) never shift the row.
struct MediaRowButton: View {
    let symbol: String
    let label: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    var enabled = true
    var emphasized = false
    var selected = false
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * (emphasized ? 0.62 : 0.56), weight: weight))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(MediaRowButtonStyle(selected: selected))
        .foregroundStyle(selected ? Color.accentColor : .white.opacity(enabled ? (emphasized ? 1 : 0.82) : 0.3))
        .disabled(!enabled)
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

private struct MediaRowButtonStyle: ButtonStyle {
    var selected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0)))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.9 : 1))
            .animation(reduceMotion ? nil : WorkspaceEditorMotion.hover(entering: configuration.isPressed, reduceMotion: false),
                       value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// Real Spotify queue (from the shared library controller); never invented.
private struct MediaQueueList: View {
    let items: [SpotifyMediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Up Next").font(.system(size: 11, weight: .semibold))
            if items.isEmpty {
                Text("The queue is empty").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(10)) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(item.subtitle).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
    }
}
