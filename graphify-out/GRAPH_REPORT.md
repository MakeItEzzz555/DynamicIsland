# Graph Report - DynamicIsland  (2026-09-24)

## Corpus Check
- 91 files · ~129,217 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 2777 nodes · 7439 edges · 120 communities (105 shown, 15 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 1030 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `08c33faa`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- AppSettings
- IslandGestureAction
- SystemStatsController
- Equatable
- SettingsView
- IslandRootView
- IslandEscapeRouter
- ClipboardHistoryStore
- TimerController
- SystemClipboardPasteboardClient
- TimerCompletionNotificationCoordinator
- ClipboardHistoryPayload
- CollapsedActivityLayoutProfile
- ClipboardHistoryStoreTests
- .normalizeAndSaveDouble
- CollapsedLiveActivitySelectorTests
- IslandNavigationStore
- .start
- FileShelfStore
- SupportedApp
- ExpandedIslandView
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- ObservableObject
- Sendable
- Int
- DynamicIslandLiveActivity
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- AudioVisualizerView
- MediaCandidate
- DynamicIsland
- CompactIslandView
- MediaModuleView
- MediaSnapshot
- AppDelegate
- FileDropProviderLoaderTests
- What You Must Do When Invoked
- IslandOverlayPanel
- String
- .refresh
- XCTestCase
- AppSettingsTests
- IslandShellShape
- View
- OverlayWindowController
- CollapsedLiveActivityPrioritySource
- IslandRootView.swift
- .normalize
- .reload
- MediaSourceKind
- MediaRemoteClient
- ClipboardImageCaptureLifecycleTests
- OverlayPresentationSessionTests
- Phase Workflow For Future Work
- IslandLayoutStore
- AppSettings.swift
- IslandSurfaceBackground
- MediaController.swift
- Bool
- DefaultExpandedTab
- NotchGeometryService
- ClipboardPasteboardReadResult
- .testTimeoutRunsNewestPendingRefreshFallbackAndRejectsLateNativeResult
- ControlledClipboardPersistence
- YouTubeMetadataProvider
- AutoCollapseDelayPreset
- IslandHostingView
- AnimationPreset
- Identifiable
- GestureInputSource
- FileDropProviderLoader
- DynamicIslandLiveActivityKind
- ManualMediaRemoteDeadlineScheduler
- Meaningful regression history
- .loadFileURLs
- ClipboardHistoryPresentationState
- Package.swift
- package_app.sh
- CollapsedPreviewKind
- NSRect
- .progress
- NowPlayingMediaProvider
- SettingsSection
- ExpandedScrollEventRoutingPolicyTests
- graphify reference: extra exports and benchmark
- Fresh critical audit instructions
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- DynamicIsland Project Context
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- ClipboardHistoryPersistenceFinalizationResult
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- CodingKeys
- RecordingFileShelfDefaults
- MediaRemoteCallbackState
- .resolve
- LiveActivitySettingsSubscriberTests
- /graphify
- .allowsCollapsedDrop
- FileClipboardHistoryPersistence
- .zeroFilledPNG
- Error
- CollapsedIslandContentMode
- Current architecture baseline
- TimerNotificationAuthorizationStatus
- FileDropProviderLoaderTests.swift
- CaseIterable
- .remainingTime

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 331 edges
2. `OverlayWindowController` - 135 edges
3. `Change Log` - 110 edges
4. `MediaController` - 105 edges
5. `IslandRootView` - 74 edges
6. `ExpandedIslandView` - 67 edges
7. `ClipboardHistoryStore` - 58 edges
8. `ExpandedIslandLayoutMetrics` - 47 edges
9. `FileThumbnailCache` - 45 edges
10. `ArtworkFlipPresentationState` - 42 edges

## Surprising Connections (you probably didn't know these)
- `2026-07-03 - Common App Launch Resolver` --references--> `AppLaunchService`  [INFERRED]
  context.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `2026-07-11 - Phase 9C Liquid Glass Visual Repair` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `Stable native overlay architecture` --references--> `IslandRootView`  [INFERRED]
  README.md → Sources/DynamicIsland/Views/IslandRootView.swift
- `2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse` --references--> `FileThumbnailCache`  [INFERRED]
  context.md → Sources/DynamicIsland/Views/ModuleViews.swift

## Import Cycles
- None detected.

## Communities (120 total, 15 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (155): AnyPublisher, Never, AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray (+147 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (40): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, .now, IslandGestureAction, collapse, .displayName, expand (+32 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (26): 2026-07-04 - Phase 5D Stats Tab, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double, Int (+18 more)

### Community 3 - "Equatable"
Cohesion: 0.12
Nodes (22): Equatable, ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted (+14 more)

### Community 4 - "SettingsView"
Cohesion: 0.07
Nodes (42): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+34 more)

### Community 5 - "IslandRootView"
Cohesion: 0.08
Nodes (29): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, IslandModules, CollapsedPreviewContent, CollapsedPreviewRow, .body, CollapsedPreviewRowContent (+21 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.11
Nodes (19): ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date, Int (+11 more)

### Community 8 - "TimerController"
Cohesion: 0.09
Nodes (25): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration (+17 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.12
Nodes (17): Bool, Duration, Never, Task, TimeInterval, UInt64, Void, SystemTimerNotificationCenterClient (+9 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.08
Nodes (28): Codable, CryptoKit, Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text (+20 more)

### Community 12 - "CollapsedActivityLayoutProfile"
Cohesion: 0.18
Nodes (11): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry, IslandCanvasGeometry, IslandGeometry, Bool (+3 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.20
Nodes (5): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, Date, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (18): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+10 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, island, stats (+8 more)

### Community 17 - ".start"
Cohesion: 0.25
Nodes (4): MockTimerNotificationCenterClient, Bool, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (14): 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge (+6 more)

### Community 19 - "SupportedApp"
Cohesion: 0.09
Nodes (25): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 3 Album Artwork Source Open, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome (+17 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.16
Nodes (12): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-04 - Phase 5J Single Visual Surface Morph, ExpandedIslandView, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation, .tabAnimationsEnabled, .tabFadeInAnimation (+4 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (66): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish (+58 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (31): ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight, .liveActivitiesStackHeight (+23 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ObservableObject"
Cohesion: 0.11
Nodes (15): Calendar, ObservableObject, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body, .emptyState, ClipboardThumbnailCache, Bool (+7 more)

### Community 26 - "Sendable"
Cohesion: 0.06
Nodes (47): Clock, Hashable, ScriptRunner, Sendable, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation (+39 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.17
Nodes (14): Candidate, CollapsedLiveActivityPrioritySettings, .defaults, CollapsedLiveActivitySelector, CollapsedLiveActivitySourceToggles, DynamicIslandLiveActivity, Bool, Date (+6 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.15
Nodes (4): CFDictionary, Bool, ClipboardImageNormalizerTests, UTType

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (3): MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "AudioVisualizerView"
Cohesion: 0.08
Nodes (28): 2026-07-04 - Phase 4C Tray File Actions Context Menu, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AlbumArtworkView, .body, AudioVisualizerVariant, .barWidth, compact (+20 more)

### Community 34 - "MediaCandidate"
Cohesion: 0.20
Nodes (4): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, MediaArbitrator, MediaCandidate, .sourceKey

### Community 35 - "DynamicIsland"
Cohesion: 0.11
Nodes (6): AppKit, Combine, DynamicIsland, Foundation, UniformTypeIdentifiers, XCTest

### Community 36 - "CompactIslandView"
Cohesion: 0.11
Nodes (22): Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CollapsedFileActivityCompactView, .accessibilityLabel, .fileText, CollapsedTimerActivityCompactView, .accessibilityLabel (+14 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.06
Nodes (39): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, Double, ClickableAlbumArtworkButton, .artwork, .body (+31 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.13
Nodes (13): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Phase 2.7 Media Source Arbitration, 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, MediaDetectionProvider, MediaSnapshot, Bool, NSImage, TimeInterval (+5 more)

### Community 39 - "AppDelegate"
Cohesion: 0.05
Nodes (35): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSStatusItem, NSWindowDelegate (+27 more)

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.18
Nodes (10): .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, Data, NSItemProvider, URL (+2 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.13
Nodes (15): Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents), Part C - Merge AST + semantic into final extraction, Step 0 - GitHub repos and multi-path merge (only if a URL or several paths), Step 1 - Ensure graphify is installed, Step 2.5 - Video and audio (only if video files detected), Step 2 - Detect files, Step 3 - Extract entities and relationships (+7 more)

### Community 42 - "IslandOverlayPanel"
Cohesion: 0.10
Nodes (18): Phase 11C.3 - Diagnostic WindowServer Transition Trace, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, NSPanel, QuartzCore, Native overlay, geometry and input, ExpandedScrollEventRoute (+10 more)

### Community 43 - "String"
Cohesion: 0.11
Nodes (16): BrowserScriptTarget, MediaArtworkFlipRequest, .isExpired, MediaController, .currentArtworkPresentationIdentity, MediaPlayer, .displayName, music (+8 more)

### Community 44 - ".refresh"
Cohesion: 0.28
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "XCTestCase"
Cohesion: 0.10
Nodes (18): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, App Entry, Current Architecture, Geometry, Modules, Overlay Windows (+10 more)

### Community 47 - "IslandShellShape"
Cohesion: 0.24
Nodes (9): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, IslandShellRadii, IslandShellShape, .animatableData, .body (+1 more)

### Community 48 - "View"
Cohesion: 0.09
Nodes (37): AirDropDropZoneView, .body, .subtitle, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, .percentText (+29 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.11
Nodes (13): CFTimeInterval, DispatchWorkItem, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedInteractiveSurfaceFrame, .collapsedScrollThreshold, .visualReferencePanelFrame, Any (+5 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.10
Nodes (18): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, Any, CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank (+10 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.05
Nodes (56): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, EnvironmentKey, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier (+48 more)

### Community 52 - ".normalize"
Cohesion: 0.21
Nodes (5): CGImageSource, ClipboardImageNormalizer, Any, Data, Int

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - "MediaSourceKind"
Cohesion: 0.21
Nodes (7): MediaSourceKind, browser, music, spotify, system, unknown, MediaSourceOpenTargetTests

### Community 55 - "MediaRemoteClient"
Cohesion: 0.13
Nodes (14): AnyObject, CopyAppDisplayNameFunction, Darwin, GetNowPlayingInfoFunction, MediaRemoteCallbackBridge, MediaRemoteClient, .isAvailable, MediaRemoteDeadlineScheduler (+6 more)

### Community 56 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.18
Nodes (9): ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, CheckedContinuation, Data, MainActor, Never, Sendable (+1 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - "Phase Workflow For Future Work"
Cohesion: 0.18
Nodes (11): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard (+3 more)

### Community 59 - "IslandLayoutStore"
Cohesion: 0.25
Nodes (7): 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, Phase 13B.2 - Native In-Island Clipboard Interface, IslandLayoutStore, Bool, CGFloat, CGRect, CGSize

### Community 60 - "AppSettings.swift"
Cohesion: 0.25
Nodes (7): Key, VisualizerAccentMode, artwork, .displayName, .id, system, white

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "MediaController.swift"
Cohesion: 0.12
Nodes (18): 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Element, Index, Media and artwork, Array, ArtworkPresentationCoordinator, .displayedSnapshot, Decision (+10 more)

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "NotchGeometryService"
Cohesion: 0.19
Nodes (10): 2026-07-04 - Phase 7A Comprehensive Settings Foundation, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 12C.1 - Integrated Notch Content Safe Areas, Phase 12C.2 - Notch-Aware Body-Relative Content Insets, NSEdgeInsets, NSScreen, NotchGeometryService, ScreenSnapshot (+2 more)

### Community 66 - "ClipboardPasteboardReadResult"
Cohesion: 0.15
Nodes (15): ImageIO, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardImageResourcePolicy, ClipboardPasteboardCapture, image (+7 more)

### Community 67 - ".testTimeoutRunsNewestPendingRefreshFallbackAndRejectsLateNativeResult"
Cohesion: 0.20
Nodes (8): ControlledMediaRemoteProvider, .count, MediaRemoteRefreshRecoveryTests, MediaRemoteTestLock, SendableMediaRemoteDictionary, NSDictionary, Result, Value

### Community 68 - "ControlledClipboardPersistence"
Cohesion: 0.14
Nodes (10): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, MemoryClipboardPersistence, .data, Bool, Data (+2 more)

### Community 69 - "YouTubeMetadataProvider"
Cohesion: 0.32
Nodes (6): Decodable, OEmbedResponse, Data, URL, YouTubeMetadata, YouTubeMetadataProvider

### Community 70 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 71 - "IslandHostingView"
Cohesion: 0.15
Nodes (10): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, Known Fragile Areas, NSHostingView, NSSize, NSTrackingArea, NSView, IslandHostingView, .intrinsicContentSize (+2 more)

### Community 72 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 73 - "Identifiable"
Cohesion: 0.29
Nodes (7): 2026-07-11 - Phase 9D Theme Simplification, Identifiable, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass

### Community 74 - "GestureInputSource"
Cohesion: 0.29
Nodes (7): GestureInputSource, camera, .displayName, .id, keyboardShortcut, none, trackpad

### Community 75 - "FileDropProviderLoader"
Cohesion: 0.15
Nodes (12): NSSecureCoding, FileDropProviderLoader, FileDropURLAccumulator, .urls, FileShelfTemporaryStorage, SendableItemProvider, Bool, NSItemProvider (+4 more)

### Community 76 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 77 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.30
Nodes (7): Entry, ManualMediaRemoteDeadlineScheduler, .scheduler, MediaRemoteCallbackBridgeTests, Bool, Int, Void

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.19
Nodes (8): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL, Bool, AirDropURLAccumulator, .urls, URL

### Community 80 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 83 - "CollapsedPreviewKind"
Cohesion: 0.25
Nodes (8): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, CollapsedPreviewKind, battery, fileDrop, liveActivity, media, none, timer

### Community 84 - "NSRect"
Cohesion: 0.18
Nodes (6): NSPoint, NSRect, .collapsedGestureCandidateScreenRegion, .currentVisibleIslandScreenRect, CGFloat, CGRect

### Community 85 - ".progress"
Cohesion: 0.17
Nodes (8): Double, Int, TimerProgressColorStage, high, low, mid, TimerProgressFormatting, TimerProgressFormattingTests

### Community 86 - "NowPlayingMediaProvider"
Cohesion: 0.25
Nodes (6): 2026-07-04 - Phase 3.4 Album Artwork Stability, MediaRemoteDictionary, NowPlayingMediaProvider, Double, NSDictionary, NSImage

### Community 87 - "SettingsSection"
Cohesion: 0.13
Nodes (15): SettingsSection, advanced, appearance, clipboard, gestures, .id, island, liveActivities (+7 more)

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 90 - "Fresh critical audit instructions"
Cohesion: 0.18
Nodes (9): Interpreter guard for subcommands, Path, Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits (+1 more)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "DynamicIsland Project Context"
Cohesion: 0.20
Nodes (9): Collapsed, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context, Expanded, Non-Negotiable Behavior To Preserve, Purpose (+1 more)

### Community 94 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 95 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 96 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 97 - "ClipboardHistoryPersistenceFinalizationResult"
Cohesion: 0.21
Nodes (10): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+2 more)

### Community 103 - "CodingKeys"
Cohesion: 0.18
Nodes (11): CodingKey, CodingKeys, files, imagePNG, text, type, url, CodingKeys (+3 more)

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "MediaRemoteCallbackState"
Cohesion: 0.33
Nodes (8): Completion, value, MediaRemoteCallbackState, .isPending, Bool, CheckedContinuation, Never, Value

### Community 108 - "/graphify"
Cohesion: 0.22
Nodes (8): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Usage, What graphify is for

### Community 109 - ".allowsCollapsedDrop"
Cohesion: 0.40
Nodes (3): FileDropPolicy, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "FileClipboardHistoryPersistence"
Cohesion: 0.31
Nodes (4): FileManager, FileClipboardHistoryPersistence, Data, URL

### Community 111 - ".zeroFilledPNG"
Cohesion: 0.43
Nodes (3): Data, Int, UInt32

### Community 112 - "Error"
Cohesion: 0.29
Nodes (7): Error, ControlledClipboardPersistenceError, requestedFailure, FileDropProviderTestError, requestedFailure, TestError, schedulingFailed

### Community 113 - "CollapsedIslandContentMode"
Cohesion: 0.29
Nodes (6): CollapsedIslandContentMode, battery, fileTray, inactive, media, timer

### Community 115 - "Current architecture baseline"
Cohesion: 0.33
Nodes (5): Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline, Evidence and graph limits

### Community 116 - "TimerNotificationAuthorizationStatus"
Cohesion: 0.33
Nodes (4): TimerNotificationAuthorizationStatus, authorized, denied, notDetermined

### Community 117 - "FileDropProviderLoaderTests.swift"
Cohesion: 0.47
Nodes (3): LockedValue, .value, Value

### Community 118 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, LiveActivityStyle, compact, detailed, .id

## Knowledge Gaps
- **521 isolated node(s):** `PackageDescription`, `package_app.sh script`, `music`, `spotify`, `safari` (+516 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 710 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `Equatable`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `TimerCompletionNotificationCoordinator`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `.start`, `FileShelfStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `ObservableObject`, `Sendable`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `AudioVisualizerView`, `MediaCandidate`, `CompactIslandView`, `MediaModuleView`, `MediaSnapshot`, `AppDelegate`, `FileDropProviderLoaderTests`, `IslandOverlayPanel`, `XCTestCase`, `AppSettingsTests`, `View`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `IslandRootView.swift`, `.reload`, `MediaSourceKind`, `MediaRemoteClient`, `AppSettings.swift`, `MediaController.swift`, `Bool`, `DefaultExpandedTab`, `.testTimeoutRunsNewestPendingRefreshFallbackAndRejectsLateNativeResult`, `YouTubeMetadataProvider`, `AutoCollapseDelayPreset`, `AnimationPreset`, `Identifiable`, `GestureInputSource`, `FileDropProviderLoader`, `DynamicIslandLiveActivityKind`, `CollapsedPreviewKind`, `NSRect`, `NowPlayingMediaProvider`, `SettingsSection`, `CodingKeys`, `RecordingFileShelfDefaults`, `LiveActivitySettingsSubscriberTests`, `.collapsedPreviewContent`, `CaseIterable`, `.remainingTime`?**
  _High betweenness centrality (0.334) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `IslandNavigationStore`, `FileShelfStore`, `ExpandedIslandView`, `Change Log`, `ObservableObject`, `Int`, `DynamicIslandLiveActivity`, `.init`, `AudioVisualizerView`, `CompactIslandView`, `MediaModuleView`, `AppDelegate`, `FileDropProviderLoaderTests`, `String`, `XCTestCase`, `AppSettingsTests`, `IslandShellShape`, `View`, `OverlayWindowController`, `IslandRootView.swift`, `.reload`, `ClipboardImageCaptureLifecycleTests`, `OverlayPresentationSessionTests`, `AppSettings.swift`, `DefaultExpandedTab`, `NotchGeometryService`, `AutoCollapseDelayPreset`, `AnimationPreset`, `Identifiable`, `GestureInputSource`, `LiveActivitySettingsSubscriberTests`, `.allowsCollapsedDrop`, `CollapsedIslandContentMode`, `CaseIterable`?**
  _High betweenness centrality (0.239) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `AppSettings`, `IslandRootView`, `IslandEscapeRouter`, `CollapsedActivityLayoutProfile`, `ExpandedIslandView`, `Change Log`, `DynamicIslandLiveActivity`, `.init`, `CompactIslandView`, `AppDelegate`, `IslandOverlayPanel`, `XCTestCase`, `OverlayPresentationSessionTests`, `IslandLayoutStore`, `Bool`, `NotchGeometryService`, `IslandHostingView`, `Identifiable`, `CollapsedPreviewKind`, `NSRect`, `DynamicIsland Project Context`, `CollapsedIslandContentMode`?**
  _High betweenness centrality (0.088) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 28 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 28 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `MediaController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5G Native Visualizer And Artwork Color`) actually correct?**
  _`MediaController` has 14 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `music` to the rest of the system?**
  _521 weakly-connected nodes found - possible documentation gaps or missing edges._