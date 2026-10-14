import SwiftUI
import SystemConfiguration

/// What a hovered collapsed activity reveals below the island. Built only
/// from existing state (media controller, live activity, agent session);
/// nothing is synthesized. Pure, so every case is testable.
enum CollapsedActivityPreview: Equatable {
    case media(title: String, artist: String, elapsed: String?, remaining: String?)
    case battery(device: String, percentage: Int?, state: BatteryLiveActivityState)
    case timer(title: String, detail: String?)
    case agent(name: String, provider: AgentProvider, status: String, activity: String?)

    /// Height added below the collapsed shell; sized to readable content.
    var height: CGFloat {
        switch self {
        case .media: 70
        case .agent: 58
        case .battery, .timer: 48
        }
    }

    struct MediaState: Equatable {
        var title: String
        var artist: String
        var position: Double
        var duration: Double
        var hasProgress: Bool
    }

    static func make(
        kind: DynamicIslandLiveActivityKind?,
        activity: DynamicIslandLiveActivity?,
        media: MediaState?,
        agent: AgentSession?,
        deviceName: String,
        now: Date = Date()
    ) -> Self? {
        switch kind {
        case .media:
            guard let media, !media.title.isEmpty else { return nil }
            let timed = media.hasProgress && MediaPlaybackTime.validDuration(media.duration) != nil
            return .media(
                title: media.title,
                artist: media.artist,
                elapsed: timed ? LiveActivityTimeFormatting.remainingTime(Int(max(0, media.position).rounded(.down))) : nil,
                remaining: timed ? MediaAdvancedController.remainingLabel(position: media.position, duration: media.duration) : nil
            )
        case .battery:
            guard let activity, let state = activity.batteryState else { return nil }
            return .battery(device: deviceName, percentage: activity.progress.map { Int(($0 * 100).rounded()) }, state: state)
        case .timer:
            guard let activity else { return nil }
            return .timer(title: activity.title, detail: activity.subtitle)
        case .agent:
            guard let agent else { return nil }
            return .agent(
                name: agent.project.displayName ?? agent.id.sessionID.provider.stableName.capitalized,
                provider: agent.id.sessionID.provider,
                status: AgentSessionPresentation.displayedStateLabel(for: agent, at: now),
                activity: safeActivity(of: agent)
            )
        default:
            return nil
        }
    }

    /// The running command's executable name or the running tool's name,
    /// projected through `AgentPrivacyProjection` (no arguments or paths).
    static func safeActivity(of session: AgentSession) -> String? {
        if let command = session.commands.values
            .filter({ $0.status == .active })
            .max(by: { $0.startedAt < $1.startedAt }) {
            return AgentPrivacyProjection.commandSummary(executable: command.displaySummary)
        }
        if let tool = session.tools.values
            .filter({ $0.status == .active })
            .max(by: { $0.startedAt < $1.startedAt }) {
            return AgentPrivacyProjection.toolName(tool.name)
        }
        return nil
    }
}

/// Readable preview row(s) shown under the collapsed shell on hover.
struct CollapsedActivityPreviewView: View {
    let preview: CollapsedActivityPreview
    let reduceMotion: Bool

    var body: some View {
        Group {
            switch preview {
            case let .media(title, artist, elapsed, remaining):
                VStack(spacing: 3) {
                    MarqueeText(text: title, font: .system(size: 13, weight: .semibold), reduceMotion: reduceMotion)
                        .foregroundStyle(.white.opacity(0.95))
                    MarqueeText(text: artist, font: .system(size: 11.5, weight: .medium), reduceMotion: reduceMotion)
                        .foregroundStyle(.white.opacity(0.62))
                    if let elapsed, let remaining {
                        Text("\(elapsed)  ·  \(remaining)")
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(artist)" + (elapsed.map { ", \($0) elapsed" } ?? ""))
            case let .battery(device, percentage, state):
                HStack(spacing: 8) {
                    Image(systemName: state == .low ? "battery.25percent" : "battery.100percent.bolt")
                        .foregroundStyle(state == .low ? .red : .green)
                    Text(device).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(batteryText(percentage: percentage, state: state))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityElement(children: .combine)
            case let .timer(title, detail):
                HStack(spacing: 8) {
                    Image(systemName: "timer").foregroundStyle(.orange)
                    Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    if let detail {
                        Text(detail).font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityElement(children: .combine)
            case let .agent(name, provider, status, activity):
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: AgentVisualStyle.providerSymbol(provider))
                            .foregroundStyle(AgentVisualStyle.providerAccent(provider))
                        Text(name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(status).font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                    if let activity {
                        Text(activity)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func batteryText(percentage: Int?, state: BatteryLiveActivityState) -> String {
        let value = percentage.map { "\($0)%" } ?? ""
        switch state {
        case .charging: return "\(value) · Charging"
        case .pluggedIn: return "\(value) · Plugged in"
        case .full: return "Charged"
        case .low: return "\(value) · Low"
        }
    }
}

/// Gentle continuous marquee for text that overflows; static when it fits
/// or under Reduce Motion (then truncated in the middle with a tooltip).
struct MarqueeText: View {
    let text: String
    let font: Font
    let reduceMotion: Bool
    /// Points per second; slow enough to read.
    var speed: Double = 24

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private let gap: CGFloat = 36
    private var overflows: Bool { textWidth > containerWidth + 0.5 && containerWidth > 0 }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if overflows && !reduceMotion {
                    TimelineView(.animation) { timeline in
                        let cycle = Double(textWidth + gap) / speed
                        let pause = 1.6
                        let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle + pause)
                        let offset = t < pause ? 0 : -CGFloat((t - pause) / cycle) * (textWidth + gap)
                        HStack(spacing: gap) { label; label }
                            .fixedSize()
                            .offset(x: offset)
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                    .mask(LinearGradient(stops: [
                        .init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96), .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                } else {
                    Text(text).font(font).lineLimit(1).truncationMode(.middle)
                        .frame(width: proxy.size.width, alignment: .center)
                }
            }
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in containerWidth = width }
        }
        .frame(height: 17)
        .background(label.fixedSize().hidden().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 })
        .clipped()
        .help(text)
        .accessibilityLabel(text)
    }

    private var label: some View { Text(text).font(font).lineLimit(1) }
}

/// The Mac's user-visible name, read once from the local configuration store
/// (never a network lookup, unlike `Host.current()`).
@MainActor
enum CollapsedActivityPreviewDevice {
    static let name: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "This Mac"
}

/// Hovering the collapsed visualizer dims the bars and reveals Pause/Play.
/// The glyph always reflects the controller's *observed* playback state, so a
/// command that fails never shows a false Play/Pause.
struct CollapsedVisualizerPlaybackControl<Bars: View>: View {
    @ObservedObject var media: MediaController
    let reduceMotion: Bool
    var onHover: ((Bool) -> Void)?
    @ViewBuilder let bars: () -> Bars

    @State private var isHovering = false

    private var canControl: Bool { media.isTransportControlAvailable }

    /// The control names the action it performs on the *observed* state.
    nonisolated static func glyph(isPlaying: Bool) -> String { isPlaying ? "pause.fill" : "play.fill" }

    var body: some View {
        ZStack {
            bars()
                .blur(radius: isHovering && canControl && !reduceMotion ? 2.5 : 0)
                .opacity(isHovering && canControl ? 0.3 : 1)
            if isHovering && canControl {
                Button { media.playPause() } label: {
                    Image(systemName: Self.glyph(isPlaying: media.isPlaying))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .help(media.isPlaying ? "Pause" : "Play")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.16)) { isHovering = hovering }
            onHover?(hovering)
        }
        .onDisappear { if isHovering { isHovering = false; onHover?(false) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(media.isPlaying ? "Playing" : "Paused")
        .accessibilityAction(named: media.isPlaying ? "Pause" : "Play") {
            if canControl { media.playPause() }
        }
    }
}
