import Foundation

/// Live preview surfaces available in Settings. Each renders production
/// components (see SettingsPreviews.swift).
enum SettingsPreviewID: String, CaseIterable, Sendable {
    case islandShell = "Island Preview (Island, Appearance, Motion, Tabs)"
    case contentMotion = "Content Motion Preview"
    case collapsedMedia = "Collapsed Media Preview"
    case collapsedHover = "Collapsed Hover Preview"
    case media = "Media Player Preview"
    case mediaLauncher = "No-source Launcher Preview"
    case fileTray = "File Tray Preview"
    case timer = "Timer Page Preview"
    case stats = "Stats Preview"
    case agents = "Agents Preview"
    case clipboard = "Clipboard Preview"
    case liveActivityLayout = "Live Activity Layout Preview"
    case systemHUD = "System HUD Preview"
    case rightWorkspace = "Right Workspace Preview"
    case productivity = "Productivity Page Preview"
}

enum SettingsAuditClass: String, CaseIterable, Sendable {
    /// Changes appearance; has a live preview.
    case visual = "VISUAL"
    /// Changes appearance, but a live preview is not provided (justified).
    case visualWithoutPreview = "VISUAL (no preview, justified)"
    case behavioral = "BEHAVIORAL"
    case permission = "PERMISSION"
    case dataPersistence = "DATA/PERSISTENCE"
    case externalIntegration = "EXTERNAL INTEGRATION"
    /// Audit finding: a user-facing setting has no production reader. The
    /// catalog must contain zero of these at release checkpoints.
    case noProductionReader = "NO PRODUCTION READER"
    /// Persisted only for compatibility with older settings files. It is not
    /// exposed in Settings until a real production reader exists.
    case deprecatedHidden = "DEPRECATED / HIDDEN"
}

struct SettingsAuditEntry: Sendable {
    let key: String
    let classification: SettingsAuditClass
    let preview: SettingsPreviewID?
    let note: String
}

/// Audit of every AppSettings property plus the right-workspace
/// configuration. A test keeps this in sync with AppSettings.
enum SettingsAuditCatalog {
    private static func visual(_ keys: [String], _ preview: SettingsPreviewID, _ note: String = "") -> [SettingsAuditEntry] {
        keys.map { SettingsAuditEntry(key: $0, classification: .visual, preview: preview, note: note) }
    }

    private static func entries(_ keys: [String], _ classification: SettingsAuditClass, _ note: String) -> [SettingsAuditEntry] {
        keys.map { SettingsAuditEntry(key: $0, classification: classification, preview: nil, note: note) }
    }

    static let noReaderNote = "User-facing setting has no production reader; this classification must remain empty."
    static let deprecatedNote = "Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists."

    static let entries: [SettingsAuditEntry] =
        // Island
        visual(["collapsedWidth", "collapsedHeight", "expandedWidth", "expandedHeight", "respectHardwareNotch",
                "islandThemeStyle", "shellOpacity", "shellStrokeEnabled"], .islandShell,
               "Width values are read through AppSettings.collapsedSize/expandedSize.")
        + visual(["useAdaptiveNotchSizing"], .islandShell,
                 "The Island preview uses the production NotchGeometryService against a deterministic notched-screen sandbox.")
        + entries(["overlayEnabled", "launchAtLoginEnabled", "expandOnClick", "collapseOnMouseLeave", "autoCollapseEnabled",
                   "autoCollapseDelayPreset", "autoCollapseGraceSeconds"], .behavioral,
                  "Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing.")
        + entries(["startCollapsedOnLaunch", "expandOnHover"], .deprecatedHidden, deprecatedNote)
        // Motion
        + visual(["animationPreset", "reduceExtraMotion", "shellAnimationSpeed"], .islandShell,
                 "Replay shows the shared IslandShellMotion animation.")
        + visual(["contentAnimationEnabled", "contentStaggerEnabled", "contentStaggerAmount", "useBlurTransitions",
                  "useScaleTransitions"], .contentMotion,
                 "Replays the production innerBlurScaleClean modifier with three staggered content items.")
        // Visualizer / hover preview
        + visual(["useArtworkAccentColor", "visualizerAccentMode", "showExpandedVisualizer"], .media)
        + visual(["showCollapsedVisualizer"], .collapsedMedia,
                 "Renders the production CompactMediaView and AudioVisualizerView with labeled sample media.")
        + visual(["collapsedHoverPreviewEnabled", "collapsedHoverPreviewMediaEnabled", "collapsedHoverPreviewHeight",
                  "collapsedHoverPreviewDelay", "collapsedHoverPreviewShowTitle", "collapsedHoverPreviewShowsArtist",
                  "collapsedHoverPreviewShowsSource", "collapsedHoverPreviewTitleIconName"], .collapsedHover,
                 "Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay.")
        + entries(["collapsedHoverPreviewArtistIconName"], .deprecatedHidden, deprecatedNote)
        // Tabs
        + visual(["showTrayTab", "showTimerTab", "showStatsTab", "showToolsTab", "showAgentsTab", "showIslandTab"], .islandShell,
                 "The expanded preview renders the production page switcher.")
        + entries(["rememberLastSelectedTab", "defaultExpandedTab"], .behavioral, "Which tab opens on expansion.")
        + entries(["showActivitiesTab", "showLiveActivitiesTab", "showGesturesTab"], .deprecatedHidden, deprecatedNote)
        // Agents
        + visual(["agentUsageMetricsEnabled"], .agents)
        + entries(["agentActivityEnabled", "agentCompletionAlertsEnabled", "agentApprovalAlertsEnabled",
                   "agentPeekDurationSeconds"], .behavioral, "Agent monitoring and alert behavior.")
        + entries(["agentActivityRecordingEnabled"], .behavioral,
                  "Record Activities: opt-in local JSON Lines of normalized agent events (no prompts or transcripts), 14 days / 20 MB.")
        + entries(["agentSoundsEnabled"], .deprecatedHidden,
                  "Hidden: AgentNotch 1.1 plays no notification sound (bundle and full upstream history audited), so no parity sound exists and the toggle had no audible effect. Value kept for migration.")
        // Media
        + visual(["mediaEnabled", "showMediaWhenPaused", "showAlbumArtwork", "showMediaTitle", "showMediaArtist",
                  "showMediaSourceName", "showPlaybackControls", "showProgressSlider", "showVolumeSlider", "showVisualizer"], .media)
        + visual(["showMediaWhenNoSource", "mediaLauncherEnabled", "showAppleMusicLauncher", "showSpotifyLauncher",
                  "showYouTubeLauncher"], .mediaLauncher,
                 "Renders the production EmptyMediaLauncherView; interactions are disabled by the Settings sandbox.")
        + entries(["openSourceOnArtworkClick", "collapseAfterOpeningMediaSource", "collapseAfterMediaLauncher"], .behavioral,
                  "Click behavior.")
        + entries(["preferSystemNowPlaying", "preferSpotifyAppleScript", "preferBrowserMedia", "browserMediaDetectionEnabled",
                   "youtubeMetadataEnrichmentEnabled"], .deprecatedHidden, deprecatedNote)
        // Tray
        + visual(["showFileThumbnails", "showFileExtensions", "showFileCountBadge"], .fileTray)
        + visual(["airDropZoneEnabled"], .fileTray,
                 "The File Tray preview renders the production AirDropDropZoneView when enabled.")
        + entries(["trayEnabled", "fileShelfEnabled", "allowFileDropsOnCollapsedIsland", "allowFileDropsOnExpandedTray",
                   "confirmBeforeClearShelf", "revealInFinderActionEnabled", "copyPathActionEnabled", "removeFileActionEnabled",
                   "openFileActionEnabled", "airDropFallbackRevealInFinder", "deferThumbnailsDuringMorph"], .behavioral,
                  "Drop, context-menu and performance behavior.")
        + entries(["maxShelfFiles", "persistFileShelfAcrossLaunches"], .dataPersistence, "Shelf capacity and persistence.")
        // Timer
        + visual(["timerPresetsEnabled", "timerPreset1Minutes", "timerPreset2Minutes", "timerPreset3Minutes",
                  "showTimerProgressRing", "timerRingAnimationEnabled"], .timer,
                 "Previewed with the production DedicatedTimerPageView and the app's real timer (read-only).")
        + entries(["timerEnabled", "timerSoundEnabled", "timerNotificationEnabled", "collapseAfterStartingTimer"], .behavioral,
                  "Timer behavior and alerts.")
        + entries(["keepIslandExpandedWhenTimerRunning", "showTimerInCollapsedIsland"], .deprecatedHidden, deprecatedNote)
        // Stats
        + visual(["showCPU", "showMemory", "showGPU", "showNetwork", "showDisk", "showBattery", "showUptime",
                  "showActivityIndicator"], .stats, "Rendered with live values.")
        + entries(["statsEnabled", "statsRefreshIntervalSeconds"], .behavioral, "Sampling behavior.")
        + entries(["animateStatsCharts", "pauseStatsDuringShellMorph"], .deprecatedHidden, deprecatedNote)
        // Activities (legacy)
        + entries(["activitiesEnabled", "activitiesRefreshIntervalSeconds", "showRunningAppsActivity", "showDownloadsActivity",
                   "showCalendarActivity", "showNowPlayingActivity"], .deprecatedHidden, deprecatedNote)
        // Clipboard
        + entries(["clipboardHistoryEnabled"], .behavioral, "Starts or stops pasteboard monitoring.")
        + entries(["clipboardHistoryMaximumItems", "clipboardHistoryPersistenceEnabled", "clipboardHistoryCaptureImagesEnabled"],
                  .dataPersistence, "History size, persistence and image capture. The Clipboard preview shows the real history.")
        // Live Activities
        + visual(["liveActivitiesEnabled", "showExpandedLiveActivitiesSection"], .rightWorkspace, "Overview page.")
        + visual(["showMusicLiveActivity", "showTimerLiveActivity", "showFileDropLiveActivity", "showBatteryLiveActivity",
                  "allowSimultaneousLiveActivitySidecars", "timerSidecarPreference"], .liveActivityLayout)
        + entries(["liveActivityStyle", "showCalendarLiveActivity", "showDownloadsLiveActivity", "liveActivityAutoDismissEnabled",
                   "liveActivityAutoDismissSeconds", "liveActivityAnimationEnabled"], .deprecatedHidden, deprecatedNote)
        // HUDs
        + visual(["systemHUDsEnabled", "volumeHUDEnabled", "brightnessHUDEnabled", "capsLockHUDEnabled",
                  "batteryStatusHUDEnabled", "lowBatteryHUDEnabled", "audioDeviceHUDEnabled", "focusHUDEnabled"], .systemHUD)
        + entries(["replaceMacOSSystemHUDs"], .permission, "Requires Accessibility to intercept system HUD keys; status is shown in Settings.")
        + entries(["systemHUDDurationSeconds"], .behavioral, "How long a HUD stays visible.")
        + entries(["collapsedPriorityRunningTimer", "collapsedPriorityPlayingMedia", "collapsedPriorityPausedTimer",
                   "collapsedPriorityRecentFiles", "collapsedPriorityPausedMedia"], .behavioral,
                  "Collapsed arbitration order, read through AppSettings' priority accessors.")
        // Gestures
        + entries(["gesturesEnabled", "gestureInputSource", "expandGestureEnabled", "collapseGestureEnabled",
                   "nextTabGestureEnabled", "previousTabGestureEnabled", "mediaPlayPauseGestureEnabled",
                   "timerStartStopGestureEnabled", "collapsedDoubleClickAction", "collapsedSwipeDownAction",
                   "collapsedSwipeUpAction", "collapsedSwipeLeftAction", "collapsedSwipeRightAction", "collapsedLongPressAction",
                   "expandedDoubleClickAction", "expandedSwipeDownAction", "expandedSwipeUpAction", "expandedSwipeLeftAction",
                   "expandedSwipeRightAction", "expandedLongPressAction", "gestureSensitivity", "gestureCooldownSeconds",
                   "requireGestureConfirmation"], .behavioral, "Gesture recognition and actions.")
        + entries(["showGestureHints", "gesturePrivacyMode"], .deprecatedHidden, deprecatedNote)
        // Advanced
        + entries(["disableVisualizerDuringMorph"], .behavioral, "Performance behavior during shell morph.")
        + entries(["verboseUILogsEnabled", "showDebugFrames", "showHitTestRegionDebug", "disableThumbnailsDuringMorph"],
                  .deprecatedHidden, deprecatedNote)
        // Right workspace (RightWorkspaceConfiguration)
        + visual(["rightWorkspace.pageOrder", "rightWorkspace.hiddenPages", "rightWorkspace.defaultPage",
                  "rightWorkspace.indicatorStyle", "rightWorkspace.toolOrder", "rightWorkspace.hiddenTools",
                  "rightWorkspace.sectionOrder", "rightWorkspace.hiddenSections"], .rightWorkspace)
        + entries(["rightWorkspace.swipeEnabled"], .behavioral, "Two-finger paging over the right half.")
        + entries(["spotify.webAPI.clientID"], .externalIntegration,
                  "Developer-only override (DEBUG builds). Release builds read the packaged Info.plist Client ID; none is packaged today, so Settings shows 'Not configured'. Local Spotify controls never depend on it.")
        // Messaging (MessagingController.Preferences, persisted by MessagingPreferencesPersistence)
        + entries(["messaging.enabled", "messaging.mutedProviders"], .behavioral,
                  "Read by MessagingController presentation and adapter observation.")
        + entries(["messaging.showPreviewOnCompact"], .behavioral,
                  "Privacy: the compact message activity subtitle shows the message text or 'New message' (MessagingController.compactPreview). Settings never renders message content.")
        + entries(["messaging.readsSystemNotifications"], .permission,
                  "Opt-in Notification Center reading; requires Full Disk Access, status shown in Messaging settings.")

    /// Visual settings whose production component cannot be rendered in a
    /// Settings preview yet. They do have production readers. The Timer page
    /// (`DedicatedTimerPageView`) is private to IslandRootView.swift; the
    /// previous Timer preview rendered a lookalike and was removed. A test
    /// pins this set so it can only shrink.
    static let knownPreviewGaps: Set<String> = []

    static var appSettingsKeys: [String] {
        entries.map(\.key).filter { !$0.contains(".") }
    }

    /// Markdown audit report generated from this catalog.
    static func markdownReport() -> String {
        var lines = [
            "# Settings preview audit",
            "",
            "Generated from `SettingsAuditCatalog` (Sources/DynamicIsland/Views/SettingsAudit.swift).",
            "A unit test keeps it in sync with every `@Published` property in `AppSettings`.",
            ""
        ]
        let counts = Dictionary(grouping: entries, by: \.classification)
        lines.append("| Classification | Count |")
        lines.append("|---|---|")
        for classification in SettingsAuditClass.allCases {
            lines.append("| \(classification.rawValue) | \(counts[classification]?.count ?? 0) |")
        }
        lines.append("| **Total** | **\(entries.count)** |")
        lines.append("")
        lines.append("| Setting | Classification | Live preview | Note |")
        lines.append("|---|---|---|---|")
        for entry in entries {
            lines.append("| `\(entry.key)` | \(entry.classification.rawValue) | \(entry.preview?.rawValue ?? "—") | \(entry.note) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
