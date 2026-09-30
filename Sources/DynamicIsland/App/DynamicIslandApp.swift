import AppKit
import Combine
import SwiftUI

struct LiveActivitySettingsSnapshot: Equatable {
    let liveActivitiesEnabled: Bool
    let showMusicLiveActivity: Bool
    let showTimerLiveActivity: Bool
    let showFileDropLiveActivity: Bool
    let showBatteryLiveActivity: Bool

    init(
        liveActivitiesEnabled: Bool,
        showMusicLiveActivity: Bool,
        showTimerLiveActivity: Bool,
        showFileDropLiveActivity: Bool,
        showBatteryLiveActivity: Bool
    ) {
        self.liveActivitiesEnabled = liveActivitiesEnabled
        self.showMusicLiveActivity = showMusicLiveActivity
        self.showTimerLiveActivity = showTimerLiveActivity
        self.showFileDropLiveActivity = showFileDropLiveActivity
        self.showBatteryLiveActivity = showBatteryLiveActivity
    }

    @MainActor
    init(settings: AppSettings) {
        self.init(
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            showMusicLiveActivity: settings.showMusicLiveActivity,
            showTimerLiveActivity: settings.showTimerLiveActivity,
            showFileDropLiveActivity: settings.showFileDropLiveActivity,
            showBatteryLiveActivity: settings.showBatteryLiveActivity
        )
    }
}

@MainActor
extension AppSettings {
    var liveActivitySettingsPublisher: AnyPublisher<LiveActivitySettingsSnapshot, Never> {
        Publishers.CombineLatest4(
            $liveActivitiesEnabled,
            $showMusicLiveActivity,
            $showTimerLiveActivity,
            $showFileDropLiveActivity
        )
        .combineLatest($showBatteryLiveActivity)
        .map { settings, showBatteryLiveActivity in
            LiveActivitySettingsSnapshot(
                liveActivitiesEnabled: settings.0,
                showMusicLiveActivity: settings.1,
                showTimerLiveActivity: settings.2,
                showFileDropLiveActivity: settings.3,
                showBatteryLiveActivity: showBatteryLiveActivity
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}

@main
struct DynamicIslandApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let islandState = IslandStateStore()
    private lazy var fileShelf = FileShelfStore(settings: settings)
    private let shortcuts = ShortcutsStore()
    private let media = MediaController()
    private let timer = TimerController()
    private let timerNotifications = TimerCompletionNotificationCoordinator()
    private let stats = SystemStatsController()
    private let liveActivities = LiveActivityStore()
    private let capabilityRegistry = IslandCapabilityRegistry()
    private lazy var keepAwakeController = KeepAwakeController(
        liveActivities: liveActivities,
        capabilities: capabilityRegistry
    )
    private lazy var windowSnapController = WindowSnapController(
        liveActivities: liveActivities,
        capabilities: capabilityRegistry
    )
    private lazy var terminalController = TerminalSessionController(
        liveActivities: liveActivities,
        capabilities: capabilityRegistry
    )
    private lazy var remindersController = RemindersController(
        liveActivities: liveActivities,
        capabilities: capabilityRegistry
    )
    private lazy var voiceTranscription = VoiceTranscriptionController(
        liveActivities: liveActivities,
        capabilities: capabilityRegistry,
        addToShelf: { [weak self] urls in
            self?.fileShelf.add(urls)
        }
    )
    private lazy var cameraPreview = CameraPreviewController(
        liveActivities: liveActivities,
        capabilities: capabilityRegistry
    )
    private let rightWorkspace = RightWorkspaceStore()
    private lazy var workspaceServices = WorkspaceServices(
        appLibrary: AppLibraryStore(),
        calendar: CalendarEventsController(),
        spotify: SpotifyLibraryController()
    )
    private lazy var backgroundRemoval = BackgroundRemovalController(
        liveActivities: liveActivities,
        capabilities: capabilityRegistry,
        addToShelf: { [weak self] urls in
            self?.fileShelf.add(urls)
        }
    )
    private lazy var productivity = ProductivityModules(
        capabilities: capabilityRegistry,
        keepAwake: keepAwakeController,
        windowSnap: windowSnapController,
        terminal: terminalController,
        reminders: remindersController,
        voice: voiceTranscription,
        camera: cameraPreview,
        backgroundRemoval: backgroundRemoval
    )
    private lazy var systemHUDController = SystemHUDController(
        settings: settings,
        liveActivities: liveActivities
    )
    private lazy var clipboardHistory = ClipboardHistoryStore(settings: settings)
    private let batteryActivityProvider = BatteryActivityProvider()
    private let navigation = IslandNavigationStore()
    private let geometryService = NotchGeometryService()
    private let agentEvents = AgentEventStore()
    private let agentProjects = AgentProjectProjectionStore()
    private let messagingPreferences = MessagingPreferencesPersistence(defaults: .standard)
    private lazy var messaging = MessagingController(
        adapters: [MessagesAppAdapter()],
        liveActivities: liveActivities,
        preferences: messagingPreferences.load(),
        presentationEnabled: { [weak self] in self?.settings.liveActivitiesEnabled ?? true }
    )
    private let agentAttention = AgentAttentionCoordinator()
    private let agentApprovalControl = AgentApprovalController()
    private lazy var agentIngestion = AgentIngestionCoordinator(eventStore: agentEvents)
    private lazy var agentIntegrationRouter = AgentIntegrationRouter(coordinator: agentIngestion)
    private lazy var agentBridge = AgentBridge(
        coordinator: agentIngestion,
        integrationRouter: agentIntegrationRouter,
        approvals: agentApprovalControl
    )
    private lazy var codexRolloutMonitor = CodexRolloutSessionMonitor(
        coordinator: agentIngestion,
        integrationRouter: agentIntegrationRouter
    )
    private lazy var agentManagedControl: AgentManagedSessionController = {
        var providers: [any AgentInteractiveProvider] = []
        if let codex = try? CodexAppServerProvider.makeDefault() { providers.append(codex) }
        // Claude Code managed sessions over the supported CLI stream-json
        // control protocol (verified against Claude Code 2.1.285).
        if let claude = try? ClaudeInteractiveProvider.makeDefault() { providers.append(claude) }
        return AgentManagedSessionController(
            providers: providers,
            coordinator: agentIngestion,
            integrationRouter: agentIntegrationRouter,
            eventStore: agentEvents,
            approvals: agentApprovalControl
        )
    }()

    private var overlayController: OverlayWindowController?
    private var menuController: MenuBarController?
    private var settingsController: SettingsWindowController?
    private var eventMonitor: Any?
    private var lastObservedFileShelfCount = 0
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        EditMenuInstaller.installIfNeeded()
        shortcuts.seedDefaultsIfNeeded()
        timer.setLifecycleHandler { [weak self] event in
            guard let self else { return }
            timerNotifications.handle(
                event,
                preferences: TimerCompletionNotificationPreferences(
                    notificationsEnabled: settings.timerNotificationEnabled,
                    soundEnabled: settings.timerSoundEnabled
                )
            )
        }

        let modules = IslandModules(
            media: media,
            fileShelf: fileShelf,
            shortcuts: shortcuts,
            timer: timer,
            stats: stats,
            liveActivities: liveActivities,
            clipboardHistory: clipboardHistory,
            navigation: navigation,
            agentEvents: agentEvents,
            agentAttention: agentAttention,
            agentApprovalControl: agentApprovalControl,
            agentManagedControl: agentManagedControl,
            agentProjects: agentProjects,
            productivity: productivity,
            systemHUD: systemHUDController,
            messaging: messaging,
            rightWorkspace: rightWorkspace,
            workspaceServices: workspaceServices
        )
        agentProjects.observe(agentEvents.$sessions)
        installMessagingObservers()
        #if DEBUG
        debugPrint(
            "DynamicIsland AppDelegate modules",
            "mediaInstance=\(ObjectIdentifier(media))"
        )
        #endif

        let overlayController = OverlayWindowController(
            settings: settings,
            islandState: islandState,
            modules: modules,
            geometryService: geometryService,
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )
        self.overlayController = overlayController
        overlayController.setVisible(settings.overlayEnabled)
        LaunchAtLoginController.setEnabled(settings.launchAtLoginEnabled)

        settings.$launchAtLoginEnabled
            .removeDuplicates()
            .sink { enabled in
                LaunchAtLoginController.setEnabled(enabled)
            }
            .store(in: &cancellables)

        settings.$statsRefreshIntervalSeconds
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.stats.setRefreshInterval(interval)
            }
            .store(in: &cancellables)

        installLiveActivityObservers()
        systemHUDController.start()
        installAgentActivityObservers()
        Task { [codexRolloutMonitor] in
            await codexRolloutMonitor.start()
        }

        menuController = MenuBarController(
            settings: settings,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onToggleOverlay: { [weak self] in self?.toggleOverlay() },
            onQuit: { NSApp.terminate(nil) }
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

    }

    /// The Messages page exists only while a visible message is queued.
    private func installMessagingObservers() {
        messaging.$preferences
            .dropFirst()
            .removeDuplicates()
            .sink { [messagingPreferences] preferences in
                messagingPreferences.save(preferences)
            }
            .store(in: &cancellables)

        messaging.$queue
            .combineLatest(messaging.$preferences)
            .map { [weak self] _, _ in !(self?.messaging.visibleEntries.isEmpty ?? true) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasMessages in
                guard let self else { return }
                navigation.hasActionableMessages = hasMessages
                navigation.ensureValidSelection(using: settings)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let clipboardFinalization = clipboardHistory.finalizePersistenceForTermination()
        #if DEBUG
        if clipboardFinalization != .completed {
            print("[ClipboardHistory] termination finalization \(clipboardFinalization)")
        }
        #endif
        keepAwakeController.stop()
        terminalController.terminate()
        voiceTranscription.cancel()
        cameraPreview.terminate()
        backgroundRemoval.terminate()
        systemHUDController.stop()
        agentBridge.stop()
        agentManagedControl.stop()
        Task { [codexRolloutMonitor] in
            await codexRolloutMonitor.stop()
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    @objc private func displaysChanged() {
        overlayController?.reposition()
    }

    /// Real objects the Settings previews render read-only, plus
    /// preview-only objects that exist solely inside Settings.
    private func settingsPreviewDependencies() -> SettingsPreviewDependencies {
        let previewActivities = LiveActivityStore()
        let previewCapabilities = IslandCapabilityRegistry()
        return SettingsPreviewDependencies(
            timer: timer,
            stats: stats,
            clipboardHistory: clipboardHistory,
            shortcuts: shortcuts,
            rightWorkspace: rightWorkspace,
            workspaceServices: workspaceServices,
            agentManagedControl: agentManagedControl,
            productivity: productivity,
            previewMedia: MediaController.settingsPreview(),
            previewShelf: SettingsPreviewFixtures.previewShelf(settings: settings),
            previewBackgroundRemoval: BackgroundRemovalController(
                liveActivities: previewActivities,
                capabilities: previewCapabilities,
                addToShelf: { _ in }
            )
        )
    }

    private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                settings: settings,
                shortcuts: shortcuts,
                agentIngestion: agentIngestion,
                agentEvents: agentEvents,
                productivity: productivity,
                agentManagedControl: agentManagedControl,
                agentProjects: agentProjects,
                messaging: messaging,
                previews: settingsPreviewDependencies()
            )
        }
        settingsController?.show()
    }

    private func toggleOverlay() {
        settings.overlayEnabled.toggle()
    }

    private func installAgentActivityObservers() {
        Publishers.CombineLatest(agentEvents.$attentionEvents, agentEvents.$sessions)
            .sink { [weak self] attentionEvents, sessions in
                self?.agentAttention.synchronize(
                    attentionEvents: attentionEvents,
                    sessions: sessions
                )
            }
            .store(in: &cancellables)

        agentAttention.$soundIntent
            .compactMap { $0 }
            .removeDuplicates()
            .sink { intent in
                SystemAgentNotificationFeedback.shared.play(intent)
            }
            .store(in: &cancellables)

        islandState.$state
            .removeDuplicates()
            .sink { [weak self] state in
                if state == .expanded {
                    self?.agentAttention.dismissForExpansion()
                }
            }
            .store(in: &cancellables)

        settings.$overlayEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.synchronizeAgentActivitySettings()
            }
            .store(in: &cancellables)

        settings.$agentActivityEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                synchronizeAgentActivitySettings()
                if enabled {
                    Task { await self.agentBridge.start() }
                    self.agentManagedControl.startObserving()
                } else {
                    self.agentBridge.stop()
                    self.agentManagedControl.stop()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self, settings.agentActivityEnabled else { return }
                Task { await self.agentManagedControl.refreshPersistentSnapshot() }
            }
            .store(in: &cancellables)

        navigation.$selectedPage
            .removeDuplicates()
            .sink { [weak self] page in
                guard let self,
                      page == .agents,
                      settings.agentActivityEnabled else { return }
                Task { await self.agentManagedControl.refreshPersistentSnapshot() }
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.synchronizeAgentActivitySettings()
                }
            }
            .store(in: &cancellables)

        synchronizeAgentActivitySettings()
    }

    private func synchronizeAgentActivitySettings() {
        agentAttention.configure(
            peekDuration: settings.agentPeekDurationSeconds,
            completionAlertsEnabled: settings.agentCompletionAlertsEnabled,
            approvalAlertsEnabled: settings.agentApprovalAlertsEnabled,
            // AgentNotch plays no notification sound (see
            // AgentNotificationFeedback.swift), so sound intents stay off.
            soundsEnabled: false
        )
        agentAttention.setEnabled(settings.overlayEnabled && settings.agentActivityEnabled)
    }

    private func installLiveActivityObservers() {
        #if DEBUG
        print("[BatteryActivity] started")
        #endif

        Publishers.CombineLatest3(timer.$remainingSeconds, timer.$totalSeconds, timer.$isRunning)
            .sink { [weak self] remainingSeconds, totalSeconds, isRunning in
                self?.updateTimerLiveActivity(
                    remainingSeconds: remainingSeconds,
                    totalSeconds: totalSeconds,
                    isRunning: isRunning
                )
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            media.$hasActiveMediaSource,
            media.$title,
            media.$artist,
            media.$sourceName
        )
        .sink { [weak self] _, _, _, _ in
            self?.updateMediaLiveActivity()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            media.$isPlaying,
            media.$hasPlaybackProgress,
            media.$playbackPosition,
            media.$duration
        )
        .sink { [weak self] _, _, _, _ in
            self?.updateMediaLiveActivity()
        }
        .store(in: &cancellables)

        lastObservedFileShelfCount = fileShelf.files.count
        fileShelf.$files
            .sink { [weak self] files in
                self?.updateFileTrayLiveActivity(files: files)
            }
            .store(in: &cancellables)

        settings.liveActivitySettingsPublisher
            .sink { [weak self] settings in
                self?.refreshLiveActivitiesForSettingsChange(settings)
            }
            .store(in: &cancellables)

        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateBatteryLiveActivity()
            }
            .store(in: &cancellables)

        updateBatteryLiveActivity()
    }

    private func refreshLiveActivitiesForSettingsChange(_ settings: LiveActivitySettingsSnapshot) {
        guard settings.liveActivitiesEnabled else {
            liveActivities.removeAll()
            return
        }
        updateTimerLiveActivity(
            remainingSeconds: timer.remainingSeconds,
            totalSeconds: timer.totalSeconds,
            isRunning: timer.isRunning,
            settings: settings
        )
        updateMediaLiveActivity(settings: settings)
        updateFileTrayLiveActivity(files: fileShelf.files, settings: settings)
        updateBatteryLiveActivity(settings: settings)
        messaging.republishActivity()
    }

    private func updateTimerLiveActivity(
        remainingSeconds: Int,
        totalSeconds: Int,
        isRunning: Bool,
        settings liveActivitySettings: LiveActivitySettingsSnapshot? = nil
    ) {
        let liveActivitySettings = liveActivitySettings ?? LiveActivitySettingsSnapshot(settings: settings)
        guard liveActivitySettings.liveActivitiesEnabled, liveActivitySettings.showTimerLiveActivity else {
            liveActivities.remove(id: LiveActivityStore.timerActivityID)
            return
        }
        let hasPausedPartialTimer = !isRunning && remainingSeconds > 0 && remainingSeconds < totalSeconds
        guard isRunning || hasPausedPartialTimer else {
            liveActivities.remove(id: LiveActivityStore.timerActivityID)
            return
        }

        let progress = TimerProgressFormatting.progress(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds
        )
        liveActivities.update(
            DynamicIslandLiveActivity(
                id: LiveActivityStore.timerActivityID,
                kind: .timer,
                title: "Timer",
                subtitle: isRunning ? Self.formattedTimerText(remainingSeconds) : "Paused • \(Self.formattedTimerText(remainingSeconds))",
                symbolName: isRunning ? "timer" : "pause.circle.fill",
                priority: isRunning ? 90 : 70,
                isActive: isRunning,
                progress: LiveActivityStore.clampedProgress(progress),
                updatedAt: Date()
            )
        )
    }

    private func updateMediaLiveActivity(settings liveActivitySettings: LiveActivitySettingsSnapshot? = nil) {
        let liveActivitySettings = liveActivitySettings ?? LiveActivitySettingsSnapshot(settings: settings)
        guard liveActivitySettings.liveActivitiesEnabled,
              liveActivitySettings.showMusicLiveActivity,
              media.hasActiveMediaSource else {
            liveActivities.remove(id: LiveActivityStore.mediaActivityID)
            return
        }
        let subtitleParts = [media.artist, media.sourceName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let progress: Double?
        if media.hasPlaybackProgress {
            progress = media.duration > 0 ? media.playbackPosition / media.duration : nil
        } else {
            progress = nil
        }

        liveActivities.update(
            DynamicIslandLiveActivity(
                id: LiveActivityStore.mediaActivityID,
                kind: .media,
                title: media.title,
                subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " • "),
                symbolName: media.isPlaying ? "play.fill" : "pause.fill",
                priority: media.isPlaying ? 80 : 55,
                isActive: media.isPlaying,
                progress: LiveActivityStore.clampedProgress(progress),
                updatedAt: Date()
            )
        )
    }

    private func updateFileTrayLiveActivity(
        files: [URL],
        settings liveActivitySettings: LiveActivitySettingsSnapshot? = nil
    ) {
        let liveActivitySettings = liveActivitySettings ?? LiveActivitySettingsSnapshot(settings: settings)
        guard liveActivitySettings.liveActivitiesEnabled, liveActivitySettings.showFileDropLiveActivity else {
            liveActivities.remove(id: LiveActivityStore.fileTrayActivityID)
            lastObservedFileShelfCount = files.count
            return
        }
        defer {
            lastObservedFileShelfCount = files.count
        }
        guard !files.isEmpty else {
            liveActivities.remove(id: LiveActivityStore.fileTrayActivityID)
            return
        }
        guard files.count > lastObservedFileShelfCount else { return }

        liveActivities.update(
            DynamicIslandLiveActivity(
                id: LiveActivityStore.fileTrayActivityID,
                kind: .fileTray,
                title: "Files added",
                subtitle: "\(files.count) \(files.count == 1 ? "file" : "files") in Tray",
                symbolName: "tray.and.arrow.down.fill",
                priority: 50,
                isActive: true,
                progress: nil,
                updatedAt: Date()
            )
        )
    }

    private func updateBatteryLiveActivity(settings liveActivitySettings: LiveActivitySettingsSnapshot? = nil) {
        let liveActivitySettings = liveActivitySettings ?? LiveActivitySettingsSnapshot(settings: settings)
        guard liveActivitySettings.liveActivitiesEnabled, liveActivitySettings.showBatteryLiveActivity else {
            BatteryActivityProvider.debugRemoving(reason: "disabled")
            liveActivities.remove(id: LiveActivityStore.batteryActivityID)
            return
        }
        guard let snapshot = batteryActivityProvider.snapshot() else {
            liveActivities.remove(id: LiveActivityStore.batteryActivityID)
            return
        }
        guard snapshot.isEligible, let activity = snapshot.liveActivity() else {
            BatteryActivityProvider.debugRemoving(reason: "ineligible")
            liveActivities.remove(id: LiveActivityStore.batteryActivityID)
            return
        }

        liveActivities.update(activity)
    }

    private static func formattedTimerText(_ seconds: Int) -> String {
        LiveActivityTimeFormatting.remainingTime(seconds)
    }
}
