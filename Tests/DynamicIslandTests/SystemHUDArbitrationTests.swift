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
        XCTAssertEqual(changed?.subtitle, "Output Changed")
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
