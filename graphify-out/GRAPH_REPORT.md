# Graph Report - DynamicIsland  (2026-09-24)

## Corpus Check
- 119 files · ~158,751 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 3650 nodes · 10058 edges · 150 communities (134 shown, 16 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1336 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e0b9d844`
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
- .constrainedActivePlayerLayout
- Data
- DynamicIsland
- CompactIslandView
- MediaModuleView
- MediaSnapshot
- AppDelegate
- FileDropProviderLoader
- What You Must Do When Invoked
- String
- MediaCandidate
- .refresh
- IslandStateStore
- AppSettingsTests
- CGFloat
- View
- OverlayWindowController
- CollapsedLiveActivityPrioritySource
- IslandRootView.swift
- Sendable
- .reload
- .resolve
- ManualMediaRemoteDeadlineScheduler
- ClipboardImageCaptureLifecycleTests
- OverlayPresentationSessionTests
- .apply
- .event
- .wait
- IslandSurfaceBackground
- NowPlayingMediaProvider
- AgentEventPayload
- DefaultExpandedTab
- AgentEventStore
- .makeProcessor
- AgentBridgeIngress
- ControlledClipboardPersistence
- MediaController
- CaseIterable
- IslandHostingView
- AnimationPreset
- IslandThemeStyle
- SettingsSection
- .loadURL
- AgentBridgeDiscoveryPublisher
- AgentCapability
- Meaningful regression history
- .loadFileURLs
- ClipboardHistoryPresentationState
- Package.swift
- package_app.sh
- IslandLayoutStore
- AgentUsage
- DedicatedTimerPageView
- AgentEventType
- AgentEventValidationError
- ExpandedScrollEventRoutingPolicyTests
- graphify reference: extra exports and benchmark
- Int
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- ServerSpy
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
- AgentEvent
- .resolve
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- FileClipboardHistoryPersistence
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- AgentBridge
- ShortcutsModuleView
- .assertFailure
- LockedValue
- SettingsWindowController
- .remainingTime
- ShortcutsStore
- AgentBridgeHTTPRequestParser
- AgentBridgeAuthenticator
- Agent Activity Integration Architecture
- Double
- 3. Phase gates
- LiveActivityStore
- Agent Capability Matrix
- Agent Event Schema Draft
- AgentNotch Reference Review
- AgentActivityKind
- .signedRequest
- MenuBarController
- AgentState
- .share
- AgentBridgeHTTPStatus
- Agent Activity Feature Phase Plan
- LaunchAtLoginController.swift
- AudioVisualizerView
- AgentBridgeAuthenticationError
- Bool
- Fresh critical audit instructions
- .decode
- DynamicIslandLiveActivityKind
- AgentBridgeDiscoveryError
- 5. Local bridge decision
- AlbumArtworkView
- PriorityStepperRow

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 331 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 105 edges
5. `IslandRootView` - 75 edges
6. `ExpandedIslandView` - 67 edges
7. `AgentEventStore` - 60 edges
8. `AgentEvent` - 58 edges
9. `ClipboardHistoryStore` - 58 edges
10. `AgentSession` - 54 edges

## Surprising Connections (you probably didn't know these)
- `A1 — Normalized domain, `AgentEventStore`, replay harness` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `1. Decision summary` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `A10 — Source app/editor association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `9. Source association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `Stable native overlay architecture` --references--> `IslandRootView`  [INFERRED]
  README.md → Sources/DynamicIsland/Views/IslandRootView.swift

## Import Cycles
- None detected.

## Communities (150 total, 16 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (155): AnyPublisher, Never, AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray (+147 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (41): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, .now, IslandGestureAction, collapse, .displayName, expand, .id (+33 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (27): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+19 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.13
Nodes (18): ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted (+10 more)

### Community 4 - "SettingsView"
Cohesion: 0.18
Nodes (24): HelpText, .body, SettingsGroup, .body, SettingsView, .advancedSection, .appearanceSection, .body (+16 more)

### Community 5 - "IslandRootView"
Cohesion: 0.07
Nodes (31): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, IslandModules, CollapsedPreviewContent, CollapsedPreviewRowContent, ExpandedIslandRightStackVisibility (+23 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.13
Nodes (14): ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date, Int (+6 more)

### Community 8 - "TimerController"
Cohesion: 0.08
Nodes (27): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Double (+19 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.09
Nodes (21): NSPasteboard, NSPasteboardItem, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image (+13 more)

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.10
Nodes (22): NSObject, Bool, Duration, Never, Task, TimeInterval, UInt64, Void (+14 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.07
Nodes (25): Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint (+17 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.10
Nodes (23): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, NSEdgeInsets, NSScreen (+15 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.17
Nodes (8): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Date, TimeInterval, UserDefaults

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
Cohesion: 0.25
Nodes (4): MockTimerNotificationCenterClient, Bool, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (15): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults (+7 more)

### Community 19 - "SupportedApp"
Cohesion: 0.08
Nodes (26): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 3 Album Artwork Source Open, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier (+18 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.10
Nodes (24): Animation, 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor, 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix, 2026-07-04 - Phase 6A.2 Single-Panel Native Morph Correction, 2026-07-04 - Phase 6A Single Adaptive Island Panel, 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing (+16 more)

### Community 21 - "Change Log"
Cohesion: 0.06
Nodes (54): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+46 more)

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
Nodes (19): Calendar, ObservableObject, UUID, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView (+11 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (42): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+34 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.16
Nodes (18): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+10 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (12): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int (+4 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.19
Nodes (3): MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.10
Nodes (18): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Any (+10 more)

### Community 33 - ".constrainedActivePlayerLayout"
Cohesion: 0.23
Nodes (8): Double, ClickableAlbumArtworkButton, .artwork, .body, MediaButton, .body, .constrainedActivePlayerView, .regularActivePlayerView

### Community 34 - "Data"
Cohesion: 0.12
Nodes (12): CryptoKit, OSStatus, AgentBridgeCredentialError, invalidStoredSecret, keychain, randomGeneration, AgentBridgeCrypto, Data (+4 more)

### Community 35 - "DynamicIsland"
Cohesion: 0.07
Nodes (10): AppKit, Combine, CoreFoundation, Darwin, DynamicIsland, Foundation, Security, AirDropService (+2 more)

### Community 36 - "CompactIslandView"
Cohesion: 0.11
Nodes (22): Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CollapsedFileActivityCompactView, .accessibilityLabel, .fileText, CollapsedPreviewRow, CollapsedTimerActivityCompactView (+14 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.09
Nodes (23): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, MediaModuleView, .activePlayerView, .artistFontSize, .artworkSize, .body (+15 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.10
Nodes (19): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Phase 2.7 Media Source Arbitration, MediaDetectionProvider, MediaSnapshot, MediaSourceKind, browser, music, spotify (+11 more)

### Community 39 - "AppDelegate"
Cohesion: 0.14
Nodes (14): Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, 2. Existing DynamicIsland invariants, AppDelegate, .liveActivitySettingsPublisher, DynamicIslandApp, LiveActivitySettingsSnapshot, Any (+6 more)

### Community 40 - "FileDropProviderLoader"
Cohesion: 0.18
Nodes (11): FileDropProviderLoader, UTType, .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider (+3 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "String"
Cohesion: 0.11
Nodes (15): MediaArtworkFlipDirection, next, previous, MediaArtworkFlipRequest, .isExpired, CodingKeys, authorName, thumbnailURL (+7 more)

### Community 43 - "MediaCandidate"
Cohesion: 0.13
Nodes (12): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, Element, Index, Array, MediaArbitrator, MediaCandidate, .sourceKey, MediaImmediateSystemHandoff (+4 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.06
Nodes (32): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 4B.1 Expanded Tray Drop Handoff Fix (+24 more)

### Community 47 - "CGFloat"
Cohesion: 0.13
Nodes (16): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline, Evidence and graph limits, SwiftUI rendering and presentation (+8 more)

### Community 48 - "View"
Cohesion: 0.07
Nodes (45): AirDropDropZoneView, .body, .subtitle, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, .body (+37 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.08
Nodes (26): CFTimeInterval, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-04 - Phase 5J.4 Final Media Fit And Mouse Leave Rect Fix, 2026-07-04 - Phase 5J.5 Final Expanded Hover Tolerance Tightening, 2026-07-11 - Phase 9C Liquid Glass Visual Repair, DispatchWorkItem, NSPoint (+18 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.08
Nodes (30): Phase 13B.2 - Native In-Island Clipboard Interface, EnvironmentKey, Gesture, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, CollapseShellOnlyEnvironmentKey (+22 more)

### Community 52 - "Sendable"
Cohesion: 0.05
Nodes (94): Codable, Comparable, Equatable, Hashable, Identifiable, Int, RawRepresentable, 1. Domain contracts (+86 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 55 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.13
Nodes (16): ControlledMediaRemoteCallback, ControlledMediaRemoteProvider, Entry, ManualMediaRemoteDeadlineScheduler, .count, .scheduler, MediaRemoteCallbackBridgeTests, MediaRemoteRefreshRecoveryTests (+8 more)

### Community 56 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.19
Nodes (8): ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, CheckedContinuation, MainActor, Never, Sendable, XCTestExpectation

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.16
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".apply"
Cohesion: 0.14
Nodes (9): AgentEventReducer, SemanticResult, applied, rejected, Bool, Date, Value, AgentPrivacyProjection (+1 more)

### Community 59 - ".event"
Cohesion: 0.12
Nodes (18): AgentActivityDescriptor, AgentApprovalRequest, AgentPlanEvent, AgentSessionMetadata, AgentTerminalEvent, AgentToolEvent, AgentReplayFixture, AgentEventReducerTests (+10 more)

### Community 60 - ".wait"
Cohesion: 0.14
Nodes (19): CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, value, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending, MediaRemoteClient (+11 more)

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.10
Nodes (18): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+10 more)

### Community 62 - "NowPlayingMediaProvider"
Cohesion: 0.20
Nodes (8): AnyObject, 2026-07-04 - Phase 3.4 Album Artwork Stability, MediaRemoteDictionary, MediaRemoteProviding, NowPlayingMediaProvider, Double, NSDictionary, NSImage

### Community 63 - "AgentEventPayload"
Cohesion: 0.12
Nodes (16): AgentEventPayload, activity, approvalRequest, approvalResolution, capabilities, command, none, plan (+8 more)

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "AgentEventStore"
Cohesion: 0.15
Nodes (11): AgentEventStore, .activeSessions, .sessionsRequiringAttention, Bool, Date, AgentSessionID, AgentSessionInstanceID, AgentEventStoreTests (+3 more)

### Community 66 - ".makeProcessor"
Cohesion: 0.26
Nodes (6): AgentBridgeRequestProcessor, AgentBridgeEnvelopeIntegrationTests, StaticString, UInt, Any, UInt64

### Community 67 - "AgentBridgeIngress"
Cohesion: 0.09
Nodes (28): Decodable, AgentBridgeGenerationEntry, AgentBridgeIngress, Bool, Date, Result, UInt64, AgentBridgeHealth (+20 more)

### Community 68 - "ControlledClipboardPersistence"
Cohesion: 0.20
Nodes (6): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, Bool, Int

### Community 69 - "MediaController"
Cohesion: 0.12
Nodes (13): 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, MediaController, .currentArtworkPresentationIdentity, MediaPlayer, .displayName, music (+5 more)

### Community 70 - "CaseIterable"
Cohesion: 0.08
Nodes (27): CaseIterable, AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal (+19 more)

### Community 71 - "IslandHostingView"
Cohesion: 0.08
Nodes (20): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, Known Fragile Areas, Phase 11C.3 - Diagnostic WindowServer Transition Trace, NSHostingView, NSPanel, NSSize, NSTrackingArea, NSView (+12 more)

### Community 72 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 73 - "IslandThemeStyle"
Cohesion: 0.33
Nodes (6): 2026-07-11 - Phase 9D Theme Simplification, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass

### Community 74 - "SettingsSection"
Cohesion: 0.13
Nodes (15): SettingsSection, advanced, appearance, clipboard, gestures, .id, island, liveActivities (+7 more)

### Community 75 - ".loadURL"
Cohesion: 0.23
Nodes (6): NSSecureCoding, FileDropURLAccumulator, .urls, SendableItemProvider, NSItemProvider, TimeInterval

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.15
Nodes (9): Int32, AgentBridgeDiscoveryPublisher, FileManager, URL, AgentBridgeDiscoveryRecord, Date, AgentBridgeDiscoveryTests, UInt16 (+1 more)

### Community 77 - "AgentCapability"
Cohesion: 0.08
Nodes (25): AgentCapabilities, .all, AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage, costUsage (+17 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.70
Nodes (3): AirDropURLAccumulator, .urls, URL

### Community 80 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 83 - "IslandLayoutStore"
Cohesion: 0.13
Nodes (16): 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, Composition, state and settings, IslandModule, IslandLayoutStore, Bool, CGFloat, CGRect (+8 more)

### Community 84 - "AgentUsage"
Cohesion: 0.08
Nodes (22): AgentUsage, AgentUsageMetric, cachedInputTokens, contextLimit, contextUsed, cost, inputTokens, outputTokens (+14 more)

### Community 85 - "DedicatedTimerPageView"
Cohesion: 0.27
Nodes (7): DedicatedTimerPageView, .controlsFontSize, .controlsSpacing, .timerControlRow, .timerControlStack, .titleFontSize, .usesCompactLayout

### Community 86 - "AgentEventType"
Cohesion: 0.07
Nodes (29): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+21 more)

### Community 87 - "AgentEventValidationError"
Cohesion: 0.06
Nodes (35): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+27 more)

### Community 88 - "ExpandedScrollEventRoutingPolicyTests"
Cohesion: 0.26
Nodes (5): ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicyTests, Bool

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 90 - "Int"
Cohesion: 0.15
Nodes (14): 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Media and artwork, ArtworkPresentationCoordinator, .displayedSnapshot, Decision, MediaPausedSwitchGate, MediaPublishGuard (+6 more)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "ServerSpy"
Cohesion: 0.13
Nodes (19): Network, AgentBridgeNetworkError, listenerCancelled, listenerFailed, missingPort, AgentBridgeServing, DeferredServerSpy, .startCount (+11 more)

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
Cohesion: 0.23
Nodes (9): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+1 more)

### Community 103 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKey, CodingKeys, files, imagePNG, text, type, url

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentEvent"
Cohesion: 0.09
Nodes (20): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, AgentEventOrigin, live, replay (+12 more)

### Community 108 - "ShelfFileTile"
Cohesion: 0.21
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, 2026-07-04 - Phase 5I.2 Animation Performance Polish, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool (+1 more)

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.22
Nodes (6): FileDropPolicy, FileShelfTemporaryStorage, Bool, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 111 - "ServerFactorySpy"
Cohesion: 0.21
Nodes (9): AgentBridgeLifecycleTests, DiscoverySpy, .records, .removedLaunchIDs, ServerFactorySpy, .createdCount, AgentBridgeServerFactory, Error (+1 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.11
Nodes (18): AgentBridgeEnvelopeError, emptyBatch, eventTooLarge, generationConflict, invalidAuthority, invalidCapability, invalidEventType, invalidPayload (+10 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.16
Nodes (11): DispatchQueue, NWConnection, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, Result (+3 more)

### Community 114 - "AgentBridge"
Cohesion: 0.20
Nodes (10): HTTPURLResponse, AgentBridge, Runtime, AgentBridgeServerFactory, Error, UUID, AgentBridgeDiscoveryPublishing, AgentBridgeCredentialStore (+2 more)

### Community 115 - "ShortcutsModuleView"
Cohesion: 0.27
Nodes (8): ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount, .shortcutTileHeight, CGFloat, Int, Void

### Community 116 - ".assertFailure"
Cohesion: 0.19
Nodes (3): AgentBridgeHTTPParserTests, StaticString, UInt

### Community 117 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 118 - "SettingsWindowController"
Cohesion: 0.20
Nodes (6): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, NSWindowDelegate, SettingsWindowController, Notification, NSWindow

### Community 120 - "ShortcutsStore"
Cohesion: 0.16
Nodes (9): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutEditorRow, .body, Binding, Void (+1 more)

### Community 121 - "AgentBridgeHTTPRequestParser"
Cohesion: 0.20
Nodes (10): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, .result (+2 more)

### Community 122 - "AgentBridgeAuthenticator"
Cohesion: 0.38
Nodes (5): AgentBridgeAuthenticator, .rememberedNonceCount, NonceEntry, Date, Set

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.14
Nodes (14): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 3. Component boundaries, 4. Per-event authority, 6. Privacy and security boundaries, 7. Attention presentation contract (+6 more)

### Community 124 - "Double"
Cohesion: 0.13
Nodes (17): Interpreter guard for subcommands, Path, .percentText, .visualizerAccentColor, StatsLineChart, .body, StatsMetricCard, .body (+9 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.15
Nodes (13): 3. Phase gates, A0 — Research and architecture, A10 — Source app/editor association and Open action, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2 — Authenticated local Agent Bridge, A3 — Codex adapter, A4 — Claude adapter (+5 more)

### Community 126 - "LiveActivityStore"
Cohesion: 0.27
Nodes (6): LiveActivityStore, .primaryActivity, Double, LiveActivityStoreTests, Date, Int

### Community 127 - "Agent Capability Matrix"
Cohesion: 0.12
Nodes (16): 1. Method and version boundary, 2. Primary supported integration surfaces, 3. Capability matrix, 4. Event-specific authority, 5. Local storage audit (content redacted), 6. Source application association, 7. Design implications, 8. Official sources (+8 more)

### Community 128 - "Agent Event Schema Draft"
Cohesion: 0.12
Nodes (16): 2. State vocabulary, 3. Session identity, 4. Normalized event types, 5. Versioned transport envelope, 6. Capability model, 7. Privacy projection, 8. Replay fixture contract, 9. Deferred decisions (+8 more)

### Community 129 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 130 - "AgentActivityKind"
Cohesion: 0.18
Nodes (11): AgentActivityKind, approval, command, failure, interruption, plan, session, subagent (+3 more)

### Community 131 - ".signedRequest"
Cohesion: 0.34
Nodes (4): AgentBridgeHTTPRequest, AgentBridgeAuthenticationTests, AgentBridgeTestSupport, Int64

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "AgentState"
Cohesion: 0.13
Nodes (14): AgentState, completed, failed, idle, interrupted, .isTerminal, planning, planReady (+6 more)

### Community 134 - ".share"
Cohesion: 0.50
Nodes (3): 2026-07-05 - Phase 8A File Shelf Tray Polish, Bool, URL

### Community 136 - "AgentBridgeHTTPStatus"
Cohesion: 0.12
Nodes (16): AgentBridgeHTTPResponse, .data, AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed (+8 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.40
Nodes (5): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, Agent Activity Feature Phase Plan

### Community 138 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 139 - "AudioVisualizerView"
Cohesion: 0.12
Nodes (18): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing (+10 more)

### Community 140 - "AgentBridgeAuthenticationError"
Cohesion: 0.12
Nodes (16): Error, AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull (+8 more)

### Community 142 - "Fresh critical audit instructions"
Cohesion: 0.29
Nodes (6): Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits

### Community 143 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

### Community 144 - "DynamicIslandLiveActivityKind"
Cohesion: 0.29
Nodes (7): 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 145 - "AgentBridgeDiscoveryError"
Cohesion: 0.40
Nodes (4): AgentBridgeDiscoveryError, insecurePermissions, invalidRecord, unavailableDirectory

### Community 147 - "5. Local bridge decision"
Cohesion: 0.50
Nodes (4): 5. Local bridge decision, Alternatives, OTLP, Selected architecture

### Community 148 - "AlbumArtworkView"
Cohesion: 0.50
Nodes (4): AlbumArtworkView, .body, .body, NSImage

### Community 149 - "PriorityStepperRow"
Cohesion: 0.67
Nodes (3): PriorityStepperRow, .body, Int

## Knowledge Gaps
- **827 isolated node(s):** `PackageDescription`, `package_app.sh script`, `CoreFoundation`, `unavailableDirectory`, `invalidRecord` (+822 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1057 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **16 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `TimerController`, `TimerCompletionNotificationCoordinator`, `ClipboardHistoryPayload`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `.start`, `FileShelfStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `ClipboardHistoryEntry`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `.constrainedActivePlayerLayout`, `Data`, `CompactIslandView`, `MediaModuleView`, `MediaSnapshot`, `AppDelegate`, `FileDropProviderLoader`, `MediaCandidate`, `AppSettingsTests`, `View`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `IslandRootView.swift`, `Sendable`, `.reload`, `.resolve`, `ManualMediaRemoteDeadlineScheduler`, `.apply`, `.event`, `.wait`, `NowPlayingMediaProvider`, `AgentEventPayload`, `DefaultExpandedTab`, `AgentEventStore`, `.makeProcessor`, `AgentBridgeIngress`, `MediaController`, `CaseIterable`, `AnimationPreset`, `IslandThemeStyle`, `SettingsSection`, `.loadURL`, `AgentBridgeDiscoveryPublisher`, `AgentCapability`, `IslandLayoutStore`, `AgentUsage`, `AgentEventType`, `AgentEventValidationError`, `Int`, `ServerSpy`, `CodingKeys`, `RecordingFileShelfDefaults`, `AgentEvent`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `ServerFactorySpy`, `AgentBridgeEnvelopeError`, `AgentBridgeNetworkServer`, `AgentBridge`, `.remainingTime`, `ShortcutsStore`, `AgentBridgeHTTPRequestParser`, `AgentBridgeAuthenticator`, `Double`, `LiveActivityStore`, `AgentActivityKind`, `.signedRequest`, `AgentState`, `AgentBridgeHTTPStatus`, `AudioVisualizerView`, `Bool`, `DynamicIslandLiveActivityKind`, `.collapsedPreviewContent`, `PriorityStepperRow`?**
  _High betweenness centrality (0.449) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `IslandNavigationStore`, `FileShelfStore`, `ExpandedIslandView`, `ClipboardHistoryEntry`, `Int`, `DynamicIslandLiveActivity`, `.init`, `.constrainedActivePlayerLayout`, `CompactIslandView`, `MediaModuleView`, `AppDelegate`, `FileDropProviderLoader`, `String`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `View`, `OverlayWindowController`, `IslandRootView.swift`, `.reload`, `ClipboardImageCaptureLifecycleTests`, `OverlayPresentationSessionTests`, `DefaultExpandedTab`, `CaseIterable`, `AnimationPreset`, `IslandThemeStyle`, `DedicatedTimerPageView`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `ShortcutsModuleView`, `SettingsWindowController`?**
  _High betweenness centrality (0.133) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `AppSettings`, `IslandGestureAction`, `CompactIslandView`, `IslandRootView`, `IslandEscapeRouter`, `IslandHostingView`, `AppDelegate`, `IslandThemeStyle`, `String`, `NotchGeometryService`, `IslandStateStore`, `IslandLayoutStore`, `IslandRootView.swift`, `Change Log`, `SettingsWindowController`, `OverlayPresentationSessionTests`, `DynamicIslandLiveActivity`, `.init`?**
  _High betweenness centrality (0.051) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `CoreFoundation` to the rest of the system?**
  _827 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppSettings` be split into smaller, more focused modules?**
  _Cohesion score 0.024731182795698924 - nodes in this community are weakly interconnected._