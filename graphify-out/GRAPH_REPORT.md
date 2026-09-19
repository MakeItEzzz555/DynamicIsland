# Graph Report - DynamicIsland  (2026-09-19)

## Corpus Check
- 82 files · ~118,502 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 2375 nodes · 6086 edges · 101 communities (89 shown, 12 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 786 edges (avg confidence: 0.88)
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
- ClipboardHistoryPresentationState
- ClipboardHistoryStore
- TimerController
- SystemClipboardPasteboardClient
- .constrainedActivePlayerLayout
- ClipboardHistoryPayload
- NotchGeometryService
- ClipboardHistoryStoreTests
- .normalizeAndSaveDouble
- CollapsedLiveActivitySelectorTests
- OverlayWindowController
- View
- FileShelfStore
- SupportedApp
- ExpandedIslandView
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- ClipboardHistoryEntry
- IslandModules
- Int
- DynamicIslandLiveActivity
- .init
- ClipboardImageNormalizerTests
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
- MediaController
- ModuleViews.swift
- IslandStateStore
- AppSettingsTests
- CGFloat
- IslandSurface
- Bool
- CollapsedLiveActivityPrioritySource
- IslandHostingView
- AppDelegate
- .reload
- .openActiveMediaSource
- MediaRemoteClient
- CodingKeys
- OverlayPresentationSessionTests
- ClipboardImageCaptureLifecycleTests
- Foundation
- IslandNavigationStore
- IslandSurfaceBackground
- DedicatedTimerPageView
- String
- Identifiable
- FileClipboardHistoryPersistence
- NSRect
- AudioVisualizerView
- IslandOverlayPanel
- Phase Workflow For Future Work
- FileShelfStoreTests
- XCTestCase
- AnimationPreset
- ClipboardPasteboardReadResult
- LiveActivityStore
- .updateTimerLiveActivity
- BatteryActivityProvider
- Equatable
- Meaningful regression history
- .trayPage
- ExpandedIslandPage
- Package.swift
- package_app.sh
- ExpandedScrollEventRoutingPolicyTests
- DynamicIsland Project Context
- MenuBarController
- .resolve
- App Entry
- IslandContentPhase
- graphify reference: extra exports and benchmark
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- .share

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 319 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 93 edges
5. `IslandRootView` - 73 edges
6. `ExpandedIslandView` - 66 edges
7. `ClipboardHistoryStore` - 55 edges
8. `ExpandedIslandLayoutMetrics` - 47 edges
9. `FileThumbnailCache` - 45 edges
10. `MediaModuleView` - 42 edges

## Surprising Connections (you probably didn't know these)
- `2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `2026-07-11 - Phase 9C Liquid Glass Visual Repair` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `Overlay Windows` --references--> `IslandStateStore`  [INFERRED]
  context.md → Sources/DynamicIsland/State/IslandStateStore.swift
- `Stable native overlay architecture` --references--> `IslandRootView`  [INFERRED]
  README.md → Sources/DynamicIsland/Views/IslandRootView.swift
- `2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse` --references--> `FileThumbnailCache`  [INFERRED]
  context.md → Sources/DynamicIsland/Views/ModuleViews.swift

## Import Cycles
- None detected.

## Communities (101 total, 12 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.03
Nodes (153): AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray, .animateStatsCharts, .animationIntensity (+145 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.08
Nodes (39): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, IslandGestureAction, collapse, .displayName, expand, .id (+31 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (26): 2026-07-04 - Phase 5D Stats Tab, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double, Int (+18 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.13
Nodes (18): ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted (+10 more)

### Community 4 - "SettingsView"
Cohesion: 0.07
Nodes (47): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsSection, advanced (+39 more)

### Community 5 - "IslandRootView"
Cohesion: 0.08
Nodes (23): 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, CollapsedPreviewRowContent, IslandRootView, .collapsedPreviewAnimation, .collapsedPreviewRows, .collapsedPreviewSurfaceFrame (+15 more)

### Community 6 - "ClipboardHistoryPresentationState"
Cohesion: 0.12
Nodes (15): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+7 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.12
Nodes (17): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Data (+9 more)

### Community 8 - "TimerController"
Cohesion: 0.18
Nodes (11): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, Int, Never, Task, Void, TimerController, .displayText, .timerControlRow (+3 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - ".constrainedActivePlayerLayout"
Cohesion: 0.23
Nodes (3): Double, .gestureCallbacks, .regularActivePlayerView

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.07
Nodes (28): Codable, CryptoKit, Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text (+20 more)

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
Cohesion: 0.11
Nodes (5): LiveActivityTimeFormatting, CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "OverlayWindowController"
Cohesion: 0.13
Nodes (13): CFTimeInterval, DispatchWorkItem, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedInteractiveSurfaceFrame, .collapsedScrollThreshold, .visualReferencePanelFrame, Any (+5 more)

### Community 17 - "View"
Cohesion: 0.10
Nodes (29): Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CollapsedBatteryActivityCompactView, CollapsedFileActivityCompactView, .accessibilityLabel, .body, .fileText (+21 more)

### Community 18 - "FileShelfStore"
Cohesion: 0.15
Nodes (14): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, FileShelfStore, AnyCancellable, Set, URL (+6 more)

### Community 19 - "SupportedApp"
Cohesion: 0.11
Nodes (20): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Phase 2 Empty Media Launcher State, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome (+12 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.13
Nodes (10): Phase 13B.2 - Native In-Island Clipboard Interface, ExpandedIslandView, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation, .tabAnimationsEnabled, .tabFadeInAnimation, .tabFadeOutAnimation (+2 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (57): 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+49 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ClipboardHistoryEntry"
Cohesion: 0.10
Nodes (19): Calendar, ObservableObject, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body (+11 more)

### Community 26 - "IslandModules"
Cohesion: 0.47
Nodes (4): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, Composition, state and settings, IslandModule, IslandModules

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.22
Nodes (13): Candidate, CollapsedLiveActivityPrioritySettings, .defaults, CollapsedLiveActivitySelector, CollapsedLiveActivitySourceToggles, DynamicIslandLiveActivity, Bool, Date (+5 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.08
Nodes (17): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageRepresentation, encoded, oversized, ClipboardImageResourcePolicy (+9 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.20
Nodes (4): Decision, Date, MediaArbitratorTests, Bool

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "ShelfFileTile"
Cohesion: 0.21
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, 2026-07-04 - Phase 5I.2 Animation Performance Polish, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool (+1 more)

### Community 34 - "InnerBlurScaleCleanModifier"
Cohesion: 0.10
Nodes (22): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier (+14 more)

### Community 35 - "DynamicIsland"
Cohesion: 0.19
Nodes (3): AppKit, DynamicIsland, XCTest

### Community 36 - "IslandRootView.swift"
Cohesion: 0.08
Nodes (39): EnvironmentKey, AirDropDropZoneView, .body, .subtitle, .accessibilityLabel, .body, .iconColor, .percentText (+31 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.08
Nodes (25): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, MediaModuleView, .activePlayerView, .artistFontSize, .artworkSize (+17 more)

### Community 38 - "MediaController.swift"
Cohesion: 0.13
Nodes (18): 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Element, Index, Media and artwork, Array, ArtworkPresentationCoordinator, .displayedSnapshot (+10 more)

### Community 39 - "ShortcutsStore"
Cohesion: 0.15
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+2 more)

### Community 40 - "LiveActivitiesModuleView"
Cohesion: 0.47
Nodes (5): LiveActivitiesModuleView, .body, .remainingActivityCount, .visibleActivities, CGSize

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.06
Nodes (32): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+24 more)

### Community 42 - "IslandLayoutStore"
Cohesion: 0.14
Nodes (16): 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, IslandLayoutStore, Bool, CGFloat, CGRect (+8 more)

### Community 43 - "MediaController"
Cohesion: 0.12
Nodes (13): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, BrowserScriptTarget, MediaArbitrator, MediaCandidate, .sourceKey, MediaController, .currentArtworkPresentationIdentity, MediaSourceIdentity (+5 more)

### Community 44 - "ModuleViews.swift"
Cohesion: 0.12
Nodes (21): 2026-07-05 - Phase 8C.10 Gesture Responsiveness And Artwork Flip, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, AlbumArtworkView, .body, ClickableAlbumArtworkButton, .artwork, .body (+13 more)

### Community 45 - "IslandStateStore"
Cohesion: 0.17
Nodes (8): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, IslandPresentationState, collapsed, expanded, IslandStateStore, .isExpandedSurfaceVisible, Bool, IslandStateStoreTests

### Community 47 - "CGFloat"
Cohesion: 0.13
Nodes (15): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline, Evidence and graph limits, SwiftUI rendering and presentation (+7 more)

### Community 48 - "IslandSurface"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor, 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix, 2026-07-04 - Phase 6A.2 Single-Panel Native Morph Correction, 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, 2026-07-04 - Phase 6A Single Adaptive Island Panel, 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership, 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing, Phase 12B.1 - Shell Shadow Removal (+8 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "IslandHostingView"
Cohesion: 0.14
Nodes (10): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, Known Fragile Areas, NSHostingView, NSSize, NSTrackingArea, NSView, IslandHostingView, .intrinsicContentSize (+2 more)

### Community 52 - "AppDelegate"
Cohesion: 0.09
Nodes (16): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSWindowDelegate, AppDelegate, DynamicIslandApp (+8 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - ".openActiveMediaSource"
Cohesion: 0.17
Nodes (6): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 55 - "MediaRemoteClient"
Cohesion: 0.13
Nodes (13): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, MediaRemoteClient, .isAvailable, MediaRemoteDictionary, NowPlayingMediaProvider, Bool (+5 more)

### Community 56 - "CodingKeys"
Cohesion: 0.18
Nodes (11): CodingKey, CodingKeys, files, imagePNG, text, type, url, CodingKeys (+3 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.16
Nodes (8): OverlayPresentationSession, .canPresentOverlay, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval, Void

### Community 58 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.18
Nodes (9): CheckedContinuation, MainActor, ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, Data, Never, Sendable (+1 more)

### Community 59 - "Foundation"
Cohesion: 0.12
Nodes (7): Combine, Darwin, Foundation, ServiceManagement, LaunchAtLoginController, Bool, AirDropService

### Community 60 - "IslandNavigationStore"
Cohesion: 0.21
Nodes (7): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, IslandNavigationStore, Int, .body, .airDropTargetBinding, .filesTargetBinding

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "DedicatedTimerPageView"
Cohesion: 0.13
Nodes (17): .visualizerAccentColor, DedicatedTimerPageView, .body, .controlsFontSize, .controlsSpacing, .titleFontSize, .usesCompactLayout, StatsLineChart (+9 more)

### Community 63 - "String"
Cohesion: 0.13
Nodes (16): Decodable, AppleScriptExecutionResult, MediaPlayer, .displayName, music, .playPauseCommand, spotify, bundleIdentifier (+8 more)

### Community 64 - "Identifiable"
Cohesion: 0.05
Nodes (44): CaseIterable, 2026-07-11 - Phase 9D Theme Simplification, Identifiable, AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds (+36 more)

### Community 65 - "FileClipboardHistoryPersistence"
Cohesion: 0.31
Nodes (4): FileManager, FileClipboardHistoryPersistence, Data, URL

### Community 66 - "NSRect"
Cohesion: 0.19
Nodes (6): NSPoint, NSRect, .collapsedGestureCandidateScreenRegion, .currentVisibleIslandScreenRect, CGFloat, CGRect

### Community 67 - "AudioVisualizerView"
Cohesion: 0.15
Nodes (15): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing (+7 more)

### Community 68 - "IslandOverlayPanel"
Cohesion: 0.10
Nodes (18): Phase 11C.3 - Diagnostic WindowServer Transition Trace, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, NSPanel, QuartzCore, Native overlay, geometry and input, ExpandedScrollEventRoute (+10 more)

### Community 69 - "Phase Workflow For Future Work"
Cohesion: 0.09
Nodes (24): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration (+16 more)

### Community 70 - "FileShelfStoreTests"
Cohesion: 0.33
Nodes (3): FileShelfStoreTests, URL, UserDefaults

### Community 71 - "XCTestCase"
Cohesion: 0.17
Nodes (8): Double, TimerProgressColorStage, high, low, mid, TimerProgressFormatting, TimerProgressFormattingTests, XCTestCase

### Community 72 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 73 - "ClipboardPasteboardReadResult"
Cohesion: 0.19
Nodes (12): Sendable, ClipboardImageCapture, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult, empty, oversized (+4 more)

### Community 74 - "LiveActivityStore"
Cohesion: 0.31
Nodes (5): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int

### Community 75 - ".updateTimerLiveActivity"
Cohesion: 0.30
Nodes (3): Bool, Int, URL

### Community 76 - "BatteryActivityProvider"
Cohesion: 0.29
Nodes (5): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, Any, .description

### Community 77 - "Equatable"
Cohesion: 0.13
Nodes (15): Equatable, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, DynamicIslandLiveActivityKind (+7 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".trayPage"
Cohesion: 0.27
Nodes (6): NSItemProvider, Bool, .fileDropTargetBinding, FileDropURLAccumulator, .urls, URL

### Community 80 - "ExpandedIslandPage"
Cohesion: 0.22
Nodes (8): ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName, timer, .title, tray

### Community 84 - "DynamicIsland Project Context"
Cohesion: 0.20
Nodes (9): Collapsed, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context, Expanded, Non-Negotiable Behavior To Preserve, Purpose (+1 more)

### Community 85 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 87 - "App Entry"
Cohesion: 0.29
Nodes (7): App Entry, Current Architecture, Geometry, Modules, Overlay Windows, State, Views

### Community 88 - "IslandContentPhase"
Cohesion: 0.33
Nodes (6): IslandContentPhase, compact, contentCollapsing, expandedContentVisible, shellCollapsing, shellExpanding

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 94 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 95 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 96 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 103 - ".share"
Cohesion: 0.50
Nodes (3): 2026-07-05 - Phase 8A File Shelf Tray Polish, Bool, URL

## Knowledge Gaps
- **481 isolated node(s):** `PackageDescription`, `package_app.sh script`, `music`, `spotify`, `safari` (+476 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 642 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `TimerController`, `.constrainedActivePlayerLayout`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `OverlayWindowController`, `View`, `FileShelfStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `ClipboardHistoryEntry`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `ShelfFileTile`, `IslandRootView.swift`, `MediaModuleView`, `MediaController.swift`, `ShortcutsStore`, `IslandLayoutStore`, `MediaController`, `ModuleViews.swift`, `IslandStateStore`, `AppSettingsTests`, `Bool`, `CollapsedLiveActivityPrioritySource`, `.reload`, `.openActiveMediaSource`, `MediaRemoteClient`, `CodingKeys`, `IslandNavigationStore`, `DedicatedTimerPageView`, `Identifiable`, `NSRect`, `IslandOverlayPanel`, `Phase Workflow For Future Work`, `FileShelfStoreTests`, `AnimationPreset`, `LiveActivityStore`, `.updateTimerLiveActivity`, `BatteryActivityProvider`, `Equatable`, `ExpandedIslandPage`?**
  _High betweenness centrality (0.333) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `OverlayWindowController`, `View`, `FileShelfStore`, `ExpandedIslandView`, `ClipboardHistoryEntry`, `IslandModules`, `Int`, `DynamicIslandLiveActivity`, `.init`, `ShelfFileTile`, `InnerBlurScaleCleanModifier`, `IslandRootView.swift`, `MediaModuleView`, `ShortcutsStore`, `LiveActivitiesModuleView`, `ModuleViews.swift`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `IslandSurface`, `AppDelegate`, `.reload`, `OverlayPresentationSessionTests`, `ClipboardImageCaptureLifecycleTests`, `IslandNavigationStore`, `DedicatedTimerPageView`, `String`, `Identifiable`, `FileShelfStoreTests`, `AnimationPreset`, `.updateTimerLiveActivity`, `MenuBarController`, `App Entry`?**
  _High betweenness centrality (0.270) - this node is a cross-community bridge._
- **Why does `Change Log` connect `Change Log` to `IslandGestureAction`, `SystemStatsController`, `IslandRootView`, `ClipboardHistoryPresentationState`, `TimerController`, `NotchGeometryService`, `View`, `FileShelfStore`, `ExpandedIslandView`, `ExpandedIslandLayoutMetrics`, `ArtworkAccentColorCache`, `ShelfFileTile`, `InnerBlurScaleCleanModifier`, `MediaModuleView`, `IslandLayoutStore`, `MediaController`, `ModuleViews.swift`, `IslandStateStore`, `CGFloat`, `IslandSurface`, `IslandHostingView`, `AppDelegate`, `.reload`, `IslandNavigationStore`, `IslandSurfaceBackground`, `Identifiable`, `AudioVisualizerView`, `IslandOverlayPanel`, `BatteryActivityProvider`, `DynamicIsland Project Context`, `.share`?**
  _High betweenness centrality (0.066) - this node is a cross-community bridge._
- **Are the 27 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 27 INFERRED edges - model-reasoned connections that need verification._
- **Are the 28 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 28 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `MediaController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5G Native Visualizer And Artwork Color`) actually correct?**
  _`MediaController` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `music` to the rest of the system?**
  _481 weakly-connected nodes found - possible documentation gaps or missing edges._