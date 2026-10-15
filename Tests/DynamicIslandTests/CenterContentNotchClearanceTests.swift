import XCTest
@testable import DynamicIsland

@MainActor
final class CenterContentNotchClearanceTests: XCTestCase {
    private var metrics: ResolvedIslandMetrics { SettingsPreviewPresentation.metrics }

    private func lane(integrated: Bool = true, shown: Bool = false) -> WorkspaceNotchLane {
        ExpandedIslandLayoutMetrics.workspaceNotchLane(metrics: metrics, isNotchIntegrated: integrated,
            pageCount: 4, clipboardEnabled: true, hardwareNotchWidth: metrics.hardwareNotchWidth,
            showNavigationControls: shown)
    }

    private func regions(_ kind: IslandWidget, _ size: WidgetPresentationSize) -> [WorkspaceWidgetRegion] {
        let placement = WidgetPlacement(kind: kind, surface: kind == .chat ? .agents : .media, order: 0, size: size)
        return [.init(id: placement.id, widgets: [placement])]
    }

    func testSpareHostHeightNeverAddsCenterLaneClearance() throws {
        // Reproduces the native failure: a +96pt host proposal used to move
        // the widget down 48pt even though the physical notch was unchanged.
        for (kind, size) in [(IslandWidget.media, WidgetPresentationSize.standard), (.media, .compact),
                             (.timer, .standard), (.calendar, .standard), (.chat, .standard)] {
            let content = regions(kind, size)
            let natural = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: content,
                maximumSize: CGSize(width: 900, height: 900), metrics: metrics, lane: lane(), minimumWidth: 0)
            let header = ExpandedHeaderLayout.hidden(metrics: metrics, isNotchIntegrated: true)
            for extra: CGFloat in [0, 32, 96, 160] {
                let chrome = ExpandedIslandLayoutMetrics(containerSize: CGSize(width: natural.width + 50,
                    height: natural.height + metrics.hardwareNotchHeight + metrics.spacing(12) + extra),
                    horizontalPadding: 25, displayMetrics: metrics, headerDrop: header.contentTopInset, showHeader: false)
                let projection = WorkspaceWidgetLayoutProjection.make(regions: content,
                    availableSize: CGSize(width: chrome.innerWidth, height: chrome.pageHeight), metrics: metrics, lane: lane())
                let frame = try XCTUnwrap(projection.frames.first?.frame)
                XCTAssertEqual(frame.minY, 0, accuracy: 0.001, "\(kind), spare height \(extra)")
                XCTAssertEqual(chrome.topPadding + frame.minY, metrics.hardwareNotchHeight + metrics.spacing(6), accuracy: 0.001)
                XCTAssertEqual(chrome.tabSwitcherHeight + chrome.tabToPageSpacing + header.headerDrop, 0)
                XCTAssertEqual(frame.size, natural)
            }
        }
    }

    func testEditorAndRuntimeKeepTheSameTopAndSemanticFrame() throws {
        for kind in [IslandWidget.media, .timer, .calendar, .chat] {
            let content = regions(kind, .standard)
            let available = CGSize(width: 900, height: 900)
            let runtime = WorkspaceWidgetLayoutProjection.make(regions: content, availableSize: available, metrics: metrics, lane: lane())
            let editor = WorkspaceWidgetLayoutProjection.make(regions: content, availableSize: available, metrics: metrics, editing: true, lane: lane())
            XCTAssertEqual(try XCTUnwrap(runtime.frames.first?.frame), try XCTUnwrap(editor.frames.first?.frame))
            let fit = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: content, maximumSize: available,
                metrics: metrics, lane: lane(), minimumWidth: 0)
            let editFit = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: content, maximumSize: available,
                metrics: metrics, editing: true, lane: lane(), minimumWidth: 0)
            XCTAssertEqual(editFit.height - fit.height, 54 + metrics.spacing(8), accuracy: 0.001,
                "only the palette adds height; no second top reservation")
        }
    }

    func testFloatingModeUsesOpticalClearanceWithoutPhysicalExclusion() throws {
        let floatingLane = lane(integrated: false)
        XCTAssertEqual(floatingLane.rise, 0)
        XCTAssertEqual(floatingLane.exclusionWidth, 0)
        XCTAssertTrue(floatingLane.anchorsMainContentToTop)
        let header = ExpandedHeaderLayout.hidden(metrics: metrics, isNotchIntegrated: false)
        let chrome = ExpandedIslandLayoutMetrics(containerSize: CGSize(width: 700, height: 500), horizontalPadding: 6,
            displayMetrics: metrics, headerDrop: header.contentTopInset, showHeader: false)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: regions(.media, .standard),
            availableSize: CGSize(width: chrome.innerWidth, height: chrome.pageHeight), metrics: metrics, lane: floatingLane)
        XCTAssertEqual(chrome.topPadding + (try XCTUnwrap(projection.frames.first?.frame.minY)), metrics.spacing(6), accuracy: 0.001)
    }

    func testVisibleNavigationRetainsItsExistingVerticalCenteringAndEditorInset() throws {
        let content = regions(.media, .standard)
        let visibleLane = lane(shown: true)
        XCTAssertFalse(visibleLane.anchorsMainContentToTop)
        let available = CGSize(width: 350, height: 400)
        let visible = WorkspaceWidgetLayoutProjection.make(regions: content, availableSize: available, metrics: metrics, lane: visibleLane)
        let plain = WorkspaceWidgetLayoutProjection.make(regions: content, availableSize: available, metrics: metrics)
        XCTAssertEqual(visible, plain, "a Standard card cannot rise into the visible header's narrow free lane")
        XCTAssertGreaterThan(try XCTUnwrap(visible.frames.first?.frame.minY), 0)
        let editor = WorkspaceWidgetLayoutProjection.make(regions: content, availableSize: available, metrics: metrics, editing: true, lane: visibleLane)
        XCTAssertEqual(try XCTUnwrap(editor.frames.first?.frame.minY), 7)
    }

    func testPreviewAndCommittedSettingsResolveTheSameAnchor() {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.showNavigationControls = false
        settings.respectHardwareNotch = true
        XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(settings: settings, metrics: metrics,
            pageCount: 4, hardwareNotchWidth: metrics.hardwareNotchWidth), lane())
        settings.respectHardwareNotch = false
        XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(settings: settings, metrics: metrics,
            pageCount: 4, hardwareNotchWidth: metrics.hardwareNotchWidth), lane(integrated: false))
    }

    func testSettingsLivePreviewUsesTheRuntimeAndEditorProjection() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.showNavigationControls = false
        settings.respectHardwareNotch = true
        for kind in [IslandWidget.media, .timer, .calendar] {
            let placement = WidgetPlacement(kind: kind, surface: .media, order: 0, size: .standard)
            let configuration = WorkspaceConfiguration(placements: [placement], customizedSurfaces: [.media]).normalized()
            let preview = SettingsPreviewPresentation(settings: settings, configuration: configuration)
            let available = CGSize(width: preview.chrome.innerWidth, height: preview.chrome.pageHeight + 96)
            let runtime = WorkspaceWidgetLayoutProjection.make(regions: preview.regions, availableSize: available,
                metrics: metrics, lane: preview.lane)
            let editor = WorkspaceWidgetLayoutProjection.make(regions: preview.regions,
                availableSize: CGSize(width: available.width + 14, height: available.height + 54 + metrics.spacing(8)),
                metrics: metrics, editing: true, lane: preview.lane)
            let frame = try XCTUnwrap(preview.projection.frames.first?.frame)
            XCTAssertEqual(frame.minY, 0, accuracy: 0.001)
            XCTAssertEqual(frame, try XCTUnwrap(runtime.frames.first?.frame))
            let editorFrame = try XCTUnwrap(editor.frames.first?.frame)
            XCTAssertEqual(frame.minY, editorFrame.minY, accuracy: 0.001)
            XCTAssertEqual(frame.size, editorFrame.size)
            XCTAssertEqual(preview.chrome.topPadding, metrics.hardwareNotchHeight + metrics.spacing(6), accuracy: 0.001)
        }
    }
}
