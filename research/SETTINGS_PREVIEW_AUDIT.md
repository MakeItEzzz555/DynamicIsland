# Settings preview audit

Generated from `SettingsAuditCatalog` (Sources/DynamicIsland/Views/SettingsAudit.swift).
A unit test keeps it in sync with every `@Published` property in `AppSettings`.

| Classification | Count |
|---|---|
| VISUAL | 72 |
| VISUAL (no preview, justified) | 21 |
| BEHAVIORAL | 66 |
| PERMISSION | 1 |
| DATA/PERSISTENCE | 5 |
| EXTERNAL INTEGRATION | 1 |
| NO PRODUCTION READER | 33 |
| **Total** | **199** |

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
| `useAdaptiveNotchSizing` | VISUAL (no preview, justified) | — | Depends on the physical notch measured from the real screen; a sandbox cannot reproduce hardware geometry. |
| `overlayEnabled` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `launchAtLoginEnabled` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `expandOnClick` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `collapseOnMouseLeave` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `autoCollapseEnabled` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `autoCollapseDelayPreset` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `autoCollapseGraceSeconds` | BEHAVIORAL | — | Pointer/launch behavior; auto-collapse values are read through AppSettings computed timing. |
| `startCollapsedOnLaunch` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `expandOnHover` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `animationPreset` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Replay shows the shared IslandShellMotion animation. |
| `reduceExtraMotion` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Replay shows the shared IslandShellMotion animation. |
| `shellAnimationSpeed` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | Replay shows the shared IslandShellMotion animation. |
| `contentAnimationEnabled` | VISUAL (no preview, justified) | — | Content entrance transitions run during a real expansion; the Island preview replays shell motion only. |
| `contentStaggerEnabled` | VISUAL (no preview, justified) | — | Content entrance transitions run during a real expansion; the Island preview replays shell motion only. |
| `contentStaggerAmount` | VISUAL (no preview, justified) | — | Content entrance transitions run during a real expansion; the Island preview replays shell motion only. |
| `useBlurTransitions` | VISUAL (no preview, justified) | — | Content entrance transitions run during a real expansion; the Island preview replays shell motion only. |
| `useScaleTransitions` | VISUAL (no preview, justified) | — | Content entrance transitions run during a real expansion; the Island preview replays shell motion only. |
| `useArtworkAccentColor` | VISUAL | Media Player Preview |  |
| `visualizerAccentMode` | VISUAL | Media Player Preview |  |
| `showExpandedVisualizer` | VISUAL | Media Player Preview |  |
| `showCollapsedVisualizer` | VISUAL (no preview, justified) | — | Collapsed compact media is shown in the island itself; the Live Activity layout preview shows its geometry. |
| `collapsedHoverPreviewEnabled` | VISUAL (no preview, justified) | — | The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet. |
| `collapsedHoverPreviewMediaEnabled` | VISUAL (no preview, justified) | — | The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet. |
| `collapsedHoverPreviewHeight` | VISUAL (no preview, justified) | — | The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet. |
| `collapsedHoverPreviewDelay` | VISUAL (no preview, justified) | — | The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet. |
| `collapsedHoverPreviewShowTitle` | VISUAL (no preview, justified) | — | The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet. |
| `collapsedHoverPreviewShowsArtist` | VISUAL (no preview, justified) | — | The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet. |
| `collapsedHoverPreviewShowsSource` | VISUAL (no preview, justified) | — | The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet. |
| `collapsedHoverPreviewTitleIconName` | VISUAL (no preview, justified) | — | The hover preview appears only while the pointer rests on the collapsed island; not reproduced in Settings yet. |
| `collapsedHoverPreviewArtistIconName` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showTrayTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showTimerTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showStatsTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showToolsTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showAgentsTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `showIslandTab` | VISUAL | Island Preview (Island, Appearance, Motion, Tabs) | The expanded preview renders the production page switcher. |
| `rememberLastSelectedTab` | BEHAVIORAL | — | Which tab opens on expansion. |
| `defaultExpandedTab` | BEHAVIORAL | — | Which tab opens on expansion. |
| `showActivitiesTab` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showLiveActivitiesTab` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showGesturesTab` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `agentUsageMetricsEnabled` | VISUAL | Agents Preview |  |
| `agentActivityEnabled` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
| `agentCompletionAlertsEnabled` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
| `agentApprovalAlertsEnabled` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
| `agentSoundsEnabled` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
| `agentPeekDurationSeconds` | BEHAVIORAL | — | Agent monitoring and alert behavior. |
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
| `showMediaWhenNoSource` | VISUAL (no preview, justified) | — | The launcher appears only when no media source exists; the preview shows the active player. |
| `mediaLauncherEnabled` | VISUAL (no preview, justified) | — | The launcher appears only when no media source exists; the preview shows the active player. |
| `showAppleMusicLauncher` | VISUAL (no preview, justified) | — | The launcher appears only when no media source exists; the preview shows the active player. |
| `showSpotifyLauncher` | VISUAL (no preview, justified) | — | The launcher appears only when no media source exists; the preview shows the active player. |
| `showYouTubeLauncher` | VISUAL (no preview, justified) | — | The launcher appears only when no media source exists; the preview shows the active player. |
| `openSourceOnArtworkClick` | BEHAVIORAL | — | Click behavior. |
| `collapseAfterOpeningMediaSource` | BEHAVIORAL | — | Click behavior. |
| `collapseAfterMediaLauncher` | BEHAVIORAL | — | Click behavior. |
| `preferSystemNowPlaying` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `preferSpotifyAppleScript` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `preferBrowserMedia` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `browserMediaDetectionEnabled` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `youtubeMetadataEnrichmentEnabled` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showFileThumbnails` | VISUAL | File Tray Preview |  |
| `showFileExtensions` | VISUAL | File Tray Preview |  |
| `showFileCountBadge` | VISUAL | File Tray Preview |  |
| `airDropZoneEnabled` | VISUAL (no preview, justified) | — | The AirDrop drop zone is part of the Tray page layout; the preview shows tiles and quick actions. |
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
| `timerPresetsEnabled` | VISUAL | Timer Preview |  |
| `timerPreset1Minutes` | VISUAL | Timer Preview |  |
| `timerPreset2Minutes` | VISUAL | Timer Preview |  |
| `timerPreset3Minutes` | VISUAL | Timer Preview |  |
| `showTimerProgressRing` | VISUAL | Live Activity Layout Preview |  |
| `timerRingAnimationEnabled` | VISUAL | Live Activity Layout Preview |  |
| `timerEnabled` | BEHAVIORAL | — | Timer behavior and alerts. |
| `timerSoundEnabled` | BEHAVIORAL | — | Timer behavior and alerts. |
| `timerNotificationEnabled` | BEHAVIORAL | — | Timer behavior and alerts. |
| `collapseAfterStartingTimer` | BEHAVIORAL | — | Timer behavior and alerts. |
| `keepIslandExpandedWhenTimerRunning` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showTimerInCollapsedIsland` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
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
| `animateStatsCharts` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `pauseStatsDuringShellMorph` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `activitiesEnabled` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `activitiesRefreshIntervalSeconds` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showRunningAppsActivity` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showDownloadsActivity` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showCalendarActivity` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showNowPlayingActivity` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
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
| `liveActivityStyle` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showCalendarLiveActivity` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showDownloadsLiveActivity` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `liveActivityAutoDismissEnabled` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `liveActivityAutoDismissSeconds` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `liveActivityAnimationEnabled` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
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
| `showGestureHints` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `gesturePrivacyMode` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `disableVisualizerDuringMorph` | BEHAVIORAL | — | Performance behavior during shell morph. |
| `verboseUILogsEnabled` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showDebugFrames` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `showHitTestRegionDebug` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `disableThumbnailsDuringMorph` | NO PRODUCTION READER | — | Shown in Settings, but no production code reads it; it has no effect today. |
| `rightWorkspace.pageOrder` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.hiddenPages` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.defaultPage` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.indicatorStyle` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.toolOrder` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.hiddenTools` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.sectionOrder` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.hiddenSections` | VISUAL | Right Workspace Preview |  |
| `rightWorkspace.swipeEnabled` | BEHAVIORAL | — | Two-finger paging over the right half. |
| `spotify.webAPI.clientID` | EXTERNAL INTEGRATION | — | Spotify Web API client; connection state and errors shown in Right Workspace settings. |
