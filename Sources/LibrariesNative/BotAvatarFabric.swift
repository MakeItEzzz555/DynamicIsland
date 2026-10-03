import CoreGraphics
import SwiftUI

/// Stock values from the browser fabric shader. Fibres are baked once into a
/// bounded native texture; the moving pillow's light is evaluated underneath.
public struct BotAvatarFur: Hashable {
    public var length: Double, density: Double, fuzz: Double, clumps: Double, curl: Double, gravity: Double
    public init(length: Double = 1, density: Double = 1.6, fuzz: Double = 0.9, clumps: Double = 0.4, curl: Double = 0.7, gravity: Double = 0.9) {
        self.length=length; self.density=density; self.fuzz=fuzz; self.clumps=clumps; self.curl=curl; self.gravity=gravity
    }
}

private struct FurKey: Hashable { var outline: String; var fur: BotAvatarFur; var color: BotColor; var light: Double; var highlight: Double }
private var textures: [FurKey: Image] = [:]
private var textureOrder: [FurKey] = []
private let textureSide = 192

func drawFabric(_ ctx: inout GraphicsContext, cfg: BotAvatarDrawConfig, pose: BotAvatarPose, body: CGAffineTransform) {
    let key = FurKey(outline: cfg.typeKey, fur: cfg.fur, color: cfg.color, light: cfg.light, highlight: cfg.highlight)
    let image: Image
    if let existing = textures[key] { image = existing }
    else {
        guard let cg = bakeFibres(cfg) else { return }
        image = Image(decorative: cg, scale: 1).interpolation(.high)
        if textureOrder.count >= 24 { textures.removeValue(forKey: textureOrder.removeFirst()) }
        textures[key] = image; textureOrder.append(key)
    }
    let cy = cos(pose.yaw), sy = sin(pose.yaw), cp = cos(pose.pitch), sp = sin(pose.pitch)
    let facing = cy*cp
    var c = ctx
    // Match the cap's turn and pillow projection, including the back of a spin.
    let cap = max(0.65, 1-0.1*cfg.rim*cfg.roundness)
    let depth = 15*cfg.depth*(facing >= 0 ? 1.0 : -1.0)
    c.transform = CGAffineTransform(a: cy*cap, b: sy*sp*cap, c: 0, d: cp*cap, tx: sy*depth-50*cy*cap, ty: -cy*sp*depth-50*sy*sp*cap-50*cp*cap).concatenating(body)
    c.draw(image, in: CGRect(x: -8, y: -8, width: 116, height: 116))
}

func bakeFibres(_ cfg: BotAvatarDrawConfig) -> CGImage? {
    guard let c = CGContext(data: nil, width: textureSide, height: textureSide, bitsPerComponent: 8, bytesPerRow: textureSide*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // Bitmap rows and SwiftUI image coordinates have opposite vertical axes.
    // Match the design path rather than reflecting the pile outside asymmetric bodies.
    c.translateBy(x: 0, y: Double(textureSide)); c.scaleBy(x: 1, y: -1)
    c.scaleBy(x: Double(textureSide)/116, y: Double(textureSide)/116)
    c.translateBy(x: 8, y: 8)
    c.setLineCap(.round)
    let f = cfg.fur
    var rng = Mulberry32(seed: 731_009)
    let count = min(32000, max(0, Int(10000*f.density)))
    let la = cfg.light * .pi/180, lx=sin(la), ly = -cos(la)
    for _ in 0..<count {
        var x=rng.next()*100, y=rng.next()*100
        // Tufts share a combing direction and anchor; fuzz breaks the regularity.
        let spacing = 2.5+f.clumps*3
        let comb = sin(x/spacing*1.7+y/spacing*0.9)*f.clumps
        x += comb*0.7; y += cos(x/spacing*0.8-y/spacing)*f.clumps*0.5
        guard cfg.cgPath.contains(CGPoint(x:x,y:y)) else { continue }
        let rx = x-50, ry = y+6
        let reach = max(1, hypot(rx, ry))
        let fall = f.gravity*(1-0.6*exp(-reach/8))
        let radial = atan2(ry/reach*(1-0.8*fall)+fall, rx/reach*(1-0.8*fall))
        let jitter = (rng.next()-0.5)*f.fuzz*1.8
        let angle = radial+jitter
        let edgeX = (cfg.cgPath.contains(CGPoint(x:x-0.8,y:y)) ? 1.0 : 0) - (cfg.cgPath.contains(CGPoint(x:x+0.8,y:y)) ? 1.0 : 0)
        let edgeY = (cfg.cgPath.contains(CGPoint(x:x,y:y-0.8)) ? 1.0 : 0) - (cfg.cgPath.contains(CGPoint(x:x,y:y+0.8)) ? 1.0 : 0)
        let edge = edgeX != 0 || edgeY != 0
        let length = (0.45+rng.next()*0.9)*f.length*(edge ? 1+f.fuzz : 1)
        let dx=(edge ? edgeX*0.7+cos(angle)*0.3 : cos(angle))*length, dy=(edge ? edgeY*0.4+sin(angle)*0.6 : sin(angle))*length+f.gravity*0.5*length
        let bend = (rng.next()-0.5)*f.curl*length
        let lit = max(-1,min(1,cos(angle)*lx+sin(angle)*ly))
        let light = lit*(0.06+0.035*cfg.highlight)+(rng.next()-0.5)*0.14
        let ink = cfg.color.shade(light)
        c.setStrokeColor(red: ink.r/255, green: ink.g/255, blue: ink.b/255, alpha: (edge ? 0.45 : 0.18)+0.16*rng.next())
        c.setLineWidth(0.20+0.08*rng.next())
        c.move(to: CGPoint(x:x,y:y))
        c.addCurve(to: CGPoint(x:x+dx,y:y+dy), control1: CGPoint(x:x+dx*0.32-dy*bend,y:y+dy*0.32+dx*bend), control2: CGPoint(x:x+dx*0.72+dy*bend,y:y+dy*0.72-dx*bend))
        c.strokePath()
    }
    return c.makeImage()
}

public enum BotAvatarFabricDiagnostics {
    public static var textureCount: Int { textures.count }
    public static var maximumTextureBytes: Int { 24*textureSide*textureSide*4 }
}
