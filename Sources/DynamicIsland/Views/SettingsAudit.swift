import Foundation

/// Live preview surfaces available in Settings. Each renders production
/// components (see SettingsPreviews.swift).
enum SettingsPreviewID: String, CaseIterable, Sendable {
    case islandShell = "Island Preview (Island, Appearance, Motion, Tabs)"
    case media = "Media Player Preview"
    case fileTray = "File Tray Preview"
    case timer = "Timer Preview"
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
    /// Shown in Settings but no production code reads it (audit finding).
    case noProductionReader = "NO PRODUCTION READER"
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

    static let noReaderNote = "Shown in Settings, but no production code reads it; it has no effect today."

    static let entries: [SettingsAuditEntry] =
        // Island
        visual(["collapsedWidth", "collapsedHeight", "expandedWidth", "expandedHeight", "respectHardwareNotch",
                "islandThemeStyle", "shellOpacity", "shellStrokeEnabled"], .islandShell,
               "Width values are read through AppSettings.collapsedSize/expandedSize.")
        + entries(["useAdaptiveNotchSizing"], .visualWithoutPreview,
                  "Depends on the physical notch measured from the real screen; a sandbox cannot reproduce hardware geometry.")
        + entries(["overlayEnabled", "launchAtLoginEnabled", "expandOnClick", "collapseOnMouseLeave", "autoCollapseEnabled",
                   "autoCollapseDelayPreset", "autoCollapseGraceSeconds"], .behavioral,
                  "Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing.")
        + entries(["startCollapsedOnLaunch", "expandOnHover"], .noProductionReader, noReaderNote)
        // Motion
        + visual(["animationPreset", "reduceExtraMotion", "shellAnimationSpeed"], .islandShell,
                 "Replay shows the shared IslandShellMotion animation.")
        + entries(["contentAnimationEnabled", "contentStaggerEnabled", "contentStaggerAmount", "useBlurTransitions",
                   "useScaleTransitions"], .visualWithoutPreview,
                  "Content entrance transitions run during a real expansion; the Island preview replays shell motion only.")
        // Visualizer / hover preview
        + visual(["useArtworkAccentColor", "visualizerAccentMode", "showExpandedVisualizer"], .media)
        + entries(["showCollapsedVisualizer"], .visualWithoutPreview,
                  "Collapsed compact media is shown in the island itself; the Live Activity layout preview shows its geometry.")
        + entries(["collapsedHoverPreviewEnabled", "collapsedHoverPreviewMediaEnabled", "collapsedHoverPreviewHeight",
                   "collapsedHoverPreviewDelay", "collapsedHoverPreviewShowTitle", "collapsedHoverPreviewShowsArtist",
                   "collapsedHoverPreviewShowsSource", "collapsedHoverPreviewTitleIconName"], .visualWithoutPreview,
                  "The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet.")
        + entries(["collapsedHoverPreviewArtistIconName"], .noProductionReader, noReaderNote)
        // Tabs
        + visual(["showTrayTab", "showTimerTab", "showStatsTab", "showToolsTab", "showAgentsTab", "showIslandTab"], .islandShell,
                 "The expanded preview renders the production page switcher.")
        + entries(["rememberLastSelectedTab", "defaultExpandedTab"], .behavioral, "Which tab opens on expansion.")
        + entries(["showActivitiesTab", "showLiveActivitiesTab", "showGesturesTab"], .noProductionReader, noReaderNote)
        // Agents
        + visual(["agentUsageMetricsEnabled"], .agents)
        + entries(["agentActivityEnabled", "agentCompletionAlertsEnabled", "agentApprovalAlertsEnabled", "agentSoundsEnabled",
                   "agentPeekDurationSeconds"], .behavioral, "Agent monitoring and alert behavior.")
        // Media
        + visual(["mediaEnabled", "showMediaWhenPaused", "showAlbumArtwork", "showMediaTitle", "showMediaArtist",
                  "showMediaSourceName", "showPlaybackControls", "showProgressSlider", "showVolumeSlider", "showVisualizer"], .media)
        + entries(["showMediaWhenNoSource", "mediaLauncherEnabled", "showAppleMusicLauncher", "showSpotifyLauncher",
                   "showYouTubeLauncher"], .visualWithoutPreview,
                  "The launcher appears only when no media source exists; the preview shows the active player.")
        + entries(["openSourceOnArtworkClick", "collapseAfterOpeningMediaSource", "collapseAfterMediaLauncher"], .behavioral,
                  "Click behavior.")
        + entries(["preferSystemNowPlaying", "preferSpotifyAppleScript", "preferBrowserMedia", "browserMediaDetectionEnabled",
                   "youtubeMetadataEnrichmentEnabled"], .noProductionReader, noReaderNote)
        // Tray
        + visual(["showFileThumbnails", "showFileExtensions", "showFileCountBadge"], .fileTray)
        + entries(["airDropZoneEnabled"], .visualWithoutPreview,
                  "The AirDrop drop zone is part of the Tray page layout; the preview shows tiles and quick actions.")
        + entries(["trayEnabled", "fileShelfEnabled", "allowFileDropsOnCollapsedIsland", "allowFileDropsOnExpandedTray",
                   "confirmBeforeClearShelf", "revealInFinderActionEnabled", "copyPathActionEnabled", "removeFileActionEnabled",
                   "openFileActionEnabled", "airDropFallbackRevealInFinder", "deferThumbnailsDuringMorph"], .behavioral,
                  "Drop, context-menu and performance behavior.")
        + entries(["maxShelfFiles", "persistFileShelfAcrossLaunches"], .dataPersistence, "Shelf capacity and persistence.")
        // Timer
        + visual(["timerPresetsEnabled", "timerPreset1Minutes", "timerPreset2Minutes", "timerPreset3Minutes"], .timer)
        + visual(["showTimerProgressRing", "timerRingAnimationEnabled"], .liveActivityLayout)
        + entries(["timerEnabled", "timerSoundEnabled", "timerNotificationEnabled", "collapseAfterStartingTimer"], .behavioral,
                  "Timer behavior and alerts.")
        + entries(["keepIslandExpandedWhenTimerRunning", "showTimerInCollapsedIsland"], .noProductionReader, noReaderNote)
        // Stats
        + visual(["showCPU", "showMemory", "showGPU", "showNetwork", "showDisk", "showBattery", "showUptime",
                  "showActivityIndicator"], .stats, "Rendered with live values.")
        + entries(["statsEnabled", "statsRefreshIntervalSeconds"], .behavioral, "Sampling behavior.")
        + entries(["animateStatsCharts", "pauseStatsDuringShellMorph"], .noProductionReader, noReaderNote)
        // Activities (legacy)
        + entries(["activitiesEnabled", "activitiesRefreshIntervalSeconds", "showRunningAppsActivity", "showDownloadsActivity",
                   "showCalendarActivity", "showNowPlayingActivity"], .noProductionReader, noReaderNote)
        // Clipboard
        + entries(["clipboardHistoryEnabled"], .behavioral, "Starts or stops pasteboard monitoring.")
        + entries(["clipboardHistoryMaximumItems", "clipboardHistoryPersistenceEnabled", "clipboardHistoryCaptureImagesEnabled"],
                  .dataPersistence, "History size, persistence and image capture. The Clipboard preview shows the real history.")
        // Live Activities
        + visual(["liveActivitiesEnabled", "showExpandedLiveActivitiesSection"], .rightWorkspace, "Overview page.")
        + visual(["showMusicLiveActivity", "showTimerLiveActivity", "showFileDropLiveActivity", "showBatteryLiveActivity",
                  "allowSimultaneousLiveActivitySidecars", "timerSidecarPreference"], .liveActivityLayout)
        + entries(["liveActivityStyle", "showCalendarLiveActivity", "showDownloadsLiveActivity", "liveActivityAutoDismissEnabled",
                   "liveActivityAutoDismissSeconds", "liveActivityAnimationEnabled"], .noProductionReader, noReaderNote)
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
        + entries(["showGestureHints", "gesturePrivacyMode"], .noProductionReader, noReaderNote)
        // Advanced
        + entries(["disableVisualizerDuringMorph"], .behavioral, "Performance behavior during shell morph.")
        + entries(["verboseUILogsEnabled", "showDebugFrames", "showHitTestRegionDebug", "disableThumbnailsDuringMorph"],
                  .noProductionReader, noReaderNote)
        // Right workspace (RightWorkspaceConfiguration)
        + visual(["rightWorkspace.pageOrder", "rightWorkspace.hiddenPages", "rightWorkspace.defaultPage",
                  "rightWorkspace.indicatorStyle", "rightWorkspace.toolOrder", "rightWorkspace.hiddenTools",
                  "rightWorkspace.sectionOrder", "rightWorkspace.hiddenSections"], .rightWorkspace)
        + entries(["rightWorkspace.swipeEnabled"], .behavioral, "Two-finger paging over the right half.")
        + entries(["spotify.webAPI.clientID"], .externalIntegration,
                  "Spotify Web API client; connection state and errors shown in Right Workspace settings.")

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
