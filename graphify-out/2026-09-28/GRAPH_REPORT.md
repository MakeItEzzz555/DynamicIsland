# Graph Report - DynamicIsland  (2026-09-28)

## Corpus Check
- 187 files · ~513,942 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 6004 nodes · 18043 edges · 203 communities (189 shown, 14 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 2552 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9cd68ac5`
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
- AgentIntegrationRouter
- Change Log
- ExpandedIslandLayoutMetrics
- ArtworkAccentColorCache
- DynamicIsland
- ClipboardHistoryView
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- OverlayWindowController
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- AgentProducerHandle
- AgentBridgeAuthenticator
- XCTest
- AppendOnlyRecordTailer
- MediaModuleView
- Phase Workflow For Future Work
- .init
- FileDropProviderLoaderTests
- What You Must Do When Invoked
- AgentSourceInstanceID
- String
- .refresh
- IslandStateStore
- AppSettingsTests
- CGFloat
- AgentIntegrationSetupService
- View
- AgentEventPayload
- CompactIslandView
- Sendable
- .reload
- String
- RecordSink
- ClipboardPasteboardReadResult
- OverlayPresentationSessionTests
- .event
- .event
- AgentActivityViews.swift
- AgentBridgeClient
- AgentPromptEditor
- ManualMediaRemoteDeadlineScheduler
- CaseIterable
- .sessionID
- .makeProcessor
- AgentBridgeClientProfile
- AgentUISnapshotTests
- AppDelegate
- AgentIntegrationSetupTests
- ExpandedScrollEventRoutingPolicyTests
- AgentIntegrationProvider
- AppendOnlyRecordTailer.swift
- DelimitedRecordFramer
- FileDropProviderLoader
- AgentBridgeDiscoveryPublisher
- AgentEvent
- Meaningful regression history
- .loadFileURLs
- AgentAttentionCoordinator
- Package.swift
- package_app.sh
- SequenceClientTransport
- .apply
- AgentBridgeDiscoveryReader
- AgentEventType
- AgentBridgeWirePayload
- ShortcutsStore
- AgentRelayCommandTests
- .readBoundedCatchUp
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- AgentSessionLauncherView
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
- .ingest
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- AgentPresentationTests
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- CodexAppServerClientTests
- ClaudeInteractiveProvider
- .assertFailure
- Foundation
- ClipboardHistoryPresentationState
- AgentUsage
- .parse
- .openActiveMediaSource
- AgentBridge
- Agent Activity Integration Architecture
- AgentEventApplication
- 3. Phase gates
- ClaudeCodeStreamingClient
- Agent Capability Matrix
- Agent Event Schema Draft
- IslandHostingView
- AgentBridgeNetworkExchange
- .signedRequest
- MenuBarController
- AgentBridgeDiscoveryReadError
- Data
- IslandOverlayPanel
- YouTubeMetadataProvider
- Agent Activity Feature Phase Plan
- IslandLayoutStore
- AgentBridgeEnvelopeBuildError
- AppKit
- AgentSession
- AgentRelayExitCode
- AudioVisualizerView
- CodexAppServerProvider
- AgentApprovalPolicyMode
- .normalize
- AgentEventValidationError
- AgentAuthorityDomain
- LaunchAtLoginController.swift
- LockedValue
- AgentNotch Reference Review
- .normalize
- AgentApprovalController
- UInt64
- CodexJSONValue
- ClaudeCodeStreamEnvelope
- MediaController.swift
- AgentManagedSessionController
- AgentActivityKind
- String
- AgentInteractiveProviderEvent
- Claude Managed Control Review — 2026-09-27
- AgentEventStore
- AgentIntegrationOperationalState
- AgentSourceRegistryTests.swift
- Run
- CodexAppServerError
- XCTestCase
- AgentState
- ExpandedContentScrollSequencePhase
- CodexAppServerClient
- AppLaunchService
- Agent Workspace Execution Plan — 2026-09-27
- .testPerSessionModelOverridesPersistAndRevalidateIndependently
- ClipboardHistoryPersistenceFinalizationResult
- AgentPresentationPriority
- AgentBridgeHTTPStatus
- CollapsedLiveActivityPrioritySource
- Identifiable
- AgentIngestionError
- AnimationPreset
- AgentEmbeddedConsoleView
- AgentConsoleViews.swift
- IslandRootView.swift
- AutoCollapseDelayPreset
- ClaudeTranscriptRecoveryAdapter
- AgentIntegrationSetupState
- DedicatedTimerPageView
- ClaudeCodeStreamingError
- Claude Managed Control Review — 2026-09-28
- Codex Managed Model Control Review — 2026-09-28
- DynamicIslandLiveActivityKind
- AgentBridgeAuthenticationError
- AgentBridgeState
- ObservableObject
- Error
- CodexListedThread
- .routine
- SystemAgentNotificationFeedback
- summary.md
- .events
- .decode

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 342 edges
2. `AgentSession` - 175 edges
3. `OverlayWindowController` - 147 edges
4. `AgentManagedSessionController` - 142 edges
5. `AgentEventStore` - 126 edges
6. `AgentIngestionCoordinator` - 112 edges
7. `Change Log` - 110 edges
8. `MediaController` - 105 edges
9. `AgentProvider` - 93 edges
10. `AgentApprovalController` - 91 edges

## Surprising Connections (you probably didn't know these)
- `A1 — Normalized domain, `AgentEventStore`, replay harness` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `2. Transport and API` --references--> `AgentIngestionCoordinator`  [INFERRED]
  research/CLAUDE_MANAGED_CONTROL_REVIEW_2026-09-27.md → Sources/DynamicIsland/Agents/AgentIngestionCoordinator.swift
- `10. Phase 6 recommendation` --references--> `ClaudeInteractiveProvider`  [INFERRED]
  research/CLAUDE_MANAGED_CONTROL_REVIEW_2026-09-27.md → Sources/DynamicIsland/Agents/ClaudeInteractiveProvider.swift
- `A4.1 Claude recovery authority` --references--> `ClaudeTranscriptRecoveryAdapter`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/Agents/ClaudeTranscriptRecovery.swift
- `A10 — Source app/editor association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift

## Import Cycles
- None detected.

## Communities (203 total, 14 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (162): AnyPublisher, Never, AppSettings, .activitiesEnabled, .agentActivityEnabled, .agentApprovalAlertsEnabled, .agentCompletionAlertsEnabled, .agentPeekDurationSeconds (+154 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (39): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, IslandGestureAction, collapse, .displayName, expand, .id (+31 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.07
Nodes (23): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+15 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.20
Nodes (7): ArtworkFlipPresentationState, .queuedSnapshot, ArtworkPresentationSnapshot, QueuedTransition, ArtworkFlipPresentationStateTests, Bool, String

### Community 4 - "SettingsView"
Cohesion: 0.14
Nodes (31): Owner, content, island, HelpText, .body, PriorityStepperRow, .body, SettingsGroup (+23 more)

### Community 5 - "IslandRootView"
Cohesion: 0.04
Nodes (51): Animation, 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, CollapsedPreviewRowContent, EnvironmentValues, .isCollapseShellOnly, .isNotchIntegratedShell (+43 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.12
Nodes (18): ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date, Int (+10 more)

### Community 8 - "TimerController"
Cohesion: 0.11
Nodes (19): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration (+11 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.09
Nodes (22): AnyObject, NSObject, Bool, Duration, Never, String, Task, TimeInterval (+14 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.06
Nodes (32): ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint, ClipboardHistoryPayload, .byteCount (+24 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.08
Nodes (28): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry (+20 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.17
Nodes (8): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Date, String, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.09
Nodes (16): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedWidth, .contentStaggerAmount, .expandedHeight (+8 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.13
Nodes (5): CollapsedLiveActivitySelectorTests, Bool, Date, Int, String

### Community 16 - "IslandNavigationStore"
Cohesion: 0.11
Nodes (16): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, agents, island, stats, .symbolName (+8 more)

### Community 17 - ".start"
Cohesion: 0.23
Nodes (6): TimerCompletionNotificationPreferences, MockTimerNotificationCenterClient, Bool, String, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (14): 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge, .body (+6 more)

### Community 19 - "SupportedApp"
Cohesion: 0.14
Nodes (14): SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName, edge, .fallbackPaths (+6 more)

### Community 20 - "AgentIntegrationRouter"
Cohesion: 0.08
Nodes (32): AgentIngestionResult, AgentIntegrationPrecedence, mcpFallback, providerNative, secondaryObservation, AgentIntegrationRouter, AgentMCPObservation, AgentMCPObservationError (+24 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (61): 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish (+53 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.05
Nodes (39): Phase 12C.1 - Integrated Notch Content Safe Areas, Phase 13B.2 - Native In-Island Clipboard Interface, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, ExpandedIslandLayoutMetrics, .compactScale (+31 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (17): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+9 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (36): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+28 more)

### Community 25 - "ClipboardHistoryView"
Cohesion: 0.12
Nodes (15): Calendar, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body, .emptyState, .header, ClipboardThumbnailCache, Bool (+7 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (49): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+41 more)

### Community 27 - "Int"
Cohesion: 0.09
Nodes (16): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer (+8 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.12
Nodes (19): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+11 more)

### Community 29 - "OverlayWindowController"
Cohesion: 0.08
Nodes (24): CFTimeInterval, 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, DispatchWorkItem, NSPoint, IslandModules, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedGestureCandidateScreenRegion (+16 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.07
Nodes (19): CFDictionary, CGImageSource, ImageIO, ClipboardImageCapture, ClipboardImageNormalizer, ClipboardImageRepresentation, encoded, oversized (+11 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (4): MediaArbitratorTests, Bool, NSImage, String

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.14
Nodes (14): BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Bool, Date, Int, String (+6 more)

### Community 33 - "AgentProducerHandle"
Cohesion: 0.05
Nodes (48): Result, AgentEventProvenance, AgentIngestionLimits, AgentProducerDescriptor, AgentProducerEpoch, AgentProducerHandle, AgentProducerPolicy, AgentSessionLease (+40 more)

### Community 34 - "AgentBridgeAuthenticator"
Cohesion: 0.12
Nodes (15): OSStatus, AgentBridgeAuthenticator, .rememberedNonceCount, AgentBridgeCredentialError, invalidStoredSecret, keychain, randomGeneration, AgentBridgeCrypto (+7 more)

### Community 35 - "XCTest"
Cohesion: 0.11
Nodes (3): Combine, DynamicIsland, XCTest

### Community 36 - "AppendOnlyRecordTailer"
Cohesion: 0.11
Nodes (14): DispatchSourceFileSystemObject, NoticeHandler, RecordHandler, 6. Privacy and security boundaries, A2.1 ingress boundary and A2.2 handoff, AppendOnlyFileIdentity, AppendOnlyRecordTailer, AppendOnlyRecordTailerHealth (+6 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.08
Nodes (24): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, Double, MediaModuleView, .activePlayerView, .artistFontSize, .artworkSize, .constrainedActivePlayerView (+16 more)

### Community 38 - "Phase Workflow For Future Work"
Cohesion: 0.07
Nodes (30): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration (+22 more)

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.18
Nodes (10): .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, String, URL (+2 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.06
Nodes (32): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+24 more)

### Community 42 - "AgentSourceInstanceID"
Cohesion: 0.08
Nodes (30): AgentSourceInstanceID, AgentMCPAdapterLimits, AgentMCPAdapterRefreshResult, AgentMCPObservationAdapter, AgentMCPObservationDecoder, AgentMCPSourceConnecting, AgentMCPSourceConnection, AgentMCPSourceDescriptor (+22 more)

### Community 43 - "String"
Cohesion: 0.09
Nodes (20): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, BrowserScriptTarget, Decision, MediaArbitrator, MediaCandidate, .sourceKey, MediaController, .currentArtworkPresentationIdentity (+12 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.07
Nodes (28): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, App Entry, Collapsed, Current Architecture, Current Stable Baseline (+20 more)

### Community 46 - "AppSettingsTests"
Cohesion: 0.12
Nodes (3): AppSettingsTests, String, UserDefaults

### Community 47 - "CGFloat"
Cohesion: 0.06
Nodes (36): AnimatablePair, 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, LinearGradient, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline (+28 more)

### Community 48 - "AgentIntegrationSetupService"
Cohesion: 0.16
Nodes (11): AgentIntegrationBackupEnvelope, AgentIntegrationSetupPaths, AgentIntegrationSetupService, .fileManager, AgentIntegrationSetupSnapshot, Bool, FileManager, Int (+3 more)

### Community 49 - "View"
Cohesion: 0.09
Nodes (26): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, 2026-07-05 - Phase 8A File Shelf Tray Polish, Phase 12A - Final Island Content Transition Sequencing, AirDropService, Bool (+18 more)

### Community 50 - "AgentEventPayload"
Cohesion: 0.10
Nodes (32): AgentApprovalRequest, AgentApprovalResolution, AgentCommandEvent, AgentEventPayload, activity, approvalRequest, approvalResolution, capabilities (+24 more)

### Community 51 - "CompactIslandView"
Cohesion: 0.06
Nodes (40): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right (+32 more)

### Community 52 - "Sendable"
Cohesion: 0.05
Nodes (92): Codable, Equatable, Hashable, RawRepresentable, 1. Domain contracts, Sendable, AgentBridgePermissionDecision, allow (+84 more)

### Community 53 - ".reload"
Cohesion: 0.23
Nodes (3): Bool, T, UserDefaults

### Community 54 - "String"
Cohesion: 0.24
Nodes (8): .result, invalidResponse, CodexAvailableModel, CodexManagedThread, CodexManagedTurn, Bool, Int, String

### Community 55 - "RecordSink"
Cohesion: 0.17
Nodes (11): AppendOnlyRecordTailerTests, Fixture, NoticeSink, openDescriptorCount(), RecordSink, .strings, Bool, Int (+3 more)

### Community 56 - "ClipboardPasteboardReadResult"
Cohesion: 0.14
Nodes (14): ClipboardPasteboardReadResult, empty, oversized, payload, sensitive, unsupported, ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor (+6 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".event"
Cohesion: 0.19
Nodes (12): Success, AgentIngestionCoordinatorTests, Array, .single, Element, Result, Set, StaticString (+4 more)

### Community 59 - ".event"
Cohesion: 0.17
Nodes (8): AgentActivityDescriptor, AgentReductionResult, AgentEventReducerTests, Set, String, TimeInterval, Int, TimeInterval

### Community 60 - "AgentActivityViews.swift"
Cohesion: 0.05
Nodes (65): AgentDashboardLayoutProjection, CGFloat, AgentAttentionSessionRow, .body, .sessionTitle, AgentCLIControlBar, .body, .selectedSession (+57 more)

### Community 61 - "AgentBridgeClient"
Cohesion: 0.10
Nodes (17): AgentBridgeClient, AgentBridgeClientResult, accepted, rejected, Bool, Date, Int, String (+9 more)

### Community 62 - "AgentPromptEditor"
Cohesion: 0.11
Nodes (15): NSScrollView, NSTextView, NSTextViewDelegate, NSViewRepresentable, .submissionValue, AgentPromptDraftPolicy, AgentPromptEditor, AgentPromptTextView (+7 more)

### Community 63 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.06
Nodes (43): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending, MediaRemoteClient (+35 more)

### Community 64 - "CaseIterable"
Cohesion: 0.05
Nodes (37): CaseIterable, 2026-07-11 - Phase 9D Theme Simplification, AgentApprovalPolicyChoice, askEveryTime, autoApprove, DefaultExpandedTab, activities, .displayName (+29 more)

### Community 65 - ".sessionID"
Cohesion: 0.21
Nodes (4): AgentEventStoreTests, Int, String, TimeInterval

### Community 66 - ".makeProcessor"
Cohesion: 0.26
Nodes (6): AgentBridgeEnvelopeIntegrationTests, StaticString, String, UInt, Any, String

### Community 67 - "AgentBridgeClientProfile"
Cohesion: 0.16
Nodes (10): AgentBridgeClientProfile, AgentBridgeDiscoveryRecord, AgentBridgeProtocol, Date, Int, Int32, String, UInt16 (+2 more)

### Community 68 - "AgentUISnapshotTests"
Cohesion: 0.17
Nodes (13): AnyView, AgentCompactAttentionTrailingView, .body, AgentSourceHealthRow, .awaitingGuidance, .body, AgentUISnapshotTests, Bool (+5 more)

### Community 69 - "AppDelegate"
Cohesion: 0.08
Nodes (26): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, NSApplicationDelegate, NSWindowDelegate, 2. Existing DynamicIsland invariants, AppDelegate, .liveActivitySettingsPublisher, DynamicIslandApp (+18 more)

### Community 70 - "AgentIntegrationSetupTests"
Cohesion: 0.19
Nodes (4): AgentHookConfigurationPlanner, Any, AgentIntegrationSetupTests, String

### Community 71 - "ExpandedScrollEventRoutingPolicyTests"
Cohesion: 0.15
Nodes (7): ExpandedContentScrollSequenceOwnership, ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicy, ExpandedScrollEventRoutingPolicyTests, Bool

### Community 72 - "AgentIntegrationProvider"
Cohesion: 0.15
Nodes (14): AgentIntegrationConfigurationExpectation, absent, digest, AgentIntegrationProvider, claude, codex, .desiredEvents, .displayName (+6 more)

### Community 73 - "AppendOnlyRecordTailer.swift"
Cohesion: 0.08
Nodes (25): Dispatch, AppendOnlyRecordLimits, AppendOnlyRecordStartPolicy, boundedCatchUp, fromEnd, AppendOnlyRecordTailerFailure, identityRace, ioFailure (+17 more)

### Community 74 - "DelimitedRecordFramer"
Cohesion: 0.33
Nodes (3): DelimitedRecordFramer, Output, DelimitedRecordFramerTests

### Community 75 - "FileDropProviderLoader"
Cohesion: 0.22
Nodes (8): NSSecureCoding, completion, FileDropProviderLoader, SendableItemProvider, NSItemProvider, TimeInterval, UTType, NSItemProvider

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.15
Nodes (8): AgentBridgeDiscoveryPublisher, FileManager, String, URL, AgentBridgeDiscoveryTests, String, UInt16, URL

### Community 77 - "AgentEvent"
Cohesion: 0.05
Nodes (48): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, AgentEventOrigin, live, localRecovery (+40 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.70
Nodes (3): AirDropURLAccumulator, .urls, URL

### Community 80 - "AgentAttentionCoordinator"
Cohesion: 0.07
Nodes (27): 7. Attention presentation contract, AgentAttentionCoordinator, Bool, Date, Never, Task, TimeInterval, Void (+19 more)

### Community 83 - "SequenceClientTransport"
Cohesion: 0.16
Nodes (13): AgentBridgeEnvelopeBuilder, Any, String, AgentBridgeClientRequest, AgentBridgeSharedClientTests, Outcome, failure, response (+5 more)

### Community 84 - ".apply"
Cohesion: 0.09
Nodes (16): AgentEventReducer, AgentEventStoreLimits, .normalized, SemanticResult, applied, rejected, Bool, Date (+8 more)

### Community 85 - "AgentBridgeDiscoveryReader"
Cohesion: 0.08
Nodes (26): dev_t, ino_t, AgentBridgeDiscoveryFileReading, AgentBridgeDiscoveryFileSnapshot, AgentBridgeDiscoveryReader, Bool, Date, Int (+18 more)

### Community 86 - "AgentEventType"
Cohesion: 0.06
Nodes (32): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+24 more)

### Community 87 - "AgentBridgeWirePayload"
Cohesion: 0.28
Nodes (12): Decodable, AgentBridgeLimits, AgentBridgeWireCapability, AgentBridgeWireEvent, AgentBridgeWirePayload, .populatedFieldCount, AgentBridgeWireRequest, .eventBatch (+4 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.07
Nodes (31): 2026-07-05 - Phase 8C.10 Gesture Responsiveness And Artwork Flip, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, LauncherShortcut, ShortcutsStore, .shortcuts, String, UUID (+23 more)

### Community 89 - "AgentRelayCommandTests"
Cohesion: 0.10
Nodes (14): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000) (+6 more)

### Community 90 - ".readBoundedCatchUp"
Cohesion: 0.19
Nodes (8): AppendOnlyRecordTailerIOError, failure, missing, BoundedRecordRing, .orderedRecords, Int, Int64, Void

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "AgentSessionLauncherView"
Cohesion: 0.20
Nodes (11): AgentLocalRepositoryChoice, .id, AgentSessionLauncherProjection, AgentSessionLauncherView, .body, .liveSessions, .repositories, .selectedProvider (+3 more)

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
Cohesion: 0.12
Nodes (16): SettingsSection, advanced, agents, appearance, clipboard, gestures, .id, island (+8 more)

### Community 103 - ".progress"
Cohesion: 0.18
Nodes (8): Double, Int, TimerProgressColorStage, high, low, mid, .body, TimerProgressFormattingTests

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentReplayHarness"
Cohesion: 0.19
Nodes (5): AgentReplayHarness, Int, AgentReplayHarnessTests, String, TimeInterval

### Community 106 - ".ingest"
Cohesion: 0.15
Nodes (9): AgentTelemetryFusion, AgentTelemetryFusionOutcome, applied, deferredNoSession, ignoredEmpty, rejected, Result, AgentTelemetryFusionTests (+1 more)

### Community 107 - "LiveActivitySettingsSubscriberTests"
Cohesion: 0.25
Nodes (3): LiveActivitySettingsSubscriberTests, String, UserDefaults

### Community 108 - "ShelfFileTile"
Cohesion: 0.13
Nodes (17): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 4C Tray File Actions Context Menu, 2026-07-04 - Phase 5I.2 Animation Performance Polish, EmptyMediaLauncherView, .body, FileShelfActions, MediaLauncherButton, .body (+9 more)

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.18
Nodes (9): FileDropPolicy, FileDropURLAccumulator, .urls, FileShelfTemporaryStorage, Bool, String, URL, .canAcceptExpandedFileDrop (+1 more)

### Community 110 - "AgentPresentationTests"
Cohesion: 0.05
Nodes (22): Int, AgentGlobalUsagePresentation, AgentIntegrationDiagnostics, AgentSessionRowEmphasis, attention, hovered, selected, selectedAttention (+14 more)

### Community 111 - "ServerFactorySpy"
Cohesion: 0.10
Nodes (28): AgentBridgeNetworkError, listenerCancelled, listenerFailed, missingPort, AgentBridgeServing, AgentBridgeLifecycleTests, DeferredServerSpy, .startCount (+20 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.10
Nodes (25): AgentBridgeIngress, AgentBridgeRequestProcessor, Bool, Date, Result, String, AgentBridgeEnvelopeError, emptyBatch (+17 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.20
Nodes (10): DispatchQueue, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, NWConnection, Result (+2 more)

### Community 114 - "CodexAppServerClientTests"
Cohesion: 0.21
Nodes (4): AsyncStream, CodexAppServerClientTests, String, URL

### Community 115 - "ClaudeInteractiveProvider"
Cohesion: 0.14
Nodes (5): ClaudeInteractiveProvider, Bool, Int, Set, String

### Community 116 - ".assertFailure"
Cohesion: 0.10
Nodes (15): Network, AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequest, AgentBridgeHTTPRequestParser, ParsedHeaders (+7 more)

### Community 117 - "Foundation"
Cohesion: 0.07
Nodes (8): AgentBridgeShared, ClaudeHookShared, CodexHookShared, CoreFoundation, CryptoKit, Darwin, Foundation, Security

### Community 118 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 119 - "AgentUsage"
Cohesion: 0.08
Nodes (33): CodingKey, AgentUsage, .allSamples, .isEmpty, .samples, .scopedEntries, AgentUsageKey, AgentUsageMetric (+25 more)

### Community 120 - ".parse"
Cohesion: 0.15
Nodes (11): ClaudeTranscriptRecoveryParser, OperationKind, command, tool, Any, Bool, Date, Double (+3 more)

### Community 121 - ".openActiveMediaSource"
Cohesion: 0.17
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 122 - "AgentBridge"
Cohesion: 0.14
Nodes (16): HTTPURLResponse, Runtime, AgentBridge, LaunchMaterial, ProducerRuntime, Runtime, AgentBridgeServerFactory, Error (+8 more)

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.11
Nodes (19): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 3. Component boundaries, 4. Per-event authority, 5. Local bridge decision, 8. Expanded Agent Activity contract (+11 more)

### Community 124 - "AgentEventApplication"
Cohesion: 0.11
Nodes (18): AgentEventApplication, applied, duplicate, ignoredAfterTerminal, ignoredWeakerEvidence, rejected, staleGeneration, AgentEventBatchApplication (+10 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.11
Nodes (18): 3. Phase gates, A0 — Research and architecture, A10 — Source app/editor association and Open action, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2.1 — Ingestion coordination and source registry, A2.2 — Relay client and append-only ingestion primitives, A2 — Authenticated local Agent Bridge (+10 more)

### Community 126 - "ClaudeCodeStreamingClient"
Cohesion: 0.17
Nodes (5): ClaudeCodeStreamingClient, AsyncStream, URL, ClaudeInteractiveProviderTests, String

### Community 127 - "Agent Capability Matrix"
Cohesion: 0.12
Nodes (16): 1. Method and version boundary, 2. Primary supported integration surfaces, 3. Capability matrix, 4. Event-specific authority, 5. Local storage audit (content redacted), 6. Source application association, 7. Design implications, 8. Official sources (+8 more)

### Community 128 - "Agent Event Schema Draft"
Cohesion: 0.12
Nodes (16): 2. State vocabulary, 3. Session identity, 4. Normalized event types, 5. Versioned transport envelope, 6. Capability model, 7. Privacy projection, 8. Replay fixture contract, 9. Deferred decisions (+8 more)

### Community 129 - "IslandHostingView"
Cohesion: 0.14
Nodes (12): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, NSHostingView, NSSize, NSTrackingArea, NSView, Native overlay, geometry and input, IslandHostingView, .intrinsicContentSize (+4 more)

### Community 130 - "AgentBridgeNetworkExchange"
Cohesion: 0.15
Nodes (15): AgentBridgeClientTransport, AgentBridgeClientTransportError, connectTimedOut, malformedResponse, requestTimedOut, responseTooLarge, unavailable, AgentBridgeNetworkExchange (+7 more)

### Community 131 - ".signedRequest"
Cohesion: 0.35
Nodes (3): AgentBridgeAuthenticationTests, AgentBridgeTestSupport, Int64

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "AgentBridgeDiscoveryReadError"
Cohesion: 0.12
Nodes (16): AgentBridgeDiscoveryReadError, changedDuringRead, invalidAuthentication, invalidHost, invalidIdentifier, invalidPort, invalidProcess, invalidTimestamp (+8 more)

### Community 134 - "Data"
Cohesion: 0.08
Nodes (18): AgentBridgeRequestAuthentication, Data, Bool, Int, Int64, String, FileClipboardHistoryPersistence, FileManager (+10 more)

### Community 135 - "IslandOverlayPanel"
Cohesion: 0.13
Nodes (14): Phase 11C.3 - Diagnostic WindowServer Transition Trace, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 11C - Persistent Overlay During App And Window Switching, Phase 12B - Native Overlay Cleanup And Runtime Optimization, CustomStringConvertible, NSPanel, ExpandedPresentationKind, agentsWorkspace (+6 more)

### Community 136 - "YouTubeMetadataProvider"
Cohesion: 0.30
Nodes (9): CodingKeys, authorName, thumbnailURL, title, OEmbedResponse, String, URL, YouTubeMetadata (+1 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.17
Nodes (10): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, A3.1 implementation refinement — Codex structured recovery, A3 implementation refinement — Codex authoritative hooks, A4.1 implementation refinement — Claude transcript recovery, A4.5 implementation refinement — bounded OTLP JSON enrichment (+2 more)

### Community 138 - "IslandLayoutStore"
Cohesion: 0.13
Nodes (11): 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, Composition, state and settings, IslandModule, IslandCanvasCoordinateSpace, IslandLayoutStore, Bool, CGFloat, CGRect (+3 more)

### Community 139 - "AgentBridgeEnvelopeBuildError"
Cohesion: 0.08
Nodes (24): AgentBridgeClientError, authenticationFailed, discoveryUnavailable, invalidInput, malformedResponse, timedOut, transportUnavailable, AttemptError (+16 more)

### Community 140 - "AppKit"
Cohesion: 0.10
Nodes (5): AppKit, QuartzCore, Key, SwiftUI, UniformTypeIdentifiers

### Community 141 - "AgentSession"
Cohesion: 0.08
Nodes (28): AgentActionControlGate, AgentSession, .isActive, .isOpen, AgentApprovalPresentation, AgentCompactPresentation, AgentDashboardPresentation, AgentDashboardPreviewFactory (+20 more)

### Community 142 - "AgentRelayExitCode"
Cohesion: 0.10
Nodes (19): Int32, AgentRelayCommand, AgentRelayCommandResult, AgentRelayExitCode, accepted, authenticationFailed, bridgeUnavailable, discoveryUnavailable (+11 more)

### Community 143 - "AudioVisualizerView"
Cohesion: 0.14
Nodes (16): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing (+8 more)

### Community 144 - "CodexAppServerProvider"
Cohesion: 0.10
Nodes (11): AgentInteractiveRequestToken, integer, string, Int64, CodexAppServerProvider, Any, Bool, Date (+3 more)

### Community 145 - "AgentApprovalPolicyMode"
Cohesion: 0.20
Nodes (9): Set, AgentApprovalPolicyKey, AgentApprovalPolicyMode, askEveryTime, autoApprove, .displayName, .isAutomatic, AgentApprovalPolicyState (+1 more)

### Community 146 - ".normalize"
Cohesion: 0.11
Nodes (11): ClaudeHookNormalizer, ClaudeHookStandardInput, Any, Bool, Date, FileHandle, Int, String (+3 more)

### Community 147 - "AgentEventValidationError"
Cohesion: 0.11
Nodes (14): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+6 more)

### Community 148 - "AgentAuthorityDomain"
Cohesion: 0.17
Nodes (10): AgentAuthorityDomain, activity, capability, interaction, lifecycle, liveness, metadata, operation (+2 more)

### Community 149 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 150 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 151 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 152 - ".normalize"
Cohesion: 0.14
Nodes (8): CodexHookNormalizer, Any, Bool, Date, Int, String, CodexHookNormalizerTests, String

### Community 153 - "AgentApprovalController"
Cohesion: 0.09
Nodes (26): AgentApprovalControlKey, AgentApprovalController, AgentApprovalControlRequest, .id, AgentApprovalControlResult, accepted, missing, Bool (+18 more)

### Community 154 - "UInt64"
Cohesion: 0.15
Nodes (13): AgentIngestionEvent, .sessionID, AgentSessionContinuity, UInt64, CodexRolloutRecoveryParser, Any, Date, Double (+5 more)

### Community 155 - "CodexJSONValue"
Cohesion: 0.09
Nodes (20): CodexJSONValue, array, .arrayValue, bool, .boolValue, .doubleValue, integer, .intValue (+12 more)

### Community 156 - "ClaudeCodeStreamEnvelope"
Cohesion: 0.39
Nodes (4): ClaudeCodeStreamEnvelope, ClaudeCodeStreamEvent, message, transportFailed

### Community 157 - "MediaController.swift"
Cohesion: 0.08
Nodes (29): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, Index, Array, ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect (+21 more)

### Community 158 - "AgentManagedSessionController"
Cohesion: 0.07
Nodes (31): S, AgentInteractiveProvider, AgentManagedSessionController, .accountUsage, .activeManagedSessionIDs, .interactiveCapabilities, .isAvailable, .managedProvider (+23 more)

### Community 159 - "AgentActivityKind"
Cohesion: 0.18
Nodes (11): AgentActivityKind, approval, command, failure, interruption, plan, session, subagent (+3 more)

### Community 160 - "String"
Cohesion: 0.33
Nodes (7): AgentOTLPJSONDecoder, AgentTelemetryObservation, .isEmpty, Any, Date, Double, String

### Community 161 - "AgentInteractiveProviderEvent"
Cohesion: 0.04
Nodes (54): AgentDiscoveredSessionDescriptor, AgentDiscoveredSessionRuntimeState, active, idle, notLoaded, systemError, AgentInteractiveCapability, accountUsage (+46 more)

### Community 162 - "Claude Managed Control Review — 2026-09-27"
Cohesion: 0.15
Nodes (12): 10. Phase 6 recommendation, 1. Supported official mechanism, 2. Transport and API, 3. Lifecycle and session semantics, 4. Streaming visible responses and tool events, 5. Approvals and user input, 6. Model control, 7. Usage and context (+4 more)

### Community 163 - "AgentEventStore"
Cohesion: 0.14
Nodes (12): State ownership, AgentEventStore, .activeSessions, .sessionsRequiringAttention, AgentIngestionCoordinator, CheckedContinuation, Never, StoreSink (+4 more)

### Community 164 - "AgentIntegrationOperationalState"
Cohesion: 0.13
Nodes (13): AgentIntegrationOperationalState, active, awaitingFirstEvent, blocked, degraded, failed, .label, notConfigured (+5 more)

### Community 165 - "AgentSourceRegistryTests.swift"
Cohesion: 0.50
Nodes (3): Array, .single, Element

### Community 166 - "Run"
Cohesion: 0.31
Nodes (7): Run, Never, Pipe, Process, String, Task, Void

### Community 167 - "CodexAppServerError"
Cohesion: 0.17
Nodes (10): CodexAppServerError, executableNotFound, launchFailed, malformedMessage, notRunning, requestTimedOut, rpcError, transportClosed (+2 more)

### Community 168 - "XCTestCase"
Cohesion: 0.17
Nodes (12): E, AgentIntegrationRouterTests, Collection, .single, EventCapture, Element, Result, StaticString (+4 more)

### Community 169 - "AgentState"
Cohesion: 0.10
Nodes (17): AgentState, completed, failed, idle, interrupted, .isTerminal, planning, planReady (+9 more)

### Community 170 - "ExpandedContentScrollSequencePhase"
Cohesion: 0.20
Nodes (10): ExpandedContentScrollSequencePhase, momentumBegan, momentumCancelled, momentumChanged, momentumEnded, phaseLess, physicalBegan, physicalCancelled (+2 more)

### Community 171 - "CodexAppServerClient"
Cohesion: 0.12
Nodes (16): CodexAppServerClient, CodexAppServerEvent, notification, serverRequest, transportClosed, object, PendingRequest, AsyncStream (+8 more)

### Community 172 - "AppLaunchService"
Cohesion: 0.34
Nodes (6): 2026-07-03 - Common App Launch Resolver, AppLaunchService, Bool, String, URL, .body

### Community 173 - "Agent Workspace Execution Plan — 2026-09-27"
Cohesion: 0.14
Nodes (13): Agent Workspace Execution Plan — 2026-09-27, Frozen invariants, Iteration rule, Phase 1 — Gesture-safe session scrolling, Phase 2 — Agents-specific expanded geometry, Phase 3.5 — Real-device workspace stabilization, Phase 3 — Enclosed workspace + session selection, Phase 4 — Embedded agent console UI (+5 more)

### Community 174 - ".testPerSessionModelOverridesPersistAndRevalidateIndependently"
Cohesion: 0.26
Nodes (3): AgentManagedModelDescriptor, .availableModels, .modelSelectionScope

### Community 175 - "ClipboardHistoryPersistenceFinalizationResult"
Cohesion: 0.23
Nodes (9): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+1 more)

### Community 176 - "AgentPresentationPriority"
Cohesion: 0.25
Nodes (8): Comparable, AgentPresentationPriority, actionRequired, failure, idle, recent, thinking, working

### Community 177 - "AgentBridgeHTTPStatus"
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 178 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.10
Nodes (18): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, Any, CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank (+10 more)

### Community 179 - "Identifiable"
Cohesion: 0.15
Nodes (14): Identifiable, AgentConsoleEntry, AgentConsoleEntryKind, agent, approval, command, error, plan (+6 more)

### Community 180 - "AgentIngestionError"
Cohesion: 0.09
Nodes (20): Bool, String, Void, AgentIdentityConflict, AgentIngestionError, capabilityCapacity, generationConflict, identityConflict (+12 more)

### Community 181 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 182 - "AgentEmbeddedConsoleView"
Cohesion: 0.07
Nodes (32): AgentSourceAssociationResolver, AgentSourceOpenTarget, String, AgentConsoleExternalApprovalRow, AgentConsoleMode, .canInterrupt, interactive, observed (+24 more)

### Community 183 - "AgentConsoleViews.swift"
Cohesion: 0.24
Nodes (8): PreferenceKey, AgentConsoleBottomPositionPreferenceKey, AgentConsoleCoordinateSpace, AgentConsoleScrollAnchor, bottom, AgentConsoleScrollRegionPreferenceKey, CGFloat, CGRect

### Community 184 - "IslandRootView.swift"
Cohesion: 0.05
Nodes (62): EnvironmentKey, SystemStatsSnapshot, AirDropDropZoneView, .body, .subtitle, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body (+54 more)

### Community 185 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 187 - "AgentIntegrationSetupState"
Cohesion: 0.29
Nodes (7): AgentIntegrationSetupState, blocked, configured, helperUnavailable, .label, needsSetup, repairRequired

### Community 188 - "DedicatedTimerPageView"
Cohesion: 0.27
Nodes (7): DedicatedTimerPageView, .controlsFontSize, .controlsSpacing, .timerControlRow, .timerControlStack, .titleFontSize, .usesCompactLayout

### Community 189 - "ClaudeCodeStreamingError"
Cohesion: 0.33
Nodes (6): ClaudeCodeStreamingError, executableNotFound, launchFailed, malformedMessage, turnAlreadyRunning, unsupported

### Community 190 - "Claude Managed Control Review — 2026-09-28"
Cohesion: 0.33
Nodes (5): Capability matrix, Claude Managed Control Review — 2026-09-28, Identity and safety, Production decision, Scope

### Community 191 - "Codex Managed Model Control Review — 2026-09-28"
Cohesion: 0.33
Nodes (5): Codex Managed Model Control Review — 2026-09-28, Context, Inventory, Selection semantics, Verified sources

### Community 192 - "DynamicIslandLiveActivityKind"
Cohesion: 0.29
Nodes (7): 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 193 - "AgentBridgeAuthenticationError"
Cohesion: 0.22
Nodes (9): AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull, timestampOutsideWindow (+1 more)

### Community 194 - "AgentBridgeState"
Cohesion: 0.33
Nodes (6): AgentBridgeState, degraded, failed, running, starting, stopped

### Community 195 - "ObservableObject"
Cohesion: 0.50
Nodes (3): ObservableObject, AgentIntegrationDiagnosticsController, AnyCancellable

### Community 196 - "Error"
Cohesion: 0.03
Nodes (59): Error, ClaudeHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook (+51 more)

### Community 203 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

## Knowledge Gaps
- **1234 isolated node(s):** `PackageDescription`, `package_app.sh script`, `unavailable`, `connectTimedOut`, `requestTimedOut` (+1229 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1626 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `AppKit`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `NotchGeometryService`, `IslandNavigationStore`, `FileShelfStore`, `Change Log`, `AgentApprovalController`, `Int`, `DynamicIslandLiveActivity`, `OverlayWindowController`, `AgentEventStore`, `MediaModuleView`, `.init`, `FileDropProviderLoaderTests`, `String`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `View`, `CompactIslandView`, `AnimationPreset`, `.reload`, `IslandRootView.swift`, `AutoCollapseDelayPreset`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `DedicatedTimerPageView`, `CaseIterable`, `ObservableObject`, `AgentUISnapshotTests`, `AppDelegate`, `ShortcutsStore`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`?**
  _High betweenness centrality (0.117) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `IslandGestureAction`, `SystemStatsController`, `.signedRequest`, `ArtworkFlipPresentationState`, `IslandRootView`, `Data`, `IslandEscapeRouter`, `SystemClipboardPasteboardClient`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `CollapsedLiveActivitySelectorTests`, `.start`, `.normalize`, `FileShelfStore`, `ArtworkAccentColorCache`, `.normalize`, `AgentApprovalController`, `ClipboardHistoryView`, `UInt64`, `MediaAutomationExecutor`, `ClipboardImageNormalizerTests`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `AgentProducerHandle`, `AgentEventStore`, `FileDropProviderLoaderTests`, `AgentState`, `AgentSourceInstanceID`, `.refresh`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `AgentEventPayload`, `Identifiable`, `AgentEmbeddedConsoleView`, `RecordSink`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `.event`, `.event`, `AgentBridgeClient`, `ManualMediaRemoteDeadlineScheduler`, `.sessionID`, `.makeProcessor`, `AgentUISnapshotTests`, `AppDelegate`, `AgentIntegrationSetupTests`, `ExpandedScrollEventRoutingPolicyTests`, `DelimitedRecordFramer`, `AgentBridgeDiscoveryPublisher`, `AgentAttentionCoordinator`, `SequenceClientTransport`, `AgentBridgeDiscoveryReader`, `AgentRelayCommandTests`, `.progress`, `AgentReplayHarness`, `.ingest`, `LiveActivitySettingsSubscriberTests`, `AgentPresentationTests`, `ServerFactorySpy`, `CodexAppServerClientTests`, `.assertFailure`, `ClipboardHistoryPresentationState`, `.parse`, `.openActiveMediaSource`, `AgentBridge`, `ClaudeCodeStreamingClient`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **Why does `IslandRootView` connect `IslandRootView` to `AppSettings`, `IslandHostingView`, `IslandGestureAction`, `IslandEscapeRouter`, `IslandOverlayPanel`, `IslandLayoutStore`, `AudioVisualizerView`, `IslandNavigationStore`, `Change Log`, `DynamicIsland`, `DynamicIslandLiveActivity`, `OverlayWindowController`, `AgentManagedSessionController`, `MediaController.swift`, `.init`, `What You Must Do When Invoked`, `String`, `IslandStateStore`, `CGFloat`, `View`, `CompactIslandView`, `IslandRootView.swift`, `AppDelegate`, `FileDropProviderLoader`, `AgentAttentionCoordinator`, `FileShelfTemporaryStorage`?**
  _High betweenness centrality (0.051) - this node is a cross-community bridge._
- **Are the 31 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 31 INFERRED edges - model-reasoned connections that need verification._
- **Are the 19 inferred relationships involving `AgentSession` (e.g. with `1. Domain contracts` and `.scheduleCompletion()`) actually correct?**
  _`AgentSession` has 19 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `unavailable` to the rest of the system?**
  _1234 weakly-connected nodes found - possible documentation gaps or missing edges._