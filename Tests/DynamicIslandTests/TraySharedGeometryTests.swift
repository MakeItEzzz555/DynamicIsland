import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class TraySharedGeometryTests: XCTestCase {
    func testTrayUsesTheMediaSemanticFootprintAtEverySizeAndDisplayScale() {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        for scale: CGFloat in [1, 2] {
            let metrics = IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
                safeAreaInsets: .init(top: 32, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
                auxiliaryTopRightArea: CGRect(x: 849, y: 950, width: 663, height: 32),
                backingScaleFactor: scale, displayID: nil, isBuiltIn: true, pixelSize: CGSize(width: 1512 * scale, height: 982 * scale)))
            for size in WidgetPresentationSize.supported(for: .media) {
                let configuration = WorkspaceConfiguration(placements: [WidgetPlacement(kind: .media, surface: .media, order: 0, size: size)],
                    customizedSurfaces: [.media]).normalized()
                func footprint(_ page: ExpandedIslandPage) -> CGSize {
                    let header = ExpandedPresentationProfile.headerLayout(page: page, configuration: configuration, editing: false,
                        settings: settings, metrics: metrics, pageCount: 4)
                    return ExpandedPresentationProfile.resolve(for: page).resolvedSize(from: settings.expandedSize, page: page,
                        configuration: configuration, editing: false, settings: settings, metrics: metrics, header: header)
                }
                XCTAssertEqual(footprint(.tray), footprint(.island))
                XCTAssertEqual(ExpandedPresentationProfile.resolve(for: .tray).accessoryHeight, 0)
                XCTAssertEqual(configuration.placements.first?.size, size, "shared shell does not rewrite saved widget size")
            }
        }
    }

    func testProductionTrayMountsOnlyNavigationAndClearsRetiredPointerFrames() throws {
        _ = NSApplication.shared
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.reduceExtraMotion = true; settings.animationPreset = .instant
        let modules = NativeIslandFixtureModules.make(settings: settings)
        modules.navigation.select(.tray)
        let layout = IslandLayoutStore()
        layout.hasHardwareNotch = false; layout.canvasSize = CGSize(width: 600, height: 400)
        layout.expandedSurfaceFrame = CGRect(x: 80, y: 100, width: 440, height: 250)
        layout.setExpandedAccessoryFrames([CGRect(x: 80, y: 50, width: 100, height: 30)], owner: .trayQuickActions)
        layout.setExpandedAccessoryFrames([CGRect(x: 80, y: 15, width: 100, height: 30)], owner: .fileDragOrbit)
        let state = IslandStateStore(); state.expand()
        let root = IslandRootView(settings: settings, islandState: state, layoutStore: layout, escapeRouter: IslandEscapeRouter(),
            modules: modules, rendersExpandedVisualContent: true, onRequestExpand: {}, onRequestCollapse: {}, onOpenSettings: {})
            .environment(\.isSettingsPreview, true)
        let window = NSPanel(contentRect: CGRect(x: 100, y: 80, width: 600, height: 400), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root); window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        for _ in 0..<5 { CameraNativeHostedFixture.pump() }
        let nav = DetachedIslandNavigationMetrics.frame(shell: layout.expandedSurfaceFrame,
            pageCount: modules.navigation.availablePages(using: settings).count)
        XCTAssertEqual(layout.expandedAccessoryFrames, [nav.integral])
        XCTAssertEqual(layout.expandedSurfaceFrame.minY - nav.maxY, 3)
        XCTAssertNotEqual(ExpandedHoverContainment.decide(pointer: CGPoint(x: nav.midX, y: nav.maxY + 1.5),
            shellFrame: layout.expandedSurfaceFrame, accessoryFrames: layout.expandedAccessoryFrames, holds: []), .collapse)
    }
}
