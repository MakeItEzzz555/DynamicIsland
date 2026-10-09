import XCTest
@testable import DynamicIsland

@MainActor
final class SettingsNavigationStructureTests: XCTestCase {
    func testSixCategoriesKeepEveryExistingSettingsPaneReachableExactlyOnce() {
        XCTAssertEqual(SettingsCategory.allCases.map(\.rawValue),
            ["General", "Island", "Media & Devices", "Productivity", "Agents", "System"])
        let sections = SettingsCategory.allCases.flatMap(\.sections)
        XCTAssertEqual(Set(sections), Set(SettingsSection.allCases))
        XCTAssertEqual(sections.count, SettingsSection.allCases.count)
        for section in SettingsSection.allCases {
            XCTAssertTrue(SettingsCategory.containing(section).sections.contains(section))
            XCTAssertFalse(SettingsCategory.tabTitle(section).isEmpty)
        }
        XCTAssertEqual(AgentSettingsTab.allCases.map(\.rawValue), ["Workspace", "Providers", "Usage", "Diagnostics"])
        XCTAssertEqual(MediaDeviceSettingsTab.allCases.map(\.rawValue), ["Media", "Audio", "HUD"])
    }

    func testChangingNavigationStylePreservesOtherStoredPreferencesAndGestureMappings() {
        let defaults = SettingsPreviewDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.timerPreset1Minutes = 37
        settings.shellOpacity = 0.73
        settings.collapsedDoubleClickAction = .openSettings
        settings.expandedDoubleClickAction = .editWorkspace
        settings.collapsedLongPressAction = .openClipboard
        settings.expandedLongPressAction = .openSettings
        settings.threeFingerTabNavigationEnabled = false
        settings.showNavigationControls = false
        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.showNavigationControls)
        XCTAssertFalse(restored.threeFingerTabNavigationEnabled)
        XCTAssertFalse(restored.gesturesEnabled, "two-finger paging does not rewrite legacy input preferences")
        XCTAssertEqual(restored.timerPreset1Minutes, 37)
        XCTAssertEqual(restored.shellOpacity, 0.73)
        XCTAssertEqual(restored.collapsedDoubleClickAction, .openSettings)
        XCTAssertEqual(restored.expandedDoubleClickAction, .editWorkspace)
        XCTAssertEqual(restored.collapsedLongPressAction, .openClipboard)
        XCTAssertEqual(restored.expandedLongPressAction, .openSettings)
    }

    func testLiveNavigationPreviewRemovesHeaderAndPreservesProductionWidgetFrames() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.clipboardHistoryEnabled = true
        for size in [WidgetPresentationSize.standard, .compact] {
            var configuration = WorkspaceConfiguration.initial
            for widget in configuration.widgets(on: .media) { configuration.remove(widget.id) }
            configuration.add(.media, on: .media)
            let widget = try XCTUnwrap(configuration.widgets(on: .media).first)
            configuration.setSize(size, for: widget.id)
            configuration.markCustomized(.media)
            settings.showNavigationControls = true
            let shown = SettingsPreviewPresentation(settings: settings, configuration: configuration)
            settings.showNavigationControls = false
            let hidden = SettingsPreviewPresentation(settings: settings, configuration: configuration)
            XCTAssertTrue(shown.chrome.showHeader)
            XCTAssertFalse(hidden.chrome.showHeader)
            XCTAssertEqual(hidden.header.mode, .hidden)
            XCTAssertEqual(hidden.header.headerDrop, 0)
            XCTAssertEqual(hidden.header.compactRowWidth, 0)
            XCTAssertEqual(hidden.chrome.tabSwitcherHeight, 0)
            XCTAssertEqual(hidden.chrome.tabToPageSpacing, 0)
            XCTAssertLessThan(hidden.geometry.expandedFrame.height, shown.geometry.expandedFrame.height)
            XCTAssertLessThan(hidden.geometry.expandedFrame.width, shown.geometry.expandedFrame.width)
            XCTAssertEqual(hidden.projection.frames.map(\.frame.size), shown.projection.frames.map(\.frame.size))
            XCTAssertEqual(hidden.navigationFittingSize, shown.navigationFittingSize,
                "the preview camera cannot disguise shell packing by scaling the widget")
            XCTAssertEqual(configuration.widgets(on: .media).first?.size, size)
        }
    }

    func testTwoFingerActionsUseExistingNavigationAndCollapsedExpansionTargetOnce() throws {
        for expanded in [false, true] {
            let settings = AppSettings(defaults: SettingsPreviewDefaults())
            settings.showNavigationControls = false
            settings.threeFingerTabNavigationEnabled = false
            settings.rememberLastSelectedTab = false
            settings.trayEnabled = true
            settings.showTrayTab = true
            settings.timerEnabled = true
            settings.showTimerTab = true
            let navigation = IslandNavigationStore()
            let layout = IslandLayoutStore()
            let pages = navigation.availablePages(using: settings)
            XCTAssertGreaterThanOrEqual(pages.count, 3)
            var gesture = IslandPageScrollGesture()
            var transitions = 0
            for index in 0..<21 {
                let outcome = gesture.update(deltaX: -20, deltaY: 0,
                    phase: index == 0 ? .began : .changed, canBegin: true)
                if outcome == .next {
                    transitions += 1
                    navigation.selectNextPage(using: settings)
                    if !expanded { layout.preservePageForNextExpansion(navigation.selectedPage) }
                }
            }
            XCTAssertEqual(transitions, 1)
            XCTAssertEqual(navigation.selectedPage, pages[1])
            XCTAssertEqual(layout.consumeExpansionPage(), expanded ? nil : pages[1])
            XCTAssertNil(layout.consumeExpansionPage())
            gesture.update(deltaX: 0, deltaY: 0, phase: .ended, canBegin: true)
            XCTAssertEqual(gesture.update(deltaX: -20, deltaY: 0, phase: .began, canBegin: true), .next)
            navigation.selectNextPage(using: settings)
            XCTAssertEqual(navigation.selectedPage, pages[2])
        }
    }
}
