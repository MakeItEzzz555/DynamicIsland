import XCTest
@testable import DynamicIsland

@MainActor
final class ZeroChromeWorkspaceGeometryTests: XCTestCase {
    private let metrics = IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaInsets: .init(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRightArea: CGRect(x: 849, y: 950, width: 663, height: 32),
        backingScaleFactor: 2, displayID: nil, isBuiltIn: true,
        pixelSize: CGSize(width: 3024, height: 1964)))

    private func configuration(_ widgets: [(IslandWidget, WidgetPresentationSize)]) -> WorkspaceConfiguration {
        // Removing the last widget recovers Now Playing. Construct the
        // requested complete layout so Timer/Calendar fixtures are truly sole.
        WorkspaceConfiguration(placements: widgets.enumerated().map {
            WidgetPlacement(kind: $0.element.0, surface: .media, order: $0.offset, size: $0.element.1)
        }, customizedSurfaces: [.media]).normalized()
    }

    private func region(_ kind: IslandWidget, _ size: WidgetPresentationSize, order: Int) -> WorkspaceWidgetRegion {
        let widget = WidgetPlacement(kind: kind, surface: .agents, order: order, size: size)
        return WorkspaceWidgetRegion(id: widget.id, widgets: [widget])
    }

    private var zeroChromeLane: WorkspaceNotchLane {
        ExpandedIslandLayoutMetrics.workspaceNotchLane(metrics: metrics, isNotchIntegrated: true,
            pageCount: 4, clipboardEnabled: false, hardwareNotchWidth: metrics.hardwareNotchWidth,
            showNavigationControls: false)
    }

    func testZeroChromePackingRemovesOnlyExternalSpaceForMediaTimerAndCalendar() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "ZeroChromePacking-\(UUID().uuidString)")!)
        settings.respectHardwareNotch = true
        settings.showNavigationControls = false
        for kind in [IslandWidget.media, .timer, .calendar] {
            for presentation in [WidgetPresentationSize.standard, .compact] {
                let config = configuration([(kind, presentation)])
                let header = ExpandedPresentationProfile.headerLayout(page: .island, configuration: config,
                    editing: false, settings: settings, metrics: metrics, pageCount: 4)
                let size = ExpandedPresentationProfile.resolve(for: .island).resolvedSize(from: CGSize(width: 900, height: 360),
                    page: .island, configuration: config, editing: false, settings: settings, metrics: metrics, header: header)
                let chrome = ExpandedIslandLayoutMetrics(containerSize: size,
                    horizontalPadding: IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true, showNavigationControls: false),
                    displayMetrics: metrics, headerDrop: header.headerDrop, showHeader: false)
                let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .media),
                    availableSize: CGSize(width: chrome.innerWidth, height: chrome.pageHeight), metrics: metrics)
                let frame = try XCTUnwrap(projection.frames.first?.frame)
                let expected = WidgetGridMetrics.make(surface: .media, metrics: metrics).size(for: presentation, kinds: [kind])
                XCTAssertEqual(frame.size, expected, "\(kind) \(presentation): semantic size unchanged")
                XCTAssertEqual(chrome.tabSwitcherHeight + chrome.tabToPageSpacing, 0)
                XCTAssertEqual(chrome.topPadding + frame.minY, metrics.hardwareNotchHeight + metrics.spacing(6), accuracy: 0.001)
                XCTAssertEqual(size.height - chrome.topPadding - frame.maxY, metrics.spacing(6), accuracy: 0.001)
                XCTAssertEqual(size.width - frame.width, 50, accuracy: 0.001, "19pt shoulder +6pt visible inset on each side")
                XCTAssertLessThan(size.width, expected.width + 62, "previous hidden side-padding profile")
                XCTAssertLessThan(size.height, expected.height + metrics.hardwareNotchHeight + 22 * metrics.spacingScale,
                                  "previous hidden top/bottom-padding profile")
            }
        }
        let floating = ExpandedHeaderLayout.hidden(metrics: metrics, isNotchIntegrated: false)
        let floatingChrome = ExpandedIslandLayoutMetrics(containerSize: .zero, horizontalPadding: 6,
            displayMetrics: metrics, headerDrop: floating.headerDrop, showHeader: false)
        XCTAssertEqual(floatingChrome.topPadding, metrics.spacing(6), accuracy: 0.001)
        XCTAssertEqual(IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: false, showNavigationControls: false), 6)
    }

    func testCompactWingsUseExistingWidthAndNeverIntersectTheNotchOrOtherWidgets() throws {
        let regions = [region(.timer, .compact, order: 0), region(.feed, .compact, order: 1), region(.chat, .standard, order: 2)]
        let available = CGSize(width: 700, height: 900)
        let plainSize = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions, maximumSize: available,
            metrics: metrics, minimumWidth: 0)
        let packedSize = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions, maximumSize: available,
            metrics: metrics, lane: zeroChromeLane, minimumWidth: 0)
        XCTAssertEqual(packedSize.width, plainSize.width, accuracy: 0.001)
        XCTAssertEqual(plainSize.height - packedSize.height, metrics.hardwareNotchHeight, accuracy: 0.001)
        let plain = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: plainSize, metrics: metrics)
        let packed = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: packedSize,
            metrics: metrics, lane: zeroChromeLane)
        let notch = CGRect(x: packedSize.width / 2 - metrics.hardwareNotchWidth / 2,
            y: -metrics.hardwareNotchHeight - metrics.spacing(6), width: metrics.hardwareNotchWidth,
            height: metrics.hardwareNotchHeight)
        for frame in packed.frames {
            XCTAssertEqual(frame.frame.size, try XCTUnwrap(plain.frames.first { $0.id == frame.id }).frame.size)
            XCTAssertFalse(frame.frame.intersects(notch))
        }
        for (index, a) in packed.frames.enumerated() {
            for b in packed.frames.dropFirst(index + 1) { XCTAssertFalse(a.frame.intersects(b.frame)) }
        }
        let left = try XCTUnwrap(packed.frames.first { $0.id == regions[0].id }).frame
        let right = try XCTUnwrap(packed.frames.first { $0.id == regions[1].id }).frame
        XCTAssertEqual(left.minY, -metrics.hardwareNotchHeight, accuracy: 0.001)
        XCTAssertEqual(left.maxX, notch.minX - metrics.spacing(6), accuracy: 0.001)
        XCTAssertEqual(right.minX, notch.maxX + metrics.spacing(6), accuracy: 0.001)
    }

    func testPhysicalNotchWidthRemainsAuthoritativeDuringTransientGeometry() {
        for width in [CGFloat.zero, 1, .nan] {
            XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(metrics: metrics, isNotchIntegrated: true,
                pageCount: 4, clipboardEnabled: false, hardwareNotchWidth: width, showNavigationControls: false), zeroChromeLane)
        }
        XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(metrics: metrics, isNotchIntegrated: false,
            pageCount: 4, clipboardEnabled: false, hardwareNotchWidth: 186, showNavigationControls: false), .none)
        XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(metrics: .fallback, isNotchIntegrated: true,
            pageCount: 4, clipboardEnabled: false, hardwareNotchWidth: 186, showNavigationControls: false), .none)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "ZeroChromeLane-\(UUID().uuidString)")!)
        settings.respectHardwareNotch = true
        settings.showNavigationControls = false
        XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(settings: settings, metrics: metrics,
            pageCount: 4, hardwareNotchWidth: metrics.hardwareNotchWidth), zeroChromeLane,
            "the committed runtime settings and direct preview resolve the same physical lane")
        settings.respectHardwareNotch = false
        XCTAssertEqual(ExpandedIslandLayoutMetrics.workspaceNotchLane(settings: settings, metrics: metrics,
            pageCount: 4, hardwareNotchWidth: metrics.hardwareNotchWidth), .none)
    }

    func testHiddenUsageBandHasNoRecoveryHeightFloor() throws {
        let regions = [region(.agentUsage, .compact, order: 0)]
        let size = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions,
            maximumSize: CGSize(width: 700, height: 900), metrics: metrics, lane: zeroChromeLane, minimumWidth: 0)
        let semantic = WidgetGridMetrics.bandSize(.agentUsage, .compact, metrics: metrics)
        XCTAssertEqual(size, semantic)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: size,
            metrics: metrics, lane: zeroChromeLane)
        XCTAssertEqual(try XCTUnwrap(projection.frames.first?.frame).size, semantic)
        XCTAssertFalse(projection.requiresScrolling)
        let empty = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: [], maximumSize: CGSize(width: 700, height: 900),
            metrics: metrics, lane: zeroChromeLane, minimumWidth: 0)
        XCTAssertGreaterThan(empty.height, size.height, "an empty workspace still has a usable recovery surface")
        let floatingSize = WorkspaceWidgetLayoutProjection.preferredContentSize(regions: regions,
            maximumSize: CGSize(width: 700, height: 900), metrics: metrics, minimumWidth: 0)
        XCTAssertEqual(floatingSize, semantic, "a hidden floating shell has no recovery-height floor either")
    }

    func testAudioDeviceHUDHasReadableWingsWithoutASliderBand() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "AudioDeviceGeometry-\(UUID().uuidString)")!)
        let audio = DynamicIslandLiveActivity(id: "audio-device-geometry", kind: .system,
            title: "AirPods Pro", subtitle: "Connected", symbolName: "airpodspro",
            priority: 950, isActive: true, progress: nil, updatedAt: .now, systemHUDKind: .audioDevice)
        let geometry = SystemHUDShellPreview.geometry(settings: settings, activity: audio)
        XCTAssertEqual(geometry.collapsedPresentationProfile, .audioDeviceHUD)
        XCTAssertEqual(geometry.collapsedPresentationProfile.heightDelta, 0)
        XCTAssertGreaterThanOrEqual(geometry.collapsedLeftRegionWidth, 24)
        XCTAssertGreaterThanOrEqual(geometry.collapsedRightRegionWidth, 96)
        XCTAssertEqual(geometry.collapsedFrame.maxY, SystemHUDShellPreview.referenceScreen.frame.maxY)
        XCTAssertEqual(geometry.collapsedFrame.midX, try XCTUnwrap(geometry.notchRect).midX, accuracy: 0.001)
    }

    func testWingPreviewAndRuntimeSharePositionsAfterEditorInset() throws {
        let regions = [region(.feed, .compact, order: 0), region(.chat, .standard, order: 1)]
        let available = CGSize(width: 700, height: 900)
        let runtime = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: available,
            metrics: metrics, lane: zeroChromeLane)
        let editor = WorkspaceWidgetLayoutProjection.make(regions: regions, availableSize: available,
            metrics: metrics, editing: true, lane: zeroChromeLane)
        for frame in runtime.frames {
            let preview = try XCTUnwrap(editor.frames.first { $0.id == frame.id }).frame
            XCTAssertEqual(preview.minX, frame.frame.minX, accuracy: 0.001)
            XCTAssertEqual(preview.minY - 7, frame.frame.minY, accuracy: 0.001)
            XCTAssertEqual(preview.size, frame.frame.size)
        }
    }

    func testWingsNeverWidenASoleWidgetOrBreakAStackOrRiseWhileScrolling() throws {
        let media = configuration([(.media, .compact)]).regions(on: .media)
        let size = CGSize(width: 700, height: 900)
        XCTAssertEqual(WorkspaceWidgetLayoutProjection.make(regions: media, availableSize: size, metrics: metrics, lane: zeroChromeLane),
                       WorkspaceWidgetLayoutProjection.make(regions: media, availableSize: size, metrics: metrics))
        var stacked = [region(.feed, .compact, order: 0), region(.chat, .standard, order: 1)]
        stacked[1].widgets[0].stacksBelowPrevious = true
        XCTAssertEqual(WorkspaceWidgetLayoutProjection.make(regions: stacked, availableSize: size, metrics: metrics, lane: zeroChromeLane),
                       WorkspaceWidgetLayoutProjection.make(regions: stacked, availableSize: size, metrics: metrics))
        let scrolling = [region(.feed, .compact, order: 0), region(.chat, .standard, order: 1)]
        let clipped = WorkspaceWidgetLayoutProjection.make(regions: scrolling,
            availableSize: CGSize(width: 700, height: 150), metrics: metrics, lane: zeroChromeLane)
        XCTAssertTrue(clipped.requiresScrolling)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(clipped.frames.map(\.frame.minY).min()), 0)
    }

    func testWingProjectionCost() {
        let regions = [region(.timer, .compact, order: 0), region(.feed, .compact, order: 1), region(.chat, .standard, order: 2)]
        let start = ProcessInfo.processInfo.systemUptime
        var frameCount = 0
        for _ in 0..<300 {
            frameCount += WorkspaceWidgetLayoutProjection.make(regions: regions,
                availableSize: CGSize(width: 700, height: 900), metrics: metrics, lane: zeroChromeLane).frames.count
        }
        let average = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 300
        XCTAssertEqual(frameCount, regions.count * 300)
        XCTAssertTrue(average.isFinite && average > 0)
        print(String(format: "ZERO_CHROME_PROJECTION average=%.4f ms (300 pure projections; not display frame pacing)", average))
    }

    func testReportMeasuredShells() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "ZeroChromeMeasurements-\(UUID().uuidString)")!)
        settings.respectHardwareNotch = true
        for shown in [true, false] {
            settings.showNavigationControls = shown
            for kind in [IslandWidget.media, .timer, .calendar] {
                for presentation in [WidgetPresentationSize.standard, .compact] {
                    let config = configuration([(kind, presentation)])
                    let header = ExpandedPresentationProfile.headerLayout(page: .island, configuration: config,
                        editing: false, settings: settings, metrics: metrics, pageCount: 4)
                    let size = ExpandedPresentationProfile.resolve(for: .island).resolvedSize(from: CGSize(width: 900, height: 360),
                        page: .island, configuration: config, editing: false, settings: settings, metrics: metrics,
                        minimumHeaderWidth: ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: 4,
                            clipboardEnabled: settings.clipboardHistoryEnabled, hardwareNotchWidth: 186), header: header)
                    let chrome = ExpandedIslandLayoutMetrics(containerSize: size,
                        horizontalPadding: IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true, showNavigationControls: shown),
                        displayMetrics: metrics, headerDrop: header.headerDrop, showHeader: shown)
                    let projection = WorkspaceWidgetLayoutProjection.make(regions: config.regions(on: .media),
                        availableSize: CGSize(width: chrome.innerWidth, height: chrome.pageHeight), metrics: metrics)
                    let frame = try XCTUnwrap(projection.frames.first?.frame)
                    let top = chrome.topPadding + chrome.tabSwitcherHeight + chrome.tabToPageSpacing
                    print("ZERO_CHROME_MEASURE shown=\(shown) widget=\(kind) size=\(presentation) shell=\(size) content=\(projection.contentSize) frame=\(frame) top=\(top) side=\(chrome.horizontalPadding) bottom=\(chrome.bottomPadding)")
                    if !shown {
                        // Reconstruct the unchanged sole-widget projection's
                        // 6ed5bde hidden chrome:31 sides,notch+10 top,12 bottom.
                        // These are resolver measurements, not physical pixels.
                        let previous = CGSize(width: frame.width + 62,
                            height: frame.height + metrics.hardwareNotchHeight + metrics.spacing(22))
                        print("ZERO_CHROME_BASELINE sha=6ed5bde widget=\(kind) size=\(presentation) shell=\(previous) widget=\(frame.size)")
                    }
                }
            }
        }
    }
}
