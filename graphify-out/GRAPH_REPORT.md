# Graph Report - DynamicIsland  (2026-09-22)

## Corpus Check
- 87 files · ~126,873 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 2659 nodes · 7069 edges · 116 communities (104 shown, 12 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 941 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1bc48607`
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
- Sendable
- NotchGeometryService
- ClipboardHistoryStoreTests
- .normalizeAndSaveDouble
- CollapsedLiveActivitySelectorTests
- IslandNavigationStore
- ArtworkPresentationCoordinator
- FileShelfStore
- SupportedApp
- View
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- ClipboardHistoryEntry
- MediaAutomationExecutor
- Int
- Equatable
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- URL
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
- DedicatedTimerPageView
- IslandStateStore
- AppSettingsTests
- CGFloat
- InnerBlurScaleCleanModifier
- OverlayWindowController
- CollapsedLiveActivityPrioritySource
- IslandRootView.swift
- ClipboardImageNormalizer.swift
- .reload
- MediaSourceKind
- ManualMediaRemoteDeadlineScheduler
- ClipboardImageCaptureLifecycleTests
- OverlayPresentationSessionTests
- Phase Workflow For Future Work
- IslandLayoutStore
- Identifiable
- IslandSurfaceBackground
- MediaSourceIdentity
- Bool
- DefaultExpandedTab
- FileClipboardHistoryPersistence
- ClipboardPasteboardReadResult
- AudioVisualizerView
- ControlledClipboardPersistence
- String
- AutoCollapseDelayPreset
- IslandHostingView
- AnimationPreset
- IslandThemeStyle
- GestureInputSource
- .loadURL
- DynamicIslandLiveActivityKind
- ShelfFileTile
- Meaningful regression history
- .loadFileURLs
- LiveActivityStore
- Package.swift
- package_app.sh
- CollapsedPreviewKind
- AudioVisualizerVariant
- BatteryActivityProvider
- .updateTimerLiveActivity
- LiveActivitiesModuleView
- graphify reference: extra exports and benchmark
- ShortcutEditorRow
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
- FileShelfTemporaryStorage
- Current architecture baseline
- CompactIslandView
- XCTestCase
- MenuBarController
- .shellDuration
- .allowsCollapsedDrop
- ObservableObject
- .zeroFilledPNG
- .scrollWheel
- LaunchAtLoginController.swift
- .remainingTime

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
- `2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `2026-07-11 - Phase 9C Liquid Glass Visual Repair` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift
- `Phase 11C.3 - Diagnostic WindowServer Transition Trace` --references--> `IslandOverlayPanel`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift

## Import Cycles
- None detected.

## Communities (116 total, 12 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.03
Nodes (153): AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray, .animateStatsCharts, .animationIntensity (+145 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (42): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, IslandGestureAction, collapse, .displayName, expand, .id (+34 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (27): 2026-07-04 - Phase 5D Stats Tab, ifaddrs, IOKit.ps, CPUCounters, NetworkCounters, Bool, Date, Double (+19 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.13
Nodes (18): ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted (+10 more)

### Community 4 - "SettingsView"
Cohesion: 0.08
Nodes (41): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsSection, advanced (+33 more)

### Community 5 - "IslandRootView"
Cohesion: 0.09
Nodes (27): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 13A - Expanded Visibility Controls, IslandModules, CollapsedPreviewRowContent, ExpandedIslandRightStackVisibility, .showsRightStack, IslandRootView (+19 more)

### Community 6 - "ClipboardHistoryPresentationState"
Cohesion: 0.12
Nodes (15): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+7 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.11
Nodes (20): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable (+12 more)

### Community 8 - "TimerController"
Cohesion: 0.10
Nodes (18): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, Double, Int, Never, Task, Void, TimerController, .displayText (+10 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.12
Nodes (10): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, ClipboardSensitivePasteboardTypes, Bool, Int, Set, SystemClipboardPasteboardClient (+2 more)

### Community 10 - ".constrainedActivePlayerLayout"
Cohesion: 0.22
Nodes (8): Double, ClickableAlbumArtworkButton, .artwork, .body, MediaButton, .body, .constrainedActivePlayerView, .regularActivePlayerView

### Community 11 - "Sendable"
Cohesion: 0.08
Nodes (27): Codable, CryptoKit, Decoder, Encoder, Sendable, ClipboardHistoryEntryKind, files, image (+19 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.12
Nodes (18): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry (+10 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.18
Nodes (7): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Date, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (18): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+10 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.13
Nodes (14): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName, timer (+6 more)

### Community 17 - "ArtworkPresentationCoordinator"
Cohesion: 0.16
Nodes (13): 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, ArtworkPresentationCoordinator, .displayedSnapshot, MediaArtworkFlipDirection, next, previous (+5 more)

### Community 18 - "FileShelfStore"
Cohesion: 0.12
Nodes (17): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, FileShelfStore, AnyCancellable, Set, URL (+9 more)

### Community 19 - "SupportedApp"
Cohesion: 0.09
Nodes (25): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 3 Album Artwork Source Open, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome (+17 more)

### Community 20 - "View"
Cohesion: 0.12
Nodes (17): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, AirDropDropZoneView, .subtitle, ExpandedHeaderButton, ExpandedIslandPageSwitcher, ExpandedIslandView, .airDropTargetBinding, .body (+9 more)

### Community 21 - "Change Log"
Cohesion: 0.06
Nodes (52): 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+44 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.05
Nodes (41): 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor, 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix, 2026-07-04 - Phase 6A.2 Single-Panel Native Morph Correction, 2026-07-04 - Phase 6A Single Adaptive Island Panel, 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership, 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing, Phase 12B.1 - Shell Shadow Removal, Phase 12C.1 - Integrated Notch Content Safe Areas (+33 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ClipboardHistoryEntry"
Cohesion: 0.12
Nodes (16): Calendar, Phase 13B.2 - Native In-Island Clipboard Interface, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body (+8 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (45): Clock, Hashable, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult (+37 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "Equatable"
Cohesion: 0.15
Nodes (20): Equatable, Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer (+12 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.15
Nodes (4): CFDictionary, Bool, ClipboardImageNormalizerTests, UTType

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.19
Nodes (3): MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "URL"
Cohesion: 0.38
Nodes (5): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, .body, Bool, URL

### Community 34 - "ShortcutsStore"
Cohesion: 0.16
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+2 more)

### Community 35 - "AppKit"
Cohesion: 0.05
Nodes (22): AppKit, Combine, DynamicIsland, Error, Foundation, QuartzCore, IslandModule, ExpandedScrollEventRoute (+14 more)

### Community 36 - ".opacity"
Cohesion: 0.07
Nodes (45): Left, Right, .body, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, CollapsedFileActivityCompactView (+37 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.08
Nodes (27): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, MediaLauncherButton, .body, MediaModuleView, .activePlayerView, .artistFontSize (+19 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.16
Nodes (11): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Phase 2.7 Media Source Arbitration, MediaDetectionProvider, MediaSnapshot, Bool, NSImage, TimeInterval, EmptyMediaDetectionProvider (+3 more)

### Community 39 - "AppDelegate"
Cohesion: 0.12
Nodes (14): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSWindowDelegate, AppDelegate, Any (+6 more)

### Community 40 - "FileDropProviderLoader"
Cohesion: 0.20
Nodes (9): FileDropProviderLoader, UTType, ControlledDataRepresentation, FileDropProviderLoaderTests, Data, NSItemProvider, URL, UserDefaults (+1 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.06
Nodes (32): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+24 more)

### Community 42 - "IslandOverlayPanel"
Cohesion: 0.20
Nodes (8): NSPanel, NSView, Native overlay, geometry and input, IslandOverlayPanel, .canBecomeKey, .canBecomeMain, OverlayPersistence, NSWindow

### Community 43 - "MediaController"
Cohesion: 0.13
Nodes (8): BrowserScriptTarget, MediaCandidate, .sourceKey, MediaController, .currentArtworkPresentationIdentity, Bool, Int, NSImage

### Community 44 - "DedicatedTimerPageView"
Cohesion: 0.13
Nodes (17): .visualizerAccentColor, DedicatedTimerPageView, .body, .controlsFontSize, .controlsSpacing, .titleFontSize, .usesCompactLayout, StatsLineChart (+9 more)

### Community 45 - "IslandStateStore"
Cohesion: 0.14
Nodes (13): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, App Entry, Current Architecture, Geometry, Modules, Overlay Windows, State (+5 more)

### Community 46 - "AppSettingsTests"
Cohesion: 0.12
Nodes (3): .advancedSection, AppSettingsTests, UserDefaults

### Community 47 - "CGFloat"
Cohesion: 0.15
Nodes (15): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, CollapsedPreviewContent, CollapsedPreviewRow, .body, .collapsedPreviewContent (+7 more)

### Community 48 - "InnerBlurScaleCleanModifier"
Cohesion: 0.17
Nodes (13): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier (+5 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.09
Nodes (23): CFTimeInterval, 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, DispatchWorkItem, NSRect, OverlayGeometrySignature (+15 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.09
Nodes (23): EnvironmentKey, CollapseShellOnlyEnvironmentKey, EnvironmentValues, .isCollapseShellOnly, .isNotchIntegratedShell, .isShellMorphing, ExpandedTabTransitionPhase, fadingIn (+15 more)

### Community 52 - "ClipboardImageNormalizer.swift"
Cohesion: 0.14
Nodes (10): CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageRepresentation, encoded, oversized, ClipboardImageResourcePolicy, Any (+2 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - "MediaSourceKind"
Cohesion: 0.19
Nodes (7): MediaSourceKind, browser, music, spotify, system, unknown, MediaSourceOpenTargetTests

### Community 55 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.05
Nodes (43): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, Darwin, GetNowPlayingInfoFunction, Completion, value, MediaRemoteCallbackBridge, MediaRemoteCallbackState (+35 more)

### Community 56 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.25
Nodes (5): MainActor, ClipboardImageCaptureLifecycleTests, async, Data, Sendable

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - "Phase Workflow For Future Work"
Cohesion: 0.18
Nodes (11): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard (+3 more)

### Community 59 - "IslandLayoutStore"
Cohesion: 0.26
Nodes (8): 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, IslandLayoutStore, Bool, CGFloat, CGRect, CGSize

### Community 60 - "Identifiable"
Cohesion: 0.18
Nodes (12): CaseIterable, Identifiable, LiveActivityStyle, compact, detailed, .id, VisualizerAccentMode, artwork (+4 more)

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "MediaSourceIdentity"
Cohesion: 0.12
Nodes (17): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Element, Index, Media and artwork, Array, Decision, MediaArbitrator (+9 more)

### Community 63 - "Bool"
Cohesion: 0.19
Nodes (5): NSPoint, ExpandedScrollEventRoutingPolicy, Bool, Date, NSEvent

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "FileClipboardHistoryPersistence"
Cohesion: 0.31
Nodes (4): FileManager, FileClipboardHistoryPersistence, Data, URL

### Community 66 - "ClipboardPasteboardReadResult"
Cohesion: 0.15
Nodes (14): ClipboardImageCapture, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult, empty, oversized, payload (+6 more)

### Community 67 - "AudioVisualizerView"
Cohesion: 0.31
Nodes (8): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerView, .body, .shouldAnimateContinuously, .visualizerOpacity, CGFloat, Double, TimeInterval

### Community 68 - "ControlledClipboardPersistence"
Cohesion: 0.15
Nodes (8): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, Bool, Data, Int, TimeInterval

### Community 69 - "String"
Cohesion: 0.09
Nodes (24): CodingKey, Decodable, CodingKeys, files, imagePNG, text, type, url (+16 more)

### Community 70 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 71 - "IslandHostingView"
Cohesion: 0.18
Nodes (9): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, Known Fragile Areas, NSHostingView, NSSize, NSTrackingArea, IslandHostingView, .intrinsicContentSize, Content (+1 more)

### Community 72 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 73 - "IslandThemeStyle"
Cohesion: 0.25
Nodes (7): 2026-07-11 - Phase 9D Theme Simplification, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass, Key

### Community 74 - "GestureInputSource"
Cohesion: 0.29
Nodes (7): GestureInputSource, camera, .displayName, .id, keyboardShortcut, none, trackpad

### Community 75 - ".loadURL"
Cohesion: 0.20
Nodes (6): NSSecureCoding, FileDropURLAccumulator, .urls, SendableItemProvider, NSItemProvider, TimeInterval

### Community 76 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 77 - "ShelfFileTile"
Cohesion: 0.20
Nodes (7): AlbumArtworkView, .body, .body, ShelfFileTile, .displayName, .fileImage, NSImage

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.23
Nodes (8): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL, AirDropURLAccumulator, .urls, NSItemProvider, URL

### Community 80 - "LiveActivityStore"
Cohesion: 0.31
Nodes (5): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int

### Community 83 - "CollapsedPreviewKind"
Cohesion: 0.25
Nodes (8): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, CollapsedPreviewKind, battery, fileDrop, liveActivity, media, none, timer

### Community 84 - "AudioVisualizerVariant"
Cohesion: 0.25
Nodes (8): AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing, CGSize

### Community 85 - "BatteryActivityProvider"
Cohesion: 0.33
Nodes (4): Phase 11A - Battery Live Activity, BatteryActivityProvider, Any, .description

### Community 87 - ".updateTimerLiveActivity"
Cohesion: 0.30
Nodes (3): Bool, Int, URL

### Community 88 - "LiveActivitiesModuleView"
Cohesion: 0.20
Nodes (10): .percentText, LiveActivitiesModuleView, .body, .remainingActivityCount, .visibleActivities, LiveActivityCard, .activityAccessibilityLabel, .body (+2 more)

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
Cohesion: 0.33
Nodes (6): ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut, TimeInterval

### Community 104 - "Current architecture baseline"
Cohesion: 0.22
Nodes (7): Activities and utility modules, Build and tests, Clipboard engine and persistence, Composition, state and settings, Current architecture baseline, Evidence and graph limits, DynamicIslandApp

### Community 105 - "CompactIslandView"
Cohesion: 0.22
Nodes (9): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 12C.3 - Hardware Notch Center Exclusion, CompactIslandView, .compactContentAnimation, .previewRowAnimation (+1 more)

### Community 106 - "XCTestCase"
Cohesion: 0.33
Nodes (3): Self, ExpandedIslandRightStackVisibilityTests, XCTestCase

### Community 107 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 108 - ".shellDuration"
Cohesion: 0.47
Nodes (4): .clipboardBackdropAnimation, .contentVisibilityAnimation, IslandContentTransitionTiming, TimeInterval

### Community 109 - ".allowsCollapsedDrop"
Cohesion: 0.38
Nodes (4): FileDropPolicy, Bool, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "ObservableObject"
Cohesion: 0.40
Nodes (4): ObservableObject, ClipboardThumbnailCache, Data, NSImage

### Community 111 - ".zeroFilledPNG"
Cohesion: 0.53
Nodes (3): Data, Int, UInt32

### Community 112 - ".scrollWheel"
Cohesion: 0.40
Nodes (4): 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix

### Community 113 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

## Knowledge Gaps
- **512 isolated node(s):** `PackageDescription`, `package_app.sh script`, `music`, `spotify`, `safari` (+507 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 687 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `TimerController`, `SystemClipboardPasteboardClient`, `.constrainedActivePlayerLayout`, `Sendable`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `ArtworkPresentationCoordinator`, `FileShelfStore`, `SupportedApp`, `View`, `Change Log`, `ArtworkAccentColorCache`, `ClipboardHistoryEntry`, `MediaAutomationExecutor`, `Int`, `Equatable`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `URL`, `ShortcutsStore`, `.opacity`, `MediaModuleView`, `MediaSnapshot`, `FileDropProviderLoader`, `MediaController`, `DedicatedTimerPageView`, `AppSettingsTests`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `IslandRootView.swift`, `.reload`, `MediaSourceKind`, `ManualMediaRemoteDeadlineScheduler`, `Identifiable`, `MediaSourceIdentity`, `Bool`, `DefaultExpandedTab`, `AutoCollapseDelayPreset`, `AnimationPreset`, `IslandThemeStyle`, `GestureInputSource`, `.loadURL`, `DynamicIslandLiveActivityKind`, `ShelfFileTile`, `LiveActivityStore`, `CollapsedPreviewKind`, `BatteryActivityProvider`, `.debugGesture`, `.updateTimerLiveActivity`, `LiveActivitiesModuleView`, `ShortcutEditorRow`, `FileShelfTemporaryStorage`, `ObservableObject`, `.collapsedPreviewContent`, `.remainingTime`?**
  _High betweenness centrality (0.311) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `.constrainedActivePlayerLayout`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `IslandNavigationStore`, `FileShelfStore`, `View`, `ExpandedIslandLayoutMetrics`, `Int`, `Equatable`, `.init`, `ShortcutsStore`, `MediaModuleView`, `AppDelegate`, `FileDropProviderLoader`, `DedicatedTimerPageView`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `OverlayWindowController`, `.reload`, `ClipboardImageCaptureLifecycleTests`, `OverlayPresentationSessionTests`, `Identifiable`, `DefaultExpandedTab`, `String`, `AutoCollapseDelayPreset`, `AnimationPreset`, `IslandThemeStyle`, `GestureInputSource`, `ShelfFileTile`, `.updateTimerLiveActivity`, `LiveActivitiesModuleView`, `CompactIslandView`, `MenuBarController`, `.shellDuration`, `.allowsCollapsedDrop`, `ObservableObject`?**
  _High betweenness centrality (0.254) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `AppSettings`, `IslandGestureAction`, `IslandRootView`, `ClipboardHistoryPresentationState`, `NotchGeometryService`, `View`, `Change Log`, `ClipboardHistoryEntry`, `Equatable`, `.init`, `AppKit`, `AppDelegate`, `IslandOverlayPanel`, `IslandStateStore`, `OverlayPresentationSessionTests`, `IslandLayoutStore`, `Bool`, `IslandHostingView`, `IslandThemeStyle`, `CollapsedPreviewKind`, `.debugGesture`, `DynamicIsland Project Context`, `CompactIslandView`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 28 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 28 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `MediaController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5G Native Visualizer And Artwork Color`) actually correct?**
  _`MediaController` has 14 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `music` to the rest of the system?**
  _512 weakly-connected nodes found - possible documentation gaps or missing edges._