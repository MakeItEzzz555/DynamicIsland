import AppKit
import XCTest
@testable import DynamicIsland

final class OverlayDisplayPolicyTests: XCTestCase {
    func testAppExclusionValidationKeepsOrderCapsDuplicatesAndNeverHidesOwnApp() {
        let input = ["com.example.Editor", "COM.EXAMPLE.EDITOR", "invalid/path", "com.local.dynamicisland", "com.example.Browser"]
        let normalized = OverlayDisplayPolicy.normalizedAppExclusions(input, ownBundleID: "com.local.dynamicisland")
        XCTAssertEqual(normalized, ["com.example.Editor", "com.example.Browser"])
        XCTAssertTrue(OverlayDisplayPolicy.hidesInApp("COM.EXAMPLE.EDITOR", exclusions: normalized, ownBundleID: "com.local.dynamicisland"))
        XCTAssertFalse(OverlayDisplayPolicy.hidesInApp("com.local.dynamicisland", exclusions: ["com.local.dynamicisland"], ownBundleID: "com.local.dynamicisland"))
        XCTAssertFalse(OverlayDisplayPolicy.hidesInApp(nil, exclusions: normalized, ownBundleID: nil))
        XCTAssertEqual(OverlayDisplayPolicy.normalizedAppExclusions((0..<100).map { "com.example.app\($0)" }, ownBundleID: nil).count, 64)
    }
    @MainActor
    func testAppExclusionsPersistAfterNormalizationAndResetPreservesPrivacy() {
        let defaults = SettingsPreviewDefaults(); let settings = AppSettings(defaults: defaults)
        settings.hiddenInAppBundleIDs = ["com.example.Editor", "COM.EXAMPLE.EDITOR", "bad/id"]
        XCTAssertEqual(settings.hiddenInAppBundleIDs, ["com.example.Editor"])
        XCTAssertEqual(AppSettings(defaults: defaults).hiddenInAppBundleIDs, settings.hiddenInAppBundleIDs)
        settings.hiddenInAppBundleIDs += ["com.example.Browser"]
        settings.hiddenInAppBundleIDs.swapAt(0, 1)
        XCTAssertEqual(AppSettings(defaults: defaults).hiddenInAppBundleIDs, ["com.example.Browser", "com.example.Editor"])
        settings.resetPreferencesPreservingAccess()
        XCTAssertEqual(settings.hiddenInAppBundleIDs, ["com.example.Browser", "com.example.Editor"])
    }
    func testThreeStatesAffectExternalDisplaysOnlyAndDeferProtectedInteractions() {
        for preference in ExternalDisplayVisibility.allCases {
            XCTAssertTrue(preference.permits(isExternal: false, active: false, protectedInteraction: false))
            XCTAssertTrue(preference.permits(isExternal: true, active: false, protectedInteraction: true))
        }
        XCTAssertFalse(ExternalDisplayVisibility.never.permits(isExternal: true, active: true, protectedInteraction: false))
        XCTAssertFalse(ExternalDisplayVisibility.whenActive.permits(isExternal: true, active: false, protectedInteraction: false))
        XCTAssertTrue(ExternalDisplayVisibility.whenActive.permits(isExternal: true, active: true, protectedInteraction: false))
        XCTAssertTrue(ExternalDisplayVisibility.always.permits(isExternal: true, active: false, protectedInteraction: false))
    }
    func testFullscreenOverlayBehaviorKeepsSpaceAndWindowCycleContract() {
        let shown = OverlayDisplayPolicy.collectionBehavior(showInFullscreen: true)
        let hidden = OverlayDisplayPolicy.collectionBehavior(showInFullscreen: false)
        XCTAssertTrue(shown.contains(.fullScreenAuxiliary)); XCTAssertFalse(hidden.contains(.fullScreenAuxiliary))
        XCTAssertTrue(hidden.contains(.canJoinAllSpaces)); XCTAssertTrue(hidden.contains(.ignoresCycle))
    }
    @MainActor
    func testPreferencesPersistAndDoNotChangeSettingsFullscreenAuthority() {
        let defaults = SettingsPreviewDefaults(); let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.externalDisplayVisibility, .always); XCTAssertTrue(settings.showOverlayInFullscreen)
        settings.externalDisplayVisibility = .whenActive; settings.showOverlayInFullscreen = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.externalDisplayVisibility, .whenActive); XCTAssertFalse(reloaded.showOverlayInFullscreen)
        _ = NSApplication.shared
        let name = "DynamicIsland.Settings.Test.\(UUID().uuidString)"
        let window = SettingsWindowController.makeWindow(frameAutosaveName: name)
        defer { window.setFrameAutosaveName(""); window.close(); NSWindow.removeFrame(usingName: name) }
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
    }
}
