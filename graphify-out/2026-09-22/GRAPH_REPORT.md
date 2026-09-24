# Graph Report - DynamicIsland  (2026-09-22)

## Corpus Check
- 87 files · ~126,632 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 2652 nodes · 7031 edges · 104 communities (94 shown, 10 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 926 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1bc48607`
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
- Sendable
- TimerController
- SystemClipboardPasteboardClient
- CGFloat
- ClipboardHistoryPayload
- NotchGeometryService
- ClipboardHistoryStoreTests
- .normalizeAndSaveDouble
- CollapsedLiveActivitySelectorTests
- IslandNavigationStore
- ClipboardHistoryPresentationState
- FileShelfStore
- SupportedApp
- ExpandedIslandView
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- .presentation
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- ShelfFileTile
- ShortcutsStore
- AppKit
- .opacity
- MediaModuleView
- MediaSnapshot
- AppDelegate
- FileDropProviderLoader
- What You Must Do When Invoked
- IslandOverlayPanel
- MediaController
- SettingsSection
- XCTestCase
- AppSettingsTests
- IslandShellShape
- CGFloat
- OverlayWindowController
- CollapsedLiveActivityPrioritySource
- View
- FileShelfStoreTests
- .reload
- MediaSourceOpenTarget
- ManualMediaRemoteDeadlineScheduler
- ExpandedIslandPage
- OverlayPresentationSessionTests
- Phase Workflow For Future Work
- Foundation
- AppSettings.swift
- IslandSurfaceBackground
- MediaCandidate
- SwiftUI
- DefaultExpandedTab
- FileClipboardHistoryPersistence
- LockedValue
- AudioVisualizerView
- ControlledClipboardPersistence
- String
- AutoCollapseDelayPreset
- IslandHostingView
- AnimationPreset
- Identifiable
- GestureInputSource
- Fresh critical audit instructions
- DynamicIslandLiveActivityKind
- CodingKeys
- Meaningful regression history
- .loadFileURLs
- ClipboardHistoryEntry
- Package.swift
- package_app.sh
- CollapsedPreviewKind
- ModuleViews.swift
- BatteryActivityProvider
- ExpandedScrollEventRoutingPolicyTests
- /graphify
- .showTrayForFileDrag
- graphify reference: extra exports and benchmark
- ShortcutEditorRow
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- CaseIterable
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- Current architecture baseline
- .resolve

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 324 edges
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
- `Composition, state and settings` --references--> `IslandModule`  [INFERRED]
  research/ARCHITECTURE_BASELINE.md → Sources/DynamicIsland/Modules/IslandModule.swift
- `Stable native overlay architecture` --references--> `IslandRootView`  [INFERRED]
  README.md → Sources/DynamicIsland/Views/IslandRootView.swift
- `2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse` --references--> `FileThumbnailCache`  [INFERRED]
  context.md → Sources/DynamicIsland/Views/ModuleViews.swift
- `2026-07-06 - Git Repo Restoration And Stable Final Tag` --references--> `FileThumbnailCache`  [INFERRED]
  context.md → Sources/DynamicIsland/Views/ModuleViews.swift

## Import Cycles
- None detected.

## Communities (104 total, 10 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.03
Nodes (153): AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray, .animateStatsCharts, .animationIntensity (+145 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.08
Nodes (39): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, IslandGestureAction, collapse, .displayName, expand, .id (+31 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (29): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+21 more)

### Community 3 - "Equatable"
Cohesion: 0.06
Nodes (45): 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, Element, Equatable, Index (+37 more)

### Community 4 - "SettingsView"
Cohesion: 0.16
Nodes (27): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsView, .advancedSection (+19 more)

### Community 5 - "IslandRootView"
Cohesion: 0.06
Nodes (37): 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, CollapsedPreviewContent, CollapsedPreviewRow, .body, CollapsedPreviewRowContent, ExpandedIslandRightStackVisibility (+29 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.09
Nodes (20): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, MainActor, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy (+12 more)

### Community 7 - "Sendable"
Cohesion: 0.09
Nodes (26): AnyObject, Sendable, ClipboardHistoryPersistence, ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult (+18 more)

### Community 8 - "TimerController"
Cohesion: 0.08
Nodes (24): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, Double, Int, Never, Task, Void, TimerController, .displayText (+16 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.08
Nodes (23): NSPasteboard, NSPasteboardItem, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image (+15 more)

### Community 10 - "CGFloat"
Cohesion: 0.28
Nodes (7): Double, ClickableAlbumArtworkButton, .body, MediaButton, .body, .regularActivePlayerView, CGFloat

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.08
Nodes (26): Codable, CryptoKit, Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text (+18 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.12
Nodes (18): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry (+10 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.19
Nodes (5): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, Date, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (18): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+10 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.24
Nodes (6): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, IslandNavigationStore, Int, .body, .gestureCallbacks

### Community 17 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 18 - "FileShelfStore"
Cohesion: 0.17
Nodes (11): 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge, .body (+3 more)

### Community 19 - "SupportedApp"
Cohesion: 0.10
Nodes (20): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 3 Album Artwork Source Open, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome (+12 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.15
Nodes (10): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, ExpandedIslandView, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation, .tabAnimationsEnabled, .tabFadeInAnimation, .tabFadeOutAnimation (+2 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (67): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish (+59 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (36): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+28 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - ".presentation"
Cohesion: 0.21
Nodes (6): Calendar, ClipboardHistoryRowPresentation, Bool, Date, Self, ClipboardHistoryRowPresentationTests

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (45): Clock, Hashable, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult (+37 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.13
Nodes (20): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+12 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (14): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Data (+6 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (3): MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "ShelfFileTile"
Cohesion: 0.20
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, NSImage (+1 more)

### Community 34 - "ShortcutsStore"
Cohesion: 0.16
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+2 more)

### Community 35 - "AppKit"
Cohesion: 0.16
Nodes (4): AppKit, DynamicIsland, UniformTypeIdentifiers, XCTest

### Community 36 - ".opacity"
Cohesion: 0.06
Nodes (50): Left, Right, ClipboardHistoryView, .body, .emptyState, .header, UUID, Void (+42 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.08
Nodes (28): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, MediaLauncherButton, .body, MediaModuleView, .activePlayerView, .artistFontSize (+20 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.11
Nodes (17): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Phase 2.7 Media Source Arbitration, MediaDetectionProvider, MediaSnapshot, MediaSourceKind, browser, music, spotify (+9 more)

### Community 39 - "AppDelegate"
Cohesion: 0.05
Nodes (30): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSStatusItem, NSWindowDelegate, Composition, state and settings (+22 more)

### Community 40 - "FileDropProviderLoader"
Cohesion: 0.08
Nodes (25): Error, NSSecureCoding, FileDropPolicy, FileDropProviderLoader, FileDropURLAccumulator, .urls, FileShelfTemporaryStorage, SendableItemProvider (+17 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.13
Nodes (15): Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents), Part C - Merge AST + semantic into final extraction, Step 0 - GitHub repos and multi-path merge (only if a URL or several paths), Step 1 - Ensure graphify is installed, Step 2.5 - Video and audio (only if video files detected), Step 2 - Detect files, Step 3 - Extract entities and relationships (+7 more)

### Community 42 - "IslandOverlayPanel"
Cohesion: 0.12
Nodes (14): Phase 11C.3 - Diagnostic WindowServer Transition Trace, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, NSPanel, Native overlay, geometry and input, IslandOverlayPanel, .canBecomeKey (+6 more)

### Community 43 - "MediaController"
Cohesion: 0.13
Nodes (8): BrowserScriptTarget, Decision, MediaController, .currentArtworkPresentationIdentity, Bool, Date, Int, NSImage

### Community 44 - "SettingsSection"
Cohesion: 0.13
Nodes (15): SettingsSection, advanced, appearance, clipboard, gestures, .id, island, liveActivities (+7 more)

### Community 45 - "XCTestCase"
Cohesion: 0.08
Nodes (25): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, App Entry, Current Architecture, Geometry (+17 more)

### Community 47 - "IslandShellShape"
Cohesion: 0.24
Nodes (9): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, IslandShellRadii, IslandShellShape, .animatableData, .body (+1 more)

### Community 48 - "CGFloat"
Cohesion: 0.10
Nodes (22): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, ExpandedTabContentTransitionModifier (+14 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.08
Nodes (25): CFTimeInterval, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5J.4 Final Media Fit And Mouse Leave Rect Fix, 2026-07-04 - Phase 5J.5 Final Expanded Hover Tolerance Tightening, 2026-07-11 - Phase 9C Liquid Glass Visual Repair, Phase 13B.2 - Native In-Island Clipboard Interface, DispatchWorkItem, NSPoint (+17 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.11
Nodes (14): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+6 more)

### Community 51 - "View"
Cohesion: 0.12
Nodes (25): EnvironmentKey, AirDropDropZoneView, .subtitle, CollapsedPreviewLabel, .body, CollapseShellOnlyEnvironmentKey, ExpandedHeaderButton, ExtraLiveActivityCard (+17 more)

### Community 52 - "FileShelfStoreTests"
Cohesion: 0.31
Nodes (3): FileShelfStoreTests, URL, UserDefaults

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - "MediaSourceOpenTarget"
Cohesion: 0.19
Nodes (6): MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 55 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.05
Nodes (43): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, Darwin, GetNowPlayingInfoFunction, Completion, value, MediaRemoteCallbackBridge, MediaRemoteCallbackState (+35 more)

### Community 56 - "ExpandedIslandPage"
Cohesion: 0.17
Nodes (11): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName, timer (+3 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - "Phase Workflow For Future Work"
Cohesion: 0.09
Nodes (20): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 4B.1 Expanded Tray Drop Handoff Fix (+12 more)

### Community 59 - "Foundation"
Cohesion: 0.20
Nodes (3): Combine, Foundation, AirDropService

### Community 60 - "AppSettings.swift"
Cohesion: 0.25
Nodes (7): Key, VisualizerAccentMode, artwork, .displayName, .id, system, white

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "MediaCandidate"
Cohesion: 0.24
Nodes (6): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, MediaArbitrator, MediaCandidate, .sourceKey, MediaSourceIdentity, .debugDescription

### Community 63 - "SwiftUI"
Cohesion: 0.17
Nodes (7): QuartzCore, IslandModule, ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicy, SwiftUI

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "FileClipboardHistoryPersistence"
Cohesion: 0.31
Nodes (4): FileManager, FileClipboardHistoryPersistence, Data, URL

### Community 66 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 67 - "AudioVisualizerView"
Cohesion: 0.33
Nodes (7): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerView, .body, .shouldAnimateContinuously, .visualizerOpacity, Double, TimeInterval

### Community 68 - "ControlledClipboardPersistence"
Cohesion: 0.14
Nodes (10): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, MemoryClipboardPersistence, .data, Bool, Data (+2 more)

### Community 69 - "String"
Cohesion: 0.12
Nodes (17): Decodable, ObservableObject, MediaPlayer, .displayName, music, .playPauseCommand, spotify, OEmbedResponse (+9 more)

### Community 70 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 71 - "IslandHostingView"
Cohesion: 0.13
Nodes (13): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, NSHostingView, NSSize, NSTrackingArea (+5 more)

### Community 72 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 73 - "Identifiable"
Cohesion: 0.29
Nodes (7): 2026-07-11 - Phase 9D Theme Simplification, Identifiable, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass

### Community 74 - "GestureInputSource"
Cohesion: 0.29
Nodes (7): GestureInputSource, camera, .displayName, .id, keyboardShortcut, none, trackpad

### Community 75 - "Fresh critical audit instructions"
Cohesion: 0.18
Nodes (9): Interpreter guard for subcommands, Path, Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits (+1 more)

### Community 76 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 77 - "CodingKeys"
Cohesion: 0.18
Nodes (11): CodingKey, CodingKeys, files, imagePNG, text, type, url, CodingKeys (+3 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.25
Nodes (7): 2026-07-05 - Phase 8A File Shelf Tray Polish, Bool, URL, AirDropURLAccumulator, .urls, NSItemProvider, URL

### Community 80 - "ClipboardHistoryEntry"
Cohesion: 0.31
Nodes (4): UUID, ClipboardHistoryEntry, Date, UUID

### Community 83 - "CollapsedPreviewKind"
Cohesion: 0.25
Nodes (8): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, CollapsedPreviewKind, battery, fileDrop, liveActivity, media, none, timer

### Community 84 - "ModuleViews.swift"
Cohesion: 0.17
Nodes (11): AlbumArtworkView, .body, AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size (+3 more)

### Community 85 - "BatteryActivityProvider"
Cohesion: 0.29
Nodes (5): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, Any, .description

### Community 87 - "/graphify"
Cohesion: 0.22
Nodes (8): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Usage, What graphify is for

### Community 88 - ".showTrayForFileDrag"
Cohesion: 0.29
Nodes (5): 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, Bool, .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding

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

### Community 104 - "Current architecture baseline"
Cohesion: 0.33
Nodes (5): Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline, Evidence and graph limits

### Community 106 - ".resolve"
Cohesion: 0.21
Nodes (6): EnvironmentValues, .isCollapseShellOnly, .isNotchIntegratedShell, .isShellMorphing, Self, ExpandedIslandRightStackVisibilityTests

## Knowledge Gaps
- **512 isolated node(s):** `PackageDescription`, `package_app.sh script`, `music`, `spotify`, `safari` (+507 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 686 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `Equatable`, `SettingsView`, `IslandRootView`, `TimerController`, `SystemClipboardPasteboardClient`, `CGFloat`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `FileShelfStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `.presentation`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `ShelfFileTile`, `ShortcutsStore`, `.opacity`, `MediaModuleView`, `MediaSnapshot`, `AppDelegate`, `FileDropProviderLoader`, `IslandOverlayPanel`, `MediaController`, `SettingsSection`, `XCTestCase`, `AppSettingsTests`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `View`, `FileShelfStoreTests`, `.reload`, `MediaSourceOpenTarget`, `ManualMediaRemoteDeadlineScheduler`, `ExpandedIslandPage`, `AppSettings.swift`, `MediaCandidate`, `DefaultExpandedTab`, `AutoCollapseDelayPreset`, `AnimationPreset`, `Identifiable`, `GestureInputSource`, `DynamicIslandLiveActivityKind`, `CodingKeys`, `ClipboardHistoryEntry`, `CollapsedPreviewKind`, `BatteryActivityProvider`, `ShortcutEditorRow`, `CaseIterable`?**
  _High betweenness centrality (0.305) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `SettingsView`, `IslandRootView`, `IslandEscapeRouter`, `Sendable`, `TimerController`, `CGFloat`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `IslandNavigationStore`, `FileShelfStore`, `ExpandedIslandView`, `Change Log`, `Int`, `DynamicIslandLiveActivity`, `.init`, `ShelfFileTile`, `ShortcutsStore`, `MediaModuleView`, `AppDelegate`, `FileDropProviderLoader`, `XCTestCase`, `AppSettingsTests`, `IslandShellShape`, `OverlayWindowController`, `View`, `FileShelfStoreTests`, `.reload`, `ExpandedIslandPage`, `OverlayPresentationSessionTests`, `AppSettings.swift`, `DefaultExpandedTab`, `String`, `AutoCollapseDelayPreset`, `AnimationPreset`, `Identifiable`, `GestureInputSource`, `.showTrayForFileDrag`, `CaseIterable`?**
  _High betweenness centrality (0.254) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `AppSettings`, `IslandRootView`, `IslandEscapeRouter`, `AppDelegate`, `IslandHostingView`, `Identifiable`, `IslandOverlayPanel`, `NotchGeometryService`, `XCTestCase`, `CollapsedPreviewKind`, `ExpandedIslandView`, `Change Log`, `OverlayPresentationSessionTests`, `Phase Workflow For Future Work`, `DynamicIslandLiveActivity`, `.init`, `SwiftUI`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Are the 30 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 30 INFERRED edges - model-reasoned connections that need verification._
- **Are the 28 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 28 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `MediaController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5G Native Visualizer And Artwork Color`) actually correct?**
  _`MediaController` has 14 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `music` to the rest of the system?**
  _512 weakly-connected nodes found - possible documentation gaps or missing edges._