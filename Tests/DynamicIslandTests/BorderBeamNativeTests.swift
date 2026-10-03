import XCTest
import CoreGraphics
import Metal
@testable import LibrariesNative

final class BorderBeamNativeTests: XCTestCase {
    func testOfficialPresetRosterAndPalettes() {
        XCTAssertEqual(Set(BeamSize.allCases.map(\.rawValue)), ["md", "sm", "line", "pulse-inner", "pulse-outside"])
        XCTAssertEqual(Set(BeamColorVariant.allCases.map(\.rawValue)), ["colorful", "mono", "ocean", "sunset"])
        for size in BeamSize.allCases {
            XCTAssertNotNil(BeamSpec.shared.sizePresets[size.rawValue])
            for theme in ["light", "dark"] { XCTAssertNotNil(BeamSpec.shared.sizeThemePresets[size.rawValue]?[theme]) }
        }
    }

    func testStrengthNormalization() {
        XCTAssertEqual(BeamRenderPolicy.normalizedStrength(-1), 0)
        XCTAssertEqual(BeamRenderPolicy.normalizedStrength(2), 1)
        XCTAssertEqual(BeamRenderPolicy.normalizedStrength(.nan), 0.7)
        XCTAssertEqual(BeamRenderPolicy.normalizedStrength(.infinity), 0.7)
    }

    func testActivityVisibilityPauseAndReduceMotionStopRendering() {
        XCTAssertTrue(BeamRenderPolicy.animates(active: true, paused: false, visible: true, reduceMotion: false))
        XCTAssertFalse(BeamRenderPolicy.animates(active: false, paused: false, visible: true, reduceMotion: false))
        XCTAssertFalse(BeamRenderPolicy.animates(active: true, paused: true, visible: true, reduceMotion: false))
        XCTAssertFalse(BeamRenderPolicy.animates(active: true, paused: false, visible: false, reduceMotion: false))
        XCTAssertFalse(BeamRenderPolicy.animates(active: true, paused: false, visible: true, reduceMotion: true))
        XCTAssertFalse(BeamRenderPolicy.animates(active: true, paused: false, visible: true, reduceMotion: false, frozen: true))
    }

    func testClockPauseResumePreservesPhaseWithoutCatchUp() {
        var clock = BeamAnimationClock(time: 3)
        XCTAssertEqual(clock.sample(100, paused: false), 3)
        XCTAssertEqual(clock.sample(100.03, paused: false), 3.03, accuracy: 0.00001)
        XCTAssertEqual(clock.sample(100.03, paused: false), 3.03, accuracy: 0.00001)
        XCTAssertEqual(clock.sample(101, paused: true), 3.03, accuracy: 0.00001)
        XCTAssertEqual(clock.sample(200, paused: false), 3.03, accuracy: 0.00001)
        XCTAssertEqual(clock.sample(200.03, paused: false), 3.06, accuracy: 0.00001)
        clock.suspend()
        XCTAssertEqual(clock.sample(900, paused: false), 3.06, accuracy: 0.00001)
    }

    func testSmallAndMediumHaveIndependentNativePresets() {
        let medium = config(size: .md)
        let small = config(size: .sm)
        XCTAssertNotEqual(medium.strokeBlobs, small.strokeBlobs)
        XCTAssertNotEqual(medium.innerBlobs, small.innerBlobs)
        XCTAssertNotEqual(medium.innerShadowBlur, small.innerShadowBlur)
        XCTAssertEqual(medium.strokeBlobs.count % 8, 0)
        XCTAssertEqual(small.strokeBlobs.count % 8, 0)
    }

    func testRotatePhaseAndColorSemantics() {
        let colorful = config(size: .md)
        XCTAssertEqual(colorful.beamAngle(at: 0), 0)
        XCTAssertEqual(colorful.beamAngle(at: colorful.duration), 0, accuracy: 0.000001)
        XCTAssertEqual(colorful.beamAngle(at: colorful.duration / 4), 0.25, accuracy: 0.000001)
        XCTAssertNotEqual(colorful.hueShiftDegrees(at: 0), colorful.hueShiftDegrees(at: 6))
        let mono = config(size: .md, variant: .mono)
        XCTAssertEqual(mono.hueShiftDegrees(at: 6), 0)
    }

    func testOfficialFilterAndBlobEncoding() {
        XCTAssertEqual(BeamColorMatrix.composed(hueDegrees: 0, brightness: 1, saturation: 1), [1, 0, 0, 0, 1, 0, 0, 0, 1])
        let blob = BlobEncoder.simple(rx: 12, ry: 8, cx: 40, cy: 50, color: BeamRGBA(r: 1, g: 0.5, b: 0.25, a: 0.7))
        XCTAssertEqual(blob.count, 14)
        XCTAssertEqual(Array(blob.prefix(4)), [12, 8, 40, 50])
        XCTAssertEqual(blob[7], 0.7, accuracy: 0.00001)
    }

    func testLineAndPulseSampleDeterministically() {
        let spec = BeamSpec.shared
        let one = BeamAnimation.lineFrameValues(spec.line.keyframes, at: 1.2, duration: spec.defaults.duration.line)
        let two = BeamAnimation.lineFrameValues(spec.line.keyframes, at: 1.2, duration: spec.defaults.duration.line)
        XCTAssertEqual(one.x, two.x)
        XCTAssertEqual(one.spike, two.spike)
        XCTAssertTrue(one.x.isFinite && one.w.isFinite && one.h.isFinite)
        for theme in ["dark", "light"] {
            let section = spec.pulse.inner[theme]!
            XCTAssertEqual(PulseDriver.sample(section, at: 2, durationScale: 1), PulseDriver.sample(section, at: 2, durationScale: 1))
        }
    }

    func testExactOfficialShadersCompileWithMacOSRuntimeCompiler() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable in this test environment") }
        XCTAssertTrue(BeamMetalDiagnostics.isAvailable, BeamMetalDiagnostics.failureDescription ?? "Unreported Metal failure")
    }

    @MainActor func testDrawOnDemandSurfaceReleasesWithoutDisplayLink() {
        weak var released: NativeBeamMetalLayer.Surface?
        autoreleasepool {
            let surface = NativeBeamMetalLayer.Surface()
            released = surface
            XCTAssertTrue(surface.isPaused)
            XCTAssertFalse(surface.enableSetNeedsDisplay)
            XCTAssertNil(surface.hitTest(.zero))
            surface.releaseDrawableResources()
            surface.delegate = nil
        }
        XCTAssertNil(released, "Metal delegate/surface must not retain itself after teardown")
    }

    func testActualGPUShaderRingCornerMaskAndStrength() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable") }
        func pixels(strength: Double) throws -> [UInt8] {
            try BeamMetalResources.fixturePixels(.rotate(
                size: CGSize(width: 80, height: 60), angle: 0, radius: 12,
                borderWidth: 3, kind: 0, edgeMaskPx: 0,
                blobs: [100, 100, 0.5, 0.5, 1, 0.5, 0.25, 1],
                background: [], backgroundBlack: false, mask: [],
                matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                opacity: strength, shadow: .clear, shadowBlur: 0
            ), width: 80, height: 60)
        }
        let full = try pixels(strength: 1)
        XCTAssertEqual(full[(30 * 80 + 40) * 4 + 3], 0, "The card center must remain transparent")
        XCTAssertEqual(full[3], 0, "The top corner must follow the rounded geometry")
        XCTAssertGreaterThan(full[(30 * 80 + 1) * 4 + 3], 0, "The border must actually render GPU pixels")
        XCTAssertTrue(try pixels(strength: 0).allSatisfy { $0 == 0 })
    }

    func testActualGPUTravelThemeAndPaletteAreDistinct() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable") }
        func render(size: BeamSize, variant: BeamColorVariant, theme: String, angle: Double) throws -> [UInt8] {
            let config = RotateBeamConfig(size: size, variant: variant, theme: theme,
                                          staticColors: variant == .mono, duration: 8,
                                          borderRadius: nil, brightness: nil, saturation: nil,
                                          hueRange: 30, strength: 0.7)
            return try BeamMetalResources.fixturePixels(.rotate(
                size: CGSize(width: 80, height: 60), angle: angle,
                radius: config.radius, borderWidth: config.borderWidth, kind: 0,
                edgeMaskPx: 0, blobs: config.strokeBlobs,
                background: config.whiteGradientStops, backgroundBlack: !config.isDark,
                mask: config.beamMaskStops, matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                opacity: 0.7 * config.themeConfig.strokeOpacity, shadow: .clear, shadowBlur: 0
            ), width: 80, height: 60)
        }
        let reference = try render(size: .md, variant: .colorful, theme: "dark", angle: 0)
        XCTAssertEqual(reference, try render(size: .md, variant: .colorful, theme: "dark", angle: 0))
        XCTAssertNotEqual(reference, try render(size: .md, variant: .colorful, theme: "dark", angle: 0.25))
        XCTAssertNotEqual(reference, try render(size: .sm, variant: .colorful, theme: "dark", angle: 0))
        XCTAssertNotEqual(reference, try render(size: .md, variant: .colorful, theme: "light", angle: 0))
        for variant in [BeamColorVariant.mono, .ocean, .sunset] {
            XCTAssertNotEqual(reference, try render(size: .md, variant: variant, theme: "dark", angle: 0))
        }
    }

    private func config(size: BeamSize, variant: BeamColorVariant = .colorful) -> RotateBeamConfig {
        RotateBeamConfig(size: size, variant: variant, theme: "dark", staticColors: variant == .mono,
                         duration: 8, borderRadius: nil, brightness: nil, saturation: nil,
                         hueRange: 30, strength: 0.7)
    }
}
