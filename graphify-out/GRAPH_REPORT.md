# Graph Report - DynamicIsland  (2026-09-25)

## Corpus Check
- 125 files · ~164,576 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 3840 nodes · 10806 edges · 151 communities (139 shown, 12 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1424 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3f8c326e`
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
- ObservableObject
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- .init
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- AgentSourceRegistry
- AgentBridgeAuthenticator
- Foundation
- Equatable
- MediaModuleView
- Phase Workflow For Future Work
- MediaCandidate
- FileDropProviderLoader
- What You Must Do When Invoked
- YouTubeMetadataProvider
- String
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
- CompactIslandView
- ManualMediaRemoteDeadlineScheduler
- ClipboardPasteboardReadResult
- OverlayPresentationSessionTests
- .event
- .sessionID
- AgentIngestionCoordinator
- IslandSurfaceBackground
- IslandHostingView
- NowPlayingMediaProvider
- DefaultExpandedTab
- AgentEventStore
- .makeProcessor
- AgentBridgeDiscoveryRecord
- Data
- AppDelegate
- AgentEvent
- OverlayGeometrySignature
- DynamicIslandLiveActivityKind
- MediaRemoteCallbackState
- AgentEventValidationError
- completion
- AgentBridgeDiscoveryPublisher
- AgentCapability
- Meaningful regression history
- .loadFileURLs
- ModuleViews.swift
- Package.swift
- package_app.sh
- CollapsedPreviewKind
- .apply
- .pause
- AgentEventType
- AgentEventStoreLimits
- ShortcutsStore
- graphify reference: extra exports and benchmark
- Int
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- ServerSpy
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- SettingsSection
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- .progress
- RecordingFileShelfDefaults
- AgentReplayHarness
- MediaRemoteTestLock
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- DynamicIsland Project Context
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- AgentBridge
- .testTimeoutRunsNewestPendingRefreshFallbackAndRejectsLateNativeResult
- .assertFailure
- Error
- AudioVisualizerView
- FileClipboardHistoryPersistence
- AgentSourceHealthState
- AgentBridgeHTTPRequestParser
- AgentEvidenceAuthority
- Agent Activity Integration Architecture
- DedicatedTimerPageView
- 3. Phase gates
- LiveActivityStore
- Agent Capability Matrix
- Agent Event Schema Draft
- .constrainedActivePlayerLayout
- AgentActivityKind
- .signedRequest
- MenuBarController
- Fresh critical audit instructions
- MediaRemoteClient
- AgentBridgeHTTPStatus
- Agent Activity Feature Phase Plan
- XCTestCase
- AppSettings.swift
- AnimationPreset
- .decode
- AutoCollapseDelayPreset
- AudioVisualizerVariant
- GestureInputSource
- IslandThemeStyle
- TimerNotificationAuthorizationStatus
- CaseIterable
- 3. Session identity
- 5. Local bridge decision

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 331 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 105 edges
5. `IslandRootView` - 75 edges
6. `ExpandedIslandView` - 67 edges
7. `AgentEventStore` - 65 edges
8. `AgentEvent` - 64 edges
9. `ClipboardHistoryStore` - 58 edges
10. `AgentSession` - 54 edges

## Surprising Connections (you probably didn't know these)
- `A1 — Normalized domain, `AgentEventStore`, replay harness` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `1. Decision summary` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `2026-07-03 - Common App Launch Resolver` --references--> `AppLaunchService`  [INFERRED]
  context.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `9. Source association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift

## Import Cycles
- None detected.

## Communities (151 total, 12 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (155): AnyPublisher, Never, AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray (+147 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (40): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, .now, IslandGestureAction, collapse, .displayName, expand (+32 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (28): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+20 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.20
Nodes (6): ArtworkFlipPresentationState, .queuedSnapshot, ArtworkPresentationSnapshot, QueuedTransition, ArtworkFlipPresentationStateTests, Bool

### Community 4 - "SettingsView"
Cohesion: 0.16
Nodes (27): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsView, .advancedSection (+19 more)

### Community 5 - "IslandRootView"
Cohesion: 0.08
Nodes (31): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, Phase 11C.9 - Predictive Space Motion Resampling, Phase 12A - Final Island Content Transition Sequencing, Phase 12B - Native Overlay Cleanup And Runtime Optimization, Phase 13A - Expanded Visibility Controls, IslandModules, CollapsedPreviewContent (+23 more)

### Community 6 - "ClipboardHistoryPresentationState"
Cohesion: 0.12
Nodes (15): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+7 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.08
Nodes (28): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed (+20 more)

### Community 8 - "TimerController"
Cohesion: 0.11
Nodes (19): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration (+11 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.12
Nodes (10): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, ClipboardSensitivePasteboardTypes, Bool, Int, Set, SystemClipboardPasteboardClient (+2 more)

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.12
Nodes (17): Bool, Duration, Never, Task, TimeInterval, UInt64, Void, SystemTimerNotificationCenterClient (+9 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.08
Nodes (23): Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint (+15 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.12
Nodes (19): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth (+11 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.17
Nodes (7): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Date, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (18): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+10 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.12
Nodes (15): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName (+7 more)

### Community 17 - ".start"
Cohesion: 0.25
Nodes (4): MockTimerNotificationCenterClient, Bool, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (14): 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge (+6 more)

### Community 19 - "SupportedApp"
Cohesion: 0.08
Nodes (25): 2026-07-04 - Phase 3 Album Artwork Source Open, A10 — Source app/editor association and Open action, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome (+17 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.14
Nodes (14): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 12A.2 - Single Authoritative Shell/Content Timeline, ExpandedIslandView, .airDropTargetBinding, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation (+6 more)

### Community 21 - "Change Log"
Cohesion: 0.06
Nodes (55): 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+47 more)

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
Nodes (47): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+39 more)

### Community 27 - "Int"
Cohesion: 0.12
Nodes (13): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.13
Nodes (20): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+12 more)

### Community 29 - ".init"
Cohesion: 0.15
Nodes (8): Phase 11C.3 - Diagnostic WindowServer Transition Trace, NSPanel, Native overlay, geometry and input, IslandOverlayPanel, .canBecomeKey, .canBecomeMain, OverlayPersistence, NSWindow

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (12): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int (+4 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.17
Nodes (5): Decision, Date, MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "AgentSourceRegistry"
Cohesion: 0.09
Nodes (31): AgentProducerDescriptor, AgentProducerPolicy, AgentSourceHealthError, identityConflict, invalidEvent, policyRejected, producerFailure, schemaMismatch (+23 more)

### Community 34 - "AgentBridgeAuthenticator"
Cohesion: 0.14
Nodes (15): AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull, timestampOutsideWindow (+7 more)

### Community 35 - "Foundation"
Cohesion: 0.06
Nodes (15): AppKit, Combine, DynamicIsland, Foundation, ServiceManagement, LaunchAtLoginController, Bool, Array (+7 more)

### Community 36 - "Equatable"
Cohesion: 0.10
Nodes (40): Equatable, AgentBridgeWirePayload, .populatedFieldCount, AgentActivityDescriptor, AgentApprovalRequest, AgentApprovalResolution, AgentCommandEvent, AgentEventPayload (+32 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.07
Nodes (28): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, .body, MediaLauncherButton, .body, MediaModuleView (+20 more)

### Community 38 - "Phase Workflow For Future Work"
Cohesion: 0.07
Nodes (30): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment (+22 more)

### Community 39 - "MediaCandidate"
Cohesion: 0.10
Nodes (19): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, Index, Array, ArtworkFlipPhase, firstHalf, idle, secondHalf, MediaArbitrator (+11 more)

### Community 40 - "FileDropProviderLoader"
Cohesion: 0.19
Nodes (10): FileDropProviderLoader, UTType, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, URL (+2 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "YouTubeMetadataProvider"
Cohesion: 0.14
Nodes (15): CodingKey, CodingKeys, files, imagePNG, text, type, url, CodingKeys (+7 more)

### Community 43 - "String"
Cohesion: 0.09
Nodes (12): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, BrowserScriptTarget, MediaController, .currentArtworkPresentationIdentity, MediaPlayer, .displayName, music, .playPauseCommand (+4 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.06
Nodes (36): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, App Entry, Current Architecture, Geometry (+28 more)

### Community 47 - "CGFloat"
Cohesion: 0.13
Nodes (16): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline, Evidence and graph limits, SwiftUI rendering and presentation (+8 more)

### Community 48 - "View"
Cohesion: 0.08
Nodes (44): AirDropDropZoneView, .body, .subtitle, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, .body (+36 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.09
Nodes (21): CFTimeInterval, DispatchWorkItem, NSPoint, NSRect, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedGestureCandidateScreenRegion, .collapsedInteractiveSurfaceFrame (+13 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.10
Nodes (18): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, Any, CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank (+10 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.07
Nodes (34): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, EnvironmentKey, AnyTransition, .blurBounce, .compactMediaContent (+26 more)

### Community 52 - "Sendable"
Cohesion: 0.04
Nodes (98): Codable, Hashable, Identifiable, Int, RawRepresentable, 1. Domain contracts, Sendable, AgentEventOrigin (+90 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - "CompactIslandView"
Cohesion: 0.09
Nodes (28): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right (+20 more)

### Community 55 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.35
Nodes (4): ManualMediaRemoteDeadlineScheduler, MediaRemoteCallbackBridgeTests, Bool, Int

### Community 56 - "ClipboardPasteboardReadResult"
Cohesion: 0.10
Nodes (21): ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult (+13 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".event"
Cohesion: 0.21
Nodes (12): Success, AgentIngestionCoordinatorTests, Array, .single, Element, Result, Set, StaticString (+4 more)

### Community 59 - ".sessionID"
Cohesion: 0.19
Nodes (6): AgentEventReducerTests, Set, TimeInterval, AgentTestFixture, Int, TimeInterval

### Community 60 - "AgentIngestionCoordinator"
Cohesion: 0.10
Nodes (28): AgentIngestionCoordinator, Bool, CheckedContinuation, Date, Never, Result, UInt64, Void (+20 more)

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "IslandHostingView"
Cohesion: 0.12
Nodes (13): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, NSHostingView, NSSize, NSTrackingArea (+5 more)

### Community 63 - "NowPlayingMediaProvider"
Cohesion: 0.20
Nodes (8): 2026-07-04 - Phase 3.4 Album Artwork Stability, MediaRemoteCallbackBridge, MediaRemoteDictionary, MediaRemoteProviding, NowPlayingMediaProvider, Double, NSDictionary, NSImage

### Community 64 - "DefaultExpandedTab"
Cohesion: 0.20
Nodes (10): DefaultExpandedTab, activities, .displayName, gestures, .id, island, liveActivities, stats (+2 more)

### Community 65 - "AgentEventStore"
Cohesion: 0.15
Nodes (8): AgentEventStore, Bool, Date, AgentEventStoreTests, Int, TimeInterval, UInt64, UInt64

### Community 66 - ".makeProcessor"
Cohesion: 0.27
Nodes (5): AgentBridgeEnvelopeIntegrationTests, StaticString, UInt, Any, UInt64

### Community 67 - "AgentBridgeDiscoveryRecord"
Cohesion: 0.11
Nodes (23): Decodable, Int32, AgentBridgeDiscoveryRecord, AgentBridgeHealth, AgentBridgeIngestionResult, AgentBridgeLimits, AgentBridgeState, degraded (+15 more)

### Community 68 - "Data"
Cohesion: 0.08
Nodes (19): CryptoKit, OSStatus, Security, AgentBridgeCredentialError, invalidStoredSecret, keychain, randomGeneration, AgentBridgeCrypto (+11 more)

### Community 69 - "AppDelegate"
Cohesion: 0.08
Nodes (24): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSWindowDelegate, 2. Existing DynamicIsland invariants, Composition, state and settings (+16 more)

### Community 70 - "AgentEvent"
Cohesion: 0.07
Nodes (40): Comparable, AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, Date, Int (+32 more)

### Community 71 - "OverlayGeometrySignature"
Cohesion: 0.13
Nodes (11): Phase 11C.4 - WindowServer Space-Transition Counter-Translation, CustomStringConvertible, QuartzCore, ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicy, OverlayGeometrySignature (+3 more)

### Community 72 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 73 - "MediaRemoteCallbackState"
Cohesion: 0.23
Nodes (12): Completion, value, MediaRemoteCallbackState, .isPending, MediaRemoteDeadlineScheduler, MediaRemoteDeadlineToken, Bool, CheckedContinuation (+4 more)

### Community 74 - "AgentEventValidationError"
Cohesion: 0.09
Nodes (15): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+7 more)

### Community 75 - "completion"
Cohesion: 0.22
Nodes (6): completion, FileDropURLAccumulator, .urls, SendableItemProvider, NSItemProvider, TimeInterval

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.17
Nodes (7): Darwin, AgentBridgeDiscoveryPublisher, FileManager, URL, AgentBridgeDiscoveryTests, UInt16, URL

### Community 77 - "AgentCapability"
Cohesion: 0.10
Nodes (20): AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage, costUsage, explicitThinking, gitMetadata (+12 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.23
Nodes (8): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL, AirDropURLAccumulator, .urls, NSItemProvider, URL

### Community 80 - "ModuleViews.swift"
Cohesion: 0.15
Nodes (16): 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, AlbumArtworkView, .body, ClickableAlbumArtworkButton, .artwork, .body, .body (+8 more)

### Community 83 - "CollapsedPreviewKind"
Cohesion: 0.25
Nodes (8): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, CollapsedPreviewKind, battery, fileDrop, liveActivity, media, none, timer

### Community 84 - ".apply"
Cohesion: 0.13
Nodes (10): AgentEventReducer, SemanticResult, applied, rejected, Bool, Date, Value, AgentCapabilityEvidence (+2 more)

### Community 86 - "AgentEventType"
Cohesion: 0.05
Nodes (39): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+31 more)

### Community 87 - "AgentEventStoreLimits"
Cohesion: 0.09
Nodes (23): AgentEventApplication, applied, duplicate, ignoredAfterTerminal, ignoredWeakerEvidence, rejected, staleGeneration, AgentEventBatchApplication (+15 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.15
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, .displayedShortcuts, ShortcutEditorRow, .body, Binding (+2 more)

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 90 - "Int"
Cohesion: 0.17
Nodes (16): ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted, none, queued, staleTransitionDiscarded, transitionCompleted (+8 more)

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

### Community 97 - "SettingsSection"
Cohesion: 0.13
Nodes (15): SettingsSection, advanced, appearance, clipboard, gestures, .id, island, liveActivities (+7 more)

### Community 103 - ".progress"
Cohesion: 0.21
Nodes (7): Double, TimerProgressColorStage, high, low, mid, TimerProgressFormatting, TimerProgressFormattingTests

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentReplayHarness"
Cohesion: 0.14
Nodes (10): AgentReplayFixture, AgentReplayHarness, AgentReplayResult, .finalAttentionEvents, .finalSessions, AgentReplayStepResult, Int, AgentReplayHarnessTests (+2 more)

### Community 106 - "MediaRemoteTestLock"
Cohesion: 0.21
Nodes (8): ControlledMediaRemoteCallback, Entry, .count, .scheduler, MediaRemoteTestLock, Result, Value, Void

### Community 108 - "ShelfFileTile"
Cohesion: 0.21
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, NSImage (+1 more)

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.19
Nodes (7): NSSecureCoding, FileDropPolicy, FileShelfTemporaryStorage, Bool, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "DynamicIsland Project Context"
Cohesion: 0.17
Nodes (10): Collapsed, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context, Expanded, Known Fragile Areas, Non-Negotiable Behavior To Preserve (+2 more)

### Community 111 - "ServerFactorySpy"
Cohesion: 0.24
Nodes (8): AgentBridgeLifecycleTests, DiscoverySpy, .records, .removedLaunchIDs, ServerFactorySpy, .createdCount, AgentBridgeServerFactory, Error

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.11
Nodes (19): AgentBridgeEnvelopeError, emptyBatch, eventTooLarge, generationConflict, invalidAuthority, invalidCapability, invalidEventType, invalidPayload (+11 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.20
Nodes (10): DispatchQueue, NWConnection, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, Result (+2 more)

### Community 114 - "AgentBridge"
Cohesion: 0.18
Nodes (11): HTTPURLResponse, AgentBridge, Runtime, AgentBridgeServerFactory, Error, UUID, AgentBridgeDiscoveryPublishing, AgentBridgeCredentialStore (+3 more)

### Community 115 - ".testTimeoutRunsNewestPendingRefreshFallbackAndRejectsLateNativeResult"
Cohesion: 0.32
Nodes (4): ControlledMediaRemoteProvider, MediaRemoteRefreshRecoveryTests, SendableMediaRemoteDictionary, NSDictionary

### Community 116 - ".assertFailure"
Cohesion: 0.19
Nodes (3): AgentBridgeHTTPParserTests, StaticString, UInt

### Community 117 - "Error"
Cohesion: 0.18
Nodes (11): Error, AgentBridgeDiscoveryError, insecurePermissions, invalidRecord, unavailableDirectory, ControlledClipboardPersistenceError, requestedFailure, FileDropProviderTestError (+3 more)

### Community 118 - "AudioVisualizerView"
Cohesion: 0.29
Nodes (8): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerView, .body, .shouldAnimateContinuously, .visualizerOpacity, Double, Int, TimeInterval

### Community 119 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 120 - "AgentSourceHealthState"
Cohesion: 0.29
Nodes (7): AgentSourceHealthState, degraded, failed, healthy, stale, starting, stopped

### Community 121 - "AgentBridgeHTTPRequestParser"
Cohesion: 0.18
Nodes (10): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, .result (+2 more)

### Community 122 - "AgentEvidenceAuthority"
Cohesion: 0.12
Nodes (15): CoreFoundation, 3. Component boundaries, Adapter contract, State ownership, AgentBridgeIngress, AgentBridgeRequestProcessor, Bool, Date (+7 more)

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.17
Nodes (12): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 6. Privacy and security boundaries, 7. Attention presentation contract, 8. Expanded Agent Activity contract (+4 more)

### Community 124 - "DedicatedTimerPageView"
Cohesion: 0.09
Nodes (21): Path, .percentText, .visualizerAccentColor, DedicatedTimerPageView, .body, .controlsFontSize, .controlsSpacing, .titleFontSize (+13 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.12
Nodes (17): 3. Phase gates, A0 — Research and architecture, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2.1 — Ingestion coordination and source registry, A2.2 — Relay client and append-only ingestion primitives, A2 — Authenticated local Agent Bridge, A3.1 — Codex protocol and recovery enrichment (+9 more)

### Community 126 - "LiveActivityStore"
Cohesion: 0.31
Nodes (5): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int

### Community 127 - "Agent Capability Matrix"
Cohesion: 0.12
Nodes (16): 1. Method and version boundary, 2. Primary supported integration surfaces, 3. Capability matrix, 4. Event-specific authority, 5. Local storage audit (content redacted), 6. Source application association, 7. Design implications, 8. Official sources (+8 more)

### Community 128 - "Agent Event Schema Draft"
Cohesion: 0.18
Nodes (11): 2. State vocabulary, 4. Normalized event types, 5. Versioned transport envelope, 6. Capability model, 7. Privacy projection, 8. Replay fixture contract, 9. Deferred decisions, Agent Event Schema Draft (+3 more)

### Community 129 - ".constrainedActivePlayerLayout"
Cohesion: 0.31
Nodes (5): Double, MediaButton, .body, .constrainedActivePlayerView, .regularActivePlayerView

### Community 130 - "AgentActivityKind"
Cohesion: 0.18
Nodes (11): AgentActivityKind, approval, command, failure, interruption, plan, session, subagent (+3 more)

### Community 131 - ".signedRequest"
Cohesion: 0.34
Nodes (4): AgentBridgeHTTPRequest, AgentBridgeAuthenticationTests, AgentBridgeTestSupport, Int64

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "Fresh critical audit instructions"
Cohesion: 0.20
Nodes (8): Interpreter guard for subcommands, Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits, CGRect

### Community 134 - "MediaRemoteClient"
Cohesion: 0.28
Nodes (6): CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, MediaRemoteClient, .isAvailable, T, UnsafeMutableRawPointer

### Community 136 - "AgentBridgeHTTPStatus"
Cohesion: 0.12
Nodes (16): AgentBridgeHTTPResponse, .data, AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed (+8 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.40
Nodes (5): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, Agent Activity Feature Phase Plan

### Community 138 - "XCTestCase"
Cohesion: 0.33
Nodes (3): Self, ExpandedIslandRightStackVisibilityTests, XCTestCase

### Community 139 - "AppSettings.swift"
Cohesion: 0.25
Nodes (7): Key, VisualizerAccentMode, artwork, .displayName, .id, system, white

### Community 140 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 141 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

### Community 143 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 144 - "AudioVisualizerVariant"
Cohesion: 0.25
Nodes (8): AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing, CGSize

### Community 145 - "GestureInputSource"
Cohesion: 0.29
Nodes (7): GestureInputSource, camera, .displayName, .id, keyboardShortcut, none, trackpad

### Community 146 - "IslandThemeStyle"
Cohesion: 0.33
Nodes (6): 2026-07-11 - Phase 9D Theme Simplification, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass

### Community 147 - "TimerNotificationAuthorizationStatus"
Cohesion: 0.33
Nodes (4): TimerNotificationAuthorizationStatus, authorized, denied, notDetermined

### Community 148 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, LiveActivityStyle, compact, detailed, .id

### Community 149 - "3. Session identity"
Cohesion: 0.40
Nodes (5): 3. Session identity, Collisions, Generation rules, Logical key, Project identity

### Community 150 - "5. Local bridge decision"
Cohesion: 0.50
Nodes (4): 5. Local bridge decision, Alternatives, OTLP, Selected architecture

## Knowledge Gaps
- **877 isolated node(s):** `PackageDescription`, `package_app.sh script`, `CoreFoundation`, `unavailableDirectory`, `invalidRecord` (+872 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1118 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerController`, `SystemClipboardPasteboardClient`, `TimerCompletionNotificationCoordinator`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `.start`, `FileShelfStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `ObservableObject`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `AgentSourceRegistry`, `AgentBridgeAuthenticator`, `Equatable`, `MediaModuleView`, `Phase Workflow For Future Work`, `MediaCandidate`, `FileDropProviderLoader`, `YouTubeMetadataProvider`, `IslandStateStore`, `AppSettingsTests`, `View`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `IslandRootView.swift`, `Sendable`, `.reload`, `CompactIslandView`, `.event`, `.sessionID`, `AgentIngestionCoordinator`, `NowPlayingMediaProvider`, `DefaultExpandedTab`, `AgentEventStore`, `.makeProcessor`, `AgentBridgeDiscoveryRecord`, `Data`, `AppDelegate`, `AgentEvent`, `OverlayGeometrySignature`, `DynamicIslandLiveActivityKind`, `AgentEventValidationError`, `completion`, `AgentBridgeDiscoveryPublisher`, `AgentCapability`, `CollapsedPreviewKind`, `.apply`, `AgentEventType`, `ShortcutsStore`, `Int`, `ServerSpy`, `SettingsSection`, `RecordingFileShelfDefaults`, `AgentReplayHarness`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `ServerFactorySpy`, `AgentBridgeEnvelopeError`, `AgentBridge`, `.testTimeoutRunsNewestPendingRefreshFallbackAndRejectsLateNativeResult`, `AgentSourceHealthState`, `AgentBridgeHTTPRequestParser`, `AgentEvidenceAuthority`, `DedicatedTimerPageView`, `LiveActivityStore`, `.constrainedActivePlayerLayout`, `AgentActivityKind`, `.signedRequest`, `MediaRemoteClient`, `AgentBridgeHTTPStatus`, `AppSettings.swift`, `AnimationPreset`, `.collapsedPreviewContent`, `AutoCollapseDelayPreset`, `GestureInputSource`, `IslandThemeStyle`, `CaseIterable`?**
  _High betweenness centrality (0.425) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `AppSettings.swift`, `NotchGeometryService`, `AnimationPreset`, `.normalizeAndSaveDouble`, `AutoCollapseDelayPreset`, `IslandNavigationStore`, `GestureInputSource`, `FileShelfStore`, `IslandThemeStyle`, `CaseIterable`, `ExpandedIslandView`, `Change Log`, `ObservableObject`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaModuleView`, `FileDropProviderLoader`, `String`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `View`, `OverlayWindowController`, `.reload`, `CompactIslandView`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `DefaultExpandedTab`, `ClipboardHistoryStoreTests`, `AppDelegate`, `ModuleViews.swift`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `DedicatedTimerPageView`?**
  _High betweenness centrality (0.139) - this node is a cross-community bridge._
- **Why does `IslandRootView` connect `IslandRootView` to `AppSettings`, `IslandGestureAction`, `Fresh critical audit instructions`, `ClipboardHistoryPresentationState`, `IslandNavigationStore`, `ExpandedIslandView`, `Change Log`, `DynamicIsland`, `DynamicIslandLiveActivity`, `String`, `IslandStateStore`, `CGFloat`, `View`, `OverlayWindowController`, `IslandRootView.swift`, `IslandHostingView`, `AppDelegate`, `FileShelfTemporaryStorage`, `AudioVisualizerView`, `DedicatedTimerPageView`, `LiveActivityStore`?**
  _High betweenness centrality (0.047) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `CoreFoundation` to the rest of the system?**
  _877 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppSettings` be split into smaller, more focused modules?**
  _Cohesion score 0.024731182795698924 - nodes in this community are weakly interconnected._