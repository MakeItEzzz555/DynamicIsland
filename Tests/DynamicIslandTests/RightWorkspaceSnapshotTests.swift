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
                        availableHeight: 86,
                        compactScale: 1
                    )
                    .frame(height: 86, alignment: .topLeading)
                    ShortcutsModuleView(
                        shortcuts: self.shortcuts,
                        availableHeight: 86,
                        compactScale: 1,
                        onShortcutLaunched: {}
                    )
                    .frame(height: 86, alignment: .topLeading)
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
