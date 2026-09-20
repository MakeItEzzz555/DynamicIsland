# Graph Report - DynamicIsland  (2026-09-20)

## Corpus Check
- 85 files · ~124,028 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 2553 nodes · 6711 edges · 106 communities (93 shown, 13 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 882 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `624a1927`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- AppSettings
- IslandGestureAction
- SystemStatsController
- ArtworkFlipPresentationState
- SettingsView
- IslandRootView
- ClipboardHistoryPresentationState
- ClipboardHistoryStore
- TimerController
- SystemClipboardPasteboardClient
- .constrainedActivePlayerLayout
- Equatable
- NotchGeometryService
- ClipboardHistoryStoreTests
- .normalizeAndSaveDouble
- CollapsedLiveActivitySelectorTests
- NSRect
- .opacity
- FileShelfStore
- SupportedApp
- ExpandedIslandView
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- ClipboardHistoryView
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- .init
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- ShelfFileTile
- ShortcutsStore
- AppKit
- CompactIslandView
- MediaModuleView
- MediaCandidate
- AppDelegate
- SettingsSection
- What You Must Do When Invoked
- Double
- MediaController
- CGFloat
- IslandStateStore
- AppSettingsTests
- CGFloat
- InnerBlurScaleCleanModifier
- OverlayWindowController
- CollapsedLiveActivityPrioritySource
- View
- .updateTimerLiveActivity
- .reload
- .openActiveMediaSource
- ManualMediaRemoteDeadlineScheduler
- XCTestCase
- OverlayPresentationSessionTests
- ClipboardImageCaptureLifecycleTests
- Foundation
- AppSettings.swift
- IslandSurfaceBackground
- Phase Workflow For Future Work
- CodingKeys
- DefaultExpandedTab
- FileClipboardHistoryPersistence
- ExpandedScrollEventRoutingPolicyTests
- AudioVisualizerView
- Sendable
- String
- AutoCollapseDelayPreset
- IslandHostingView
- AnimationPreset
- Identifiable
- GestureInputSource
- LiveActivityStore
- DynamicIslandLiveActivityKind
- CollapsedIslandContentMode
- Meaningful regression history
- .loadFileURLs
- .resolve
- Package.swift
- package_app.sh
- IslandLayoutStore
- ModuleViews.swift
- CaseIterable
- LaunchAtLoginController.swift
- BatteryActivityProvider
- graphify reference: extra exports and benchmark
- .remainingTime
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- MediaController.swift
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- Fresh critical audit instructions
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- SwiftUI
- MenuBarController
- IslandRootView.swift

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 319 edges
2. `OverlayWindowController` - 135 edges
3. `Change Log` - 110 edges
4. `MediaController` - 105 edges
5. `IslandRootView` - 73 edges
6. `ExpandedIslandView` - 66 edges
7. `ClipboardHistoryStore` - 55 edges
8. `ExpandedIslandLayoutMetrics` - 47 edges
9. `FileThumbnailCache` - 45 edges
10. `ArtworkFlipPresentationState` - 42 edges

## Surprising Connections (you probably didn't know these)
- `2026-07-03 - Common App Launch Resolver` --references--> `AppLaunchService`  [INFERRED]
  context.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `Stable native overlay architecture` --references--> `IslandRootView`  [INFERRED]
  README.md → Sources/DynamicIsland/Views/IslandRootView.swift
- `2026-07-04 - Phase 5J.6 Premium Motion Re-Polish` --references--> `InnerBlurScaleCleanModifier`  [INFERRED]
  context.md → Sources/DynamicIsland/Views/IslandRootView.swift
- `2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse` --references--> `FileThumbnailCache`  [INFERRED]
  context.md → Sources/DynamicIsland/Views/ModuleViews.swift
- `2026-07-06 - Git Repo Restoration And Stable Final Tag` --references--> `FileThumbnailCache`  [INFERRED]
  context.md → Sources/DynamicIsland/Views/ModuleViews.swift

## Import Cycles
- None detected.

## Communities (106 total, 13 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.03
Nodes (153): AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray, .animateStatsCharts, .animationIntensity (+145 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.08
Nodes (37): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, IslandGestureAction, collapse, .displayName, expand, .id, mediaNextTrack (+29 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (27): 2026-07-04 - Phase 7A Comprehensive Settings Foundation, Darwin, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+19 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.13
Nodes (18): ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted (+10 more)

### Community 4 - "SettingsView"
Cohesion: 0.12
Nodes (32): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsView, .advancedSection (+24 more)

### Community 5 - "IslandRootView"
Cohesion: 0.08
Nodes (29): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, IslandModules, CollapsedPreviewContent, CollapsedPreviewRowContent, ExpandedIslandRightStackVisibility (+21 more)

### Community 6 - "ClipboardHistoryPresentationState"
Cohesion: 0.12
Nodes (15): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+7 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.11
Nodes (20): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Data (+12 more)

### Community 8 - "TimerController"
Cohesion: 0.14
Nodes (16): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, Int, Never, Task, Void, TimerController, .displayText, DedicatedTimerPageView (+8 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - ".constrainedActivePlayerLayout"
Cohesion: 0.31
Nodes (5): Double, MediaButton, .body, .constrainedActivePlayerView, .regularActivePlayerView

### Community 11 - "Equatable"
Cohesion: 0.08
Nodes (29): Codable, CryptoKit, Decoder, Encoder, Equatable, ClipboardHistoryEntryKind, files, image (+21 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.12
Nodes (18): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry (+10 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.17
Nodes (8): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Data, Date, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (18): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+10 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "NSRect"
Cohesion: 0.15
Nodes (7): 2026-07-04 - Phase 5J.4 Final Media Fit And Mouse Leave Rect Fix, 2026-07-04 - Phase 5J.5 Final Expanded Hover Tolerance Tightening, NSRect, .collapsedGestureCandidateScreenRegion, .currentVisibleIslandScreenRect, CGFloat, CGRect

### Community 17 - ".opacity"
Cohesion: 0.15
Nodes (23): .body, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, .percentText, .body, .body (+15 more)

### Community 18 - "FileShelfStore"
Cohesion: 0.06
Nodes (33): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 5D Stats Tab, 2026-07-05 - Phase 8A File Shelf Tray Polish, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, Bool (+25 more)

### Community 19 - "SupportedApp"
Cohesion: 0.11
Nodes (19): 2026-07-03 - Phase 2 Empty Media Launcher State, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName (+11 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.12
Nodes (18): 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor, 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix, 2026-07-04 - Phase 6A.2 Single-Panel Native Morph Correction, 2026-07-04 - Phase 6A Single Adaptive Island Panel, 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership, 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing, Phase 12B.1 - Shell Shadow Removal, Phase 12C.2 - Notch-Aware Body-Relative Content Insets (+10 more)

### Community 21 - "Change Log"
Cohesion: 0.06
Nodes (51): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+43 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ClipboardHistoryView"
Cohesion: 0.12
Nodes (12): Calendar, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body, .emptyState, .header, Bool, Date (+4 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.05
Nodes (49): Clock, Hashable, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult (+41 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.17
Nodes (14): Candidate, CollapsedLiveActivityPrioritySettings, .defaults, CollapsedLiveActivitySelector, CollapsedLiveActivitySourceToggles, DynamicIslandLiveActivity, Bool, Date (+6 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (13): CFDictionary, CGImageSource, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Data, Int (+5 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.19
Nodes (3): MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "ShelfFileTile"
Cohesion: 0.23
Nodes (8): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, URL

### Community 34 - "ShortcutsStore"
Cohesion: 0.15
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+2 more)

### Community 35 - "AppKit"
Cohesion: 0.18
Nodes (4): AppKit, DynamicIsland, ImageIO, XCTest

### Community 36 - "CompactIslandView"
Cohesion: 0.12
Nodes (21): Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CollapsedFileActivityCompactView, .accessibilityLabel, .fileText, CollapsedTimerActivityCompactView, .accessibilityLabel (+13 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.09
Nodes (23): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, MediaModuleView, .activePlayerView, .artistFontSize, .artworkSize, .body (+15 more)

### Community 38 - "MediaCandidate"
Cohesion: 0.10
Nodes (20): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Phase 2.7 Media Source Arbitration, 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, MediaArbitrator, MediaCandidate, .sourceKey, MediaSourceIdentity, .debugDescription (+12 more)

### Community 39 - "AppDelegate"
Cohesion: 0.12
Nodes (14): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSWindowDelegate, AppDelegate, Any (+6 more)

### Community 40 - "SettingsSection"
Cohesion: 0.13
Nodes (15): SettingsSection, advanced, appearance, clipboard, gestures, .id, island, liveActivities (+7 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "Double"
Cohesion: 0.12
Nodes (20): Interpreter guard for subcommands, Path, CollapsedPreviewActivityRow, .iconColor, CollapsedPreviewRow, .body, .visualizerAccentColor, .body (+12 more)

### Community 43 - "MediaController"
Cohesion: 0.14
Nodes (7): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, BrowserScriptTarget, MediaController, .currentArtworkPresentationIdentity, Bool, NSImage, .gestureCallbacks

### Community 44 - "CGFloat"
Cohesion: 0.17
Nodes (13): 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, AlbumArtworkView, .body, ClickableAlbumArtworkButton, .artwork, .body, .body (+5 more)

### Community 45 - "IslandStateStore"
Cohesion: 0.07
Nodes (27): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, App Entry, Collapsed, Current Architecture, Current Stable Baseline, Current UI/Interaction Requirements (+19 more)

### Community 47 - "CGFloat"
Cohesion: 0.20
Nodes (11): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, IslandShellLayout, IslandShellRadii, IslandShellShape, .animatableData (+3 more)

### Community 48 - "InnerBlurScaleCleanModifier"
Cohesion: 0.12
Nodes (19): Animation, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, Phase 13B.2 - Native In-Island Clipboard Interface, Gesture, AnyTransition, .blurBounce, .compactMediaContent (+11 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.09
Nodes (18): CFTimeInterval, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-11 - Phase 9C Liquid Glass Visual Repair, DispatchWorkItem, NSPoint, OverlayWindowController, .collapsedGestureCandidateRegion (+10 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "View"
Cohesion: 0.17
Nodes (15): AirDropDropZoneView, .subtitle, ExpandedHeaderButton, ExpandedIslandPageSwitcher, ExtraLiveActivityCard, FileDropHighlightView, LiveActivitiesModuleView, .body (+7 more)

### Community 52 - ".updateTimerLiveActivity"
Cohesion: 0.30
Nodes (3): Bool, Int, URL

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - ".openActiveMediaSource"
Cohesion: 0.17
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 55 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.06
Nodes (41): CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, value, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending, MediaRemoteClient (+33 more)

### Community 56 - "XCTestCase"
Cohesion: 0.17
Nodes (8): Double, TimerProgressColorStage, high, low, mid, TimerProgressFormatting, TimerProgressFormattingTests, XCTestCase

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.17
Nodes (9): MainActor, ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, CheckedContinuation, Data, Never, Sendable (+1 more)

### Community 59 - "Foundation"
Cohesion: 0.22
Nodes (3): Combine, Foundation, AirDropService

### Community 60 - "AppSettings.swift"
Cohesion: 0.25
Nodes (7): Key, VisualizerAccentMode, artwork, .displayName, .id, system, white

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "Phase Workflow For Future Work"
Cohesion: 0.12
Nodes (19): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard (+11 more)

### Community 63 - "CodingKeys"
Cohesion: 0.18
Nodes (11): CodingKey, CodingKeys, files, imagePNG, text, type, url, CodingKeys (+3 more)

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "FileClipboardHistoryPersistence"
Cohesion: 0.31
Nodes (4): FileManager, FileClipboardHistoryPersistence, Data, URL

### Community 67 - "AudioVisualizerView"
Cohesion: 0.33
Nodes (7): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerView, .body, .shouldAnimateContinuously, .visualizerOpacity, Double, TimeInterval

### Community 68 - "Sendable"
Cohesion: 0.16
Nodes (15): Sendable, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image, ready (+7 more)

### Community 69 - "String"
Cohesion: 0.14
Nodes (13): Decodable, MediaPlayer, .displayName, music, .playPauseCommand, spotify, OEmbedResponse, Data (+5 more)

### Community 70 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 71 - "IslandHostingView"
Cohesion: 0.06
Nodes (32): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, Phase 11C.3 - Diagnostic WindowServer Transition Trace, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings (+24 more)

### Community 72 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 73 - "Identifiable"
Cohesion: 0.29
Nodes (7): 2026-07-11 - Phase 9D Theme Simplification, Identifiable, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass

### Community 74 - "GestureInputSource"
Cohesion: 0.29
Nodes (7): GestureInputSource, camera, .displayName, .id, keyboardShortcut, none, trackpad

### Community 75 - "LiveActivityStore"
Cohesion: 0.31
Nodes (5): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int

### Community 76 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 77 - "CollapsedIslandContentMode"
Cohesion: 0.33
Nodes (6): CollapsedIslandContentMode, battery, fileTray, inactive, media, timer

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.26
Nodes (6): NSItemProvider, Bool, .fileDropTargetBinding, FileDropURLAccumulator, .urls, URL

### Community 83 - "IslandLayoutStore"
Cohesion: 0.11
Nodes (19): 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, ObservableObject, IslandLayoutStore, Bool, CGFloat, CGRect (+11 more)

### Community 84 - "ModuleViews.swift"
Cohesion: 0.13
Nodes (14): AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing, CompactShelfBadge (+6 more)

### Community 85 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, LiveActivityStyle, compact, detailed, .id

### Community 86 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 88 - "BatteryActivityProvider"
Cohesion: 0.29
Nodes (5): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, Any, .description

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "MediaController.swift"
Cohesion: 0.15
Nodes (15): Element, Index, Array, ArtworkPresentationCoordinator, .displayedSnapshot, MediaArtworkFlipDirection, next, previous (+7 more)

### Community 94 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 95 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 96 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 97 - "Fresh critical audit instructions"
Cohesion: 0.29
Nodes (6): Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits

### Community 104 - "SwiftUI"
Cohesion: 0.14
Nodes (9): Activities and utility modules, Build and tests, Clipboard engine and persistence, Composition, state and settings, Current architecture baseline, Evidence and graph limits, DynamicIslandApp, IslandModule (+1 more)

### Community 105 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 106 - "IslandRootView.swift"
Cohesion: 0.09
Nodes (23): EnvironmentKey, CollapseShellOnlyEnvironmentKey, EnvironmentValues, .isCollapseShellOnly, .isNotchIntegratedShell, .isShellMorphing, ExpandedTabTransitionPhase, fadingIn (+15 more)

## Knowledge Gaps
- **500 isolated node(s):** `PackageDescription`, `package_app.sh script`, `music`, `spotify`, `safari` (+495 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 666 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `.constrainedActivePlayerLayout`, `Equatable`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `NSRect`, `.opacity`, `FileShelfStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `ClipboardHistoryView`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `ShelfFileTile`, `ShortcutsStore`, `CompactIslandView`, `MediaModuleView`, `MediaCandidate`, `SettingsSection`, `Double`, `MediaController`, `IslandStateStore`, `AppSettingsTests`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `View`, `.updateTimerLiveActivity`, `.reload`, `.openActiveMediaSource`, `ManualMediaRemoteDeadlineScheduler`, `AppSettings.swift`, `Phase Workflow For Future Work`, `CodingKeys`, `DefaultExpandedTab`, `AutoCollapseDelayPreset`, `IslandHostingView`, `AnimationPreset`, `Identifiable`, `GestureInputSource`, `LiveActivityStore`, `DynamicIslandLiveActivityKind`, `IslandLayoutStore`, `ModuleViews.swift`, `CaseIterable`, `.collapsedPreviewContent`, `BatteryActivityProvider`, `.remainingTime`, `MediaController.swift`, `IslandRootView.swift`?**
  _High betweenness centrality (0.346) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `FileShelfStore`, `ExpandedIslandView`, `Int`, `DynamicIslandLiveActivity`, `.init`, `ShelfFileTile`, `ShortcutsStore`, `CompactIslandView`, `MediaModuleView`, `AppDelegate`, `CGFloat`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `InnerBlurScaleCleanModifier`, `OverlayWindowController`, `View`, `.updateTimerLiveActivity`, `.reload`, `OverlayPresentationSessionTests`, `ClipboardImageCaptureLifecycleTests`, `AppSettings.swift`, `DefaultExpandedTab`, `String`, `AutoCollapseDelayPreset`, `AnimationPreset`, `Identifiable`, `GestureInputSource`, `IslandLayoutStore`, `CaseIterable`, `MenuBarController`?**
  _High betweenness centrality (0.264) - this node is a cross-community bridge._
- **Why does `IslandRootView` connect `IslandRootView` to `AppSettings`, `IslandGestureAction`, `ClipboardHistoryPresentationState`, `FileShelfStore`, `ExpandedIslandView`, `Change Log`, `DynamicIsland`, `DynamicIslandLiveActivity`, `.init`, `AppDelegate`, `Double`, `MediaController`, `IslandStateStore`, `CGFloat`, `InnerBlurScaleCleanModifier`, `OverlayWindowController`, `View`, `AudioVisualizerView`, `IslandHostingView`, `LiveActivityStore`, `CollapsedIslandContentMode`, `.loadFileURLs`, `IslandLayoutStore`, `IslandRootView.swift`?**
  _High betweenness centrality (0.074) - this node is a cross-community bridge._
- **Are the 27 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 27 INFERRED edges - model-reasoned connections that need verification._
- **Are the 28 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 28 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `MediaController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5G Native Visualizer And Artwork Color`) actually correct?**
  _`MediaController` has 14 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `music` to the rest of the system?**
  _500 weakly-connected nodes found - possible documentation gaps or missing edges._