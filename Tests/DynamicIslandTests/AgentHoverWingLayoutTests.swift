import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// The hover shell can widen to 300pt or to include sidecars. Its physical
/// camera gap must stay put, while the Thinking Orb sits on the OUTER left wing.
@MainActor
final class AgentHoverWingLayoutTests: XCTestCase {
    func testHoverExpandsBothWingsWithoutMovingThePhysicalNotchOrShrinkingIcons() {
        for notchWidth in [184.0, 200.0, 242.0] {
            let orb = AgentCompactOrbMetrics.primaryOrb
            let provider = AgentCompactOrbMetrics.providerIcon
            let wing: CGFloat = max(orb + CollapsedActivityLayoutProfile.leadingContentPadding,
                                    provider) + CollapsedActivityResolvedGeometry.notchSideSafetyClearance
            let baseWidth = notchWidth + 2 * (wing + IslandShellLayout.collapsedHorizontalPadding)
            let base = CGRect(x: 480, y: 700, width: baseWidth, height: 34)
            let original = CompactCollapsedSideSlotGeometry(
                isNotchIntegrated: true, leftRegionWidth: wing,
                notchCoreWidth: notchWidth, rightRegionWidth: wing)
            for extraLeft in [0.0, 24.0, 90.0] {
                for extraRight in [0.0, 24.0, 70.0] {
                    let hover = CGRect(x: base.minX - extraLeft, y: 630,
                                       width: baseWidth + extraLeft + extraRight, height: 92)
                    let layout = AgentHoverWingLayout.resolve(
                        original: original, collapsedFrame: base, hoverFrame: hover)
                    let slots = layout.slots
                    let leftStart = hover.minX + IslandShellLayout.collapsedHorizontalPadding
                    let leftOrb = CGRect(x: leftStart + CollapsedActivityLayoutProfile.leadingContentPadding,
                                         y: 0, width: orb, height: orb)
                    let rightIcon = CGRect(x: hover.maxX - IslandShellLayout.collapsedHorizontalPadding - provider,
                                           y: 0, width: provider, height: provider)
                    let notchStart = leftStart + slots.leftRegionWidth
                    let originalNotchStart = base.minX + IslandShellLayout.collapsedHorizontalPadding + wing
                    let notchEnd = notchStart + slots.notchCoreWidth
                    XCTAssertEqual(layout.contentWidth, hover.width - 2 * IslandShellLayout.collapsedHorizontalPadding)
                    XCTAssertEqual(slots.leftRegionWidth + slots.notchCoreWidth + slots.rightRegionWidth, layout.contentWidth,
                                   accuracy: 0.001)
                    XCTAssertEqual(notchStart, originalNotchStart, accuracy: 0.001,
                                   "Physical camera gap must not move as hover shell grows")
                    XCTAssertLessThanOrEqual(leftOrb.maxX + CollapsedActivityResolvedGeometry.notchSideSafetyClearance,
                                             notchStart)
                    XCTAssertGreaterThanOrEqual(rightIcon.minX - CollapsedActivityResolvedGeometry.notchSideSafetyClearance,
                                                notchEnd)
                    XCTAssertEqual(leftOrb.minX - hover.minX, 13, accuracy: 0.001,
                                   "Thinking Orb belongs beside the hover shell's outer LEFT edge")
                    XCTAssertEqual(hover.maxX - rightIcon.maxX, 8, accuracy: 0.001,
                                   "Claude/Codex provider icon belongs beside the outer RIGHT edge")
                }
            }
        }
    }

    func testFloatingHoverUsesFullOuterWidthWithoutAnInventedCameraNotch() {
        let original = CompactCollapsedSideSlotGeometry(
            isNotchIntegrated: false, leftRegionWidth: 0, notchCoreWidth: 0, rightRegionWidth: 0)
        let base = CGRect(x: 500, y: 700, width: 130, height: 34)
        let hover = CGRect(x: 410, y: 630, width: 310, height: 92)
        let result = AgentHoverWingLayout.resolve(original: original, collapsedFrame: base, hoverFrame: hover)
        XCTAssertFalse(result.slots.usesPhysicalNotchRegions)
        XCTAssertEqual(result.slots.notchCoreWidth, 0)
        XCTAssertEqual(result.contentWidth, 294)
    }

    func testActualSwiftUISlotLayoutRendersOrbsAtOutermostEnds() throws {
        _ = NSApplication.shared
        let original = CompactCollapsedSideSlotGeometry(
            isNotchIntegrated: true, leftRegionWidth: 31, notchCoreWidth: 200, rightRegionWidth: 31)
        let base = CGRect(x: 400, y: 700, width: 278, height: 34)
        let hover = CGRect(x: 360, y: 630, width: 358, height: 92)
        let geometry = AgentHoverWingLayout.resolve(
            original: original, collapsedFrame: base, hoverFrame: hover)
        let orb: CGFloat = AgentCompactOrbMetrics.primaryOrb
        let provider = AgentCompactOrbMetrics.providerIcon
        let view = CompactCollapsedSideSlotLayout(geometry: geometry.slots) {
            Circle().fill(Color.green).frame(width: orb, height: orb)
        } right: {
            Circle().fill(Color.orange).frame(width: provider, height: provider)
        }
        .frame(width: geometry.contentWidth, height: 34)
        .background(Color.clear)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        func visible(_ x: Int) -> Bool {
            (0..<bitmap.pixelsHigh).contains { y in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5
            }
        }
        XCTAssertTrue(visible(12), "The primary orb must render near the outer left edge, not under the notch")
        XCTAssertTrue(visible(Int(geometry.contentWidth) - 12), "The provider icon must render near the outer right edge")
        let cameraCenter = Int(geometry.slots.leftRegionWidth + geometry.slots.notchCoreWidth / 2)
        XCTAssertFalse(visible(cameraCenter), "No widget may render into the camera gap")
    }
}
