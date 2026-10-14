import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class CollapsedHoverOwnershipTests: XCTestCase {
    func testRenderedUnionPublishesOnlyEntryAndActualExit() {
        let layout = IslandLayoutStore()
        let base = CGRect(x: 100, y: 200, width: 220, height: 34)
        let preview = CGRect(x: 80, y: 140, width: 300, height: 94)
        let sidecar = CGRect(x: 330, y: 200, width: 40, height: 34)
        var edges: [Bool] = []
        let token = layout.$collapsedPointerInside.dropFirst().sink { edges.append($0) }
        for _ in 0..<120 {
            layout.updateCollapsedPointer(at: CGPoint(x: 350, y: 215), frames: [base, sidecar, preview], enabled: true)
        }
        layout.updateCollapsedPointer(at: CGPoint(x: 200, y: 160), frames: [base, sidecar, preview], enabled: true)
        layout.updateCollapsedPointer(at: CGPoint(x: 390, y: 160), frames: [base, sidecar, preview], enabled: true)
        XCTAssertEqual(edges, [true, false])
        withExtendedLifetime(token) {}
    }

    func testProductionRootKeepsStationaryAgentHoverAndPreviewTraversalStable() async throws {
        try await exerciseRoot(sessionCount: 2, reducedMotion: false)
    }

    func testReducedMotionKeepsTheSameHoverOwnership() async throws {
        try await exerciseRoot(sessionCount: 1, reducedMotion: true)
    }

    private func exerciseRoot(sessionCount: Int, reducedMotion: Bool) async throws {
        _ = NSApplication.shared
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.reduceExtraMotion = reducedMotion
        settings.collapsedHoverPreviewDelay = 0
        let modules = NativeIslandFixtureModules.make(settings: settings)
        let offset = Date().timeIntervalSince(AgentTestFixture.baseDate) - 5
        for n in 0..<sessionCount {
            let id = AgentTestFixture.sessionID(n == 0 ? .codex : .claude, "hover-\(n)")
            XCTAssertEqual(modules.agentEvents.ingest(AgentTestFixture.event("start-\(n)", sessionID: id, type: .sessionStarted, offset: offset + Double(n) * 0.1, payload: .sessionMetadata(AgentSessionMetadata(project: .init(displayName: "Synthetic hover"))))), .applied)
            XCTAssertEqual(modules.agentEvents.ingest(AgentTestFixture.event("think-\(n)", sessionID: id, type: .thinkingStarted, offset: offset + 1 + Double(n) * 0.1)), .applied)
        }
        XCTAssertNotNil(AgentCompactPresentation.make(sessions: modules.agentEvents.sessions))
        modules.liveActivities.update(.init(id: "hover-agent", kind: .agent, title: "Fixture", subtitle: nil, symbolName: "terminal",
            priority: 1000, isActive: true, progress: nil, updatedAt: Date()))
        let layout = IslandLayoutStore()
        layout.hasHardwareNotch = false
        layout.canvasSize = CGSize(width: 520, height: 280)
        layout.collapsedSurfaceFrame = CGRect(x: 100, y: 226, width: 320, height: 34)
        let state = IslandStateStore()
        var expansions = 0, collapses = 0
        let root = IslandRootView(settings: settings, islandState: state, layoutStore: layout,
            escapeRouter: IslandEscapeRouter(), modules: modules, rendersExpandedVisualContent: true,
            onRequestExpand: { expansions += 1 }, onRequestCollapse: { collapses += 1 }, onOpenSettings: {})
            .environment(\.settingsPreviewReduceMotion, reducedMotion)
            .environment(\.isSettingsPreview, true)
        let window = IslandOverlayPanel(contentRect: CGRect(x: 100, y: 100, width: 520, height: 280),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = true
        window.acceptsMouseMovedEvents = true
        let host = NSHostingView(rootView: root)
        window.contentView = host; window.orderFrontRegardless()
        var previewEntries = 0, previewExits = 0, deliveredMoves = 0
        let token = layout.$collapsedPreviewActive.dropFirst().removeDuplicates().sink { active in
            if active { previewEntries += 1 } else { previewExits += 1 }
        }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            if event.window === window {
                deliveredMoves += 1
                layout.updateCollapsedPointer(at: event.locationInWindow,
                    frames: [layout.collapsedSurfaceFrame, layout.collapsedLeadingSidecarFrame,
                             layout.collapsedTrailingSidecarFrame, layout.collapsedPreviewSurfaceFrame], enabled: true)
            }
            return event
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            withExtendedLifetime(token) {}
            window.contentView = nil; window.close()
        }
        CameraNativeHostedFixture.pump()
        // The production orb/provider/mini-orb band and then the grown preview body.
        for point in [CGPoint(x: 120, y: 242), CGPoint(x: 400, y: 242), CGPoint(x: 370, y: 242), CGPoint(x: 260, y: 205), CGPoint(x: 120, y: 242)] {
            let deadline = Date().addingTimeInterval(2)
            repeat {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 0, pressure: 0))
                NSApp.postEvent(event, atStart: false)
                CameraNativeHostedFixture.pump()
                try await Task.sleep(for: .milliseconds(10))
            } while Date() < deadline
            XCTAssertGreaterThan(deliveredMoves, 0, "AppKit must deliver the fixture mouse events")
            XCTAssertTrue(layout.collapsedPointerInside, "rendered geometry owns this point")
            XCTAssertTrue(layout.collapsedPreviewActive)
            XCTAssertEqual(previewEntries, 1)
            XCTAssertEqual(previewExits, 0)
        }
        XCTAssertEqual(expansions, 0); XCTAssertEqual(collapses, 0)
        layout.updateCollapsedPointer(at: CGPoint(x: 10, y: 10), frames: [layout.collapsedPreviewSurfaceFrame], enabled: true)
        CameraNativeHostedFixture.pump()
        XCTAssertFalse(layout.collapsedPreviewActive)
        XCTAssertEqual(previewExits, 1)
        XCTAssertFalse(modules.productivity.camera.isRunning)
    }
}

@MainActor
enum NativeIslandFixtureModules {
    private final class EmptyHistory: ClipboardHistoryPersistence, @unchecked Sendable {
        let archiveURL = URL(fileURLWithPath: "/tmp/unused-synthetic-history")
        func loadData() -> Data? { nil }
        func saveDataAtomically(_ data: Data) throws {}
        func deleteArchive() throws {}
    }
    private struct OfflineTokens: SpotifyCredentialStoring {
        func credentials() -> SpotifyStoredCredentials { .init() }
        func store(accessToken: String, expiresAt: Date, refreshToken: String?, authorizationDate: Date?) {}
        func clear() {}
    }
    static func make(settings: AppSettings) -> IslandModules {
        let defaults = SettingsPreviewDefaults(), activities = LiveActivityStore(), capabilities = IslandCapabilityRegistry()
        let shelf = FileShelfStore(settings: settings, defaults: defaults, ownership: TemporaryFileOwnershipLedger(temporaryRoots: []))
        let operations = BackgroundOperationController(liveActivities: activities)
        let background = BackgroundRemovalController(liveActivities: activities, capabilities: capabilities, addToShelf: { _ in })
        let recording = ScreenRecordingController(liveActivities: activities, capabilities: capabilities,
            requestLedger: .init(defaults: defaults, buildIdentity: "hover-fixture"))
        let productivity = ProductivityModules(capabilities: capabilities,
            keepAwake: KeepAwakeController(liveActivities: activities, capabilities: capabilities),
            windowSnap: WindowSnapController(liveActivities: activities, capabilities: capabilities),
            terminal: TerminalSessionController(liveActivities: activities, capabilities: capabilities),
            reminders: RemindersController(liveActivities: activities, capabilities: capabilities),
            voice: VoiceTranscriptionController(liveActivities: activities, capabilities: capabilities, addToShelf: { _ in }),
            camera: CameraPreviewController(liveActivities: activities, capabilities: capabilities),
            backgroundRemoval: background, screenRecording: recording, screenRecordingSetup: .production(controller: recording))
        let events = AgentEventStore(), approvals = AgentApprovalController()
        return IslandModules(media: .settingsPreview(), fileShelf: shelf, backgroundOperations: operations,
            fileDragSession: FileDragSessionController(), shortcuts: ShortcutsStore(defaults: defaults), timer: TimerController(),
            stats: SystemStatsController(), liveActivities: activities,
            clipboardHistory: ClipboardHistoryStore(settings: settings, persistence: EmptyHistory(), automaticallySchedulesTimer: false),
            navigation: IslandNavigationStore(), agentEvents: events, agentAttention: AgentAttentionCoordinator(),
            agentApprovalControl: approvals, agentManagedControl: AgentManagedSessionController(providers: [],
                coordinator: AgentIngestionCoordinator(eventStore: events), eventStore: events, approvals: approvals),
            agentProjects: AgentProjectProjectionStore(), agentActivityRecorder: AgentActivityRecorder(), productivity: productivity,
            systemHUD: SystemHUDController(settings: settings, liveActivities: activities),
            messaging: MessagingController(adapters: [], liveActivities: activities), rightWorkspace: RightWorkspaceStore(defaults: defaults),
            workspaceServices: WorkspaceServices(appLibrary: AppLibraryStore(defaults: defaults), calendar: CalendarEventsController(),
                spotify: SpotifyLibraryController(defaults: defaults, tokens: OfflineTokens())),
            basketPresenter: BasketPresenter(manager: BasketManager(settings: settings, shelf: shelf, operations: operations),
                settings: settings, fileShelf: shelf, backgroundRemoval: background))
    }
}
