import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case island = "Island"
    case appearance = "Appearance"
    case motion = "Motion"
    case tabs = "Navigation"
    case media = "Media"
    case tray = "Tray"
    case basket = "Basket"
    case timer = "Timer"
    case stats = "Stats"
    case agents = "AI Agents"
    case clipboard = "Clipboard"
    case productivity = "Productivity"
    case rightWorkspace = "Right Workspace"
    case messaging = "Messaging"
    case liveActivities = "Live Activities"
    case gestures = "Gesture Shortcuts"
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
        case .basket: "basket"
        case .timer: "timer"
        case .stats: "chart.xyaxis.line"
        case .agents: "cpu"
        case .clipboard: "doc.on.clipboard"
        case .productivity: "wand.and.stars"
        case .rightWorkspace: "rectangle.split.3x1"
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
    let previews: SettingsPreviewDependencies?
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
        messaging: MessagingController? = nil,
        previews: SettingsPreviewDependencies? = nil
    ) {
        self.messaging = messaging
        self.previews = previews
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
                    case .basket:
                        basketSection
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
                            if let previews {
                                ProductivityDeckSettingsPreview(
                                    workspace: previews.rightWorkspace,
                                    productivity: productivity,
                                    shelf: previews.previewShelf
                                )
                            }
                            ProductivitySettingsView(productivity: productivity)
                        }
                    case .rightWorkspace:
                        settingsForm("Right Workspace") {
                            if let previews {
                                RightWorkspaceSettingsView(
                                    settings: settings,
                                    workspace: previews.rightWorkspace,
                                    dependencies: previews
                                )
                            } else {
                                HelpText("Right workspace settings are unavailable.")
                            }
                        }
                    case .messaging:
                        settingsForm("Messaging") {
                            if let messaging {
                                MessagingSettingsView(controller: messaging)
                                Button("Restore Messaging Defaults") {
                                    messaging.preferences = .init()
                                }
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
            IslandShellSettingsPreview(settings: settings, dependencies: previews)
            SettingsGroup("General") {
                Toggle("Enable overlay", isOn: $settings.overlayEnabled)
                Toggle("Launch at login", isOn: $settings.launchAtLoginEnabled)
                Toggle("Expand on click", isOn: $settings.expandOnClick)
                Toggle("Collapse on mouse leave", isOn: $settings.collapseOnMouseLeave)
                Toggle("Auto collapse", isOn: $settings.autoCollapseEnabled)
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
                    disabled: !settings.autoCollapseEnabled || settings.autoCollapseDelayPreset != .manual
                )
            }
            .disabled(!settings.autoCollapseEnabled)

            DisclosureGroup("Advanced sizing") {
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
    }

    private var appearanceSection: some View {
        settingsForm("Appearance") {
            IslandShellSettingsPreview(settings: settings, dependencies: previews)
            if let previews {
                CollapsedMediaSettingsPreview(settings: settings, media: previews.previewMedia)
                CollapsedHoverSettingsPreview(settings: settings, media: previews.previewMedia)
            }
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
            IslandShellSettingsPreview(settings: settings, dependencies: previews)
            ContentMotionSettingsPreview(settings: settings)
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
                    .disabled(!settings.contentAnimationEnabled)
                SliderRow(title: "Stagger amount", value: $settings.contentStaggerAmount, range: 0...2.0, format: "%.2f", disabled: !settings.contentAnimationEnabled || !settings.contentStaggerEnabled)
                Toggle("Blur transitions", isOn: $settings.useBlurTransitions)
                    .disabled(!settings.contentAnimationEnabled)
                Toggle("Scale transitions", isOn: $settings.useScaleTransitions)
                    .disabled(!settings.contentAnimationEnabled)
                HelpText("Expansion still avoids fade-in. Opacity is only available to the staged removal path.")
            }
        }
    }

    private var tabsSection: some View {
        settingsForm("Navigation") {
            SettingsGroup("Navigation") {
                Picker("Navigation mode", selection: $settings.showNavigationControls) {
                    Text("Visible Controls").tag(true)
                    Text("Gesture Only").tag(false)
                }
                .pickerStyle(.segmented)
                HelpText(settings.showNavigationControls
                    ? "Page controls and workspace commands appear in the island header."
                    : "Swipe with three fingers to change pages. Secondary-click the island background for workspace commands. Settings remains available in the menu bar.")
            }
            IslandShellSettingsPreview(settings: settings, dependencies: previews)
            SettingsGroup("Pages") {
                Toggle("Island", isOn: .constant(true))
                    .disabled(true)
                Toggle("Agents", isOn: $settings.showAgentsTab).disabled(!settings.agentActivityEnabled)
                Toggle("Tray", isOn: $settings.showTrayTab).disabled(!settings.trayEnabled)
                Toggle("Timer", isOn: $settings.showTimerTab).disabled(!settings.timerEnabled)
                Toggle("Stats", isOn: $settings.showStatsTab).disabled(!settings.statsEnabled)
                Toggle("Tools", isOn: $settings.showToolsTab)
                HelpText("Enable each feature in its category before showing its page. Workspace customization also controls page order and visibility.")
            }
            pointerShortcutSettings
            DisclosureGroup("Advanced") {
              SettingsGroup("Page selection") {
                Toggle("Swipe between pages with three fingers", isOn: $settings.threeFingerTabNavigationEnabled)
                HelpText("Turning off three-finger navigation restores visible controls.")
                Toggle("Remember last page", isOn: $settings.rememberLastSelectedTab)
                Picker("Starting page", selection: $settings.defaultExpandedTab) {
                    ForEach([DefaultExpandedTab.island, .tray, .timer, .stats]) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                    if ![DefaultExpandedTab.island, .tray, .timer, .stats].contains(settings.defaultExpandedTab) {
                        Text("Island (legacy selection)").tag(settings.defaultExpandedTab)
                    }
                }
                .disabled(settings.rememberLastSelectedTab)
              }
            }
        }
    }

    private var mediaSection: some View {
        settingsForm("Media") {
            if let previews {
                MediaSettingsPreview(settings: settings, media: previews.previewMedia, customization: previews.customization)
                MediaLauncherSettingsPreview(settings: settings, media: previews.previewMedia)
            }
            SettingsGroup("Visibility") {
                Toggle("Enable media", isOn: $settings.mediaEnabled)
                Toggle("Show when paused", isOn: $settings.showMediaWhenPaused)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show launcher when no source", isOn: $settings.showMediaWhenNoSource)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show album artwork", isOn: $settings.showAlbumArtwork)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show title", isOn: $settings.showMediaTitle)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show artist", isOn: $settings.showMediaArtist)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show source name", isOn: $settings.showMediaSourceName)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show visualizer", isOn: $settings.showVisualizer)
                    .disabled(!settings.mediaEnabled)
            }

            SettingsGroup("Controls") {
                Toggle("Show playback controls", isOn: $settings.showPlaybackControls)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show progress slider", isOn: $settings.showProgressSlider)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show volume slider", isOn: $settings.showVolumeSlider)
                    .disabled(!settings.mediaEnabled)
                Toggle("Open source on artwork click", isOn: $settings.openSourceOnArtworkClick)
                    .disabled(!settings.mediaEnabled)
                Toggle("Collapse after opening source", isOn: $settings.collapseAfterOpeningMediaSource)
                    .disabled(!settings.mediaEnabled || !settings.openSourceOnArtworkClick)
                Toggle("Collapse after launcher", isOn: $settings.collapseAfterMediaLauncher)
                    .disabled(!settings.mediaEnabled || !settings.mediaLauncherEnabled)
            }
            .disabled(!settings.mediaEnabled)

            SettingsGroup("Launchers") {
                Toggle("Enable launchers", isOn: $settings.mediaLauncherEnabled)
                    .disabled(!settings.mediaEnabled)
                Toggle("Show Apple Music launcher", isOn: $settings.showAppleMusicLauncher)
                    .disabled(!settings.mediaEnabled || !settings.mediaLauncherEnabled)
                Toggle("Show Spotify launcher", isOn: $settings.showSpotifyLauncher)
                    .disabled(!settings.mediaEnabled || !settings.mediaLauncherEnabled)
                Toggle("Show YouTube launcher", isOn: $settings.showYouTubeLauncher)
                    .disabled(!settings.mediaEnabled || !settings.mediaLauncherEnabled)
            }
            .disabled(!settings.mediaEnabled)

        }
    }

    private var basketSection: some View {
        settingsForm("Basket") {
            FloatingBasketSettingsPreview(settings: settings)
            SettingsGroup("Floating Basket") {
                Toggle("Enable Floating Basket", isOn: $settings.floatingBasketEnabled)
                HelpText("Shake while dragging files to summon a Basket near the pointer. Works without Accessibility.")
                Stepper("Shake sensitivity: \(settings.basketJiggleSensitivity)", value: $settings.basketJiggleSensitivity, in: 1...5)
                    .disabled(!settings.floatingBasketEnabled)
                HelpText("Higher sensitivity needs fewer direction changes within half a second.")
                Toggle("Allow multiple Baskets", isOn: $settings.basketMultipleEnabled)
                    .disabled(!settings.floatingBasketEnabled)
                HelpText("Shake again with one Basket open to add another; with two or more, shaking shows the Basket switcher. Turning this off merges Baskets.")
            }
            SettingsGroup("Auto-hide") {
                Toggle("Hide idle Baskets", isOn: $settings.basketAutoHideEnabled)
                    .disabled(!settings.floatingBasketEnabled)
                Stepper(
                    "Hide after \(settings.basketAutoHideDelay.formatted(.number.precision(.fractionLength(1)))) s",
                    value: $settings.basketAutoHideDelay, in: 0.5...10, step: 0.5
                )
                .disabled(!settings.floatingBasketEnabled || !settings.basketAutoHideEnabled)
                HelpText("Hidden Baskets keep their files. Shake during a drag or use the menu bar's Show Hidden Basket to bring them back. Empty Baskets close when a drag ends without a drop.")
            }
        }
    }

    private var traySection: some View {
        settingsForm("Tray") {
            if let previews {
                FileTraySettingsPreview(
                    settings: settings,
                    shelf: previews.previewShelf,
                    backgroundRemoval: previews.previewBackgroundRemoval
                )
            }
            SettingsGroup("Tray") {
                Toggle("Enable tray", isOn: $settings.trayEnabled)
                Toggle("Enable file shelf", isOn: $settings.fileShelfEnabled)
                    .disabled(!settings.trayEnabled)
                Toggle("Enable AirDrop zone", isOn: $settings.airDropZoneEnabled)
                    .disabled(!settings.trayEnabled)
                Toggle("Allow collapsed file drops", isOn: $settings.allowFileDropsOnCollapsedIsland)
                    .disabled(!settings.trayEnabled)
                Toggle("Allow expanded tray drops", isOn: $settings.allowFileDropsOnExpandedTray)
                    .disabled(!settings.trayEnabled)
                Stepper("Max shelf files: \(settings.maxShelfFiles)", value: $settings.maxShelfFiles, in: 1...48)
                    .disabled(!settings.trayEnabled || !settings.fileShelfEnabled)
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
            .disabled(!settings.trayEnabled || !settings.fileShelfEnabled)

            SettingsGroup("Actions") {
                Toggle("Open file action", isOn: $settings.openFileActionEnabled)
                    .disabled(!settings.trayEnabled || !settings.fileShelfEnabled)
                Toggle("Reveal in Finder action", isOn: $settings.revealInFinderActionEnabled)
                    .disabled(!settings.trayEnabled || !settings.fileShelfEnabled)
                Toggle("Copy path actions", isOn: $settings.copyPathActionEnabled)
                    .disabled(!settings.trayEnabled || !settings.fileShelfEnabled)
                Toggle("Remove file action", isOn: $settings.removeFileActionEnabled)
                    .disabled(!settings.trayEnabled || !settings.fileShelfEnabled)
                Toggle("AirDrop fallback reveal in Finder", isOn: $settings.airDropFallbackRevealInFinder)
                    .disabled(!settings.trayEnabled || !settings.airDropZoneEnabled)
            }
        }
    }

    private var timerSection: some View {
        settingsForm("Timer") {
            if let previews {
                TimerPageSettingsPreview(settings: settings, timer: previews.timer, customization: previews.customization)
            }
            SettingsGroup("Timer") {
                Toggle("Enable timer", isOn: $settings.timerEnabled)
                Toggle("Preset buttons", isOn: $settings.timerPresetsEnabled)
                    .disabled(!settings.timerEnabled)
                Toggle("Show progress ring", isOn: $settings.showTimerProgressRing)
                    .disabled(!settings.timerEnabled)
                Toggle("Ring animation", isOn: $settings.timerRingAnimationEnabled)
                    .disabled(!settings.timerEnabled || !settings.showTimerProgressRing)
                Toggle("Collapse after starting timer", isOn: $settings.collapseAfterStartingTimer)
                    .disabled(!settings.timerEnabled)
            }

            SettingsGroup("Presets") {
                Stepper("Preset 1: \(settings.timerPreset1Minutes)m", value: $settings.timerPreset1Minutes, in: 1...180)
                Stepper("Preset 2: \(settings.timerPreset2Minutes)m", value: $settings.timerPreset2Minutes, in: 1...180)
                Stepper("Preset 3: \(settings.timerPreset3Minutes)m", value: $settings.timerPreset3Minutes, in: 1...180)
            }
            .disabled(!settings.timerEnabled || !settings.timerPresetsEnabled)

            SettingsGroup("Completion") {
                Toggle("Timer notification", isOn: $settings.timerNotificationEnabled)
                    .disabled(!settings.timerEnabled)
                Toggle("Timer sound", isOn: $settings.timerSoundEnabled)
                    .disabled(!settings.timerEnabled || !settings.timerNotificationEnabled)
                HelpText("Timer completion notifications use the native macOS alert and system sound.")
            }
            .disabled(!settings.timerEnabled)

        }
    }

    private var agentsSection: some View {
        settingsForm("AI Agents") {
            if let control = previews?.agentManagedControl {
                AgentsSettingsPreview(managedControl: control, settings: settings, dependencies: previews)
            }
            SettingsGroup("Agent Activity") {
                Toggle("Enable agent activity", isOn: $settings.agentActivityEnabled)
                Toggle("Show Agents tab", isOn: $settings.showAgentsTab)
                    .disabled(!settings.agentActivityEnabled)
                Toggle("Completion alerts", isOn: $settings.agentCompletionAlertsEnabled)
                    .disabled(!settings.agentActivityEnabled)
                HStack {
                    Toggle("Agent task completion sound", isOn: $settings.agentCompletionSoundEnabled)
                        .disabled(!settings.agentActivityEnabled || !settings.agentCompletionAlertsEnabled)
                    Spacer()
                    Button("Preview") { SystemNotificationSoundPlayer.play(.completionChime) }
                        .controlSize(.small)
                        .disabled(!settings.agentActivityEnabled)
                }
                .help("One subtle system chime (Glass) when an agent finishes a task. Uses the completion alert, so it follows Completion alerts.")
                Toggle("Input alerts", isOn: $settings.agentApprovalAlertsEnabled)
                    .disabled(!settings.agentActivityEnabled)
                Toggle("Usage metrics", isOn: $settings.agentUsageMetricsEnabled)
                    .disabled(!settings.agentActivityEnabled)
                Toggle("Record activities", isOn: $settings.agentActivityRecordingEnabled)
                    .disabled(!settings.agentActivityEnabled)
                    .help("Saves normalized agent activity (states, tools, approvals, usage) as local JSON Lines in Application Support/DynamicIsland/AgentActivity. Never prompts, transcripts, commands' arguments, paths or secrets. Kept 14 days, at most 20 MB.")
                SliderRow(
                    title: "Alert duration",
                    value: $settings.agentPeekDurationSeconds,
                    range: 1...10,
                    format: "%.1fs",
                    disabled: !settings.agentActivityEnabled
                )
                HelpText("Usage values are shown only when supported data is available.")
            }

            SettingsGroup("Appearance") {
                AgentAppearanceSettingsView(settings: settings)
                    .disabled(!settings.agentActivityEnabled)
                HelpText("Orb, avatar, voice-beam and send-button previews are local presentation state and never change a live agent session.")
            }

            if let agentManagedControl, let agentProjects {
              DisclosureGroup("Advanced diagnostics") {
                SettingsGroup("Provider & Project Diagnostics") {
                    AgentDiagnosticsView(
                        agentEvents: agentEvents,
                        managedControl: agentManagedControl,
                        projects: agentProjects
                    )
                }
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
            if let previews {
                StatsSettingsPreview(settings: settings, stats: previews.stats)
            }
            SettingsGroup("Stats") {
                Toggle("Enable stats", isOn: $settings.statsEnabled)
                SliderRow(title: "Refresh interval", value: $settings.statsRefreshIntervalSeconds, range: 0.5...10.0, format: "%.1fs", disabled: !settings.statsEnabled)
                Toggle("Show live indicator", isOn: $settings.showActivityIndicator)
                    .disabled(!settings.statsEnabled)
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
            .disabled(!settings.statsEnabled)

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
                Toggle("Music live activity", isOn: $settings.showMusicLiveActivity)
                    .disabled(!settings.liveActivitiesEnabled)
                Toggle("Timer live activity", isOn: $settings.showTimerLiveActivity)
                    .disabled(!settings.liveActivitiesEnabled)
                Toggle("File drop live activity", isOn: $settings.showFileDropLiveActivity)
                    .disabled(!settings.liveActivitiesEnabled)
                Toggle("Battery live activity", isOn: $settings.showBatteryLiveActivity)
                    .disabled(!settings.liveActivitiesEnabled)
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
                .disabled(!settings.liveActivitiesEnabled)
                Picker("Timer side", selection: $settings.timerSidecarPreference) {
                    ForEach(LiveActivitySidePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .disabled(!settings.liveActivitiesEnabled || !settings.allowSimultaneousLiveActivitySidecars)
                LiveActivityLayoutSettingsPreview(settings: settings, dependencies: previews)
                HelpText(
                    "Automatic placement keeps the strongest activity in the center and moves compatible compact activities into leading or trailing sidecars. Transient HUDs overlay the composition without destroying it."
                )
            }

            DisclosureGroup("Advanced activity priority") {
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
    }

    private var clipboardSection: some View {
        settingsForm("Clipboard") {
            if let previews {
                ClipboardSettingsPreview(store: previews.clipboardHistory)
            }
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
                Toggle("Auto-focus search when opened", isOn: $settings.clipboardHistoryAutoFocusSearch)
                    .disabled(!settings.clipboardHistoryEnabled)
                Toggle("Enable tags", isOn: $settings.clipboardHistoryTagsEnabled)
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
                ClipboardExcludedAppsPicker(settings: settings)
                    .disabled(!settings.clipboardHistoryEnabled)
                HelpText(
                    "Monitoring stays on this Mac and persistence is optional. " +
                    "Clipboard items marked concealed, transient, or autogenerated are skipped. " +
                    "Excluded applications are blocked before capture. History content is never sent anywhere."
                )
            }
        }
    }

    private var pointerShortcutSettings: some View {
        SettingsGroup("Gesture Shortcuts") {
                Toggle("Enable pointer shortcuts", isOn: $settings.gesturesEnabled)
                Picker("Input source", selection: $settings.gestureInputSource) {
                    ForEach(GestureInputSource.allCases) { source in
                        Text(source == .keyboardShortcut ? "Keyboard Shortcut (Unavailable)" : source.displayName).tag(source)
                            .disabled(source == .camera || source == .keyboardShortcut)
                    }
                }
                .disabled(!settings.gesturesEnabled)
                Text("Collapsed island").font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                gestureActionPicker("Double Click", selection: $settings.collapsedDoubleClickAction)
                gestureActionPicker("Long Press", selection: $settings.collapsedLongPressAction)
                Text("Expanded island").font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                gestureActionPicker("Double Click", selection: $settings.expandedDoubleClickAction)
                gestureActionPicker("Long Press", selection: $settings.expandedLongPressAction)
                Toggle("Require confirmation", isOn: $settings.requireGestureConfirmation)
                    .disabled(!settings.gesturesEnabled || settings.gestureInputSource != .trackpad)
                HelpText("Shortcuts act on the island background. Content controls keep their own clicks. Choose Pointer / Trackpad to use these mappings; camera and global keyboard input are unavailable.")
        }
    }

    private var gesturesSection: some View {
        settingsForm("Gesture Shortcuts") {
            pointerShortcutSettings
            DisclosureGroup("Advanced recognition") {
              SettingsGroup("Pointer / Trackpad") {
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
                HelpText("Pointer gestures use the mappings below. Camera gestures remain unavailable.")
              }
            }

            SettingsGroup("Collapsed Media Pill Gestures") {
                gestureActionPicker("Two-Finger Swipe Left", selection: $settings.collapsedSwipeLeftAction, actions: collapsedMediaPillActions)
                gestureActionPicker("Two-Finger Swipe Right", selection: $settings.collapsedSwipeRightAction, actions: collapsedMediaPillActions)
                gestureActionPicker("Two-Finger Swipe Down", selection: $settings.collapsedSwipeDownAction, actions: collapsedMediaPillActions)
                gestureActionPicker("Two-Finger Swipe Up", selection: $settings.collapsedSwipeUpAction, actions: collapsedMediaPillActions)
            }

            SettingsGroup("Expanded Island Gestures") {
                gestureActionPicker("Swipe Down", selection: $settings.expandedSwipeDownAction)
                gestureActionPicker("Swipe Up", selection: $settings.expandedSwipeUpAction)
                gestureActionPicker("Swipe Left", selection: $settings.expandedSwipeLeftAction)
                gestureActionPicker("Swipe Right", selection: $settings.expandedSwipeRightAction)
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
            DisclosureGroup("Renderer options") {
              SettingsGroup("Performance") {
                Toggle("Disable visualizer during morph", isOn: $settings.disableVisualizerDuringMorph)
                HelpText("Performance controls shown here are wired to the production renderer.")
              }
            }

            SettingsGroup("Reset") {
                HStack(spacing: 10) {
                    Button("Reset All Settings") {
                        settings.resetAllSettings()
                    }
                    Button("Reset Shell & Motion") {
                        settings.resetLayoutSettings()
                    }
                    Button("Reset Modules") {
                        settings.resetModuleSettings()
                    }
                }
                HelpText("These resets affect preferences. Use Customize Workspace to reset saved widget placement.")
            }
        }
    }

    private func settingsForm<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            content()
            if SettingsCategoryDefaults.supports(selectedSection) {
                Button("Restore \(selectedSection.rawValue) Defaults") {
                    SettingsCategoryDefaults.restore(selectedSection, settings: settings)
                }
                .help(selectedSection == .clipboard
                    ? "Restore clipboard options. Application exclusions and history stay intact."
                    : "Restore this category’s controls. Saved workspace placement stays intact.")
            }
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
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
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
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
        }
        .disabled(disabled)
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
