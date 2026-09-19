# Graph Report - DynamicIsland  (2026-09-19)

## Corpus Check
- 79 files · ~115,903 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 2289 nodes · 5887 edges · 105 communities (92 shown, 13 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 781 edges (avg confidence: 0.88)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `df2bd0c2`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- AppSettings
- IslandGestureAction
- SystemStatsController
- ArtworkFlipPresentationState
- SettingsView
- IslandRootView
- IslandEscapeRouter
- ClipboardHistoryStore
- TimerController
- SystemClipboardPasteboardClient
- MediaController
- ClipboardHistoryPayload
- Equatable
- ClipboardHistoryStoreTests
- .normalizeAndSaveDouble
- CollapsedLiveActivitySelectorTests
- OverlayWindowController
- View
- FileShelfStore
- SupportedApp
- ExpandedIslandView
- FileThumbnailCache
- ExpandedIslandLayoutMetrics
- XCTestCase
- DynamicIsland
- ObservableObject
- IslandModules
- Int
- DynamicIslandLiveActivity
- .assignArtwork
- MediaArbitratorTests
- BatteryActivitySnapshot
- ShelfFileTile
- InnerBlurScaleCleanModifier
- DynamicIsland
- IslandRootView.swift
- MediaModuleView
- MediaController.swift
- ShortcutsStore
- LiveActivitiesModuleView
- What You Must Do When Invoked
- IslandLayoutStore
- MediaCandidate
- ModuleViews.swift
- IslandStateStore
- AppSettingsTests
- CGFloat
- Change Log
- Bool
- CollapsedLiveActivityPrioritySource
- IslandHostingView
- AppDelegate
- .reload
- .openActiveMediaSource
- MediaRemoteClient
- CodingKeys
- OverlayPresentationSessionTests
- Identifiable
- Phase Workflow For Future Work
- IslandNavigationStore
- ClipboardHistoryPresentationState
- Double
- String
- DefaultExpandedTab
- FileClipboardHistoryPersistence
- .innerBlurScaleClean
- AudioVisualizerView
- OverlayGeometrySignature
- MediaSnapshot
- FileShelfStoreTests
- AppSettings.swift
- AnimationPreset
- AutoCollapseDelayPreset
- AudioVisualizerVariant
- GestureInputSource
- CollapsedPreviewContent
- CollapsedIslandContentMode
- Meaningful regression history
- .trayPage
- ExpandedIslandPage
- Package.swift
- package_app.sh
- SettingsSection
- DynamicIsland Project Context
- CompactIslandView
- .resolve
- IslandOverlayPanel
- DynamicIslandLiveActivityKind
- graphify reference: extra exports and benchmark
- ShortcutEditorRow
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- CaseIterable
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- .scrollWheel
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- .share
- .remainingTime

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 318 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 93 edges
5. `IslandRootView` - 73 edges
6. `ExpandedIslandView` - 66 edges
7. `ClipboardHistoryStore` - 47 edges
8. `ExpandedIslandLayoutMetrics` - 47 edges
9. `FileThumbnailCache` - 45 edges
10. `MediaModuleView` - 42 edges

## Surprising Connections (you probably didn't know these)
- `2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `2026-07-11 - Phase 9C Liquid Glass Visual Repair` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `Phase 11C.3 - Diagnostic WindowServer Transition Trace` --references--> `IslandOverlayPanel`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `Overlay Windows` --references--> `IslandStateStore`  [INFERRED]
  context.md → Sources/DynamicIsland/State/IslandStateStore.swift
- `Stable native overlay architecture` --references--> `IslandRootView`  [INFERRED]
  README.md → Sources/DynamicIsland/Views/IslandRootView.swift

## Import Cycles
- None detected.

## Communities (105 total, 13 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.03
Nodes (153): AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray, .animateStatsCharts, .animationIntensity (+145 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (39): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, IslandGestureAction, collapse, .displayName, expand, .id (+31 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (28): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, Darwin, ifaddrs, CPUCounters, NetworkCounters, Bool, Date (+20 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.13
Nodes (18): ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted (+10 more)

### Community 4 - "SettingsView"
Cohesion: 0.16
Nodes (27): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsView, .advancedSection (+19 more)

### Community 5 - "IslandRootView"
Cohesion: 0.07
Nodes (25): 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, .percentText, CollapsedPreviewRowContent, ExpandedIslandRightStackVisibility, .showsRightStack, IslandRootView (+17 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.13
Nodes (17): AnyObject, Sendable, ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, Bool, Data (+9 more)

### Community 8 - "TimerController"
Cohesion: 0.09
Nodes (23): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, Never, Double, Int, Void, TimerController, .displayText, TimerProgressColorStage (+15 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.10
Nodes (15): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, ClipboardPasteboardReadResult, empty, oversized, payload, sensitive (+7 more)

### Community 10 - "MediaController"
Cohesion: 0.12
Nodes (12): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, MediaController, .currentArtworkPresentationIdentity, MediaPlayer, .displayName, music, .playPauseCommand, spotify (+4 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.08
Nodes (28): Codable, CryptoKit, Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text (+20 more)

### Community 12 - "Equatable"
Cohesion: 0.12
Nodes (20): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, Equatable, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile (+12 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.17
Nodes (8): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Data, Date, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (18): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+10 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "OverlayWindowController"
Cohesion: 0.10
Nodes (18): CFTimeInterval, 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, DispatchWorkItem, NSRect, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedGestureCandidateScreenRegion, .collapsedInteractiveSurfaceFrame (+10 more)

### Community 17 - "View"
Cohesion: 0.08
Nodes (43): Left, Right, AirDropDropZoneView, .body, .subtitle, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body (+35 more)

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (15): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, FileShelfStore, AnyCancellable, Set, URL (+7 more)

### Community 19 - "SupportedApp"
Cohesion: 0.13
Nodes (18): 2026-07-03 - Common App Launch Resolver, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName (+10 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.25
Nodes (6): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, ExpandedIslandView, .body, .tabAnimationsEnabled, .tabFadeInAnimation, .tabFadeOutAnimation

### Community 21 - "FileThumbnailCache"
Cohesion: 0.07
Nodes (29): 2026-07-05 - Phase 8C.10 Gesture Responsiveness And Artwork Flip, 2026-07-05 - Phase 8C.8 Media Gesture One-Shot Lockout, 2026-07-05 - Phase 8C.9 End-of-Swipe Media Gesture Resolution, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, 2026-07-11 - Phase 10B.2 Collapsed Live Activity Hover Preview, 2026-07-11 - Phase 10B.3 Collapsed Timer Pill Layout Repair, 2026-07-11 - Phase 10B.4 Compact Timer Pill Final Fix, 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix (+21 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "XCTestCase"
Cohesion: 0.09
Nodes (19): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+11 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ObservableObject"
Cohesion: 0.11
Nodes (16): Calendar, ObservableObject, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body, .emptyState, .header, ClipboardThumbnailCache (+8 more)

### Community 26 - "IslandModules"
Cohesion: 0.18
Nodes (4): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, Composition, state and settings, IslandModule, IslandModules

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.20
Nodes (13): Candidate, CollapsedLiveActivityPrioritySettings, .defaults, CollapsedLiveActivitySelector, CollapsedLiveActivitySourceToggles, DynamicIslandLiveActivity, Bool, Date (+5 more)

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "ShelfFileTile"
Cohesion: 0.22
Nodes (8): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, URL

### Community 34 - "InnerBlurScaleCleanModifier"
Cohesion: 0.11
Nodes (20): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, ExpandedTabContentTransitionModifier (+12 more)

### Community 35 - "DynamicIsland"
Cohesion: 0.07
Nodes (12): AppKit, Combine, DynamicIsland, Foundation, NSStatusItem, ServiceManagement, LaunchAtLoginController, Bool (+4 more)

### Community 36 - "IslandRootView.swift"
Cohesion: 0.11
Nodes (19): EnvironmentKey, CollapseShellOnlyEnvironmentKey, EnvironmentValues, .isCollapseShellOnly, .isNotchIntegratedShell, .isShellMorphing, IslandContentPhase, compact (+11 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.07
Nodes (29): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, .body, MediaLauncherButton, .body, MediaModuleView (+21 more)

### Community 38 - "MediaController.swift"
Cohesion: 0.13
Nodes (18): 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Element, Index, Media and artwork, AppleScriptExecutionResult, Array, ArtworkPresentationCoordinator, .displayedSnapshot (+10 more)

### Community 39 - "ShortcutsStore"
Cohesion: 0.16
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+2 more)

### Community 40 - "LiveActivitiesModuleView"
Cohesion: 0.28
Nodes (8): LiveActivitiesModuleView, .body, .remainingActivityCount, .visibleActivities, LiveActivityCard, .activityAccessibilityLabel, .body, CGSize

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.06
Nodes (32): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+24 more)

### Community 42 - "IslandLayoutStore"
Cohesion: 0.21
Nodes (10): 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, Phase 12C.3 - Hardware Notch Center Exclusion, IslandLayoutStore, Bool, CGFloat (+2 more)

### Community 43 - "MediaCandidate"
Cohesion: 0.19
Nodes (9): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, Decision, MediaArbitrator, MediaCandidate, .sourceKey, MediaSourceIdentity, .debugDescription, Date (+1 more)

### Community 44 - "ModuleViews.swift"
Cohesion: 0.16
Nodes (14): 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, AlbumArtworkView, .body, ClickableAlbumArtworkButton, .artwork, .body, CompactMediaView (+6 more)

### Community 45 - "IslandStateStore"
Cohesion: 0.18
Nodes (8): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, IslandPresentationState, collapsed, expanded, IslandStateStore, .isExpandedSurfaceVisible, Bool, IslandStateStoreTests

### Community 47 - "CGFloat"
Cohesion: 0.07
Nodes (33): AnimatablePair, 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, LinearGradient, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline (+25 more)

### Community 48 - "Change Log"
Cohesion: 0.08
Nodes (31): 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+23 more)

### Community 49 - "Bool"
Cohesion: 0.21
Nodes (3): NSPoint, Bool, NSEvent

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.13
Nodes (14): IOKit.ps, CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id (+6 more)

### Community 51 - "IslandHostingView"
Cohesion: 0.15
Nodes (10): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, Known Fragile Areas, Phase 13B.2 - Native In-Island Clipboard Interface, NSHostingView, NSSize, NSTrackingArea, IslandHostingView, .intrinsicContentSize (+2 more)

### Community 52 - "AppDelegate"
Cohesion: 0.06
Nodes (28): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 11A - Battery Live Activity, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSWindowDelegate, AppDelegate (+20 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - ".openActiveMediaSource"
Cohesion: 0.16
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 55 - "MediaRemoteClient"
Cohesion: 0.14
Nodes (12): CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, MediaRemoteClient, .isAvailable, MediaRemoteDictionary, NowPlayingMediaProvider, Bool, Double (+4 more)

### Community 56 - "CodingKeys"
Cohesion: 0.18
Nodes (11): CodingKey, CodingKeys, files, imagePNG, text, type, url, CodingKeys (+3 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - "Identifiable"
Cohesion: 0.29
Nodes (7): 2026-07-11 - Phase 9D Theme Simplification, Identifiable, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass

### Community 59 - "Phase Workflow For Future Work"
Cohesion: 0.20
Nodes (10): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-04 - Phase 3.4 Album Artwork Stability (+2 more)

### Community 60 - "IslandNavigationStore"
Cohesion: 0.21
Nodes (7): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, IslandNavigationStore, Int, .body, .airDropTargetBinding, .filesTargetBinding

### Community 61 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 62 - "Double"
Cohesion: 0.20
Nodes (13): .visualizerAccentColor, .body, StatsLineChart, .body, StatsMetricCard, .body, Color, Double (+5 more)

### Community 63 - "String"
Cohesion: 0.17
Nodes (10): Decodable, BrowserScriptTarget, Bool, OEmbedResponse, Data, URL, YouTubeMetadata, YouTubeMetadataProvider (+2 more)

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "FileClipboardHistoryPersistence"
Cohesion: 0.31
Nodes (4): FileManager, FileClipboardHistoryPersistence, Data, URL

### Community 66 - ".innerBlurScaleClean"
Cohesion: 0.21
Nodes (7): ExpandedHeaderButton, .clipboardBackdropAnimation, .contentVisibilityAnimation, IslandContentTransitionTiming, SettingsGearButton, TimeInterval, Void

### Community 67 - "AudioVisualizerView"
Cohesion: 0.18
Nodes (11): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerView, .body, .shouldAnimateContinuously, .visualizerOpacity, MediaButton, .body, .constrainedActivePlayerView (+3 more)

### Community 68 - "OverlayGeometrySignature"
Cohesion: 0.15
Nodes (10): Phase 11C.4 - WindowServer Space-Transition Counter-Translation, CustomStringConvertible, QuartzCore, ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicy, OverlayGeometrySignature (+2 more)

### Community 69 - "MediaSnapshot"
Cohesion: 0.15
Nodes (14): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Phase 2.7 Media Source Arbitration, Hashable, MediaDetectionProvider, MediaSnapshot, MediaSourceKind, browser, music (+6 more)

### Community 70 - "FileShelfStoreTests"
Cohesion: 0.29
Nodes (4): 2026-07-04 - Phase 4B.1 Expanded Tray Drop Handoff Fix, FileShelfStoreTests, URL, UserDefaults

### Community 71 - "AppSettings.swift"
Cohesion: 0.25
Nodes (7): Key, VisualizerAccentMode, artwork, .displayName, .id, system, white

### Community 72 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 73 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 74 - "AudioVisualizerVariant"
Cohesion: 0.25
Nodes (8): AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing, CGSize

### Community 75 - "GestureInputSource"
Cohesion: 0.29
Nodes (7): GestureInputSource, camera, .displayName, .id, keyboardShortcut, none, trackpad

### Community 76 - "CollapsedPreviewContent"
Cohesion: 0.13
Nodes (13): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, CollapsedPreviewContent, CollapsedPreviewKind, battery, fileDrop, liveActivity, media, none (+5 more)

### Community 77 - "CollapsedIslandContentMode"
Cohesion: 0.29
Nodes (6): CollapsedIslandContentMode, battery, fileTray, inactive, media, timer

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".trayPage"
Cohesion: 0.27
Nodes (6): NSItemProvider, Bool, .fileDropTargetBinding, FileDropURLAccumulator, .urls, URL

### Community 80 - "ExpandedIslandPage"
Cohesion: 0.22
Nodes (8): ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName, timer, .title, tray

### Community 83 - "SettingsSection"
Cohesion: 0.13
Nodes (15): SettingsSection, advanced, appearance, clipboard, gestures, .id, island, liveActivities (+7 more)

### Community 84 - "DynamicIsland Project Context"
Cohesion: 0.12
Nodes (16): App Entry, Collapsed, Current Architecture, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context, Expanded (+8 more)

### Community 85 - "CompactIslandView"
Cohesion: 0.25
Nodes (8): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, CompactIslandView, .compactContentAnimation, .previewRowAnimation, .shouldShowMediaSession

### Community 87 - "IslandOverlayPanel"
Cohesion: 0.18
Nodes (8): NSPanel, NSView, Native overlay, geometry and input, IslandOverlayPanel, .canBecomeKey, .canBecomeMain, OverlayPersistence, NSWindow

### Community 88 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 90 - "ShortcutEditorRow"
Cohesion: 0.40
Nodes (5): ShortcutEditorRow, .body, Binding, Void, WritableKeyPath

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, LiveActivityStyle, compact, detailed, .id

### Community 94 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 95 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 96 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 97 - ".scrollWheel"
Cohesion: 0.40
Nodes (4): 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix

### Community 103 - ".share"
Cohesion: 0.50
Nodes (3): 2026-07-05 - Phase 8A File Shelf Tray Polish, Bool, URL

## Knowledge Gaps
- **477 isolated node(s):** `PackageDescription`, `package_app.sh script`, `music`, `spotify`, `safari` (+472 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 624 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `Equatable`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `OverlayWindowController`, `View`, `FileShelfStore`, `ExpandedIslandView`, `ObservableObject`, `IslandModules`, `Int`, `DynamicIslandLiveActivity`, `.init`, `ShelfFileTile`, `DynamicIsland`, `MediaModuleView`, `LiveActivitiesModuleView`, `ModuleViews.swift`, `AppSettingsTests`, `CGFloat`, `Change Log`, `AppDelegate`, `.reload`, `OverlayPresentationSessionTests`, `Identifiable`, `IslandNavigationStore`, `String`, `DefaultExpandedTab`, `.innerBlurScaleClean`, `FileShelfStoreTests`, `AppSettings.swift`, `AnimationPreset`, `AutoCollapseDelayPreset`, `GestureInputSource`, `CollapsedIslandContentMode`, `DynamicIsland Project Context`, `CompactIslandView`, `CaseIterable`?**
  _High betweenness centrality (0.298) - this node is a cross-community bridge._
- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `MediaController`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `OverlayWindowController`, `View`, `FileShelfStore`, `SupportedApp`, `FileThumbnailCache`, `XCTestCase`, `ObservableObject`, `IslandModules`, `Int`, `DynamicIslandLiveActivity`, `.init`, `.assignArtwork`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `ShelfFileTile`, `IslandRootView.swift`, `MediaModuleView`, `MediaController.swift`, `ShortcutsStore`, `LiveActivitiesModuleView`, `MediaCandidate`, `IslandStateStore`, `AppSettingsTests`, `Bool`, `CollapsedLiveActivityPrioritySource`, `AppDelegate`, `.reload`, `.openActiveMediaSource`, `MediaRemoteClient`, `CodingKeys`, `Identifiable`, `IslandNavigationStore`, `Double`, `DefaultExpandedTab`, `.innerBlurScaleClean`, `AudioVisualizerView`, `OverlayGeometrySignature`, `MediaSnapshot`, `FileShelfStoreTests`, `AppSettings.swift`, `AnimationPreset`, `AutoCollapseDelayPreset`, `GestureInputSource`, `CollapsedPreviewContent`, `ExpandedIslandPage`, `SettingsSection`, `DynamicIslandLiveActivityKind`, `ShortcutEditorRow`, `CaseIterable`, `.remainingTime`?**
  _High betweenness centrality (0.289) - this node is a cross-community bridge._
- **Why does `IslandRootView` connect `IslandRootView` to `AppSettings`, `IslandGestureAction`, `IslandEscapeRouter`, `MediaController`, `OverlayWindowController`, `View`, `FileThumbnailCache`, `DynamicIsland`, `IslandModules`, `DynamicIslandLiveActivity`, `InnerBlurScaleCleanModifier`, `IslandRootView.swift`, `LiveActivitiesModuleView`, `What You Must Do When Invoked`, `IslandLayoutStore`, `IslandStateStore`, `CGFloat`, `Change Log`, `IslandHostingView`, `AppDelegate`, `IslandNavigationStore`, `.innerBlurScaleClean`, `AudioVisualizerView`, `CollapsedPreviewContent`, `CollapsedIslandContentMode`?**
  _High betweenness centrality (0.102) - this node is a cross-community bridge._
- **Are the 26 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 26 INFERRED edges - model-reasoned connections that need verification._
- **Are the 28 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 28 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `MediaController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5G Native Visualizer And Artwork Color`) actually correct?**
  _`MediaController` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `music` to the rest of the system?**
  _477 weakly-connected nodes found - possible documentation gaps or missing edges._