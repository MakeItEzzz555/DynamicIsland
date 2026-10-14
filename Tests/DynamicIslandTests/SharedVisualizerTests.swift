import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class SharedVisualizerTests: XCTestCase {
    func testMicrophoneMeterIsBoundedSilentAndResponsiveWithoutFabricatedBands() {
        XCTAssertEqual(MicrophoneBarMapper.levels(level: 0, barCount: 12), SpectrumBarMapper.silent(barCount: 12))
        for bad in [Double.nan, .infinity, -.infinity, -5, 5] {
            XCTAssertTrue(MicrophoneBarMapper.levels(level: bad, barCount: 7).allSatisfy { $0.isFinite && (0.12...1).contains($0) })
        }
        XCTAssertEqual(MicrophoneBarMapper.levels(level: 1, barCount: 0), [])
        let low = MicrophoneBarMapper.levels(level: 0.1, barCount: 12)
        let high = MicrophoneBarMapper.levels(level: 0.9, barCount: 12)
        XCTAssertTrue(zip(low, high).allSatisfy { $0 < $1 })
    }

    func testRecorderAttackAndReleaseRemainFrameRateIndependent() {
        let config = VoiceBeamConfiguration()
        let envelope = VoiceBeamEnvelope()
        _ = envelope.sample(rawLevel: 0, timestamp: 0, configuration: config)
        let attack = envelope.sample(rawLevel: 1, timestamp: 0.1, configuration: config)
        let release = envelope.sample(rawLevel: 0, timestamp: 0.2, configuration: config)
        XCTAssertGreaterThan(attack, 0); XCTAssertGreaterThan(release, 0)
        XCTAssertLessThan(release, attack)
        envelope.reset(); XCTAssertEqual(envelope.value, 0)
    }

    func testOneNativeRendererAcceptsEveryPaletteAndReduceMotionMeterUpdates() throws {
        _ = NSApplication.shared
        func raster(_ level: Double, palette: AudioVisualizerPalette) throws -> Data {
            let view = AudioVisualizerBars(levels: MicrophoneBarMapper.levels(level: level, barCount: 12),
                variant: .expanded, palette: palette, accent: .cyan, secondary: nil)
                .environment(\.settingsPreviewReduceMotion, true)
            let host = NSHostingView(rootView: view); host.frame = CGRect(x: 0, y: 0, width: 76, height: 28)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        for palette in [AudioVisualizerPalette.media, .call, .voice] {
            XCTAssertNotEqual(try raster(0.1, palette: palette), try raster(0.9, palette: palette))
        }
    }
}
