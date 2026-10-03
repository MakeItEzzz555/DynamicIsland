import Foundation
import SwiftUI
import AppKit

/// A body or ink colour, as the web library keeps it: sRGB channels 0–255,
/// and — for a shade made by `shade(_:_:)` — the hsl numbers it was written
/// with (rounded to a tenth, as the web's `hsl()` strings are), so every
/// derived colour comes out to the same channel values as on the web.
public struct BotColor: Hashable, Sendable {
    /// sRGB, 0–255 (not rounded).
    public let r: Double, g: Double, b: Double
    /// h in degrees, s and l in percent, each rounded to a tenth; only for
    /// colours produced by `shade`.
    let hsl: HSL?

    struct HSL: Hashable, Sendable { var h: Double, s: Double, l: Double }

    public init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b; self.hsl = nil
    }
    init(hsl: HSL) {
        self.hsl = hsl
        let c = hslToRgb(hsl.h / 360, hsl.s / 100, hsl.l / 100)
        r = c.0; g = c.1; b = c.2
    }

    /// Parse `#rgb` / `#rrggbb` / `rgb(r g b)` / `hsl(h s% l%)`; nil for anything else.
    public init?(_ css: String) {
        guard let c = parseColor(css) else { return nil }
        self.init(r: c.0, g: c.1, b: c.2)
    }

    /// From a SwiftUI colour, resolved in sRGB.
    public init(_ color: Color) {
        let ui = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        do {
            self.init(r: Double(r) * 255, g: Double(g) * 255, b: Double(b) * 255)
        }
    }

    /// The colour as SwiftUI sees it.
    public var color: Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1) }
    public func withAlpha(_ a: Double) -> Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: max(0, min(1, a))) }

    /// Relative luminance (WCAG), 0–1.
    public var luminance: Double {
        func lin(_ v: Double) -> Double {
            let x = v / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public static let darkInk = BotColor("#1E1A33")!
    public static let lightInk = BotColor("#F7F5F2")!

    /// Face ink for a body colour: dark ink, or light ink on a dark body.
    public var autoInk: BotColor { luminance < 0.13 ? .lightInk : .darkInk }

    /// A shade of the colour: `dl` moves the lightness (−1..1), `ds` the
    /// saturation. Darker shades get a touch more saturation so they stay
    /// rich instead of going grey, the way a painted surface falls into shadow.
    public func shade(_ dl: Double, _ ds: Double = 0) -> BotColor {
        let (h, s, l) = rgbToHsl(r, g, b)
        let ns = clamp01(s + ds + (dl < 0 ? -dl * 0.25 : 0)), nl = clamp01(l + dl)
        return BotColor(hsl: HSL(h: tenth(h * 360), s: tenth(ns * 100), l: tenth(nl * 100)))
    }

    /// The hsl numbers the web's `hslNums` reads: the colour's own if it is
    /// a shade, else those of `shade(0)`.
    var hslNums: HSL { hsl ?? shade(0).hsl! }

    /// Interpolate the hsl numbers (the web's `mixCss`).
    public func mix(_ other: BotColor, _ t: Double) -> BotColor {
        let a = hslNums, b = other.hslNums
        return BotColor(hsl: HSL(h: tenth(a.h + (b.h - a.h) * t), s: tenth(a.s + (b.s - a.s) * t), l: tenth(a.l + (b.l - a.l) * t)))
    }

    /// Linear-light channels, 0–1.
    var linear: SIMD3<Double> {
        func toLin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return SIMD3(toLin(r / 255), toLin(g / 255), toLin(b / 255))
    }
}

/// JavaScript's `toFixed(1)` on a non-negative number, as a value.
private func tenth(_ v: Double) -> Double { (v * 10).rounded() / 10 }
private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

/// Parse #rgb / #rrggbb / rgb() / hsl() into 0–255 channels; nil for anything else.
func parseColor(_ input: String) -> (Double, Double, Double)? {
    let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let m = s.firstMatch(of: #/^hsla?\(\s*([\d.]+)(?:deg)?[,\s]+([\d.]+)%[,\s]+([\d.]+)%/#.ignoresCase()) {
        let c = hslToRgb((Double(m.1) ?? 0) / 360, (Double(m.2) ?? 0) / 100, (Double(m.3) ?? 0) / 100)
        return (c.0, c.1, c.2)
    }
    if let m = s.firstMatch(of: #/^#([0-9a-f]{3}|[0-9a-f]{6})$/#.ignoresCase()) {
        var h = String(m.1)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let n = Int(h, radix: 16) ?? 0
        return (Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255))
    }
    if let m = s.firstMatch(of: #/^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)/#.ignoresCase()) {
        return (Double(m.1) ?? 0, Double(m.2) ?? 0, Double(m.3) ?? 0)
    }
    return nil
}

func rgbToHsl(_ r0: Double, _ g0: Double, _ b0: Double) -> (Double, Double, Double) {
    let r = r0 / 255, g = g0 / 255, b = b0 / 255
    let mx = max(r, g, b), mn = min(r, g, b)
    let l = (mx + mn) / 2
    if mx == mn { return (0, 0, l) }
    let d = mx - mn
    let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
    var h = 0.0
    if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
    else if mx == g { h = (b - r) / d + 2 }
    else { h = (r - g) / d + 4 }
    return (h / 6, s, l)
}

func hslToRgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
    if s == 0 { return (l * 255, l * 255, l * 255) }
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    func f(_ t0: Double) -> Double {
        let t = ((t0.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
        if t < 1.0 / 6 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2 { return q }
        if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
        return p
    }
    return (f(h + 1.0 / 3) * 255, f(h) * 255, f(h - 1.0 / 3) * 255)
}

public extension BotColor {
    func adjusted(brightness: Double, saturation: Double) -> BotColor {
        let shaded = brightness == 1 && saturation == 1 ? self : shade((min(2,max(0,brightness))-1)*0.35, (min(1.5,max(0,saturation))-1)*0.5)
        return shaded.richer(max(0,min(2.5,saturation)-1.5))
    }
    // Reference OKLab chroma boost, including the gamut/lightness search.
    func richer(_ t: Double) -> BotColor {
        let c = linear
        let l = cbrt(0.4122214708*c[0]+0.5363325363*c[1]+0.0514459929*c[2])
        let m = cbrt(0.2119034982*c[0]+0.6806995451*c[1]+0.1073969566*c[2])
        let s = cbrt(0.0883024619*c[0]+0.2817188376*c[1]+0.6299787005*c[2])
        let L = 0.2104542553*l+0.793617785*m-0.0040720468*s
        let a = 1.9779984951*l-2.428592205*m+0.4505937099*s
        let b = 0.0259040371*l+0.7827717662*m-0.808675766*s
        let C = hypot(a,b)
        guard t > 0, C >= 0.0001 else { return self }
        func inverse(_ L: Double, _ a: Double, _ b: Double) -> SIMD3<Double> {
            let l = pow(L+0.3963377774*a+0.2158037573*b,3)
            let m = pow(L-0.1055613458*a-0.0638541728*b,3)
            let s = pow(L-0.0894841775*a-1.291485548*b,3)
            return SIMD3(4.0767416621*l-3.3077115913*m+0.2309699292*s, -1.2684380046*l+2.6097574011*m-0.3413193965*s, -0.0041960863*l-0.7034186147*m+1.707614701*s)
        }
        let ua=a/C, ub=b/C, want=C*(1+0.5*t)
        var best: SIMD3<Double>?; var bestC=C
        for k in 0...6 {
            let Lk=L*(1-0.15*t*Double(k)/6)
            var lo=0.0, hi=want
            for _ in 0..<18 {
                let mid=(lo+hi)/2, rgb=inverse(Lk,ua*mid,ub*mid)
                if (0..<3).allSatisfy({ rgb[$0] >= -0.0001 && rgb[$0] <= 1.0001 }) { lo=mid } else { hi=mid }
            }
            if lo > bestC+0.004*Double(k) { bestC=lo; best=inverse(Lk,ua*lo,ub*lo) }
            if lo >= want-0.0001 { break }
        }
        guard let best else { return self }
        func srgb(_ x: Double) -> Double { let x=min(1,max(0,x)); return (255*(x <= 0.0031308 ? 12.92*x : 1.055*pow(x,1/2.4)-0.055)).rounded() }
        return BotColor(r:srgb(best[0]),g:srgb(best[1]),b:srgb(best[2]))
    }
}
