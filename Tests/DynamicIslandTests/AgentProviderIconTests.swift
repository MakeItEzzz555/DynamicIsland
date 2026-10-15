import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Collapsed Agents: primary orb left of the notch, the supplied provider
/// artwork rightmost on the right, never wider than the former layout.
@MainActor
final class AgentProviderIconTests: XCTestCase {
    private let claude = SettingsPreviewFixtures.agentSession(provider: .claude)
    private let codex = SettingsPreviewFixtures.agentSession(provider: .codex)
    private let other = SettingsPreviewFixtures.agentSession(provider: .other("gemini"))

    private func compact(_ sessions: [AgentSession], overflow: Int = 0) -> AgentCompactPresentation {
        AgentCompactPresentation(sessions: sessions, overflowCount: overflow, summary: "Working")
    }

    func testSuppliedArtworkResolvesFromTheResourceBundle() throws {
        for provider in [AgentProvider.claude, .codex] {
            let name = try XCTUnwrap(AgentProviderVisualIdentity.resolve(provider).assetName)
            let image = try XCTUnwrap(AgentProviderIconImages.image(named: name), "\(name) missing from the resource bundle")
            let rep = try XCTUnwrap(image.representations.first)
            XCTAssertEqual(rep.pixelsWide, 256)
            XCTAssertEqual(rep.pixelsHigh, 256)
            XCTAssertTrue(rep.hasAlpha, "transparency preserved")
        }
        XCTAssertNil(AgentProviderVisualIdentity.resolve(.other("gemini")).assetName, "unknown providers use the neutral fallback")
        XCTAssertNil(AgentProviderIconImages.image(named: "MissingProviderIcon"))
    }

    func testAccessibilityNamesComeFromTheProviderIdentity() {
        XCTAssertEqual(AgentProviderVisualIdentity.resolve(.claude).accessibilityName, "Claude")
        XCTAssertEqual(AgentProviderVisualIdentity.resolve(.codex).accessibilityName, "Codex")
        XCTAssertEqual(AgentProviderVisualIdentity.resolve(.other("gemini")).accessibilityName, "Agent provider")
    }

    func testSingleSessionIsOrbLeftAndProviderIconRight() {
        let single = compact([claude])
        XCTAssertEqual(AgentCompactOrbMetrics.leadingWidth, AgentCompactOrbMetrics.primaryOrb, "orb only, no provider glyph")
        XCTAssertEqual(AgentCompactOrbMetrics.trailingWidth(for: single), AgentCompactOrbMetrics.providerIcon, "icon only, no state glyph")
    }

    /// Wing icon frames in shell coordinates, mirroring CompactCollapsedSideSlotLayout.
    func testWingIconsStayInsideWingsClearOfNotchNearOuterEdgeAndLegible() {
        let sets = [[claude], [claude, codex], [codex, claude, other], [claude, codex, other, claude]]
        for notchWidth in [184.0, 200.0, 210.0] {
            for sessions in sets {
                for overflow in [0, 3] {
                    let presentation = compact(sessions, overflow: overflow)
                    let left = AgentCompactOrbMetrics.leadingWidth
                    let right = AgentCompactOrbMetrics.trailingWidth(for: presentation)
                    let notch = CGRect(x: 500 - notchWidth / 2, y: 0, width: notchWidth, height: 32)
                    let profile = CollapsedActivityLayoutProfile(leftContentWidth: left, rightContentWidth: right)
                    // existingWidth deliberately wider than required to exercise extra per-side width.
                    for existing in [notchWidth + 40, notchWidth + 200] {
                        let g = CollapsedActivityResolvedGeometry.resolve(
                            notchRect: notch, existingWidth: existing, collapsedHeight: 34, topY: 34, profile: profile)
                        let leftRegion = CGRect(x: g.frame.minX + CollapsedActivityResolvedGeometry.outerHorizontalPadding, y: 0,
                                                width: g.leftRegionWidth, height: 34)
                        let rightRegion = CGRect(x: notch.maxX, y: 0, width: g.rightRegionWidth, height: 34)
                        let leftIcon = CGRect(x: leftRegion.minX + CollapsedActivityLayoutProfile.leadingContentPadding, y: 0,
                                              width: left, height: AgentCompactOrbMetrics.primaryOrb)
                        let rightIcon = CGRect(x: rightRegion.maxX - AgentCompactOrbMetrics.providerIcon, y: 0,
                                               width: AgentCompactOrbMetrics.providerIcon, height: AgentCompactOrbMetrics.providerIcon)
                        let rightContent = CGRect(x: rightRegion.maxX - right, y: 0, width: right, height: 20)
                        let label = "notch \(notchWidth) sessions \(sessions.count) overflow \(overflow) existing \(existing)"
                        XCTAssertTrue(leftRegion.contains(leftIcon), label)
                        XCTAssertTrue(rightRegion.contains(rightContent), label)
                        XCTAssertGreaterThanOrEqual(notch.minX - leftIcon.maxX, CollapsedActivityResolvedGeometry.notchSideSafetyClearance, label)
                        XCTAssertGreaterThanOrEqual(rightContent.minX - notch.maxX, CollapsedActivityResolvedGeometry.notchSideSafetyClearance, label)
                        // Anchored to the outer edges of the island (outer padding + leading padding / trailing flush).
                        XCTAssertEqual(leftIcon.minX - g.frame.minX, 13, accuracy: 0.5, label)
                        XCTAssertEqual(g.frame.maxX - rightIcon.maxX, 8, accuracy: 0.5, label)
                        XCTAssertGreaterThanOrEqual(leftIcon.minX, g.frame.minX)
                        XCTAssertLessThanOrEqual(rightIcon.maxX, g.frame.maxX)
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(AgentCompactOrbMetrics.primaryOrb, 22)
        XCTAssertGreaterThanOrEqual(AgentCompactOrbMetrics.providerIcon, 22)
        XCTAssertEqual(AgentCompactOrbMetrics.providerIcon, AgentCompactOrbMetrics.primaryOrb, "both wings equally legible")
        XCTAssertGreaterThanOrEqual(AgentCompactOrbMetrics.secondaryOrb, 16)
    }

    func testPrimaryProviderIconIsTheRightmostElement() throws {
        // Codex primary (blue), Claude secondary orb: the right edge must be Codex blue.
        for (sessions, expectsBlue) in [([codex, claude], true), ([claude, codex], false)] {
            let presentation = compact(sessions)
            let view = AgentCompactRoutineTrailingView(presentation: presentation)
                .frame(width: AgentCompactOrbMetrics.trailingWidth(for: presentation), height: 20)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let rep = NSBitmapImageRep(cgImage: image)
            let iconColumns = Int(AgentCompactOrbMetrics.providerIcon * 2)
            var blue = 0, orange = 0
            for x in (rep.pixelsWide - iconColumns)..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { continue }
                    if c.blueComponent > c.redComponent + 0.2 { blue += 1 }
                    if c.redComponent > c.blueComponent + 0.2 { orange += 1 }
                }
            }
            XCTAssertGreaterThan(expectsBlue ? blue : orange, 20, "primary provider artwork drawn at the right edge")
            XCTAssertLessThan(expectsBlue ? orange : blue, 5, "no other provider's artwork in the icon slot")
        }
    }
}
