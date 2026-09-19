# Graph Report - DynamicIsland  (2026-09-19)

## Corpus Check
- 84 files · ~121,289 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 2474 nodes · 6428 edges · 107 communities (92 shown, 15 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 828 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `d69f00db`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- AppSettings
- IslandGestureAction
- SystemStatsController
- Equatable
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
- CompactCollapsedSideSlotLayout
- IslandNavigationStore
- SupportedApp
- ExpandedIslandView
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- ClipboardHistoryEntry
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- .init
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- ShelfFileTile
- BlurBounceModifier
- DynamicIsland
- View
- MediaModuleView
- MediaCandidate
- ShortcutsStore
- SettingsSection
- What You Must Do When Invoked
- IslandLayoutStore
- MediaController
- ModuleViews.swift
- IslandStateStore
- AppSettingsTests
- CGFloat
- Bool
- Bool
- CollapsedLiveActivityPrioritySource
- FileShelfStore
- AppDelegate
- .reload
- .openActiveMediaSource
- MediaRemoteClient
- CodingKeys
- OverlayPresentationSessionTests
- ClipboardImageCaptureLifecycleTests
- Foundation
- AppSettings.swift
- IslandSurfaceBackground
- Sendable
- String
- DefaultExpandedTab
- FileClipboardHistoryPersistence
- IslandHostingView
- AudioVisualizerView
- IslandOverlayPanel
- Phase Workflow For Future Work
- AutoCollapseDelayPreset
- AudioVisualizerVariant
- AnimationPreset
- Identifiable
- GestureInputSource
- LiveActivityStore
- DynamicIslandLiveActivityKind
- CollapsedIslandContentMode
- Meaningful regression history
- .loadFileURLs
- ShortcutEditorRow
- Package.swift
- package_app.sh
- ExpandedScrollEventRoutingPolicyTests
- DynamicIsland Project Context
- CaseIterable
- .resolve
- .subscript
- graphify reference: extra exports and benchmark
- .remainingTime
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- ExpandedIslandPage
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- FileShelfStoreTests
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- SettingsWindowController
- SwiftUI
- MenuBarController
- IslandContentPhase

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 319 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 101 edges
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
- `Phase 11C.3 - Diagnostic WindowServer Transition Trace` --references--> `IslandOverlayPanel`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `Stable native overlay architecture` --references--> `IslandRootView`  [INFERRED]
  README.md → Sources/DynamicIsland/Views/IslandRootView.swift
- `2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse` --references--> `FileThumbnailCache`  [INFERRED]
  context.md → Sources/DynamicIsland/Views/ModuleViews.swift

## Import Cycles
- None detected.

## Communities (107 total, 15 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.03
Nodes (153): AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray, .animateStatsCharts, .animationIntensity (+145 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (39): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, IslandGestureAction, collapse, .displayName, expand, .id (+31 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (32): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+24 more)

### Community 3 - "Equatable"
Cohesion: 0.10
Nodes (27): Equatable, ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted (+19 more)

### Community 4 - "SettingsView"
Cohesion: 0.16
Nodes (27): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsView, .advancedSection (+19 more)

### Community 5 - "IslandRootView"
Cohesion: 0.05
Nodes (53): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5J Single Visual Surface Morph, 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 11C.9 - Predictive Space Motion Resampling (+45 more)

### Community 6 - "ClipboardHistoryPresentationState"
Cohesion: 0.12
Nodes (15): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+7 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.12
Nodes (17): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Data (+9 more)

### Community 8 - "TimerController"
Cohesion: 0.08
Nodes (24): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, Double, Int, Never, Task, Void, TimerController, .displayText (+16 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - ".constrainedActivePlayerLayout"
Cohesion: 0.39
Nodes (3): Double, .constrainedActivePlayerView, .regularActivePlayerView

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.07
Nodes (28): Codable, CryptoKit, Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text (+20 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.12
Nodes (19): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth (+11 more)

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
Cohesion: 0.12
Nodes (13): CFTimeInterval, DispatchWorkItem, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedInteractiveSurfaceFrame, .collapsedScrollThreshold, .visualReferencePanelFrame, Any (+5 more)

### Community 17 - "CompactCollapsedSideSlotLayout"
Cohesion: 0.38
Nodes (6): 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CompactCollapsedSideSlotLayout, .body

### Community 18 - "IslandNavigationStore"
Cohesion: 0.21
Nodes (7): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, IslandNavigationStore, Int, .body, .airDropTargetBinding, .filesTargetBinding

### Community 19 - "SupportedApp"
Cohesion: 0.11
Nodes (20): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Phase 2 Empty Media Launcher State, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome (+12 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.12
Nodes (16): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, Phase 12A - Final Island Content Transition Sequencing, ExpandedIslandView, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation (+8 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (60): 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+52 more)

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

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (47): Clock, Hashable, Result, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation (+39 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.17
Nodes (14): Candidate, CollapsedLiveActivityPrioritySettings, .defaults, CollapsedLiveActivitySelector, CollapsedLiveActivitySourceToggles, DynamicIslandLiveActivity, Bool, Date (+6 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.08
Nodes (17): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageRepresentation, encoded, oversized, ClipboardImageResourcePolicy (+9 more)

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "ShelfFileTile"
Cohesion: 0.20
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, NSImage (+1 more)

### Community 34 - "BlurBounceModifier"
Cohesion: 0.40
Nodes (6): AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, UnitPoint, ViewModifier

### Community 35 - "DynamicIsland"
Cohesion: 0.16
Nodes (3): AppKit, DynamicIsland, XCTest

### Community 36 - "View"
Cohesion: 0.05
Nodes (71): 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, EnvironmentKey, AirDropDropZoneView, .body, .subtitle, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body (+63 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.09
Nodes (22): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, MediaModuleView, .activePlayerView, .artistFontSize, .artworkSize, .body, .disabledState (+14 more)

### Community 38 - "MediaCandidate"
Cohesion: 0.18
Nodes (9): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Decision, MediaArbitrator, MediaCandidate, .sourceKey, MediaPausedSwitchGate, Date (+1 more)

### Community 39 - "ShortcutsStore"
Cohesion: 0.15
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+2 more)

### Community 40 - "SettingsSection"
Cohesion: 0.13
Nodes (15): SettingsSection, advanced, appearance, clipboard, gestures, .id, island, liveActivities (+7 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.06
Nodes (32): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+24 more)

### Community 42 - "IslandLayoutStore"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, IslandLayoutStore, Bool, CGFloat, CGRect (+8 more)

### Community 43 - "MediaController"
Cohesion: 0.13
Nodes (8): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, BrowserScriptTarget, MediaArtworkFlipRequest, .isExpired, MediaController, .currentArtworkPresentationIdentity, MediaRefreshTimerLifetime, Timer

### Community 44 - "ModuleViews.swift"
Cohesion: 0.15
Nodes (17): 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, AlbumArtworkView, .body, ClickableAlbumArtworkButton, .artwork, .body, EmptyMediaLauncherView (+9 more)

### Community 45 - "IslandStateStore"
Cohesion: 0.11
Nodes (17): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, App Entry, Current Architecture, Geometry, Modules, Overlay Windows, State (+9 more)

### Community 47 - "CGFloat"
Cohesion: 0.13
Nodes (16): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline, Evidence and graph limits, SwiftUI rendering and presentation (+8 more)

### Community 48 - "Bool"
Cohesion: 0.18
Nodes (4): MediaSourceIdentity, .debugDescription, Bool, NSImage

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.10
Nodes (18): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, Any, CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank (+10 more)

### Community 51 - "FileShelfStore"
Cohesion: 0.17
Nodes (12): 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge (+4 more)

### Community 52 - "AppDelegate"
Cohesion: 0.16
Nodes (10): Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, AppDelegate, Any, AnyCancellable, Bool, Int, Notification (+2 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - ".openActiveMediaSource"
Cohesion: 0.16
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 55 - "MediaRemoteClient"
Cohesion: 0.13
Nodes (13): CopyAppDisplayNameFunction, Darwin, GetNowPlayingInfoFunction, NSDictionary, MediaRemoteClient, .isAvailable, MediaRemoteDictionary, NowPlayingMediaProvider (+5 more)

### Community 56 - "CodingKeys"
Cohesion: 0.18
Nodes (11): CodingKey, CodingKeys, files, imagePNG, text, type, url, CodingKeys (+3 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.18
Nodes (9): CheckedContinuation, MainActor, ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, Data, Never, Sendable (+1 more)

### Community 59 - "Foundation"
Cohesion: 0.14
Nodes (6): Combine, Foundation, ServiceManagement, LaunchAtLoginController, Bool, AirDropService

### Community 60 - "AppSettings.swift"
Cohesion: 0.25
Nodes (7): Key, VisualizerAccentMode, artwork, .displayName, .id, system, white

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "Sendable"
Cohesion: 0.19
Nodes (12): Sendable, ClipboardImageCapture, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult, empty, oversized (+4 more)

### Community 63 - "String"
Cohesion: 0.17
Nodes (13): Decodable, MediaPlayer, .displayName, music, .playPauseCommand, spotify, OEmbedResponse, Data (+5 more)

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "FileClipboardHistoryPersistence"
Cohesion: 0.31
Nodes (4): FileManager, FileClipboardHistoryPersistence, Data, URL

### Community 66 - "IslandHostingView"
Cohesion: 0.11
Nodes (15): Phase 13B.2 - Native In-Island Clipboard Interface, NSHostingView, NSPoint, NSRect, NSSize, NSTrackingArea, NSView, IslandHostingView (+7 more)

### Community 67 - "AudioVisualizerView"
Cohesion: 0.33
Nodes (7): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerView, .body, .shouldAnimateContinuously, .visualizerOpacity, Double, TimeInterval

### Community 68 - "IslandOverlayPanel"
Cohesion: 0.11
Nodes (17): Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12B - Native Overlay Cleanup And Runtime Optimization, CustomStringConvertible, NSPanel, QuartzCore, Native overlay, geometry and input, ExpandedScrollEventRoute, islandGesture (+9 more)

### Community 69 - "Phase Workflow For Future Work"
Cohesion: 0.08
Nodes (26): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration (+18 more)

### Community 70 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 71 - "AudioVisualizerVariant"
Cohesion: 0.25
Nodes (8): AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing, CGSize

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
Cohesion: 0.29
Nodes (6): CollapsedIslandContentMode, battery, fileTray, inactive, media, timer

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.17
Nodes (9): 2026-07-05 - Phase 8A File Shelf Tray Polish, NSItemProvider, Bool, URL, Bool, .fileDropTargetBinding, FileDropURLAccumulator, .urls (+1 more)

### Community 80 - "ShortcutEditorRow"
Cohesion: 0.40
Nodes (5): ShortcutEditorRow, .body, Binding, Void, WritableKeyPath

### Community 84 - "DynamicIsland Project Context"
Cohesion: 0.17
Nodes (10): Collapsed, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context, Expanded, Known Fragile Areas, Non-Negotiable Behavior To Preserve (+2 more)

### Community 85 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, LiveActivityStyle, compact, detailed, .id

### Community 88 - ".subscript"
Cohesion: 0.50
Nodes (3): Element, Index, Array

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "ExpandedIslandPage"
Cohesion: 0.18
Nodes (11): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName, timer (+3 more)

### Community 94 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 95 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 96 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 97 - "FileShelfStoreTests"
Cohesion: 0.33
Nodes (3): FileShelfStoreTests, URL, UserDefaults

### Community 103 - "SettingsWindowController"
Cohesion: 0.20
Nodes (7): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, NSObject, NSWindowDelegate, SettingsWindowController, Notification, NSWindow

### Community 104 - "SwiftUI"
Cohesion: 0.22
Nodes (4): Composition, state and settings, DynamicIslandApp, IslandModule, SwiftUI

### Community 105 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 106 - "IslandContentPhase"
Cohesion: 0.33
Nodes (6): IslandContentPhase, compact, contentCollapsing, expandedContentVisible, shellCollapsing, shellExpanding

## Knowledge Gaps
- **498 isolated node(s):** `PackageDescription`, `package_app.sh script`, `music`, `spotify`, `safari` (+493 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 661 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `Equatable`, `SettingsView`, `IslandRootView`, `TimerController`, `.constrainedActivePlayerLayout`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `OverlayWindowController`, `IslandNavigationStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `ClipboardHistoryEntry`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `ShelfFileTile`, `View`, `MediaModuleView`, `MediaCandidate`, `ShortcutsStore`, `SettingsSection`, `IslandLayoutStore`, `MediaController`, `ModuleViews.swift`, `IslandStateStore`, `AppSettingsTests`, `Bool`, `Bool`, `CollapsedLiveActivityPrioritySource`, `FileShelfStore`, `AppDelegate`, `.reload`, `.openActiveMediaSource`, `MediaRemoteClient`, `CodingKeys`, `AppSettings.swift`, `DefaultExpandedTab`, `IslandHostingView`, `IslandOverlayPanel`, `Phase Workflow For Future Work`, `AutoCollapseDelayPreset`, `AnimationPreset`, `Identifiable`, `GestureInputSource`, `LiveActivityStore`, `DynamicIslandLiveActivityKind`, `ShortcutEditorRow`, `CaseIterable`, `.collapsedPreviewContent`, `.remainingTime`, `ExpandedIslandPage`, `FileShelfStoreTests`?**
  _High betweenness centrality (0.327) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `OverlayWindowController`, `IslandNavigationStore`, `ExpandedIslandView`, `Change Log`, `ClipboardHistoryEntry`, `Int`, `DynamicIslandLiveActivity`, `.init`, `ShelfFileTile`, `View`, `MediaModuleView`, `ShortcutsStore`, `ModuleViews.swift`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `FileShelfStore`, `AppDelegate`, `.reload`, `OverlayPresentationSessionTests`, `ClipboardImageCaptureLifecycleTests`, `AppSettings.swift`, `String`, `DefaultExpandedTab`, `AutoCollapseDelayPreset`, `AnimationPreset`, `Identifiable`, `GestureInputSource`, `CollapsedIslandContentMode`, `CaseIterable`, `ExpandedIslandPage`, `FileShelfStoreTests`, `SettingsWindowController`, `MenuBarController`?**
  _High betweenness centrality (0.290) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `AppSettings`, `IslandRootView`, `ClipboardHistoryPresentationState`, `NotchGeometryService`, `CompactCollapsedSideSlotLayout`, `ExpandedIslandView`, `Change Log`, `DynamicIslandLiveActivity`, `.init`, `IslandLayoutStore`, `IslandStateStore`, `Bool`, `AppDelegate`, `OverlayPresentationSessionTests`, `IslandHostingView`, `IslandOverlayPanel`, `Identifiable`, `CollapsedIslandContentMode`, `DynamicIsland Project Context`, `SettingsWindowController`?**
  _High betweenness centrality (0.064) - this node is a cross-community bridge._
- **Are the 27 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 27 INFERRED edges - model-reasoned connections that need verification._
- **Are the 28 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 28 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `MediaController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5G Native Visualizer And Artwork Color`) actually correct?**
  _`MediaController` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `music` to the rest of the system?**
  _498 weakly-connected nodes found - possible documentation gaps or missing edges._