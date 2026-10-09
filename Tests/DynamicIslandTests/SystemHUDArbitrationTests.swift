import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

final class SystemHUDArbitrationTests: XCTestCase {
    func testSameKindCoalescesToNewestDescriptor() {
        var arbiter = SystemHUDArbiter()
        let first = SystemHUDDescriptor(
            kind: .volume,
            title: "Volume",
            subtitle: "40%",
            symbolName: "speaker.wave.2.fill",
            progress: 0.4,
            priority: 120,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let second = SystemHUDDescriptor(
            kind: .volume,
            title: "Volume",
            subtitle: "52%",
            symbolName: "speaker.wave.2.fill",
            progress: 0.52,
            priority: 120,
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertNotNil(arbiter.present(first))
        XCTAssertNotNil(arbiter.present(second))
        XCTAssertEqual(arbiter.current, second)
    }

    func testHigherPriorityPreemptsLowerAndLowerCannotReplaceHigher() {
        var arbiter = SystemHUDArbiter()
        let volume = SystemHUDDescriptor(
            kind: .volume, title: "Volume", subtitle: "50%",
            symbolName: "speaker.wave.2.fill", progress: 0.5, priority: 120
        )
        let critical = SystemHUDDescriptor(
            kind: .battery, title: "Critical Battery", subtitle: "8%",
            symbolName: "exclamationmark.triangle.fill", progress: 0.08, priority: 190,
            coalescingKey: "battery-critical"
        )
        let caps = SystemHUDDescriptor(
            kind: .capsLock, title: "Caps Lock On", subtitle: "ABC",
            symbolName: "capslock.fill", priority: 130
        )

        XCTAssertNotNil(arbiter.present(volume))
        XCTAssertNotNil(arbiter.present(critical))
        XCTAssertNil(arbiter.present(caps))
        XCTAssertEqual(arbiter.current, critical)
    }

    func testStaleDismissCannotRemoveNewerHUD() {
        var arbiter = SystemHUDArbiter()
        let first = SystemHUDDescriptor(
            kind: .volume, title: "Volume", subtitle: "40%",
            symbolName: "speaker.wave.2.fill", priority: 120
        )
        let second = SystemHUDDescriptor(
            kind: .capsLock, title: "Caps Lock On", subtitle: "ABC",
            symbolName: "capslock.fill", priority: 130
        )

        let oldGeneration = try! XCTUnwrap(arbiter.present(first))
        let newGeneration = try! XCTUnwrap(arbiter.present(second))
        XCTAssertFalse(arbiter.dismiss(generation: oldGeneration))
        XCTAssertEqual(arbiter.current, second)
        XCTAssertTrue(arbiter.dismiss(generation: newGeneration))
        XCTAssertNil(arbiter.current)
    }

    func testCapsLockTrackerPublishesOnlyOnChange() {
        var tracker = CapsLockHUDStateTracker()
        XCTAssertEqual(tracker.transition(to: false)?.title, "Caps Lock Off")
        XCTAssertNil(tracker.transition(to: false))
        XCTAssertEqual(tracker.transition(to: true)?.title, "Caps Lock On")
        XCTAssertNil(tracker.transition(to: true))
        XCTAssertEqual(tracker.transition(to: false)?.title, "Caps Lock Off")
    }

    func testFocusTrackerPublishesOnlyOnActualStateChange() {
        var tracker = FocusHUDStateTracker()
        XCTAssertEqual(tracker.transition(to: false)?.subtitle, "Off")
        XCTAssertNil(tracker.transition(to: false))
        XCTAssertEqual(tracker.transition(to: true)?.subtitle, "On")
        XCTAssertNil(tracker.transition(to: true))
        XCTAssertEqual(tracker.transition(to: false)?.subtitle, "Off")
    }

    func testBatteryChargingTransitionPublishesOnce() {
        var tracker = BatteryHUDStateTracker()
        let battery = snapshot(percentage: 73, plugged: false)
        let charging = snapshot(percentage: 74, plugged: true, charging: true)

        XCTAssertNil(tracker.transition(
            to: battery,
            statusEnabled: true,
            lowBatteryEnabled: true
        ))
        XCTAssertEqual(
            tracker.transition(
                to: charging,
                statusEnabled: true,
                lowBatteryEnabled: true
            )?.title,
            "Charging"
        )
        XCTAssertNil(tracker.transition(
            to: snapshot(percentage: 75, plugged: true, charging: true),
            statusEnabled: true,
            lowBatteryEnabled: true
        ))
    }

    func testBatteryThresholdCrossingDoesNotSpamUntilBandChanges() {
        var tracker = BatteryHUDStateTracker()
        _ = tracker.transition(
            to: snapshot(percentage: 30, plugged: false),
            statusEnabled: true,
            lowBatteryEnabled: true
        )

        XCTAssertEqual(
            tracker.transition(
                to: snapshot(percentage: 20, plugged: false),
                statusEnabled: true,
                lowBatteryEnabled: true
            )?.title,
            "Low Battery"
        )
        XCTAssertNil(tracker.transition(
            to: snapshot(percentage: 19, plugged: false),
            statusEnabled: true,
            lowBatteryEnabled: true
        ))
        XCTAssertEqual(
            tracker.transition(
                to: snapshot(percentage: 10, plugged: false),
                statusEnabled: true,
                lowBatteryEnabled: true
            )?.title,
            "Critical Battery"
        )
        XCTAssertNil(tracker.transition(
            to: snapshot(percentage: 9, plugged: false),
            statusEnabled: true,
            lowBatteryEnabled: true
        ))

        _ = tracker.transition(
            to: snapshot(percentage: 25, plugged: false),
            statusEnabled: true,
            lowBatteryEnabled: true
        )
        XCTAssertEqual(
            tracker.transition(
                to: snapshot(percentage: 20, plugged: false),
                statusEnabled: true,
                lowBatteryEnabled: true
            )?.title,
            "Low Battery"
        )
    }

    func testAudioOutputPublishesOnlyIdentityChanges() {
        var tracker = AudioOutputHUDStateTracker()
        let first = AudioOutputDeviceSnapshot(
            deviceID: 1,
            name: "MacBook Pro Speakers",
            kind: .generic
        )
        let same = AudioOutputDeviceSnapshot(
            deviceID: 1,
            name: "MacBook Pro Speakers",
            kind: .generic
        )
        let airPods = AudioOutputDeviceSnapshot(
            deviceID: 2,
            name: "AirPods Pro",
            kind: .airPodsPro
        )

        XCTAssertNil(tracker.transition(to: first))
        XCTAssertNil(tracker.transition(to: same))
        let changed = tracker.transition(to: airPods)
        XCTAssertEqual(changed?.title, "AirPods Pro")
        XCTAssertEqual(changed?.subtitle, "Connected")
        XCTAssertNil(changed?.progress, "CoreAudio output identity supplies no device battery reading")
        XCTAssertEqual(changed?.symbolName, "airpodspro")
    }

    func testAudioOutputClassificationIsConservative() {
        XCTAssertEqual(AudioOutputDeviceKind.classify(name: "Nicolas's AirPods Pro"), .airPodsPro)
        XCTAssertEqual(AudioOutputDeviceKind.classify(name: "AirPods Max"), .airPodsMax)
        XCTAssertEqual(AudioOutputDeviceKind.classify(name: "Beats Studio Pro"), .beats)
        XCTAssertEqual(AudioOutputDeviceKind.classify(name: "Sony WH-1000XM5"), .headphones)
        XCTAssertEqual(AudioOutputDeviceKind.classify(name: "USB Audio DAC"), .generic)
    }

    func testPercentageFormattingNeverTruncatesBoundaryValues() {
        XCTAssertEqual(SystemHUDFormatting.percentage(0), "0%")
        XCTAssertEqual(SystemHUDFormatting.percentage(0.09), "9%")
        XCTAssertEqual(SystemHUDFormatting.percentage(0.10), "10%")
        XCTAssertEqual(SystemHUDFormatting.percentage(0.99), "99%")
        XCTAssertEqual(SystemHUDFormatting.percentage(1), "100%")
        XCTAssertEqual(SystemHUDFormatting.percentage(1.5), "100%")
    }

    func testVolumeAccentStaysLightBlueAndStrengthTracksValue() {
        let low = SystemHUDAccentComponents.resolve(kind: .volume, value: 0.1)
        let high = SystemHUDAccentComponents.resolve(kind: .volume, value: 1.0)
        XCTAssertGreaterThan(low.blue, low.red)
        XCTAssertGreaterThan(low.green, low.red)
        XCTAssertGreaterThan(high.blue, high.red)
        XCTAssertGreaterThan(high.opacity, low.opacity)
        XCTAssertGreaterThan(high.glowStrength, low.glowStrength)
    }

    func testBrightnessAccentStaysLightYellowAndStrengthTracksValue() {
        let low = SystemHUDAccentComponents.resolve(kind: .brightness, value: 0.1)
        let high = SystemHUDAccentComponents.resolve(kind: .brightness, value: 1.0)
        XCTAssertGreaterThan(low.red, low.blue)
        XCTAssertGreaterThan(low.green, low.blue)
        XCTAssertGreaterThan(high.opacity, low.opacity)
        XCTAssertGreaterThan(high.glowStrength, low.glowStrength)
    }

    func testInteractiveHUDPresentationIsTransientAndTallerThanNormalCollapsedShell() {
        let normal = CollapsedPresentationProfile.normal
        let hud = CollapsedPresentationProfile.systemHUD(value: 1)
        XCTAssertEqual(hud.kind, .systemHUD)
        XCTAssertGreaterThan(hud.heightDelta, normal.heightDelta)
        XCTAssertGreaterThan(hud.bottomCornerRadius, normal.bottomCornerRadius)
        XCTAssertEqual(hud.contentProfile, .systemHUD)
    }

    /// Runtime-observed regression: collapsedHeight 29.87pt under a 34pt
    /// notch band put the slider row inside the physical notch and ended the
    /// shell ~8pt below it. The HUD must hang a full slider band below the
    /// physical top band while its top edge stays on the screen top.
    func testInteractiveHUDShellHangsASliderBandBelowThePhysicalNotch() {
        let service = NotchGeometryService()
        for (notchHeight, collapsedHeight) in [(CGFloat(34), CGFloat(29.87)), (32, 44), (38, 32), (38, 44)] {
            let screen = notchedScreen(notchHeight: notchHeight)
            let hud = service.geometry(
                for: screen,
                collapsedSize: CGSize(width: 190, height: collapsedHeight),
                expandedSize: CGSize(width: 760, height: 260),
                collapsedPresentationProfile: .systemHUD(value: 0.5)
            )
            let topBand = max(collapsedHeight, notchHeight)
            let brokenHeight = collapsedHeight + 12
            XCTAssertEqual(hud.collapsedFrame.maxY, screen.frame.maxY, accuracy: 0.5, "top edge must stay pinned")
            XCTAssertGreaterThanOrEqual(
                hud.collapsedFrame.height,
                topBand + CollapsedPresentationProfile.systemHUDSliderBandHeight - 1,
                "notch=\(notchHeight) collapsed=\(collapsedHeight)"
            )
            XCTAssertGreaterThanOrEqual(hud.collapsedFrame.height, brokenHeight + 10, "must visibly extend below the old shell")
            XCTAssertLessThanOrEqual(hud.collapsedFrame.height, 80, "must not become comically tall")
            let rowBand = CollapsedPresentationProfile.systemHUDRowBandHeight(shellHeight: hud.collapsedFrame.height)
            XCTAssertGreaterThanOrEqual(rowBand, notchHeight - 0.5, "slider row must start below the physical notch")
        }
    }

    func testInteractiveHUDGrowsDownwardFromTheSameTopEdgeAsTheNormalShell() {
        let service = NotchGeometryService()
        let screen = notchedScreen(notchHeight: 34)
        let size = CGSize(width: 190, height: 29.87)
        let normal = service.geometry(for: screen, collapsedSize: size, expandedSize: CGSize(width: 760, height: 260))
        let hud = service.geometry(
            for: screen,
            collapsedSize: size,
            expandedSize: CGSize(width: 760, height: 260),
            collapsedPresentationProfile: .systemHUD(value: 1)
        )
        XCTAssertEqual(hud.collapsedFrame.maxY, normal.collapsedFrame.maxY, accuracy: 0.5)
        XCTAssertLessThan(hud.collapsedFrame.minY, normal.collapsedFrame.minY - 20)
        XCTAssertEqual(hud.collapsedFrame.midX, normal.collapsedFrame.midX, accuracy: 1)
        XCTAssertLessThanOrEqual(hud.collapsedFrame.width, normal.collapsedFrame.width + 60, "no width explosion (width profile is unchanged by the height fix)")
    }

    func testFloatingIslandBelowTheNotchDoesNotReserveTheNotchBand() {
        let hud = NotchGeometryService().geometry(
            for: notchedScreen(notchHeight: 38),
            collapsedSize: CGSize(width: 190, height: 29.87),
            expandedSize: CGSize(width: 760, height: 260),
            collapsedPresentationProfile: .systemHUD(value: 0.5),
            useAdaptiveNotchSizing: false
        )
        XCTAssertEqual(
            hud.collapsedFrame.height,
            (29.87 + CollapsedPresentationProfile.systemHUDSliderBandHeight).rounded(.up),
            accuracy: 1,
            "a floating island is not occluded by the notch"
        )
    }

    func testBrightnessAndVolumeResolveIdenticalHUDShellGeometryAtEveryValue() {
        let service = NotchGeometryService()
        let screen = notchedScreen(notchHeight: 34)
        let frames = [0, 0.09, 0.10, 0.50, 0.99, 1.0].map { value in
            service.geometry(
                for: screen,
                collapsedSize: CGSize(width: 190, height: 29.87),
                expandedSize: CGSize(width: 760, height: 260),
                collapsedPresentationProfile: .systemHUD(value: value)
            ).collapsedFrame
        }
        XCTAssertEqual(Set(frames.map { "\($0)" }).count, 1, "HUD geometry must not depend on kind or value")
    }

    /// Renders the production HUD content in the content area of a 34pt-notch
    /// shell and locates the slider by its full-width accent rows: the slider
    /// must sit below the physical top band, not be centered up into it.
    @MainActor
    func testRenderedHUDSliderSitsBelowTheRowBandAtEveryBoundaryValue() throws {
        let shellHeight = CGFloat(34) + CollapsedPresentationProfile.systemHUDSliderBandHeight
        let contentHeight = shellHeight - IslandShellLayout.collapsedBottomPadding
        let rowBand = CollapsedPresentationProfile.systemHUDRowBandHeight(shellHeight: shellHeight)
        let width: CGFloat = 300
        for kind in [SystemHUDKind.brightness, .volume] {
            for value in [0.0, 0.09, 0.10, 0.50, 0.99, 1.0] {
                let activity = DynamicIslandLiveActivity(
                    id: LiveActivityStore.systemHUDActivityID,
                    kind: .system,
                    title: kind == .brightness ? "Brightness" : "Volume",
                    subtitle: SystemHUDFormatting.percentage(value),
                    symbolName: kind == .brightness ? "sun.max.fill" : "speaker.wave.3.fill",
                    priority: 100,
                    isActive: true,
                    progress: value,
                    updatedAt: Date(),
                    systemHUDKind: kind
                )
                let hosting = NSHostingView(rootView: CollapsedSystemHUDCompactView(
                    activity: activity,
                    layout: CompactCollapsedSideSlotGeometry(
                        isNotchIntegrated: false,
                        leftRegionWidth: 0,
                        notchCoreWidth: 0,
                        rightRegionWidth: 0
                    )
                )
                .frame(width: width, height: contentHeight)
                .background(Color.black))
                hosting.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)

                // The slider track is the only element spanning most of the width.
                let scale = CGFloat(rep.pixelsHigh) / contentHeight
                var trackRows: [CGFloat] = []
                for py in 0..<rep.pixelsHigh {
                    var lit = 0
                    for px in stride(from: 0, to: rep.pixelsWide, by: 2) {
                        if let c = rep.colorAt(x: px, y: py), c.brightnessComponent > 0.015 { lit += 1 }
                    }
                    if Double(lit) > Double(rep.pixelsWide / 2) * 0.55 { trackRows.append(CGFloat(py) / scale) }
                }
                let label = "\(kind) \(value)"
                let top = try XCTUnwrap(trackRows.min(), "slider track not found: \(label)")
                let bottom = try XCTUnwrap(trackRows.max())
                XCTAssertGreaterThanOrEqual(top, rowBand + 4, "slider must clear the physical top band: \(label)")
                XCTAssertLessThanOrEqual(bottom, contentHeight - 2, "slider must not clip at the bottom: \(label)")
            }
        }
    }

    private func notchedScreen(notchHeight: CGFloat) -> ScreenSnapshot {
        let size = CGSize(width: 1512, height: 982)
        return ScreenSnapshot(
            frame: CGRect(origin: .zero, size: size),
            visibleFrame: CGRect(x: 0, y: 0, width: size.width, height: size.height - notchHeight),
            safeAreaInsets: NSEdgeInsets(top: notchHeight, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: size.height - notchHeight, width: (size.width - 180) / 2, height: notchHeight),
            auxiliaryTopRightArea: CGRect(x: (size.width + 180) / 2, y: size.height - notchHeight, width: (size.width - 180) / 2, height: notchHeight)
        )
    }

    private func snapshot(
        percentage: Int,
        plugged: Bool,
        charging: Bool = false,
        charged: Bool = false
    ) -> BatteryActivitySnapshot {
        BatteryActivitySnapshot(
            percentage: percentage,
            powerSourceStateDescription: plugged ? "AC Power" : "Battery Power",
            isPluggedIn: plugged,
            isCharging: charging,
            isCharged: charged,
            isOnBattery: !plugged
        )
    }
}
