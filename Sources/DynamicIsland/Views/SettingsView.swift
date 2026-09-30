import AppKit
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case island = "Island"
    case appearance = "Appearance"
    case motion = "Motion"
    case tabs = "Tabs"
    case media = "Media"
    case tray = "Tray"
    case timer = "Timer"
    case stats = "Stats"
    case agents = "AI Agents"
    case clipboard = "Clipboard"
    case productivity = "Productivity"
    case messaging = "Messaging"
    case liveActivities = "Live Activities"
    case gestures = "Gestures"
    case advanced = "Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .island: "capsule.tophalf.filled"
        case .appearance: "paintbrush"
        case .motion: "sparkles"
        case .tabs: "square.grid.2x2"
        case .media: "music.note"
        case .tray: "tray.full"
        case .timer: "timer"
        case .stats: "chart.xyaxis.line"
        case .agents: "cpu"
        case .clipboard: "doc.on.clipboard"
        case .productivity: "wand.and.stars"
        case .messaging: "message"
        case .liveActivities: "waveform.path.ecg"
        case .gestures: "hand.raised"
        case .advanced: "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcuts: ShortcutsStore
    let productivity: ProductivityModules
    let agentEvents: AgentEventStore
    let agentManagedControl: AgentManagedSessionController?
    let agentProjects: AgentProjectProjectionStore?
    let messaging: MessagingController?
    @StateObject private var agentSetup = AgentIntegrationSetupController()
    @StateObject private var agentDiagnostics: AgentIntegrationDiagnosticsController
    @State private var selectedSection: SettingsSection = .island
    @State private var systemHUDAccessibilityGranted = SystemHUDAccessibilityPermission.isGranted

    init(
        settings: AppSettings,
        shortcuts: ShortcutsStore,
        agentIngestion: AgentIngestionCoordinator,
        agentEvents: AgentEventStore,
        productivity: ProductivityModules,
        agentManagedControl: AgentManagedSessionController? = nil,
        agentProjects: AgentProjectProjectionStore? = nil,
        messaging: MessagingController? = nil
    ) {
        self.messaging = messaging
        self.settings = settings
        self.shortcuts = shortcuts
        self.productivity = productivity
        self.agentEvents = agentEvents
        self.agentManagedControl = agentManagedControl
        self.agentProjects = agentProjects
        _agentDiagnostics = StateObject(
            wrappedValue: AgentIntegrationDiagnosticsController(
                coordinator: agentIngestion,
                eventStore: agentEvents
            )
        )
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedSection {
                    case .island:
                        islandSection
                    case .appearance:
                        appearanceSection
                    case .motion:
                        motionSection
                    case .tabs:
                        tabsSection
                    case .media:
                        mediaSection
                    case .tray:
                        traySection
                    case .timer:
                        timerSection
                    case .stats:
                        statsSection
                    case .agents:
                        agentsSection
                    case .clipboard:
                        clipboardSection
                    case .productivity:
                        settingsForm("Productivity") {
                            ProductivitySettingsView(productivity: productivity)
                        }
                    case .messaging:
                        settingsForm("Messaging") {
                            if let messaging {
                                MessagingSettingsView(controller: messaging)
                            } else {
                                HelpText("Messaging is unavailable.")
                            }
                        }
                    case .liveActivities:
                        liveActivitiesSection
                    case .gestures:
                        gesturesSection
                    case .advanced:
                        advancedSection
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 920, height: 700)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemHUDAccessibilityGranted = SystemHUDAccessibilityPermission.isGranted
        }
    }

    private var islandSection: some View {
        settingsForm("Island") {
            SettingsGroup("General") {
                Toggle("Enable overlay", isOn: $settings.overlayEnabled)
                Toggle("Launch at login", isOn: $settings.launchAtLoginEnabled)
                Toggle("Start collapsed on launch", isOn: $settings.startCollapsedOnLaunch)
                Toggle("Expand on click", isOn: $settings.expandOnClick)
                Toggle("Collapse on mouse leave", isOn: $settings.collapseOnMouseLeave)
                Toggle("Auto collapse", isOn: $settings.autoCollapseEnabled)
                Toggle("Expand on hover", isOn: $settings.expandOnHover)
                    .disabled(true)
                HelpText("Expand on hover is stored now and left unwired until a dedicated hover-expansion pass.")
            }

            SettingsGroup("Auto Collapse") {
                Picker("Delay preset", selection: $settings.autoCollapseDelayPreset) {
                    ForEach(AutoCollapseDelayPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                SliderRow(
                    title: "Manual grace",
                    value: $settings.autoCollapseGraceSeconds,
                    range: 0.10...2.00,
                    format: "%.2fs",
                    disabled: settings.autoCollapseDelayPreset != .manual
                )
            }

            SettingsGroup("Size") {
                Toggle("Use adaptive notch sizing", isOn: $settings.useAdaptiveNotchSizing)
                Toggle("Respect hardware notch", isOn: $settings.respectHardwareNotch)
                SliderRow(title: "Collapsed width", value: $settings.collapsedWidth, range: 120...360, format: "%.0f pt")
                SliderRow(title: "Collapsed height", value: $settings.collapsedHeight, range: 28...64, format: "%.0f pt")
                SliderRow(title: "Expanded width", value: $settings.expandedWidth, range: 520...920, format: "%.0f pt")
                SliderRow(title: "Expanded height", value: $settings.expandedHeight, range: 180...360, format: "%.0f pt")
            }
        }
    }

    private var appearanceSection: some View {
        settingsForm("Appearance") {
            SettingsGroup("Shell") {
                Picker("Island Theme", selection: $settings.islandThemeStyle) {
                    ForEach(IslandThemeStyle.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                SliderRow(title: "Shell opacity", value: $settings.shellOpacity, range: 0.35...1.0, format: "%.2f")
                Toggle("Shell stroke", isOn: $settings.shellStrokeEnabled)
                HelpText("Liquid Glass uses Apple’s native glassEffect when available. On older macOS versions or older SDKs, DynamicIsland uses a fallback material/gloss effect.")
            }

            SettingsGroup("Visualizer") {
                Toggle("Use artwork accent color", isOn: $settings.useArtworkAccentColor)
                Picker("Accent mode", selection: $settings.visualizerAccentMode) {
                    ForEach(VisualizerAccentMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Show collapsed visualizer", isOn: $settings.showCollapsedVisualizer)
                Toggle("Show expanded visualizer", isOn: $settings.showExpandedVisualizer)
            }

            SettingsGroup("Collapsed Preview") {
                Toggle("Enable hover preview", isOn: $settings.collapsedHoverPreviewEnabled)
                Toggle("Use media preview", isOn: $settings.collapsedHoverPreviewMediaEnabled)
                    .disabled(!settings.collapsedHoverPreviewEnabled)
                SliderRow(
                    title: "Preview height",
                    value: $settings.collapsedHoverPreviewHeight,
                    range: 44...96,
                    format: "%.0f pt",
                    disabled: !settings.collapsedHoverPreviewEnabled
                )
                SliderRow(
                    title: "Preview delay",
                    value: $settings.collapsedHoverPreviewDelay,
                    range: 0...0.4,
                    format: "%.2fs",
                    disabled: !settings.collapsedHoverPreviewEnabled
                )
                Toggle("Show song name", isOn: $settings.collapsedHoverPreviewShowTitle)
                    .disabled(!settings.collapsedHoverPreviewEnabled || !settings.collapsedHoverPreviewMediaEnabled)
                Toggle("Show artist", isOn: $settings.collapsedHoverPreviewShowsArtist)
                    .disabled(!settings.collapsedHoverPreviewEnabled || !settings.collapsedHoverPreviewMediaEnabled)
                Toggle("Use source name if artist missing", isOn: $settings.collapsedHoverPreviewShowsSource)
                    .disabled(!settings.collapsedHoverPreviewEnabled || !settings.collapsedHoverPreviewMediaEnabled || !settings.collapsedHoverPreviewShowsArtist)
                HelpText("Hover preview expands the collapsed pill visually without resizing the overlay panel.")
            }
        }
    }

    private var motionSection: some View {
        settingsForm("Motion") {
            SettingsGroup("Animation") {
                Picker("Preset", selection: $settings.animationPreset) {
                    ForEach(AnimationPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                Toggle("Reduce extra motion", isOn: $settings.reduceExtraMotion)
                SliderRow(title: "Shell speed", value: $settings.shellAnimationSpeed, range: 0.25...2.0, format: "%.2fx")
                Toggle("Content animation", isOn: $settings.contentAnimationEnabled)
                Toggle("Content stagger", isOn: $settings.contentStaggerEnabled)
                SliderRow(title: "Stagger amount", value: $settings.contentStaggerAmount, range: 0...2.0, format: "%.2f", disabled: !settings.contentStaggerEnabled)
                Toggle("Blur transitions", isOn: $settings.useBlurTransitions)
                Toggle("Scale transitions", isOn: $settings.useScaleTransitions)
                HelpText("Expansion still avoids fade-in. Opacity is only available to the staged removal path.")
            }
        }
    }

    private var tabsSection: some View {
        settingsForm("Tabs") {
            SettingsGroup("Visible Tabs") {
                Toggle("Island tab", isOn: .constant(true))
                    .disabled(true)
                Toggle("Tray tab", isOn: $settings.showTrayTab)
                Toggle("Timer tab", isOn: $settings.showTimerTab)
                Toggle("Stats tab", isOn: $settings.showStatsTab)
                Toggle("Tools tab", isOn: $settings.showToolsTab)
                Toggle("Activities tab", isOn: $settings.showActivitiesTab)
                    .disabled(true)
                Toggle("Live Activities tab", isOn: $settings.showLiveActivitiesTab)
                    .disabled(true)
                Toggle("Gestures tab", isOn: $settings.showGesturesTab)
                    .disabled(true)
                HelpText("Only Island, Tray, Timer, and Stats are implemented as live tabs in this phase.")
            }

            SettingsGroup("Selection") {
                Toggle("Remember last selected tab", isOn: $settings.rememberLastSelectedTab)
                Picker("Default expanded tab", selection: $settings.defaultExpandedTab) {
                    ForEach(DefaultExpandedTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
            }
        }
    }

    private var mediaSection: some View {
        settingsForm("Media") {
            SettingsGroup("Visibility") {
                Toggle("Enable media", isOn: $settings.mediaEnabled)
                Toggle("Show when paused", isOn: $settings.showMediaWhenPaused)
                Toggle("Show launcher when no source", isOn: $settings.showMediaWhenNoSource)
                Toggle("Show album artwork", isOn: $settings.showAlbumArtwork)
                Toggle("Show title", isOn: $settings.showMediaTitle)
                Toggle("Show artist", isOn: $settings.showMediaArtist)
                Toggle("Show source name", isOn: $settings.showMediaSourceName)
                Toggle("Show visualizer", isOn: $settings.showVisualizer)
            }

            SettingsGroup("Controls") {
                Toggle("Show playback controls", isOn: $settings.showPlaybackControls)
                Toggle("Show progress slider", isOn: $settings.showProgressSlider)
                Toggle("Show volume slider", isOn: $settings.showVolumeSlider)
                Toggle("Open source on artwork click", isOn: $settings.openSourceOnArtworkClick)
                Toggle("Collapse after opening source", isOn: $settings.collapseAfterOpeningMediaSource)
                Toggle("Collapse after launcher", isOn: $settings.collapseAfterMediaLauncher)
            }

            SettingsGroup("Launchers") {
                Toggle("Enable launchers", isOn: $settings.mediaLauncherEnabled)
                Toggle("Show Apple Music launcher", isOn: $settings.showAppleMusicLauncher)
                Toggle("Show Spotify launcher", isOn: $settings.showSpotifyLauncher)
                Toggle("Show YouTube launcher", isOn: $settings.showYouTubeLauncher)
            }

            SettingsGroup("Providers") {
                Toggle("Prefer System Now Playing", isOn: $settings.preferSystemNowPlaying)
                    .disabled(true)
                Toggle("Prefer Spotify AppleScript", isOn: $settings.preferSpotifyAppleScript)
                    .disabled(true)
                Toggle("Prefer browser media", isOn: $settings.preferBrowserMedia)
                    .disabled(true)
                Toggle("Browser media detection", isOn: $settings.browserMediaDetectionEnabled)
                    .disabled(true)
                Toggle("YouTube metadata enrichment", isOn: $settings.youtubeMetadataEnrichmentEnabled)
                    .disabled(true)
                HelpText("Provider preference fields are persisted now and left for a dedicated media-provider wiring pass.")
            }
        }
    }

    private var traySection: some View {
        settingsForm("Tray") {
            SettingsGroup("Tray") {
                Toggle("Enable tray", isOn: $settings.trayEnabled)
                Toggle("Enable file shelf", isOn: $settings.fileShelfEnabled)
                Toggle("Enable AirDrop zone", isOn: $settings.airDropZoneEnabled)
                Toggle("Allow collapsed file drops", isOn: $settings.allowFileDropsOnCollapsedIsland)
                Toggle("Allow expanded tray drops", isOn: $settings.allowFileDropsOnExpandedTray)
                Stepper("Max shelf files: \(settings.maxShelfFiles)", value: $settings.maxShelfFiles, in: 1...48)
            }

            SettingsGroup("Files") {
                Toggle("Show thumbnails", isOn: $settings.showFileThumbnails)
                Toggle("Defer thumbnails during morph", isOn: $settings.deferThumbnailsDuringMorph)
                Toggle("Show file extensions", isOn: $settings.showFileExtensions)
                Toggle("Show file count badge", isOn: $settings.showFileCountBadge)
                Toggle("Confirm before clearing shelf", isOn: $settings.confirmBeforeClearShelf)
                Toggle("Persist shelf across launches", isOn: $settings.persistFileShelfAcrossLaunches)
                HelpText("Persistence restores existing files on launch and silently drops missing files.")
            }

            SettingsGroup("Actions") {
                Toggle("Open file action", isOn: $settings.openFileActionEnabled)
                Toggle("Reveal in Finder action", isOn: $settings.revealInFinderActionEnabled)
                Toggle("Copy path actions", isOn: $settings.copyPathActionEnabled)
                Toggle("Remove file action", isOn: $settings.removeFileActionEnabled)
                Toggle("AirDrop fallback reveal in Finder", isOn: $settings.airDropFallbackRevealInFinder)
            }
        }
    }

    private var timerSection: some View {
        settingsForm("Timer") {
            SettingsGroup("Timer") {
                Toggle("Enable timer", isOn: $settings.timerEnabled)
                Toggle("Preset buttons", isOn: $settings.timerPresetsEnabled)
                Toggle("Show progress ring", isOn: $settings.showTimerProgressRing)
                Toggle("Ring animation", isOn: $settings.timerRingAnimationEnabled)
                Toggle("Collapse after starting timer", isOn: $settings.collapseAfterStartingTimer)
                Toggle("Keep expanded while timer runs", isOn: $settings.keepIslandExpandedWhenTimerRunning)
                    .disabled(true)
                HelpText("Keeping the island pinned while the timer runs is stored now and left for a later interaction pass.")
            }

            SettingsGroup("Presets") {
                Stepper("Preset 1: \(settings.timerPreset1Minutes)m", value: $settings.timerPreset1Minutes, in: 1...180)
                Stepper("Preset 2: \(settings.timerPreset2Minutes)m", value: $settings.timerPreset2Minutes, in: 1...180)
                Stepper("Preset 3: \(settings.timerPreset3Minutes)m", value: $settings.timerPreset3Minutes, in: 1...180)
            }

            SettingsGroup("Completion") {
                Toggle("Timer notification", isOn: $settings.timerNotificationEnabled)
                Toggle("Timer sound", isOn: $settings.timerSoundEnabled)
                    .disabled(!settings.timerNotificationEnabled)
                HelpText("Timer completion notifications use the native macOS alert and system sound.")
            }

            SettingsGroup("Future Options") {
                Toggle("Show timer in collapsed island", isOn: $settings.showTimerInCollapsedIsland)
                    .disabled(true)
                HelpText("Collapsed-timer presentation is stored now and not implemented yet.")
            }
        }
    }

    private var agentsSection: some View {
        settingsForm("AI Agents") {
            SettingsGroup("Agent Activity") {
                Toggle("Enable agent activity", isOn: $settings.agentActivityEnabled)
                Toggle("Show Agents tab", isOn: $settings.showAgentsTab)
                    .disabled(!settings.agentActivityEnabled)
                Toggle("Completion alerts", isOn: $settings.agentCompletionAlertsEnabled)
                    .disabled(!settings.agentActivityEnabled)
                Toggle("Input alerts", isOn: $settings.agentApprovalAlertsEnabled)
                    .disabled(!settings.agentActivityEnabled)
                Toggle("Alert sounds", isOn: $settings.agentSoundsEnabled)
                    .disabled(!settings.agentActivityEnabled)
                Toggle("Usage metrics", isOn: $settings.agentUsageMetricsEnabled)
                    .disabled(!settings.agentActivityEnabled)
                SliderRow(
                    title: "Alert duration",
                    value: $settings.agentPeekDurationSeconds,
                    range: 1...10,
                    format: "%.1fs",
                    disabled: !settings.agentActivityEnabled
                )
                HelpText("Usage values are shown only when supported data is available.")
            }

            if let agentManagedControl, let agentProjects {
                SettingsGroup("Provider & Project Diagnostics") {
                    AgentDiagnosticsView(
                        agentEvents: agentEvents,
                        managedControl: agentManagedControl,
                        projects: agentProjects
                    )
                }
            }

            SettingsGroup("Provider Setup") {
                agentProviderSetupRow(.codex)
                Divider()
                agentProviderSetupRow(.claude)

                HStack(spacing: 8) {
                    Button("Refresh status") {
                        agentSetup.refresh()
                        agentDiagnostics.refresh()
                    }
                    .disabled(agentSetup.isWorking || agentDiagnostics.isRefreshing)

                    if agentSetup.isWorking || agentDiagnostics.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let error = agentSetup.lastError {
                    Text(error)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                HelpText(
                    "Setup is opt-in. DynamicIsland previews the exact observer hooks before writing, " +
                    "backs up the existing file, preserves unrelated JSON keys and handlers, and refuses " +
                    "unsafe, malformed, read-only, or externally changed files. Hooks are observer-only " +
                    "and cannot approve or deny actions. Restart the provider or start a new session after changes. " +
                    "Codex also requires reviewing and trusting the installed hooks with /hooks."
                )
            }

            if let preview = agentSetup.preview {
                SettingsGroup("Setup Preview") {
                    Text(preview.provider.displayName + " • " + preview.configPath)
                        .font(.system(size: 11, weight: .semibold))
                        .textSelection(.enabled)

                    ScrollView(.vertical) {
                        Text(preview.text)
                            .font(.system(size: 9, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 220)

                    HStack(spacing: 8) {
                        Button("Apply") {
                            agentSetup.applyPreview()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(agentSetup.isWorking)

                        Button("Cancel") {
                            agentSetup.cancelPreview()
                        }
                        .disabled(agentSetup.isWorking)
                    }
                }
            }
        }
        .onAppear {
            agentSetup.refresh()
            agentDiagnostics.refresh()
        }
    }

    @ViewBuilder
    private func agentProviderSetupRow(_ provider: AgentIntegrationProvider) -> some View {
        let snapshot = agentSetup.snapshots[provider]
        let diagnostics = snapshot.map {
            AgentIntegrationDiagnostics.make(
                provider: provider,
                setup: $0.state,
                active: agentDiagnostics.activeHealth,
                stopped: agentDiagnostics.stoppedHealth
            )
        }
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                let agentProvider: AgentProvider = provider == .codex ? .codex : .claude
                Image(systemName: AgentVisualStyle.providerSymbol(agentProvider))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AgentVisualStyle.providerAccent(agentProvider))
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.055), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    if let snapshot {
                        Text(snapshot.detail)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let diagnostics {
                    Label(diagnostics.state.label, systemImage: agentOperationalStatusSymbol(diagnostics.state))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(agentOperationalStatusColor(diagnostics.state))
                        .accessibilityLabel("\(provider.displayName) status: \(diagnostics.state.label)")
                } else {
                    Text("Checking…")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot {
                if let diagnostics {
                    AgentSourceHealthRow(provider: provider, diagnostics: diagnostics)
                }

                HStack(alignment: .center, spacing: 10) {
                    Text(snapshot.configPath)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        switch snapshot.state {
                        case .configured:
                            Button("Reconfigure…") { agentSetup.prepare(provider) }
                            Button("Remove") { agentSetup.remove(provider) }
                        case .needsSetup, .repairRequired:
                            Button(snapshot.state == .repairRequired ? "Repair…" : "Configure…") {
                                agentSetup.prepare(provider)
                            }
                        case .helperUnavailable, .blocked:
                            Button("Configure…") { agentSetup.prepare(provider) }
                                .disabled(true)
                        }

                        if snapshot.backupAvailable {
                            Button("Rollback") { agentSetup.rollback(provider) }
                        }
                    }
                }
                .disabled(agentSetup.isWorking)
            }
        }
    }

    private func agentOperationalStatusColor(_ state: AgentIntegrationOperationalState) -> Color {
        switch state {
        case .active: .green
        case .awaitingFirstEvent, .stale, .repairRequired: .orange
        case .degraded, .failed, .unavailable, .blocked: .red
        case .notConfigured, .stopped: .secondary
        }
    }

    private func agentOperationalStatusSymbol(_ state: AgentIntegrationOperationalState) -> String {
        switch state {
        case .active: "checkmark.circle.fill"
        case .awaitingFirstEvent: "clock.badge.exclamationmark"
        case .stale: "clock.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .stopped: "stop.circle.fill"
        case .repairRequired: "wrench.and.screwdriver.fill"
        case .unavailable, .blocked: "exclamationmark.circle.fill"
        case .notConfigured: "circle.dashed"
        }
    }

    private var statsSection: some View {
        settingsForm("Stats") {
            SettingsGroup("Stats") {
                Toggle("Enable stats", isOn: $settings.statsEnabled)
                SliderRow(title: "Refresh interval", value: $settings.statsRefreshIntervalSeconds, range: 0.5...10.0, format: "%.1fs")
                Toggle("Show live indicator", isOn: $settings.showActivityIndicator)
            }

            SettingsGroup("Visible Cards") {
                Toggle("CPU", isOn: $settings.showCPU)
                Toggle("Memory", isOn: $settings.showMemory)
                Toggle("GPU", isOn: $settings.showGPU)
                Toggle("Network", isOn: $settings.showNetwork)
                Toggle("Disk", isOn: $settings.showDisk)
                Toggle("Battery", isOn: $settings.showBattery)
                Toggle("Uptime", isOn: $settings.showUptime)
            }

            SettingsGroup("Activities") {
                Toggle("Animate stats charts", isOn: $settings.animateStatsCharts)
                    .disabled(true)
                Toggle("Pause stats during shell morph", isOn: $settings.pauseStatsDuringShellMorph)
                    .disabled(true)
                Toggle("Enable activities", isOn: $settings.activitiesEnabled)
                    .disabled(true)
                SliderRow(title: "Activities refresh", value: $settings.activitiesRefreshIntervalSeconds, range: 0.5...30.0, format: "%.1fs", disabled: true)
                Toggle("Running apps", isOn: $settings.showRunningAppsActivity)
                    .disabled(true)
                Toggle("Downloads", isOn: $settings.showDownloadsActivity)
                    .disabled(true)
                Toggle("Calendar", isOn: $settings.showCalendarActivity)
                    .disabled(true)
                Toggle("Now Playing", isOn: $settings.showNowPlayingActivity)
                    .disabled(true)
                HelpText("Only the existing Stats tab is live in this phase. Activities fields are future-facing.")
            }
        }
    }

    private var liveActivitiesSection: some View {
        settingsForm("Live Activities") {
            SettingsGroup("Expanded Island") {
                Toggle(
                    "Show Live Activities section",
                    isOn: $settings.showExpandedLiveActivitiesSection
                )
                .disabled(!settings.liveActivitiesEnabled)
                HelpText(
                    "Hides only the Live Activities section on the expanded Island page. " +
                    "Collapsed Live Activities and their priority selection remain active."
                )
            }
            SettingsGroup("Sources") {
                Toggle("Enable live activities", isOn: $settings.liveActivitiesEnabled)
                Picker("Style", selection: $settings.liveActivityStyle) {
                    ForEach(LiveActivityStyle.allCases) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .disabled(true)
                Toggle("Music live activity", isOn: $settings.showMusicLiveActivity)
                Toggle("Timer live activity", isOn: $settings.showTimerLiveActivity)
                Toggle("File drop live activity", isOn: $settings.showFileDropLiveActivity)
                Toggle("Battery live activity", isOn: $settings.showBatteryLiveActivity)
                Toggle("Calendar live activity", isOn: $settings.showCalendarLiveActivity)
                    .disabled(true)
                Toggle("Downloads live activity", isOn: $settings.showDownloadsLiveActivity)
                    .disabled(true)
                Toggle("Auto dismiss", isOn: $settings.liveActivityAutoDismissEnabled)
                    .disabled(true)
                SliderRow(title: "Dismiss delay", value: $settings.liveActivityAutoDismissSeconds, range: 1...60, format: "%.0fs", disabled: true)
                Toggle("Animation", isOn: $settings.liveActivityAnimationEnabled)
                    .disabled(true)
                HelpText("Music, Timer, File Tray, and Battery activities appear in the Island tab. Calendar, Downloads, and auto-dismiss controls are reserved for later phases.")
            }
            SettingsGroup("System HUDs") {
                Toggle("Enable system HUDs", isOn: $settings.systemHUDsEnabled)
                Toggle(
                    "Replace macOS volume / brightness HUD",
                    isOn: $settings.replaceMacOSSystemHUDs
                )
                .disabled(!settings.systemHUDsEnabled)

                if settings.replaceMacOSSystemHUDs {
                    HStack(spacing: 8) {
                        Label(
                            systemHUDAccessibilityGranted
                                ? "Accessibility granted"
                                : "Accessibility required",
                            systemImage: systemHUDAccessibilityGranted
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(systemHUDAccessibilityGranted ? .green : .orange)

                        Spacer(minLength: 0)

                        if !systemHUDAccessibilityGranted {
                            Button("Grant Access") {
                                _ = SystemHUDAccessibilityPermission.request()
                                systemHUDAccessibilityGranted = SystemHUDAccessibilityPermission.isGranted
                            }
                            .buttonStyle(.borderless)
                        }

                        Button("Open Settings") {
                            SystemHUDAccessibilityPermission.openSettings()
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Toggle("Volume", isOn: $settings.volumeHUDEnabled)
                    .disabled(!settings.systemHUDsEnabled)
                Toggle("Brightness", isOn: $settings.brightnessHUDEnabled)
                    .disabled(!settings.systemHUDsEnabled)
                Toggle("Caps Lock", isOn: $settings.capsLockHUDEnabled)
                    .disabled(!settings.systemHUDsEnabled)
                Toggle("Battery status", isOn: $settings.batteryStatusHUDEnabled)
                    .disabled(!settings.systemHUDsEnabled)
                Toggle("Low / critical battery", isOn: $settings.lowBatteryHUDEnabled)
                    .disabled(!settings.systemHUDsEnabled)
                Toggle("Audio output device", isOn: $settings.audioDeviceHUDEnabled)
                    .disabled(!settings.systemHUDsEnabled)
                Toggle("Focus status", isOn: $settings.focusHUDEnabled)
                    .disabled(!settings.systemHUDsEnabled)
                HelpText(
                    "Focus status uses Apple's Focus Status API and may request permission the first time it is enabled. " +
                    "DynamicIsland shows only generic On / Off state because the public API does not expose the active Focus name."
                )
                SliderRow(
                    title: "Display duration",
                    value: $settings.systemHUDDurationSeconds,
                    range: 0.5...3.0,
                    format: "%.1fs",
                    disabled: !settings.systemHUDsEnabled
                )
                SystemHUDSettingsPreview(settings: settings)
                    .opacity(settings.systemHUDsEnabled ? 1 : 0.45)
                HelpText(
                    settings.replaceMacOSSystemHUDs
                        ? "With Accessibility granted, DynamicIsland changes volume / brightness itself and suppresses the native macOS HUD only after the change succeeds. Unsupported devices fall through to macOS."
                        : "Passive mode leaves macOS controls untouched and mirrors trustworthy volume / brightness values in DynamicIsland."
                )
            }

            SettingsGroup("Multi-Activity Layout") {
                Toggle(
                    "Allow simultaneous sidecars",
                    isOn: $settings.allowSimultaneousLiveActivitySidecars
                )
                Picker("Timer side", selection: $settings.timerSidecarPreference) {
                    ForEach(LiveActivitySidePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                LiveActivityLayoutSettingsPreview(settings: settings)
                HelpText(
                    "Automatic placement keeps the strongest activity in the center and moves compatible compact activities into leading or trailing sidecars. Transient HUDs overlay the composition without destroying it."
                )
            }

            SettingsGroup("Collapsed Live Activity Priority") {
                PriorityStepperRow(
                    title: CollapsedLiveActivityPrioritySource.runningTimer.displayName,
                    value: $settings.collapsedPriorityRunningTimer
                )
                PriorityStepperRow(
                    title: CollapsedLiveActivityPrioritySource.playingMedia.displayName,
                    value: $settings.collapsedPriorityPlayingMedia
                )
                PriorityStepperRow(
                    title: CollapsedLiveActivityPrioritySource.pausedTimer.displayName,
                    value: $settings.collapsedPriorityPausedTimer
                )
                PriorityStepperRow(
                    title: CollapsedLiveActivityPrioritySource.recentFiles.displayName,
                    value: $settings.collapsedPriorityRecentFiles
                )
                PriorityStepperRow(
                    title: CollapsedLiveActivityPrioritySource.pausedMedia.displayName,
                    value: $settings.collapsedPriorityPausedMedia
                )
                Button("Restore Defaults") {
                    settings.resetCollapsedLiveActivityPrioritySettings()
                }
                .buttonStyle(.borderless)
                HelpText("Higher priority appears first in the collapsed island. If two activities have the same priority, DynamicIsland uses the default order.")
            }
        }
    }

    private var clipboardSection: some View {
        settingsForm("Clipboard") {
            SettingsGroup("Clipboard History") {
                Toggle("Enable clipboard history", isOn: $settings.clipboardHistoryEnabled)
                Stepper(
                    "Maximum items: \(settings.clipboardHistoryMaximumItems)",
                    value: $settings.clipboardHistoryMaximumItems,
                    in: 10...200
                )
                .disabled(!settings.clipboardHistoryEnabled)
                Toggle("Capture images", isOn: $settings.clipboardHistoryCaptureImagesEnabled)
                    .disabled(!settings.clipboardHistoryEnabled)
                Toggle(
                    "Persist history across launches",
                    isOn: $settings.clipboardHistoryPersistenceEnabled
                )
                .disabled(!settings.clipboardHistoryEnabled)
                HelpText(
                    "Clipboard monitoring is off by default. DynamicIsland records only " +
                    "changes copied after Clipboard History is enabled."
                )
            }

            SettingsGroup("Privacy") {
                HelpText(
                    "Monitoring stays on this Mac and persistence is optional. " +
                    "Clipboard items marked concealed, transient, or autogenerated are skipped. " +
                    "History content is never sent anywhere."
                )
            }
        }
    }

    private var gesturesSection: some View {
        settingsForm("Gestures") {
            SettingsGroup("Pointer / Trackpad") {
                Toggle("Enable gestures", isOn: $settings.gesturesEnabled)
                Picker("Input source", selection: $settings.gestureInputSource) {
                    ForEach(GestureInputSource.allCases) { source in
                        Text(source.displayName).tag(source)
                            .disabled(source == .camera)
                    }
                }
                .disabled(!settings.gesturesEnabled)
                Toggle("Expand gesture", isOn: $settings.expandGestureEnabled)
                    .disabled(!settings.gesturesEnabled || settings.gestureInputSource != .trackpad)
                Toggle("Collapse gesture", isOn: $settings.collapseGestureEnabled)
                    .disabled(!settings.gesturesEnabled || settings.gestureInputSource != .trackpad)
                Toggle("Next tab gesture", isOn: $settings.nextTabGestureEnabled)
                    .disabled(!settings.gesturesEnabled || settings.gestureInputSource != .trackpad)
                Toggle("Previous tab gesture", isOn: $settings.previousTabGestureEnabled)
                    .disabled(!settings.gesturesEnabled || settings.gestureInputSource != .trackpad)
                Toggle("Media play/pause gesture", isOn: $settings.mediaPlayPauseGestureEnabled)
                    .disabled(!settings.gesturesEnabled || settings.gestureInputSource != .trackpad)
                Toggle("Timer start/stop gesture", isOn: $settings.timerStartStopGestureEnabled)
                    .disabled(!settings.gesturesEnabled || settings.gestureInputSource != .trackpad)
                SliderRow(
                    title: "Sensitivity",
                    value: $settings.gestureSensitivity,
                    range: 0...1,
                    format: "%.2f",
                    disabled: !settings.gesturesEnabled || settings.gestureInputSource != .trackpad
                )
                SliderRow(
                    title: "Cooldown",
                    value: $settings.gestureCooldownSeconds,
                    range: 0.1...10.0,
                    format: "%.2fs",
                    disabled: !settings.gesturesEnabled
                )
                Toggle("Show gesture hints", isOn: $settings.showGestureHints)
                    .disabled(!settings.gesturesEnabled)
                Toggle("Require confirmation", isOn: $settings.requireGestureConfirmation)
                    .disabled(!settings.gesturesEnabled)
                HelpText("Pointer gestures use the mappings below. Camera gestures remain unavailable.")
            }

            SettingsGroup("Collapsed Media Pill Gestures") {
                gestureActionPicker("Double Click", selection: $settings.collapsedDoubleClickAction, actions: collapsedMediaPillActions)
                gestureActionPicker("Two-Finger Swipe Left", selection: $settings.collapsedSwipeLeftAction, actions: collapsedMediaPillActions)
                gestureActionPicker("Two-Finger Swipe Right", selection: $settings.collapsedSwipeRightAction, actions: collapsedMediaPillActions)
                gestureActionPicker("Two-Finger Swipe Down", selection: $settings.collapsedSwipeDownAction, actions: collapsedMediaPillActions)
                gestureActionPicker("Two-Finger Swipe Up", selection: $settings.collapsedSwipeUpAction, actions: collapsedMediaPillActions)
                gestureActionPicker("Long Press", selection: $settings.collapsedLongPressAction, actions: collapsedMediaPillActions)
            }

            SettingsGroup("Expanded Island Gestures") {
                gestureActionPicker("Double Click", selection: $settings.expandedDoubleClickAction)
                gestureActionPicker("Swipe Down", selection: $settings.expandedSwipeDownAction)
                gestureActionPicker("Swipe Up", selection: $settings.expandedSwipeUpAction)
                gestureActionPicker("Swipe Left", selection: $settings.expandedSwipeLeftAction)
                gestureActionPicker("Swipe Right", selection: $settings.expandedSwipeRightAction)
                gestureActionPicker("Long Press", selection: $settings.expandedLongPressAction)
            }

            SettingsGroup("Coming Soon") {
                Text("Camera gestures")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                Toggle("Privacy mode", isOn: $settings.gesturePrivacyMode)
                    .disabled(true)
                HelpText("Camera-based gestures are not implemented. No camera permission, capture session, or hand recognition is used.")
            }
        }
    }

    private func gestureActionPicker(
        _ title: String,
        selection: Binding<IslandGestureAction>,
        actions: [IslandGestureAction] = IslandGestureAction.allCases
    ) -> some View {
        let displayedActions = actions.contains(selection.wrappedValue)
            ? actions
            : [selection.wrappedValue] + actions

        return Picker(title, selection: selection) {
            ForEach(displayedActions) { action in
                Text(action.displayName).tag(action)
            }
        }
        .disabled(!settings.gesturesEnabled || settings.gestureInputSource != .trackpad)
    }

    private var collapsedMediaPillActions: [IslandGestureAction] {
        [.none, .expand, .mediaNextTrack, .mediaPreviousTrack, .mediaPlayPause, .openSettings]
    }

    private var advancedSection: some View {
        settingsForm("Advanced") {
            SettingsGroup("Debug") {
                Toggle("Verbose UI logs", isOn: $settings.verboseUILogsEnabled)
                    .disabled(true)
                Toggle("Show debug frames", isOn: $settings.showDebugFrames)
                    .disabled(true)
                Toggle("Show hit-test region debug", isOn: $settings.showHitTestRegionDebug)
                    .disabled(true)
                Toggle("Disable visualizer during morph", isOn: $settings.disableVisualizerDuringMorph)
                    .disabled(true)
                Toggle("Disable thumbnails during morph", isOn: $settings.disableThumbnailsDuringMorph)
                HelpText("Verbose logging and debug overlays remain launch/debug-only in this phase.")
            }

            SettingsGroup("Reset") {
                HStack(spacing: 10) {
                    Button("Reset All Settings") {
                        settings.resetAllSettings()
                    }
                    Button("Reset Layout") {
                        settings.resetLayoutSettings()
                    }
                    Button("Reset Modules") {
                        settings.resetModuleSettings()
                    }
                }
            }
        }
    }

    private func settingsForm<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            content()
        }
    }
}

struct AgentSourceHealthRow: View {
    let provider: AgentIntegrationProvider
    let diagnostics: AgentIntegrationDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if diagnostics.state == .awaitingFirstEvent {
                Label(awaitingGuidance, systemImage: "info.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if diagnostics.acceptedCount > 0 || diagnostics.rejectedCount > 0 || diagnostics.droppedCount > 0 {
                HStack(spacing: 16) {
                    healthMetric("Accepted", value: diagnostics.acceptedCount)
                    healthMetric("Rejected", value: diagnostics.rejectedCount)
                    healthMetric("Dropped", value: diagnostics.droppedCount)
                    Spacer(minLength: 0)
                    if let lastAccepted = diagnostics.lastAcceptedEventAt {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("LAST EVENT")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(lastAccepted, style: .relative)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Last accepted event \(lastAccepted.formatted())")
                    }
                }
                .padding(.vertical, 5)
                .overlay(alignment: .top) {
                    Divider().opacity(0.35)
                }
            }

            if diagnostics.schemaMismatchCount > 0 {
                Label(
                    "Schema mismatch detected (\(diagnostics.schemaMismatchCount.formatted()))",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
            }

            if let error = diagnostics.lastError {
                Label("Last safe error: \(safeErrorLabel(error))", systemImage: "exclamationmark.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var awaitingGuidance: String {
        switch provider {
        case .codex:
            "Configuration is installed, but no Codex event has been accepted yet. Start a new session and review the installed hooks with /hooks."
        case .claude:
            "Configuration is installed, but no Claude event has been accepted yet. Restart Claude or start a new session."
        }
    }

    private func healthMetric(_ label: String, value: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func safeErrorLabel(_ error: AgentSourceHealthError) -> String {
        switch error {
        case .policyRejected: "Policy rejected"
        case .schemaMismatch: "Schema mismatch"
        case .invalidEvent: "Invalid event"
        case .staleProducer: "Stale producer"
        case .identityConflict: "Identity conflict"
        case .storeRejected: "Event store rejected"
        case .producerFailure: "Producer failure"
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .disabled(disabled)
        }
    }
}

private struct PriorityStepperRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        Stepper(value: $value, in: CollapsedLiveActivityPrioritySettings.range, step: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

struct HelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ShortcutEditorRow: View {
    @State var shortcut: LauncherShortcut
    let onUpdate: (LauncherShortcut) -> Void
    let onRemove: (LauncherShortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: binding(\.title))
                TextField("SF Symbol", text: binding(\.symbolName))
                    .frame(width: 120)
                Button {
                    onRemove(shortcut)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove shortcut")
            }
            TextField("Path or URL", text: binding(\.target))
        }
    }

    private func binding(_ keyPath: WritableKeyPath<LauncherShortcut, String>) -> Binding<String> {
        Binding {
            shortcut[keyPath: keyPath]
        } set: { newValue in
            shortcut[keyPath: keyPath] = newValue
            onUpdate(shortcut)
        }
    }
}


private enum SystemHUDPreviewCase: String, CaseIterable, Identifiable {
    case volume = "Volume"
    case brightness = "Brightness"
    case capsOn = "Caps Lock On"
    case capsOff = "Caps Lock Off"
    case charging = "Charging"
    case lowBattery = "Low Battery"
    case criticalBattery = "Critical Battery"
    case airPods = "AirPods Pro"
    case headphones = "Headphones"
    case focus = "Focus"

    var id: String { rawValue }
}

private struct SystemHUDSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    @State private var previewValue = 0.68
    @State private var previewCase: SystemHUDPreviewCase = .volume

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Live Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Preview", selection: $previewCase) {
                    ForEach(SystemHUDPreviewCase.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 145)
            }

            CollapsedSystemHUDCompactView(
                activity: previewActivity,
                layout: CompactCollapsedSideSlotGeometry(
                    isNotchIntegrated: false,
                    leftRegionWidth: 0,
                    notchCoreWidth: 0,
                    rightRegionWidth: 0
                )
            )
            .frame(width: 190, height: 32)
            .padding(.horizontal, 14)
            .background(Color.black, in: Capsule(style: .continuous))

            if previewActivity.progress != nil {
                Slider(value: $previewValue, in: 0...1)
                    .frame(maxWidth: 220)
            }
        }
        .padding(.vertical, 4)
        .allowsHitTesting(settings.systemHUDsEnabled)
    }

    private var previewActivity: DynamicIslandLiveActivity {
        let descriptor: SystemHUDDescriptor
        switch previewCase {
        case .volume:
            descriptor = SystemHUDDescriptor(
                kind: .volume,
                title: "Volume",
                subtitle: "\(Int(previewValue * 100))%",
                symbolName: "speaker.wave.2.fill",
                progress: previewValue,
                priority: 120
            )
        case .brightness:
            descriptor = SystemHUDDescriptor(
                kind: .brightness,
                title: "Brightness",
                subtitle: "\(Int(previewValue * 100))%",
                symbolName: "sun.max.fill",
                progress: previewValue,
                priority: 120
            )
        case .capsOn:
            descriptor = SystemHUDDescriptor(
                kind: .capsLock, title: "Caps Lock On", subtitle: "ABC",
                symbolName: "capslock.fill", priority: 130
            )
        case .capsOff:
            descriptor = SystemHUDDescriptor(
                kind: .capsLock, title: "Caps Lock Off", subtitle: "abc",
                symbolName: "capslock", priority: 130
            )
        case .charging:
            descriptor = SystemHUDDescriptor(
                kind: .battery, title: "Charging", subtitle: "\(Int(previewValue * 100))%",
                symbolName: "battery.100percent.bolt", progress: previewValue, priority: 155
            )
        case .lowBattery:
            descriptor = SystemHUDDescriptor(
                kind: .battery, title: "Low Battery", subtitle: "15%",
                symbolName: "battery.25percent", progress: 0.15, priority: 180
            )
        case .criticalBattery:
            descriptor = SystemHUDDescriptor(
                kind: .battery, title: "Critical Battery", subtitle: "8%",
                symbolName: "exclamationmark.triangle.fill", progress: 0.08, priority: 190
            )
        case .airPods:
            descriptor = SystemHUDDescriptor(
                kind: .audioDevice, title: "AirPods Pro", subtitle: "Output Changed",
                symbolName: "airpodspro", priority: 165
            )
        case .headphones:
            descriptor = SystemHUDDescriptor(
                kind: .audioDevice, title: "Headphones", subtitle: "Output Changed",
                symbolName: "headphones", priority: 165
            )
        case .focus:
            descriptor = SystemHUDDescriptor(
                kind: .focus, title: "Focus", subtitle: "On",
                symbolName: "moon.fill", priority: 140
            )
        }

        return DynamicIslandLiveActivity(
            id: "settings-system-hud",
            kind: .system,
            title: descriptor.title,
            subtitle: descriptor.subtitle,
            symbolName: descriptor.symbolName,
            priority: 200,
            isActive: true,
            progress: descriptor.progress,
            updatedAt: Date()
        )
    }
}


private struct LiveActivityLayoutSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    @State private var scenario: LiveActivityLayoutPreviewScenario = .mediaTimer

    private let canvasSize = CGSize(width: 320, height: 68)
    private let primaryFrame = CGRect(x: 52, y: 19, width: 216, height: 34)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Layout Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Scenario", selection: $scenario) {
                    ForEach(LiveActivityLayoutPreviewScenario.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 215)
            }

            ZStack(alignment: .topLeading) {
                Color.clear

                previewPrimary
                    .frame(width: primaryFrame.width, height: primaryFrame.height)
                    .position(
                        x: primaryFrame.midX,
                        y: canvasSize.height - primaryFrame.midY
                    )

                LiveActivitySidecarLayer(
                    resolution: resolution,
                    compositeGeometry: compositeGeometry,
                    canvasHeight: canvasSize.height,
                    reduceMotion: true,
                    onActivate: { _ in }
                )

                if let overlay = resolution.overlayTransient?.activity {
                    CollapsedSystemHUDCompactView(
                        activity: overlay,
                        layout: CompactCollapsedSideSlotGeometry(
                            isNotchIntegrated: false,
                            leftRegionWidth: 0,
                            notchCoreWidth: 0,
                            rightRegionWidth: 0
                        )
                    )
                    .padding(.horizontal, 14)
                    .frame(width: primaryFrame.width, height: primaryFrame.height)
                    .background(Color.black.opacity(0.985), in: Capsule())
                    .position(
                        x: primaryFrame.midX,
                        y: canvasSize.height - primaryFrame.midY
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private var previewPrimary: some View {
        HStack(spacing: 7) {
            if resolution.primary?.activity.kind == .media {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.17))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
            } else if let primary = resolution.primary?.activity {
                Image(systemName: primary.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 22)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(resolution.primary?.activity.title ?? "DynamicIsland")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if let subtitle = resolution.primary?.activity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if resolution.primary?.activity.kind == .media {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(0.62))
                            .frame(width: 2, height: CGFloat(5 + (index % 3) * 3))
                    }
                }
                .frame(width: 22, height: 15)
            }
        }
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.985), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var resolution: LiveActivityLayoutResolution {
        LiveActivityLayoutResolver.resolve(
            activities: activities,
            context: LiveActivityLayoutContext(
                availableWidth: scenario == .constrained ? 240 : canvasSize.width,
                hasHardwareNotch: false,
                hardwareNotchWidth: 0,
                primaryMinimumWidth: 172,
                primaryIdealWidth: primaryFrame.width,
                sidecarDiameter: LiveActivitySidecarMetrics.diameter,
                sidecarGap: LiveActivitySidecarMetrics.gap,
                allowSimultaneousSidecars: settings.allowSimultaneousLiveActivitySidecars,
                timerSidePreference: settings.timerSidecarPreference
            )
        )
    }

    private var compositeGeometry: LiveActivityCompositeGeometry {
        LiveActivityCompositeGeometry.resolve(
            primaryFrame: primaryFrame,
            canvasSize: canvasSize,
            resolution: resolution,
            sidecarDiameter: LiveActivitySidecarMetrics.diameter,
            sidecarGap: LiveActivitySidecarMetrics.gap
        )
    }

    private var activities: [DynamicIslandLiveActivity] {
        LiveActivityPreviewCatalog.activities(for: scenario)
    }
}
