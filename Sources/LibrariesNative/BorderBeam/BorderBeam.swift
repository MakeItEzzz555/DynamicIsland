// Adapted from Libraries.dev BorderBeamKit, MIT © 2026 Jakub Antalik.
// Upstream revision d06640864eb4adc2fe240f899a44ee6210779782.
import SwiftUI
import AppKit

/// The official Libraries.dev layer model, rendered by native Metal on macOS.
/// The clock belongs to this decoration; it does not publish to agent state.
public struct BorderBeam<Content: View>: View {
    private let size: BeamSize
    private let variant: BeamColorVariant
    private let theme: BeamTheme
    private let strength: Double
    private let active: Bool
    private let paused: Bool
    private let externallyVisible: Bool
    private let radius: Double?
    private let duration: Double?
    private let frozenTime: Double?
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowVisible = false
    @StateObject private var playback = BeamPlayback()

    public init(
        size: BeamSize = .md,
        colorVariant: BeamColorVariant = .colorful,
        strength: Double = 0.7,
        active: Bool = true,
        theme: BeamTheme = .auto,
        borderRadius: Double? = nil,
        duration: Double? = nil,
        paused: Bool = false,
        visible: Bool = true,
        frozenTime: Double? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.size = size
        self.variant = colorVariant
        self.theme = theme
        self.strength = BeamRenderPolicy.normalizedStrength(strength)
        self.active = active
        self.paused = paused
        self.externallyVisible = visible
        self.radius = borderRadius.map { $0.isFinite ? max(0, $0) : 16 }
        self.duration = duration.map { $0.isFinite ? min(120, max(0.1, $0)) : 8 }
        self.frozenTime = frozenTime.map { $0.isFinite ? max(0, $0) : 0 }
        self.content = content()
    }

    public var body: some View {
        let stopped = !BeamRenderPolicy.animates(
            active: active, paused: paused, visible: externallyVisible && windowVisible,
            reduceMotion: reduceMotion, frozen: frozenTime != nil
        )
        content
            .background {
                if size == .pulseOutside { decoration(stopped: stopped, part: .glow) }
            }
            .overlay { decoration(stopped: stopped, part: size == .pulseOutside ? .stroke : .all) }
            .background {
                if frozenTime == nil {
                    BeamVisibilityProbe { windowVisible = $0; if !$0 { playback.suspend() } }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: stopped) { _, _ in playback.suspend() }
            .onDisappear { playback.suspend() }
    }

    private var resolvedTheme: String {
        theme == .auto ? (colorScheme == .dark ? "dark" : "light") : theme.rawValue
    }

    private func decoration(stopped: Bool, part: PulseBeamPart) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: stopped)) { tick in
            let time = frozenTime ?? (reduceMotion ? 1.6 : playback.sample(tick.date.timeIntervalSinceReferenceDate, paused: stopped))
            layers(at: time, part: part)
        }
        .opacity(active ? 1 : 0)
        // These are upstream effect fades, not shell motion tokens. The
        // transitions-polish usage rule keeps 0.6/0.5s rather than forcing a
        // panel transition duration onto the glow. Reduce Motion is direct.
        .animation(reduceMotion ? nil : .timingCurve(0.25, 0.1, 0.25, 1, duration: active ? 0.6 : 0.5), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func layers(at time: Double, part: PulseBeamPart) -> some View {
        switch size {
        case .md, .sm:
            RotateBeamLayers(config: RotateBeamConfig(
                size: size, variant: variant, theme: resolvedTheme,
                staticColors: variant == .mono,
                duration: duration ?? BeamSpec.shared.defaults.duration.rotate,
                borderRadius: radius, brightness: nil, saturation: nil,
                hueRange: BeamSpec.shared.defaults.hueRange, strength: strength
            ), renderTime: time, renderOpacity: 1)
        case .line:
            LineBeamLayers(config: LineBeamConfig(
                variant: variant, theme: resolvedTheme, staticColors: variant == .mono,
                duration: duration ?? BeamSpec.shared.defaults.duration.line,
                borderRadius: radius, brightness: nil, saturation: nil,
                hueRange: BeamSpec.shared.defaults.lineHueRangeCap, strength: strength
            ), renderTime: time, renderOpacity: 1)
        case .pulseInner, .pulseOutside:
            PulseBeamLayers(config: PulseBeamConfig(
                size: size, variant: variant, theme: resolvedTheme,
                staticColors: variant == .mono,
                duration: duration ?? BeamSpec.shared.defaults.duration.pulse,
                borderRadius: radius, brightness: nil, saturation: nil,
                strength: strength, reduceMotion: reduceMotion, tuning: .none
            ), renderTime: time, renderOpacity: 1, part: part)
        }
    }
}

public enum BeamRenderPolicy {
    public static func normalizedStrength(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.7
    }
    public static func animates(active: Bool, paused: Bool, visible: Bool, reduceMotion: Bool, frozen: Bool = false) -> Bool {
        active && !paused && visible && !reduceMotion && !frozen
    }
}

private final class BeamPlayback: ObservableObject {
    private static let origin = Date.now.timeIntervalSinceReferenceDate
    private var clock = BeamAnimationClock(time: Date.now.timeIntervalSinceReferenceDate - origin + 1.6)
    func sample(_ timestamp: Double, paused: Bool) -> Double {
        clock.sample(timestamp, paused: paused)
    }
    func suspend() { clock.suspend() }
}

/// Sampled, bounded clock; no timers, notifications, tasks or wall-clock
/// accumulation while paused. Shared timestamps do not advance it twice.
struct BeamAnimationClock {
    private(set) var time: Double
    private var last: Double?
    init(time: Double = 1.6) { self.time = time }
    mutating func sample(_ timestamp: Double, paused: Bool) -> Double {
        if paused { suspend(); return time }
        if let last, timestamp > last, timestamp - last < 0.12 { time += timestamp - last }
        last = timestamp
        return time
    }
    mutating func suspend() { last = nil }
}

private struct BeamVisibilityProbe: NSViewRepresentable {
    var changed: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.evaluate() }
    final class Probe: NSView {
        var changed: (Bool) -> Void
        private var last: Bool?
        private var observations: [NSObjectProtocol] = []
        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
            for name in [NSWindow.didChangeOcclusionStateNotification, NSView.boundsDidChangeNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.evaluate() })
            }
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); evaluate() }
        override func layout() { super.layout(); evaluate() }
        func evaluate() {
            let visible = !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty && window?.occlusionState.contains(.visible) == true
            guard visible != last else { return }
            last = visible
            // AppKit can lay out during SwiftUI reconciliation. Publish one
            // weak, finite handoff rather than modifying view state in layout.
            DispatchQueue.main.async { [weak self] in self?.changed(visible) }
        }
        deinit { observations.forEach(NotificationCenter.default.removeObserver) }
    }
}
