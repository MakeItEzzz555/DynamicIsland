import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class DetachedIslandNavigationTests: XCTestCase {
    func testFooterIsCenteredOutsideShellAndPanelContainsBothSizes() {
        for count in [1, 4, 7] {
            for size in [CGSize(width: 160, height: 200), CGSize(width: 760, height: 500)] {
                let shell = CGRect(origin: CGPoint(x: 400, y: 600), size: size)
                var profile = ExpandedPresentationProfile.standard
                profile.accessoryHeight = DetachedIslandNavigationMetrics.accessoryHeight
                profile.accessoryWidth = DetachedIslandNavigationMetrics.width(pageCount: count)
                let footer = DetachedIslandNavigationMetrics.frame(shell: shell, pageCount: count)
                let panel = profile.panelFrame(forExpandedFrame: shell)
                XCTAssertEqual(footer.midX, shell.midX)
                XCTAssertEqual(shell.minY - footer.maxY, DetachedIslandNavigationMetrics.gap)
                XCTAssertTrue(panel.contains(footer))
                XCTAssertEqual(panel.maxY, shell.maxY, "notch/top anchor never moves")
                let bridge = CGPoint(x: footer.midX, y: footer.maxY + DetachedIslandNavigationMetrics.gap / 2)
                XCTAssertNotEqual(ExpandedHoverContainment.decide(pointer: bridge, shellFrame: shell,
                    accessoryFrames: [footer], holds: []), .collapse)
            }
        }
    }

    func testTrayNavigationIsImmediatelyBelowTheShell() {
        let shell = CGRect(x: 100, y: 300, width: 180, height: 400)
        let footer = DetachedIslandNavigationMetrics.frame(shell: shell, pageCount: 7)
        XCTAssertEqual(shell.minY - footer.maxY, 3)
        var profile = ExpandedPresentationProfile.resolve(for: .tray)
        profile.accessoryHeight += DetachedIslandNavigationMetrics.accessoryHeight
        profile.accessoryWidth = footer.width
        XCTAssertTrue(profile.panelFrame(forExpandedFrame: shell).contains(footer))
    }

    func testAccessoryOwnershipDoesNotRemoveOtherControls() {
        let layout = IslandLayoutStore()
        let shell = layout.expandedSurfaceFrame
        let nav = DetachedIslandNavigationMetrics.frame(shell: shell, pageCount: 4)
        let tray = CGRect(x: shell.midX - 60, y: shell.minY - 40, width: 120, height: 30)
        layout.setExpandedAccessoryFrames([tray], owner: .trayQuickActions)
        layout.setExpandedAccessoryFrames([nav], owner: .navigation)
        XCTAssertTrue(layout.expandedPrecisionInteractionFrame.contains(nav))
        layout.setExpandedAccessoryFrames([], owner: .navigation)
        XCTAssertEqual(layout.expandedAccessoryFrames, [tray.integral])
        XCTAssertEqual(layout.expandedPrecisionInteractionFrame, shell)
    }

    func testNormalCollapseReturnRejectsStaleCompletionAndExpansionCancellation() {
        let layout = IslandLayoutStore()
        let first = layout.beginNormalCollapsedReturn()
        XCTAssertTrue(layout.isReturningToNormalCollapsedSize)
        let second = layout.beginNormalCollapsedReturn()
        XCTAssertFalse(layout.finishNormalCollapsedReturn(generation: first))
        XCTAssertTrue(layout.isReturningToNormalCollapsedSize)
        XCTAssertTrue(layout.finishNormalCollapsedReturn(generation: second))
        XCTAssertFalse(layout.isReturningToNormalCollapsedSize)
        XCTAssertFalse(layout.finishNormalCollapsedReturn(generation: second))
        let interrupted = layout.beginNormalCollapsedReturn()
        layout.cancelNormalCollapsedReturn()
        XCTAssertFalse(layout.finishNormalCollapsedReturn(generation: interrupted))
        XCTAssertFalse(layout.isReturningToNormalCollapsedSize)
    }

    func testProductionFooterDeliversNativePageAndEditActionsWithoutSystemCursorMovement() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "DetachedFooter-\(UUID().uuidString)")!)
        settings.agentActivityEnabled = true
        settings.showAgentsTab = true
        let navigation = IslandNavigationStore()
        let pages = navigation.availablePages(using: settings)
        let width = DetachedIslandNavigationMetrics.width(pageCount: pages.count)
        var edits = 0
        var moved = 0
        let anchor = TabPointerAnchor(movePointer: { _ in moved += 1; return true })
        let view = DetachedIslandNavigationBar(settings: settings, navigation: navigation, pointerAnchor: anchor,
            onEdit: { edits += 1 }, onEditTabs: {}, onReset: {})
        let window = CameraNativeHostedFixture.hosted(view, size: CGSize(width: width, height: DetachedIslandNavigationMetrics.height))
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        defer { router.shutdown(); window.close() }
        for (index, page) in pages.enumerated() {
            let x = 8 + CGFloat(index) * (ExpandedIslandHeaderMetrics.buttonWidth + ExpandedIslandHeaderMetrics.tabSpacing) + 15
            CameraNativeHostedFixture.click(router, at: CGPoint(x: x, y: 19))
            XCTAssertEqual(navigation.selectedPage, page)
        }
        CameraNativeHostedFixture.click(router, at: CGPoint(x: width - 19, y: 19))
        XCTAssertEqual(edits, 1)
        XCTAssertFalse(anchor.isActive)
        XCTAssertEqual(moved, 0)
    }

    func testExpandedContourClearsContentCornersAndUsesOnePath() {
        let radii = IslandShellRadii.interpolated(progress: 1, isNotchIntegrated: true)
        let rect = CGRect(x: 0, y: 0, width: 600, height: 300)
        let path = IslandShellShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom).path(in: rect)
        let inset = IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true, showNavigationControls: false)
        for x in [inset, rect.width - inset] {
            XCTAssertTrue(path.contains(CGPoint(x: x, y: rect.height - IslandShellLayout.expandedBottomPadding)))
        }
        XCTAssertGreaterThan(radii.top, 19)
        XCTAssertEqual(radii.bottom, 40)
    }
    func testSecretNotchMenuRetainsSettingsAndClipboardAuthority() throws {
        _ = NSApplication.shared // NSApp.sendAction below; don't depend on another test creating it.
        var openedSettings = 0
        var openedClipboard = 0
        let geometry = IslandBackgroundInteractionGeometry(size: CGSize(width: 600, height: 240),
            horizontalPadding: 40, bottomPadding: 12, contentTop: 38,
            notchSize: CGSize(width: 200, height: 32), allowsBackground: true)
        XCTAssertEqual(geometry.region(at: CGPoint(x: 300, y: 8)), .notch)
        let view = IslandShellBackgroundInputView(frame: CGRect(origin: .zero, size: geometry.size))
        view.configure(IslandShellBackgroundInteraction(geometry: geometry, enabled: true,
            presentationGeneration: 1, clipboardEnabled: true, onEdit: {},
            onClipboard: { openedClipboard += 1 }, onSettings: { openedSettings += 1 }, onNavigate: { _ in }))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: 300, y: 8),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(view.menu(for: event))
        for tag in [3, 4] {
            let item = try XCTUnwrap(menu.item(withTag: tag))
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        }
        XCTAssertEqual(openedSettings, 1)
        XCTAssertEqual(openedClipboard, 1)
        view.configure(IslandShellBackgroundInteraction(geometry: geometry, enabled: false,
            presentationGeneration: 2, clipboardEnabled: true, onEdit: {}, onClipboard: {}, onSettings: {}, onNavigate: { _ in }))
        XCTAssertNil(view.menu(for: event), "morphing/protected input cannot open the menu")
    }

    func testNativeProductionSurfaceAndFooterRenderSnapshot() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.agentActivityEnabled = true
        settings.showAgentsTab = true
        let navigation = IslandNavigationStore()
        let media = MediaController.settingsPreview()
        let content = VStack(spacing: DetachedIslandNavigationMetrics.gap) {
            IslandSurface(settings: settings, isExpanded: true, visualProgress: 1) {
                MediaModuleView(settings: settings, media: media, availableHeight: 190,
                    onLauncherActivated: {}, onMediaSourceOpened: {})
                    .padding(.top, 38)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 12)
            }
            .notchIntegrated(true)
            .frame(width: 600, height: 240)
            DetachedIslandNavigationBar(settings: settings, navigation: navigation,
                onEdit: {}, onEditTabs: {}, onReset: {})
                .fixedSize()
        }
        .padding(12)
        .background(Color.gray.opacity(0.25))
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 320)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        CameraNativeHostedFixture.pump()
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/dynamicisland-detached-nav-native.png"))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertTrue(media.isSettingsPreview, "snapshot never starts providers or commands")
    }

}
