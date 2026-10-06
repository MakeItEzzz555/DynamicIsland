import SwiftUI
import AppKit
import LibrariesNative

private struct NativeVisualSnapshotTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}
extension EnvironmentValues {
    // Development-only render input, supplied by deterministic snapshot tests.
    var nativeVisualSnapshotTime: Double? {
        get { self[NativeVisualSnapshotTimeKey.self] }
        set { self[NativeVisualSnapshotTimeKey.self] = newValue }
    }
}

// Decoration owns its redraw clock. It never publishes ticks to the island,
// transcript or domain store. Inactive menu-bar windows may remain visible.
@MainActor private final class OrbPlayback: ObservableObject {
    private static let origin = Date.now.timeIntervalSinceReferenceDate
    var time = Date.now.timeIntervalSinceReferenceDate - OrbPlayback.origin + 0.6
    var last: Double?
    func sample(_ timestamp: Double, paused: Bool) -> Double {
        if paused { last = nil; return time }
        if let last, timestamp > last, timestamp - last < 0.12 { time += timestamp - last }
        last = timestamp
        return time
    }
}

struct AgentOrbView: View {
    let state: AgentOrbVisualState
    var size: CGFloat = 20
    var speed: Double = 1
    var paused = false
    var terminal = false
    var frozenTime: Double? = nil
    @Environment(\.nativeVisualSnapshotTime) private var snapshotTime
    private var renderTime: Double? { frozenTime ?? snapshotTime }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false
    @StateObject private var playback = OrbPlayback()
    @State private var previous: AgentOrbVisualState?
    @State private var changedAt = Date.distantPast

    var body: some View {
        let stopped = paused || terminal || reduceMotion || !visible || renderTime != nil
        TimelineView(.animation(minimumInterval: IslandFrameCadence.interval(.expandedDecoration), paused: stopped)) { tick in
            Canvas { context, _ in
                let t = renderTime ?? (reduceMotion ? 0.6 : playback.sample(tick.date.timeIntervalSinceReferenceDate, paused: stopped))
                let progress = stopped ? 1 : min(1, max(0, tick.date.timeIntervalSince(changedAt) / 0.24))
                if let previous, progress < 1 { paint(previous, t: t, opacity: 1-progress, context: &context) }
                paint(state, t: t, opacity: progress, context: &context)
            }
        }
        .frame(width: size, height: size)
        .background { if renderTime == nil { NativeVisualVisibility { visible = $0 } } }
        .onChange(of: state) { old, _ in previous = old; changedAt = .now }
        .onDisappear { playback.last = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.displayName) agent activity")
        .accessibilityAddTraits(.isImage)
    }

    private func paint(_ state: AgentOrbVisualState, t: Double, opacity: Double, context: inout GraphicsContext) {
        let tuning: OrbSize = size <= 28 ? .px20 : .px64
        let referenceSide = Double(tuning.rawValue)
        let preset = resolvePreset(OrbState(rawValue: state.rawValue)!, tuning)
        let engineTime = renderTime != nil || reduceMotion ? t : t * preset.speed * min(2, max(0.25, speed))
        let frame = orbFrame(preset, size: referenceSide, t: engineTime)
        var c = context
        c.scaleBy(x: size/referenceSide, y: size/referenceSide)
        c.opacity *= opacity
        func ink(_ white: Double, _ alpha: Double) -> Color {
            let w = min(1, max(0, white))
            let gray = ((colorScheme == .dark ? 1-w : w)*255).rounded()/255
            return Color(.sRGB, red: gray, green: gray, blue: gray, opacity: alpha)
        }
        for line in frame.lines {
            var p = Path(); p.move(to: CGPoint(x: line.x1, y: line.y1)); p.addLine(to: CGPoint(x: line.x2, y: line.y2))
            c.stroke(p, with: .color(ink(line.white, line.a)), lineWidth: line.w)
        }
        for dot in frame.dots {
            c.fill(Path(ellipseIn: CGRect(x: dot.x-dot.r, y: dot.y-dot.r, width: dot.r*2, height: dot.r*2)), with: .color(ink(dot.white, dot.a)))
        }
    }
}

enum AgentAvatarStateMapper {
    static func state(_ state: AgentState) -> LibrariesNative.BotAvatarState {
        if AgentVisualMotion.animates(state) { return .working }
        return state == .completed ? .sleeping : .default
    }
}

// A bounded presentation-only roster retains phase through compact/expanded
// handoff. No session/domain mutation, timers, observers or Tasks live here.
@MainActor enum AgentAvatarPlayers {
    private static var players: [AgentSessionInstanceID: BotAvatarPlayer] = [:]
    private static var seeds: [AgentSessionInstanceID: Double] = [:]
    private static var order: [AgentSessionInstanceID] = []
    static let capacity = 64
    static var count: Int { players.count }
    static func player(for id: AgentSessionInstanceID, state: LibrariesNative.BotAvatarState, seed override: Double? = nil) -> BotAvatarPlayer {
        let seed = override ?? BotAvatarDeterminism.seed(for: id)
        if let player = players[id] {
            if seeds[id] != seed { player.simulation.reseed(seed, state: state); player.suspend(); seeds[id] = seed }
            return player
        }
        if order.count >= capacity { let oldest = order.removeFirst(); players.removeValue(forKey: oldest); seeds.removeValue(forKey: oldest) }
        let player = BotAvatarPlayer(seed: seed, state: state)
        players[id] = player; seeds[id] = seed; order.append(id)
        return player
    }
}

@MainActor private final class AvatarRenderContext: ObservableObject {
    let player = BotAvatarPlayer(seed: 0.5)
    let renderer = BotAvatarRenderState()
}

struct BotAvatarView: View {
    let sessionID: AgentSessionInstanceID?
    var configuration: BotAvatarConfiguration
    var state: AgentState = .idle
    var overrideType: BotAvatarType? = nil
    var compact = false
    var paused = false
    var frozenTime: Double? = nil
    var interactionEnabled = true
    @Environment(\.nativeVisualSnapshotTime) private var snapshotTime
    private var renderTime: Double? { frozenTime ?? snapshotTime }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var visible = false
    @StateObject private var rendering = AvatarRenderContext()

    var body: some View {
        let config = configuration.normalized()
        let fidelity = (config.fidelity ?? .init()).normalized()
        let type = overrideType ?? (config.automaticShape == false ? config.type : sessionID.map(BotAvatarDeterminism.type(for:)) ?? config.type)
        let nativeType = LibrariesNative.BotAvatarType(rawValue: type.rawValue)!
        let nativeState = AgentAvatarStateMapper.state(state)
        // Historical/snapshot poses must not change or suspend the live rig for
        // the same session while a current working presentation is visible.
        let player = renderTime == nil
            ? sessionID.map { AgentAvatarPlayers.player(for: $0, state: nativeState, seed: fidelity.seed) } ?? rendering.player
            : rendering.player
        let side = compact ? min(config.size, 24) : config.size
        // Unlike the reference's free overscan, island/row content is bounded.
        // Reserve room above the body for the complete jump arc and hats.
        let box = side * (compact ? (config.hat == .none ? 0.82 : 0.68) : 1.0)
        let stopped = paused || fidelity.paused || reduceMotion || !visible || renderTime != nil || fidelity.poseEnabled || config.motionStrength == 0
        let interactive = config.interactive && interactionEnabled && !reduceMotion && !paused && !fidelity.paused && !fidelity.poseEnabled
        TimelineView(.animation(minimumInterval: IslandFrameCadence.interval(.expandedDecoration), paused: stopped)) { tick in
            Canvas { context, _ in
                var pose: BotAvatarPose
                if let frozenTime = renderTime {
                    let sim = BotAvatarSim(seed: fidelity.seed ?? sessionID.map(BotAvatarDeterminism.seed(for:)) ?? 0.5, state: nativeState)
                    sim.setJump(config.nativeJump); sim.setTurn(config.turn)
                    for _ in 0..<Int(min(30, max(0, frozenTime))*60) { sim.update(1/60) }
                    pose = sim.pose
                } else if reduceMotion || (!visible && player.lastTimestamp == nil) {
                    pose = .rest(nativeState)
                } else {
                    player.simulation.setJump(config.nativeJump); player.simulation.setTurn(config.turn)
                    pose = player.frame(at: tick.date.timeIntervalSinceReferenceDate, state: nativeState, speed: config.speed, paused: stopped)
                }
                if fidelity.poseEnabled {
                    pose = .rest(nativeState)
                    pose.yaw = fidelity.yaw * .pi/180; pose.pitch = fidelity.pitch * .pi/180; pose.roll = fidelity.roll * .pi/180
                }
                pose.y *= config.motionStrength * (compact ? 0.25 : 1)
                pose.sx = 1+(pose.sx-1)*config.motionStrength
                pose.sy = 1+(pose.sy-1)*config.motionStrength
                pose.whirl = reduceMotion ? 0 : pose.whirl
                var cfg = config.nativeDraw(type: nativeType)
                cfg.scale = min(2, displayScale); cfg.still = stopped; cfg.theme = colorScheme
                drawBotAvatarFrame(&context, box: box, pose: pose, cfg: cfg, state: rendering.renderer)
            }
            .allowsHitTesting(false)
        }
        .frame(width: box*BOT_AVATAR_OVERSCAN, height: box*BOT_AVATAR_OVERSCAN)
        .offset(y: -BOT_AVATAR_RISE*box)
        .frame(width: side, height: side)
        .modifier(NativeAvatarContainment(compact: compact))
        .background { if renderTime == nil { NativeVisualVisibility { visible = $0; if !$0 { player.suspend() } } } }
        .overlay {
            if renderTime == nil {
                NativeAvatarPointer(enabled: interactive, player: player)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { if interactive { player.simulation.poke() } })
        .onChange(of: fidelity.seed, initial: true) { _, seed in
            if sessionID == nil { rendering.player.simulation.reseed(seed ?? 0.5, state: nativeState) }
        }
        .onDisappear { player.suspend() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sessionID?.sessionID.provider.stableName ?? "Agent") — \(AgentSessionPresentation.stateLabel(state)), \(type.displayName) avatar")
        .accessibilityAddTraits(.isImage)
    }
}

extension BotAvatarConfiguration {
    var nativeJump: BotAvatarJumpConfig {
        var jump = BotAvatarJumpConfig.defaults
        if let a = advanced?.normalized() {
            jump.height = a.jumpHeight*100; jump.time = a.jumpDuration
            jump.stretch = a.squashStretch*8; jump.squash = a.squashStretch*9.2
            jump.spin = a.spin; jump.lean = a.lean; jump.every = a.idleJumpCadence
        }
        let f = (fidelity ?? .init()).normalized()
        jump.squashTime = f.jumpSquashTime; jump.squashEase = BotAvatarSquashEase(rawValue: f.jumpSquashEase)!
        jump.groundTime = f.jumpGroundTime; jump.groundEase = BotAvatarSquashEase(rawValue: f.jumpGroundEase)!
        jump.riseTime = f.jumpRiseTime; jump.riseEase = BotAvatarSquashEase(rawValue: f.jumpRiseEase)!
        jump.clickSquashTime = f.jumpClickSquashTime; jump.land = f.jumpLand
        return jump
    }

    func nativeDraw(type: LibrariesNative.BotAvatarType) -> BotAvatarDrawConfig {
        let f = (fidelity ?? .init()).normalized()
        let stockBrightness: Double = type == .clover ? 1.2 : type == .star ? 1.1 : type == .cat ? 1.22 : 1
        let stockSaturation: Double = type == .clover ? 1.59 : type == .star ? 1.84 : type == .cat ? 1.88 : 1.5
        let body = (f.bodyColorHex.flatMap(BotColor.init) ?? type.paletteColor).adjusted(brightness: brightness*stockBrightness, saturation: saturation+stockSaturation-1.5)
        var cfg = BotAvatarDrawConfig(type: type, face: LibrariesNative.BotAvatarFace(rawValue: face.rawValue), color: body, ink: f.inkColorHex.flatMap(BotColor.init))
        cfg.shading = LibrariesNative.BotAvatarShading(rawValue: shading.rawValue)!
        cfg.light = shading == .fabric ? 295 : 300
        if shading == .fabric { cfg.shadow = 1.15; cfg.highlight = 1.45; cfg.rim = 0.6; cfg.spread = 1.6 }
        if let a = advanced?.normalized() {
            cfg.shadow = a.shadow*2; cfg.highlight = a.highlight*3; cfg.light = a.lightAngle
            cfg.rim = a.rimLight*2; cfg.spread = a.spread*1.55; cfg.depth = a.depth*0.65
            cfg.roundness = a.roundness
            cfg.fur = BotAvatarFur(length: a.furLength*8, density: a.density*3.2, fuzz: a.fuzz*2.6, clumps: a.clumping*1.6, curl: a.curl*2.8, gravity: a.gravity*2.25)
        }
        cfg.backLight = f.backLight; cfg.lightFront = f.lightFront; cfg.shine = f.shine; cfg.sheen = f.sheen; cfg.backSoftness = f.backSoftness
        cfg.wear = BotAvatarWear(hat: hat.rawValue, glasses: glasses.rawValue, headphones: headphones, bowTie: bowTie, color: BotColor(accessoryColorHex) ?? .darkInk)
        cfg.whirl = BotAvatarWhirl(strength: whirl, size: f.whirlSize, width: f.whirlWidth, length: f.whirlLength, tilt: f.whirlTilt)
        if let custom = f.customBodyPath {
            let path = botAvatarCGPath(custom)
            if !path.isEmpty && path.boundingBox.width > 0 && path.boundingBox.height > 0 {
                cfg.path = Path(path); cfg.cgPath = path; cfg.parts = nil; cfg.partsCGPath = nil; cfg.typeKey = custom
            }
        }
        return cfg
    }
}

private struct NativeAvatarContainment: ViewModifier {
    let compact: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if compact { content.clipped() } else { content }
    }
}
