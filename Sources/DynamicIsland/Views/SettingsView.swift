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
        case .liveActivities: "waveform.path.ecg"
        case .gestures: "hand.raised"
        case .advanced: "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcuts: ShortcutsStore
    @State private var selectedSection: SettingsSection = .island

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
                Picker("Theme", selection: $settings.islandTheme) {
                    ForEach(IslandTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                SliderRow(title: "Shell opacity", value: $settings.shellOpacity, range: 0.35...1.0, format: "%.2f")
                Toggle("Shell stroke", isOn: $settings.shellStrokeEnabled)
                Toggle("Shell shadow", isOn: $settings.shellShadowEnabled)
                Toggle("Notch shoulder blend", isOn: $settings.notchShoulderBlendEnabledSetting)
                    .disabled(true)
                HelpText("Shoulder blend remains parked and disabled in the active shell path.")
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
                Toggle("Opacity transitions", isOn: $settings.useOpacityTransitions)
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

            SettingsGroup("Future Options") {
                Toggle("Timer sound", isOn: $settings.timerSoundEnabled)
                    .disabled(true)
                Toggle("Timer notification", isOn: $settings.timerNotificationEnabled)
                    .disabled(true)
                Toggle("Show timer in collapsed island", isOn: $settings.showTimerInCollapsedIsland)
                    .disabled(true)
                HelpText("Timer sound, notifications, and collapsed-timer presentation are stored now and not implemented yet.")
            }
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
            SettingsGroup("Coming Soon") {
                Toggle("Enable live activities", isOn: $settings.liveActivitiesEnabled)
                    .disabled(true)
                Picker("Style", selection: $settings.liveActivityStyle) {
                    ForEach(LiveActivityStyle.allCases) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .disabled(true)
                Toggle("Music live activity", isOn: $settings.showMusicLiveActivity)
                    .disabled(true)
                Toggle("Timer live activity", isOn: $settings.showTimerLiveActivity)
                    .disabled(true)
                Toggle("File drop live activity", isOn: $settings.showFileDropLiveActivity)
                    .disabled(true)
                Toggle("Battery live activity", isOn: $settings.showBatteryLiveActivity)
                    .disabled(true)
                Toggle("Calendar live activity", isOn: $settings.showCalendarLiveActivity)
                    .disabled(true)
                Toggle("Downloads live activity", isOn: $settings.showDownloadsLiveActivity)
                    .disabled(true)
                Toggle("Auto dismiss", isOn: $settings.liveActivityAutoDismissEnabled)
                    .disabled(true)
                SliderRow(title: "Dismiss delay", value: $settings.liveActivityAutoDismissSeconds, range: 1...60, format: "%.0fs", disabled: true)
                Toggle("Animation", isOn: $settings.liveActivityAnimationEnabled)
                    .disabled(true)
                HelpText("These fields are persisted now and intentionally marked coming soon because a live-activities engine does not exist yet.")
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

private struct SettingsGroup<Content: View>: View {
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

private struct HelpText: View {
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
