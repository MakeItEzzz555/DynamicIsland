import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Opt-in renders of the right workspace for visual review. Uses the real
/// production views and controllers (no prompts are triggered: controllers
/// only read permission state). Enable with
/// DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR=<dir>.
@MainActor
final class RightWorkspaceSnapshotTests: XCTestCase {
    func testRenderRightWorkspacePages() async throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR to render workspace screenshots.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let harness = WorkspaceRenderHarness()
        await harness.services.appLibrary.reload()
        await harness.services.appLibrary.waitForLoad()

        for page in RightWorkspacePage.allCases {
            harness.store.show(page)
            try render(harness.workspace(), name: "40-right-workspace-\(page.rawValue)", to: output)
        }
    }

    private func render<V: View>(_ view: V, name: String, to directory: URL) throws {
        let size = CGSize(width: 470, height: 230)
        let hosting = NSHostingView(rootView: view
            .frame(width: 430, height: 196)
            .padding(17)
            .background(Color.black)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

/// Real production objects for workspace rendering.
@MainActor
final class WorkspaceRenderHarness {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "WorkspaceRender-\(UUID().uuidString)")!)
    let liveActivities = LiveActivityStore()
    let registry = IslandCapabilityRegistry()
    let navigation = IslandNavigationStore()
    let shortcuts = ShortcutsStore()
    let store = RightWorkspaceStore(defaults: UserDefaults(suiteName: "WorkspaceRenderStore-\(UUID().uuidString)")!)
    lazy var fileShelf = FileShelfStore(settings: settings, defaults: UserDefaults(suiteName: "WorkspaceRenderShelf-\(UUID().uuidString)")!)
    lazy var productivity = ProductivityModules(
        capabilities: registry,
        keepAwake: KeepAwakeController(liveActivities: liveActivities, capabilities: registry),
        windowSnap: WindowSnapController(liveActivities: liveActivities, capabilities: registry),
        terminal: TerminalSessionController(liveActivities: liveActivities, capabilities: registry),
        reminders: RemindersController(liveActivities: liveActivities, capabilities: registry),
        voice: VoiceTranscriptionController(liveActivities: liveActivities, capabilities: registry, addToShelf: { _ in }),
        camera: CameraPreviewController(liveActivities: liveActivities, capabilities: registry),
        backgroundRemoval: BackgroundRemovalController(liveActivities: liveActivities, capabilities: registry, addToShelf: { _ in })
    )
    let services = WorkspaceServices(
        appLibrary: AppLibraryStore(defaults: UserDefaults(suiteName: "WorkspaceRenderApps-\(UUID().uuidString)")!),
        calendar: CalendarEventsController(),
        spotify: SpotifyLibraryController(
            defaults: UserDefaults(suiteName: "WorkspaceRenderSpotify-\(UUID().uuidString)")!,
            tokens: SpotifyTokenStore(service: "com.local.dynamicisland.spotify.render")
        )
    )

    func workspace() -> some View {
        RightWorkspaceView(
            store: store,
            layoutStore: nil,
            reduceMotion: false,
            overview: {
                VStack(spacing: 10) {
                    LiveActivitiesModuleView(
                        liveActivities: self.liveActivities,
                        navigation: self.navigation,
                        settings: self.settings,
                        availableHeight: 85,
                        compactScale: 1
                    )
                    .frame(height: 85, alignment: .topLeading)
                    ShortcutsModuleView(
                        shortcuts: self.shortcuts,
                        availableHeight: 85,
                        compactScale: 1,
                        onShortcutLaunched: {}
                    )
                    .frame(height: 85, alignment: .topLeading)
                }
            },
            productivity: {
                ProductivityDeckView(
                    productivity: self.productivity,
                    fileShelf: self.fileShelf,
                    tools: self.store.configuration.visibleTools,
                    reduceMotion: false
                )
            },
            appsMedia: {
                AppsMediaDeckView(
                    services: self.services,
                    media: nil,
                    sections: self.store.configuration.visibleSections,
                    layoutStore: nil
                )
            }
        )
    }
}

/// Opt-in renders of the Settings live previews (same env var).
@MainActor
final class SettingsPreviewSnapshotTests: XCTestCase {
    func testRenderSettingsPreviews() async throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR to render settings previews.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let harness = WorkspaceRenderHarness()
        harness.settings.clipboardHistoryEnabled = false
        let previewActivities = LiveActivityStore()
        let registry = IslandCapabilityRegistry()
        let claude = ClaudeInteractiveProvider(
            client: try ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"))
        )
        let agents = AgentManagedSessionController(
            providers: [claude, CodexAppServerProvider(client: try CodexAppServerClient())],
            coordinator: AgentIngestionCoordinator(eventStore: AgentEventStore()),
            eventStore: AgentEventStore(),
            approvals: AgentApprovalController()
        )
        agents.selectProvider(.claude)
        let deps = SettingsPreviewDependencies(
            timer: TimerController(),
            stats: SystemStatsController(),
            clipboardHistory: ClipboardHistoryStore(settings: harness.settings, automaticallySchedulesTimer: false),
            shortcuts: harness.shortcuts,
            rightWorkspace: harness.store,
            workspaceServices: harness.services,
            agentManagedControl: agents,
            productivity: harness.productivity,
            previewMedia: MediaController.settingsPreview(),
            previewShelf: SettingsPreviewFixtures.previewShelf(settings: harness.settings),
            previewBackgroundRemoval: BackgroundRemovalController(
                liveActivities: previewActivities, capabilities: registry, addToShelf: { _ in }
            )
        )
        let settings = harness.settings
        let views: [(String, AnyView)] = [
            ("50-settings-island", AnyView(IslandShellSettingsPreview(settings: settings))),
            ("51-settings-media", AnyView(MediaSettingsPreview(settings: settings, media: deps.previewMedia))),
            ("52-settings-right-workspace", AnyView(RightWorkspaceSettingsView(settings: settings, workspace: deps.rightWorkspace, dependencies: deps))),
            ("53-settings-agents", AnyView(AgentsSettingsPreview(managedControl: agents))),
            ("54-settings-tray", AnyView(FileTraySettingsPreview(settings: settings, shelf: deps.previewShelf, backgroundRemoval: deps.previewBackgroundRemoval))),
            ("55-settings-live-activity-layout", AnyView(LiveActivityLayoutSettingsPreview(settings: settings))),
            ("56-settings-stats", AnyView(StatsSettingsPreview(settings: settings, stats: deps.stats))),
            ("58-settings-timer-page", AnyView(TimerPageSettingsPreview(settings: settings, timer: deps.timer))),
            ("57-settings-productivity", AnyView(ProductivityDeckSettingsPreview(workspace: deps.rightWorkspace, productivity: deps.productivity, shelf: deps.previewShelf))),
            ("58-settings-content-motion", AnyView(ContentMotionSettingsPreview(settings: settings))),
            ("59-settings-collapsed-media", AnyView(CollapsedMediaSettingsPreview(settings: settings, media: deps.previewMedia))),
            ("60-settings-collapsed-hover", AnyView(CollapsedHoverSettingsPreview(settings: settings, media: deps.previewMedia))),
            ("61-settings-media-launcher", AnyView(MediaLauncherSettingsPreview(settings: settings, media: deps.previewMedia)))
        ]
        for (name, view) in views {
            let size = CGSize(width: 700, height: name.contains("right-workspace") ? 900 : 320)
            let hosting = NSHostingView(rootView: view.padding(20).frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor)))
            hosting.frame = CGRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            hosting.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
        }
    }
}
