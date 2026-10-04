import AppKit
import Metal
import XCTest
@testable import LibrariesNative
@testable import DynamicIsland

@MainActor
final class NativeMetalFxTests: XCTestCase {
    func testActualGPUCompilesAllPresetsThemesAndTimeChangesMaterial() throws {
        XCTAssertTrue(MetalFxDiagnostics.isAvailable, MetalFxDiagnostics.failureDescription ?? "GPU unavailable")
        let size = CGSize(width: 30, height: 30)
        var samples = [[UInt8]]()
        for preset in MetalPreset.allCases {
            for theme in [MetalResolvedTheme.dark, .light] {
                let material = MetalMaterial.preset(preset, theme: theme)
                let sample = try MetalSheetResources.fixturePixels(.init(size: size, mapping: .init(size: size, shaderScale: 1.3), material: material, time: 1.25, opacity: material.shaderOpacity, displayScale: 2))
                XCTAssertTrue(sample.contains { $0 > 0 })
                samples.append(sample)
            }
        }
        XCTAssertNotEqual(samples[0], samples[1])
        XCTAssertNotEqual(samples[0], samples[2])
        XCTAssertNotEqual(samples[2], samples[4])
        let parameters = MetalSheetParameters(size: size, mapping: .init(size: size, shaderScale: 1.3), material: .preset(.chromatic, theme: .dark), time: 2.5, opacity: 1, displayScale: 2)
        XCTAssertNotEqual(samples[0], try MetalSheetResources.fixturePixels(parameters))
        let zero = MetalSheetParameters(size: size, mapping: .init(size: size, shaderScale: 1.3), material: .base, time: 1, opacity: 0, displayScale: 2)
        XCTAssertTrue(try MetalSheetResources.fixturePixels(zero).allSatisfy { $0 == 0 })
    }
    func testClockPauseResumeAndCircleBandAreStable() {
        let clock = MetalInstanceClock()
        let before = clock.time(now: 100)
        clock.setPaused(true, now: 100)
        XCTAssertEqual(clock.time(now: 300), before)
        clock.setPaused(false, now: 300)
        XCTAssertEqual(clock.time(now: 301), before + 1)
        let points = MetalGeometry.roundRectOutline(CGRect(x: 0, y: 0, width: 30, height: 30), radius: 15, deform: nil)
        XCTAssertTrue(points.allSatisfy { abs(hypot($0.x - 15, $0.y - 15) - 15) < 0.01 })
        XCTAssertEqual(MetalRimOptions.default.blur, 0.5)
        XCTAssertEqual(MetalRimOptions.default.offsetY, 1)
        XCTAssertTrue(MetalGeometry.roundRectOutline(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 30), radius: 15, deform: nil).isEmpty)
        XCTAssertTrue(MetalGeometry.roundRectOutline(.zero, radius: 0, deform: nil).isEmpty)
    }
    func testPointerFieldIsBoundedPresentationOnlyAndSettles() {
        let bend = MetalBendModel()
        var field: MetalBendField?
        for index in 0..<120 {
            field = bend.step(now: Double(index + 1) / 120, tilt: CGVector(dx: 0.3, dy: 0), size: CGSize(width: 30, height: 30), radius: 15, cfg: .default)
        }
        let point = CGPoint(x: 30, y: 15)
        let changed = field?.deform(point) ?? point
        XCTAssertNotEqual(changed, point)
        XCTAssertLessThan(hypot(changed.x - point.x, changed.y - point.y), 16)
        bend.reset(); XCTAssertNil(bend.field)
        let bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        XCTAssertEqual(NativeMetalPointer.TrackingView.vector(point: CGPoint(x: 15, y: 15), bounds: bounds), .zero)
        XCTAssertEqual(NativeMetalPointer.TrackingView.vector(point: CGPoint(x: 100, y: 100), bounds: bounds), .zero)
    }
}
