import SwiftUI
import Foundation
import AppKit

enum AgentPresenceIndicatorStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case orb
    case avatar
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .automatic: "Auto"
        case .orb: "Thinking Orb"
        case .avatar: "Bot Avatar"
        }
    }
}

enum AgentOrbVisualState: String, CaseIterable, Codable, Identifiable, Sendable {
    case working, searching, solving, listening, connecting, weaving, composing, breathing, shaping
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BotAvatarType: String, CaseIterable, Codable, Identifiable, Sendable {
    case clover, flower, triangle, square, blob, ghost, circle, drop, star
    case droid, mech, alien, hexagon, cat, cloud, pill, pebble, puddle
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BotAvatarFace: String, CaseIterable, Codable, Identifiable, Sendable {
    case eyes, mouth
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BotAvatarShading: String, CaseIterable, Codable, Identifiable, Sendable {
    case fabric, plastic, crisp, smooth, flat
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BotAvatarHat: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, beret, beanie, party, crown
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BotAvatarGlasses: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, round, square, shades
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum VoiceBeamColorVariant: String, CaseIterable, Codable, Identifiable, Sendable {
    case colorful, mono, ocean, sunset, forest, candy, ice, gold
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum MetalSendPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case chromatic, silver, gold
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct BotAvatarConfiguration: Codable, Equatable, Sendable {
    var enabled = true
    var type: BotAvatarType = .clover
    var face: BotAvatarFace = .eyes
    var shading: BotAvatarShading = .fabric
    var size = 26.0
    var speed = 1.0
    var brightness = 1.0
    var saturation = 1.5
    var interactive = true
    var turn = 1.0
    var hat: BotAvatarHat = .none
    var glasses: BotAvatarGlasses = .none
    var headphones = false
    var bowTie = false
    var accessoryColorHex = "#222222"
    var whirl = 0.0
    var motionStrength = 1.0
    // Optional additions preserve the checkpoint's persisted JSON.
    var automaticShape: Bool? = nil
    var advanced: BotAvatarAdvancedConfiguration? = nil

    var details: BotAvatarAdvancedConfiguration {
        get { advanced ?? BotAvatarAdvancedConfiguration() }
        set { advanced = newValue }
    }

    func normalized() -> Self {
        var copy = self
        copy.size = copy.size.clamped(to: 18...72, fallback: 26)
        copy.speed = copy.speed.clamped(to: 0.25...2, fallback: 1)
        copy.brightness = copy.brightness.clamped(to: 0.5...1.5, fallback: 1)
        copy.saturation = copy.saturation.clamped(to: 0.5...2.5, fallback: 1.5)
        copy.turn = copy.turn.clamped(to: 0...2, fallback: 1)
        copy.whirl = copy.whirl.clamped(to: 0...2, fallback: 0)
        copy.motionStrength = copy.motionStrength.clamped(to: 0...2, fallback: 1)
        copy.advanced = copy.advanced?.normalized()
        if Color.agentHexComponents(copy.accessoryColorHex) == nil { copy.accessoryColorHex = "#222222" }
        return copy
    }
}

struct BotAvatarAdvancedConfiguration: Codable, Equatable, Sendable {
    var shadow = 0.28
    var highlight = 0.48
    var lightAngle = 225.0
    var rimLight = 0.26
    var spread = 1.0
    var depth = 1.0
    var roundness = 1.0
    var furLength = 0.12
    var density = 0.5
    var fuzz = 0.35
    var clumping = 0.25
    var curl = 0.25
    var gravity = 0.4
    var jumpHeight = 0.08
    var jumpDuration = 1.0
    var squashStretch = 0.12
    var spin = 0.0
    var lean = 5.0
    var idleJumpCadence = 0.0

    func normalized() -> Self {
        var c = self
        for key in [\Self.shadow, \.highlight, \.rimLight, \.furLength, \.density, \.fuzz, \.clumping, \.curl, \.gravity, \.squashStretch] {
            c[keyPath: key] = c[keyPath: key].clamped(to: 0...1, fallback: Self()[keyPath: key])
        }
        c.lightAngle = c.lightAngle.clamped(to: 0...360, fallback: 225)
        c.spread = c.spread.clamped(to: 0.25...2, fallback: 1)
        c.depth = c.depth.clamped(to: 0...2, fallback: 1)
        c.roundness = c.roundness.clamped(to: 0...2, fallback: 1)
        c.jumpHeight = c.jumpHeight.clamped(to: 0...0.3, fallback: 0.08)
        c.jumpDuration = c.jumpDuration.clamped(to: 0.3...3, fallback: 1)
        c.spin = c.spin.clamped(to: 0...2, fallback: 0)
        c.lean = c.lean.clamped(to: 0...20, fallback: 5)
        c.idleJumpCadence = c.idleJumpCadence.clamped(to: 0...20, fallback: 0)
        return c
    }
}

enum AgentVisualMotion {
    static func animates(_ state: AgentState) -> Bool {
        [.thinking, .planning, .working, .runningTool, .runningCommand].contains(state)
    }

    static func paused(reduceMotion: Bool, visible: Bool, active: Bool, enabled: Bool = true) -> Bool {
        reduceMotion || !visible || !active || !enabled
    }
}

// Local visibility and scene activity; never publish decorative ticks into the store/island.
private struct AgentVisualTimeline<Content: View>: View {
    @State private var visible = false
    @State private var appActive = NSApplication.shared.isActive
    var interval: Double
    var paused: Bool
    var runsWhileInactive = false
    @ViewBuilder var content: (TimeInterval) -> Content

    var body: some View {
        let stopped = AgentVisualMotion.paused(reduceMotion: paused, visible: visible, active: appActive || runsWhileInactive)
        TimelineView(.animation(minimumInterval: appActive ? interval : max(interval, 1.0 / 8.0), paused: stopped)) { timeline in
            content(stopped ? 0 : timeline.date.timeIntervalSinceReferenceDate)
        }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in appActive = false }
    }
}

struct VoiceBeamConfiguration: Codable, Equatable, Sendable {
    var variant: VoiceBeamColorVariant = .colorful
    var sensitivity = 1.0
    var threshold = 0.04
    var attack = 0.12
    var release = 0.32
    var reach = 1.0
    var spread = 1.0
    var flow = 1.0
    var bend = 1.0
    var idle = 0.08
    var strength = 0.9
    var animationEnabled = true

    func normalized() -> Self {
        var copy = self
        copy.sensitivity = copy.sensitivity.clamped(to: 0.25...3, fallback: 1)
        copy.threshold = copy.threshold.clamped(to: 0...0.4, fallback: 0.04)
        copy.attack = copy.attack.clamped(to: 0.02...0.8, fallback: 0.12)
        copy.release = copy.release.clamped(to: 0.05...1.5, fallback: 0.32)
        copy.reach = copy.reach.clamped(to: 0.4...2.5, fallback: 1)
        copy.spread = copy.spread.clamped(to: 0.4...2.5, fallback: 1)
        copy.flow = copy.flow.clamped(to: 0...2.5, fallback: 1)
        copy.bend = copy.bend.clamped(to: 0...2.5, fallback: 1)
        copy.idle = copy.idle.clamped(to: 0...0.5, fallback: 0.08)
        copy.strength = copy.strength.clamped(to: 0...1, fallback: 0.9)
        return copy
    }

    func reactiveLevel(_ raw: Double) -> Double {
        let c = normalized()
        let input = raw.clamped(to: 0...1, fallback: 0)
        let gated = max(0, input - c.threshold) / max(1 - c.threshold, 0.001)
        return min(max(gated * c.sensitivity, c.idle), 1)
    }
}

struct MetalSendConfiguration: Codable, Equatable, Sendable {
    var enabled = true
    var preset: MetalSendPreset = .chromatic
    var strength = 0.92
    var glowEnabled = true
    var glowGain = 1.0
    var innerShadow = true
    var animationEnabled = true

    func normalized() -> Self {
        var copy = self
        copy.strength = copy.strength.clamped(to: 0...1, fallback: 0.92)
        copy.glowGain = copy.glowGain.clamped(to: 0...2, fallback: 1)
        return copy
    }
}

struct AgentVisualPreferences: Codable, Equatable, Sendable {
    var indicatorStyle: AgentPresenceIndicatorStyle = .automatic
    var orbSpeed = 1.0
    var avatar = BotAvatarConfiguration()
    var voice = VoiceBeamConfiguration()
    var metal = MetalSendConfiguration()

    static let defaults = AgentVisualPreferences()

    func normalized() -> Self {
        var copy = self
        copy.orbSpeed = copy.orbSpeed.clamped(to: 0.25...2, fallback: 1)
        copy.avatar = copy.avatar.normalized()
        copy.voice = copy.voice.normalized()
        copy.metal = copy.metal.normalized()
        return copy
    }

    static func decode(from defaults: UserDefaults, key: String) -> Self {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return .defaults
        }
        return decoded.normalized()
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(normalized())
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard isFinite else { return fallback }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

enum AgentOrbStateMapper {
    static func state(for interaction: AgentManagedInteractionState, session: AgentSession) -> AgentOrbVisualState {
        switch interaction {
        case .connecting, .checkingAttachment, .stopping: .connecting
        case .submitting: .composing
        case .working: state(for: session)
        case .observed, .ready, .failed: .breathing
        }
    }

    static func state(for state: AgentState) -> AgentOrbVisualState {
        switch state {
        case .idle, .completed, .waitingForApproval, .waitingForUser: .breathing
        case .thinking: .solving
        case .planning: .weaving
        case .working: .working
        case .runningTool: .shaping
        case .runningCommand: .working
        case .planReady: .composing
        case .failed, .interrupted: .breathing
        }
    }

    static func state(for session: AgentSession) -> AgentOrbVisualState {
        if AgentVisualMotion.animates(session.state), let hint = activityHint(for: session) {
            switch hint {
            case .searching: return .searching
            case .connecting: return .connecting
            case .composing: return .composing
            }
        }
        switch session.state {
        case .idle, .completed, .waitingForApproval, .waitingForUser:
            return .breathing
        case .thinking:
            return activityHint(for: session) == .searching ? .searching : .solving
        case .planning:
            return .weaving
        case .working:
            switch activityHint(for: session) {
            case .searching: return .searching
            case .connecting: return .connecting
            case .composing: return .composing
            case .none: return .working
            }
        case .runningTool:
            return .shaping
        case .runningCommand:
            return .working
        case .planReady:
            return .composing
        case .failed, .interrupted:
            return .breathing
        }
    }

    static func state(for voicePhase: VoiceTranscriptionPhase) -> AgentOrbVisualState {
        switch voicePhase {
        case .recording: .listening
        case .requestingPermission, .preparing, .stopping: .connecting
        case .transcribing: .composing
        case .idle, .completed, .failed: .breathing
        }
    }

    private enum ActivityHint { case searching, connecting, composing }

    private static func activityHint(for session: AgentSession) -> ActivityHint? {
        guard let activity = session.recentActivity.last,
              activity.status == .active || activity.status == .pending else { return nil }
        let text = "\(activity.title) \(activity.summary ?? "")".lowercased()
        if text.contains("search") || text.contains("brows") || text.contains("lookup") { return .searching }
        if text.contains("connect") || text.contains("resum") || text.contains("loading") { return .connecting }
        if text.contains("write") || text.contains("compose") || text.contains("draft") || text.contains("generat") { return .composing }
        return nil
    }
}

enum BotAvatarDeterminism {
    static func type(for id: AgentSessionInstanceID) -> BotAvatarType {
        let seed = "\(id.sessionID.provider.stableName)|\(id.sessionID.nativeID)|\(id.generation.rawValue)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let values = BotAvatarType.allCases
        return values[Int(hash % UInt64(values.count))]
    }
}

struct AgentOrbView: View {
    let state: AgentOrbVisualState
    var size: CGFloat = 20
    var speed: Double = 1
    var paused = false
    var terminal = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let motionPaused = paused || reduceMotion || terminal
        AgentVisualTimeline(interval: size <= 26 ? 1.0 / 15.0 : 1.0 / 30.0, paused: motionPaused) { time in
            ZStack {
                Canvas { context, canvasSize in
                    draw(in: &context, size: canvasSize, time: time)
                }
                .id(state)
                .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: state)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.displayName) agent activity")
    }

    private func draw(in context: inout GraphicsContext, size canvasSize: CGSize, time: TimeInterval) {
        let s = min(canvasSize.width, canvasSize.height)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let count = size <= 24 ? 5 : 7
        let phase = time * max(speed, 0.05)
        for index in 0..<count {
            let p = Double(index) / Double(count)
            let point = orbPoint(index: index, count: count, center: center, radius: s * 0.27, phase: phase)
            let pulse = 0.78 + 0.22 * sin(phase * pulseFrequency + p * .pi * 2)
            let radius = max(1.1, s * 0.075 * CGFloat(pulse))
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(orbColor(index: index, count: count)))
        }
    }

    private var pulseFrequency: Double {
        switch state {
        case .breathing: 1.4
        case .listening: 5.0
        case .working, .shaping: 3.4
        default: 2.4
        }
    }

    private func orbPoint(index: Int, count: Int, center: CGPoint, radius: CGFloat, phase: Double) -> CGPoint {
        let p = Double(index) / Double(count)
        let angle = p * .pi * 2
        switch state {
        case .working:
            return polar(center, radius * (0.8 + 0.18 * CGFloat(sin(phase * 2 + angle))), angle + phase * 2.2)
        case .searching:
            return CGPoint(x: center.x + radius * CGFloat(sin(phase * 2.2 + angle)), y: center.y + radius * 0.48 * CGFloat(cos(angle)))
        case .solving:
            return polar(center, radius * CGFloat(0.45 + p * 0.65), angle + phase * (1.3 + p))
        case .listening:
            return CGPoint(x: center.x + radius * CGFloat((p - 0.5) * 2), y: center.y + radius * 0.72 * CGFloat(sin(phase * 4.0 + p * .pi * 3)))
        case .connecting:
            let side: CGFloat = index < count / 2 ? -1 : 1
            let approach = CGFloat(0.45 + 0.35 * cos(phase * 1.8))
            return CGPoint(x: center.x + side * radius * approach, y: center.y + radius * CGFloat(sin(angle)) * 0.58)
        case .weaving:
            return CGPoint(x: center.x + radius * CGFloat(sin(angle + phase * 1.4)), y: center.y + radius * 0.62 * CGFloat(sin(angle * 2 - phase * 1.1)))
        case .composing:
            return CGPoint(x: center.x + radius * CGFloat((p - 0.5) * 2), y: center.y + radius * 0.62 * CGFloat(cos(phase * 2.2 - p * .pi * 2)))
        case .breathing:
            let breathe = 0.72 + 0.16 * CGFloat(sin(phase * 1.3))
            return polar(center, radius * breathe, angle)
        case .shaping:
            let squareish = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            let contraction = CGFloat(0.72 + 0.20 * sin(phase * 2.8 + p * .pi))
            return CGPoint(x: center.x + (squareish.x - center.x) * contraction, y: center.y + (squareish.y - center.y) * contraction)
        }
    }

    private func polar(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }

    private func orbColor(index: Int, count: Int) -> Color {
        let alpha = colorScheme == .dark ? 0.96 : 0.86
        let t = Double(index) / Double(max(count - 1, 1))
        switch state {
        case .searching, .connecting:
            return Color(hue: 0.55 + 0.08 * t, saturation: 0.78, brightness: 1.0).opacity(alpha)
        case .listening:
            return Color(hue: 0.48 + 0.22 * t, saturation: 0.82, brightness: 1.0).opacity(alpha)
        case .weaving, .solving:
            return Color(hue: 0.70 + 0.18 * t, saturation: 0.72, brightness: 1.0).opacity(alpha)
        case .composing:
            return Color(hue: 0.08 + 0.12 * t, saturation: 0.75, brightness: 1.0).opacity(alpha)
        case .working, .shaping:
            return Color(hue: 0.42 + 0.28 * t, saturation: 0.76, brightness: 1.0).opacity(alpha)
        case .breathing:
            return Color.white.opacity(colorScheme == .dark ? 0.84 : 0.68)
        }
    }
}

struct BotAvatarView: View {
    let sessionID: AgentSessionInstanceID?
    var configuration: BotAvatarConfiguration
    var state: AgentState = .idle
    var overrideType: BotAvatarType? = nil
    var compact = false
    var paused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let config = configuration.normalized()
        let detail = config.details
        let type = overrideType ?? (config.automaticShape == false ? config.type : sessionID.map(BotAvatarDeterminism.type(for:)) ?? config.type)
        let size = CGFloat(compact ? min(config.size, 24) : config.size)
        let working = AgentVisualMotion.animates(state)
        let idleJump = state == .idle && detail.idleJumpCadence > 0 && detail.jumpHeight > 0 && config.motionStrength > 0
        let animated = (working && config.motionStrength > 0) || idleJump
        AgentVisualTimeline(interval: compact ? 1.0 / 15.0 : 1.0 / 30.0, paused: paused || reduceMotion || !animated) { time in
            let t = time * config.speed
            let sleeping = state == .idle || state == .completed
            let jumpPhase = working ? t / detail.jumpDuration : t.truncatingRemainder(dividingBy: max(detail.idleJumpCadence, detail.jumpDuration)) / detail.jumpDuration
            let jump = time == 0 || jumpPhase > 1 && !working ? 0 : abs(sin(jumpPhase * .pi))
            ZStack {
                if config.whirl > 0, working {
                    Circle()
                        .trim(from: 0.08, to: 0.86)
                        .stroke(bodyColor(type, config: config).opacity(0.24 + 0.18 * config.whirl), style: StrokeStyle(lineWidth: max(1, size * 0.055), lineCap: .round))
                        .rotationEffect(.degrees(t * 90 * config.motionStrength))
                        .padding(-size * 0.08)
                }

                AvatarBodyShape(type: type, roundness: detail.roundness)
                    .fill(bodyFill(type: type, config: config))
                    .overlay {
                        AvatarBodyShape(type: type, roundness: detail.roundness)
                            .stroke(LinearGradient(colors: [.white.opacity(detail.rimLight), .clear], startPoint: .bottomTrailing, endPoint: .topLeading), lineWidth: config.shading == .flat ? 0 : 0.8 + detail.depth)
                    }
                    .overlay {
                        if config.shading == .fabric {
                            AvatarFabricTexture(configuration: detail)
                                .clipShape(AvatarBodyShape(type: type, roundness: detail.roundness))
                        }
                    }
                    .shadow(color: Color.black.opacity(config.shading == .flat ? 0 : detail.shadow), radius: 1 + 3 * detail.spread, y: detail.depth * 2)

                avatarFace(size: size, sleeping: sleeping, config: config)
                accessories(size: size, config: config)
            }
            .frame(width: size, height: size)
            .scaleEffect(x: max(0.5, 1 - jump * detail.squashStretch * 0.25 * config.motionStrength), y: 1 + jump * detail.squashStretch * 0.25 * config.motionStrength)
            .rotationEffect(.degrees(working ? (sin(t * 3.2) * detail.lean + t * 90 * detail.spin) * config.motionStrength : 0))
            .offset(y: -jump * size * detail.jumpHeight * config.motionStrength * (compact ? 0.25 : 1))
        }
        .frame(width: CGFloat(compact ? min(config.size, 24) : config.size), height: CGFloat(compact ? min(config.size, 24) : config.size))
        .scaleEffect(config.interactive && hovering && !reduceMotion ? 1.05 : 1)
        .rotation3DEffect(
            .degrees(config.interactive && hovering && !reduceMotion ? 7 * config.turn : 0),
            axis: (x: 0, y: 1, z: 0)
        )
        .onHover { value in
            if config.interactive && !reduceMotion { hovering = value }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bot avatar, \(state.rawValue)")
    }

    private func bodyColor(_ type: BotAvatarType, config: BotAvatarConfiguration) -> Color {
        let index = BotAvatarType.allCases.firstIndex(of: type) ?? 0
        return Color(
            hue: Double(index) / Double(BotAvatarType.allCases.count),
            saturation: min(max(0.48 * config.saturation, 0.16), 1),
            brightness: min(max(0.78 * config.brightness, 0.28), 1)
        )
    }

    private func bodyFill(type: BotAvatarType, config: BotAvatarConfiguration) -> AnyShapeStyle {
        let base = bodyColor(type, config: config)
        let detail = config.details
        let angle = detail.lightAngle * .pi / 180
        let light = UnitPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
        let end = UnitPoint(x: 1 - light.x, y: 1 - light.y)
        switch config.shading {
        case .flat:
            return AnyShapeStyle(base)
        case .smooth:
            return AnyShapeStyle(LinearGradient(colors: [.white.opacity(detail.highlight * 0.4), base, base.opacity(1 - 0.3 * detail.depth)], startPoint: light, endPoint: end))
        case .crisp:
            return AnyShapeStyle(LinearGradient(stops: [.init(color: .white.opacity(detail.highlight), location: 0), .init(color: base, location: min(0.8, 0.35 * detail.spread)), .init(color: base.opacity(1 - 0.3 * detail.depth), location: 1)], startPoint: light, endPoint: end))
        case .plastic:
            return AnyShapeStyle(RadialGradient(colors: [.white.opacity(detail.highlight), base, base.opacity(1 - 0.3 * detail.depth)], center: light, startRadius: 0, endRadius: config.size * detail.spread))
        case .fabric:
            return AnyShapeStyle(RadialGradient(colors: [.white.opacity(detail.highlight), base, base.opacity(1 - 0.3 * detail.depth)], center: light, startRadius: 0, endRadius: config.size * detail.spread))
        }
    }

    private func edgeOpacity(_ shading: BotAvatarShading) -> Double {
        switch shading {
        case .flat: 0
        case .smooth: 0.14
        case .crisp: 0.46
        case .plastic: 0.34
        case .fabric: 0.26
        }
    }

    @ViewBuilder
    private func avatarFace(size: CGFloat, sleeping: Bool, config: BotAvatarConfiguration) -> some View {
        VStack(spacing: size * 0.07) {
            HStack(spacing: size * 0.18) {
                Capsule()
                    .fill(faceColor)
                    .frame(width: size * 0.10, height: sleeping ? 1.5 : size * 0.13)
                Capsule()
                    .fill(faceColor)
                    .frame(width: size * 0.10, height: sleeping ? 1.5 : size * 0.13)
            }
            if config.face == .mouth {
                Capsule()
                    .fill(faceColor.opacity(0.86))
                    .frame(width: size * 0.22, height: max(1.5, size * 0.045))
            }
        }
        .offset(y: size * 0.04)
    }

    private var faceColor: Color {
        colorScheme == .dark ? .black.opacity(0.78) : .black.opacity(0.72)
    }

    @ViewBuilder
    private func accessories(size: CGFloat, config: BotAvatarConfiguration) -> some View {
        let accessoryColor = Color(agentHex: config.accessoryColorHex) ?? .black.opacity(0.82)
        if config.hat != .none {
            Group {
                switch config.hat {
                case .none: EmptyView()
                case .beret:
                    Ellipse().fill(accessoryColor).frame(width: size * 0.46, height: size * 0.16)
                case .beanie:
                    RoundedRectangle(cornerRadius: size * 0.08).fill(accessoryColor).frame(width: size * 0.50, height: size * 0.18)
                case .party:
                    TriangleShape().fill(accessoryColor).frame(width: size * 0.34, height: size * 0.30)
                case .crown:
                    Image(systemName: "crown.fill").resizable().scaledToFit().foregroundStyle(accessoryColor).frame(width: size * 0.38, height: size * 0.24)
                }
            }
            .offset(y: -size * 0.43)
        }
        if config.glasses != .none {
            HStack(spacing: size * 0.04) {
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: config.glasses == .round ? size * 0.1 : size * 0.025)
                        .fill(config.glasses == .shades ? accessoryColor : .clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: config.glasses == .round ? size * 0.1 : size * 0.025)
                                .stroke(accessoryColor, lineWidth: max(1, size * 0.025))
                        }
                        .frame(width: size * 0.21, height: size * 0.18)
                }
            }.offset(y: size * 0.01)
        }
        if config.headphones {
            Image(systemName: "headphones")
                .resizable()
                .scaledToFit()
                .foregroundStyle(accessoryColor)
                .frame(width: size * 0.76, height: size * 0.76)
        }
        if config.bowTie {
            HStack(spacing: 1) {
                TriangleShape().fill(accessoryColor).frame(width: size * 0.14, height: size * 0.12).rotationEffect(.degrees(-90))
                TriangleShape().fill(accessoryColor).frame(width: size * 0.14, height: size * 0.12).rotationEffect(.degrees(90))
            }
            .offset(y: size * 0.34)
        }
    }
}

// Bounded static fibers, deterministic across redraws. No texture timer or random seed.
private struct AvatarFabricTexture: View {
    var configuration: BotAvatarAdvancedConfiguration

    var body: some View {
        Canvas { context, size in
            let c = configuration
            let count = Int(c.density * 120)
            for index in 0..<count {
                let seed = Double(index)
                let group = floor(seed / 4)
                let x = (sin(seed * 78.233) * 43758.5453).fraction
                let y = (sin(seed * 12.9898) * 96321.9123).fraction
                let cluster = (sin(group * 32.17) * 15731.7).fraction
                let start = CGPoint(x: (x * (1 - c.clumping) + cluster * c.clumping) * size.width, y: y * size.height)
                let length = size.height * c.furLength * 0.35
                let end = CGPoint(x: start.x + length * (x - 0.5), y: start.y + length * (c.gravity - 0.5) * 2)
                var path = Path()
                path.move(to: start)
                path.addQuadCurve(to: end, control: CGPoint(x: start.x + length * c.curl, y: start.y - length * (1 - c.gravity)))
                context.stroke(path, with: .color(.white.opacity(0.10 + c.fuzz * 0.25)), lineWidth: 0.35 + c.fuzz)
            }
        }
        .allowsHitTesting(false)
    }
}

private extension Double {
    var fraction: Double { self - floor(self) }
}

private struct AvatarBodyShape: Shape {
    let type: BotAvatarType
    var roundness: Double = 1

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        switch type {
        case .circle: return Path(ellipseIn: inset)
        case .square, .droid, .mech:
            return Path(roundedRect: inset, cornerRadius: rect.width * (type == .square ? 0.18 : 0.28) * roundness)
        case .pill:
            return Path(roundedRect: inset.insetBy(dx: 0, dy: rect.height * 0.14), cornerRadius: rect.width * 0.42 * roundness)
        case .triangle:
            var p = Path(); p.move(to: CGPoint(x: rect.midX, y: inset.minY)); p.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY)); p.addLine(to: CGPoint(x: inset.minX, y: inset.maxY)); p.closeSubpath(); return p
        case .hexagon:
            return polygonPath(sides: 6, rect: inset, rotation: .pi / 6)
        case .star:
            return starPath(rect: inset)
        case .drop:
            var p = Path(); p.move(to: CGPoint(x: rect.midX, y: inset.minY)); p.addCurve(to: CGPoint(x: inset.maxX, y: rect.midY), control1: CGPoint(x: inset.maxX, y: inset.minY + rect.height * 0.18), control2: CGPoint(x: inset.maxX, y: rect.midY - rect.height * 0.12)); p.addCurve(to: CGPoint(x: rect.midX, y: inset.maxY), control1: CGPoint(x: inset.maxX, y: inset.maxY - rect.height * 0.12), control2: CGPoint(x: rect.midX + rect.width * 0.18, y: inset.maxY)); p.addCurve(to: CGPoint(x: inset.minX, y: rect.midY), control1: CGPoint(x: rect.midX - rect.width * 0.18, y: inset.maxY), control2: CGPoint(x: inset.minX, y: inset.maxY - rect.height * 0.12)); p.addCurve(to: CGPoint(x: rect.midX, y: inset.minY), control1: CGPoint(x: inset.minX, y: rect.midY - rect.height * 0.12), control2: CGPoint(x: inset.minX, y: inset.minY + rect.height * 0.18)); return p
        case .clover:
            var p = Path(); let r = rect.width * 0.23
            for c in [CGPoint(x: rect.midX, y: rect.midY-r*0.72), CGPoint(x: rect.midX+r*0.72, y: rect.midY), CGPoint(x: rect.midX, y: rect.midY+r*0.72), CGPoint(x: rect.midX-r*0.72, y: rect.midY)] { p.addEllipse(in: CGRect(x:c.x-r,y:c.y-r,width:r*2,height:r*2)) }
            return p
        case .flower:
            var p = Path(); let r = rect.width * 0.19
            for i in 0..<6 { let a = Double(i) * .pi / 3; let c = CGPoint(x: rect.midX + cos(a)*rect.width*0.25, y: rect.midY + sin(a)*rect.height*0.25); p.addEllipse(in:CGRect(x:c.x-r,y:c.y-r,width:r*2,height:r*2)) }
            p.addEllipse(in: CGRect(x: rect.midX-r, y: rect.midY-r, width:r*2,height:r*2)); return p
        case .ghost:
            let p = Path(roundedRect: inset, cornerRadius: rect.width * 0.34 * roundness); return p
        case .cloud:
            var p = Path(); p.addEllipse(in: CGRect(x: inset.minX, y: rect.midY-rect.height*0.18, width:rect.width*0.44,height:rect.height*0.36)); p.addEllipse(in:CGRect(x:rect.midX-rect.width*0.24,y:inset.minY,width:rect.width*0.48,height:rect.height*0.48)); p.addEllipse(in:CGRect(x:rect.midX,y:rect.midY-rect.height*0.16,width:rect.width*0.42,height:rect.height*0.34)); return p
        case .cat:
            var p = Path(roundedRect: inset, cornerRadius: rect.width * 0.30 * roundness); p.move(to: CGPoint(x:inset.minX+rect.width*0.12,y:inset.minY+rect.height*0.06)); p.addLine(to: CGPoint(x:inset.minX,y:inset.minY-rect.height*0.12)); p.addLine(to: CGPoint(x:inset.minX+rect.width*0.24,y:inset.minY)); p.move(to: CGPoint(x:inset.maxX-rect.width*0.12,y:inset.minY+rect.height*0.06)); p.addLine(to: CGPoint(x:inset.maxX,y:inset.minY-rect.height*0.12)); p.addLine(to: CGPoint(x:inset.maxX-rect.width*0.24,y:inset.minY)); return p
        case .blob, .alien, .pebble, .puddle:
            let xScale: CGFloat = type == .puddle ? 0.98 : type == .pebble ? 0.78 : 0.90
            let yScale: CGFloat = type == .puddle ? 0.58 : type == .alien ? 0.92 : 0.82
            let r = CGRect(x: rect.midX - inset.width*xScale/2, y: rect.midY - inset.height*yScale/2, width: inset.width*xScale, height: inset.height*yScale)
            return Path(roundedRect: r, cornerRadius: rect.width * (type == .blob ? 0.34 : 0.42) * roundness)
        }
    }

    private func polygonPath(sides: Int, rect: CGRect, rotation: Double) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<sides {
            let a = rotation + Double(i) * .pi * 2 / Double(sides)
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath(); return p
    }

    private func starPath(rect: CGRect) -> Path {
        var p = Path(); let c = CGPoint(x:rect.midX,y:rect.midY); let outer=min(rect.width,rect.height)/2; let inner=outer*0.44
        for i in 0..<10 { let r = i.isMultiple(of:2) ? outer : inner; let a = -.pi/2 + Double(i) * Double.pi / 5; let pt=CGPoint(x:c.x+r*CGFloat(cos(a)),y:c.y+r*CGFloat(sin(a))); i == 0 ? p.move(to:pt) : p.addLine(to:pt) }
        p.closeSubpath(); return p
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x:rect.midX,y:rect.minY)); p.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY)); p.addLine(to:CGPoint(x:rect.minX,y:rect.maxY)); p.closeSubpath(); return p
    }
}

final class VoiceBeamEnvelope {
    private(set) var value: Double = 0
    private var lastTimestamp: TimeInterval?

    func sample(rawLevel: Double, timestamp: TimeInterval, configuration: VoiceBeamConfiguration) -> Double {
        let config = configuration.normalized()
        let target = config.reactiveLevel(rawLevel)
        guard let lastTimestamp else {
            self.lastTimestamp = timestamp
            value = target
            return value
        }

        let delta = min(max(timestamp - lastTimestamp, 0), 0.25)
        self.lastTimestamp = timestamp
        let timeConstant = target >= value ? config.attack : config.release
        let alpha = timeConstant <= 0 ? 1 : 1 - exp(-delta / timeConstant)
        value += (target - value) * alpha
        value = min(max(value, 0), 1)
        return value
    }

    func reset() {
        value = 0
        lastTimestamp = nil
    }
}

struct VoiceBeamView: View {
    var level: () -> Double
    var processing = false
    var configuration: VoiceBeamConfiguration
    var height: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var envelope = VoiceBeamEnvelope()

    var body: some View {
        let config = configuration.normalized()
        AgentVisualTimeline(interval: 1.0 / 30.0, paused: reduceMotion || !config.animationEnabled, runsWhileInactive: true) { time in
            GeometryReader { proxy in
                let t = time * config.flow
                Canvas { context, size in
                    // Static listening still reflects the meter when its owner updates;
                    // processing never reads the microphone after capture stops.
                    let reactive = processing ? 0.55 : (time == 0 ? config.reactiveLevel(level()) : envelope.sample(rawLevel: level(), timestamp: time, configuration: config))
                    let geometry = VoiceBeamGeometry.make(width: size.width, height: size.height, level: reactive, processing: processing, time: t, configuration: config)
                    let centerX = geometry.centerX
                    let beamWidth = geometry.width
                    let bloom = geometry.bloom
                    let colors = beamColors(config.variant)
                    for index in colors.indices {
                        let p = Double(index) / Double(max(colors.count - 1, 1))
                        let x = centerX + CGFloat(p - 0.5) * beamWidth * CGFloat(0.72 + 0.12 * sin(t * 2 + p * .pi * 2))
                        let w = max(6, beamWidth / CGFloat(colors.count) * 1.8)
                        let y = size.height - bloom * CGFloat(0.55 + 0.28 * sin(t * 2.3 + p * .pi * 2) * config.bend)
                        let rect = CGRect(x: x - w / 2, y: y, width: w, height: bloom)
                        context.fill(Path(roundedRect: rect, cornerRadius: w/2), with:.color(colors[index].opacity(config.strength * (processing ? 0.94 : 0.78))))
                    }
                    let core = CGRect(x:centerX-beamWidth/2,y:size.height-max(1.5,bloom*0.16),width:beamWidth,height:max(1.5,bloom*0.16))
                    context.fill(Path(roundedRect:core,cornerRadius:core.height/2),with:.color(Color.white.opacity(config.strength * 0.9)))
                }
                .blur(radius: processing ? 1.1 : 1.7)
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: processing) { _, _ in envelope.reset() }
        .onDisappear { envelope.reset() }
    }

    private func beamColors(_ variant: VoiceBeamColorVariant) -> [Color] {
        switch variant {
        case .colorful: [.cyan, .blue, .purple, .pink, .orange]
        case .mono: [.white.opacity(0.62), .white, .white.opacity(0.62)]
        case .ocean: [.cyan, .blue, .indigo]
        case .sunset: [.yellow, .orange, .pink, .purple]
        case .forest: [.mint, .green, .teal]
        case .candy: [.pink, .purple, .cyan]
        case .ice: [.white, .cyan, .blue.opacity(0.8)]
        case .gold: [.yellow, .orange, Color(red:0.95,green:0.75,blue:0.20)]
        }
    }
}

struct VoiceBeamGeometry: Equatable {
    var centerX: CGFloat
    var width: CGFloat
    var bloom: CGFloat

    static func make(width: CGFloat, height: CGFloat, level: Double, processing: Bool, time: Double, configuration: VoiceBeamConfiguration) -> Self {
        let c = configuration.normalized()
        let reactive = processing ? 0.55 : level.clamped(to: 0...1, fallback: 0)
        return Self(
            centerX: processing ? width * (0.5 + 0.18 * sin(time * 1.9)) : width / 2,
            width: min(width * 0.85, max(18, width * (processing ? 0.22 : 0.20 + 0.55 * reactive) * c.spread)),
            bloom: min(height, max(2, height * (processing ? 0.48 : 0.18 + reactive * 0.72) * c.reach))
        )
    }
}

struct MetalSendButton: View {
    var configuration: MetalSendConfiguration
    var isEnabled: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let config = configuration.normalized()
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? (config.enabled && config.strength >= 0.5 ? Color.black.opacity(0.9) : Color.white) : Color.white.opacity(0.45))
                .frame(width: 30, height: 30)
                .background {
                    if config.enabled {
                        metalSurface(config)
                    } else {
                        Circle().fill(Color.white.opacity(isEnabled ? 0.16 : 0.06))
                    }
                }
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(MetalSendPressStyle(reduceMotion: reduceMotion, hovering: hovering && isEnabled))
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.72), value: hovering)
        .accessibilityLabel("Send prompt")
        .accessibilityValue(isEnabled ? "Ready" : "Unavailable")
    }

    @ViewBuilder
    private func metalSurface(_ config: MetalSendConfiguration) -> some View {
        AgentVisualTimeline(interval: 1.0 / 24.0, paused: reduceMotion || !config.animationEnabled || !isEnabled || !hovering) { t in
            let colors: [Color] = switch config.preset {
            case .chromatic: [.cyan, .white, .pink, .purple, .cyan]
            case .silver: [.white.opacity(0.9), .gray.opacity(0.55), .white, .gray.opacity(0.72)]
            case .gold: [.yellow.opacity(0.9), .orange.opacity(0.85), .white.opacity(0.78), .yellow]
            }
            Circle()
                .fill(AngularGradient(colors: colors, center: .center, angle: .degrees(t * 34)))
                .opacity(isEnabled ? config.strength : 0.20)
                .overlay {
                    if config.innerShadow {
                        Circle().stroke(LinearGradient(colors:[.white.opacity(0.86),.clear,.black.opacity(0.28)],startPoint:.top,endPoint:.bottom),lineWidth:1)
                    }
                }
                .shadow(color: config.glowEnabled && isEnabled ? colors.first!.opacity(0.32 * config.glowGain) : .clear, radius: 7 * config.glowGain)
        }
        .allowsHitTesting(false)
    }
}

private struct MetalSendPressStyle: ButtonStyle {
    var reduceMotion: Bool
    var hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.92 : hovering ? 1.05 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension Color {
    fileprivate init?(agentHex: String) {
        guard let c = Self.agentHexComponents(agentHex) else { return nil }
        self = Color(red: c.0, green: c.1, blue: c.2)
    }

    fileprivate static func agentHexComponents(_ value: String) -> (Double, Double, Double)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }), let number = Int(hex, radix:16) else { return nil }
        return (Double((number >> 16) & 0xff)/255, Double((number >> 8) & 0xff)/255, Double(number & 0xff)/255)
    }
}


private struct AgentVisualPreferencesEnvironmentKey: EnvironmentKey {
    static let defaultValue = AgentVisualPreferences.defaults
}

extension EnvironmentValues {
    var agentVisualPreferences: AgentVisualPreferences {
        get { self[AgentVisualPreferencesEnvironmentKey.self] }
        set { self[AgentVisualPreferencesEnvironmentKey.self] = newValue.normalized() }
    }
}

struct AgentPresenceGlyph: View {
    let session: AgentSession
    var size: CGFloat = 20
    var paused = false
    @Environment(\.agentVisualPreferences) private var preferences

    var body: some View {
        let config = preferences.normalized()
        let resolvedStyle: AgentPresenceIndicatorStyle = {
            if config.indicatorStyle != .automatic { return config.indicatorStyle }
            if config.avatar.enabled && AgentSessionPresentation.requiresAttention(session) { return .avatar }
            return .orb
        }()

        Group {
            switch resolvedStyle {
            case .avatar:
                if config.avatar.enabled {
                    BotAvatarView(
                        sessionID: session.id,
                        configuration: compactAvatar(config.avatar),
                        state: session.state,
                        compact: true,
                        paused: paused
                    )
                } else {
                    orb(config)
                }
            case .orb, .automatic:
                orb(config)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.id.sessionID.provider.stableName.capitalized), \(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))")
    }

    private func orb(_ config: AgentVisualPreferences) -> some View {
        AgentOrbView(
            state: AgentOrbStateMapper.state(for: session),
            size: size,
            speed: config.orbSpeed,
            paused: paused,
            terminal: !AgentVisualMotion.animates(session.state)
        )
    }

    private func compactAvatar(_ config: BotAvatarConfiguration) -> BotAvatarConfiguration {
        var copy = config
        copy.size = min(config.size, Double(size))
        return copy
    }
}

struct CollapsedVoiceBeamCompactView: View {
    @ObservedObject var controller: VoiceTranscriptionController
    let activity: DynamicIslandLiveActivity
    @Environment(\.agentVisualPreferences) private var preferences

    var body: some View {
        let processing = activity.kind == .voiceTranscription
        ZStack(alignment: .bottom) {
            HStack(spacing: 6) {
                Image(systemName: processing ? "waveform" : "mic.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(processing ? Color.cyan : Color.white.opacity(0.92))
                Text(processing ? "Transcribing" : "Listening")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !processing {
                    Text("LIVE")
                        .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.red.opacity(0.92))
                }
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 4)

            VoiceBeamView(
                level: { controller.liveAudioLevel },
                processing: processing,
                configuration: preferences.voice,
                height: 14
            )
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(processing ? "Voice transcription processing" : "Voice recording listening")
    }
}
