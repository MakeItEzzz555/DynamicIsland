import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

final class LockScreenLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let notch = CGRect(x: 664, y: 950, width: 184, height: 32)

    private func layout(_ change: (inout LockScreenPreferences) -> Void = { _ in },
                        media: Bool = true, radials: Int = 3) -> LockScreenLayout {
        var prefs = LockScreenPreferences()
        change(&prefs)
        return LockScreenLayout.resolve(screen: screen, notch: notch, preferences: prefs.normalized(),
                                        hasMedia: media, radialCount: radials, hasAlert: false)
    }

    func testIslandWrapsTheNotchWithVisibleWings() {
        let island = layout().island
        XCTAssertEqual(island.midX, notch.midX, accuracy: 0.5)
        XCTAssertEqual(island.width, notch.width + 2 * LockScreenLayout.islandWing)
        XCTAssertEqual(island.maxY, screen.maxY, "flush with the top edge, like the desktop island")
        XCTAssertEqual(island.height, notch.height)
        let floating = LockScreenLayout.resolve(screen: screen, notch: nil, preferences: .init(),
                                                hasMedia: false, radialCount: 0, hasAlert: false).island
        XCTAssertLessThan(floating.maxY, screen.maxY, "notchless displays get a floating pill")
    }

    func testRadialRowAttachesBelowOrAboveMediaWithTheGap() throws {
        let below = layout { $0.secondaryGap = 20 }
        let media = try XCTUnwrap(below.media), row = try XCTUnwrap(below.secondary)
        XCTAssertEqual(media.minY - row.maxY, 20, accuracy: 0.01, "row hangs below the card with the gap")
        XCTAssertEqual(row.midX, media.midX, accuracy: 0.5)
        XCTAssertEqual(row.width, LockScreenLayout.secondaryWidth(count: 3))

        let above = layout { $0.secondaryGap = 20; $0.secondaryPlacement = .above }
        let aboveMedia = try XCTUnwrap(above.media), aboveRow = try XCTUnwrap(above.secondary)
        XCTAssertEqual(aboveRow.minY - aboveMedia.maxY, 20, accuracy: 0.01, "row sits above the card with the gap")
        XCTAssertEqual(aboveRow.maxY, media.maxY, accuracy: 0.01, "the attached group starts at the same column top")
        XCTAssertLessThan(aboveRow.maxY, screen.maxY - 280, "never overlaps the system clock")
    }

    func testMediaOffsetMovesTheWholeGroupAndTheRowReplacesMissingMedia() throws {
        let base = layout(), moved = layout { $0.mediaVerticalOffset = 40 }
        XCTAssertEqual(try XCTUnwrap(base.media).minY - XCTUnwrap(moved.media).minY, 40, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(base.secondary).minY - XCTUnwrap(moved.secondary).minY, 40, accuracy: 0.01)
        let noMedia = layout(media: false)
        XCTAssertNil(noMedia.media)
        XCTAssertEqual(try XCTUnwrap(noMedia.secondary).maxY, try XCTUnwrap(base.media).maxY, accuracy: 0.01)
        XCTAssertNil(layout(radials: 0).secondary)
    }

    func testRadialItemsFollowOrderAndOnlyFillRealProgress() {
        var content = LockScreenContent()
        content.battery = .init(percent: 64, isCharging: false)
        content.timer = .init(remainingSeconds: 90, progress: 0.25, isRunning: true)
        content.keepAwake = .init(expiresAt: nil, progress: nil)
        let items = LockScreenRadialItem.items(for: content, order: [.keepAwake, .battery, .timer])
        XCTAssertEqual(items.map(\.kind), [.keepAwake, .battery, .timer])
        XCTAssertEqual(items[1].progress, 0.64)
        XCTAssertEqual(items[1].value, "64")
        XCTAssertEqual(items[2].progress, 0.25)
        XCTAssertEqual(items[2].value, "1:30")
        XCTAssertNil(items[0].progress, "indefinite Keep Awake has no fill to show")
        XCTAssertEqual(items[0].value, "On")
        XCTAssertTrue(LockScreenRadialItem.items(for: .empty, order: LockScreenRadialKind.allCases).isEmpty)
    }

    func testKeepAwakeProgressComesFromTheRealDuration() {
        let now = Date(timeIntervalSince1970: 1_000)
        let sources = LockScreenSources(keepAwakeExpiresAt: now.addingTimeInterval(900), keepAwakeTotalSeconds: 3_600,
                                        keepAwakeActive: true)
        let content = LockScreenPrivacyProjector.project(sources, disclosure: .init(keepAwake: true), state: .locked, now: now)
        XCTAssertEqual(content.keepAwake?.progress ?? -1, 0.25, accuracy: 0.0001)
    }

    func testNewPreferencesNormalizeAndDecodeSafely() throws {
        var prefs = LockScreenPreferences()
        prefs.secondaryGap = 500
        prefs.radialOrder = [.timer, .timer]
        let normalized = prefs.normalized()
        XCTAssertEqual(normalized.secondaryGap, 60)
        XCTAssertEqual(normalized.radialOrder, [.timer, .battery, .keepAwake], "duplicates removed, missing kinds appended")
        let old = try JSONDecoder().decode(LockScreenPreferences.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertEqual(old.secondaryPlacement, .below)
        XCTAssertEqual(old.radialOrder, LockScreenRadialKind.allCases)
    }

    @MainActor
    func testRadialGaugeAndIslandRenderAtTheirFrames() throws {
        _ = NSApplication.shared
        let item = LockScreenRadialItem(kind: .battery, symbol: "battery.75", value: "64", progress: 0.64, tint: .white,
                                        accessibilityLabel: "Battery 64 percent")
        let gauge = NSHostingView(rootView: LockScreenRadialGauge(item: item))
        XCTAssertEqual(gauge.fittingSize.width, LockScreenLayout.radialDiameter, accuracy: 0.5)
        let island = NSHostingView(rootView: LockScreenIslandHUD(phase: .locked, notchWidth: 184, showsActivity: true)
            .frame(width: 316, height: 32))
        island.frame = CGRect(x: 0, y: 0, width: 316, height: 32)
        island.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(island.bitmapImageRepForCachingDisplay(in: island.bounds))
        island.cacheDisplay(in: island.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / island.bounds.width
        // The left wing (lock icon area) is drawn: opaque black shell outside the notch.
        XCTAssertGreaterThan(rep.colorAt(x: Int(10 * scale), y: Int(16 * scale))?.alphaComponent ?? 0, 0.9)
    }
}
