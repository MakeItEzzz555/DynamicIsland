import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class NotchSettingsRoutingTests: XCTestCase {
    func testCollapsedClickExpandsButHoldOnlyOpensSettingsAndReleaseCannotRepeat() throws {
        try verifyPressLifecycle(expanded: false)
    }

    func testExpandedDoubleClickAndLongPressReachConfiguredActionsWithoutMenuStealingPress() throws {
        try verifyPressLifecycle(expanded: true)
    }

    private func verifyPressLifecycle(expanded: Bool) throws {
        let geometry = IslandBackgroundInteractionGeometry(size: CGSize(width: 300, height: 100),
            horizontalPadding: 20, bottomPadding: 12, contentTop: 38,
            notchSize: CGSize(width: 200, height: 32), allowsBackground: expanded)
        var expands = 0, holds = 0
        let view = IslandShellBackgroundInputView(frame: CGRect(origin: .zero, size: geometry.size))
        view.configure(IslandShellBackgroundInteraction(geometry: geometry, enabled: true,
            presentationGeneration: 1, clipboardEnabled: true, onEdit: {}, onClipboard: {}, onSettings: {},
            onNavigate: { _ in },
            onClick: expanded ? {} : { expands += 1 }, onLongPress: { holds += 1 }))
        let panel = IslandOverlayPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        defer { view.cancelPress(); panel.contentView = nil; panel.close() }
        func event(_ type: NSEvent.EventType, count: Int = 1, x: CGFloat = 150) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 65),
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 1, clickCount: count, pressure: 1))
        }
        panel.sendEvent(try event(.leftMouseDown))
        XCTAssertEqual(expands, 0, "press must allow a hold rather than expanding/opening a menu immediately")
        view.completeLongPress()
        panel.sendEvent(try event(.leftMouseUp))
        XCTAssertEqual(holds, 1)
        XCTAssertEqual(expands, 0, "long-press release never also expands")
        if !expanded {
            panel.sendEvent(try event(.leftMouseDown))
            panel.sendEvent(try event(.leftMouseUp))
            XCTAssertEqual(expands, 1)
            XCTAssertEqual(holds, 1)
        }
        // Double-click was removed: a second click is just another click.
        panel.sendEvent(try event(.leftMouseDown, count: 2))
        panel.sendEvent(try event(.leftMouseUp, count: 2))
        XCTAssertEqual(expands, expanded ? 0 : 2)
        XCTAssertEqual(holds, 1)
        panel.sendEvent(try event(.leftMouseDown))
        panel.sendEvent(try event(.leftMouseDragged, x: 180))
        view.completeLongPress()
        panel.sendEvent(try event(.leftMouseUp, x: 180))
        XCTAssertEqual(holds, 1, "moving outside press slop cancels the hold")
        XCTAssertEqual(expands, expanded ? 0 : 2)
        if !expanded {
            XCTAssertTrue(view.accessibilityPerformPress())
            XCTAssertEqual(expands, 3, "VoiceOver press follows collapsed click authority")
            XCTAssertEqual(holds, 1)
        }
    }

    func testExpandedNotchReleaseRetainsNativeSettingsMenu() throws {
        _ = NSApplication.shared
        let geometry = IslandBackgroundInteractionGeometry(size: CGSize(width: 300, height: 100),
            horizontalPadding: 20, bottomPadding: 12, contentTop: 38,
            notchSize: CGSize(width: 200, height: 32), allowsBackground: true)
        let view = IslandShellBackgroundInputView(frame: CGRect(origin: .zero, size: geometry.size))
        var settingsCalls = 0, fallbackUsed = false
        let tracking = NotchMenuTestObserver()
        view.configure(.init(geometry: geometry, enabled: true, presentationGeneration: 1, clipboardEnabled: true,
            onEdit: {}, onClipboard: {}, onSettings: { settingsCalls += 1 }, onNavigate: { _ in }))
        let panel = IslandOverlayPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = view; panel.orderFrontRegardless()
        defer { panel.contentView = nil; panel.close() }
        NotificationCenter.default.addObserver(tracking, selector: #selector(NotchMenuTestObserver.didBegin(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(tracking) }
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 150, y: 65), modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        let down = try click(panel, topPoint: CGPoint(x: 150, y: 35))
        let timer = Timer(timeInterval: 0.05, repeats: false) { _ in
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
            if let escape { NSApp.postEvent(escape, atStart: true) }
        }
        let safety = Timer(timeInterval: 0.75, repeats: false) { _ in
            MainActor.assumeIsolated { fallbackUsed = true; tracking.menu?.cancelTracking() }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(safety, forMode: .eventTracking)
        defer { timer.invalidate(); safety.invalidate() }
        panel.sendEvent(down); panel.sendEvent(up)
        XCTAssertTrue(tracking.began)
        XCTAssertFalse(fallbackUsed, "native Escape must dismiss the preserved left-click menu")
        let item = try XCTUnwrap(view.menu(for: down)?.item(withTag: 4))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(settingsCalls, 1)
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testPanelFindsProductionMenuBehindFullFrameContentInBothStates() throws {
        for expanded in [false, true] {
            let size = CGSize(width: expanded ? 600 : 240, height: expanded ? 240 : 40)
            var settingsCalls = 0
            let geometry = IslandBackgroundInteractionGeometry(size: size, horizontalPadding: 40,
                bottomPadding: 12, contentTop: 38, notchSize: CGSize(width: 200, height: 32),
                allowsBackground: expanded)
            let interaction = IslandShellBackgroundInteraction(geometry: geometry, enabled: true,
                presentationGeneration: 1, clipboardEnabled: true, onEdit: {}, onClipboard: {},
                onSettings: { settingsCalls += 1 }, onNavigate: { _ in })
            let settings = AppSettings(defaults: SettingsPreviewDefaults())
            let host = NSHostingView(rootView: IslandSurface(settings: settings, isExpanded: expanded,
                visualProgress: expanded ? 1 : 0, backgroundInteraction: interaction) {
                    NotchOccludingEditor()
                }.frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            let panel = IslandOverlayPanel(contentRect: host.frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = host
            defer { panel.contentView = nil; panel.close() }
            host.layoutSubtreeIfNeeded()
            let event = try click(panel, topPoint: CGPoint(x: size.width / 2, y: 35))
            let target = try XCTUnwrap(panel.notchActionsTarget(for: event), "reachable below the physical cutout")
            let menu = try XCTUnwrap(target.menu(for: event))
            let item = try XCTUnwrap(menu.item(withTag: 4))
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
            XCTAssertEqual(settingsCalls, 1)
            XCTAssertNil(panel.notchActionsTarget(for: try click(panel,
                topPoint: CGPoint(x: size.width / 2, y: 39))), "never steal content below clearance")
            XCTAssertNil(panel.notchActionsTarget(for: try click(panel,
                topPoint: CGPoint(x: 1, y: 35))), "never steal clicks outside the center notch lane")
            var protected = geometry
            protected.excludedRects = [protected.notchMenuRect]
            target.configure(IslandShellBackgroundInteraction(geometry: protected, enabled: true,
                presentationGeneration: 2, clipboardEnabled: true, onEdit: {}, onClipboard: {},
                onSettings: { settingsCalls += 1 }, onNavigate: { _ in }))
            XCTAssertNil(panel.notchActionsTarget(for: event), "native control ownership vetoes the route")
            target.configure(IslandShellBackgroundInteraction(geometry: geometry, enabled: false,
                presentationGeneration: 3, clipboardEnabled: true, onEdit: {}, onClipboard: {},
                onSettings: { settingsCalls += 1 }, onNavigate: { _ in }))
            XCTAssertNil(panel.notchActionsTarget(for: event), "shell morph cannot open a stale menu")
            _ = NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
            XCTAssertEqual(settingsCalls, 1)
        }
    }

    func testNonNotchedDisplayKeepsSmallEmptyTopCenterEntry() {
        let geometry = IslandBackgroundInteractionGeometry(size: CGSize(width: 600, height: 300),
            horizontalPadding: 40, bottomPadding: 12, contentTop: 16,
            notchSize: .zero, allowsBackground: true)
        XCTAssertEqual(geometry.region(at: CGPoint(x: 300, y: 8)), .notch)
        XCTAssertNil(geometry.region(at: CGPoint(x: 300, y: 16)))
        XCTAssertNil(geometry.region(at: CGPoint(x: 230, y: 8)))
    }

    private func click(_ panel: NSPanel, topPoint: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: topPoint.x, y: panel.contentView!.bounds.height - topPoint.y),
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
}

private struct NotchOccludingEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextView { NSTextView(frame: .zero) }
    func updateNSView(_ view: NSTextView, context: Context) {}
}

@MainActor
private final class NotchMenuTestObserver: NSObject {
    var menu: NSMenu?
    var began = false
    @objc func didBegin(_ note: Notification) {
        began = true
        menu = note.object as? NSMenu
    }
}
