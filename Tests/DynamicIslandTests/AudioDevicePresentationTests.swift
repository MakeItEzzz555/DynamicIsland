import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

final class AudioDevicePresentationTests: XCTestCase {
    func testObservedNameRemainsVerbatimAndUnknownBatteryIsAbsent() {
        let name = "Nicolas’s AirPods Pro"
        let device = AudioDevicePresentation(name: name)
        XCTAssertEqual(device.name, name)
        XCTAssertEqual(device.family, .airPodsPro)
        XCTAssertNil(device.batteryPercentage)
        XCTAssertEqual(device.status, "Connected")
        XCTAssertEqual(AudioDevicePresentation(name: name, batteryPercentage: 73).status, "Connected · 73%")
        XCTAssertEqual(AudioDevicePresentation(name: name, batteryPercentage: 0).status, "Connected · 0%")
        XCTAssertNil(AudioDevicePresentation(name: name, batteryPercentage: -1).batteryPercentage)
        XCTAssertNil(AudioDevicePresentation(name: name, batteryPercentage: 101).batteryPercentage)
    }

    func testClassificationRequiresExplicitModelEvidence() {
        let examples: [(String, AudioOutputDeviceKind)] = [
            ("AirPods", .airPods), ("AirPods Pro 2", .airPodsPro), ("AirPods Max", .airPodsMax),
            ("AirPods 3", .airPodsGen3), ("AirPods (3rd generation)", .airPodsGen3),
            ("AirPods gen 3", .airPodsGen3), ("Alex 3's AirPods", .airPods), ("AirPods 30", .airPods),
            ("AirPods 4", .airPods), ("Beats Studio Pro", .beats), ("Studio Buds", .beats),
            ("Sony WH-1000XM5", .headphones), ("Sony WF-1000XM5", .earbuds),
            ("Galaxy Buds", .earbuds), ("USB Audio DAC", .generic), ("Bose Speaker", .generic)
        ]
        for (name, family) in examples { XCTAssertEqual(AudioOutputDeviceKind.classify(name: name), family, name) }
    }

    func testSymbolFallbackDoesNotRequireTheNewerFamilySymbol() {
        XCTAssertEqual(AudioOutputDeviceKind.airPodsGen3.resolvedSymbolName { $0 == "earbuds" }, "earbuds")
        XCTAssertEqual(AudioOutputDeviceKind.airPodsMax.resolvedSymbolName { $0 == "headphones" }, "headphones")
        XCTAssertEqual(AudioOutputDeviceKind.beats.resolvedSymbolName { _ in false }, "speaker.wave.2.fill")
        XCTAssertEqual(AudioOutputDeviceKind.airPodsPro.resolvedSymbolName { _ in true }, "airpodspro")
    }

    @MainActor
    func testEveryFamilyResolvesToAnAvailablePublicSymbol() {
        let families: [AudioOutputDeviceKind] = [.airPods, .airPodsPro, .airPodsMax, .airPodsGen3,
                                                 .beats, .headphones, .earbuds, .generic]
        for family in families {
            let symbol = family.resolvedSymbolName {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
            }
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(family): \(symbol)")
        }
    }

    func testParallaxIsBoundedAndReducedMotionRemainsStill() {
        XCTAssertEqual(AudioDeviceModelMotion.rotation(normalizedX: 2, enabled: true, reduceMotion: false), 12)
        XCTAssertEqual(AudioDeviceModelMotion.rotation(normalizedX: -2, enabled: true, reduceMotion: false), -12)
        XCTAssertEqual(AudioDeviceModelMotion.rotation(normalizedX: 0.8, enabled: true, reduceMotion: true), 0)
        XCTAssertEqual(AudioDeviceModelMotion.rotation(normalizedX: 0.8, enabled: false, reduceMotion: false), 0)
        XCTAssertEqual(AudioDeviceModelMotion.rotation(normalizedX: .nan, enabled: true, reduceMotion: false), 0)
    }

    @MainActor
    func testSyntheticPreviewRendersWithoutLiveControllersOrExtraMotion() {
        let model = AudioDevicePresentation(name: "Sample AirPods Max")
        let host = NSHostingView(rootView: HStack {
            AudioDeviceModelView(family: model.family, motionEnabled: false)
            AudioDeviceConnectionLabel(name: model.name)
        }.padding(8).background(Color.black))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 52)
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        XCTAssertNotNil(bitmap)
        if let bitmap { host.cacheDisplay(in: host.bounds, to: bitmap) }
        XCTAssertNil(model.batteryPercentage)
    }
}
