import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testResetPanelSizeUsesOwnedWindowWithoutChangingIslandPreferences() throws {
        _ = NSApplication.shared
        let name = "DynamicIsland.Settings.Test.\(UUID().uuidString)"
        let window = SettingsWindowController.makeWindow(frameAutosaveName: name)
        defer { window.setFrameAutosaveName(""); window.close(); NSWindow.removeFrame(usingName: name) }
        window.setContentSize(NSSize(width: 950, height: 800))
        XCTAssertTrue(SettingsWindowController.resetPanelSize(window))
        let size = try XCTUnwrap(window.contentView).bounds.size
        XCTAssertEqual(size.width, 720, accuracy: 1); XCTAssertEqual(size.height, 700, accuracy: 1)
    }
    func testNativeWindowSupportsStandardControlsAndFullscreen() {
        _ = NSApplication.shared
        let name = "DynamicIsland.Settings.Test.\(UUID().uuidString)"
        let window = SettingsWindowController.makeWindow(frameAutosaveName: name)
        defer {
            window.setFrameAutosaveName("")
            window.close()
            NSWindow.removeFrame(usingName: name)
        }

        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertNotNil(window.standardWindowButton(.closeButton))
        XCTAssertNotNil(window.standardWindowButton(.miniaturizeButton))
        XCTAssertNotNil(window.standardWindowButton(.zoomButton))
        XCTAssertEqual(window.contentMinSize, SettingsWindowController.minimumContentSize)
        XCTAssertFalse(window.isReleasedWhenClosed)
    }

    func testWindowMenuUsesNativeChordsAndExactTargetWithoutAnIslandCloseAction() {
        let target = NSObject()
        let menu = SettingsWindowController.makeWindowMenu(target: target)
        XCTAssertEqual(menu.items.map(\.keyEquivalent), [",", "w", "m", "f"])
        XCTAssertEqual(menu.items.map(\.keyEquivalentModifierMask), [.command, .command, .command, [.command, .control]])
        XCTAssertTrue(menu.items.allSatisfy { $0.target === target })
        XCTAssertEqual(menu.items.map { NSStringFromSelector($0.action!) }, ["showSettings:", "closeSettings:", "minimizeSettings:", "fullscreenSettings:"])
    }

    func testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy() throws {
        _ = NSApplication.shared
        let name = "DynamicIsland.Settings.Test.\(UUID().uuidString)"
        let window = SettingsWindowController.makeWindow(frameAutosaveName: name)
        var presses = 0
        window.contentView = NSHostingView(rootView: Button("Native Settings action") { presses += 1 }
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        CameraNativeHostedFixture.pump()
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer {
            router.shutdown(); window.setFrameAutosaveName(""); window.close()
            NSWindow.removeFrame(usingName: name)
            NSApp.setActivationPolicy(previousPolicy)
        }
        XCTAssertNotNil(window as? CameraLocalEventWindow)
        let content = try XCTUnwrap(window.contentView)
        let point = content.convert(CGPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil)
        CameraNativeHostedFixture.click(router, at: point)
        XCTAssertEqual(presses, 1)
    }

    func testNativeFrameRestoresSizeAndPositionAfterClose() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let name = "DynamicIsland.Settings.Test.\(UUID().uuidString)"
        defer { NSWindow.removeFrame(usingName: name) }
        let original = SettingsWindowController.makeWindow(frameAutosaveName: name)
        let visible = screen.visibleFrame
        original.setContentSize(NSSize(width: min(1000, visible.width - 80),
                                       height: min(720, visible.height - 100)))
        original.setFrameOrigin(NSPoint(x: visible.minX + 30, y: visible.minY + 30))
        let expected = original.frame
        original.setFrameAutosaveName("")
        original.close()

        let restored = SettingsWindowController.makeWindow(frameAutosaveName: name)
        defer {
            restored.setFrameAutosaveName("")
            restored.close()
        }
        XCTAssertEqual(restored.frame.minX, expected.minX, accuracy: 1)
        XCTAssertEqual(restored.frame.minY, expected.minY, accuracy: 1)
        XCTAssertEqual(restored.frame.width, expected.width, accuracy: 1)
        XCTAssertEqual(restored.frame.height, expected.height, accuracy: 1)
    }

    func testHostingSurfaceFollowsNativeWindowResize() {
        _ = NSApplication.shared
        let name = "DynamicIsland.Settings.Test.\(UUID().uuidString)"
        let window = SettingsWindowController.makeWindow(frameAutosaveName: name)
        defer {
            window.setFrameAutosaveName("")
            window.close()
            NSWindow.removeFrame(usingName: name)
        }
        let host = NSHostingView(rootView: Text("Settings window resize fixture")
            .frame(minWidth: SettingsWindowController.minimumContentSize.width, maxWidth: .infinity,
                   minHeight: SettingsWindowController.minimumContentSize.height, maxHeight: .infinity))
        window.contentView = host
        window.setContentSize(NSSize(width: 1100, height: 800))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.bounds.width, 1100, accuracy: 1)
        XCTAssertEqual(host.bounds.height, 800, accuracy: 1)
        window.setContentSize(SettingsWindowController.minimumContentSize)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.bounds.size, SettingsWindowController.minimumContentSize)
    }
}
