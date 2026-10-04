import SwiftUI
import Foundation
import AppKit
import LibrariesNative

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
    var fidelity: BotAvatarFidelityConfiguration? = nil

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
        copy.fidelity = copy.fidelity?.normalized()
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
        case .observed, .ready: state(for: session)
        case .failed: .breathing
        }
    }

    static func state(for state: AgentState) -> AgentOrbVisualState {
        switch state {
        case .idle, .completed, .waitingForApproval, .waitingForUser, .failed, .interrupted: .breathing
        case .thinking: .solving
        case .planning: .shaping
        case .working, .runningTool, .runningCommand: .working
        case .planReady: .composing
        }
    }

    static func state(for kind: AgentProcessingKind) -> AgentOrbVisualState {
        switch kind {
        case .reasoning: .solving
        case .planning: .shaping
        case .searching: .searching
        case .executing: .working
        case .connecting: .connecting
        case .listening: .listening
        case .composing: .composing
        case .synthesizing: .weaving
        case .background: .breathing
        }
    }

    static func state(for session: AgentSession) -> AgentOrbVisualState {
        guard AgentVisualMotion.animates(session.state) else { return state(for: session.state) }
        if let kind = session.currentProcessingKind { return state(for: kind) }
        return state(for: session.state)
    }

    static func state(for voicePhase: VoiceTranscriptionPhase) -> AgentOrbVisualState {
        switch voicePhase {
        case .recording: .listening
        case .requestingPermission, .preparing, .stopping: .connecting
        case .transcribing: .composing
        case .idle, .completed, .failed: .breathing
        }
    }
}

enum BotAvatarDeterminism {
    static func type(for id: AgentSessionInstanceID) -> BotAvatarType {
        let hash = hash(for: id)
        let values = BotAvatarType.allCases
        return values[Int(hash % UInt64(values.count))]
    }

    static func seed(for id: AgentSessionInstanceID) -> Double { Double(hash(for: id) >> 11) / 9_007_199_254_740_992 }

    private static func hash(for id: AgentSessionInstanceID) -> UInt64 {
        let seed = "\(id.sessionID.provider.stableName)|\(id.sessionID.nativeID)|\(id.generation.rawValue)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
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
    var sessionID: AgentSessionInstanceID? = nil
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var visible = false
    @StateObject private var localMetal = MetalFxModel()

    private var metal: MetalFxModel { sessionID.map(AgentMetalModelStore.model(for:)) ?? localMetal }

    var body: some View {
        let config = configuration.normalized()
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? (config.enabled && config.strength >= 0.5 ? Color.white.opacity(0.95) : Color.white) : Color.white.opacity(0.45))
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
        NativeMetalFx(model: metal, preset: MetalPreset(rawValue: config.preset.rawValue) ?? .chromatic,
            strength: isEnabled ? config.strength : 0.20,
            innerShadow: config.innerShadow, glow: config.glowEnabled && isEnabled,
            glowGain: config.glowGain,
            paused: reduceMotion || !config.animationEnabled || !isEnabled || !visible)
        .background { NativeVisualVisibility { visible = $0 } }
        .background { NativeMetalPointer(model: metal, enabled: visible && isEnabled && !reduceMotion) }

        .allowsHitTesting(false)
    }
}

private struct MetalSendPressStyle: ButtonStyle {
    var reduceMotion: Bool
    var hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
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
            if config.avatar.enabled { return .avatar }
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
