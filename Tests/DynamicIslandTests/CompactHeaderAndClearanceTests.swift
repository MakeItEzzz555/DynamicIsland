import XCTest
@testable import DynamicIsland

/// Final compact shell (2026-10-06): a single widget can move the header into
/// one row below the notch; bottom clearance is one token; widget geometry
/// never depends on the header mode or on siblings.
@MainActor
final class CompactHeaderAndClearanceTests: XCTestCase {
    private let notched = IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaInsets: .init(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRightArea: CGRect(x: 849, y: 950, width: 663, height: 32),
        backingScaleFactor: 2, displayID: nil, isBuiltIn: true,
        pixelSize: CGSize(width: 3024, height: 1964)))
    private let pageCount = 4
    private let notchWidth: CGFloat = 186

    private func settings() -> AppSettings {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "CompactHeaderTests-\(UUID().uuidString)")!)
        settings.agentActivityEnabled = true
        settings.respectHardwareNotch = true
        return settings
    }

    private func config(_ surface: WorkspaceSurface, _ widgets: [(IslandWidget, WidgetPresentationSize)]) -> WorkspaceConfiguration {
        var config = WorkspaceConfiguration.initial
        for widget in config.widgets(on: surface) { config.remove(widget.id) }
        for (kind, size) in widgets {
            config.add(kind, on: surface)
            if let id = config.widgets(on: surface).last(where: { $0.kind == kind })?.id { config.setSize(size, for: id) }
        }
        config.markCustomized(surface)
        return config
    }

    private func page(_ surface: WorkspaceSurface) -> ExpandedIslandPage { surface == .media ? .island : .agents }

    private func header(_ config: WorkspaceConfiguration, _ surface: WorkspaceSurface, editing: Bool = false,
                        settings: AppSettings) -> ExpandedHeaderLayout {
        ExpandedPresentationProfile.headerLayout(page: page(surface), configuration: config, editing: editing,
                                                 settings: settings, metrics: notched, pageCount: pageCount)
    }

    private func shell(_ config: WorkspaceConfiguration, _ surface: WorkspaceSurface, header: ExpandedHeaderLayout,
                       settings: AppSettings) -> CGSize {
        ExpandedPresentationProfile.resolve(for: page(surface)).resolvedSize(from: CGSize(width: 900, height: 360),
            page: page(surface), configuration: config, editing: false, settings: settings, metrics: notched,
            minimumHeaderWidth: ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: pageCount,
                clipboardEnabled: settings.clipboardHistoryEnabled, hardwareNotchWidth: notchWidth),
            header: header)
    }

    /// The widget frames the editor lays out inside a shell of `size`.
    private func frames(_ config: WorkspaceConfiguration, _ surface: WorkspaceSurface, shell size: CGSize,
                        header: ExpandedHeaderLayout) -> [WidgetID: CGRect] {
        let padding = IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true)
        let chrome = ExpandedIslandLayoutMetrics(containerSize: size, horizontalPadding: padding, displayMetrics: notched,
                                                 headerDrop: header.mode == .compactBelowNotch ? header.headerDrop : 0)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: surface),
            availableSize: CGSize(width: chrome.innerWidth, height: chrome.pageHeight), metrics: notched)
        return Dictionary(uniqueKeysWithValues: projection.frames.map { ($0.id, $0.frame) })
    }

    // MARK: Header mode

    func testSingleStandardWidgetUsesTheCompactRowAndTheShellNarrows() throws {
        let settings = settings()
        for (surface, kind, size) in [(WorkspaceSurface.media, IslandWidget.media, WidgetPresentationSize.standard),
                                      (.media, .media, .large)] {
            let config = config(surface, [(kind, size)])
            let compact = header(config, surface, settings: settings)
            XCTAssertEqual(compact.mode, .compactBelowNotch, "\(kind)")
            let narrow = shell(config, surface, header: compact, settings: settings)
            let wide = shell(config, surface, header: .winged, settings: settings)
            XCTAssertLessThan(narrow.width, wide.width - 0.5, "\(kind): no notch-wide side wings")
            let id = try XCTUnwrap(config.regions(on: surface).first?.id)
            let a = try XCTUnwrap(frames(config, surface, shell: narrow, header: compact)[id])
            let b = try XCTUnwrap(frames(config, surface, shell: wide, header: .winged)[id])
            XCTAssertEqual(a.width, b.width, accuracy: 0.01, "\(kind): the widget never resizes with the header mode")
            XCTAssertEqual(a.height, b.height, accuracy: 0.01)
            XCTAssertLessThanOrEqual(compact.compactRowWidth, a.width + 0.5, "the row fits the widget below it")
        }
    }

    func testCompactRowStartsBelowTheNotchWithFullSizeButtons() {
        let settings = settings()
        let compact = header(config(.media, [(.media, .large)]), .media, settings: settings)
        XCTAssertEqual(compact.mode, .compactBelowNotch)
        let chrome = ExpandedIslandLayoutMetrics(containerSize: .zero, horizontalPadding: 0, displayMetrics: notched,
                                                 headerDrop: compact.headerDrop)
        XCTAssertGreaterThanOrEqual(chrome.topPadding, notched.hardwareNotchHeight + ExpandedIslandLayoutMetrics.notchContentClearance(metrics: notched) - 0.01,
                                    "the row can never intersect the notch")
        XCTAssertEqual(compact.compactRowWidth,
                       ExpandedIslandHeaderMetrics.leadingGroupWidth(pageCount: pageCount) + ExpandedHeaderLayout.compactGroupSpacing
                       + ExpandedIslandHeaderMetrics.trailingGroupWidth(clipboardEnabled: settings.clipboardHistoryEnabled),
                       accuracy: 0.01, "buttons keep their 30 pt hit size")
        XCTAssertEqual(ExpandedIslandHeaderMetrics.buttonWidth, 30)
    }

    func testFallbacksKeepTheWingedHeader() {
        let settings = settings()
        // Chat is mandatory on Agents; a lone Standard Chat (shown as Chat or,
        // switched in place, Terminal) is already wider than the winged
        // header, so compact would only add height.
        let chat = config(.agents, [])
        XCTAssertEqual(chat.regions(on: .agents).count, 1)
        XCTAssertEqual(header(chat, .agents, settings: settings).mode, .winged, "no width gain")
        XCTAssertEqual(header(config(.media, [(.media, .standard), (.timer, .compact)]), .media, settings: settings).mode, .winged,
                       "two widgets")
        XCTAssertEqual(header(config(.media, [(.media, .compact)]), .media, settings: settings).mode, .winged,
                       "a Compact widget is narrower than the full row: never shrink buttons")
        XCTAssertEqual(header(config(.media, [(.media, .standard)]), .media, editing: true, settings: settings).mode, .winged,
                       "editing keeps pointer geometry stable")
        settings.respectHardwareNotch = false
        XCTAssertEqual(header(config(.media, [(.media, .standard)]), .media, settings: settings).mode, .winged, "no notch shell")
        XCTAssertEqual(ExpandedHeaderLayout.resolve(regionCount: 1, singleRegionWidth: 900, contentHeight: 10_000, editing: false,
            metrics: notched, isNotchIntegrated: true, pageCount: pageCount, clipboardEnabled: true).mode, .winged,
            "no vertical room")
    }

    // MARK: Bottom clearance

    func testShellBottomSitsOneClearanceBelowTheLowestWidget() throws {
        let settings = settings()
        let clearance = ExpandedIslandLayoutMetrics.contentBottomClearance(metrics: notched)
        XCTAssertEqual(clearance, 12 * notched.spacingScale, accuracy: 0.001)
        for (surface, widgets) in [(WorkspaceSurface.media, [(IslandWidget.media, WidgetPresentationSize.standard)]),
                                   (.media, [(.media, .large), (.timer, .compact)]),
                                   (.agents, [(.chat, .standard), (.feed, .compact)]),
                                   (.agents, [(.terminal, .large)])] {
            let config = config(surface, widgets)
            let mode = header(config, surface, settings: settings)
            let size = shell(config, surface, header: mode, settings: settings)
            let chrome = ExpandedIslandLayoutMetrics(containerSize: size,
                horizontalPadding: IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true), displayMetrics: notched,
                headerDrop: mode.mode == .compactBelowNotch ? mode.headerDrop : 0)
            let lowest = try XCTUnwrap(frames(config, surface, shell: size, header: mode).values.map(\.maxY).max())
            let pageTop = chrome.topPadding + chrome.tabSwitcherHeight + chrome.tabToPageSpacing
            XCTAssertEqual(size.height - (pageTop + lowest), clearance, accuracy: 0.5, "\(widgets)")
        }
    }

    // MARK: Semantic size invariance across siblings and header modes

    func testWidgetSizeIsIndependentOfSiblingsAndHeaderMode() throws {
        let settings = settings()
        let cases: [(WorkspaceSurface, IslandWidget, [[(IslandWidget, WidgetPresentationSize)]])] = [
            (.media, .media, [[], [(.timer, .compact)], [(.timer, .standard)], [(.timer, .compact), (.files, .compact), (.clipboard, .standard)]]),
            (.agents, .chat, [[], [(.feed, .compact)], [(.timer, .standard)], [(.feed, .compact), (.timer, .compact), (.agentUsage, .standard)]]),
            (.agents, .terminal, [[], [(.feed, .compact)], [(.timer, .standard)]]),
        ]
        for (surface, kind, siblingSets) in cases {
            for size in WidgetPresentationSize.allCases {
                var sizes: [CGSize] = []
                for siblings in siblingSets {
                    let config = config(surface, [(kind, size)] + siblings)
                    let mode = header(config, surface, settings: settings)
                    let shellSize = shell(config, surface, header: mode, settings: settings)
                    let id = try XCTUnwrap(config.widgets(on: surface).first { $0.kind == kind }?.id)
                    let region = try XCTUnwrap(config.regions(on: surface).first { $0.widgets.contains { $0.id == id } }?.id)
                    sizes.append(try XCTUnwrap(frames(config, surface, shell: shellSize, header: mode)[region]).size)
                    sizes.append(try XCTUnwrap(frames(config, surface, shell: shell(config, surface, header: .winged, settings: settings),
                                                      header: .winged)[region]).size)
                }
                for other in sizes {
                    XCTAssertEqual(other.width, sizes[0].width, accuracy: 0.01, "\(kind) \(size)")
                    XCTAssertEqual(other.height, sizes[0].height, accuracy: 0.01, "\(kind) \(size)")
                }
            }
        }
    }
}
