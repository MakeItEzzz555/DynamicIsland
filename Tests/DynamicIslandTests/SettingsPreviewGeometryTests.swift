import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class SettingsPreviewGeometryTests: XCTestCase {
    private func configuration(_ widgets: [(IslandWidget, WidgetPresentationSize)]) -> WorkspaceConfiguration {
        var value = WorkspaceConfiguration.initial
        value.placements.removeAll { $0.surface == .media }
        value.groups.removeAll { $0.surface == .media }
        for (kind, size) in widgets {
            value.add(kind, on: .media)
            if let widget = value.widgets(on: .media).first(where: { $0.kind == kind }) {
                value.setSize(size, for: widget.id)
            }
        }
        value.markCustomized(.media)
        return value.normalized()
    }

    func testCollapsedPreviewResolvesPhysicalNotchAndVisibilityWithoutMinimumOverrides() {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.collapsedWidth = 120
        settings.collapsedHeight = 28
        let media = MediaController.settingsPreview()
        let visible = SettingsPreviewPresentation(settings: settings,
            mediaVisible: SettingsPreviewPresentation.mediaVisible(settings: settings, media: media))
        XCTAssertEqual(visible.geometry.collapsedNotchCoreWidth, 242)
        XCTAssertEqual(visible.geometry.collapsedLeftRegionWidth, visible.geometry.collapsedRightRegionWidth)
        XCTAssertEqual(visible.geometry.collapsedFrame.height, settings.collapsedSize.height)

        settings.respectHardwareNotch = false
        let floating = SettingsPreviewPresentation(settings: settings)
        XCTAssertEqual(floating.geometry.collapsedNotchCoreWidth, 0)
        XCTAssertEqual(floating.geometry.collapsedFrame.width, settings.collapsedSize.width)
        XCTAssertEqual(floating.geometry.collapsedFrame.height, 28)

        settings.mediaEnabled = false
        XCTAssertFalse(SettingsPreviewPresentation.mediaVisible(settings: settings, media: media))
        let inactive = SettingsPreviewPresentation(settings: settings, mediaVisible: false)
        XCTAssertEqual(inactive.geometry.collapsedFrame.width, 126,
                       "floating inactive geometry keeps the production resolver's minimum")
    }

    func testCustomizedPreviewUsesPersistedSemanticSizesAndStableWidgetGeometry() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let solo = configuration([(.media, .compact)])
        let withSibling = configuration([(.media, .compact), (.timer, .large)])
        let a = SettingsPreviewPresentation(settings: settings, configuration: solo)
        let b = SettingsPreviewPresentation(settings: settings, configuration: withSibling)
        let mediaID = try XCTUnwrap(solo.widgets(on: .media).first?.id)
        let mediaA = try XCTUnwrap(a.projection.frames.first { $0.id == mediaID })
        let mediaB = try XCTUnwrap(b.projection.frames.first { $0.id == mediaID })
        XCTAssertEqual(mediaA.frame.size, mediaB.frame.size)
        XCTAssertEqual(mediaA.frame.width, mediaA.frame.height, accuracy: 0.001)
        XCTAssertGreaterThan(b.geometry.expandedFrame.height, a.geometry.expandedFrame.height)
        let large = SettingsPreviewPresentation(settings: settings, configuration: configuration([(.media, .large)]))
        XCTAssertGreaterThan(try XCTUnwrap(large.projection.frames.first).frame.height, mediaA.frame.height)
    }

    func testPreviewLayoutPreservesPlacementOrderAndFeatureAvailability() {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.timerEnabled = true
        let configured = configuration([(.timer, .compact), (.media, .standard)])
        let preview = SettingsPreviewPresentation(settings: settings, configuration: configured)
        XCTAssertEqual(preview.regions.compactMap { $0.widgets.first?.kind }, [.timer, .media])
        settings.timerEnabled = false
        let filtered = SettingsPreviewPresentation(settings: settings, configuration: configured)
        XCTAssertEqual(filtered.regions.compactMap { $0.widgets.first?.kind }, [.media])
        XCTAssertEqual(configured.widgets(on: .media).count, 2, "availability never rewrites saved placements")
    }

    func testMediaAndTimerPreviewPlacementUsesTheGridSizeClass() {
        let configured = configuration([(.media, .large), (.timer, .compact)])
        let media = SettingsPreviewPresentation.placement(kind: .media, configuration: configured)
        let timer = SettingsPreviewPresentation.placement(kind: .timer, configuration: configured)
        XCTAssertEqual(media.presentationSize, .large)
        XCTAssertEqual(timer.presentationSize, .compact)
        XCTAssertEqual(timer.size.width, timer.size.height)
        XCTAssertGreaterThan(media.size.height, timer.size.height)
        XCTAssertEqual(SettingsPreviewPresentation.fit(size: media.size,
            in: CGSize(width: media.size.width / 2, height: media.size.height)), 0.5)
    }

    func testPreviewPreferencesAreMemoryOnlyAcrossTypedPersistencePaths() {
        let defaults = SettingsPreviewDefaults()
        let key = "settings-preview-isolation-\(UUID().uuidString)"
        defaults.set(true, forKey: key)
        XCTAssertTrue(defaults.bool(forKey: key))
        defaults.set(27, forKey: key)
        XCTAssertEqual(defaults.integer(forKey: key), 27)
        defaults.set(0.25, forKey: key)
        XCTAssertEqual(defaults.double(forKey: key), 0.25)
        defaults.set(Data([1, 2]), forKey: key)
        XCTAssertEqual(defaults.data(forKey: key), Data([1, 2]))
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
        XCTAssertNil(SettingsPreviewDefaults().object(forKey: key), "another preview does not inherit mutations")
        defaults.removeObject(forKey: key)
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testWorkspaceSampleDependenciesHaveNoLiveProviderOrProcessAuthority() {
        let samples = SettingsPreviewWorkspaceSamples()
        XCTAssertEqual(samples.services.calendar.accessState, .fullAccess)
        XCTAssertEqual(samples.services.calendar.events.first?.title, "Sample planning session")
        XCTAssertEqual(samples.services.spotify.connectionState, .needsClientID)
        XCTAssertTrue(samples.services.appLibrary.apps.isEmpty)
        XCTAssertFalse(samples.terminal.isRunning)
        XCTAssertThrowsError(try samples.terminal.startShell())
        XCTAssertFalse(samples.terminal.isRunning)
    }

    func testSampleQuotaUsesBothIndependentProductionWindows() {
        let usage = SettingsPreviewFixtures.accountUsage()
        let indicators = AgentUsageIndicatorPresentation.make(provider: .claude, accountUsage: usage,
            selectedSession: nil, now: SettingsPreviewFixtures.referenceDate)
        XCTAssertEqual(indicators.filter { $0.kind != .context }.count, 2)
        XCTAssertTrue(indicators.filter { $0.kind != .context }.allSatisfy(\.isAvailable))
        XCTAssertNotEqual(indicators[0].fraction, indicators[1].fraction)
    }

    func testSandboxInheritsReduceMotionAndDisablesNativeInteraction() throws {
        let recorder = PreviewEnvironmentRecorder()
        let view = SettingsPreviewSandbox(title: "Test preview") { reduced in
            PreviewEnvironmentProbe(recorder: recorder, passedReduceMotion: reduced)
        }
        let hosting = NSHostingView(rootView: view.frame(width: 500, height: 260))
        hosting.frame = CGRect(x: 0, y: 0, width: 500, height: 260)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(try XCTUnwrap(recorder.reduced), NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        XCTAssertEqual(recorder.passedReduceMotion, recorder.reduced,
                       "the default preview passes the OS preference to production motion helpers")
        XCTAssertEqual(recorder.enabled, false)
        XCTAssertEqual(recorder.preview, true)
        XCTAssertEqual(recorder.rulerInteraction, false)
    }

    func testHiddenHeaderPreviewReclaimsChromeWithoutChangingWidgetSize() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let configured = configuration([(.media, .compact)])
        let visible = SettingsPreviewPresentation(settings: settings, configuration: configured)
        settings.showNavigationControls = false
        let hidden = SettingsPreviewPresentation(settings: settings, configuration: configured)
        XCTAssertEqual(hidden.header.mode, .hidden)
        XCTAssertFalse(hidden.chrome.showHeader)
        XCTAssertEqual(hidden.chrome.tabSwitcherHeight, 0)
        XCTAssertEqual(hidden.chrome.tabToPageSpacing, 0)
        XCTAssertEqual(try XCTUnwrap(hidden.projection.frames.first).frame.size,
                       try XCTUnwrap(visible.projection.frames.first).frame.size)
    }

    func testLiveActivityPreviewUsesResolvedShellAndContainedSidecars() {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        for scenario in LiveActivityLayoutPreviewScenario.allCases {
            let preview = LiveActivityLayoutSettingsPreview.presentation(settings: settings, scenario: scenario)
            XCTAssertEqual(preview.composite.primaryFrame.size, preview.geometry.collapsedFrame.size)
            let bounds = CGRect(origin: .zero, size: preview.canvasSize)
            XCTAssertTrue(bounds.contains(preview.composite.primaryFrame), scenario.rawValue)
            if preview.resolution.leadingSidecar != nil {
                XCTAssertNotNil(preview.composite.leadingSidecarFrame, scenario.rawValue)
            }
            if preview.resolution.trailingSidecar != nil {
                XCTAssertNotNil(preview.composite.trailingSidecarFrame, scenario.rawValue)
            }
            XCTAssertTrue(bounds.contains(preview.composite.interactionFrame), scenario.rawValue)
        }
        settings.respectHardwareNotch = false
        settings.collapsedWidth = 140
        settings.collapsedHeight = 29
        let floating = LiveActivityLayoutSettingsPreview.presentation(settings: settings, scenario: .mediaTimer)
        XCTAssertEqual(floating.geometry.collapsedNotchCoreWidth, 0)
        XCTAssertEqual(floating.geometry.collapsedFrame.height, 29)
        XCTAssertEqual(floating.geometry.collapsedFrame.width, settings.collapsedSize.width)
        let constrained = LiveActivityLayoutSettingsPreview.presentation(settings: settings, scenario: .constrained)
        XCTAssertEqual([constrained.resolution.leadingSidecar, constrained.resolution.trailingSidecar].compactMap { $0 }.count, 1)
    }

    func testTimerPreviewRemountDoesNotMigratePreferencesOrMutateLiveTimer() async throws {
        let defaults = SettingsPreviewDefaults()
        let settings = AppSettings(defaults: defaults)
        let timer = TimerController()
        defaults.set(17, forKey: "focusTimerMinutes")
        defaults.set(0, forKey: "focusTimerSeconds")
        let initial = timer.timingSnapshot
        _ = NSApplication.shared
        for _ in 0..<3 {
            let content = FocusTimerView(timer: timer, settings: settings, showsPanel: false)
                .defaultAppStorage(defaults).environment(\.isSettingsPreview, true).disabled(true)
                .transformEnvironment(\.timerRulerInteractionRegistration) { $0.enabled = false }
            let host = NSHostingView(rootView: content.frame(width: 350, height: 220))
            host.frame = CGRect(x: 0, y: 0, width: 350, height: 220)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            for _ in 0..<3 { try await Task.sleep(for: .milliseconds(3)); host.layoutSubtreeIfNeeded() }
            window.contentView = nil
            window.close()
        }
        XCTAssertEqual(defaults.integer(forKey: "focusTimerSeconds"), 0,
                       "mounting a preview must not perform the production legacy-minute migration")
        XCTAssertEqual(timer.timingSnapshot, initial)
        XCTAssertFalse(timer.isRunning)
    }

    func testPreviewTranscriptMountDoesNotSaveSharedViewportState() async throws {
        _ = NSApplication.shared
        let session = SettingsPreviewFixtures.agentSession(provider: .claude)
        let store = AgentTranscriptViewportStore.shared
        let position = store.position(for: session.id)
        let count = store.count
        let console = AgentEmbeddedConsoleView(session: session,
            transcriptEntries: SettingsPreviewFixtures.transcript(provider: .claude),
            approvalControl: AgentApprovalController(), onSelectSession: { _ in }, onSubmit: { _ in false }, onInterrupt: {})
        let host = NSHostingView(rootView: console.environment(\.isSettingsPreview, true)
            .environment(\.rightWorkspacePageIsActive, false).disabled(true).frame(width: 400, height: 230))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 230)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        for _ in 0..<6 { try await Task.sleep(for: .milliseconds(3)); host.layoutSubtreeIfNeeded() }
        window.contentView = nil
        window.close()
        XCTAssertEqual(store.position(for: session.id), position)
        XCTAssertEqual(store.count, count, "preview layout never adds entries or evicts live transcript positions")
    }
}

@MainActor
private final class PreviewEnvironmentRecorder {
    var reduced: Bool?
    var passedReduceMotion: Bool?
    var enabled: Bool?
    var preview: Bool?
    var rulerInteraction: Bool?
}

private struct PreviewEnvironmentProbe: View {
    let recorder: PreviewEnvironmentRecorder
    let passedReduceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isSettingsPreview) private var preview
    @Environment(\.timerRulerInteractionRegistration) private var rulerInteraction

    var body: some View {
        recorder.reduced = reduced
        recorder.passedReduceMotion = passedReduceMotion
        recorder.enabled = enabled
        recorder.preview = preview
        recorder.rulerInteraction = rulerInteraction.enabled
        return Color.clear
    }
}
