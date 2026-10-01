import Foundation
import SwiftUI

public enum AutoCollapseDelayPreset: String, CaseIterable, Identifiable {
    case fast
    case normal
    case relaxed
    case manual

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .relaxed: "Relaxed"
        case .manual: "Manual"
        }
    }

    public var impliedSeconds: Double {
        switch self {
        case .fast: 0.18
        case .normal: 0.30
        case .relaxed: 0.48
        case .manual: 0.30
        }
    }
}

public enum IslandThemeStyle: String, CaseIterable, Identifiable {
    case classicBlack
    case liquidGlass

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classicBlack: "Classic Black"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

public enum VisualizerAccentMode: String, CaseIterable, Identifiable {
    case artwork
    case white
    case system

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .artwork: "Artwork"
        case .white: "White"
        case .system: "System"
        }
    }
}

public enum AnimationPreset: String, CaseIterable, Identifiable {
    case subtle
    case normal
    case slow
    case instant

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .subtle: "Subtle"
        case .normal: "Normal"
        case .slow: "Slow"
        case .instant: "Instant"
        }
    }

    public var shellDuration: Double {
        switch self {
        case .subtle: 0.28
        case .normal: 0.40
        case .slow: 0.54
        case .instant: 0.01
        }
    }
}

public enum DefaultExpandedTab: String, CaseIterable, Identifiable {
    case island
    case tray
    case timer
    case stats
    case activities
    case liveActivities
    case gestures

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .island: "Island"
        case .tray: "Tray"
        case .timer: "Timer"
        case .stats: "Stats"
        case .activities: "Activities"
        case .liveActivities: "Live Activities"
        case .gestures: "Gestures"
        }
    }
}

public enum LiveActivityStyle: String, CaseIterable, Identifiable {
    case compact
    case detailed

    public var id: String { rawValue }
}

public enum GestureInputSource: String, CaseIterable, Identifiable {
    case camera
    case trackpad
    case keyboardShortcut
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .camera: "Camera (Coming Soon)"
        case .trackpad: "Pointer / Trackpad"
        case .keyboardShortcut: "Keyboard Shortcut"
        case .none: "None"
        }
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    @Published public var overlayEnabled: Bool { didSet { save(overlayEnabled, for: Key.overlayEnabled) } }
    @Published public var launchAtLoginEnabled: Bool { didSet { save(launchAtLoginEnabled, for: Key.launchAtLoginEnabled) } }
    @Published public var startCollapsedOnLaunch: Bool { didSet { save(startCollapsedOnLaunch, for: Key.startCollapsedOnLaunch) } }
    @Published public var expandOnHover: Bool { didSet { save(expandOnHover, for: Key.expandOnHover) } }
    @Published public var expandOnClick: Bool { didSet { save(expandOnClick, for: Key.expandOnClick) } }
    @Published public var collapseOnMouseLeave: Bool { didSet { save(collapseOnMouseLeave, for: Key.collapseOnMouseLeave) } }
    @Published public var autoCollapseEnabled: Bool { didSet { save(autoCollapseEnabled, for: Key.autoCollapseEnabled) } }
    @Published public var autoCollapseDelayPreset: AutoCollapseDelayPreset { didSet { save(autoCollapseDelayPreset.rawValue, for: Key.autoCollapseDelayPreset) } }
    @Published public var autoCollapseGraceSeconds: Double {
        didSet { normalizeAutoCollapseGrace(oldValue: oldValue) }
    }
    @Published public var collapsedWidth: Double {
        didSet { normalizeCollapsedWidth(oldValue: oldValue) }
    }
    @Published public var collapsedHeight: Double {
        didSet { normalizeCollapsedHeight(oldValue: oldValue) }
    }
    @Published public var expandedWidth: Double {
        didSet { normalizeExpandedWidth(oldValue: oldValue) }
    }
    @Published public var expandedHeight: Double {
        didSet { normalizeExpandedHeight(oldValue: oldValue) }
    }
    @Published public var useAdaptiveNotchSizing: Bool { didSet { save(useAdaptiveNotchSizing, for: Key.useAdaptiveNotchSizing) } }
    @Published public var respectHardwareNotch: Bool { didSet { save(respectHardwareNotch, for: Key.respectHardwareNotch) } }

    @Published public var islandThemeStyle: IslandThemeStyle { didSet { save(islandThemeStyle.rawValue, for: Key.islandThemeStyle) } }
    @Published public var shellOpacity: Double { didSet { normalizeShellOpacity(oldValue: oldValue) } }
    @Published public var shellStrokeEnabled: Bool { didSet { save(shellStrokeEnabled, for: Key.shellStrokeEnabled) } }
    @Published public var useArtworkAccentColor: Bool { didSet { save(useArtworkAccentColor, for: Key.useArtworkAccentColor) } }
    @Published public var visualizerAccentMode: VisualizerAccentMode { didSet { save(visualizerAccentMode.rawValue, for: Key.visualizerAccentMode) } }
    @Published public var showCollapsedVisualizer: Bool { didSet { save(showCollapsedVisualizer, for: Key.showCollapsedVisualizer) } }
    @Published public var showExpandedVisualizer: Bool { didSet { save(showExpandedVisualizer, for: Key.showExpandedVisualizer) } }
    @Published public var collapsedHoverPreviewEnabled: Bool { didSet { save(collapsedHoverPreviewEnabled, for: Key.collapsedHoverPreviewEnabled) } }
    @Published public var collapsedHoverPreviewMediaEnabled: Bool { didSet { save(collapsedHoverPreviewMediaEnabled, for: Key.collapsedHoverPreviewMediaEnabled) } }
    @Published public var collapsedHoverPreviewHeight: Double {
        didSet { normalizeCollapsedHoverPreviewHeight(oldValue: oldValue) }
    }
    @Published public var collapsedHoverPreviewDelay: Double {
        didSet { normalizeCollapsedHoverPreviewDelay(oldValue: oldValue) }
    }
    @Published public var collapsedHoverPreviewShowTitle: Bool { didSet { save(collapsedHoverPreviewShowTitle, for: Key.collapsedHoverPreviewShowTitle) } }
    @Published public var collapsedHoverPreviewShowsArtist: Bool { didSet { save(collapsedHoverPreviewShowsArtist, for: Key.collapsedHoverPreviewShowsArtist) } }
    @Published public var collapsedHoverPreviewShowsSource: Bool { didSet { save(collapsedHoverPreviewShowsSource, for: Key.collapsedHoverPreviewShowsSource) } }
    @Published public var collapsedHoverPreviewTitleIconName: String { didSet { save(collapsedHoverPreviewTitleIconName, for: Key.collapsedHoverPreviewTitleIconName) } }
    @Published public var collapsedHoverPreviewArtistIconName: String { didSet { save(collapsedHoverPreviewArtistIconName, for: Key.collapsedHoverPreviewArtistIconName) } }

    @Published public var animationPreset: AnimationPreset { didSet { save(animationPreset.rawValue, for: Key.animationPreset) } }
    @Published public var reduceExtraMotion: Bool { didSet { save(reduceExtraMotion, for: Key.reduceExtraMotion) } }
    @Published public var shellAnimationSpeed: Double {
        didSet { normalizeShellAnimationSpeed(oldValue: oldValue) }
    }
    @Published public var contentAnimationEnabled: Bool { didSet { save(contentAnimationEnabled, for: Key.contentAnimationEnabled) } }
    @Published public var contentStaggerEnabled: Bool { didSet { save(contentStaggerEnabled, for: Key.contentStaggerEnabled) } }
    @Published public var contentStaggerAmount: Double {
        didSet { normalizeContentStaggerAmount(oldValue: oldValue) }
    }
    @Published public var useBlurTransitions: Bool { didSet { save(useBlurTransitions, for: Key.useBlurTransitions) } }
    @Published public var useScaleTransitions: Bool { didSet { save(useScaleTransitions, for: Key.useScaleTransitions) } }

    @Published public var showIslandTab: Bool {
        didSet {
            guard !isNormalizingSettings else { return }
            if !showIslandTab {
                isNormalizingSettings = true
                defer { isNormalizingSettings = false }
                showIslandTab = true
            }
            save(showIslandTab, for: Key.showIslandTab)
        }
    }
    @Published public var showTrayTab: Bool { didSet { save(showTrayTab, for: Key.showTrayTab) } }
    @Published public var showTimerTab: Bool { didSet { save(showTimerTab, for: Key.showTimerTab) } }
    @Published public var showStatsTab: Bool { didSet { save(showStatsTab, for: Key.showStatsTab) } }
    @Published public var showToolsTab: Bool { didSet { save(showToolsTab, for: Key.showToolsTab) } }
    @Published public var showAgentsTab: Bool { didSet { save(showAgentsTab, for: Key.showAgentsTab) } }
    @Published public var showActivitiesTab: Bool { didSet { save(showActivitiesTab, for: Key.showActivitiesTab) } }
    @Published public var showLiveActivitiesTab: Bool { didSet { save(showLiveActivitiesTab, for: Key.showLiveActivitiesTab) } }
    @Published public var showGesturesTab: Bool { didSet { save(showGesturesTab, for: Key.showGesturesTab) } }
    @Published public var rememberLastSelectedTab: Bool { didSet { save(rememberLastSelectedTab, for: Key.rememberLastSelectedTab) } }
    @Published public var defaultExpandedTab: DefaultExpandedTab { didSet { save(defaultExpandedTab.rawValue, for: Key.defaultExpandedTab) } }

    @Published public var agentActivityEnabled: Bool { didSet { save(agentActivityEnabled, for: Key.agentActivityEnabled) } }
    @Published public var agentCompletionAlertsEnabled: Bool { didSet { save(agentCompletionAlertsEnabled, for: Key.agentCompletionAlertsEnabled) } }
    @Published public var agentApprovalAlertsEnabled: Bool { didSet { save(agentApprovalAlertsEnabled, for: Key.agentApprovalAlertsEnabled) } }
    @Published public var agentSoundsEnabled: Bool { didSet { save(agentSoundsEnabled, for: Key.agentSoundsEnabled) } }
    @Published public var agentUsageMetricsEnabled: Bool { didSet { save(agentUsageMetricsEnabled, for: Key.agentUsageMetricsEnabled) } }
    /// Record Activities: explicit opt-in, local normalized events only.
    @Published public var agentActivityRecordingEnabled: Bool { didSet { save(agentActivityRecordingEnabled, for: Key.agentActivityRecordingEnabled) } }
    @Published public var agentPeekDurationSeconds: Double { didSet { save(agentPeekDurationSeconds, for: Key.agentPeekDurationSeconds) } }

    @Published public var mediaEnabled: Bool { didSet { save(mediaEnabled, for: Key.mediaEnabled) } }
    @Published public var showMediaWhenPaused: Bool { didSet { save(showMediaWhenPaused, for: Key.showMediaWhenPaused) } }
    @Published public var showMediaWhenNoSource: Bool { didSet { save(showMediaWhenNoSource, for: Key.showMediaWhenNoSource) } }
    @Published public var showAlbumArtwork: Bool { didSet { save(showAlbumArtwork, for: Key.showAlbumArtwork) } }
    @Published public var showMediaTitle: Bool { didSet { save(showMediaTitle, for: Key.showMediaTitle) } }
    @Published public var showMediaArtist: Bool { didSet { save(showMediaArtist, for: Key.showMediaArtist) } }
    @Published public var showMediaSourceName: Bool { didSet { save(showMediaSourceName, for: Key.showMediaSourceName) } }
    @Published public var showPlaybackControls: Bool { didSet { save(showPlaybackControls, for: Key.showPlaybackControls) } }
    @Published public var showProgressSlider: Bool { didSet { save(showProgressSlider, for: Key.showProgressSlider) } }
    @Published public var showVolumeSlider: Bool { didSet { save(showVolumeSlider, for: Key.showVolumeSlider) } }
    @Published public var showVisualizer: Bool { didSet { save(showVisualizer, for: Key.showVisualizer) } }
    @Published public var openSourceOnArtworkClick: Bool { didSet { save(openSourceOnArtworkClick, for: Key.openSourceOnArtworkClick) } }
    @Published public var collapseAfterOpeningMediaSource: Bool { didSet { save(collapseAfterOpeningMediaSource, for: Key.collapseAfterOpeningMediaSource) } }
    @Published public var collapseAfterMediaLauncher: Bool { didSet { save(collapseAfterMediaLauncher, for: Key.collapseAfterMediaLauncher) } }
    @Published public var mediaLauncherEnabled: Bool { didSet { save(mediaLauncherEnabled, for: Key.mediaLauncherEnabled) } }
    @Published public var showAppleMusicLauncher: Bool { didSet { save(showAppleMusicLauncher, for: Key.showAppleMusicLauncher) } }
    @Published public var showSpotifyLauncher: Bool { didSet { save(showSpotifyLauncher, for: Key.showSpotifyLauncher) } }
    @Published public var showYouTubeLauncher: Bool { didSet { save(showYouTubeLauncher, for: Key.showYouTubeLauncher) } }
    @Published public var preferSystemNowPlaying: Bool { didSet { save(preferSystemNowPlaying, for: Key.preferSystemNowPlaying) } }
    @Published public var preferSpotifyAppleScript: Bool { didSet { save(preferSpotifyAppleScript, for: Key.preferSpotifyAppleScript) } }
    @Published public var preferBrowserMedia: Bool { didSet { save(preferBrowserMedia, for: Key.preferBrowserMedia) } }
    @Published public var browserMediaDetectionEnabled: Bool { didSet { save(browserMediaDetectionEnabled, for: Key.browserMediaDetectionEnabled) } }
    @Published public var youtubeMetadataEnrichmentEnabled: Bool { didSet { save(youtubeMetadataEnrichmentEnabled, for: Key.youtubeMetadataEnrichmentEnabled) } }

    @Published public var trayEnabled: Bool { didSet { save(trayEnabled, for: Key.trayEnabled) } }
    @Published public var fileShelfEnabled: Bool { didSet { save(fileShelfEnabled, for: Key.fileShelfEnabled) } }
    @Published public var airDropZoneEnabled: Bool { didSet { save(airDropZoneEnabled, for: Key.airDropZoneEnabled) } }
    @Published public var allowFileDropsOnCollapsedIsland: Bool { didSet { save(allowFileDropsOnCollapsedIsland, for: Key.allowFileDropsOnCollapsedIsland) } }
    @Published public var allowFileDropsOnExpandedTray: Bool { didSet { save(allowFileDropsOnExpandedTray, for: Key.allowFileDropsOnExpandedTray) } }
    @Published public var maxShelfFiles: Int {
        didSet { normalizeMaxShelfFiles(oldValue: oldValue) }
    }
    @Published public var persistFileShelfAcrossLaunches: Bool { didSet { save(persistFileShelfAcrossLaunches, for: Key.persistFileShelfAcrossLaunches) } }
    @Published public var showFileThumbnails: Bool { didSet { save(showFileThumbnails, for: Key.showFileThumbnails) } }
    @Published public var deferThumbnailsDuringMorph: Bool { didSet { save(deferThumbnailsDuringMorph, for: Key.deferThumbnailsDuringMorph) } }
    @Published public var showFileExtensions: Bool { didSet { save(showFileExtensions, for: Key.showFileExtensions) } }
    @Published public var showFileCountBadge: Bool { didSet { save(showFileCountBadge, for: Key.showFileCountBadge) } }
    /// Floating Basket (Droppy parity). Shake a real file drag to summon it.
    @Published public var floatingBasketEnabled: Bool { didSet { save(floatingBasketEnabled, for: Key.floatingBasketEnabled) } }
    /// 1...5, higher = fewer direction reversals needed (Droppy default 3).
    @Published public var basketJiggleSensitivity: Int {
        didSet { normalizeAndSaveInt(\.basketJiggleSensitivity, oldValue: oldValue, fallback: 3, range: 1...5, key: Key.basketJiggleSensitivity) }
    }
    @Published public var basketMultipleEnabled: Bool { didSet { save(basketMultipleEnabled, for: Key.basketMultipleEnabled) } }
    @Published public var basketAutoHideEnabled: Bool { didSet { save(basketAutoHideEnabled, for: Key.basketAutoHideEnabled) } }
    @Published public var basketAutoHideDelay: Double {
        didSet { normalizeAndSaveDouble(\.basketAutoHideDelay, oldValue: oldValue, fallback: 2.0, range: 0.5...10.0, key: Key.basketAutoHideDelay) }
    }
    @Published public var confirmBeforeClearShelf: Bool { didSet { save(confirmBeforeClearShelf, for: Key.confirmBeforeClearShelf) } }
    @Published public var revealInFinderActionEnabled: Bool { didSet { save(revealInFinderActionEnabled, for: Key.revealInFinderActionEnabled) } }
    @Published public var copyPathActionEnabled: Bool { didSet { save(copyPathActionEnabled, for: Key.copyPathActionEnabled) } }
    @Published public var removeFileActionEnabled: Bool { didSet { save(removeFileActionEnabled, for: Key.removeFileActionEnabled) } }
    @Published public var openFileActionEnabled: Bool { didSet { save(openFileActionEnabled, for: Key.openFileActionEnabled) } }
    @Published public var airDropFallbackRevealInFinder: Bool { didSet { save(airDropFallbackRevealInFinder, for: Key.airDropFallbackRevealInFinder) } }

    @Published public var timerEnabled: Bool { didSet { save(timerEnabled, for: Key.timerEnabled) } }
    @Published public var timerPresetsEnabled: Bool { didSet { save(timerPresetsEnabled, for: Key.timerPresetsEnabled) } }
    @Published public var timerPreset1Minutes: Int {
        didSet { normalizeTimerPreset1(oldValue: oldValue) }
    }
    @Published public var timerPreset2Minutes: Int {
        didSet { normalizeTimerPreset2(oldValue: oldValue) }
    }
    @Published public var timerPreset3Minutes: Int {
        didSet { normalizeTimerPreset3(oldValue: oldValue) }
    }
    @Published public var timerSoundEnabled: Bool { didSet { save(timerSoundEnabled, for: Key.timerSoundEnabled) } }
    @Published public var timerNotificationEnabled: Bool { didSet { save(timerNotificationEnabled, for: Key.timerNotificationEnabled) } }
    @Published public var collapseAfterStartingTimer: Bool { didSet { save(collapseAfterStartingTimer, for: Key.collapseAfterStartingTimer) } }
    @Published public var keepIslandExpandedWhenTimerRunning: Bool { didSet { save(keepIslandExpandedWhenTimerRunning, for: Key.keepIslandExpandedWhenTimerRunning) } }
    @Published public var showTimerInCollapsedIsland: Bool { didSet { save(showTimerInCollapsedIsland, for: Key.showTimerInCollapsedIsland) } }
    @Published public var showTimerProgressRing: Bool { didSet { save(showTimerProgressRing, for: Key.showTimerProgressRing) } }
    @Published public var timerRingAnimationEnabled: Bool { didSet { save(timerRingAnimationEnabled, for: Key.timerRingAnimationEnabled) } }

    @Published public var statsEnabled: Bool { didSet { save(statsEnabled, for: Key.statsEnabled) } }
    @Published public var statsRefreshIntervalSeconds: Double {
        didSet { normalizeStatsRefreshInterval(oldValue: oldValue) }
    }
    @Published public var showCPU: Bool { didSet { save(showCPU, for: Key.showCPU) } }
    @Published public var showMemory: Bool { didSet { save(showMemory, for: Key.showMemory) } }
    @Published public var showGPU: Bool { didSet { save(showGPU, for: Key.showGPU) } }
    @Published public var showNetwork: Bool { didSet { save(showNetwork, for: Key.showNetwork) } }
    @Published public var showDisk: Bool { didSet { save(showDisk, for: Key.showDisk) } }
    @Published public var showBattery: Bool { didSet { save(showBattery, for: Key.showBattery) } }
    @Published public var showUptime: Bool { didSet { save(showUptime, for: Key.showUptime) } }
    @Published public var animateStatsCharts: Bool { didSet { save(animateStatsCharts, for: Key.animateStatsCharts) } }
    @Published public var pauseStatsDuringShellMorph: Bool { didSet { save(pauseStatsDuringShellMorph, for: Key.pauseStatsDuringShellMorph) } }
    @Published public var showActivityIndicator: Bool { didSet { save(showActivityIndicator, for: Key.showActivityIndicator) } }
    @Published public var activitiesEnabled: Bool { didSet { save(activitiesEnabled, for: Key.activitiesEnabled) } }
    @Published public var activitiesRefreshIntervalSeconds: Double {
        didSet { normalizeActivitiesRefreshInterval(oldValue: oldValue) }
    }
    @Published public var showRunningAppsActivity: Bool { didSet { save(showRunningAppsActivity, for: Key.showRunningAppsActivity) } }
    @Published public var showDownloadsActivity: Bool { didSet { save(showDownloadsActivity, for: Key.showDownloadsActivity) } }
    @Published public var showCalendarActivity: Bool { didSet { save(showCalendarActivity, for: Key.showCalendarActivity) } }
    @Published public var showNowPlayingActivity: Bool { didSet { save(showNowPlayingActivity, for: Key.showNowPlayingActivity) } }

    @Published public var clipboardHistoryEnabled: Bool { didSet { save(clipboardHistoryEnabled, for: Key.clipboardHistoryEnabled) } }
    @Published public var clipboardHistoryMaximumItems: Int {
        didSet { normalizeClipboardHistoryMaximumItems(oldValue: oldValue) }
    }
    @Published public var clipboardHistoryPersistenceEnabled: Bool { didSet { save(clipboardHistoryPersistenceEnabled, for: Key.clipboardHistoryPersistenceEnabled) } }
    @Published public var clipboardHistoryCaptureImagesEnabled: Bool { didSet { save(clipboardHistoryCaptureImagesEnabled, for: Key.clipboardHistoryCaptureImagesEnabled) } }

    @Published public var liveActivitiesEnabled: Bool { didSet { save(liveActivitiesEnabled, for: Key.liveActivitiesEnabled) } }
    @Published public var showExpandedLiveActivitiesSection: Bool {
        didSet {
            save(showExpandedLiveActivitiesSection, for: Key.showExpandedLiveActivitiesSection)
        }
    }
    @Published public var liveActivityStyle: LiveActivityStyle { didSet { save(liveActivityStyle.rawValue, for: Key.liveActivityStyle) } }
    @Published public var showMusicLiveActivity: Bool { didSet { save(showMusicLiveActivity, for: Key.showMusicLiveActivity) } }
    @Published public var showTimerLiveActivity: Bool { didSet { save(showTimerLiveActivity, for: Key.showTimerLiveActivity) } }
    @Published public var showFileDropLiveActivity: Bool { didSet { save(showFileDropLiveActivity, for: Key.showFileDropLiveActivity) } }
    @Published public var showBatteryLiveActivity: Bool { didSet { save(showBatteryLiveActivity, for: Key.showBatteryLiveActivity) } }
    @Published public var showCalendarLiveActivity: Bool { didSet { save(showCalendarLiveActivity, for: Key.showCalendarLiveActivity) } }
    @Published public var showDownloadsLiveActivity: Bool { didSet { save(showDownloadsLiveActivity, for: Key.showDownloadsLiveActivity) } }
    @Published public var liveActivityAutoDismissEnabled: Bool { didSet { save(liveActivityAutoDismissEnabled, for: Key.liveActivityAutoDismissEnabled) } }
    @Published public var liveActivityAutoDismissSeconds: Double {
        didSet { normalizeLiveActivityDismiss(oldValue: oldValue) }
    }
    @Published public var liveActivityAnimationEnabled: Bool { didSet { save(liveActivityAnimationEnabled, for: Key.liveActivityAnimationEnabled) } }
    @Published public var allowSimultaneousLiveActivitySidecars: Bool {
        didSet { save(allowSimultaneousLiveActivitySidecars, for: Key.allowSimultaneousLiveActivitySidecars) }
    }
    @Published public var timerSidecarPreference: LiveActivitySidePreference {
        didSet { save(timerSidecarPreference.rawValue, for: Key.timerSidecarPreference) }
    }
    @Published public var systemHUDsEnabled: Bool { didSet { save(systemHUDsEnabled, for: Key.systemHUDsEnabled) } }
    @Published public var replaceMacOSSystemHUDs: Bool { didSet { save(replaceMacOSSystemHUDs, for: Key.replaceMacOSSystemHUDs) } }
    @Published public var volumeHUDEnabled: Bool { didSet { save(volumeHUDEnabled, for: Key.volumeHUDEnabled) } }
    @Published public var brightnessHUDEnabled: Bool { didSet { save(brightnessHUDEnabled, for: Key.brightnessHUDEnabled) } }
    @Published public var capsLockHUDEnabled: Bool { didSet { save(capsLockHUDEnabled, for: Key.capsLockHUDEnabled) } }
    @Published public var batteryStatusHUDEnabled: Bool { didSet { save(batteryStatusHUDEnabled, for: Key.batteryStatusHUDEnabled) } }
    @Published public var lowBatteryHUDEnabled: Bool { didSet { save(lowBatteryHUDEnabled, for: Key.lowBatteryHUDEnabled) } }
    @Published public var audioDeviceHUDEnabled: Bool { didSet { save(audioDeviceHUDEnabled, for: Key.audioDeviceHUDEnabled) } }
    @Published public var focusHUDEnabled: Bool { didSet { save(focusHUDEnabled, for: Key.focusHUDEnabled) } }
    @Published public var systemHUDDurationSeconds: Double { didSet { save(systemHUDDurationSeconds, for: Key.systemHUDDurationSeconds) } }
    @Published public var collapsedPriorityRunningTimer: Int {
        didSet { normalizeCollapsedPriorityRunningTimer(oldValue: oldValue) }
    }
    @Published public var collapsedPriorityPlayingMedia: Int {
        didSet { normalizeCollapsedPriorityPlayingMedia(oldValue: oldValue) }
    }
    @Published public var collapsedPriorityPausedTimer: Int {
        didSet { normalizeCollapsedPriorityPausedTimer(oldValue: oldValue) }
    }
    @Published public var collapsedPriorityRecentFiles: Int {
        didSet { normalizeCollapsedPriorityRecentFiles(oldValue: oldValue) }
    }
    @Published public var collapsedPriorityPausedMedia: Int {
        didSet { normalizeCollapsedPriorityPausedMedia(oldValue: oldValue) }
    }

    @Published public var gesturesEnabled: Bool { didSet { save(gesturesEnabled, for: Key.gesturesEnabled) } }
    @Published public var gestureInputSource: GestureInputSource { didSet { save(gestureInputSource.rawValue, for: Key.gestureInputSource) } }
    @Published public var expandGestureEnabled: Bool { didSet { save(expandGestureEnabled, for: Key.expandGestureEnabled) } }
    @Published public var collapseGestureEnabled: Bool { didSet { save(collapseGestureEnabled, for: Key.collapseGestureEnabled) } }
    @Published public var nextTabGestureEnabled: Bool { didSet { save(nextTabGestureEnabled, for: Key.nextTabGestureEnabled) } }
    @Published public var previousTabGestureEnabled: Bool { didSet { save(previousTabGestureEnabled, for: Key.previousTabGestureEnabled) } }
    @Published public var mediaPlayPauseGestureEnabled: Bool { didSet { save(mediaPlayPauseGestureEnabled, for: Key.mediaPlayPauseGestureEnabled) } }
    @Published public var timerStartStopGestureEnabled: Bool { didSet { save(timerStartStopGestureEnabled, for: Key.timerStartStopGestureEnabled) } }
    @Published public var collapsedDoubleClickAction: IslandGestureAction { didSet { save(collapsedDoubleClickAction.rawValue, for: Key.collapsedDoubleClickAction) } }
    @Published public var collapsedSwipeDownAction: IslandGestureAction { didSet { save(collapsedSwipeDownAction.rawValue, for: Key.collapsedSwipeDownAction) } }
    @Published public var collapsedSwipeUpAction: IslandGestureAction { didSet { save(collapsedSwipeUpAction.rawValue, for: Key.collapsedSwipeUpAction) } }
    @Published public var collapsedSwipeLeftAction: IslandGestureAction { didSet { save(collapsedSwipeLeftAction.rawValue, for: Key.collapsedSwipeLeftAction) } }
    @Published public var collapsedSwipeRightAction: IslandGestureAction { didSet { save(collapsedSwipeRightAction.rawValue, for: Key.collapsedSwipeRightAction) } }
    @Published public var collapsedLongPressAction: IslandGestureAction { didSet { save(collapsedLongPressAction.rawValue, for: Key.collapsedLongPressAction) } }
    @Published public var expandedDoubleClickAction: IslandGestureAction { didSet { save(expandedDoubleClickAction.rawValue, for: Key.expandedDoubleClickAction) } }
    @Published public var expandedSwipeDownAction: IslandGestureAction { didSet { save(expandedSwipeDownAction.rawValue, for: Key.expandedSwipeDownAction) } }
    @Published public var expandedSwipeUpAction: IslandGestureAction { didSet { save(expandedSwipeUpAction.rawValue, for: Key.expandedSwipeUpAction) } }
    @Published public var expandedSwipeLeftAction: IslandGestureAction { didSet { save(expandedSwipeLeftAction.rawValue, for: Key.expandedSwipeLeftAction) } }
    @Published public var expandedSwipeRightAction: IslandGestureAction { didSet { save(expandedSwipeRightAction.rawValue, for: Key.expandedSwipeRightAction) } }
    @Published public var expandedLongPressAction: IslandGestureAction { didSet { save(expandedLongPressAction.rawValue, for: Key.expandedLongPressAction) } }
    @Published public var gestureSensitivity: Double {
        didSet { normalizeGestureSensitivity(oldValue: oldValue) }
    }
    @Published public var gestureCooldownSeconds: Double {
        didSet { normalizeGestureCooldown(oldValue: oldValue) }
    }
    @Published public var showGestureHints: Bool { didSet { save(showGestureHints, for: Key.showGestureHints) } }
    @Published public var requireGestureConfirmation: Bool { didSet { save(requireGestureConfirmation, for: Key.requireGestureConfirmation) } }
    @Published public var gesturePrivacyMode: Bool { didSet { save(gesturePrivacyMode, for: Key.gesturePrivacyMode) } }

    @Published public var verboseUILogsEnabled: Bool { didSet { save(verboseUILogsEnabled, for: Key.verboseUILogsEnabled) } }
    @Published public var showDebugFrames: Bool { didSet { save(showDebugFrames, for: Key.showDebugFrames) } }
    @Published public var showHitTestRegionDebug: Bool { didSet { save(showHitTestRegionDebug, for: Key.showHitTestRegionDebug) } }
    @Published public var disableVisualizerDuringMorph: Bool { didSet { save(disableVisualizerDuringMorph, for: Key.disableVisualizerDuringMorph) } }
    @Published public var disableThumbnailsDuringMorph: Bool { didSet { save(disableThumbnailsDuringMorph, for: Key.disableThumbnailsDuringMorph) } }

    private let defaults: UserDefaults
    private var isNormalizingSettings = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        overlayEnabled = Self.bool(defaults, Key.overlayEnabled, true)
        launchAtLoginEnabled = Self.bool(defaults, Key.launchAtLoginEnabled, false)
        startCollapsedOnLaunch = Self.bool(defaults, Key.startCollapsedOnLaunch, true)
        expandOnHover = Self.bool(defaults, Key.expandOnHover, false)
        expandOnClick = Self.bool(defaults, Key.expandOnClick, true)
        collapseOnMouseLeave = Self.bool(defaults, Key.collapseOnMouseLeave, true)
        autoCollapseEnabled = Self.bool(defaults, Key.autoCollapseEnabled, true)
        autoCollapseDelayPreset = Self.enumValue(defaults, Key.autoCollapseDelayPreset, .normal)
        autoCollapseGraceSeconds = Self.double(defaults, Key.autoCollapseGraceSeconds, 0.30)
        collapsedWidth = Self.double(defaults, Key.collapsedWidth, 190)
        collapsedHeight = Self.double(defaults, Key.collapsedHeight, 44)
        expandedWidth = Self.double(defaults, Key.expandedWidth, 860)
        expandedHeight = Self.double(defaults, Key.expandedHeight, 286)
        useAdaptiveNotchSizing = Self.bool(defaults, Key.useAdaptiveNotchSizing, true)
        respectHardwareNotch = Self.bool(defaults, Key.respectHardwareNotch, true)

        islandThemeStyle = Self.islandThemeStyleValue(defaults, Key.islandThemeStyle, .classicBlack)
        Self.migrateLegacyIslandThemeStyleIfNeeded(defaults, Key.islandThemeStyle)
        shellOpacity = Self.double(defaults, Key.shellOpacity, 1.0)
        shellStrokeEnabled = Self.bool(defaults, Key.shellStrokeEnabled, true)
        useArtworkAccentColor = Self.bool(defaults, Key.useArtworkAccentColor, true)
        visualizerAccentMode = Self.enumValue(defaults, Key.visualizerAccentMode, .artwork)
        showCollapsedVisualizer = Self.bool(defaults, Key.showCollapsedVisualizer, true)
        showExpandedVisualizer = Self.bool(defaults, Key.showExpandedVisualizer, true)
        collapsedHoverPreviewEnabled = Self.bool(defaults, Key.collapsedHoverPreviewEnabled, true)
        collapsedHoverPreviewMediaEnabled = Self.bool(defaults, Key.collapsedHoverPreviewMediaEnabled, true)
        collapsedHoverPreviewHeight = Self.double(defaults, Key.collapsedHoverPreviewHeight, 58)
        collapsedHoverPreviewDelay = Self.double(defaults, Key.collapsedHoverPreviewDelay, 0.08)
        collapsedHoverPreviewShowTitle = Self.bool(defaults, Key.collapsedHoverPreviewShowTitle, true)
        collapsedHoverPreviewShowsArtist = Self.bool(defaults, Key.collapsedHoverPreviewShowsArtist, true)
        collapsedHoverPreviewShowsSource = Self.bool(defaults, Key.collapsedHoverPreviewShowsSource, false)
        collapsedHoverPreviewTitleIconName = Self.string(defaults, Key.collapsedHoverPreviewTitleIconName, "music.mic")
        collapsedHoverPreviewArtistIconName = Self.string(defaults, Key.collapsedHoverPreviewArtistIconName, "person.fill")

        animationPreset = Self.enumValue(defaults, Key.animationPreset, .normal)
        reduceExtraMotion = Self.bool(defaults, Key.reduceExtraMotion, false)
        shellAnimationSpeed = Self.double(defaults, Key.shellAnimationSpeed, 1.0)
        contentAnimationEnabled = Self.bool(defaults, Key.contentAnimationEnabled, true)
        contentStaggerEnabled = Self.bool(defaults, Key.contentStaggerEnabled, true)
        contentStaggerAmount = Self.double(defaults, Key.contentStaggerAmount, 1.0)
        useBlurTransitions = Self.bool(defaults, Key.useBlurTransitions, true)
        useScaleTransitions = Self.bool(defaults, Key.useScaleTransitions, true)

        showIslandTab = true
        showTrayTab = Self.bool(defaults, Key.showTrayTab, true)
        showTimerTab = Self.bool(defaults, Key.showTimerTab, true)
        showStatsTab = Self.bool(defaults, Key.showStatsTab, true)
        showToolsTab = Self.bool(defaults, Key.showToolsTab, true)
        showAgentsTab = Self.bool(defaults, Key.showAgentsTab, true)
        agentActivityEnabled = Self.bool(defaults, Key.agentActivityEnabled, true)
        agentCompletionAlertsEnabled = Self.bool(defaults, Key.agentCompletionAlertsEnabled, true)
        agentApprovalAlertsEnabled = Self.bool(defaults, Key.agentApprovalAlertsEnabled, true)
        agentSoundsEnabled = Self.bool(defaults, Key.agentSoundsEnabled, true)
        agentUsageMetricsEnabled = Self.bool(defaults, Key.agentUsageMetricsEnabled, true)
        agentActivityRecordingEnabled = Self.bool(defaults, Key.agentActivityRecordingEnabled, false)
        agentPeekDurationSeconds = Self.double(defaults, Key.agentPeekDurationSeconds, 5.0)
        showActivitiesTab = Self.bool(defaults, Key.showActivitiesTab, false)
        showLiveActivitiesTab = Self.bool(defaults, Key.showLiveActivitiesTab, false)
        showGesturesTab = Self.bool(defaults, Key.showGesturesTab, false)
        rememberLastSelectedTab = Self.bool(defaults, Key.rememberLastSelectedTab, true)
        defaultExpandedTab = Self.enumValue(defaults, Key.defaultExpandedTab, .island)

        mediaEnabled = Self.bool(defaults, Key.mediaEnabled, true)
        showMediaWhenPaused = Self.bool(defaults, Key.showMediaWhenPaused, true)
        showMediaWhenNoSource = Self.bool(defaults, Key.showMediaWhenNoSource, true)
        showAlbumArtwork = Self.bool(defaults, Key.showAlbumArtwork, true)
        showMediaTitle = Self.bool(defaults, Key.showMediaTitle, true)
        showMediaArtist = Self.bool(defaults, Key.showMediaArtist, true)
        showMediaSourceName = Self.bool(defaults, Key.showMediaSourceName, true)
        showPlaybackControls = Self.bool(defaults, Key.showPlaybackControls, true)
        showProgressSlider = Self.bool(defaults, Key.showProgressSlider, true)
        showVolumeSlider = Self.bool(defaults, Key.showVolumeSlider, true)
        showVisualizer = Self.bool(defaults, Key.showVisualizer, true)
        openSourceOnArtworkClick = Self.bool(defaults, Key.openSourceOnArtworkClick, true)
        collapseAfterOpeningMediaSource = Self.bool(defaults, Key.collapseAfterOpeningMediaSource, true)
        collapseAfterMediaLauncher = Self.bool(defaults, Key.collapseAfterMediaLauncher, true)
        mediaLauncherEnabled = Self.bool(defaults, Key.mediaLauncherEnabled, true)
        showAppleMusicLauncher = Self.bool(defaults, Key.showAppleMusicLauncher, true)
        showSpotifyLauncher = Self.bool(defaults, Key.showSpotifyLauncher, true)
        showYouTubeLauncher = Self.bool(defaults, Key.showYouTubeLauncher, true)
        preferSystemNowPlaying = Self.bool(defaults, Key.preferSystemNowPlaying, true)
        preferSpotifyAppleScript = Self.bool(defaults, Key.preferSpotifyAppleScript, true)
        preferBrowserMedia = Self.bool(defaults, Key.preferBrowserMedia, true)
        browserMediaDetectionEnabled = Self.bool(defaults, Key.browserMediaDetectionEnabled, true)
        youtubeMetadataEnrichmentEnabled = Self.bool(defaults, Key.youtubeMetadataEnrichmentEnabled, true)

        trayEnabled = Self.bool(defaults, Key.trayEnabled, true)
        fileShelfEnabled = Self.bool(defaults, Key.fileShelfEnabled, true)
        airDropZoneEnabled = Self.bool(defaults, Key.airDropZoneEnabled, true)
        allowFileDropsOnCollapsedIsland = Self.bool(defaults, Key.allowFileDropsOnCollapsedIsland, true)
        allowFileDropsOnExpandedTray = Self.bool(defaults, Key.allowFileDropsOnExpandedTray, true)
        maxShelfFiles = Self.int(defaults, Key.maxShelfFiles, 12)
        persistFileShelfAcrossLaunches = Self.bool(defaults, Key.persistFileShelfAcrossLaunches, false)
        showFileThumbnails = Self.bool(defaults, Key.showFileThumbnails, true)
        deferThumbnailsDuringMorph = Self.bool(defaults, Key.deferThumbnailsDuringMorph, true)
        showFileExtensions = Self.bool(defaults, Key.showFileExtensions, true)
        showFileCountBadge = Self.bool(defaults, Key.showFileCountBadge, true)
        floatingBasketEnabled = Self.bool(defaults, Key.floatingBasketEnabled, true)
        basketJiggleSensitivity = Self.int(defaults, Key.basketJiggleSensitivity, 3)
        basketMultipleEnabled = Self.bool(defaults, Key.basketMultipleEnabled, true)
        basketAutoHideEnabled = Self.bool(defaults, Key.basketAutoHideEnabled, false)
        basketAutoHideDelay = Self.double(defaults, Key.basketAutoHideDelay, 2.0)
        confirmBeforeClearShelf = Self.bool(defaults, Key.confirmBeforeClearShelf, false)
        revealInFinderActionEnabled = Self.bool(defaults, Key.revealInFinderActionEnabled, true)
        copyPathActionEnabled = Self.bool(defaults, Key.copyPathActionEnabled, true)
        removeFileActionEnabled = Self.bool(defaults, Key.removeFileActionEnabled, true)
        openFileActionEnabled = Self.bool(defaults, Key.openFileActionEnabled, true)
        airDropFallbackRevealInFinder = Self.bool(defaults, Key.airDropFallbackRevealInFinder, true)

        timerEnabled = Self.bool(defaults, Key.timerEnabled, true)
        timerPresetsEnabled = Self.bool(defaults, Key.timerPresetsEnabled, true)
        timerPreset1Minutes = Self.int(defaults, Key.timerPreset1Minutes, 5)
        timerPreset2Minutes = Self.int(defaults, Key.timerPreset2Minutes, 10)
        timerPreset3Minutes = Self.int(defaults, Key.timerPreset3Minutes, 15)
        timerSoundEnabled = Self.bool(defaults, Key.timerSoundEnabled, false)
        timerNotificationEnabled = Self.bool(defaults, Key.timerNotificationEnabled, false)
        collapseAfterStartingTimer = Self.bool(defaults, Key.collapseAfterStartingTimer, false)
        keepIslandExpandedWhenTimerRunning = Self.bool(defaults, Key.keepIslandExpandedWhenTimerRunning, false)
        showTimerInCollapsedIsland = Self.bool(defaults, Key.showTimerInCollapsedIsland, false)
        showTimerProgressRing = Self.bool(defaults, Key.showTimerProgressRing, true)
        timerRingAnimationEnabled = Self.bool(defaults, Key.timerRingAnimationEnabled, true)

        statsEnabled = Self.bool(defaults, Key.statsEnabled, true)
        statsRefreshIntervalSeconds = Self.double(defaults, Key.statsRefreshIntervalSeconds, 2.0)
        showCPU = Self.bool(defaults, Key.showCPU, true)
        showMemory = Self.bool(defaults, Key.showMemory, true)
        showGPU = Self.bool(defaults, Key.showGPU, true)
        showNetwork = Self.bool(defaults, Key.showNetwork, true)
        showDisk = Self.bool(defaults, Key.showDisk, true)
        showBattery = Self.bool(defaults, Key.showBattery, true)
        showUptime = Self.bool(defaults, Key.showUptime, true)
        animateStatsCharts = Self.bool(defaults, Key.animateStatsCharts, true)
        pauseStatsDuringShellMorph = Self.bool(defaults, Key.pauseStatsDuringShellMorph, true)
        showActivityIndicator = Self.bool(defaults, Key.showActivityIndicator, true)
        activitiesEnabled = Self.bool(defaults, Key.activitiesEnabled, false)
        activitiesRefreshIntervalSeconds = Self.double(defaults, Key.activitiesRefreshIntervalSeconds, 3.0)
        showRunningAppsActivity = Self.bool(defaults, Key.showRunningAppsActivity, false)
        showDownloadsActivity = Self.bool(defaults, Key.showDownloadsActivity, false)
        showCalendarActivity = Self.bool(defaults, Key.showCalendarActivity, false)
        showNowPlayingActivity = Self.bool(defaults, Key.showNowPlayingActivity, false)
        clipboardHistoryEnabled = Self.bool(defaults, Key.clipboardHistoryEnabled, false)
        clipboardHistoryMaximumItems = Self.int(defaults, Key.clipboardHistoryMaximumItems, 50)
        clipboardHistoryPersistenceEnabled = Self.bool(defaults, Key.clipboardHistoryPersistenceEnabled, false)
        clipboardHistoryCaptureImagesEnabled = Self.bool(defaults, Key.clipboardHistoryCaptureImagesEnabled, true)

        liveActivitiesEnabled = Self.bool(defaults, Key.liveActivitiesEnabled, true)
        showExpandedLiveActivitiesSection = Self.bool(defaults, Key.showExpandedLiveActivitiesSection, true)
        liveActivityStyle = Self.enumValue(defaults, Key.liveActivityStyle, .compact)
        showMusicLiveActivity = Self.bool(defaults, Key.showMusicLiveActivity, true)
        showTimerLiveActivity = Self.bool(defaults, Key.showTimerLiveActivity, true)
        showFileDropLiveActivity = Self.bool(defaults, Key.showFileDropLiveActivity, true)
        showBatteryLiveActivity = Self.bool(defaults, Key.showBatteryLiveActivity, true)
        showCalendarLiveActivity = Self.bool(defaults, Key.showCalendarLiveActivity, false)
        showDownloadsLiveActivity = Self.bool(defaults, Key.showDownloadsLiveActivity, false)
        liveActivityAutoDismissEnabled = Self.bool(defaults, Key.liveActivityAutoDismissEnabled, true)
        liveActivityAutoDismissSeconds = Self.double(defaults, Key.liveActivityAutoDismissSeconds, 6.0)
        liveActivityAnimationEnabled = Self.bool(defaults, Key.liveActivityAnimationEnabled, true)
        allowSimultaneousLiveActivitySidecars = Self.bool(
            defaults,
            Key.allowSimultaneousLiveActivitySidecars,
            true
        )
        timerSidecarPreference = Self.enumValue(
            defaults,
            Key.timerSidecarPreference,
            .automatic
        )
        systemHUDsEnabled = Self.bool(defaults, Key.systemHUDsEnabled, true)
        replaceMacOSSystemHUDs = Self.bool(defaults, Key.replaceMacOSSystemHUDs, true)
        volumeHUDEnabled = Self.bool(defaults, Key.volumeHUDEnabled, true)
        brightnessHUDEnabled = Self.bool(defaults, Key.brightnessHUDEnabled, true)
        capsLockHUDEnabled = Self.bool(defaults, Key.capsLockHUDEnabled, true)
        batteryStatusHUDEnabled = Self.bool(defaults, Key.batteryStatusHUDEnabled, true)
        lowBatteryHUDEnabled = Self.bool(defaults, Key.lowBatteryHUDEnabled, true)
        audioDeviceHUDEnabled = Self.bool(defaults, Key.audioDeviceHUDEnabled, true)
        focusHUDEnabled = Self.bool(defaults, Key.focusHUDEnabled, false)
        systemHUDDurationSeconds = Self.double(defaults, Key.systemHUDDurationSeconds, 1.4)
        collapsedPriorityRunningTimer = Self.int(defaults, Key.collapsedPriorityRunningTimer, CollapsedLiveActivityPrioritySource.runningTimer.defaultPriority)
        collapsedPriorityPlayingMedia = Self.int(defaults, Key.collapsedPriorityPlayingMedia, CollapsedLiveActivityPrioritySource.playingMedia.defaultPriority)
        collapsedPriorityPausedTimer = Self.int(defaults, Key.collapsedPriorityPausedTimer, CollapsedLiveActivityPrioritySource.pausedTimer.defaultPriority)
        collapsedPriorityRecentFiles = Self.int(defaults, Key.collapsedPriorityRecentFiles, CollapsedLiveActivityPrioritySource.recentFiles.defaultPriority)
        collapsedPriorityPausedMedia = Self.int(defaults, Key.collapsedPriorityPausedMedia, CollapsedLiveActivityPrioritySource.pausedMedia.defaultPriority)

        gesturesEnabled = Self.bool(defaults, Key.gesturesEnabled, false)
        gestureInputSource = Self.enumValue(defaults, Key.gestureInputSource, .none)
        expandGestureEnabled = Self.bool(defaults, Key.expandGestureEnabled, true)
        collapseGestureEnabled = Self.bool(defaults, Key.collapseGestureEnabled, true)
        nextTabGestureEnabled = Self.bool(defaults, Key.nextTabGestureEnabled, true)
        previousTabGestureEnabled = Self.bool(defaults, Key.previousTabGestureEnabled, true)
        mediaPlayPauseGestureEnabled = Self.bool(defaults, Key.mediaPlayPauseGestureEnabled, true)
        timerStartStopGestureEnabled = Self.bool(defaults, Key.timerStartStopGestureEnabled, true)
        collapsedDoubleClickAction = Self.enumValue(defaults, Key.collapsedDoubleClickAction, .mediaPlayPause)
        collapsedSwipeDownAction = Self.enumValue(defaults, Key.collapsedSwipeDownAction, .expand)
        collapsedSwipeUpAction = Self.enumValue(defaults, Key.collapsedSwipeUpAction, .none)
        collapsedSwipeLeftAction = Self.enumValue(defaults, Key.collapsedSwipeLeftAction, .mediaNextTrack)
        collapsedSwipeRightAction = Self.enumValue(defaults, Key.collapsedSwipeRightAction, .mediaPreviousTrack)
        collapsedLongPressAction = Self.enumValue(defaults, Key.collapsedLongPressAction, .openSettings)
        expandedDoubleClickAction = Self.enumValue(defaults, Key.expandedDoubleClickAction, .none)
        expandedSwipeDownAction = Self.enumValue(defaults, Key.expandedSwipeDownAction, .none)
        expandedSwipeUpAction = Self.enumValue(defaults, Key.expandedSwipeUpAction, .collapse)
        expandedSwipeLeftAction = Self.enumValue(defaults, Key.expandedSwipeLeftAction, .nextTab)
        expandedSwipeRightAction = Self.enumValue(defaults, Key.expandedSwipeRightAction, .previousTab)
        expandedLongPressAction = Self.enumValue(defaults, Key.expandedLongPressAction, .openSettings)
        gestureSensitivity = Self.double(defaults, Key.gestureSensitivity, 0.5)
        gestureCooldownSeconds = Self.double(defaults, Key.gestureCooldownSeconds, 0.75)
        showGestureHints = Self.bool(defaults, Key.showGestureHints, true)
        requireGestureConfirmation = Self.bool(defaults, Key.requireGestureConfirmation, false)
        gesturePrivacyMode = Self.bool(defaults, Key.gesturePrivacyMode, true)

        verboseUILogsEnabled = Self.bool(defaults, Key.verboseUILogsEnabled, false)
        showDebugFrames = Self.bool(defaults, Key.showDebugFrames, false)
        showHitTestRegionDebug = Self.bool(defaults, Key.showHitTestRegionDebug, false)
        disableVisualizerDuringMorph = Self.bool(defaults, Key.disableVisualizerDuringMorph, true)
        disableThumbnailsDuringMorph = Self.bool(defaults, Key.disableThumbnailsDuringMorph, true)

        normalizeAll()
    }

    public var launchAtLogin: Bool {
        get { launchAtLoginEnabled }
        set { launchAtLoginEnabled = newValue }
    }

    public var animationIntensity: Double {
        get { shellAnimationSpeed }
        set { shellAnimationSpeed = newValue }
    }

    public var shortcutsEnabled: Bool {
        get { true }
        set {}
    }

    public var collapsedSize: CGSize {
        CGSize(
            width: normalizedDouble(collapsedWidth, fallback: 190, range: 120...360),
            height: normalizedDouble(collapsedHeight, fallback: 44, range: 28...64)
        )
    }

    public var expandedSize: CGSize {
        CGSize(
            width: normalizedDouble(expandedWidth, fallback: 860, range: 520...920),
            height: normalizedDouble(expandedHeight, fallback: 286, range: 180...360)
        )
    }

    public var effectiveAutoCollapseGraceSeconds: Double {
        guard autoCollapseEnabled else { return .infinity }
        switch autoCollapseDelayPreset {
        case .manual:
            return autoCollapseGraceSeconds
        case .fast, .normal, .relaxed:
            return autoCollapseDelayPreset.impliedSeconds
        }
    }

    public func resetAllSettings() {
        reset(keys: Key.allCases)
        reload()
        reset(keys: Key.clipboardHistoryKeys)
    }

    public func resetLayoutSettings() {
        reset(keys: [
            Key.collapsedWidth, Key.collapsedHeight, Key.expandedWidth, Key.expandedHeight,
            Key.useAdaptiveNotchSizing, Key.respectHardwareNotch,
            Key.collapsedHoverPreviewEnabled, Key.collapsedHoverPreviewHeight,
            Key.collapsedHoverPreviewDelay,
            Key.animationPreset, Key.reduceExtraMotion, Key.shellAnimationSpeed,
            Key.contentAnimationEnabled, Key.contentStaggerEnabled, Key.contentStaggerAmount,
            Key.useBlurTransitions, Key.useScaleTransitions
        ])
        reload()
    }

    public func resetModuleSettings() {
        reset(keys: [
            Key.showTrayTab, Key.showTimerTab, Key.showStatsTab, Key.showToolsTab, Key.showAgentsTab,
            Key.agentActivityEnabled, Key.agentCompletionAlertsEnabled, Key.agentApprovalAlertsEnabled,
            Key.agentSoundsEnabled, Key.agentUsageMetricsEnabled, Key.agentActivityRecordingEnabled,
            Key.agentPeekDurationSeconds,
            Key.defaultExpandedTab,
            Key.mediaEnabled, Key.showMediaWhenPaused, Key.showMediaWhenNoSource,
            Key.showAlbumArtwork, Key.showMediaTitle, Key.showMediaArtist, Key.showMediaSourceName,
            Key.showPlaybackControls, Key.showProgressSlider, Key.showVolumeSlider, Key.showVisualizer,
            Key.collapsedHoverPreviewMediaEnabled, Key.collapsedHoverPreviewShowTitle,
            Key.collapsedHoverPreviewShowsArtist, Key.collapsedHoverPreviewShowsSource,
            Key.trayEnabled, Key.fileShelfEnabled, Key.airDropZoneEnabled,
            Key.floatingBasketEnabled, Key.basketJiggleSensitivity, Key.basketMultipleEnabled,
            Key.basketAutoHideEnabled, Key.basketAutoHideDelay,
            Key.timerEnabled, Key.timerPresetsEnabled, Key.timerPreset1Minutes, Key.timerPreset2Minutes, Key.timerPreset3Minutes,
            Key.statsEnabled, Key.showCPU, Key.showMemory, Key.showGPU, Key.showNetwork, Key.showDisk, Key.showBattery, Key.showUptime,
            Key.clipboardHistoryEnabled, Key.clipboardHistoryMaximumItems,
            Key.clipboardHistoryPersistenceEnabled, Key.clipboardHistoryCaptureImagesEnabled,
            Key.showExpandedLiveActivitiesSection, Key.allowSimultaneousLiveActivitySidecars,
            Key.timerSidecarPreference, Key.systemHUDsEnabled, Key.replaceMacOSSystemHUDs,
            Key.volumeHUDEnabled, Key.brightnessHUDEnabled, Key.capsLockHUDEnabled,
            Key.batteryStatusHUDEnabled, Key.lowBatteryHUDEnabled, Key.audioDeviceHUDEnabled,
            Key.focusHUDEnabled, Key.systemHUDDurationSeconds
        ])
        reload()
    }

    var collapsedLiveActivityPrioritySettings: CollapsedLiveActivityPrioritySettings {
        CollapsedLiveActivityPrioritySettings(
            runningTimer: collapsedPriorityRunningTimer,
            playingMedia: collapsedPriorityPlayingMedia,
            pausedTimer: collapsedPriorityPausedTimer,
            recentFiles: collapsedPriorityRecentFiles,
            pausedMedia: collapsedPriorityPausedMedia
        )
    }

    func resetCollapsedLiveActivityPrioritySettings() {
        let defaults = CollapsedLiveActivityPrioritySettings.defaults
        collapsedPriorityRunningTimer = defaults.runningTimer
        collapsedPriorityPlayingMedia = defaults.playingMedia
        collapsedPriorityPausedTimer = defaults.pausedTimer
        collapsedPriorityRecentFiles = defaults.recentFiles
        collapsedPriorityPausedMedia = defaults.pausedMedia
    }

    private func reload() {
        overlayEnabled = Self.bool(defaults, Key.overlayEnabled, true)
        launchAtLoginEnabled = Self.bool(defaults, Key.launchAtLoginEnabled, false)
        startCollapsedOnLaunch = Self.bool(defaults, Key.startCollapsedOnLaunch, true)
        expandOnHover = Self.bool(defaults, Key.expandOnHover, false)
        expandOnClick = Self.bool(defaults, Key.expandOnClick, true)
        collapseOnMouseLeave = Self.bool(defaults, Key.collapseOnMouseLeave, true)
        autoCollapseEnabled = Self.bool(defaults, Key.autoCollapseEnabled, true)
        autoCollapseDelayPreset = Self.enumValue(defaults, Key.autoCollapseDelayPreset, .normal)
        autoCollapseGraceSeconds = Self.double(defaults, Key.autoCollapseGraceSeconds, 0.30)
        collapsedWidth = Self.double(defaults, Key.collapsedWidth, 190)
        collapsedHeight = Self.double(defaults, Key.collapsedHeight, 44)
        expandedWidth = Self.double(defaults, Key.expandedWidth, 860)
        expandedHeight = Self.double(defaults, Key.expandedHeight, 286)
        useAdaptiveNotchSizing = Self.bool(defaults, Key.useAdaptiveNotchSizing, true)
        respectHardwareNotch = Self.bool(defaults, Key.respectHardwareNotch, true)
        islandThemeStyle = Self.islandThemeStyleValue(defaults, Key.islandThemeStyle, .classicBlack)
        Self.migrateLegacyIslandThemeStyleIfNeeded(defaults, Key.islandThemeStyle)
        shellOpacity = Self.double(defaults, Key.shellOpacity, 1.0)
        shellStrokeEnabled = Self.bool(defaults, Key.shellStrokeEnabled, true)
        useArtworkAccentColor = Self.bool(defaults, Key.useArtworkAccentColor, true)
        visualizerAccentMode = Self.enumValue(defaults, Key.visualizerAccentMode, .artwork)
        showCollapsedVisualizer = Self.bool(defaults, Key.showCollapsedVisualizer, true)
        showExpandedVisualizer = Self.bool(defaults, Key.showExpandedVisualizer, true)
        collapsedHoverPreviewEnabled = Self.bool(defaults, Key.collapsedHoverPreviewEnabled, true)
        collapsedHoverPreviewMediaEnabled = Self.bool(defaults, Key.collapsedHoverPreviewMediaEnabled, true)
        collapsedHoverPreviewHeight = Self.double(defaults, Key.collapsedHoverPreviewHeight, 58)
        collapsedHoverPreviewDelay = Self.double(defaults, Key.collapsedHoverPreviewDelay, 0.08)
        collapsedHoverPreviewShowTitle = Self.bool(defaults, Key.collapsedHoverPreviewShowTitle, true)
        collapsedHoverPreviewShowsArtist = Self.bool(defaults, Key.collapsedHoverPreviewShowsArtist, true)
        collapsedHoverPreviewShowsSource = Self.bool(defaults, Key.collapsedHoverPreviewShowsSource, false)
        collapsedHoverPreviewTitleIconName = Self.string(defaults, Key.collapsedHoverPreviewTitleIconName, "music.mic")
        collapsedHoverPreviewArtistIconName = Self.string(defaults, Key.collapsedHoverPreviewArtistIconName, "person.fill")
        animationPreset = Self.enumValue(defaults, Key.animationPreset, .normal)
        reduceExtraMotion = Self.bool(defaults, Key.reduceExtraMotion, false)
        shellAnimationSpeed = Self.double(defaults, Key.shellAnimationSpeed, 1.0)
        contentAnimationEnabled = Self.bool(defaults, Key.contentAnimationEnabled, true)
        contentStaggerEnabled = Self.bool(defaults, Key.contentStaggerEnabled, true)
        contentStaggerAmount = Self.double(defaults, Key.contentStaggerAmount, 1.0)
        useBlurTransitions = Self.bool(defaults, Key.useBlurTransitions, true)
        useScaleTransitions = Self.bool(defaults, Key.useScaleTransitions, true)
        showIslandTab = true
        showTrayTab = Self.bool(defaults, Key.showTrayTab, true)
        showTimerTab = Self.bool(defaults, Key.showTimerTab, true)
        showStatsTab = Self.bool(defaults, Key.showStatsTab, true)
        showToolsTab = Self.bool(defaults, Key.showToolsTab, true)
        showAgentsTab = Self.bool(defaults, Key.showAgentsTab, true)
        agentActivityEnabled = Self.bool(defaults, Key.agentActivityEnabled, true)
        agentCompletionAlertsEnabled = Self.bool(defaults, Key.agentCompletionAlertsEnabled, true)
        agentApprovalAlertsEnabled = Self.bool(defaults, Key.agentApprovalAlertsEnabled, true)
        agentSoundsEnabled = Self.bool(defaults, Key.agentSoundsEnabled, true)
        agentUsageMetricsEnabled = Self.bool(defaults, Key.agentUsageMetricsEnabled, true)
        agentActivityRecordingEnabled = Self.bool(defaults, Key.agentActivityRecordingEnabled, false)
        agentPeekDurationSeconds = Self.double(defaults, Key.agentPeekDurationSeconds, 5.0)
        showActivitiesTab = Self.bool(defaults, Key.showActivitiesTab, false)
        showLiveActivitiesTab = Self.bool(defaults, Key.showLiveActivitiesTab, false)
        showGesturesTab = Self.bool(defaults, Key.showGesturesTab, false)
        rememberLastSelectedTab = Self.bool(defaults, Key.rememberLastSelectedTab, true)
        defaultExpandedTab = Self.enumValue(defaults, Key.defaultExpandedTab, .island)
        mediaEnabled = Self.bool(defaults, Key.mediaEnabled, true)
        showMediaWhenPaused = Self.bool(defaults, Key.showMediaWhenPaused, true)
        showMediaWhenNoSource = Self.bool(defaults, Key.showMediaWhenNoSource, true)
        showAlbumArtwork = Self.bool(defaults, Key.showAlbumArtwork, true)
        showMediaTitle = Self.bool(defaults, Key.showMediaTitle, true)
        showMediaArtist = Self.bool(defaults, Key.showMediaArtist, true)
        showMediaSourceName = Self.bool(defaults, Key.showMediaSourceName, true)
        showPlaybackControls = Self.bool(defaults, Key.showPlaybackControls, true)
        showProgressSlider = Self.bool(defaults, Key.showProgressSlider, true)
        showVolumeSlider = Self.bool(defaults, Key.showVolumeSlider, true)
        showVisualizer = Self.bool(defaults, Key.showVisualizer, true)
        openSourceOnArtworkClick = Self.bool(defaults, Key.openSourceOnArtworkClick, true)
        collapseAfterOpeningMediaSource = Self.bool(defaults, Key.collapseAfterOpeningMediaSource, true)
        collapseAfterMediaLauncher = Self.bool(defaults, Key.collapseAfterMediaLauncher, true)
        mediaLauncherEnabled = Self.bool(defaults, Key.mediaLauncherEnabled, true)
        showAppleMusicLauncher = Self.bool(defaults, Key.showAppleMusicLauncher, true)
        showSpotifyLauncher = Self.bool(defaults, Key.showSpotifyLauncher, true)
        showYouTubeLauncher = Self.bool(defaults, Key.showYouTubeLauncher, true)
        preferSystemNowPlaying = Self.bool(defaults, Key.preferSystemNowPlaying, true)
        preferSpotifyAppleScript = Self.bool(defaults, Key.preferSpotifyAppleScript, true)
        preferBrowserMedia = Self.bool(defaults, Key.preferBrowserMedia, true)
        browserMediaDetectionEnabled = Self.bool(defaults, Key.browserMediaDetectionEnabled, true)
        youtubeMetadataEnrichmentEnabled = Self.bool(defaults, Key.youtubeMetadataEnrichmentEnabled, true)
        trayEnabled = Self.bool(defaults, Key.trayEnabled, true)
        fileShelfEnabled = Self.bool(defaults, Key.fileShelfEnabled, true)
        airDropZoneEnabled = Self.bool(defaults, Key.airDropZoneEnabled, true)
        allowFileDropsOnCollapsedIsland = Self.bool(defaults, Key.allowFileDropsOnCollapsedIsland, true)
        allowFileDropsOnExpandedTray = Self.bool(defaults, Key.allowFileDropsOnExpandedTray, true)
        maxShelfFiles = Self.int(defaults, Key.maxShelfFiles, 12)
        persistFileShelfAcrossLaunches = Self.bool(defaults, Key.persistFileShelfAcrossLaunches, false)
        showFileThumbnails = Self.bool(defaults, Key.showFileThumbnails, true)
        deferThumbnailsDuringMorph = Self.bool(defaults, Key.deferThumbnailsDuringMorph, true)
        showFileExtensions = Self.bool(defaults, Key.showFileExtensions, true)
        showFileCountBadge = Self.bool(defaults, Key.showFileCountBadge, true)
        floatingBasketEnabled = Self.bool(defaults, Key.floatingBasketEnabled, true)
        basketJiggleSensitivity = Self.int(defaults, Key.basketJiggleSensitivity, 3)
        basketMultipleEnabled = Self.bool(defaults, Key.basketMultipleEnabled, true)
        basketAutoHideEnabled = Self.bool(defaults, Key.basketAutoHideEnabled, false)
        basketAutoHideDelay = Self.double(defaults, Key.basketAutoHideDelay, 2.0)
        confirmBeforeClearShelf = Self.bool(defaults, Key.confirmBeforeClearShelf, false)
        revealInFinderActionEnabled = Self.bool(defaults, Key.revealInFinderActionEnabled, true)
        copyPathActionEnabled = Self.bool(defaults, Key.copyPathActionEnabled, true)
        removeFileActionEnabled = Self.bool(defaults, Key.removeFileActionEnabled, true)
        openFileActionEnabled = Self.bool(defaults, Key.openFileActionEnabled, true)
        airDropFallbackRevealInFinder = Self.bool(defaults, Key.airDropFallbackRevealInFinder, true)
        timerEnabled = Self.bool(defaults, Key.timerEnabled, true)
        timerPresetsEnabled = Self.bool(defaults, Key.timerPresetsEnabled, true)
        timerPreset1Minutes = Self.int(defaults, Key.timerPreset1Minutes, 5)
        timerPreset2Minutes = Self.int(defaults, Key.timerPreset2Minutes, 10)
        timerPreset3Minutes = Self.int(defaults, Key.timerPreset3Minutes, 15)
        timerSoundEnabled = Self.bool(defaults, Key.timerSoundEnabled, false)
        timerNotificationEnabled = Self.bool(defaults, Key.timerNotificationEnabled, false)
        collapseAfterStartingTimer = Self.bool(defaults, Key.collapseAfterStartingTimer, false)
        keepIslandExpandedWhenTimerRunning = Self.bool(defaults, Key.keepIslandExpandedWhenTimerRunning, false)
        showTimerInCollapsedIsland = Self.bool(defaults, Key.showTimerInCollapsedIsland, false)
        showTimerProgressRing = Self.bool(defaults, Key.showTimerProgressRing, true)
        timerRingAnimationEnabled = Self.bool(defaults, Key.timerRingAnimationEnabled, true)
        statsEnabled = Self.bool(defaults, Key.statsEnabled, true)
        statsRefreshIntervalSeconds = Self.double(defaults, Key.statsRefreshIntervalSeconds, 2.0)
        showCPU = Self.bool(defaults, Key.showCPU, true)
        showMemory = Self.bool(defaults, Key.showMemory, true)
        showGPU = Self.bool(defaults, Key.showGPU, true)
        showNetwork = Self.bool(defaults, Key.showNetwork, true)
        showDisk = Self.bool(defaults, Key.showDisk, true)
        showBattery = Self.bool(defaults, Key.showBattery, true)
        showUptime = Self.bool(defaults, Key.showUptime, true)
        animateStatsCharts = Self.bool(defaults, Key.animateStatsCharts, true)
        pauseStatsDuringShellMorph = Self.bool(defaults, Key.pauseStatsDuringShellMorph, true)
        showActivityIndicator = Self.bool(defaults, Key.showActivityIndicator, true)
        activitiesEnabled = Self.bool(defaults, Key.activitiesEnabled, false)
        activitiesRefreshIntervalSeconds = Self.double(defaults, Key.activitiesRefreshIntervalSeconds, 3.0)
        showRunningAppsActivity = Self.bool(defaults, Key.showRunningAppsActivity, false)
        showDownloadsActivity = Self.bool(defaults, Key.showDownloadsActivity, false)
        showCalendarActivity = Self.bool(defaults, Key.showCalendarActivity, false)
        showNowPlayingActivity = Self.bool(defaults, Key.showNowPlayingActivity, false)
        clipboardHistoryEnabled = Self.bool(defaults, Key.clipboardHistoryEnabled, false)
        clipboardHistoryMaximumItems = Self.int(defaults, Key.clipboardHistoryMaximumItems, 50)
        clipboardHistoryPersistenceEnabled = Self.bool(defaults, Key.clipboardHistoryPersistenceEnabled, false)
        clipboardHistoryCaptureImagesEnabled = Self.bool(defaults, Key.clipboardHistoryCaptureImagesEnabled, true)
        liveActivitiesEnabled = Self.bool(defaults, Key.liveActivitiesEnabled, true)
        showExpandedLiveActivitiesSection = Self.bool(defaults, Key.showExpandedLiveActivitiesSection, true)
        liveActivityStyle = Self.enumValue(defaults, Key.liveActivityStyle, .compact)
        showMusicLiveActivity = Self.bool(defaults, Key.showMusicLiveActivity, true)
        showTimerLiveActivity = Self.bool(defaults, Key.showTimerLiveActivity, true)
        showFileDropLiveActivity = Self.bool(defaults, Key.showFileDropLiveActivity, true)
        showBatteryLiveActivity = Self.bool(defaults, Key.showBatteryLiveActivity, true)
        showCalendarLiveActivity = Self.bool(defaults, Key.showCalendarLiveActivity, false)
        showDownloadsLiveActivity = Self.bool(defaults, Key.showDownloadsLiveActivity, false)
        liveActivityAutoDismissEnabled = Self.bool(defaults, Key.liveActivityAutoDismissEnabled, true)
        liveActivityAutoDismissSeconds = Self.double(defaults, Key.liveActivityAutoDismissSeconds, 6.0)
        liveActivityAnimationEnabled = Self.bool(defaults, Key.liveActivityAnimationEnabled, true)
        allowSimultaneousLiveActivitySidecars = Self.bool(
            defaults,
            Key.allowSimultaneousLiveActivitySidecars,
            true
        )
        timerSidecarPreference = Self.enumValue(
            defaults,
            Key.timerSidecarPreference,
            .automatic
        )
        systemHUDsEnabled = Self.bool(defaults, Key.systemHUDsEnabled, true)
        replaceMacOSSystemHUDs = Self.bool(defaults, Key.replaceMacOSSystemHUDs, true)
        volumeHUDEnabled = Self.bool(defaults, Key.volumeHUDEnabled, true)
        brightnessHUDEnabled = Self.bool(defaults, Key.brightnessHUDEnabled, true)
        capsLockHUDEnabled = Self.bool(defaults, Key.capsLockHUDEnabled, true)
        batteryStatusHUDEnabled = Self.bool(defaults, Key.batteryStatusHUDEnabled, true)
        lowBatteryHUDEnabled = Self.bool(defaults, Key.lowBatteryHUDEnabled, true)
        audioDeviceHUDEnabled = Self.bool(defaults, Key.audioDeviceHUDEnabled, true)
        focusHUDEnabled = Self.bool(defaults, Key.focusHUDEnabled, false)
        systemHUDDurationSeconds = Self.double(defaults, Key.systemHUDDurationSeconds, 1.4)
        collapsedPriorityRunningTimer = Self.int(defaults, Key.collapsedPriorityRunningTimer, CollapsedLiveActivityPrioritySource.runningTimer.defaultPriority)
        collapsedPriorityPlayingMedia = Self.int(defaults, Key.collapsedPriorityPlayingMedia, CollapsedLiveActivityPrioritySource.playingMedia.defaultPriority)
        collapsedPriorityPausedTimer = Self.int(defaults, Key.collapsedPriorityPausedTimer, CollapsedLiveActivityPrioritySource.pausedTimer.defaultPriority)
        collapsedPriorityRecentFiles = Self.int(defaults, Key.collapsedPriorityRecentFiles, CollapsedLiveActivityPrioritySource.recentFiles.defaultPriority)
        collapsedPriorityPausedMedia = Self.int(defaults, Key.collapsedPriorityPausedMedia, CollapsedLiveActivityPrioritySource.pausedMedia.defaultPriority)
        gesturesEnabled = Self.bool(defaults, Key.gesturesEnabled, false)
        gestureInputSource = Self.enumValue(defaults, Key.gestureInputSource, .none)
        expandGestureEnabled = Self.bool(defaults, Key.expandGestureEnabled, true)
        collapseGestureEnabled = Self.bool(defaults, Key.collapseGestureEnabled, true)
        nextTabGestureEnabled = Self.bool(defaults, Key.nextTabGestureEnabled, true)
        previousTabGestureEnabled = Self.bool(defaults, Key.previousTabGestureEnabled, true)
        mediaPlayPauseGestureEnabled = Self.bool(defaults, Key.mediaPlayPauseGestureEnabled, true)
        timerStartStopGestureEnabled = Self.bool(defaults, Key.timerStartStopGestureEnabled, true)
        collapsedDoubleClickAction = Self.enumValue(defaults, Key.collapsedDoubleClickAction, .mediaPlayPause)
        collapsedSwipeDownAction = Self.enumValue(defaults, Key.collapsedSwipeDownAction, .expand)
        collapsedSwipeUpAction = Self.enumValue(defaults, Key.collapsedSwipeUpAction, .none)
        collapsedSwipeLeftAction = Self.enumValue(defaults, Key.collapsedSwipeLeftAction, .mediaNextTrack)
        collapsedSwipeRightAction = Self.enumValue(defaults, Key.collapsedSwipeRightAction, .mediaPreviousTrack)
        collapsedLongPressAction = Self.enumValue(defaults, Key.collapsedLongPressAction, .openSettings)
        expandedDoubleClickAction = Self.enumValue(defaults, Key.expandedDoubleClickAction, .none)
        expandedSwipeDownAction = Self.enumValue(defaults, Key.expandedSwipeDownAction, .none)
        expandedSwipeUpAction = Self.enumValue(defaults, Key.expandedSwipeUpAction, .collapse)
        expandedSwipeLeftAction = Self.enumValue(defaults, Key.expandedSwipeLeftAction, .nextTab)
        expandedSwipeRightAction = Self.enumValue(defaults, Key.expandedSwipeRightAction, .previousTab)
        expandedLongPressAction = Self.enumValue(defaults, Key.expandedLongPressAction, .openSettings)
        gestureSensitivity = Self.double(defaults, Key.gestureSensitivity, 0.5)
        gestureCooldownSeconds = Self.double(defaults, Key.gestureCooldownSeconds, 0.75)
        showGestureHints = Self.bool(defaults, Key.showGestureHints, true)
        requireGestureConfirmation = Self.bool(defaults, Key.requireGestureConfirmation, false)
        gesturePrivacyMode = Self.bool(defaults, Key.gesturePrivacyMode, true)
        verboseUILogsEnabled = Self.bool(defaults, Key.verboseUILogsEnabled, false)
        showDebugFrames = Self.bool(defaults, Key.showDebugFrames, false)
        showHitTestRegionDebug = Self.bool(defaults, Key.showHitTestRegionDebug, false)
        disableVisualizerDuringMorph = Self.bool(defaults, Key.disableVisualizerDuringMorph, true)
        disableThumbnailsDuringMorph = Self.bool(defaults, Key.disableThumbnailsDuringMorph, true)
        normalizeAll()
    }

    private func normalizeAll() {
        isNormalizingSettings = true
        defer { isNormalizingSettings = false }

        autoCollapseGraceSeconds = normalizedDouble(autoCollapseGraceSeconds, fallback: 0.30, range: 0.10...2.00)
        collapsedWidth = normalizedDouble(collapsedWidth, fallback: 190, range: 120...360)
        collapsedHeight = normalizedDouble(collapsedHeight, fallback: 44, range: 28...64)
        expandedWidth = normalizedDouble(expandedWidth, fallback: 860, range: 520...920)
        expandedHeight = normalizedDouble(expandedHeight, fallback: 286, range: 180...360)
        shellOpacity = normalizedDouble(shellOpacity, fallback: 1.0, range: 0.35...1.0)
        collapsedHoverPreviewHeight = normalizedDouble(collapsedHoverPreviewHeight, fallback: 58, range: 44...96)
        collapsedHoverPreviewDelay = normalizedDouble(collapsedHoverPreviewDelay, fallback: 0.08, range: 0...0.4)
        shellAnimationSpeed = normalizedDouble(shellAnimationSpeed, fallback: 1.0, range: 0.25...2.0)
        contentStaggerAmount = normalizedDouble(contentStaggerAmount, fallback: 1.0, range: 0...2.0)
        maxShelfFiles = normalizedInt(maxShelfFiles, fallback: 12, range: 1...48)
        basketJiggleSensitivity = normalizedInt(basketJiggleSensitivity, fallback: 3, range: 1...5)
        basketAutoHideDelay = normalizedDouble(basketAutoHideDelay, fallback: 2.0, range: 0.5...10.0)
        timerPreset1Minutes = normalizedInt(timerPreset1Minutes, fallback: 5, range: 1...180)
        timerPreset2Minutes = normalizedInt(timerPreset2Minutes, fallback: 10, range: 1...180)
        timerPreset3Minutes = normalizedInt(timerPreset3Minutes, fallback: 15, range: 1...180)
        statsRefreshIntervalSeconds = normalizedDouble(statsRefreshIntervalSeconds, fallback: 2.0, range: 0.5...10.0)
        activitiesRefreshIntervalSeconds = normalizedDouble(activitiesRefreshIntervalSeconds, fallback: 3.0, range: 0.5...30.0)
        clipboardHistoryMaximumItems = normalizedInt(clipboardHistoryMaximumItems, fallback: 50, range: 10...200)
        liveActivityAutoDismissSeconds = normalizedDouble(liveActivityAutoDismissSeconds, fallback: 6.0, range: 1.0...60.0)
        collapsedPriorityRunningTimer = normalizedCollapsedLiveActivityPriority(collapsedPriorityRunningTimer)
        collapsedPriorityPlayingMedia = normalizedCollapsedLiveActivityPriority(collapsedPriorityPlayingMedia)
        collapsedPriorityPausedTimer = normalizedCollapsedLiveActivityPriority(collapsedPriorityPausedTimer)
        collapsedPriorityRecentFiles = normalizedCollapsedLiveActivityPriority(collapsedPriorityRecentFiles)
        collapsedPriorityPausedMedia = normalizedCollapsedLiveActivityPriority(collapsedPriorityPausedMedia)
        gestureSensitivity = normalizedDouble(gestureSensitivity, fallback: 0.5, range: 0...1.0)
        gestureCooldownSeconds = normalizedDouble(gestureCooldownSeconds, fallback: 0.75, range: 0.1...10.0)
        showIslandTab = true
        saveAllNormalizedValues()
    }

    private func normalizeAutoCollapseGrace(oldValue: Double) {
        normalizeAndSaveDouble(\.autoCollapseGraceSeconds, oldValue: oldValue, fallback: 0.30, range: 0.10...2.00, key: Key.autoCollapseGraceSeconds)
    }

    private func normalizeCollapsedWidth(oldValue: Double) {
        normalizeAndSaveDouble(\.collapsedWidth, oldValue: oldValue, fallback: 190, range: 120...360, key: Key.collapsedWidth)
    }

    private func normalizeCollapsedHeight(oldValue: Double) {
        normalizeAndSaveDouble(\.collapsedHeight, oldValue: oldValue, fallback: 44, range: 28...64, key: Key.collapsedHeight)
    }

    private func normalizeExpandedWidth(oldValue: Double) {
        normalizeAndSaveDouble(\.expandedWidth, oldValue: oldValue, fallback: 860, range: 520...920, key: Key.expandedWidth)
    }

    private func normalizeExpandedHeight(oldValue: Double) {
        normalizeAndSaveDouble(\.expandedHeight, oldValue: oldValue, fallback: 286, range: 180...360, key: Key.expandedHeight)
    }

    private func normalizeShellOpacity(oldValue: Double) {
        normalizeAndSaveDouble(\.shellOpacity, oldValue: oldValue, fallback: 1.0, range: 0.35...1.0, key: Key.shellOpacity)
    }

    private func normalizeCollapsedHoverPreviewHeight(oldValue: Double) {
        normalizeAndSaveDouble(\.collapsedHoverPreviewHeight, oldValue: oldValue, fallback: 58, range: 44...96, key: Key.collapsedHoverPreviewHeight)
    }

    private func normalizeCollapsedHoverPreviewDelay(oldValue: Double) {
        normalizeAndSaveDouble(\.collapsedHoverPreviewDelay, oldValue: oldValue, fallback: 0.08, range: 0...0.4, key: Key.collapsedHoverPreviewDelay)
    }

    private func normalizeShellAnimationSpeed(oldValue: Double) {
        normalizeAndSaveDouble(\.shellAnimationSpeed, oldValue: oldValue, fallback: 1.0, range: 0.25...2.0, key: Key.shellAnimationSpeed)
    }

    private func normalizeContentStaggerAmount(oldValue: Double) {
        normalizeAndSaveDouble(\.contentStaggerAmount, oldValue: oldValue, fallback: 1.0, range: 0...2.0, key: Key.contentStaggerAmount)
    }

    private func normalizeMaxShelfFiles(oldValue: Int) {
        normalizeAndSaveInt(\.maxShelfFiles, oldValue: oldValue, fallback: 12, range: 1...48, key: Key.maxShelfFiles)
    }

    private func normalizeTimerPreset1(oldValue: Int) {
        normalizeAndSaveInt(\.timerPreset1Minutes, oldValue: oldValue, fallback: 5, range: 1...180, key: Key.timerPreset1Minutes)
    }

    private func normalizeTimerPreset2(oldValue: Int) {
        normalizeAndSaveInt(\.timerPreset2Minutes, oldValue: oldValue, fallback: 10, range: 1...180, key: Key.timerPreset2Minutes)
    }

    private func normalizeTimerPreset3(oldValue: Int) {
        normalizeAndSaveInt(\.timerPreset3Minutes, oldValue: oldValue, fallback: 15, range: 1...180, key: Key.timerPreset3Minutes)
    }

    private func normalizeStatsRefreshInterval(oldValue: Double) {
        normalizeAndSaveDouble(\.statsRefreshIntervalSeconds, oldValue: oldValue, fallback: 2.0, range: 0.5...10.0, key: Key.statsRefreshIntervalSeconds)
    }

    private func normalizeActivitiesRefreshInterval(oldValue: Double) {
        normalizeAndSaveDouble(\.activitiesRefreshIntervalSeconds, oldValue: oldValue, fallback: 3.0, range: 0.5...30.0, key: Key.activitiesRefreshIntervalSeconds)
    }

    private func normalizeClipboardHistoryMaximumItems(oldValue: Int) {
        normalizeAndSaveInt(
            \.clipboardHistoryMaximumItems,
            oldValue: oldValue,
            fallback: 50,
            range: 10...200,
            key: Key.clipboardHistoryMaximumItems
        )
    }

    private func normalizeLiveActivityDismiss(oldValue: Double) {
        normalizeAndSaveDouble(\.liveActivityAutoDismissSeconds, oldValue: oldValue, fallback: 6.0, range: 1.0...60.0, key: Key.liveActivityAutoDismissSeconds)
    }

    private func normalizeGestureSensitivity(oldValue: Double) {
        normalizeAndSaveDouble(\.gestureSensitivity, oldValue: oldValue, fallback: 0.5, range: 0...1.0, key: Key.gestureSensitivity)
    }

    private func normalizeGestureCooldown(oldValue: Double) {
        normalizeAndSaveDouble(\.gestureCooldownSeconds, oldValue: oldValue, fallback: 0.75, range: 0.1...10.0, key: Key.gestureCooldownSeconds)
    }

    private func normalizeCollapsedPriorityRunningTimer(oldValue: Int) {
        normalizeAndSaveCollapsedPriority(
            \.collapsedPriorityRunningTimer,
            oldValue: oldValue,
            fallback: CollapsedLiveActivityPrioritySource.runningTimer.defaultPriority,
            key: Key.collapsedPriorityRunningTimer
        )
    }

    private func normalizeCollapsedPriorityPlayingMedia(oldValue: Int) {
        normalizeAndSaveCollapsedPriority(
            \.collapsedPriorityPlayingMedia,
            oldValue: oldValue,
            fallback: CollapsedLiveActivityPrioritySource.playingMedia.defaultPriority,
            key: Key.collapsedPriorityPlayingMedia
        )
    }

    private func normalizeCollapsedPriorityPausedTimer(oldValue: Int) {
        normalizeAndSaveCollapsedPriority(
            \.collapsedPriorityPausedTimer,
            oldValue: oldValue,
            fallback: CollapsedLiveActivityPrioritySource.pausedTimer.defaultPriority,
            key: Key.collapsedPriorityPausedTimer
        )
    }

    private func normalizeCollapsedPriorityRecentFiles(oldValue: Int) {
        normalizeAndSaveCollapsedPriority(
            \.collapsedPriorityRecentFiles,
            oldValue: oldValue,
            fallback: CollapsedLiveActivityPrioritySource.recentFiles.defaultPriority,
            key: Key.collapsedPriorityRecentFiles
        )
    }

    private func normalizeCollapsedPriorityPausedMedia(oldValue: Int) {
        normalizeAndSaveCollapsedPriority(
            \.collapsedPriorityPausedMedia,
            oldValue: oldValue,
            fallback: CollapsedLiveActivityPrioritySource.pausedMedia.defaultPriority,
            key: Key.collapsedPriorityPausedMedia
        )
    }

    private func normalizeAndSaveCollapsedPriority(
        _ keyPath: ReferenceWritableKeyPath<AppSettings, Int>,
        oldValue: Int,
        fallback: Int,
        key: String
    ) {
        normalizeAndSaveInt(
            keyPath,
            oldValue: oldValue,
            fallback: fallback,
            range: CollapsedLiveActivityPrioritySettings.range,
            key: key
        )
    }

    private func normalizeAndSaveDouble(
        _ keyPath: ReferenceWritableKeyPath<AppSettings, Double>,
        oldValue: Double,
        fallback: Double,
        range: ClosedRange<Double>,
        key: String
    ) {
        guard !isNormalizingSettings else { return }

        let current = self[keyPath: keyPath]
        let normalized = normalizedDouble(current, fallback: fallback, range: range)
        if normalized != current {
            isNormalizingSettings = true
            defer { isNormalizingSettings = false }
            self[keyPath: keyPath] = normalized
            save(normalized, for: key)
            return
        }

        if normalized != oldValue {
            save(normalized, for: key)
        }
    }

    private func normalizeAndSaveInt(
        _ keyPath: ReferenceWritableKeyPath<AppSettings, Int>,
        oldValue: Int,
        fallback: Int,
        range: ClosedRange<Int>,
        key: String
    ) {
        guard !isNormalizingSettings else { return }

        let current = self[keyPath: keyPath]
        let normalized = normalizedInt(current, fallback: fallback, range: range)
        if normalized != current {
            isNormalizingSettings = true
            defer { isNormalizingSettings = false }
            self[keyPath: keyPath] = normalized
            save(normalized, for: key)
            return
        }

        if normalized != oldValue {
            save(normalized, for: key)
        }
    }

    private func normalizedDouble(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func normalizedInt(_ value: Int, fallback: Int, range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func normalizedCollapsedLiveActivityPriority(_ value: Int) -> Int {
        normalizedInt(
            value,
            fallback: CollapsedLiveActivityPrioritySource.pausedMedia.defaultPriority,
            range: CollapsedLiveActivityPrioritySettings.range
        )
    }

    private func saveAllNormalizedValues() {
        save(autoCollapseGraceSeconds, for: Key.autoCollapseGraceSeconds)
        save(collapsedWidth, for: Key.collapsedWidth)
        save(collapsedHeight, for: Key.collapsedHeight)
        save(expandedWidth, for: Key.expandedWidth)
        save(expandedHeight, for: Key.expandedHeight)
        save(shellOpacity, for: Key.shellOpacity)
        save(collapsedHoverPreviewHeight, for: Key.collapsedHoverPreviewHeight)
        save(collapsedHoverPreviewDelay, for: Key.collapsedHoverPreviewDelay)
        save(shellAnimationSpeed, for: Key.shellAnimationSpeed)
        save(contentStaggerAmount, for: Key.contentStaggerAmount)
        save(maxShelfFiles, for: Key.maxShelfFiles)
        save(basketJiggleSensitivity, for: Key.basketJiggleSensitivity)
        save(basketAutoHideDelay, for: Key.basketAutoHideDelay)
        save(timerPreset1Minutes, for: Key.timerPreset1Minutes)
        save(timerPreset2Minutes, for: Key.timerPreset2Minutes)
        save(timerPreset3Minutes, for: Key.timerPreset3Minutes)
        save(statsRefreshIntervalSeconds, for: Key.statsRefreshIntervalSeconds)
        save(activitiesRefreshIntervalSeconds, for: Key.activitiesRefreshIntervalSeconds)
        save(clipboardHistoryMaximumItems, for: Key.clipboardHistoryMaximumItems)
        save(liveActivityAutoDismissSeconds, for: Key.liveActivityAutoDismissSeconds)
        save(collapsedPriorityRunningTimer, for: Key.collapsedPriorityRunningTimer)
        save(collapsedPriorityPlayingMedia, for: Key.collapsedPriorityPlayingMedia)
        save(collapsedPriorityPausedTimer, for: Key.collapsedPriorityPausedTimer)
        save(collapsedPriorityRecentFiles, for: Key.collapsedPriorityRecentFiles)
        save(collapsedPriorityPausedMedia, for: Key.collapsedPriorityPausedMedia)
        save(gestureSensitivity, for: Key.gestureSensitivity)
        save(gestureCooldownSeconds, for: Key.gestureCooldownSeconds)
        save(showIslandTab, for: Key.showIslandTab)
    }

    private func save(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
    }

    private func reset(keys: [String]) {
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private static func double(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }

    private static func int(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    private static func string(_ defaults: UserDefaults, _ key: String, _ fallback: String) -> String {
        guard let value = defaults.string(forKey: key), !value.isEmpty else {
            return fallback
        }
        return value
    }

    private static func islandThemeStyleValue(_ defaults: UserDefaults, _ key: String, _ fallback: IslandThemeStyle) -> IslandThemeStyle {
        guard let rawValue = defaults.string(forKey: key) else {
            return fallback
        }
        if let value = IslandThemeStyle(rawValue: rawValue) {
            return value
        }
        return legacyHybridThemeRawValues.contains(rawValue) ? .liquidGlass : fallback
    }

    private static func migrateLegacyIslandThemeStyleIfNeeded(_ defaults: UserDefaults, _ key: String) {
        guard let rawValue = defaults.string(forKey: key), legacyHybridThemeRawValues.contains(rawValue) else {
            return
        }
        defaults.set(IslandThemeStyle.liquidGlass.rawValue, forKey: key)
    }

    private static func enumValue<T: RawRepresentable>(_ defaults: UserDefaults, _ key: String, _ fallback: T) -> T where T.RawValue == String {
        guard let rawValue = defaults.string(forKey: key), let value = T(rawValue: rawValue) else {
            return fallback
        }
        return value
    }

    private static let legacyHybridThemeRawValues: Set<String> = [
        "hybridBlackGlass",
        "blackLiquidGlass",
        "blackGlass",
        "blackAndLiquidGlass",
        "blackPlusLiquidGlass",
        "hybridBlackLiquidGlass"
    ]
}

private enum Key {
    static let overlayEnabled = "overlayEnabled"
    static let launchAtLoginEnabled = "launchAtLoginEnabled"
    static let startCollapsedOnLaunch = "startCollapsedOnLaunch"
    static let expandOnHover = "expandOnHover"
    static let expandOnClick = "expandOnClick"
    static let collapseOnMouseLeave = "collapseOnMouseLeave"
    static let autoCollapseEnabled = "autoCollapseEnabled"
    static let autoCollapseDelayPreset = "autoCollapseDelayPreset"
    static let autoCollapseGraceSeconds = "autoCollapseGraceSeconds"
    static let collapsedWidth = "collapsedWidth"
    static let collapsedHeight = "collapsedHeight"
    static let expandedWidth = "expandedWidth"
    static let expandedHeight = "expandedHeight"
    static let useAdaptiveNotchSizing = "useAdaptiveNotchSizing"
    static let respectHardwareNotch = "respectHardwareNotch"
    static let islandThemeStyle = "islandThemeStyle"
    static let shellOpacity = "shellOpacity"
    static let shellStrokeEnabled = "shellStrokeEnabled"
    static let useArtworkAccentColor = "useArtworkAccentColor"
    static let visualizerAccentMode = "visualizerAccentMode"
    static let showCollapsedVisualizer = "showCollapsedVisualizer"
    static let showExpandedVisualizer = "showExpandedVisualizer"
    static let collapsedHoverPreviewEnabled = "collapsedHoverPreviewEnabled"
    static let collapsedHoverPreviewMediaEnabled = "collapsedHoverPreviewMediaEnabled"
    static let collapsedHoverPreviewHeight = "collapsedHoverPreviewHeight"
    static let collapsedHoverPreviewDelay = "collapsedHoverPreviewDelay"
    static let collapsedHoverPreviewShowTitle = "collapsedHoverPreviewShowTitle"
    static let collapsedHoverPreviewShowsArtist = "collapsedHoverPreviewShowsArtist"
    static let collapsedHoverPreviewShowsSource = "collapsedHoverPreviewShowsSource"
    static let collapsedHoverPreviewTitleIconName = "collapsedHoverPreviewTitleIconName"
    static let collapsedHoverPreviewArtistIconName = "collapsedHoverPreviewArtistIconName"
    static let animationPreset = "animationPreset"
    static let reduceExtraMotion = "reduceExtraMotion"
    static let shellAnimationSpeed = "shellAnimationSpeed"
    static let contentAnimationEnabled = "contentAnimationEnabled"
    static let contentStaggerEnabled = "contentStaggerEnabled"
    static let contentStaggerAmount = "contentStaggerAmount"
    static let useBlurTransitions = "useBlurTransitions"
    static let useScaleTransitions = "useScaleTransitions"
    static let showIslandTab = "showIslandTab"
    static let showTrayTab = "showTrayTab"
    static let showTimerTab = "showTimerTab"
    static let showStatsTab = "showStatsTab"
    static let showToolsTab = "showToolsTab"
    static let showAgentsTab = "showAgentsTab"
    static let agentActivityEnabled = "agentActivityEnabled"
    static let agentCompletionAlertsEnabled = "agentCompletionAlertsEnabled"
    static let agentApprovalAlertsEnabled = "agentApprovalAlertsEnabled"
    static let agentSoundsEnabled = "agentSoundsEnabled"
    static let agentUsageMetricsEnabled = "agentUsageMetricsEnabled"
    static let agentActivityRecordingEnabled = "agentActivityRecordingEnabled"
    static let agentPeekDurationSeconds = "agentPeekDurationSeconds"
    static let showActivitiesTab = "showActivitiesTab"
    static let showLiveActivitiesTab = "showLiveActivitiesTab"
    static let showGesturesTab = "showGesturesTab"
    static let rememberLastSelectedTab = "rememberLastSelectedTab"
    static let defaultExpandedTab = "defaultExpandedTab"
    static let mediaEnabled = "mediaEnabled"
    static let showMediaWhenPaused = "showMediaWhenPaused"
    static let showMediaWhenNoSource = "showMediaWhenNoSource"
    static let showAlbumArtwork = "showAlbumArtwork"
    static let showMediaTitle = "showMediaTitle"
    static let showMediaArtist = "showMediaArtist"
    static let showMediaSourceName = "showMediaSourceName"
    static let showPlaybackControls = "showPlaybackControls"
    static let showProgressSlider = "showProgressSlider"
    static let showVolumeSlider = "showVolumeSlider"
    static let showVisualizer = "showVisualizer"
    static let openSourceOnArtworkClick = "openSourceOnArtworkClick"
    static let collapseAfterOpeningMediaSource = "collapseAfterOpeningMediaSource"
    static let collapseAfterMediaLauncher = "collapseAfterMediaLauncher"
    static let mediaLauncherEnabled = "mediaLauncherEnabled"
    static let showAppleMusicLauncher = "showAppleMusicLauncher"
    static let showSpotifyLauncher = "showSpotifyLauncher"
    static let showYouTubeLauncher = "showYouTubeLauncher"
    static let preferSystemNowPlaying = "preferSystemNowPlaying"
    static let preferSpotifyAppleScript = "preferSpotifyAppleScript"
    static let preferBrowserMedia = "preferBrowserMedia"
    static let browserMediaDetectionEnabled = "browserMediaDetectionEnabled"
    static let youtubeMetadataEnrichmentEnabled = "youtubeMetadataEnrichmentEnabled"
    static let trayEnabled = "trayEnabled"
    static let fileShelfEnabled = "fileShelfEnabled"
    static let airDropZoneEnabled = "airDropZoneEnabled"
    static let allowFileDropsOnCollapsedIsland = "allowFileDropsOnCollapsedIsland"
    static let allowFileDropsOnExpandedTray = "allowFileDropsOnExpandedTray"
    static let maxShelfFiles = "maxShelfFiles"
    static let persistFileShelfAcrossLaunches = "persistFileShelfAcrossLaunches"
    static let showFileThumbnails = "showFileThumbnails"
    static let deferThumbnailsDuringMorph = "deferThumbnailsDuringMorph"
    static let showFileExtensions = "showFileExtensions"
    static let showFileCountBadge = "showFileCountBadge"
    static let floatingBasketEnabled = "floatingBasketEnabled"
    static let basketJiggleSensitivity = "basketJiggleSensitivity"
    static let basketMultipleEnabled = "basketMultipleEnabled"
    static let basketAutoHideEnabled = "basketAutoHideEnabled"
    static let basketAutoHideDelay = "basketAutoHideDelay"
    static let confirmBeforeClearShelf = "confirmBeforeClearShelf"
    static let revealInFinderActionEnabled = "revealInFinderActionEnabled"
    static let copyPathActionEnabled = "copyPathActionEnabled"
    static let removeFileActionEnabled = "removeFileActionEnabled"
    static let openFileActionEnabled = "openFileActionEnabled"
    static let airDropFallbackRevealInFinder = "airDropFallbackRevealInFinder"
    static let timerEnabled = "timerEnabled"
    static let timerPresetsEnabled = "timerPresetsEnabled"
    static let timerPreset1Minutes = "timerPreset1Minutes"
    static let timerPreset2Minutes = "timerPreset2Minutes"
    static let timerPreset3Minutes = "timerPreset3Minutes"
    static let timerSoundEnabled = "timerSoundEnabled"
    static let timerNotificationEnabled = "timerNotificationEnabled"
    static let collapseAfterStartingTimer = "collapseAfterStartingTimer"
    static let keepIslandExpandedWhenTimerRunning = "keepIslandExpandedWhenTimerRunning"
    static let showTimerInCollapsedIsland = "showTimerInCollapsedIsland"
    static let showTimerProgressRing = "showTimerProgressRing"
    static let timerRingAnimationEnabled = "timerRingAnimationEnabled"
    static let statsEnabled = "statsEnabled"
    static let statsRefreshIntervalSeconds = "statsRefreshIntervalSeconds"
    static let showCPU = "showCPU"
    static let showMemory = "showMemory"
    static let showGPU = "showGPU"
    static let showNetwork = "showNetwork"
    static let showDisk = "showDisk"
    static let showBattery = "showBattery"
    static let showUptime = "showUptime"
    static let animateStatsCharts = "animateStatsCharts"
    static let pauseStatsDuringShellMorph = "pauseStatsDuringShellMorph"
    static let showActivityIndicator = "showActivityIndicator"
    static let activitiesEnabled = "activitiesEnabled"
    static let activitiesRefreshIntervalSeconds = "activitiesRefreshIntervalSeconds"
    static let showRunningAppsActivity = "showRunningAppsActivity"
    static let showDownloadsActivity = "showDownloadsActivity"
    static let showCalendarActivity = "showCalendarActivity"
    static let showNowPlayingActivity = "showNowPlayingActivity"
    static let clipboardHistoryEnabled = "clipboardHistoryEnabled"
    static let clipboardHistoryMaximumItems = "clipboardHistoryMaximumItems"
    static let clipboardHistoryPersistenceEnabled = "clipboardHistoryPersistenceEnabled"
    static let clipboardHistoryCaptureImagesEnabled = "clipboardHistoryCaptureImagesEnabled"
    static let liveActivitiesEnabled = "liveActivitiesEnabled"
    static let showExpandedLiveActivitiesSection = "showExpandedLiveActivitiesSection"
    static let liveActivityStyle = "liveActivityStyle"
    static let showMusicLiveActivity = "showMusicLiveActivity"
    static let showTimerLiveActivity = "showTimerLiveActivity"
    static let showFileDropLiveActivity = "showFileDropLiveActivity"
    static let showBatteryLiveActivity = "showBatteryLiveActivity"
    static let showCalendarLiveActivity = "showCalendarLiveActivity"
    static let showDownloadsLiveActivity = "showDownloadsLiveActivity"
    static let liveActivityAutoDismissEnabled = "liveActivityAutoDismissEnabled"
    static let liveActivityAutoDismissSeconds = "liveActivityAutoDismissSeconds"
    static let liveActivityAnimationEnabled = "liveActivityAnimationEnabled"
    static let allowSimultaneousLiveActivitySidecars = "allowSimultaneousLiveActivitySidecars"
    static let timerSidecarPreference = "timerSidecarPreference"
    static let systemHUDsEnabled = "systemHUDsEnabled"
    static let replaceMacOSSystemHUDs = "replaceMacOSSystemHUDs"
    static let volumeHUDEnabled = "volumeHUDEnabled"
    static let brightnessHUDEnabled = "brightnessHUDEnabled"
    static let capsLockHUDEnabled = "capsLockHUDEnabled"
    static let batteryStatusHUDEnabled = "batteryStatusHUDEnabled"
    static let lowBatteryHUDEnabled = "lowBatteryHUDEnabled"
    static let audioDeviceHUDEnabled = "audioDeviceHUDEnabled"
    static let focusHUDEnabled = "focusHUDEnabled"
    static let systemHUDDurationSeconds = "systemHUDDurationSeconds"
    static let collapsedPriorityRunningTimer = "collapsedPriorityRunningTimer"
    static let collapsedPriorityPlayingMedia = "collapsedPriorityPlayingMedia"
    static let collapsedPriorityPausedTimer = "collapsedPriorityPausedTimer"
    static let collapsedPriorityRecentFiles = "collapsedPriorityRecentFiles"
    static let collapsedPriorityPausedMedia = "collapsedPriorityPausedMedia"
    static let gesturesEnabled = "gesturesEnabled"
    static let gestureInputSource = "gestureInputSource"
    static let expandGestureEnabled = "expandGestureEnabled"
    static let collapseGestureEnabled = "collapseGestureEnabled"
    static let nextTabGestureEnabled = "nextTabGestureEnabled"
    static let previousTabGestureEnabled = "previousTabGestureEnabled"
    static let mediaPlayPauseGestureEnabled = "mediaPlayPauseGestureEnabled"
    static let timerStartStopGestureEnabled = "timerStartStopGestureEnabled"
    static let collapsedDoubleClickAction = "collapsedDoubleClickAction"
    static let collapsedSwipeDownAction = "collapsedSwipeDownAction"
    static let collapsedSwipeUpAction = "collapsedSwipeUpAction"
    static let collapsedSwipeLeftAction = "collapsedSwipeLeftAction"
    static let collapsedSwipeRightAction = "collapsedSwipeRightAction"
    static let collapsedLongPressAction = "collapsedLongPressAction"
    static let expandedDoubleClickAction = "expandedDoubleClickAction"
    static let expandedSwipeDownAction = "expandedSwipeDownAction"
    static let expandedSwipeUpAction = "expandedSwipeUpAction"
    static let expandedSwipeLeftAction = "expandedSwipeLeftAction"
    static let expandedSwipeRightAction = "expandedSwipeRightAction"
    static let expandedLongPressAction = "expandedLongPressAction"
    static let gestureSensitivity = "gestureSensitivity"
    static let gestureCooldownSeconds = "gestureCooldownSeconds"
    static let showGestureHints = "showGestureHints"
    static let requireGestureConfirmation = "requireGestureConfirmation"
    static let gesturePrivacyMode = "gesturePrivacyMode"
    static let verboseUILogsEnabled = "verboseUILogsEnabled"
    static let showDebugFrames = "showDebugFrames"
    static let showHitTestRegionDebug = "showHitTestRegionDebug"
    static let disableVisualizerDuringMorph = "disableVisualizerDuringMorph"
    static let disableThumbnailsDuringMorph = "disableThumbnailsDuringMorph"

    static let allCases: [String] = [
        overlayEnabled, launchAtLoginEnabled, startCollapsedOnLaunch, expandOnHover, expandOnClick,
        collapseOnMouseLeave, autoCollapseEnabled, autoCollapseDelayPreset, autoCollapseGraceSeconds,
        collapsedWidth, collapsedHeight, expandedWidth, expandedHeight, useAdaptiveNotchSizing,
        respectHardwareNotch, islandThemeStyle, shellOpacity, shellStrokeEnabled,
        useArtworkAccentColor, visualizerAccentMode,
        showCollapsedVisualizer, showExpandedVisualizer, collapsedHoverPreviewEnabled,
        collapsedHoverPreviewMediaEnabled, collapsedHoverPreviewHeight, collapsedHoverPreviewDelay,
        collapsedHoverPreviewShowTitle, collapsedHoverPreviewShowsArtist, collapsedHoverPreviewShowsSource,
        collapsedHoverPreviewTitleIconName, collapsedHoverPreviewArtistIconName, animationPreset, reduceExtraMotion,
        shellAnimationSpeed, contentAnimationEnabled, contentStaggerEnabled, contentStaggerAmount,
        useBlurTransitions, useScaleTransitions, showIslandTab, showTrayTab,
        showTimerTab, showStatsTab, showToolsTab, showAgentsTab, agentActivityEnabled,
        agentCompletionAlertsEnabled, agentApprovalAlertsEnabled, agentSoundsEnabled,
        agentUsageMetricsEnabled, agentActivityRecordingEnabled, agentPeekDurationSeconds,
        showActivitiesTab, showLiveActivitiesTab, showGesturesTab,
        rememberLastSelectedTab, defaultExpandedTab, mediaEnabled, showMediaWhenPaused,
        showMediaWhenNoSource, showAlbumArtwork, showMediaTitle, showMediaArtist, showMediaSourceName,
        showPlaybackControls, showProgressSlider, showVolumeSlider, showVisualizer,
        openSourceOnArtworkClick, collapseAfterOpeningMediaSource, collapseAfterMediaLauncher,
        mediaLauncherEnabled, showAppleMusicLauncher, showSpotifyLauncher, showYouTubeLauncher,
        preferSystemNowPlaying, preferSpotifyAppleScript, preferBrowserMedia,
        browserMediaDetectionEnabled, youtubeMetadataEnrichmentEnabled, trayEnabled, fileShelfEnabled,
        airDropZoneEnabled, allowFileDropsOnCollapsedIsland, allowFileDropsOnExpandedTray, maxShelfFiles,
        persistFileShelfAcrossLaunches, showFileThumbnails, deferThumbnailsDuringMorph,
        showFileExtensions, showFileCountBadge, floatingBasketEnabled, basketJiggleSensitivity,
        basketMultipleEnabled, basketAutoHideEnabled, basketAutoHideDelay,
        confirmBeforeClearShelf, revealInFinderActionEnabled,
        copyPathActionEnabled, removeFileActionEnabled, openFileActionEnabled,
        airDropFallbackRevealInFinder, timerEnabled, timerPresetsEnabled, timerPreset1Minutes,
        timerPreset2Minutes, timerPreset3Minutes, timerSoundEnabled, timerNotificationEnabled,
        collapseAfterStartingTimer, keepIslandExpandedWhenTimerRunning, showTimerInCollapsedIsland,
        showTimerProgressRing, timerRingAnimationEnabled, statsEnabled, statsRefreshIntervalSeconds,
        showCPU, showMemory, showGPU, showNetwork, showDisk, showBattery, showUptime,
        animateStatsCharts, pauseStatsDuringShellMorph, showActivityIndicator, activitiesEnabled,
        activitiesRefreshIntervalSeconds, showRunningAppsActivity, showDownloadsActivity,
        showCalendarActivity, showNowPlayingActivity, clipboardHistoryEnabled,
        clipboardHistoryMaximumItems, clipboardHistoryPersistenceEnabled,
        clipboardHistoryCaptureImagesEnabled, liveActivitiesEnabled,
        showExpandedLiveActivitiesSection, liveActivityStyle,
        showMusicLiveActivity, showTimerLiveActivity, showFileDropLiveActivity,
        showBatteryLiveActivity, showCalendarLiveActivity, showDownloadsLiveActivity,
        liveActivityAutoDismissEnabled, liveActivityAutoDismissSeconds, liveActivityAnimationEnabled,
        systemHUDsEnabled, replaceMacOSSystemHUDs, volumeHUDEnabled, brightnessHUDEnabled,
        capsLockHUDEnabled, batteryStatusHUDEnabled, lowBatteryHUDEnabled, audioDeviceHUDEnabled,
        focusHUDEnabled, systemHUDDurationSeconds,
        collapsedPriorityRunningTimer, collapsedPriorityPlayingMedia, collapsedPriorityPausedTimer,
        collapsedPriorityRecentFiles, collapsedPriorityPausedMedia,
        gesturesEnabled, gestureInputSource, expandGestureEnabled, collapseGestureEnabled,
        nextTabGestureEnabled, previousTabGestureEnabled, mediaPlayPauseGestureEnabled,
        timerStartStopGestureEnabled, collapsedDoubleClickAction, collapsedSwipeDownAction,
        collapsedSwipeUpAction, collapsedSwipeLeftAction, collapsedSwipeRightAction,
        collapsedLongPressAction, expandedDoubleClickAction, expandedSwipeDownAction,
        expandedSwipeUpAction, expandedSwipeLeftAction, expandedSwipeRightAction,
        expandedLongPressAction, gestureSensitivity, gestureCooldownSeconds,
        showGestureHints, requireGestureConfirmation, gesturePrivacyMode, verboseUILogsEnabled,
        showDebugFrames, showHitTestRegionDebug, disableVisualizerDuringMorph,
        disableThumbnailsDuringMorph
    ]

    static let clipboardHistoryKeys = [
        clipboardHistoryEnabled,
        clipboardHistoryMaximumItems,
        clipboardHistoryPersistenceEnabled,
        clipboardHistoryCaptureImagesEnabled
    ]
}
