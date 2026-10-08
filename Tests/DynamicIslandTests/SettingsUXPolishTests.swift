import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class SettingsUXPolishTests: XCTestCase {
    func testNavigationDefaultsRestoreRecoveryWithoutChangingModulesOrPlacement() {
        let defaults = SettingsPreviewDefaults()
        let settings = AppSettings(defaults: defaults)
        let workspace = WorkspaceCustomizationStore(defaults: defaults)
        var configuration = workspace.configuration
        configuration.add(.timer, on: .media)
        configuration.markCustomized(.media)
        workspace.commit(configuration)
        let saved = workspace.configuration

        settings.showNavigationControls = false
        settings.gestureInputSource = .none
        settings.collapsedDoubleClickAction = .openSettings
        settings.expandedLongPressAction = .none
        settings.showTimerTab = false
        settings.mediaEnabled = false
        settings.timerPreset1Minutes = 37

        SettingsCategoryDefaults.restore(.tabs, settings: settings)

        let restored = AppSettings(defaults: defaults)
        let expected = AppSettings(defaults: SettingsPreviewDefaults())
        XCTAssertTrue(restored.showNavigationControls)
        XCTAssertTrue(restored.threeFingerTabNavigationEnabled)
        XCTAssertEqual(restored.gestureInputSource, expected.gestureInputSource)
        XCTAssertEqual(restored.collapsedDoubleClickAction, expected.collapsedDoubleClickAction)
        XCTAssertEqual(restored.expandedLongPressAction, expected.expandedLongPressAction)
        XCTAssertTrue(restored.showTimerTab)
        XCTAssertFalse(restored.mediaEnabled, "navigation defaults never re-enable an unrelated module")
        XCTAssertEqual(restored.timerPreset1Minutes, 37)
        XCTAssertEqual(WorkspaceCustomizationStore(defaults: defaults).configuration, saved)
    }

    func testCategoryDefaultsUseProductionValuesAndPreserveOtherCategories() {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let expected = AppSettings(defaults: SettingsPreviewDefaults())
        settings.timerEnabled = false
        settings.timerPreset1Minutes = 37
        settings.timerSoundEnabled = false
        settings.gestureSensitivity = 0.31
        settings.shellOpacity = 0.43
        SettingsCategoryDefaults.restore(.timer, settings: settings)
        XCTAssertEqual(settings.timerEnabled, expected.timerEnabled)
        XCTAssertEqual(settings.timerPreset1Minutes, expected.timerPreset1Minutes)
        XCTAssertEqual(settings.timerSoundEnabled, expected.timerSoundEnabled)
        XCTAssertEqual(settings.gestureSensitivity, 0.31)
        XCTAssertEqual(settings.shellOpacity, 0.43)

        settings.clipboardHistoryEnabled = true
        settings.clipboardHistoryMaximumItems = 133
        settings.clipboardHistoryExcludedAppBundleIDs = ["com.example.private-notes"]
        SettingsCategoryDefaults.restore(.clipboard, settings: settings)
        XCTAssertEqual(settings.clipboardHistoryEnabled, expected.clipboardHistoryEnabled)
        XCTAssertEqual(settings.clipboardHistoryMaximumItems, expected.clipboardHistoryMaximumItems)
        XCTAssertEqual(settings.clipboardHistoryExcludedAppBundleIDs, ["com.example.private-notes"],
                       "restoring options keeps explicit privacy exclusions")
    }

    func testEveryCategoryRestorePreservesWorkspaceAndClipboardPrivacy() {
        for section in SettingsSection.allCases where SettingsCategoryDefaults.supports(section) {
            let defaults = SettingsPreviewDefaults()
            let settings = AppSettings(defaults: defaults)
            let workspace = WorkspaceCustomizationStore(defaults: defaults)
            var configuration = workspace.configuration
            configuration.add(.timer, on: .media)
            configuration.markCustomized(.media)
            configuration.navigation.hidden.insert(.stats)
            workspace.commit(configuration)
            let saved = workspace.configuration
            settings.clipboardHistoryExcludedAppBundleIDs = ["com.example.private-notes"]

            SettingsCategoryDefaults.restore(section, settings: settings)

            XCTAssertEqual(WorkspaceCustomizationStore(defaults: defaults).configuration, saved, section.rawValue)
            XCTAssertEqual(AppSettings(defaults: defaults).clipboardHistoryExcludedAppBundleIDs,
                           ["com.example.private-notes"], section.rawValue)
        }
    }

    func testSyntheticAudioPreviewsUseNamedProductionFamiliesWithoutInventingBattery() {
        let cases: [(SystemHUDPreviewCase, AudioOutputDeviceKind)] = [
            (.airPods, .airPods), (.airPodsPro, .airPodsPro), (.airPodsGen3, .airPodsGen3),
            (.airPodsMax, .airPodsMax), (.beats, .beats), (.headphones, .headphones),
            (.earbuds, .earbuds), (.genericAudio, .generic)
        ]
        for (sample, family) in cases {
            let activity = sample.activity()
            let device = AudioDevicePresentation(name: activity.title)
            XCTAssertEqual(activity.systemHUDKind, .audioDevice)
            XCTAssertEqual(device.family, family, sample.rawValue)
            XCTAssertEqual(activity.symbolName, family.symbolName)
            XCTAssertEqual(activity.subtitle, "Connected")
            XCTAssertNil(activity.progress)
            XCTAssertNil(device.batteryPercentage)
        }
        XCTAssertTrue(SystemHUDPreviewCase.airPodsPro.activity().title.contains("Maya"))
    }

    func testHUDPreviewSwitchesTrackTheirProductionDependencies() {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.systemHUDsEnabled = true
        settings.audioDeviceHUDEnabled = true
        XCTAssertTrue(SystemHUDPreviewCase.airPodsPro.isEnabled(settings: settings))
        settings.audioDeviceHUDEnabled = false
        XCTAssertFalse(SystemHUDPreviewCase.airPodsPro.isEnabled(settings: settings))
        settings.volumeHUDEnabled = true
        XCTAssertTrue(SystemHUDPreviewCase.volume.isEnabled(settings: settings))
        settings.systemHUDsEnabled = false
        XCTAssertTrue(SystemHUDPreviewCase.allCases.allSatisfy { !$0.isEnabled(settings: settings) })
        XCTAssertFalse(SystemHUDPreviewCase.lowBattery.hasAdjustableLevel)
        XCTAssertEqual(SystemHUDPreviewCase.lowBattery.activity(value: 0.9).progress, 0.15)
    }

    func testMountedPreviewReactsToNavigationModeAndRestoresSharedGeometry() async throws {
        _ = NSApplication.shared
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let recorder = NavigationPreviewRecorder()
        let view = NavigationPreviewProbe(settings: settings, recorder: recorder)
        let host = NSHostingView(rootView: view.frame(width: 560, height: 240))
        host.frame = CGRect(x: 0, y: 0, width: 560, height: 240)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        func settle() async throws {
            for _ in 0..<4 { try await Task.sleep(for: .milliseconds(5)); host.layoutSubtreeIfNeeded() }
        }
        try await settle()
        let visible = try XCTUnwrap(recorder.presentation)
        XCTAssertTrue(visible.chrome.showHeader)
        settings.showNavigationControls = false
        try await settle()
        let hidden = try XCTUnwrap(recorder.presentation)
        XCTAssertEqual(hidden.header.mode, .hidden)
        XCTAssertFalse(hidden.chrome.showHeader)
        XCTAssertEqual(hidden.chrome.tabSwitcherHeight, 0)
        XCTAssertEqual(hidden.chrome.tabToPageSpacing, 0)
        XCTAssertLessThan(hidden.chrome.workspaceVerticalChrome, visible.chrome.workspaceVerticalChrome)
        settings.showNavigationControls = true
        try await settle()
        let restored = try XCTUnwrap(recorder.presentation)
        XCTAssertEqual(restored.chrome.topPadding, visible.chrome.topPadding)
        XCTAssertEqual(restored.geometry.expandedFrame.size, visible.geometry.expandedFrame.size)
    }
}

@MainActor
private final class NavigationPreviewRecorder {
    var presentation: SettingsPreviewPresentation?
}

private struct NavigationPreviewProbe: View {
    @ObservedObject var settings: AppSettings
    let recorder: NavigationPreviewRecorder

    var body: some View {
        recorder.presentation = SettingsPreviewPresentation(settings: settings)
        return IslandShellSettingsPreview(settings: settings)
    }
}
