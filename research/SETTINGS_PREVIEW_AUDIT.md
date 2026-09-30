# Settings preview audit

Generated from `SettingsAuditCatalog` (Sources/DynamicIsland/Views/SettingsAudit.swift).
A unit test keeps it in sync with every `@Published` property in `AppSettings`.

| Classification | Count |
|---|---|
| VISUAL | 93 |
| VISUAL (no preview, justified) | 0 |
| BEHAVIORAL | 68 |
| PERMISSION | 2 |
| DATA/PERSISTENCE | 5 |
| EXTERNAL INTEGRATION | 1 |
| NO PRODUCTION READER | 0 |
| DEPRECATED / HIDDEN | 34 |
| **Total** | **203** |

| Setting | Classification | Live preview | Note |
|---|---|---|---|
| `collapsedWidth` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Width values are read through AppSettings.collapsedSize/expandedSize. |
| `collapsedHeight` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Width values are read through AppSettings.collapsedSize/expandedSize. |
| `expandedWidth` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Width values are read through AppSettings.collapsedSize/expandedSize. |
| `expandedHeight` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Width values are read through AppSettings.collapsedSize/expandedSize. |
| `respectHardwareNotch` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Width values are read through AppSettings.collapsedSize/expandedSize. |
| `islandThemeStyle` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Width values are read through AppSettings.collapsedSize/expandedSize. |
| `shellOpacity` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Width values are read through AppSettings.collapsedSize/expandedSize. |
| `shellStrokeEnabled` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Width values are read through AppSettings.collapsedSize/expandedSize. |
| `useAdaptiveNotchSizing` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The Island preview uses the production NotchGeometryService against a deterministic notched-screen sandbox. |
| `overlayEnabled` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `launchAtLoginEnabled` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `expandOnClick` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `collapseOnMouseLeave` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `autoCollapseEnabled` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `autoCollapseDelayPreset` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `autoCollapseGraceSeconds` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `startCollapsedOnLaunch` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `expandOnHover` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `animationPreset` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Replay shows the shared IslandShellMotion animation. |
| `reduceExtraMotion` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Replay shows the shared IslandShellMotion animation. |
| `shellAnimationSpeed` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Replay shows the shared IslandShellMotion animation. |
| `contentAnimationEnabled` | VISUAL | Content Motion Preview | Replays the production innerBlurScaleClean modifier with three staggered content items. |
| `contentStaggerEnabled` | VISUAL | Content Motion Preview | Replays the production innerBlurScaleClean modifier with three staggered content items. |
| `contentStaggerAmount` | VISUAL | Content Motion Preview | Replays the production innerBlurScaleClean modifier with three staggered content items. |
| `useBlurTransitions` | VISUAL | Content Motion Preview | Replays the production innerBlurScaleClean modifier with three staggered content items. |
| `useScaleTransitions` | VISUAL | Content Motion Preview | Replays the production innerBlurScaleClean modifier with three staggered content items. |
| `useArtworkAccentColor` | VISUAL | Media Player Preview |  |
| `visualizerAccentMode` | VISUAL | Media Player Preview |  |
| `showExpandedVisualizer` | VISUAL | Media Player Preview |  |
| `showCollapsedVisualizer` | VISUAL | Collapsed Media Preview | Renders the production CompactMediaView and AudioVisualizerView with labeled sample media. |
| `collapsedHoverPreviewEnabled` | VISUAL | Collapsed Hover Preview | Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay. |
| `collapsedHoverPreviewMediaEnabled` | VISUAL | Collapsed Hover Preview | Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay. |
| `collapsedHoverPreviewHeight` | VISUAL | Collapsed Hover Preview | Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay. |
| `collapsedHoverPreviewDelay` | VISUAL | Collapsed Hover Preview | Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay. |
| `collapsedHoverPreviewShowTitle` | VISUAL | Collapsed Hover Preview | Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay. |
| `collapsedHoverPreviewShowsArtist` | VISUAL | Collapsed Hover Preview | Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay. |
| `collapsedHoverPreviewShowsSource` | VISUAL | Collapsed Hover Preview | Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay. |
| `collapsedHoverPreviewTitleIconName` | VISUAL | Collapsed Hover Preview | Renders the production IslandSurface and CollapsedPreviewRow; Replay Delay uses the configured delay. |
| `collapsedHoverPreviewArtistIconName` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showTrayTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showTimerTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showStatsTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showToolsTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showAgentsTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showIslandTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `rememberLastSelectedTab` | BEHAVIORAL | — | Which tab opens on expansion. |
| `defaultExpandedTab` | BEHAVIORAL | — | Which tab opens on expansion. |
| `showActivitiesTab` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showLiveActivitiesTab` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showGesturesTab` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `agentUsageMetricsEnabled` | VISUAL | Agents Preview |  |
| `agentActivityEnabled` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
| `agentCompletionAlertsEnabled` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
| `agentApprovalAlertsEnabled` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
| `agentPeekDurationSeconds` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
| `agentSoundsEnabled` | DEPRECATED / HIDDEN | — | Hidden: AgentNotch 1.1 plays no notification sound (bundle and full upstream history audited), so no parity sound exists and the toggle had no audible effect. Value kept for migration. |
| `mediaEnabled` | VISUAL | Media Player Preview |  |
| `showMediaWhenPaused` | VISUAL | Media Player Preview |  |
| `showAlbumArtwork` | VISUAL | Media Player Preview |  |
| `showMediaTitle` | VISUAL | Media Player Preview |  |
| `showMediaArtist` | VISUAL | Media Player Preview |  |
| `showMediaSourceName` | VISUAL | Media Player Preview |  |
| `showPlaybackControls` | VISUAL | Media Player Preview |  |
| `showProgressSlider` | VISUAL | Media Player Preview |  |
| `showVolumeSlider` | VISUAL | Media Player Preview |  |
| `showVisualizer` | VISUAL | Media Player Preview |  |
| `showMediaWhenNoSource` | VISUAL | No-source Launcher Preview | Renders the production EmptyMediaLauncherView; interactions are disabled by the Settings sandbox. |
| `mediaLauncherEnabled` | VISUAL | No-source Launcher Preview | Renders the production EmptyMediaLauncherView; interactions are disabled by the Settings sandbox. |
| `showAppleMusicLauncher` | VISUAL | No-source Launcher Preview | Renders the production EmptyMediaLauncherView; interactions are disabled by the Settings sandbox. |
| `showSpotifyLauncher` | VISUAL | No-source Launcher Preview | Renders the production EmptyMediaLauncherView; interactions are disabled by the Settings sandbox. |
| `showYouTubeLauncher` | VISUAL | No-source Launcher Preview | Renders the production EmptyMediaLauncherView; interactions are disabled by the Settings sandbox. |
| `openSourceOnArtworkClick` | BEHAVIORAL | — | Click behavior. |
| `collapseAfterOpeningMediaSource` | BEHAVIORAL | — | Click behavior. |
| `collapseAfterMediaLauncher` | BEHAVIORAL | — | Click behavior. |
| `preferSystemNowPlaying` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `preferSpotifyAppleScript` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `preferBrowserMedia` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `browserMediaDetectionEnabled` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `youtubeMetadataEnrichmentEnabled` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showFileThumbnails` | VISUAL | File Tray Preview |  |
| `showFileExtensions` | VISUAL | File Tray Preview |  |
| `showFileCountBadge` | VISUAL | File Tray Preview |  |
| `airDropZoneEnabled` | VISUAL | File Tray Preview | The File Tray preview renders the production AirDropDropZoneView when enabled. |
| `trayEnabled` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `fileShelfEnabled` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `allowFileDropsOnCollapsedIsland` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `allowFileDropsOnExpandedTray` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `confirmBeforeClearShelf` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `revealInFinderActionEnabled` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `copyPathActionEnabled` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `removeFileActionEnabled` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `openFileActionEnabled` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `airDropFallbackRevealInFinder` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `deferThumbnailsDuringMorph` | BEHAVIORAL | — | Drop, context-menu and performance behavior. |
| `maxShelfFiles` | DATA/PERSISTENCE | — | Shelf capacity and persistence. |
| `persistFileShelfAcrossLaunches` | DATA/PERSISTENCE | — | Shelf capacity and persistence. |
| `timerPresetsEnabled` | VISUAL | Timer Page Preview | Previewed with the production DedicatedTimerPageView and the app's real timer (read-only). |
| `timerPreset1Minutes` | VISUAL | Timer Page Preview | Previewed with the production DedicatedTimerPageView and the app's real timer (read-only). |
| `timerPreset2Minutes` | VISUAL | Timer Page Preview | Previewed with the production DedicatedTimerPageView and the app's real timer (read-only). |
| `timerPreset3Minutes` | VISUAL | Timer Page Preview | Previewed with the production DedicatedTimerPageView and the app's real timer (read-only). |
| `showTimerProgressRing` | VISUAL | Timer Page Preview | Previewed with the production DedicatedTimerPageView and the app's real timer (read-only). |
| `timerRingAnimationEnabled` | VISUAL | Timer Page Preview | Previewed with the production DedicatedTimerPageView and the app's real timer (read-only). |
| `timerEnabled` | BEHAVIORAL | — | Timer behavior and alerts. |
| `timerSoundEnabled` | BEHAVIORAL | — | Timer behavior and alerts. |
| `timerNotificationEnabled` | BEHAVIORAL | — | Timer behavior and alerts. |
| `collapseAfterStartingTimer` | BEHAVIORAL | — | Timer behavior and alerts. |
| `keepIslandExpandedWhenTimerRunning` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showTimerInCollapsedIsland` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showCPU` | VISUAL | Stats Preview | Rendered with live values. |
| `showMemory` | VISUAL | Stats Preview | Rendered with live values. |
| `showGPU` | VISUAL | Stats Preview | Rendered with live values. |
| `showNetwork` | VISUAL | Stats Preview | Rendered with live values. |
| `showDisk` | VISUAL | Stats Preview | Rendered with live values. |
| `showBattery` | VISUAL | Stats Preview | Rendered with live values. |
| `showUptime` | VISUAL | Stats Preview | Rendered with live values. |
| `showActivityIndicator` | VISUAL | Stats Preview | Rendered with live values. |
| `statsEnabled` | BEHAVIORAL | — | Sampling behavior. |
| `statsRefreshIntervalSeconds` | BEHAVIORAL | — | Sampling behavior. |
| `animateStatsCharts` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `pauseStatsDuringShellMorph` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `activitiesEnabled` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `activitiesRefreshIntervalSeconds` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showRunningAppsActivity` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showDownloadsActivity` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showCalendarActivity` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showNowPlayingActivity` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `clipboardHistoryEnabled` | BEHAVIORAL | — | Starts or stops pasteboard monitoring. |
| `clipboardHistoryMaximumItems` | DATA/PERSISTENCE | — | History size, persistence and image capture. The Clipboard preview shows the real history. |
| `clipboardHistoryPersistenceEnabled` | DATA/PERSISTENCE | — | History size, persistence and image capture. The Clipboard preview shows the real history. |
| `clipboardHistoryCaptureImagesEnabled` | DATA/PERSISTENCE | — | History size, persistence and image capture. The Clipboard preview shows the real history. |
| `liveActivitiesEnabled` | VISUAL | Right Workspace Preview | Overview page. |
| `showExpandedLiveActivitiesSection` | VISUAL | Right Workspace Preview | Overview page. |
| `showMusicLiveActivity` | VISUAL | Live Activity Layout Preview |  |
| `showTimerLiveActivity` | VISUAL | Live Activity Layout Preview |  |
| `showFileDropLiveActivity` | VISUAL | Live Activity Layout Preview |  |
| `showBatteryLiveActivity` | VISUAL | Live Activity Layout Preview |  |
| `allowSimultaneousLiveActivitySidecars` | VISUAL | Live Activity Layout Preview |  |
| `timerSidecarPreference` | VISUAL | Live Activity Layout Preview |  |
| `liveActivityStyle` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showCalendarLiveActivity` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showDownloadsLiveActivity` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `liveActivityAutoDismissEnabled` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `liveActivityAutoDismissSeconds` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `liveActivityAnimationEnabled` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `systemHUDsEnabled` | VISUAL | System HUD Preview |  |
| `volumeHUDEnabled` | VISUAL | System HUD Preview |  |
| `brightnessHUDEnabled` | VISUAL | System HUD Preview |  |
| `capsLockHUDEnabled` | VISUAL | System HUD Preview |  |
| `batteryStatusHUDEnabled` | VISUAL | System HUD Preview |  |
| `lowBatteryHUDEnabled` | VISUAL | System HUD Preview |  |
| `audioDeviceHUDEnabled` | VISUAL | System HUD Preview |  |
| `focusHUDEnabled` | VISUAL | System HUD Preview |  |
| `replaceMacOSSystemHUDs` | PERMISSION | — | Requires Accessibility to intercept system HUD keys; status is shown in Settings. |
| `systemHUDDurationSeconds` | BEHAVIORAL | — | How long a HUD stays visible. |
| `collapsedPriorityRunningTimer` | BEHAVIORAL | — | Collapsed arbitration order, read through AppSettings' priority accessors. |
| `collapsedPriorityPlayingMedia` | BEHAVIORAL | — | Collapsed arbitration order, read through AppSettings' priority accessors. |
| `collapsedPriorityPausedTimer` | BEHAVIORAL | — | Collapsed arbitration order, read through AppSettings' priority accessors. |
| `collapsedPriorityRecentFiles` | BEHAVIORAL | — | Collapsed arbitration order, read through AppSettings' priority accessors. |
| `collapsedPriorityPausedMedia` | BEHAVIORAL | — | Collapsed arbitration order, read through AppSettings' priority accessors. |
| `gesturesEnabled` | BEHAVIORAL | — | Gesture recognition and actions. |
| `gestureInputSource` | BEHAVIORAL | — | Gesture recognition and actions. |
| `expandGestureEnabled` | BEHAVIORAL | — | Gesture recognition and actions. |
| `collapseGestureEnabled` | BEHAVIORAL | — | Gesture recognition and actions. |
| `nextTabGestureEnabled` | BEHAVIORAL | — | Gesture recognition and actions. |
| `previousTabGestureEnabled` | BEHAVIORAL | — | Gesture recognition and actions. |
| `mediaPlayPauseGestureEnabled` | BEHAVIORAL | — | Gesture recognition and actions. |
| `timerStartStopGestureEnabled` | BEHAVIORAL | — | Gesture recognition and actions. |
| `collapsedDoubleClickAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `collapsedSwipeDownAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `collapsedSwipeUpAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `collapsedSwipeLeftAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `collapsedSwipeRightAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `collapsedLongPressAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `expandedDoubleClickAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `expandedSwipeDownAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `expandedSwipeUpAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `expandedSwipeLeftAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `expandedSwipeRightAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `expandedLongPressAction` | BEHAVIORAL | — | Gesture recognition and actions. |
| `gestureSensitivity` | BEHAVIORAL | — | Gesture recognition and actions. |
| `gestureCooldownSeconds` | BEHAVIORAL | — | Gesture recognition and actions. |
| `requireGestureConfirmation` | BEHAVIORAL | — | Gesture recognition and actions. |
| `showGestureHints` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `gesturePrivacyMode` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `disableVisualizerDuringMorph` | BEHAVIORAL | — | Performance behavior during shell morph. |
| `verboseUILogsEnabled` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showDebugFrames` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `showHitTestRegionDebug` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `disableThumbnailsDuringMorph` | DEPRECATED / HIDDEN | — | Legacy persisted value retained for migration compatibility; hidden from Settings until real production behavior exists. |
| `rightWorkspace.pageOrder` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.hiddenPages` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.defaultPage` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.indicatorStyle` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.toolOrder` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.hiddenTools` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.sectionOrder` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.hiddenSections` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.swipeEnabled` | BEHAVIORAL | — | Two-finger paging over the right half. |
| `spotify.webAPI.clientID` | EXTERNAL INTEGRATION | — | Developer-only override (DEBUG builds). Release builds read the packaged Info.plist Client ID; none is packaged today, so Settings shows 'Not configured'. Local Spotify controls never depend on it. |
| `messaging.enabled` | BEHAVIORAL | — | Read by MessagingController presentation and adapter observation. |
| `messaging.mutedProviders` | BEHAVIORAL | — | Read by MessagingController presentation and adapter observation. |
| `messaging.showPreviewOnCompact` | BEHAVIORAL | — | Privacy: the compact message activity subtitle shows the message text or 'New message' (MessagingController.compactPreview). Settings never renders message content. |
| `messaging.readsSystemNotifications` | PERMISSION | — | Opt-in Notification Center reading; requires Full Disk Access, status shown in Messaging settings. |
