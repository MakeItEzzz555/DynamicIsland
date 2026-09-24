# Graph Report - DynamicIsland  (2026-09-24)

## Corpus Check
- 119 files · ~158,602 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 3648 nodes · 10047 edges · 145 communities (131 shown, 14 thin omitted)
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
- String
- ExpandedIslandView
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- ObservableObject
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- .init
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- XCTestCase
- .constrainedActivePlayerLayout
- Data
- DynamicIsland
- CompactIslandView
- MediaModuleView
- MediaSnapshot
- AppDelegate
- FileDropProviderLoaderTests
- What You Must Do When Invoked
- AgentSessionID
- MediaController
- .refresh
- IslandStateStore
- AppSettingsTests
- CGFloat
- View
- OverlayWindowController
- CollapsedLiveActivityPrioritySource
- IslandRootView.swift
- Equatable
- .reload
- .openActiveMediaSource
- ManualMediaRemoteDeadlineScheduler
- ClipboardPasteboardReadResult
- OverlayPresentationSessionTests
- .apply
- .sessionID
- VisualizerAccentMode
- IslandSurfaceBackground
- Phase Workflow For Future Work
- OverlayGeometrySignature
- DefaultExpandedTab
- AgentEventStore
- .makeProcessor
- Sendable
- ControlledClipboardPersistence
- MediaPlayer
- AutoCollapseDelayPreset
- IslandHostingView
- AnimationPreset
- IslandThemeStyle
- GestureInputSource
- FileDropProviderLoader
- AgentBridgeDiscoveryPublisher
- AgentCapability
- Meaningful regression history
- .loadFileURLs
- ClipboardHistoryPresentationState
- Package.swift
- package_app.sh
- IslandLayoutStore
- AgentUsage
- .progress
- AgentEventType
- AgentEventValidationError
- ExpandedScrollEventRoutingPolicyTests
- graphify reference: extra exports and benchmark
- MediaController.swift
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
- Current architecture baseline
- .assertFailure
- LockedValue
- CaseIterable
- .remainingTime
- ShortcutsStore
- AgentBridgeHTTPRequestParser
- .shellDuration
- Agent Activity Integration Architecture
- DedicatedTimerPageView
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
- AudioVisualizerVariant
- Fresh critical audit instructions
- .decode
- SwiftUI

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
- `2026-07-03 - Common App Launch Resolver` --references--> `AppLaunchService`  [INFERRED]
  context.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `A10 — Source app/editor association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `9. Source association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift

## Import Cycles
- None detected.

## Communities (145 total, 14 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (155): AnyPublisher, Never, AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray (+147 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.08
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
Nodes (28): 2026-07-04 - Phase 5J Single Visual Surface Morph, 2026-07-04 - Phase 6A Single Adaptive Island Panel, 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, IslandModules, CollapsedPreviewRowContent, ExpandedIslandRightStackVisibility (+20 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.11
Nodes (19): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date (+11 more)

### Community 8 - "TimerController"
Cohesion: 0.12
Nodes (19): ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration, MainActor (+11 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.10
Nodes (20): Bool, Duration, Never, Task, TimeInterval, UInt64, Void, SystemTimerNotificationCenterClient (+12 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.08
Nodes (24): Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint (+16 more)

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
Cohesion: 0.14
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.13
Nodes (14): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName, timer (+6 more)

### Community 17 - ".start"
Cohesion: 0.24
Nodes (5): TimerCompletionNotificationPreferences, MockTimerNotificationCenterClient, Bool, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (15): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults (+7 more)

### Community 19 - "String"
Cohesion: 0.09
Nodes (27): AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName, edge (+19 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.12
Nodes (19): Animation, 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor, 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix, 2026-07-04 - Phase 6A.2 Single-Panel Native Morph Correction, 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging (+11 more)

### Community 21 - "Change Log"
Cohesion: 0.06
Nodes (51): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish (+43 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ObservableObject"
Cohesion: 0.11
Nodes (15): Calendar, ObservableObject, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body, .emptyState, .header, ClipboardThumbnailCache (+7 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (42): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+34 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.10
Nodes (27): 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer (+19 more)

### Community 29 - ".init"
Cohesion: 0.15
Nodes (9): Phase 11C.3 - Diagnostic WindowServer Transition Trace, NSPanel, 2. Existing DynamicIsland invariants, Native overlay, geometry and input, IslandOverlayPanel, .canBecomeKey, .canBecomeMain, OverlayPersistence (+1 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (12): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int (+4 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.17
Nodes (5): Decision, Date, MediaArbitratorTests, Bool, NSImage

### Community 32 - "XCTestCase"
Cohesion: 0.09
Nodes (19): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Any (+11 more)

### Community 33 - ".constrainedActivePlayerLayout"
Cohesion: 0.24
Nodes (7): Double, ClickableAlbumArtworkButton, .artwork, .body, MediaButton, .body, .regularActivePlayerView

### Community 34 - "Data"
Cohesion: 0.09
Nodes (17): CryptoKit, OSStatus, AgentBridgeAuthenticator, .rememberedNonceCount, AgentBridgeCredentialError, invalidStoredSecret, keychain, randomGeneration (+9 more)

### Community 35 - "DynamicIsland"
Cohesion: 0.07
Nodes (10): AppKit, Combine, CoreFoundation, Darwin, DynamicIsland, Foundation, Security, AirDropService (+2 more)

### Community 36 - "CompactIslandView"
Cohesion: 0.11
Nodes (22): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CollapsedFileActivityCompactView, .accessibilityLabel, .fileText, CollapsedTimerActivityCompactView (+14 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.07
Nodes (32): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, AlbumArtworkView, .body, EmptyMediaLauncherView, .body, .body (+24 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.10
Nodes (18): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, MediaDetectionProvider, MediaSnapshot, MediaSourceKind, browser, music, spotify, system (+10 more)

### Community 39 - "AppDelegate"
Cohesion: 0.10
Nodes (19): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSWindowDelegate, AppDelegate, .liveActivitySettingsPublisher (+11 more)

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.18
Nodes (9): .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, URL, UserDefaults (+1 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "AgentSessionID"
Cohesion: 0.11
Nodes (16): 3. Component boundaries, Adapter contract, State ownership, AgentBridgeGenerationEntry, AgentBridgeIngress, Bool, Date, Result (+8 more)

### Community 43 - "MediaController"
Cohesion: 0.11
Nodes (12): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, BrowserScriptTarget, MediaArbitrator, MediaCandidate, .sourceKey, MediaController, .currentArtworkPresentationIdentity, MediaSourceIdentity (+4 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.07
Nodes (26): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, App Entry, Collapsed, Current Architecture, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes (+18 more)

### Community 47 - "CGFloat"
Cohesion: 0.15
Nodes (15): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, CollapsedPreviewContent, CollapsedPreviewRow, .body, .collapsedPreviewContent (+7 more)

### Community 48 - "View"
Cohesion: 0.08
Nodes (42): AirDropDropZoneView, .body, .subtitle, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, .percentText (+34 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.08
Nodes (26): CFTimeInterval, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-04 - Phase 5J.4 Final Media Fit And Mouse Leave Rect Fix, 2026-07-04 - Phase 5J.5 Final Expanded Hover Tolerance Tightening, 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, 2026-07-11 - Phase 9C Liquid Glass Visual Repair, DispatchWorkItem (+18 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.07
Nodes (33): EnvironmentKey, Gesture, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, CollapseShellOnlyEnvironmentKey, EnvironmentValues (+25 more)

### Community 52 - "Equatable"
Cohesion: 0.05
Nodes (88): Codable, Comparable, Equatable, Hashable, Identifiable, Int, RawRepresentable, 1. Domain contracts (+80 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - ".openActiveMediaSource"
Cohesion: 0.15
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 55 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.06
Nodes (42): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, value, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending (+34 more)

### Community 56 - "ClipboardPasteboardReadResult"
Cohesion: 0.10
Nodes (21): ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult (+13 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".apply"
Cohesion: 0.13
Nodes (11): AgentEventReducer, SemanticResult, applied, rejected, Bool, Date, Value, AgentProjectContext (+3 more)

### Community 59 - ".sessionID"
Cohesion: 0.18
Nodes (9): AgentActivityDescriptor, AgentToolEvent, AgentReductionResult, AgentEventReducerTests, Set, TimeInterval, AgentTestFixture, Int (+1 more)

### Community 60 - "VisualizerAccentMode"
Cohesion: 0.33
Nodes (6): VisualizerAccentMode, artwork, .displayName, .id, system, white

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "Phase Workflow For Future Work"
Cohesion: 0.18
Nodes (11): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration (+3 more)

### Community 63 - "OverlayGeometrySignature"
Cohesion: 0.17
Nodes (11): Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, QuartzCore, ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicy (+3 more)

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "AgentEventStore"
Cohesion: 0.14
Nodes (8): AgentEventStore, Bool, Date, AgentEventStoreTests, Int, TimeInterval, UInt64, UInt64

### Community 66 - ".makeProcessor"
Cohesion: 0.22
Nodes (9): AgentBridgeRequestProcessor, AgentBridgeHTTPResponse, .data, AgentBridgeEnvelopeIntegrationTests, StaticString, UInt, AgentBridgeTestSupport, Any (+1 more)

### Community 67 - "Sendable"
Cohesion: 0.08
Nodes (49): Decodable, Sendable, AgentBridgeHealth, AgentBridgeIngestionResult, AgentBridgeLimits, AgentBridgeState, degraded, failed (+41 more)

### Community 68 - "ControlledClipboardPersistence"
Cohesion: 0.22
Nodes (7): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, Bool, Int, TimeInterval

### Community 69 - "MediaPlayer"
Cohesion: 0.28
Nodes (5): MediaPlayer, .displayName, music, .playPauseCommand, spotify

### Community 70 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 71 - "IslandHostingView"
Cohesion: 0.14
Nodes (12): 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, NSHostingView, NSSize, NSTrackingArea, NSView (+4 more)

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
Cohesion: 0.30
Nodes (7): NSSecureCoding, completion, FileDropProviderLoader, SendableItemProvider, NSItemProvider, TimeInterval, UTType

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.15
Nodes (9): Int32, AgentBridgeDiscoveryPublisher, FileManager, URL, AgentBridgeDiscoveryRecord, Date, AgentBridgeDiscoveryTests, UInt16 (+1 more)

### Community 77 - "AgentCapability"
Cohesion: 0.08
Nodes (26): AgentCapabilities, .all, AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage, costUsage (+18 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.48
Nodes (4): AirDropURLAccumulator, .urls, NSItemProvider, URL

### Community 80 - "ClipboardHistoryPresentationState"
Cohesion: 0.25
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 83 - "IslandLayoutStore"
Cohesion: 0.13
Nodes (17): 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, Phase 13B.2 - Native In-Island Clipboard Interface, IslandLayoutStore, Bool, CGFloat (+9 more)

### Community 84 - "AgentUsage"
Cohesion: 0.08
Nodes (22): AgentUsage, AgentUsageMetric, cachedInputTokens, contextLimit, contextUsed, cost, inputTokens, outputTokens (+14 more)

### Community 85 - ".progress"
Cohesion: 0.18
Nodes (8): Double, Int, TimerProgressColorStage, high, low, mid, TimerProgressFormatting, TimerProgressFormattingTests

### Community 86 - "AgentEventType"
Cohesion: 0.07
Nodes (29): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+21 more)

### Community 87 - "AgentEventValidationError"
Cohesion: 0.06
Nodes (35): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+27 more)

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 90 - "MediaController.swift"
Cohesion: 0.08
Nodes (27): 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, Element, Index, Media and artwork (+19 more)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "ServerSpy"
Cohesion: 0.12
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
Cohesion: 0.10
Nodes (18): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, AgentEventOrigin, live, replay (+10 more)

### Community 108 - "ShelfFileTile"
Cohesion: 0.21
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, NSImage (+1 more)

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.18
Nodes (8): FileDropPolicy, FileDropURLAccumulator, .urls, FileShelfTemporaryStorage, Bool, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 111 - "ServerFactorySpy"
Cohesion: 0.23
Nodes (9): AgentBridgeLifecycleTests, DiscoverySpy, .records, .removedLaunchIDs, ServerFactorySpy, .createdCount, AgentBridgeServerFactory, Error (+1 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.07
Nodes (29): Error, AgentBridgeDiscoveryError, insecurePermissions, invalidRecord, unavailableDirectory, AgentBridgeEnvelopeError, emptyBatch, eventTooLarge (+21 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.20
Nodes (10): DispatchQueue, NWConnection, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, Result (+2 more)

### Community 114 - "AgentBridge"
Cohesion: 0.20
Nodes (10): HTTPURLResponse, AgentBridge, Runtime, AgentBridgeServerFactory, Error, UUID, AgentBridgeDiscoveryPublishing, AgentBridgeCredentialStore (+2 more)

### Community 115 - "Current architecture baseline"
Cohesion: 0.18
Nodes (8): Activities and utility modules, Build and tests, Clipboard engine and persistence, Composition, state and settings, Current architecture baseline, Evidence and graph limits, DynamicIslandApp, IslandModule

### Community 116 - ".assertFailure"
Cohesion: 0.19
Nodes (3): AgentBridgeHTTPParserTests, StaticString, UInt

### Community 117 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 118 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, LiveActivityStyle, compact, detailed, .id

### Community 120 - "ShortcutsStore"
Cohesion: 0.15
Nodes (11): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+3 more)

### Community 121 - "AgentBridgeHTTPRequestParser"
Cohesion: 0.18
Nodes (10): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, .result (+2 more)

### Community 122 - ".shellDuration"
Cohesion: 0.42
Nodes (4): .clipboardBackdropAnimation, .contentVisibilityAnimation, IslandContentTransitionTiming, TimeInterval

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.14
Nodes (14): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 5. Local bridge decision, 6. Privacy and security boundaries, 8. Expanded Agent Activity contract (+6 more)

### Community 124 - "DedicatedTimerPageView"
Cohesion: 0.11
Nodes (21): Interpreter guard for subcommands, Path, .visualizerAccentColor, DedicatedTimerPageView, .body, .controlsFontSize, .controlsSpacing, .titleFontSize (+13 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.15
Nodes (13): 3. Phase gates, A0 — Research and architecture, A10 — Source app/editor association and Open action, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2 — Authenticated local Agent Bridge, A3 — Codex adapter, A4 — Claude adapter (+5 more)

### Community 126 - "LiveActivityStore"
Cohesion: 0.31
Nodes (5): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int

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
Cohesion: 0.37
Nodes (3): AgentBridgeHTTPRequest, AgentBridgeAuthenticationTests, Int64

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
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.40
Nodes (5): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, Agent Activity Feature Phase Plan

### Community 138 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 139 - "AudioVisualizerView"
Cohesion: 0.29
Nodes (8): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerView, .body, .shouldAnimateContinuously, .visualizerOpacity, Double, Int, TimeInterval

### Community 140 - "AgentBridgeAuthenticationError"
Cohesion: 0.22
Nodes (9): AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull, timestampOutsideWindow (+1 more)

### Community 141 - "AudioVisualizerVariant"
Cohesion: 0.25
Nodes (8): AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing, CGSize

### Community 142 - "Fresh critical audit instructions"
Cohesion: 0.29
Nodes (6): Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits

### Community 143 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

## Knowledge Gaps
- **827 isolated node(s):** `PackageDescription`, `package_app.sh script`, `CoreFoundation`, `unavailableDirectory`, `invalidRecord` (+822 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1057 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `TimerCompletionNotificationCoordinator`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `.start`, `FileShelfStore`, `Change Log`, `ArtworkAccentColorCache`, `ObservableObject`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `XCTestCase`, `.constrainedActivePlayerLayout`, `Data`, `CompactIslandView`, `MediaModuleView`, `MediaSnapshot`, `AppDelegate`, `FileDropProviderLoaderTests`, `AgentSessionID`, `MediaController`, `IslandStateStore`, `AppSettingsTests`, `View`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `IslandRootView.swift`, `Equatable`, `.reload`, `.openActiveMediaSource`, `ManualMediaRemoteDeadlineScheduler`, `.apply`, `.sessionID`, `VisualizerAccentMode`, `OverlayGeometrySignature`, `DefaultExpandedTab`, `AgentEventStore`, `.makeProcessor`, `Sendable`, `MediaPlayer`, `AutoCollapseDelayPreset`, `AnimationPreset`, `IslandThemeStyle`, `GestureInputSource`, `FileDropProviderLoader`, `AgentBridgeDiscoveryPublisher`, `AgentCapability`, `IslandLayoutStore`, `AgentUsage`, `AgentEventType`, `AgentEventValidationError`, `MediaController.swift`, `ServerSpy`, `CodingKeys`, `RecordingFileShelfDefaults`, `AgentEvent`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `ServerFactorySpy`, `AgentBridgeEnvelopeError`, `AgentBridge`, `CaseIterable`, `.remainingTime`, `ShortcutsStore`, `AgentBridgeHTTPRequestParser`, `DedicatedTimerPageView`, `LiveActivityStore`, `AgentActivityKind`, `.signedRequest`, `AgentState`, `AgentBridgeHTTPStatus`, `SwiftUI`?**
  _High betweenness centrality (0.442) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `SwiftUI`, `IslandNavigationStore`, `FileShelfStore`, `String`, `ExpandedIslandView`, `ObservableObject`, `Int`, `DynamicIslandLiveActivity`, `.init`, `.constrainedActivePlayerLayout`, `CompactIslandView`, `MediaModuleView`, `AppDelegate`, `FileDropProviderLoaderTests`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `View`, `OverlayWindowController`, `IslandRootView.swift`, `.reload`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `VisualizerAccentMode`, `DefaultExpandedTab`, `AutoCollapseDelayPreset`, `AnimationPreset`, `IslandThemeStyle`, `GestureInputSource`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `CaseIterable`, `ShortcutsStore`, `.shellDuration`, `DedicatedTimerPageView`?**
  _High betweenness centrality (0.140) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `AppSettings`, `CompactIslandView`, `IslandRootView`, `IslandEscapeRouter`, `AppDelegate`, `IslandHostingView`, `IslandThemeStyle`, `NotchGeometryService`, `IslandStateStore`, `IslandLayoutStore`, `Change Log`, `OverlayPresentationSessionTests`, `DynamicIslandLiveActivity`, `.init`, `OverlayGeometrySignature`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `CoreFoundation` to the rest of the system?**
  _827 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppSettings` be split into smaller, more focused modules?**
  _Cohesion score 0.024731182795698924 - nodes in this community are weakly interconnected._