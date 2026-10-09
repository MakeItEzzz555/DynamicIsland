import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class IslandNavigationControlsTests: XCTestCase {
    private let notched = IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaInsets: .init(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRightArea: CGRect(x: 849, y: 950, width: 663, height: 32),
        backingScaleFactor: 2, displayID: nil, isBuiltIn: true,
        pixelSize: CGSize(width: 3024, height: 1964)))

    private func settings() -> AppSettings {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "IslandNavigationControls-\(UUID().uuidString)")!)
        settings.respectHardwareNotch = true
        settings.agentActivityEnabled = true
        return settings
    }

    private func configuration(surface: WorkspaceSurface, widget: IslandWidget, size: WidgetPresentationSize) -> WorkspaceConfiguration {
        var config = WorkspaceConfiguration.initial
        for existing in config.widgets(on: surface) { config.remove(existing.id) }
        config.add(widget, on: surface)
        if let id = config.widgets(on: surface).first(where: { $0.kind == widget })?.id { config.setSize(size, for: id) }
        config.markCustomized(surface)
        return config
    }

    private func geometry(config: WorkspaceConfiguration, page: ExpandedIslandPage, editing: Bool = false,
                          settings: AppSettings) -> (ExpandedHeaderLayout, CGSize, [WidgetID: CGRect]) {
        let surface: WorkspaceSurface = page == .island ? .media : .agents
        let header = ExpandedPresentationProfile.headerLayout(page: page, configuration: config, editing: editing,
            settings: settings, metrics: notched, pageCount: 4)
        let size = ExpandedPresentationProfile.resolve(for: page).resolvedSize(from: CGSize(width: 900, height: 360),
            page: page, configuration: config, editing: editing, settings: settings, metrics: notched,
            minimumHeaderWidth: ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: 4, clipboardEnabled: true,
                hardwareNotchWidth: 186), header: header)
        let chrome = ExpandedIslandLayoutMetrics(containerSize: size,
            horizontalPadding: IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true,
                showNavigationControls: settings.showNavigationControls), displayMetrics: notched,
            headerDrop: header.contentTopInset, showHeader: header.mode != .hidden)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: surface),
            availableSize: CGSize(width: chrome.innerWidth, height: chrome.pageHeight), metrics: notched, editing: editing)
        return (header, size, Dictionary(uniqueKeysWithValues: projection.frames.map { ($0.id, $0.frame) }))
    }

    func testHiddenHeaderHasNoRowOrGapAndKeepsPhysicalNotchClearance() {
        let settings = settings()
        settings.showNavigationControls = false
        for editing in [false, true] {
            for page in ExpandedIslandPage.allCases {
                let header = ExpandedPresentationProfile.headerLayout(page: page, configuration: .initial, editing: editing,
                    settings: settings, metrics: notched, pageCount: 4)
                XCTAssertEqual(header.mode, .hidden)
                XCTAssertEqual(header.compactRowWidth, 0)
                XCTAssertEqual(header.headerDrop, 0)
                XCTAssertEqual(header.physicalNotchInset, notched.hardwareNotchHeight)
                let chrome = ExpandedIslandLayoutMetrics(containerSize: .zero, horizontalPadding: 0,
                    displayMetrics: notched, headerDrop: header.contentTopInset, showHeader: false)
                XCTAssertEqual(chrome.tabSwitcherHeight, 0)
                XCTAssertEqual(chrome.tabToPageSpacing, 0)
                XCTAssertEqual(chrome.topPadding, notched.hardwareNotchHeight
                    + ExpandedIslandLayoutMetrics.notchContentClearance(metrics: notched, showNavigationControls: false), accuracy: 0.001)
            }
        }
        let external = ExpandedHeaderLayout.hidden(metrics: .fallback, isNotchIntegrated: false)
        XCTAssertEqual(external.headerDrop, 0)
        let lane = ExpandedIslandLayoutMetrics.workspaceNotchLane(settings: settings, metrics: notched,
            pageCount: 4, hardwareNotchWidth: 186)
        XCTAssertEqual(lane.rise, notched.hardwareNotchHeight)
        XCTAssertEqual(lane.exclusionWidth, notched.hardwareNotchWidth + 2 * notched.spacing(6), accuracy: 0.001)
        XCTAssertEqual(lane.headerGroupWidth, 0)
        XCTAssertEqual(lane.minimumInnerWidth, 0)
    }

    func testHiddenHeaderShrinksShellWithoutChangingSemanticWidgetSize() throws {
        let settings = settings()
        for (surface, page, kind) in [(WorkspaceSurface.media, ExpandedIslandPage.island, IslandWidget.media),
                                      (.agents, .agents, .chat), (.agents, .agents, .terminal)] {
            for semanticSize in WidgetPresentationSize.allCases {
                let config = configuration(surface: surface, widget: kind, size: semanticSize)
                settings.showNavigationControls = true
                let shown = geometry(config: config, page: page, settings: settings)
                settings.showNavigationControls = false
                let hidden = geometry(config: config, page: page, settings: settings)
                XCTAssertLessThanOrEqual(hidden.1.width, shown.1.width + 0.01)
                let id = try XCTUnwrap(config.regions(on: surface).first(where: { $0.widgets.contains { $0.kind == kind } })?.id)
                let before = try XCTUnwrap(shown.2[id])
                let after = try XCTUnwrap(hidden.2[id])
                XCTAssertEqual(before.width, after.width, accuracy: 0.01, "\(kind) \(semanticSize)")
                XCTAssertEqual(before.height, after.height, accuracy: 0.01, "\(kind) \(semanticSize)")
                if kind == .media && semanticSize == .compact {
                    XCTAssertLessThan(hidden.1.width, shown.1.width - 1, "no header minimum remains")
                    let editing = geometry(config: config, page: page, editing: true, settings: settings)
                    XCTAssertEqual(editing.0.mode, .hidden)
                    XCTAssertGreaterThan(editing.1.width, hidden.1.width, "editor palette retains its own recovery footprint")
                    XCTAssertEqual(try XCTUnwrap(editing.2[id]).size, after.size)
                }
            }
        }
    }

    func testHiddenUncustomizedPagesUseSavedProjectionAndEditorAddsOnlyItsPalette() {
        let settings = settings()
        settings.showNavigationControls = false
        for page in [ExpandedIslandPage.island, .agents] {
            let config = WorkspaceConfiguration.initial
            let normal = geometry(config: config, page: page, settings: settings)
            let editing = geometry(config: config, page: page, editing: true, settings: settings)
            XCTAssertEqual(normal.0.mode, .hidden)
            XCTAssertEqual(editing.0.mode, .hidden)
            XCTAssertEqual(editing.1.height - normal.1.height,
                7 + WorkspaceEditorChrome.paletteHeight + notched.spacing(8), accuracy: 0.01)
            XCTAssertEqual(normal.2.mapValues(\.size), editing.2.mapValues(\.size))
        }
    }

    func testCompactCellKeepsItsDisplayUnitInsideTinyAndWideHosts() throws {
        let config = configuration(surface: .media, widget: .media, size: .compact)
        let unit = WidgetGridMetrics.make(surface: .media, metrics: notched).side
        for width in [unit * 0.4, unit, unit * 2, unit * 4] {
            let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .media),
                availableSize: CGSize(width: width, height: unit * 2), metrics: notched)
            let frame = try XCTUnwrap(projection.frames.first?.frame)
            XCTAssertEqual(frame.width, unit, accuracy: 0.001)
            XCTAssertEqual(frame.height, unit, accuracy: 0.001)
            XCTAssertTrue(frame.origin.x.isFinite)
            XCTAssertTrue(frame.origin.y.isFinite)
            if width < unit { XCTAssertGreaterThan(frame.maxX, width, "a transient tiny host clips instead of rescaling") }
        }
    }

    func testRequestDeliveryRejectsStaleGenerationsAndCancelsOnPresentationEnd() throws {
        let layout = IslandLayoutStore()
        layout.requestWorkspaceAction(.edit)
        let old = try XCTUnwrap(layout.workspaceActionRequest)
        layout.requestWorkspaceAction(.clipboard)
        let newest = try XCTUnwrap(layout.workspaceActionRequest)
        XCTAssertNil(layout.consumeWorkspaceAction(generation: old.generation))
        XCTAssertEqual(layout.consumeWorkspaceAction(generation: newest.generation), .clipboard)
        XCTAssertNil(layout.consumeWorkspaceAction(generation: newest.generation))
        layout.preservePageForNextExpansion(.agents)
        layout.requestWorkspaceAction(.edit)
        let cancelled = try XCTUnwrap(layout.workspaceActionRequest)
        layout.cancelWorkspaceActionRequests()
        XCTAssertNil(layout.consumeWorkspaceAction(generation: cancelled.generation))
        XCTAssertNil(layout.consumeExpansionPage())
        layout.requestWorkspaceAction(.edit)
        XCTAssertGreaterThan(try XCTUnwrap(layout.workspaceActionRequest).generation, cancelled.generation)
    }

    func testExplicitExpansionPageIsOneShotAndIndependentOfRememberDefault() {
        let settings = settings()
        settings.rememberLastSelectedTab = false
        let layout = IslandLayoutStore()
        layout.preservePageForNextExpansion(.agents)
        XCTAssertEqual(layout.consumeExpansionPage(), .agents)
        XCTAssertNil(layout.consumeExpansionPage(), "the following ordinary expansion uses its configured default")
    }

    func testApplyAndCancelKeepHiddenNavigationAndEditorCanReopen() throws {
        let settings = settings()
        settings.showNavigationControls = false
        let store = WorkspaceCustomizationStore(defaults: UserDefaults(suiteName: "HiddenEditor-\(UUID().uuidString)")!)
        let saved = store.configuration
        var draft = saved
        draft.add(.timer, on: .media)
        let layout = IslandLayoutStore()
        layout.setWorkspaceLayoutPreview(draft, surface: .media)
        layout.setWorkspaceLayoutPreview(nil, surface: .media)
        XCTAssertEqual(store.configuration, saved, "Cancel preserves the stored configuration")
        XCTAssertNil(layout.workspaceLayoutPreview)
        var editing = true
        var completions = 0
        XCTAssertTrue(WorkspaceEditorApply.apply(draft: &draft, surface: .media, store: store, editing: &editing,
            completion: { completions += 1 }))
        XCTAssertFalse(editing)
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(settings.showNavigationControls)
        layout.requestWorkspaceAction(.edit)
        let reopen = try XCTUnwrap(layout.workspaceActionRequest)
        XCTAssertEqual(layout.consumeWorkspaceAction(generation: reopen.generation), .edit)
    }

    func testNavigationControlPreferencePersistsAndResetRestoresVisibility() {
        let defaults = UserDefaults(suiteName: "NavigationControlPersistence-\(UUID().uuidString)")!
        let initial = AppSettings(defaults: defaults)
        XCTAssertTrue(initial.showNavigationControls)
        initial.showNavigationControls = false
        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.showNavigationControls)
        restored.resetAllSettings()
        XCTAssertTrue(AppSettings(defaults: defaults).showNavigationControls)
    }

    func testThreeFingerPagingDefaultsOnWithoutEnablingLegacyGestureInput() {
        let settings = settings()
        XCTAssertFalse(settings.gesturesEnabled)
        XCTAssertEqual(settings.gestureInputSource, .none)
        XCTAssertTrue(settings.threeFingerTabNavigationEnabled)
        settings.requireGestureConfirmation = true
        XCTAssertTrue(settings.threeFingerTabNavigationEnabled, "legacy confirmation does not disable page navigation")
        XCTAssertFalse(settings.gesturesEnabled)
        XCTAssertEqual(settings.gestureInputSource, .none)
    }

    func testExistingGestureOnlyPreferenceLoadsWithoutEnablingOptionalThreeFingerPaging() {
        let defaults = UserDefaults(suiteName: "NavigationRecovery-\(UUID().uuidString)")!
        defaults.set(false, forKey: "showNavigationControls")
        defaults.set(false, forKey: "threeFingerTabNavigationEnabled")
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.showNavigationControls)
        XCTAssertFalse(settings.threeFingerTabNavigationEnabled)
        XCTAssertFalse(defaults.bool(forKey: "showNavigationControls"))
        XCTAssertFalse(defaults.bool(forKey: "threeFingerTabNavigationEnabled"))
        XCTAssertFalse(AppSettings(defaults: defaults).threeFingerTabNavigationEnabled)
    }

    func testGestureOnlyIsIndependentOfOptionalThreeFingerPaging() {
        let defaults = UserDefaults(suiteName: "NavigationTransitions-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.threeFingerTabNavigationEnabled = false
        XCTAssertTrue(settings.showNavigationControls)
        settings.showNavigationControls = false
        XCTAssertFalse(settings.threeFingerTabNavigationEnabled)
        XCTAssertFalse(settings.showNavigationControls)
        let hidden = AppSettings(defaults: defaults)
        XCTAssertFalse(hidden.threeFingerTabNavigationEnabled)
        XCTAssertFalse(hidden.showNavigationControls)
        settings.threeFingerTabNavigationEnabled = false
        XCTAssertFalse(settings.showNavigationControls)
        XCTAssertFalse(settings.threeFingerTabNavigationEnabled)
        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.showNavigationControls)
        XCTAssertFalse(restored.threeFingerTabNavigationEnabled)
        restored.resetModuleSettings()
        let reset = AppSettings(defaults: defaults)
        XCTAssertTrue(reset.showNavigationControls)
        XCTAssertTrue(reset.threeFingerTabNavigationEnabled)
    }

    func testReloadPreservesGestureOnlyAndOptionalPagingOptOut() {
        let defaults = UserDefaults(suiteName: "NavigationReload-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        defaults.set(false, forKey: "showNavigationControls")
        defaults.set(false, forKey: "threeFingerTabNavigationEnabled")
        settings.resetLayoutSettings() // Existing public path reloads unrelated module preferences.
        XCTAssertFalse(settings.showNavigationControls)
        XCTAssertFalse(settings.threeFingerTabNavigationEnabled)
        XCTAssertFalse(defaults.bool(forKey: "showNavigationControls"))
        XCTAssertFalse(defaults.bool(forKey: "threeFingerTabNavigationEnabled"))
    }
}

@MainActor
final class IslandBackgroundInteractionTests: XCTestCase {
    private var geometry: IslandBackgroundInteractionGeometry {
        IslandBackgroundInteractionGeometry(size: CGSize(width: 600, height: 300), horizontalPadding: 12,
            bottomPadding: 12, contentTop: 48, notchSize: CGSize(width: 186, height: 32), allowsBackground: true)
    }

    func testPhysicalNotchAndPaddingAreTheOnlyHitRegions() {
        XCTAssertEqual(geometry.region(at: CGPoint(x: 300, y: 20)), .notch)
        XCTAssertNil(geometry.region(at: CGPoint(x: 300, y: 33)), "no synthetic band below the notch")
        XCTAssertNil(geometry.region(at: CGPoint(x: 206, y: 20)), "no interaction outside hardware notch width")
        XCTAssertEqual(geometry.region(at: CGPoint(x: 6, y: 100)), .background)
        XCTAssertEqual(geometry.region(at: CGPoint(x: 300, y: 294)), .background)
        for controlPoint in [CGPoint(x: 100, y: 20), CGPoint(x: 20, y: 60), CGPoint(x: 300, y: 100),
                             CGPoint(x: 588 - 1, y: 288 - 1), CGPoint(x: 300, y: 287)] {
            XCTAssertNil(geometry.region(at: controlPoint), "header and every page control stay outside the input region")
        }
        XCTAssertNil(geometry.region(at: CGPoint(x: -1, y: 100)))
        XCTAssertNil(geometry.region(at: CGPoint(x: 300, y: 301)))
    }

    func testNativeRegionsVetoPaddingAndNotchAndCollapsedHasNoBackgroundPress() {
        var configured = geometry
        configured.excludedRects = [CGRect(x: 0, y: 90, width: 30, height: 30), CGRect(x: 290, y: 10, width: 30, height: 30)]
        XCTAssertNil(configured.region(at: CGPoint(x: 6, y: 100)))
        XCTAssertNil(configured.region(at: CGPoint(x: 300, y: 20)))
        let collapsed = IslandBackgroundInteractionGeometry(size: geometry.size, horizontalPadding: 12,
            bottomPadding: 12, contentTop: 48, notchSize: .zero, allowsBackground: false)
        XCTAssertNil(collapsed.region(at: CGPoint(x: 6, y: 100)))
    }

    func testNativeHitFilterNeverTakesContentOrRoundedOffCornersAndDisablesDuringMorph() {
        let input = IslandShellBackgroundInputView(frame: CGRect(origin: .zero, size: geometry.size))
        func config(enabled: Bool) -> IslandShellBackgroundInteraction {
            IslandShellBackgroundInteraction(geometry: geometry, enabled: enabled, presentationGeneration: 1,
                clipboardEnabled: true, onEdit: {}, onClipboard: {}, onSettings: {}, onNavigate: { _ in },
                shellShape: IslandShellShape(topCornerRadius: 19, bottomCornerRadius: 24))
        }
        input.configure(config(enabled: true))
        XCTAssertNil(input.hitTest(CGPoint(x: 300, y: 100)))
        XCTAssertNil(input.hitTest(CGPoint(x: 1, y: 299)))
        XCTAssertTrue(input.hitTest(CGPoint(x: 300, y: 294)) === input)
        input.configure(config(enabled: false))
        XCTAssertNil(input.hitTest(CGPoint(x: 300, y: 294)))
    }

    func testProductionSurfaceKeepsNativeContentAheadOfBackgroundInput() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "BackgroundSurface-\(UUID().uuidString)")!)
        let interaction = IslandShellBackgroundInteraction(geometry: geometry, enabled: true, presentationGeneration: 1,
            clipboardEnabled: true, onEdit: {}, onClipboard: {}, onSettings: {}, onNavigate: { _ in })
        let host = NSHostingView(rootView: IslandSurface(settings: settings, isExpanded: true, visualProgress: 1,
            backgroundInteraction: interaction) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 48).allowsHitTesting(false)
                    NativeContentFixture().frame(height: 240)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }.frame(width: 600, height: 300))
        host.frame = CGRect(origin: .zero, size: geometry.size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let background = try XCTUnwrap(descendants(host).compactMap { $0 as? IslandShellBackgroundInputView }.first)
        let native = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        let controlPoint = native.convert(CGPoint(x: native.bounds.midX, y: native.bounds.midY), to: host)
        let controlHit = host.hitTest(host.convert(controlPoint, to: host.superview))
        XCTAssertTrue(controlHit === native, "native text entry keeps the actual production hit path")
        let paddingPoint = background.convert(CGPoint(x: 300, y: 294), to: host)
        let paddingHit = host.hitTest(host.convert(paddingPoint, to: host.superview))
        XCTAssertTrue(paddingHit === background, "empty shell padding reaches the lower sibling")
    }
}

private struct NativeContentFixture: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: .zero)
        view.isVerticallyResizable = false
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {}
}
