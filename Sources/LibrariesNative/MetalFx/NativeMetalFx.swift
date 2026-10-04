// MIT © 2026 Jakub Antalik. MetalFxKit macOS adaptation: native GPU host, pointer input and lifecycle.
import SwiftUI

public final class MetalFxModel: ObservableObject {
    let clock = MetalInstanceClock()
    let bend = MetalBendModel()
    let glow = MetalGlowState()
    var pointer = CGVector.zero
    var size = CGSize.zero
    var cornerRadius: CGFloat = 0
    var ringWidth: CGFloat = 2
    var kind: MetalShapeKind = .circle
    var material = MetalMaterial.base
    var opacityMul: Float = 1
    var shaderScale: Float = 1.3
    var isSheet = false
    public init() {}
    public func setPointer(_ value: CGVector) { pointer = value }
    public func setPaused(_ paused: Bool, now: TimeInterval) { clock.setPaused(paused, now: now); if paused { pointer = .zero; bend.reset() } }
    func time(now: TimeInterval) -> Double { clock.time(now: now) }
}
public enum MetalFxVariant: Sendable { case button, circle }

public struct NativeMetalFx: View {
    public var model: MetalFxModel
    public var preset: MetalPreset
    public var strength: Double
    public var innerShadow: Bool
    public var glow: Bool
    public var glowGain: Double
    public var paused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    public init(model: MetalFxModel, preset: MetalPreset, strength: Double, innerShadow: Bool, glow: Bool, glowGain: Double, paused: Bool) {
        self.model = model; self.preset = preset; self.strength = strength; self.innerShadow = innerShadow; self.glow = glow; self.glowGain = glowGain; self.paused = paused
    }
    public var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: paused)) { ctx in
                if geometry.size.width.isFinite && geometry.size.height.isFinite && geometry.size.width > 0 && geometry.size.height > 0 {
                MetalFxFrame(model: model, now: ctx.date.timeIntervalSinceReferenceDate, size: geometry.size,
                    variant: .circle, material: .preset(preset, theme: scheme == .dark ? .dark : .light), theme: scheme == .dark ? .dark : .light,
                    strength: min(1, max(0, strength)), shaderScale: 1.3, ringWidth: 2, cornerRadius: nil,
                    innerShadow: innerShadow, glow: glow, glowGain: glowGain, tilt: !paused, bendConfig: .default, glowConfig: .default, fill: nil, displayScale: displayScale)
                }
            }
        }
        .onChange(of: paused, initial: true) { _, value in model.setPaused(value, now: Date().timeIntervalSinceReferenceDate) }
        .onDisappear { model.setPaused(true, now: Date().timeIntervalSinceReferenceDate) }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
/// One frame of the ring's layers (fill, band, hairline, rim, glow, inner
/// shadow), in the box's coordinates. Overflows the box on purpose: the halo
/// and a bent band reach past it.
struct MetalFxFrame: View {
    let model: MetalFxModel
    let now: TimeInterval
    let size: CGSize
    let variant: MetalFxVariant
    let material: MetalMaterial
    let theme: MetalResolvedTheme
    let strength: Double
    let shaderScale: Float
    let ringWidth: CGFloat
    let cornerRadius: CGFloat?
    let innerShadow: Bool
    let glow: Bool
    let glowGain: Double
    let tilt: Bool
    let bendConfig: MetalBendConfig
    let glowConfig: MetalGlowConfig
    let fill: Color?
    let displayScale: CGFloat

    var body: some View {
        let radius = min(cornerRadius ?? .infinity, min(size.width, size.height) / 2)
        let kind = MetalGeometry.kind(size: size, radius: radius)
        let t = model.time(now: now)
        let box = CGRect(origin: .zero, size: size)

        // Bend: tilt → field → outline displacement.
        let tiltV = tilt ? model.pointer : .zero
        let field = tilt ? model.bend.step(now: now, tilt: tiltV, size: size, radius: radius, cfg: bendConfig) : nil
        let deform: MetalDeform? = field.map { f in { f.deform($0) } }

        let outer = MetalGeometry.roundRectOutline(box, radius: radius, deform: deform)
        let inner = MetalGeometry.roundRectOutline(box.insetBy(dx: ringWidth, dy: ringWidth), radius: max(0, radius - ringWidth), deform: deform)
        let outerPath = MetalGeometry.path(outer)
        let bandPath = MetalGeometry.bandPath(outer: outer, inner: inner)
        let rimW: CGFloat = variant == .circle ? 2 : 1
        let rimInner = MetalGeometry.roundRectOutline(box.insetBy(dx: rimW, dy: rimW), radius: max(0, radius - rimW), deform: deform)
        let rimPath = MetalGeometry.bandPath(outer: outer, inner: rimInner)

        let mapping = MetalSheetMapping(size: size, shaderScale: shaderScale)
        let opacityMul = Float(strength) * material.shaderOpacity
        let margin = ceil(field?.reach ?? 0)
        let sheetSize = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        let sheetMapping = MetalSheetMapping(origin: mapping.origin - SIMD2<Float>(repeating: Float(margin)) * mapping.scale, scale: mapping.scale)
        let parameters = MetalSheetParameters(size: sheetSize, mapping: sheetMapping, material: material, time: t, opacity: opacityMul, displayScale: displayScale)

        let surface = fill ?? (theme == .dark ? Color(red: 0x27 / 255.0, green: 0x27 / 255.0, blue: 0x27 / 255.0) : .white)
        let rimColor = theme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)

        // Keep the anchor snapshot current for reflections / the edge halo.
        let _ = {
            model.size = size; model.cornerRadius = radius; model.ringWidth = ringWidth; model.kind = kind
            model.material = material; model.opacityMul = opacityMul; model.shaderScale = shaderScale; model.isSheet = false
        }()

        ZStack(alignment: .topLeading) {
            outerPath.fill(surface)
            NativeMetalSheet(parameters: parameters)
                .frame(width: sheetSize.width, height: sheetSize.height)
                .mask { bandPath.offsetBy(dx: margin, dy: margin).fill(.white, style: FillStyle(eoFill: true)) }
                .offset(x: -margin, y: -margin)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            if variant == .circle && theme == .dark {
                // The circle variant's dark hairline just outside the box.
                MetalGeometry.path(MetalGeometry.roundRectOutline(box.insetBy(dx: -0.5, dy: -0.5), radius: radius + 0.5, deform: deform))
                    .stroke(Color.black.opacity(0.45), lineWidth: 1)
            }
            rimPath.fill(rimColor, style: FillStyle(eoFill: true))
            if glow {
                glowLayer(mapping: mapping, t: t, radius: radius, kind: kind, deform: deform, bandPath: bandPath)
            }
            if innerShadow {
                MetalRimLayer(options: .default) { bandPath.fill(.white, style: FillStyle(eoFill: true)) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func glowLayer(mapping: MetalSheetMapping, t: Double, radius: CGFloat, kind: MetalShapeKind, deform: MetalDeform?, bandPath: Path) -> some View {
        let cfg = glowConfig
        let _ = model.glow.configure(size: size, radius: radius, kind: kind, cfg: cfg)
        let mat = material
        let tf = Float(t)
        let sampler = MetalGlowSampler(
            luminance: { p in mat.luminance(uv: mapping.uv(p), time: tf) },
            rgb: { p in mat.sample(uv: mapping.uv(p), time: tf) }
        )
        let frame = model.glow.tick(nowMs: t * 1000, sampler: sampler, strength: strength * glowGain, theme: theme, deform: deform, cfg: cfg)
        if let frame {
            let ratio = Double(MetalGeometry.shapePerim(size.width, size.height, radius, kind) / MetalGeometry.rrPerim(140, 40, 20))
            let halo = MetalGlowSprites.halo(halfLen: max(1, cfg.haloHalfLen * ratio), s: 1, scale: displayScale, cfg: cfg)
            let extra = MetalGlowSprites.extra(halfLen: max(0.6, cfg.extraHalfLen * ratio), s: 1, scale: displayScale, cfg: cfg)
            let margin: CGFloat = 48
            MetalGlowLayer(frame: frame, halo: halo, extra: extra, theme: theme, small: kind == .circle && min(size.width, size.height) <= 44, size: size, margin: margin) {
                ZStack(alignment: .topLeading) {
                    Color.white.opacity(0.5)
                    bandPath.offsetBy(dx: margin, dy: margin).fill(.white, style: FillStyle(eoFill: true))
                }
            }
        }
    }
}
