import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class NotchContextMenuTests: XCTestCase {
    func testHostedRightClickReachesAllAccessibleEmptyTopRegionsAtDifferentWidths() throws {
        _ = NSApplication.shared
        for width: CGFloat in [240, 340, 600] {
            let (panel, background) = makePanel(width: width, notched: true)
            defer { panel.contentView = nil; panel.close() }
            for point in [CGPoint(x: 12, y: 4), CGPoint(x: width / 2, y: 35), CGPoint(x: width - 12, y: 4)] {
                let event = try event(panel, point: point)
                XCTAssertTrue(panel.notchActionsTarget(for: event) === background)
                var routes = 0
                panel.onNotchRightClick = { incoming in
                    guard panel.notchActionsTarget(for: incoming) != nil else { return false }
                    routes += 1; return true
                }
                panel.sendEvent(event)
                XCTAssertEqual(routes, 1)
            }
            XCTAssertNil(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: width / 2, y: 10))), "physical cutout is not an accessible menu target")
            XCTAssertTrue(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: width / 2, y: 39))) === background,
                          "right-click opens the island menu anywhere on the collapsed shell")
            XCTAssertNil(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: -1, y: 10))))
            XCTAssertFalse(panel.isKeyWindow, "passive context routing never acquires the editor keyboard")
        }
    }

    func testUppermostDeliverablePixelsUseTheProductionShoulderContour() throws {
        for width: CGFloat in [240, 340, 600] {
            for notched in [true, false] {
                let (panel, background) = makePanel(width: width, notched: notched)
                defer { panel.contentView = nil; panel.close() }
                let geometry = IslandBackgroundInteractionGeometry(size: CGSize(width: width, height: 40),
                    horizontalPadding: 20, bottomPadding: 4, contentTop: 38,
                    notchSize: notched ? CGSize(width: 200, height: 32) : .zero, allowsBackground: false)
                background.configure(IslandShellBackgroundInteraction(geometry: geometry, enabled: true,
                    presentationGeneration: 1, clipboardEnabled: true, onEdit: {}, onClipboard: {},
                    onSettings: {}, onNavigate: { _ in }).clipped(to: .init(topCornerRadius: notched ? 6 : 0, bottomCornerRadius: 14)))
                let xs: [CGFloat] = notched ? [12, width - 12] : [12, width / 2, width - 12]
                for x in xs {
                    for y: CGFloat in [0, 0.25, 0.5, 1, 2] {
                        let click = try event(panel, point: CGPoint(x: x, y: y))
                        XCTAssertTrue(panel.notchActionsTarget(for: click) === background, "top edge x=\(x) y=\(y)")
                        var routed = false
                        panel.onNotchRightClick = { incoming in
                            routed = panel.notchActionsTarget(for: incoming) === background; return routed
                        }
                        panel.sendEvent(click)
                        XCTAssertTrue(routed)
                    }
                }
                XCTAssertNil(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: 12, y: -0.25))))
                if notched { XCTAssertNil(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: width / 2, y: 0)))) }
            }
        }
    }

    func testNotchlessFallbackDoesNotClaimDesktopOrExpandedContent() throws {
        for expanded in [false, true] {
            let (panel, _) = makePanel(width: 360, notched: false, expanded: expanded)
            defer { panel.contentView = nil; panel.close() }
            // Top-center lane: island menu in both states (expanded header lane is empty chrome).
            XCTAssertNotNil(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: 180, y: 10))))
            // Below the lane: the whole collapsed shell, but never expanded content.
            XCTAssertEqual(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: 180, y: 25))) != nil, !expanded)
            XCTAssertNil(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: 400, y: 10))), "never the desktop")
        }
    }

    func testRegisteredControlsAndCompactContentHavePriorityIncludingFileContextMenu() throws {
        let exclusion = CGRect(x: 0, y: 8, width: 48, height: 16)
        let (panel, _) = makePanel(width: 340, notched: true, exclusions: [exclusion])
        defer { panel.contentView = nil; panel.close() }
        let file = RightClickControl(frame: CGRect(x: 0, y: 40 - exclusion.maxY, width: 48, height: 16))
        panel.contentView?.addSubview(file)
        let click = try event(panel, point: CGPoint(x: 20, y: 16))
        XCTAssertNil(panel.notchActionsTarget(for: click))
        XCTAssertTrue(panel.contentView?.hitTest(click.locationInWindow) === file)
        panel.sendEvent(click)
        XCTAssertEqual(file.rightClicks, 1, "AppKit forwards the file context event instead of invoking island actions")
        XCTAssertNotNil(panel.notchActionsTarget(for: try event(panel, point: CGPoint(x: 320, y: 16))),
                        "compact wings are part of the right-click surface; only registered controls keep their events")
    }

    func testSharedSettingsAndNormalQuitCallbacksAndRequiredMenuOrder() throws {
        _ = NSApplication.shared
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.menuBarIconEnabled = false
        var opened = 0, quit = 0
        let controller = MenuBarController(settings: settings, onOpenSettings: { opened += 1 },
            onToggleOverlay: {}, onQuit: { quit += 1 })
        let menu = controller.makeNotchMenu()
        XCTAssertEqual(menu.items.map(\.title), ["Settings…", "Customize Workspace…", "Clipboard", "Live Audio", "",
                                                 "Previous Page", "Next Page", "", "Quit Island"])
        XCTAssertTrue(menu.items[4].isSeparatorItem); XCTAssertTrue(menu.items[7].isSeparatorItem)
        XCTAssertEqual(menu.items[3].state, .off, "Live Audio reflects the saved preference")
        for index in [1, 3, 5, 6] { XCTAssertTrue(menu.items[index].target === controller) }
        for index in [0, 8] {
            let item = menu.items[index]
            XCTAssertTrue(item.target === controller)
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        }
        XCTAssertEqual(opened, 1); XCTAssertEqual(quit, 1)
    }

    func testClipboardUsesSharedRouteAndRevalidatesDisabledPreference() async throws {
        _ = NSApplication.shared
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.menuBarIconEnabled = false; settings.clipboardHistoryEnabled = true
        var opened = 0
        let controller = MenuBarController(settings: settings, onOpenSettings: {}, onToggleOverlay: {},
            onQuit: {}, onOpenClipboard: { opened += 1 })
        let item = try XCTUnwrap(controller.makeNotchMenu().items.first { $0.title == "Clipboard" }?.submenu?.items.first)
        XCTAssertEqual(item.title, "Open Clipboard History")
        XCTAssertTrue(item.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(opened, 1)
        settings.clipboardHistoryEnabled = false
        _ = NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(opened, 1)
        let disabled = try XCTUnwrap(controller.makeNotchMenu().items.first { $0.title == "Clipboard" })
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertFalse(try XCTUnwrap(disabled.submenu?.items.first).isEnabled)
    }

    func testNestedTrackingReleasesOnlyMenuHoldAfterFinalDismissal() {
        let layout = IslandLayoutStore()
        var lifecycle = NativeMenuTrackingLifecycle()
        layout.setTransientInteraction(true, owner: .workspaceEditor)
        lifecycle.begin(); lifecycle.begin()
        layout.setTransientInteraction(lifecycle.isTracking, owner: .nativeMenu)
        lifecycle.end()
        layout.setTransientInteraction(lifecycle.isTracking, owner: .nativeMenu)
        XCTAssertTrue(layout.transientInteractionOwners.contains(.nativeMenu))
        lifecycle.end()
        layout.setTransientInteraction(lifecycle.isTracking, owner: .nativeMenu)
        XCTAssertFalse(layout.transientInteractionOwners.contains(.nativeMenu))
        XCTAssertTrue(layout.transientInteractionOwners.contains(.workspaceEditor))
        lifecycle.end(); XCTAssertEqual(lifecycle.depth, 0)
    }

    func testClipboardActionWaitsForLastSubmenuAndReleasesExactlyOnce() {
        var lifecycle = NativeMenuTrackingLifecycle()
        XCTAssertFalse(lifecycle.deferWorkspaceAction(.clipboard))
        lifecycle.begin(); lifecycle.begin()
        XCTAssertTrue(lifecycle.deferWorkspaceAction(.clipboard))
        XCTAssertNil(lifecycle.end())
        XCTAssertTrue(lifecycle.isTracking)
        XCTAssertEqual(lifecycle.end(), .clipboard)
        XCTAssertNil(lifecycle.end())
        XCTAssertFalse(lifecycle.isTracking)
    }

    func testActualNativePopupTracksAndEscapeReleasesOnlyItsOwnHold() throws {
        let (panel, background) = makePanel(width: 340, notched: false)
        defer { panel.contentView = nil; panel.close() }
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.menuBarIconEnabled = false
        let controller = MenuBarController(settings: settings, onOpenSettings: {}, onToggleOverlay: {}, onQuit: {})
        let menu = controller.makeNotchMenu()
        let layout = IslandLayoutStore()
        layout.setTransientInteraction(true, owner: .workspaceEditor)
        var lifecycle = NativeMenuTrackingLifecycle(), began = 0, ended = 0
        let center = NotificationCenter.default
        let start = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: menu, queue: .main) { _ in
            MainActor.assumeIsolated {
                began += 1; lifecycle.begin(); layout.setTransientInteraction(true, owner: .nativeMenu)
            }
        }
        let end = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: menu, queue: .main) { _ in
            MainActor.assumeIsolated {
                ended += 1; lifecycle.end(); layout.setTransientInteraction(lifecycle.isTracking, owner: .nativeMenu)
            }
        }
        defer { center.removeObserver(start); center.removeObserver(end) }
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        var escapePosted = false, fallbackUsed = false
        let keyTimer = Timer(timeInterval: 0.05, repeats: false) { _ in
            MainActor.assumeIsolated { escapePosted = true; NSApp.postEvent(escape, atStart: true) }
        }
        let safetyTimer = Timer(timeInterval: 0.5, repeats: false) { _ in
            MainActor.assumeIsolated { fallbackUsed = true; menu.cancelTracking() }
        }
        RunLoop.main.add(keyTimer, forMode: .eventTracking)
        RunLoop.main.add(safetyTimer, forMode: .eventTracking)
        defer { keyTimer.invalidate(); safetyTimer.invalidate() }
        CameraNativeHostedFixture.pump()
        let active = NSApp.isActive
        NSMenu.popUpContextMenu(menu, with: try event(panel, point: CGPoint(x: 170, y: 4)), for: background)
        XCTAssertGreaterThan(began, 0)
        XCTAssertEqual(began, ended)
        XCTAssertTrue(escapePosted)
        XCTAssertFalse(fallbackUsed, "native Escape must dismiss; the bounded safety timer is not acceptance")
        XCTAssertFalse(layout.transientInteractionOwners.contains(.nativeMenu))
        XCTAssertTrue(layout.transientInteractionOwners.contains(.workspaceEditor))
        XCTAssertEqual(NSApp.isActive, active)
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testMorphDisablesStaleMenuTargetWithoutChangingLeftClickAuthority() throws {
        let (panel, background) = makePanel(width: 340, notched: true)
        defer { panel.contentView = nil; panel.close() }
        let click = try event(panel, point: CGPoint(x: 170, y: 35))
        XCTAssertNotNil(panel.notchActionsTarget(for: click))
        let geometry = IslandBackgroundInteractionGeometry(size: CGSize(width: 340, height: 40),
            horizontalPadding: 20, bottomPadding: 4, contentTop: 38,
            notchSize: CGSize(width: 200, height: 32), allowsBackground: false)
        background.configure(.init(geometry: geometry, enabled: false, presentationGeneration: 2,
            clipboardEnabled: true, onEdit: {}, onClipboard: {}, onSettings: {}, onNavigate: {_ in}))
        XCTAssertNil(panel.notchActionsTarget(for: click))
    }

    private func makePanel(width: CGFloat, notched: Bool, expanded: Bool = false,
                           exclusions: [CGRect] = []) -> (IslandOverlayPanel, IslandShellBackgroundInputView) {
        _ = NSApplication.shared
        let size = CGSize(width: width, height: 40)
        let panel = IslandOverlayPanel(contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        let background = IslandShellBackgroundInputView(frame: container.bounds)
        let geometry = IslandBackgroundInteractionGeometry(size: size, horizontalPadding: 20,
            bottomPadding: 4, contentTop: 38, notchSize: notched ? CGSize(width: 200, height: 32) : .zero,
            allowsBackground: expanded, excludedRects: exclusions,
            )
        background.configure(.init(geometry: geometry, enabled: true, presentationGeneration: 1,
            clipboardEnabled: true, onEdit: {}, onClipboard: {}, onSettings: {}, onNavigate: {_ in}))
        container.addSubview(background)
        let occluder = NSHostingView(rootView: Color.clear)
        occluder.frame = container.bounds; container.addSubview(occluder)
        panel.contentView = container
        panel.orderFrontRegardless()
        return (panel, background)
    }
    private func event(_ panel: NSPanel, point: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown,
            location: CGPoint(x: point.x, y: 40 - point.y), modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
}

private final class RightClickControl: NSControl {
    var rightClicks = 0
    override func rightMouseDown(with event: NSEvent) { rightClicks += 1 }
}
