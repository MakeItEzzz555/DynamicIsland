# Graph Report - DynamicIsland  (2026-09-24)

## Corpus Check
- 107 files · ~149,972 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 3319 nodes · 9058 edges · 139 communities (126 shown, 13 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 1255 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `d8788bb0`
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
- TimerCompletionNotificationCoordinator
- ClipboardHistoryPayload
- NotchGeometryService
- ClipboardHistoryStoreTests
- .normalizeAndSaveDouble
- CollapsedLiveActivitySelectorTests
- IslandNavigationStore
- .start
- FileShelfStore
- SupportedApp
- View
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- ObservableObject
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- ModuleViews.swift
- MediaCandidate
- DynamicIsland
- CompactIslandView
- MediaModuleView
- MediaSnapshot
- LiveActivitySettingsSnapshot
- FileDropProviderLoaderTests
- What You Must Do When Invoked
- IslandOverlayPanel
- MediaController
- .refresh
- IslandStateStore
- AppSettingsTests
- CGFloat
- .opacity
- OverlayWindowController
- CollapsedLiveActivityPrioritySource
- IslandRootView.swift
- Sendable
- .reload
- .openActiveMediaSource
- ManualMediaRemoteDeadlineScheduler
- ClipboardImageCaptureLifecycleTests
- OverlayPresentationSessionTests
- .apply
- .sessionID
- AppSettings.swift
- IslandSurfaceBackground
- Phase Workflow For Future Work
- Bool
- DefaultExpandedTab
- AgentEventStore
- ClipboardPasteboardReadResult
- AgentEvent
- ControlledClipboardPersistence
- String
- AutoCollapseDelayPreset
- IslandHostingView
- AnimationPreset
- IslandThemeStyle
- GestureInputSource
- FileDropProviderLoader
- DynamicIslandLiveActivityKind
- AgentCapability
- Meaningful regression history
- DedicatedTimerPageView
- ClipboardHistoryPresentationState
- Package.swift
- package_app.sh
- CollapsedPreviewKind
- AgentUsage
- .progress
- AgentEventType
- AgentEventValidationError
- OverlayWindowController.swift
- graphify reference: extra exports and benchmark
- Int
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- DynamicIsland Project Context
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- ClipboardHistoryPersistence
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- CodingKeys
- RecordingFileShelfDefaults
- AgentReplayHarness
- XCTestCase
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- FileClipboardHistoryPersistence
- .zeroFilledPNG
- Error
- CollapsedIslandContentMode
- SwiftUI
- TimerNotificationAuthorizationStatus
- LockedValue
- CaseIterable
- .remainingTime
- ShortcutsStore
- AppDelegate
- InnerBlurScaleCleanModifier
- Agent Activity Integration Architecture
- LiveActivitiesModuleView
- 3. Phase gates
- LiveActivityStore
- Agent Capability Matrix
- Agent Event Schema Draft
- AgentNotch Reference Review
- AgentActivityKind
- BatteryActivityProvider
- MenuBarController
- SettingsWindowController
- .share
- 3. Session identity
- Agent Activity Feature Phase Plan
- LaunchAtLoginController.swift

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 331 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 105 edges
5. `IslandRootView` - 75 edges
6. `ExpandedIslandView` - 67 edges
7. `ClipboardHistoryStore` - 58 edges
8. `AgentEvent` - 56 edges
9. `AgentSession` - 54 edges
10. `AgentEventStore` - 49 edges

## Surprising Connections (you probably didn't know these)
- `A1 — Normalized domain, `AgentEventStore`, replay harness` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `1. Decision summary` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `State ownership` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `A10 — Source app/editor association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `9. Source association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift

## Import Cycles
- None detected.

## Communities (139 total, 13 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (155): AnyPublisher, Never, AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray (+147 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (38): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, .now, IslandGestureAction, collapse, .displayName, expand, .id (+30 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (27): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+19 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.13
Nodes (18): ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted (+10 more)

### Community 4 - "SettingsView"
Cohesion: 0.07
Nodes (47): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsSection, advanced (+39 more)

### Community 5 - "IslandRootView"
Cohesion: 0.08
Nodes (28): 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, CollapsedPreviewContent, CollapsedPreviewRow, .body, CollapsedPreviewRowContent, ExpandedIslandRightStackVisibility (+20 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.13
Nodes (16): ClipboardHistoryStore, AnyCancellable, async, Bool, Data, Date, Never, Set (+8 more)

### Community 8 - "TimerController"
Cohesion: 0.10
Nodes (21): ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration, Int (+13 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (9): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, ClipboardSensitivePasteboardTypes, Bool, Set, SystemClipboardPasteboardClient, .changeCount (+1 more)

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.12
Nodes (17): Bool, Duration, Never, Task, TimeInterval, UInt64, Void, SystemTimerNotificationCenterClient (+9 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.10
Nodes (19): Decoder, Encoder, ClipboardHistoryFingerprint, ClipboardHistoryPayload, .byteCount, files, imagePNG, .kind (+11 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.12
Nodes (18): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry (+10 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.21
Nodes (5): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, Date, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (18): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+10 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.13
Nodes (14): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName, timer (+6 more)

### Community 17 - ".start"
Cohesion: 0.26
Nodes (4): MockTimerNotificationCenterClient, Bool, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (15): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults (+7 more)

### Community 19 - "SupportedApp"
Cohesion: 0.13
Nodes (18): 2026-07-03 - Common App Launch Resolver, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName (+10 more)

### Community 20 - "View"
Cohesion: 0.15
Nodes (12): AirDropDropZoneView, .subtitle, ExpandedHeaderButton, ExpandedIslandPageSwitcher, ExpandedIslandView, .body, .tabAnimationsEnabled, .tabFadeInAnimation (+4 more)

### Community 21 - "Change Log"
Cohesion: 0.06
Nodes (51): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish (+43 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.05
Nodes (41): 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor, 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix, 2026-07-04 - Phase 6A.2 Single-Panel Native Morph Correction, 2026-07-04 - Phase 6A Single Adaptive Island Panel, 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership, 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing, Phase 12B.1 - Shell Shadow Removal, Phase 12C.1 - Integrated Notch Content Safe Areas (+33 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ObservableObject"
Cohesion: 0.10
Nodes (16): Calendar, ObservableObject, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body, .emptyState, .header, ClipboardThumbnailCache (+8 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (44): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+36 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.17
Nodes (14): Candidate, CollapsedLiveActivityPrioritySettings, .defaults, CollapsedLiveActivitySelector, CollapsedLiveActivitySourceToggles, DynamicIslandLiveActivity, Bool, Date (+6 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.12
Nodes (7): CFDictionary, CGImageSource, ClipboardImageNormalizer, Any, Bool, ClipboardImageNormalizerTests, UTType

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (3): MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "ModuleViews.swift"
Cohesion: 0.08
Nodes (31): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, AlbumArtworkView, .body, AudioVisualizerVariant, .barWidth, compact (+23 more)

### Community 34 - "MediaCandidate"
Cohesion: 0.21
Nodes (6): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, MediaArbitrator, MediaCandidate, .sourceKey, MediaSourceIdentity, .debugDescription

### Community 35 - "DynamicIsland"
Cohesion: 0.09
Nodes (7): AppKit, Combine, CryptoKit, DynamicIsland, Foundation, UniformTypeIdentifiers, XCTest

### Community 36 - "CompactIslandView"
Cohesion: 0.12
Nodes (21): Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CollapsedFileActivityCompactView, .accessibilityLabel, .fileText, CollapsedTimerActivityCompactView, .accessibilityLabel (+13 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.07
Nodes (29): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, .body, MediaLauncherButton, .body, MediaModuleView (+21 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.12
Nodes (16): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, MediaDetectionProvider, MediaSnapshot, MediaSourceKind, browser, music, spotify, system (+8 more)

### Community 39 - "LiveActivitySettingsSnapshot"
Cohesion: 0.29
Nodes (5): .liveActivitySettingsPublisher, LiveActivitySettingsSnapshot, Bool, Int, URL

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.18
Nodes (10): .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, Data, NSItemProvider, URL (+2 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.06
Nodes (32): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+24 more)

### Community 42 - "IslandOverlayPanel"
Cohesion: 0.16
Nodes (9): Phase 11C.3 - Diagnostic WindowServer Transition Trace, NSPanel, NSView, Native overlay, geometry and input, IslandOverlayPanel, .canBecomeKey, .canBecomeMain, OverlayPersistence (+1 more)

### Community 43 - "MediaController"
Cohesion: 0.16
Nodes (6): BrowserScriptTarget, MediaController, .currentArtworkPresentationIdentity, Bool, Double, NSImage

### Community 44 - ".refresh"
Cohesion: 0.28
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.08
Nodes (24): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, App Entry, Current Architecture, Geometry (+16 more)

### Community 47 - "CGFloat"
Cohesion: 0.20
Nodes (11): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, IslandShellLayout, IslandShellRadii, IslandShellShape, .animatableData (+3 more)

### Community 48 - ".opacity"
Cohesion: 0.08
Nodes (37): .body, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, .percentText, .body, CollapsedPreviewActivityRow (+29 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.07
Nodes (29): CFTimeInterval, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-04 - Phase 5J.4 Final Media Fit And Mouse Leave Rect Fix, 2026-07-04 - Phase 5J.5 Final Expanded Hover Tolerance Tightening, 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, 2026-07-11 - Phase 9C Liquid Glass Visual Repair, Phase 11C.4 - WindowServer Space-Transition Counter-Translation (+21 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.07
Nodes (32): Phase 13B.2 - Native In-Island Clipboard Interface, EnvironmentKey, Gesture, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, CollapseShellOnlyEnvironmentKey (+24 more)

### Community 52 - "Sendable"
Cohesion: 0.05
Nodes (99): Codable, Comparable, Equatable, Hashable, Identifiable, Int, RawRepresentable, 1. Domain contracts (+91 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - ".openActiveMediaSource"
Cohesion: 0.16
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 55 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.05
Nodes (44): AnyObject, 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, Darwin, GetNowPlayingInfoFunction, Completion, value, MediaRemoteCallbackBridge (+36 more)

### Community 56 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.18
Nodes (9): ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, CheckedContinuation, Data, MainActor, Never, Sendable (+1 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.16
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".apply"
Cohesion: 0.07
Nodes (27): AgentEventReducer, AgentEventStoreLimits, .normalized, SemanticResult, applied, rejected, Bool, Date (+19 more)

### Community 59 - ".sessionID"
Cohesion: 0.16
Nodes (15): AgentActivityDescriptor, AgentApprovalRequest, AgentApprovalResolution, AgentPlanEvent, AgentSessionMetadata, AgentTerminalEvent, AgentToolEvent, AgentEventReducerTests (+7 more)

### Community 60 - "AppSettings.swift"
Cohesion: 0.25
Nodes (7): Key, VisualizerAccentMode, artwork, .displayName, .id, system, white

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "Phase Workflow For Future Work"
Cohesion: 0.08
Nodes (24): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration, 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard (+16 more)

### Community 63 - "Bool"
Cohesion: 0.16
Nodes (3): NSPoint, Bool, NSEvent

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "AgentEventStore"
Cohesion: 0.14
Nodes (12): AgentEventStore, .activeSessions, .sessionsRequiringAttention, Bool, Date, AgentSessionID, AgentSessionInstanceID, AgentEventStoreTests (+4 more)

### Community 66 - "ClipboardPasteboardReadResult"
Cohesion: 0.13
Nodes (17): ImageIO, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardImageResourcePolicy, ClipboardPasteboardCapture, image (+9 more)

### Community 67 - "AgentEvent"
Cohesion: 0.08
Nodes (28): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, AgentEventOrigin, live, replay (+20 more)

### Community 68 - "ControlledClipboardPersistence"
Cohesion: 0.13
Nodes (10): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, MemoryClipboardPersistence, .data, Bool, Data (+2 more)

### Community 69 - "String"
Cohesion: 0.11
Nodes (18): CodingKey, Decodable, MediaPlayer, .displayName, music, .playPauseCommand, spotify, CodingKeys (+10 more)

### Community 70 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 71 - "IslandHostingView"
Cohesion: 0.15
Nodes (12): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, NSHostingView, NSSize, NSTrackingArea (+4 more)

### Community 72 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 73 - "IslandThemeStyle"
Cohesion: 0.33
Nodes (6): 2026-07-11 - Phase 9D Theme Simplification, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass

### Community 74 - "GestureInputSource"
Cohesion: 0.29
Nodes (7): GestureInputSource, camera, .displayName, .id, keyboardShortcut, none, trackpad

### Community 75 - "FileDropProviderLoader"
Cohesion: 0.22
Nodes (8): NSSecureCoding, completion, FileDropProviderLoader, SendableItemProvider, NSItemProvider, TimeInterval, UTType, NSItemProvider

### Community 76 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 77 - "AgentCapability"
Cohesion: 0.07
Nodes (28): 3. Component boundaries, Adapter contract, State ownership, AgentCapabilities, .all, AgentCapability, approvalControl, approvalObservation (+20 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - "DedicatedTimerPageView"
Cohesion: 0.16
Nodes (11): AirDropURLAccumulator, .urls, DedicatedTimerPageView, .controlsFontSize, .controlsSpacing, .titleFontSize, .usesCompactLayout, LiveActivityCard (+3 more)

### Community 80 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 83 - "CollapsedPreviewKind"
Cohesion: 0.25
Nodes (8): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, CollapsedPreviewKind, battery, fileDrop, liveActivity, media, none, timer

### Community 84 - "AgentUsage"
Cohesion: 0.08
Nodes (22): AgentUsage, AgentUsageMetric, cachedInputTokens, contextLimit, contextUsed, cost, inputTokens, outputTokens (+14 more)

### Community 85 - ".progress"
Cohesion: 0.15
Nodes (10): 5. Local storage audit (content redacted), Claude, Codex, Cross-surface findings, Double, TimerProgressColorStage, high, low (+2 more)

### Community 86 - "AgentEventType"
Cohesion: 0.07
Nodes (29): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+21 more)

### Community 87 - "AgentEventValidationError"
Cohesion: 0.07
Nodes (28): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+20 more)

### Community 88 - "OverlayWindowController.swift"
Cohesion: 0.17
Nodes (7): QuartzCore, ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicy, ExpandedScrollEventRoutingPolicyTests, Bool

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 90 - "Int"
Cohesion: 0.16
Nodes (12): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, ArtworkPresentationCoordinator, .displayedSnapshot, MediaArtworkFlipDirection, next, previous, MediaArtworkFlipRequest, .isExpired (+4 more)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "DynamicIsland Project Context"
Cohesion: 0.17
Nodes (10): Collapsed, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context, Expanded, Known Fragile Areas, Non-Negotiable Behavior To Preserve (+2 more)

### Community 94 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 95 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 96 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 97 - "ClipboardHistoryPersistence"
Cohesion: 0.16
Nodes (12): ClipboardHistoryPersistence, ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed (+4 more)

### Community 103 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, files, imagePNG, text, type, url

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentReplayHarness"
Cohesion: 0.14
Nodes (10): AgentReplayFixture, AgentReplayHarness, AgentReplayResult, .finalAttentionEvents, .finalSessions, AgentReplayStepResult, Int, AgentReplayHarnessTests (+2 more)

### Community 106 - "XCTestCase"
Cohesion: 0.33
Nodes (3): Self, ExpandedIslandRightStackVisibilityTests, XCTestCase

### Community 108 - "ShelfFileTile"
Cohesion: 0.23
Nodes (8): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, URL

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.18
Nodes (8): FileDropPolicy, FileDropURLAccumulator, .urls, FileShelfTemporaryStorage, Bool, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "FileClipboardHistoryPersistence"
Cohesion: 0.31
Nodes (4): FileManager, FileClipboardHistoryPersistence, Data, URL

### Community 111 - ".zeroFilledPNG"
Cohesion: 0.53
Nodes (3): Data, Int, UInt32

### Community 112 - "Error"
Cohesion: 0.29
Nodes (7): Error, ControlledClipboardPersistenceError, requestedFailure, FileDropProviderTestError, requestedFailure, TestError, schedulingFailed

### Community 113 - "CollapsedIslandContentMode"
Cohesion: 0.33
Nodes (6): CollapsedIslandContentMode, battery, fileTray, inactive, media, timer

### Community 115 - "SwiftUI"
Cohesion: 0.14
Nodes (9): Activities and utility modules, Build and tests, Clipboard engine and persistence, Composition, state and settings, Current architecture baseline, Evidence and graph limits, DynamicIslandApp, IslandModule (+1 more)

### Community 116 - "TimerNotificationAuthorizationStatus"
Cohesion: 0.40
Nodes (4): TimerNotificationAuthorizationStatus, authorized, denied, notDetermined

### Community 117 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 118 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, LiveActivityStyle, compact, detailed, .id

### Community 120 - "ShortcutsStore"
Cohesion: 0.16
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+2 more)

### Community 121 - "AppDelegate"
Cohesion: 0.16
Nodes (12): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-05 - Settings Window Activation Fix, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, 2. Existing DynamicIsland invariants, AppDelegate, Any (+4 more)

### Community 122 - "InnerBlurScaleCleanModifier"
Cohesion: 0.21
Nodes (10): Animation, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, .clipboardBackdropAnimation, .contentVisibilityAnimation, InnerBlurScaleCleanModifier, .blur, .scale (+2 more)

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.13
Nodes (15): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 5. Local bridge decision, 6. Privacy and security boundaries, 7. Attention presentation contract (+7 more)

### Community 124 - "LiveActivitiesModuleView"
Cohesion: 0.22
Nodes (11): ExtraLiveActivityCard, LiveActivitiesModuleView, .body, .remainingActivityCount, .visibleActivities, StatsLineChart, .body, StatsMetricCard (+3 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.15
Nodes (13): 3. Phase gates, A0 — Research and architecture, A10 — Source app/editor association and Open action, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2 — Authenticated local Agent Bridge, A3 — Codex adapter, A4 — Claude adapter (+5 more)

### Community 126 - "LiveActivityStore"
Cohesion: 0.31
Nodes (5): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int

### Community 127 - "Agent Capability Matrix"
Cohesion: 0.17
Nodes (12): 1. Method and version boundary, 2. Primary supported integration surfaces, 3. Capability matrix, 4. Event-specific authority, 6. Source application association, 7. Design implications, 8. Official sources, Agent Capability Matrix (+4 more)

### Community 128 - "Agent Event Schema Draft"
Cohesion: 0.18
Nodes (11): 2. State vocabulary, 4. Normalized event types, 5. Versioned transport envelope, 6. Capability model, 7. Privacy projection, 8. Replay fixture contract, 9. Deferred decisions, Agent Event Schema Draft (+3 more)

### Community 129 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 130 - "AgentActivityKind"
Cohesion: 0.18
Nodes (11): AgentActivityKind, approval, command, failure, interruption, plan, session, subagent (+3 more)

### Community 131 - "BatteryActivityProvider"
Cohesion: 0.29
Nodes (5): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, Any, .description

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "SettingsWindowController"
Cohesion: 0.25
Nodes (6): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, NSObject, NSWindowDelegate, SettingsWindowController, Notification, NSWindow

### Community 134 - ".share"
Cohesion: 0.40
Nodes (4): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL

### Community 136 - "3. Session identity"
Cohesion: 0.40
Nodes (5): 3. Session identity, Collisions, Generation rules, Logical key, Project identity

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.40
Nodes (5): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, Agent Activity Feature Phase Plan

### Community 138 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

## Knowledge Gaps
- **759 isolated node(s):** `PackageDescription`, `package_app.sh script`, `live`, `replay`, `sessionStarted` (+754 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 963 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `SystemClipboardPasteboardClient`, `TimerCompletionNotificationCoordinator`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `.start`, `FileShelfStore`, `SupportedApp`, `View`, `Change Log`, `ArtworkAccentColorCache`, `ObservableObject`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `ModuleViews.swift`, `MediaCandidate`, `CompactIslandView`, `MediaModuleView`, `MediaSnapshot`, `LiveActivitySettingsSnapshot`, `FileDropProviderLoaderTests`, `IslandOverlayPanel`, `MediaController`, `IslandStateStore`, `AppSettingsTests`, `.opacity`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `IslandRootView.swift`, `Sendable`, `.reload`, `.openActiveMediaSource`, `ManualMediaRemoteDeadlineScheduler`, `.apply`, `.sessionID`, `AppSettings.swift`, `Phase Workflow For Future Work`, `Bool`, `DefaultExpandedTab`, `AgentEventStore`, `AgentEvent`, `AutoCollapseDelayPreset`, `AnimationPreset`, `IslandThemeStyle`, `GestureInputSource`, `FileDropProviderLoader`, `DynamicIslandLiveActivityKind`, `AgentCapability`, `DedicatedTimerPageView`, `CollapsedPreviewKind`, `AgentUsage`, `AgentEventType`, `AgentEventValidationError`, `Int`, `CodingKeys`, `RecordingFileShelfDefaults`, `AgentReplayHarness`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `.collapsedPreviewContent`, `CaseIterable`, `.remainingTime`, `ShortcutsStore`, `LiveActivitiesModuleView`, `LiveActivityStore`, `AgentActivityKind`, `BatteryActivityProvider`?**
  _High betweenness centrality (0.390) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `MenuBarController`, `SettingsWindowController`, `IslandRootView`, `ClipboardHistoryStore`, `SettingsView`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `IslandNavigationStore`, `FileShelfStore`, `View`, `ExpandedIslandLayoutMetrics`, `ObservableObject`, `Int`, `DynamicIslandLiveActivity`, `.init`, `ModuleViews.swift`, `CompactIslandView`, `MediaModuleView`, `LiveActivitySettingsSnapshot`, `FileDropProviderLoaderTests`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `OverlayWindowController`, `IslandRootView.swift`, `.reload`, `ClipboardImageCaptureLifecycleTests`, `OverlayPresentationSessionTests`, `AppSettings.swift`, `DefaultExpandedTab`, `String`, `AutoCollapseDelayPreset`, `AnimationPreset`, `IslandThemeStyle`, `GestureInputSource`, `DedicatedTimerPageView`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `SwiftUI`, `CaseIterable`, `AppDelegate`, `InnerBlurScaleCleanModifier`, `LiveActivitiesModuleView`?**
  _High betweenness centrality (0.183) - this node is a cross-community bridge._
- **Why does `IslandRootView` connect `IslandRootView` to `AppSettings`, `IslandGestureAction`, `SettingsWindowController`, `IslandEscapeRouter`, `IslandNavigationStore`, `View`, `Change Log`, `ExpandedIslandLayoutMetrics`, `DynamicIsland`, `DynamicIslandLiveActivity`, `ModuleViews.swift`, `What You Must Do When Invoked`, `MediaController`, `IslandStateStore`, `CGFloat`, `OverlayWindowController`, `IslandRootView.swift`, `IslandHostingView`, `FileDropProviderLoader`, `DedicatedTimerPageView`, `Int`, `FileShelfTemporaryStorage`, `CollapsedIslandContentMode`, `AppDelegate`, `InnerBlurScaleCleanModifier`, `LiveActivitiesModuleView`, `LiveActivityStore`?**
  _High betweenness centrality (0.074) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `live` to the rest of the system?**
  _759 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppSettings` be split into smaller, more focused modules?**
  _Cohesion score 0.02434894783520116 - nodes in this community are weakly interconnected._