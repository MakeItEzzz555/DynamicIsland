import SwiftUI

/// Attached native vector approximation of the reference's lit accessory meshes.
/// Accessories use the same pose, extrusion depth and body transform as the head.
public struct BotAvatarWear {
    public var hat: String, glasses: String
    public var headphones: Bool, bowTie: Bool
    public var color: BotColor
    public init(hat: String = "none", glasses: String = "none", headphones: Bool = false, bowTie: Bool = false, color: BotColor = .darkInk) {
        self.hat=hat; self.glasses=glasses; self.headphones=headphones; self.bowTie=bowTie; self.color=color
    }
}
private var seats: [String: Double] = [:]

func drawWear(_ ctx: inout GraphicsContext, cfg: BotAvatarDrawConfig, pose: BotAvatarPose, body: CGAffineTransform, behind: Bool) {
    let wear=cfg.wear
    if wear.hat == "none" && wear.glasses == "none" && !wear.headphones && !wear.bowTie { return }
    let cy=cos(pose.yaw), sy=sin(pose.yaw), cp=cos(pose.pitch), sp=sin(pose.pitch)
    var c=ctx
    func plane(_ z: Double) -> CGAffineTransform {
        CGAffineTransform(a:cy,b:sy*sp,c:0,d:cp,tx:sy*z,ty: -cy*sp*z).concatenating(body)
    }
    c.transform = plane(behind ? -12 : 17*cfg.depth)
    let light=wear.color.shade(0.18), dark=wear.color.shade(-0.15)
    let fill=GraphicsContext.Shading.linearGradient(Gradient(colors:[light.color,wear.color.color,dark.color]),startPoint:CGPoint(x:-24,y:-40),endPoint:CGPoint(x:28,y:20))
    func solid(_ p: Path) { c.fill(p, with: fill); c.stroke(p, with:.color(light.withAlpha(0.4)),lineWidth:0.6) }
    func line(_ p: Path, width: Double) { c.stroke(p,with:.color(wear.color.color),style:StrokeStyle(lineWidth:width,lineCap:.round,lineJoin:.round)) }
    if behind {
        if wear.headphones {
            var p=Path(); p.move(to:CGPoint(x:-39,y:2));p.addCurve(to:CGPoint(x:39,y:2),control1:CGPoint(x:-43,y:-63),control2:CGPoint(x:43,y:-63));line(p,width:5)
        }
        return
    }
    guard cy*cp > -0.15 else { return }
    if wear.headphones {
        for x in [-40.0,32] { solid(Path(roundedRect:CGRect(x:x,y:-12,width:8,height:24),cornerRadius:4)) }
    }
    if wear.hat != "none" {
        let seat: Double
        if let cached=seats[cfg.typeKey] { seat=cached }
        else {
            seat = Double((0..<70).first { y in cfg.cgPath.contains(CGPoint(x:35,y:y)) && cfg.cgPath.contains(CGPoint(x:65,y:y)) } ?? 15)-50
            if seats.count >= 64 { seats.removeAll() };seats[cfg.typeKey]=seat
        }
        switch wear.hat {
        case "beret":
            solid(Path(ellipseIn:CGRect(x:-27,y:seat-15,width:56,height:20)))
            solid(Path(roundedRect:CGRect(x:-3,y:seat-19,width:4,height:7),cornerRadius:2))
        case "beanie":
            solid(Path(roundedRect:CGRect(x:-24,y:seat-25,width:48,height:30),cornerRadius:17))
            solid(Path(roundedRect:CGRect(x:-26,y:seat-4,width:52,height:9),cornerRadius:3))
            solid(Path(ellipseIn:CGRect(x:-5,y:seat-32,width:10,height:10)))
            for x in stride(from:-18.0,through:18,by:6) { var p=Path();p.move(to:CGPoint(x:x,y:seat-19));p.addLine(to:CGPoint(x:x,y:seat-6));c.stroke(p,with:.color(light.withAlpha(0.4)),lineWidth:0.6) }
        case "party":
            var p=Path();p.move(to:CGPoint(x:-21,y:seat+1));p.addLine(to:CGPoint(x:4,y:seat-40));p.addLine(to:CGPoint(x:24,y:seat+1));p.closeSubpath();solid(p)
            for (x,y) in [(-8.0,-5.0),(6,-17),(11,-3),(1,-28)] { c.fill(Path(ellipseIn:CGRect(x:x,y:seat+y,width:4,height:4)),with:.color(light.color)) }
            solid(Path(ellipseIn:CGRect(x:0,y:seat-45,width:8,height:8)))
        case "crown":
            var p=Path();p.move(to:CGPoint(x:-25,y:seat-2))
            for q in [CGPoint(x:-28,y:seat-23),CGPoint(x:-13,y:seat-12),CGPoint(x:0,y:seat-29),CGPoint(x:13,y:seat-12),CGPoint(x:28,y:seat-23),CGPoint(x:25,y:seat+1)] { p.addLine(to:q) }
            p.closeSubpath();solid(p)
            for x in [-13.0,0,13] { c.fill(Path(ellipseIn:CGRect(x:x-2,y:seat-5,width:4,height:4)),with:.color(light.color)) }
        default: break
        }
    }
    if wear.glasses != "none" {
        // Face placement and scaling follow each body's own preset.
        c.transform = CGAffineTransform(a:cfg.faceScale,b:0,c:0,d:cfg.faceScale,tx:cfg.faceX-50,ty:cfg.faceY-49).concatenating(plane(18*cfg.depth))
        for x in [-25.0,3] {
            let r=CGRect(x:x,y:-10,width:22,height:18)
            let p=wear.glasses == "round" ? Path(ellipseIn:r) : Path(roundedRect:r,cornerRadius:wear.glasses == "shades" ? 4 : 2)
            if wear.glasses == "shades" { c.fill(p,with:.color(wear.color.color));c.stroke(p,with:.color(light.color),lineWidth:0.8) }
            else { c.fill(p,with:.color(Color.white.opacity(0.08)));line(p,width:2.3) }
        }
        var bridge=Path();bridge.move(to:CGPoint(x:-3,y:-3));bridge.addQuadCurve(to:CGPoint(x:3,y:-3),control:CGPoint(x:0,y:-6));line(bridge,width:2)
    }
    if wear.bowTie {
        c.transform = plane(18*cfg.depth)
        let y=min(40,cfg.faceY-50+28)
        var p=Path();p.move(to:CGPoint(x:0,y:y));p.addLine(to:CGPoint(x:-14,y:y-9));p.addQuadCurve(to:CGPoint(x:-14,y:y+9),control:CGPoint(x:-17,y:y));p.closeSubpath();solid(p)
        p=Path();p.move(to:CGPoint(x:0,y:y));p.addLine(to:CGPoint(x:14,y:y-9));p.addQuadCurve(to:CGPoint(x:14,y:y+9),control:CGPoint(x:17,y:y));p.closeSubpath();solid(p)
        solid(Path(roundedRect:CGRect(x:-3,y:y-4,width:6,height:8),cornerRadius:2))
    }
}
