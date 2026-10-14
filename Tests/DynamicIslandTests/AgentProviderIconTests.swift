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

    /// The pre-icon footprint: orb + 11 pt glyph left, mini orbs or a 16 pt state glyph right.
    private func legacyTotal(_ presentation: AgentCompactPresentation) -> CGFloat {
        let others = presentation.sessions.count - 1
        let badge: CGFloat = presentation.overflowCount > 0 ? 18 : 0
        let trailing = others > 0 ? CGFloat(others) * 13 + CGFloat(others - 1) * 4 + (badge > 0 ? 4 + badge : 0) : max(16, badge)
        return 18 + 4 + 11 + trailing
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
        XCTAssertLessThan(AgentCompactOrbMetrics.leadingWidth + AgentCompactOrbMetrics.trailingWidth(for: single), legacyTotal(single))
    }

    func testMultipleAndMixedSessionsNeverWidenTheIsland() {
        for presentation in [compact([claude, codex]), compact([codex, claude]), compact([claude, codex, other]),
                             compact([claude, codex, other], overflow: 2), compact([codex], overflow: 1)] {
            let total = AgentCompactOrbMetrics.leadingWidth + AgentCompactOrbMetrics.trailingWidth(for: presentation)
            XCTAssertLessThanOrEqual(total, legacyTotal(presentation), "\(presentation.sessions.count) sessions, overflow \(presentation.overflowCount)")
            let profile = CollapsedPresentationProfile.agentRoutine(
                leftContentWidth: AgentCompactOrbMetrics.leadingWidth,
                rightContentWidth: AgentCompactOrbMetrics.trailingWidth(for: presentation))
            let legacy = CollapsedPresentationProfile.agentRoutine(leftContentWidth: 33, rightContentWidth: legacyTotal(presentation) - 33)
            XCTAssertLessThanOrEqual(profile.minimumFloatingWidth, legacy.minimumFloatingWidth, "no regression on narrow/notchless hosts")
        }
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
