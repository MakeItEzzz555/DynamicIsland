import AppKit
import SwiftUI

struct ArtworkColorSample: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

enum ArtworkAccentColorExtractor {
    static let fallbackColor = Color.white.opacity(0.72)

    static func dominantColor(from image: NSImage) -> NSColor? {
        guard let samples = downsampledSamples(from: image, size: 24), !samples.isEmpty else {
            return nil
        }
        return dominantColor(from: samples)
    }

    static func dominantColor(from samples: [ArtworkColorSample]) -> NSColor? {
        let vibrant = samples.filter(isVibrantCandidate)
        let candidates = vibrant.isEmpty ? samples.filter(isUsableFallbackCandidate) : vibrant
        guard !candidates.isEmpty else { return nil }

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var totalWeight = 0.0

        for sample in candidates {
            let saturation = saturation(red: sample.red, green: sample.green, blue: sample.blue)
            let brightness = brightness(red: sample.red, green: sample.green, blue: sample.blue)
            let weight = max(0.15, saturation) * sample.alpha * (0.65 + brightness * 0.35)
            red += sample.red * weight
            green += sample.green * weight
            blue += sample.blue * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }
        return NSColor(
            calibratedRed: red / totalWeight,
            green: green / totalWeight,
            blue: blue / totalWeight,
            alpha: 1
        )
    }

    static let sampleGridSize = 24

    /// A second, visibly different color for the bar gradient: the dominant
    /// color of whichever artwork half differs most from `primary`. Grayscale
    /// art gets a tonal partner; colors that are too close are hue-shifted.
    static func secondaryColor(from image: NSImage, primary: NSColor) -> NSColor? {
        guard let samples = downsampledSamples(from: image, size: sampleGridSize), !samples.isEmpty else { return nil }
        return secondaryColor(from: samples, gridSize: sampleGridSize, primary: primary)
    }

    static func secondaryColor(from samples: [ArtworkColorSample], gridSize: Int, primary: NSColor) -> NSColor? {
        guard gridSize > 1, let base = primary.usingColorSpace(.sRGB) else { return nil }
        let left = samples.enumerated().filter { $0.offset % gridSize < gridSize / 2 }.map(\.element)
        let right = samples.enumerated().filter { $0.offset % gridSize >= gridSize / 2 }.map(\.element)
        let candidates = [left, right].compactMap(dominantColor(from:)).compactMap { $0.usingColorSpace(.sRGB) }
        func distance(_ c: NSColor) -> CGFloat {
            let dr = c.redComponent - base.redComponent, dg = c.greenComponent - base.greenComponent, db = c.blueComponent - base.blueComponent
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
        if base.saturationComponent < 0.12 {
            // Grayscale artwork: a darker tone of the same gray, never a fake hue.
            return NSColor(hue: 0, saturation: 0, brightness: max(0.32, base.brightnessComponent * 0.6), alpha: 1)
        }
        if let best = candidates.max(by: { distance($0) < distance($1) }), distance(best) >= 0.18 {
            return best
        }
        return NSColor(hue: (base.hueComponent + 0.11).truncatingRemainder(dividingBy: 1),
                       saturation: min(1, max(0.35, base.saturationComponent * 1.15)),
                       brightness: max(0.55, base.brightnessComponent), alpha: 1)
    }

    private static func downsampledSamples(from image: NSImage, size: Int) -> [ArtworkColorSample]? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let width = max(1, size)
        let height = max(1, size)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: pixels.count, by: bytesPerPixel).map { offset in
            ArtworkColorSample(
                red: Double(pixels[offset]) / 255.0,
                green: Double(pixels[offset + 1]) / 255.0,
                blue: Double(pixels[offset + 2]) / 255.0,
                alpha: Double(pixels[offset + 3]) / 255.0
            )
        }
    }

    private static func isVibrantCandidate(_ sample: ArtworkColorSample) -> Bool {
        guard sample.alpha > 0.35 else { return false }
        let brightness = brightness(red: sample.red, green: sample.green, blue: sample.blue)
        let saturation = saturation(red: sample.red, green: sample.green, blue: sample.blue)
        return brightness > 0.12 && brightness < 0.92 && saturation > 0.18
    }

    private static func isUsableFallbackCandidate(_ sample: ArtworkColorSample) -> Bool {
        guard sample.alpha > 0.35 else { return false }
        let brightness = brightness(red: sample.red, green: sample.green, blue: sample.blue)
        let saturation = saturation(red: sample.red, green: sample.green, blue: sample.blue)
        return brightness > 0.08 && brightness < 0.95 && saturation > 0.05
    }

    private static func brightness(red: Double, green: Double, blue: Double) -> Double {
        max(red, green, blue)
    }

    private static func saturation(red: Double, green: Double, blue: Double) -> Double {
        let maximum = max(red, green, blue)
        guard maximum > 0 else { return 0 }
        let minimum = min(red, green, blue)
        return (maximum - minimum) / maximum
    }
}

@MainActor
final class ArtworkAccentColorCache: ObservableObject {
    static let shared = ArtworkAccentColorCache()

    @Published private var colorsByKey: [String: Color] = [:]
    @Published private var secondaryByKey: [String: Color] = [:]
    private var inFlightKeys: Set<String> = []

    func color(for artworkKey: String?, image: NSImage?) -> Color {
        guard let artworkKey, let image else {
            return ArtworkAccentColorExtractor.fallbackColor
        }

        if let cached = colorsByKey[artworkKey] {
            return cached
        }

        requestColor(for: artworkKey, image: image)
        return ArtworkAccentColorExtractor.fallbackColor
    }

    /// Gradient partner for `color(for:image:)`; nil until computed or when
    /// there is no artwork (bars stay a single color).
    func secondaryColor(for artworkKey: String?, image: NSImage?) -> Color? {
        guard let artworkKey, image != nil else { return nil }
        return secondaryByKey[artworkKey]
    }

    func containsColor(for artworkKey: String) -> Bool {
        colorsByKey[artworkKey] != nil
    }

    private func requestColor(for artworkKey: String, image: NSImage) {
        guard !inFlightKeys.contains(artworkKey) else { return }
        guard let imageData = image.tiffRepresentation else {
            colorsByKey[artworkKey] = ArtworkAccentColorExtractor.fallbackColor
            return
        }
        inFlightKeys.insert(artworkKey)

        Task.detached(priority: .utility) { [artworkKey, imageData] in
            let decoded = NSImage(data: imageData)
            let primary = decoded.flatMap(ArtworkAccentColorExtractor.dominantColor(from:))
            let color = primary.map(Color.init(nsColor:)) ?? ArtworkAccentColorExtractor.fallbackColor
            let secondary = decoded.flatMap { image in
                primary.flatMap { ArtworkAccentColorExtractor.secondaryColor(from: image, primary: $0) }
            }.map(Color.init(nsColor:))

            await MainActor.run {
                self.colorsByKey[artworkKey] = color
                if let secondary { self.secondaryByKey[artworkKey] = secondary }
                self.inFlightKeys.remove(artworkKey)
            }
        }
    }
}
