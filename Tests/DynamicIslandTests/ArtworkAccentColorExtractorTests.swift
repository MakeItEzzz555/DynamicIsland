import AppKit
import XCTest
@testable import DynamicIsland

final class ArtworkAccentColorExtractorTests: XCTestCase {
    func testDominantColorIgnoresBlackWhiteAndTransparentSamples() throws {
        let color = ArtworkAccentColorExtractor.dominantColor(from: [
            ArtworkColorSample(red: 0.01, green: 0.01, blue: 0.01, alpha: 1),
            ArtworkColorSample(red: 0.98, green: 0.98, blue: 0.98, alpha: 1),
            ArtworkColorSample(red: 1, green: 0, blue: 0, alpha: 0.1),
            ArtworkColorSample(red: 0.08, green: 0.62, blue: 0.80, alpha: 1),
            ArtworkColorSample(red: 0.10, green: 0.58, blue: 0.76, alpha: 1)
        ])

        let components = components(of: try XCTUnwrap(color))
        XCTAssertGreaterThan(components.blue, components.red)
        XCTAssertGreaterThan(components.green, components.red)
    }

    func testDominantColorReturnsNilForOnlyUnusableSamples() {
        let color = ArtworkAccentColorExtractor.dominantColor(from: [
            ArtworkColorSample(red: 0, green: 0, blue: 0, alpha: 1),
            ArtworkColorSample(red: 1, green: 1, blue: 1, alpha: 1),
            ArtworkColorSample(red: 0.8, green: 0.1, blue: 0.1, alpha: 0.1)
        ])

        XCTAssertNil(color)
    }

    @MainActor
    func testAccentColorCacheStoresExtractedColorForArtworkKey() async {
        let cache = ArtworkAccentColorCache()
        let image = solidImage(color: .systemBlue)

        _ = cache.color(for: "test-artwork", image: image)
        for _ in 0..<20 where !cache.containsColor(for: "test-artwork") {
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertTrue(cache.containsColor(for: "test-artwork"))
    }

    private func components(of color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        return (converted.redComponent, converted.greenComponent, converted.blueComponent)
    }

    private func solidImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
}
