# Graph Report - DynamicIsland  (2026-09-25)

## Corpus Check
- 125 files · ~164,485 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 3839 nodes · 10799 edges · 146 communities (133 shown, 13 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1422 edges (avg confidence: 0.86)
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
- IslandEscapeRouter
- ClipboardHistoryStore
- CountdownLifecycleEvent
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
- Phase Workflow For Future Work
- ExpandedIslandView
- Change Log
- ExpandedIslandLayoutMetrics
- XCTestCase
- DynamicIsland
- ObservableObject
- MediaAutomationExecutor
- Int
- CollapsedLiveActivityPrioritySettings
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- AgentSourceRegistry
- AgentBridgeAuthenticator
- Foundation
- Equatable
- MediaModuleView
- MediaSnapshot
- LiveActivitySettingsSnapshot
- FileDropProviderLoaderTests
- What You Must Do When Invoked
- String
- MediaController
- .refresh
- IslandStateStore
- AppSettingsTests
- CGFloat
- View
- OverlayWindowController
- CollapsedLiveActivityPrioritySource
- InnerBlurScaleCleanModifier
- Sendable
- .reload
- .resolve
- ManualMediaRemoteDeadlineScheduler
- ClipboardImageCaptureLifecycleTests
- OverlayPresentationSessionTests
- .event
- .sessionID
- AgentIngestionCoordinator
- IslandSurfaceBackground
- IslandHostingView
- NowPlayingMediaProvider
- CaseIterable
- AgentEventStore
- .makeProcessor
- AgentBridgeModels.swift
- Data
- AppDelegate
- AgentProducerHandle
- IslandOverlayPanel
- DynamicIslandLiveActivity
- NowPlayingMediaProvider.swift
- ClipboardHistoryPersistenceFinalizationResult
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
- TimerController
- AgentEventType
- AgentEventValidationError
- AgentIngestionError
- graphify reference: extra exports and benchmark
- MediaController.swift
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- ServerSpy
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- AgentBridgeDiscoveryRecord
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- AgentAuthorityDomain
- RecordingFileShelfDefaults
- AgentEvent
- CollapsedIslandContentMode
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- BatteryActivityProvider
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- AgentBridge
- AgentSourceHealthError
- .assertFailure
- Error
- SwiftUI
- FileClipboardHistoryPersistence
- AgentSourceHealthState
- AgentBridgeHTTPRequestParser
- AgentBridgeIngress
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
- IslandContentPhase
- AgentBridgeAuthenticationError
- .decode
- LockedValue
- Array
- SystemStatsController.swift

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 331 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 105 edges
5. `IslandRootView` - 75 edges
6. `ExpandedIslandView` - 67 edges
7. `AgentEvent` - 64 edges
8. `AgentEventStore` - 64 edges
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
- `2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish` --references--> `OverlayWindowController`  [INFERRED]
  context.md → Sources/DynamicIsland/Overlay/OverlayWindowController.swift

## Import Cycles
- None detected.

## Communities (146 total, 13 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (155): AnyPublisher, Never, AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray (+147 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.08
Nodes (38): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, .now, IslandGestureAction, collapse, .displayName, expand, .id (+30 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.06
Nodes (26): 2026-07-04 - Phase 5D Stats Tab, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double, Int (+18 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.19
Nodes (8): ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationState, .queuedSnapshot, ArtworkFlipPresentationStateTests, Bool

### Community 4 - "SettingsView"
Cohesion: 0.05
Nodes (57): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+49 more)

### Community 5 - "IslandRootView"
Cohesion: 0.05
Nodes (53): Animation, 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5J Single Visual Surface Morph, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 11C.9 - Predictive Space Motion Resampling (+45 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.11
Nodes (19): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date (+11 more)

### Community 8 - "CountdownLifecycleEvent"
Cohesion: 0.10
Nodes (17): ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Double, Duration (+9 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.09
Nodes (21): NSPasteboard, NSPasteboardItem, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image (+13 more)

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.11
Nodes (17): Bool, Duration, Never, Task, TimeInterval, UInt64, Void, SystemTimerNotificationCenterClient (+9 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.07
Nodes (25): Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint (+17 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.12
Nodes (19): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth (+11 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.13
Nodes (14): ClipboardHistoryArchive, ClipboardHistoryStoreTests, ControlledClipboardPersistence, .data, .deleteCount, .saveCount, FakeClipboardPasteboardClient, MemoryClipboardPersistence (+6 more)

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (19): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+11 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.13
Nodes (14): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, island, stats, .symbolName, timer (+6 more)

### Community 17 - ".start"
Cohesion: 0.20
Nodes (8): TimerNotificationAuthorizationStatus, authorized, denied, notDetermined, MockTimerNotificationCenterClient, Bool, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, FileShelfStore, AnyCancellable, Set, URL (+8 more)

### Community 19 - "Phase Workflow For Future Work"
Cohesion: 0.06
Nodes (36): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment (+28 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.16
Nodes (9): ExpandedIslandView, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation, .tabAnimationsEnabled, .tabFadeInAnimation, .tabFadeOutAnimation, IslandContentTransitionTiming (+1 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (57): 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+49 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "XCTestCase"
Cohesion: 0.07
Nodes (21): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+13 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ObservableObject"
Cohesion: 0.11
Nodes (15): Calendar, ObservableObject, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body, .emptyState, .header, ClipboardThumbnailCache (+7 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (44): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+36 more)

### Community 27 - "Int"
Cohesion: 0.11
Nodes (13): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer (+5 more)

### Community 28 - "CollapsedLiveActivityPrioritySettings"
Cohesion: 0.23
Nodes (9): Candidate, CollapsedLiveActivityPrioritySettings, .defaults, CollapsedLiveActivitySelector, CollapsedLiveActivitySourceToggles, Bool, Int, .collapsedContentMode (+1 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.10
Nodes (10): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int (+2 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.17
Nodes (5): Decision, Date, MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (13): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, BatteryLiveActivityState (+5 more)

### Community 33 - "AgentSourceRegistry"
Cohesion: 0.11
Nodes (24): AgentProducerDescriptor, AgentProducerPolicy, AgentSourceHealthSnapshot, AgentSourceInstanceID, AgentSourceKind, authenticatedBridge, heuristicFallback, officialHook (+16 more)

### Community 34 - "AgentBridgeAuthenticator"
Cohesion: 0.27
Nodes (7): AgentBridgeRequestProcessor, AgentBridgeAuthenticator, .rememberedNonceCount, NonceEntry, Bool, Date, Set

### Community 35 - "Foundation"
Cohesion: 0.07
Nodes (9): AppKit, Combine, DynamicIsland, Foundation, Array, .single, Element, UniformTypeIdentifiers (+1 more)

### Community 36 - "Equatable"
Cohesion: 0.14
Nodes (35): Codable, Equatable, AgentBridgeWirePayload, .populatedFieldCount, AgentActivityDescriptor, AgentApprovalRequest, AgentApprovalResolution, AgentCommandEvent (+27 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.04
Nodes (59): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, Double, AlbumArtworkView, .body (+51 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.11
Nodes (16): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Phase 2.7 Media Source Arbitration, MediaSnapshot, MediaSourceKind, browser, music, spotify, system (+8 more)

### Community 39 - "LiveActivitySettingsSnapshot"
Cohesion: 0.26
Nodes (6): 2. Existing DynamicIsland invariants, .liveActivitySettingsPublisher, LiveActivitySettingsSnapshot, Bool, Int, URL

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.18
Nodes (9): .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, URL, UserDefaults (+1 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.06
Nodes (32): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+24 more)

### Community 42 - "String"
Cohesion: 0.10
Nodes (22): CodingKey, CodingKeys, files, imagePNG, text, type, url, MediaPlayer (+14 more)

### Community 43 - "MediaController"
Cohesion: 0.10
Nodes (14): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, BrowserScriptTarget, MediaArbitrator, MediaCandidate, .sourceKey, MediaController, .currentArtworkPresentationIdentity, MediaImmediateSystemHandoff (+6 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.08
Nodes (24): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, App Entry, Collapsed, Current Architecture, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context (+16 more)

### Community 47 - "CGFloat"
Cohesion: 0.20
Nodes (11): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, IslandShellLayout, IslandShellRadii, IslandShellShape, .animatableData (+3 more)

### Community 48 - "View"
Cohesion: 0.06
Nodes (61): 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix, Phase 12C.3 - Hardware Notch Center Exclusion, EnvironmentKey, Left, Right, AirDropDropZoneView, .body (+53 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.09
Nodes (21): CFTimeInterval, DispatchWorkItem, NSPoint, NSRect, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedGestureCandidateScreenRegion, .collapsedInteractiveSurfaceFrame (+13 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "InnerBlurScaleCleanModifier"
Cohesion: 0.10
Nodes (23): 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, Phase 12A - Final Island Content Transition Sequencing, Phase 13B.2 - Native In-Island Clipboard Interface, Gesture, AnyTransition, .blurBounce, .compactMediaContent (+15 more)

### Community 52 - "Sendable"
Cohesion: 0.05
Nodes (87): Comparable, Hashable, Identifiable, Int, RawRepresentable, 1. Domain contracts, 7. Attention presentation contract, Sendable (+79 more)

### Community 53 - ".reload"
Cohesion: 0.35
Nodes (3): Bool, T, UserDefaults

### Community 55 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.13
Nodes (16): ControlledMediaRemoteCallback, ControlledMediaRemoteProvider, Entry, ManualMediaRemoteDeadlineScheduler, .count, .scheduler, MediaRemoteCallbackBridgeTests, MediaRemoteRefreshRecoveryTests (+8 more)

### Community 56 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.19
Nodes (8): ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, CheckedContinuation, MainActor, Never, Sendable, XCTestExpectation

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".event"
Cohesion: 0.25
Nodes (9): Success, AgentIngestionCoordinatorTests, Result, Set, StaticString, UInt, UInt64, XCTAssertFailure() (+1 more)

### Community 59 - ".sessionID"
Cohesion: 0.17
Nodes (10): AgentReductionResult, AgentSessionID, AgentEventReducerTests, Set, TimeInterval, AgentTestFixture, Date, Int (+2 more)

### Community 60 - "AgentIngestionCoordinator"
Cohesion: 0.17
Nodes (12): 3. Component boundaries, Adapter contract, State ownership, AgentIngestionCoordinator, Bool, CheckedContinuation, Date, Never (+4 more)

### Community 61 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 62 - "IslandHostingView"
Cohesion: 0.13
Nodes (13): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, Known Fragile Areas, NSHostingView, NSSize (+5 more)

### Community 63 - "NowPlayingMediaProvider"
Cohesion: 0.12
Nodes (14): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, MediaRemoteClient, .isAvailable, MediaRemoteDictionary, MediaRemoteProviding, NowPlayingMediaProvider (+6 more)

### Community 64 - "CaseIterable"
Cohesion: 0.04
Nodes (51): CaseIterable, 2026-07-11 - Phase 9D Theme Simplification, AnimationPreset, .displayName, .id, instant, normal, .shellDuration (+43 more)

### Community 65 - "AgentEventStore"
Cohesion: 0.13
Nodes (11): AgentEventStore, .activeSessions, .sessionsRequiringAttention, Bool, Date, AgentSessionInstanceID, AgentEventStoreTests, Int (+3 more)

### Community 66 - ".makeProcessor"
Cohesion: 0.27
Nodes (5): AgentBridgeEnvelopeIntegrationTests, StaticString, UInt, Any, UInt64

### Community 67 - "AgentBridgeModels.swift"
Cohesion: 0.13
Nodes (20): Decodable, AgentBridgeHealth, AgentBridgeIngestionResult, AgentBridgeLimits, AgentBridgeState, degraded, failed, running (+12 more)

### Community 68 - "Data"
Cohesion: 0.13
Nodes (9): AgentBridgeHTTPResponse, .data, randomGeneration, AgentBridgeCrypto, Data, Int, Int64, Int (+1 more)

### Community 69 - "AppDelegate"
Cohesion: 0.12
Nodes (14): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSObject, NSWindowDelegate, AppDelegate, Any (+6 more)

### Community 70 - "AgentProducerHandle"
Cohesion: 0.18
Nodes (12): AgentIdentityConflict, AgentIngestionEvent, .sessionID, AgentIngestionLimits, AgentIngestionResult, AgentProducerHandle, AgentSessionContinuity, AgentSessionLease (+4 more)

### Community 71 - "IslandOverlayPanel"
Cohesion: 0.09
Nodes (18): Phase 11C.3 - Diagnostic WindowServer Transition Trace, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, CustomStringConvertible, NSPanel, NSView, QuartzCore, Native overlay, geometry and input, ExpandedScrollEventRoute (+10 more)

### Community 72 - "DynamicIslandLiveActivity"
Cohesion: 0.19
Nodes (11): DynamicIslandLiveActivity, DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer, Date (+3 more)

### Community 73 - "NowPlayingMediaProvider.swift"
Cohesion: 0.23
Nodes (12): Completion, value, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending, MediaRemoteDeadlineScheduler, MediaRemoteDeadlineToken, Bool (+4 more)

### Community 74 - "ClipboardHistoryPersistenceFinalizationResult"
Cohesion: 0.23
Nodes (9): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+1 more)

### Community 75 - "FileDropProviderLoader"
Cohesion: 0.22
Nodes (8): NSSecureCoding, completion, FileDropProviderLoader, SendableItemProvider, NSItemProvider, TimeInterval, UTType, NSItemProvider

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.19
Nodes (6): AgentBridgeDiscoveryPublisher, FileManager, URL, AgentBridgeDiscoveryTests, UInt16, URL

### Community 77 - "AgentCapability"
Cohesion: 0.08
Nodes (23): AgentCapabilities, .all, AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage, costUsage (+15 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.53
Nodes (3): AirDropURLAccumulator, .urls, URL

### Community 80 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 83 - "IslandLayoutStore"
Cohesion: 0.13
Nodes (17): 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, IslandLayoutStore, Bool, CGFloat (+9 more)

### Community 84 - "AgentUsage"
Cohesion: 0.07
Nodes (24): AgentUsage, AgentUsageMetric, cachedInputTokens, contextLimit, contextUsed, cost, inputTokens, outputTokens (+16 more)

### Community 85 - "TimerController"
Cohesion: 0.18
Nodes (11): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, Never, Task, UInt64, Void, TimerController, .displayText, .timerControlRow (+3 more)

### Community 86 - "AgentEventType"
Cohesion: 0.05
Nodes (38): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+30 more)

### Community 87 - "AgentEventValidationError"
Cohesion: 0.06
Nodes (35): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+27 more)

### Community 88 - "AgentIngestionError"
Cohesion: 0.15
Nodes (13): AgentIngestionError, capabilityCapacity, generationConflict, identityConflict, invalidDescriptor, invalidEvent, invalidProducer, leaseCapacity (+5 more)

### Community 89 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 90 - "MediaController.swift"
Cohesion: 0.08
Nodes (31): 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, Index, Media and artwork, Array, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted (+23 more)

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

### Community 97 - "AgentBridgeDiscoveryRecord"
Cohesion: 0.24
Nodes (6): HTTPURLResponse, Int32, AgentBridgeDiscoveryRecord, Date, AgentBridgeNetworkTests, URL

### Community 103 - "AgentAuthorityDomain"
Cohesion: 0.18
Nodes (10): AgentAuthorityDomain, activity, capability, interaction, lifecycle, liveness, metadata, operation (+2 more)

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentEvent"
Cohesion: 0.08
Nodes (22): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, AgentEventOrigin, live, replay (+14 more)

### Community 106 - "CollapsedIslandContentMode"
Cohesion: 0.18
Nodes (7): CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, LiveActivityTimeFormatting

### Community 108 - "ShelfFileTile"
Cohesion: 0.23
Nodes (8): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, URL

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.18
Nodes (8): FileDropPolicy, FileDropURLAccumulator, .urls, FileShelfTemporaryStorage, Bool, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "BatteryActivityProvider"
Cohesion: 0.39
Nodes (4): Phase 11A - Battery Live Activity, BatteryActivityProvider, Any, .description

### Community 111 - "ServerFactorySpy"
Cohesion: 0.21
Nodes (9): AgentBridgeLifecycleTests, DiscoverySpy, .records, .removedLaunchIDs, ServerFactorySpy, .createdCount, AgentBridgeServerFactory, Error (+1 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.11
Nodes (19): AgentBridgeEnvelopeError, emptyBatch, eventTooLarge, generationConflict, invalidAuthority, invalidCapability, invalidEventType, invalidPayload (+11 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.20
Nodes (10): DispatchQueue, NWConnection, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, Result (+2 more)

### Community 114 - "AgentBridge"
Cohesion: 0.30
Nodes (7): AgentBridge, Runtime, AgentBridgeServerFactory, Error, UUID, AgentBridgeDiscoveryPublishing, AgentBridgeCredentialStore

### Community 115 - "AgentSourceHealthError"
Cohesion: 0.25
Nodes (8): AgentSourceHealthError, identityConflict, invalidEvent, policyRejected, producerFailure, schemaMismatch, staleProducer, storeRejected

### Community 116 - ".assertFailure"
Cohesion: 0.19
Nodes (3): AgentBridgeHTTPParserTests, StaticString, UInt

### Community 117 - "Error"
Cohesion: 0.18
Nodes (11): Error, AgentBridgeDiscoveryError, insecurePermissions, invalidRecord, unavailableDirectory, ControlledClipboardPersistenceError, requestedFailure, FileDropProviderTestError (+3 more)

### Community 118 - "SwiftUI"
Cohesion: 0.14
Nodes (9): Activities and utility modules, Build and tests, Clipboard engine and persistence, Composition, state and settings, Current architecture baseline, Evidence and graph limits, DynamicIslandApp, IslandModule (+1 more)

### Community 119 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 120 - "AgentSourceHealthState"
Cohesion: 0.29
Nodes (7): AgentSourceHealthState, degraded, failed, healthy, stale, starting, stopped

### Community 121 - "AgentBridgeHTTPRequestParser"
Cohesion: 0.18
Nodes (10): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, .result (+2 more)

### Community 122 - "AgentBridgeIngress"
Cohesion: 0.24
Nodes (4): AgentBridgeIngress, Bool, Date, Result

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.13
Nodes (15): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 5. Local bridge decision, 6. Privacy and security boundaries, 8. Expanded Agent Activity contract (+7 more)

### Community 124 - "DedicatedTimerPageView"
Cohesion: 0.14
Nodes (18): .visualizerAccentColor, DedicatedTimerPageView, .body, .controlsFontSize, .controlsSpacing, .titleFontSize, .usesCompactLayout, StatsLineChart (+10 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.11
Nodes (18): 3. Phase gates, A0 — Research and architecture, A10 — Source app/editor association and Open action, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2.1 — Ingestion coordination and source registry, A2.2 — Relay client and append-only ingestion primitives, A2 — Authenticated local Agent Bridge (+10 more)

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
Cohesion: 0.34
Nodes (4): AgentBridgeHTTPRequest, AgentBridgeAuthenticationTests, AgentBridgeTestSupport, Int64

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "AgentState"
Cohesion: 0.14
Nodes (14): AgentState, completed, failed, idle, interrupted, .isTerminal, planning, planReady (+6 more)

### Community 134 - ".share"
Cohesion: 0.40
Nodes (4): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL

### Community 136 - "AgentBridgeHTTPStatus"
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.40
Nodes (5): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, Agent Activity Feature Phase Plan

### Community 138 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 139 - "IslandContentPhase"
Cohesion: 0.33
Nodes (6): IslandContentPhase, compact, contentCollapsing, expandedContentVisible, shellCollapsing, shellExpanding

### Community 140 - "AgentBridgeAuthenticationError"
Cohesion: 0.11
Nodes (16): CryptoKit, OSStatus, Security, AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders (+8 more)

### Community 141 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

### Community 143 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 144 - "Array"
Cohesion: 0.67
Nodes (3): Array, .single, Element

### Community 145 - "SystemStatsController.swift"
Cohesion: 0.25
Nodes (3): CoreFoundation, Darwin, IOKit.ps

## Knowledge Gaps
- **877 isolated node(s):** `PackageDescription`, `package_app.sh script`, `CoreFoundation`, `unavailableDirectory`, `invalidRecord` (+872 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1118 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `SystemStatsController`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `ClipboardHistoryStore`, `TimerCompletionNotificationCoordinator`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `.start`, `FileShelfStore`, `Phase Workflow For Future Work`, `Change Log`, `XCTestCase`, `ObservableObject`, `MediaAutomationExecutor`, `Int`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `AgentSourceRegistry`, `AgentBridgeAuthenticator`, `Equatable`, `MediaModuleView`, `MediaSnapshot`, `LiveActivitySettingsSnapshot`, `FileDropProviderLoaderTests`, `MediaController`, `IslandStateStore`, `AppSettingsTests`, `View`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `Sendable`, `.reload`, `.resolve`, `ManualMediaRemoteDeadlineScheduler`, `.event`, `.sessionID`, `AgentIngestionCoordinator`, `NowPlayingMediaProvider`, `CaseIterable`, `AgentEventStore`, `.makeProcessor`, `AgentBridgeModels.swift`, `Data`, `AgentProducerHandle`, `IslandOverlayPanel`, `DynamicIslandLiveActivity`, `FileDropProviderLoader`, `AgentBridgeDiscoveryPublisher`, `AgentCapability`, `IslandLayoutStore`, `AgentUsage`, `TimerController`, `AgentEventType`, `AgentEventValidationError`, `MediaController.swift`, `ServerSpy`, `AgentBridgeDiscoveryRecord`, `AgentAuthorityDomain`, `RecordingFileShelfDefaults`, `AgentEvent`, `CollapsedIslandContentMode`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `BatteryActivityProvider`, `ServerFactorySpy`, `AgentBridgeEnvelopeError`, `AgentBridge`, `AgentSourceHealthError`, `AgentSourceHealthState`, `AgentBridgeHTTPRequestParser`, `AgentBridgeIngress`, `DedicatedTimerPageView`, `LiveActivityStore`, `AgentActivityKind`, `.signedRequest`, `AgentState`, `AgentBridgeHTTPStatus`, `.collapsedPreviewContent`?**
  _High betweenness centrality (0.437) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `SystemStatsController`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `IslandNavigationStore`, `FileShelfStore`, `ExpandedIslandView`, `Change Log`, `ObservableObject`, `Int`, `CollapsedLiveActivityPrioritySettings`, `.init`, `MediaModuleView`, `LiveActivitySettingsSnapshot`, `FileDropProviderLoaderTests`, `String`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `View`, `OverlayWindowController`, `InnerBlurScaleCleanModifier`, `.reload`, `ClipboardImageCaptureLifecycleTests`, `OverlayPresentationSessionTests`, `CaseIterable`, `AppDelegate`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `SwiftUI`, `DedicatedTimerPageView`?**
  _High betweenness centrality (0.137) - this node is a cross-community bridge._
- **Why does `IslandRootView` connect `IslandRootView` to `AppSettings`, `IslandGestureAction`, `IslandEscapeRouter`, `IslandContentPhase`, `IslandNavigationStore`, `ExpandedIslandView`, `Change Log`, `DynamicIsland`, `CollapsedLiveActivityPrioritySettings`, `MediaModuleView`, `LiveActivitySettingsSnapshot`, `What You Must Do When Invoked`, `MediaController`, `IslandStateStore`, `CGFloat`, `View`, `OverlayWindowController`, `IslandHostingView`, `AppDelegate`, `DynamicIslandLiveActivity`, `FileDropProviderLoader`, `IslandLayoutStore`, `MediaController.swift`, `CollapsedIslandContentMode`, `FileShelfTemporaryStorage`, `LiveActivityStore`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `CoreFoundation` to the rest of the system?**
  _877 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppSettings` be split into smaller, more focused modules?**
  _Cohesion score 0.024731182795698924 - nodes in this community are weakly interconnected._