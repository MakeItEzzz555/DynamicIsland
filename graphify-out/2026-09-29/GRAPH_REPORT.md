# Graph Report - DynamicIsland  (2026-09-29)

## Corpus Check
- 191 files · ~520,689 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 6145 nodes · 18575 edges · 207 communities (190 shown, 17 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 2656 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `492185cd`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- AppSettings
- IslandGestureAction
- UInt64
- ArtworkFlipPresentationState
- SettingsView
- IslandRootView
- IslandEscapeRouter
- ClipboardHistoryPersistence
- TimerController
- SystemClipboardPasteboardClient
- TimerCompletionNotificationCoordinator
- ClipboardHistoryPayload
- NotchGeometryService
- ClipboardHistoryStore
- .normalizeAndSaveDouble
- CollapsedLiveActivitySelectorTests
- IslandNavigationStore
- .start
- FileShelfStore
- OverlayGeometrySignature
- AgentIntegrationRouter
- Change Log
- ExpandedIslandLayoutMetrics
- Int
- DynamicIsland
- ClipboardHistoryEntry
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- OverlayWindowController
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- AgentSessionInstanceID
- AgentBridgeAuthenticator
- Phase Workflow For Future Work
- AppendOnlyRecordTailer
- MediaModuleView
- View
- AgentEmbeddedConsoleView
- FileDropProviderLoaderTests
- What You Must Do When Invoked
- AgentMCPObservationAdapter
- String
- .refresh
- DynamicIsland Project Context
- AppSettingsTests
- CGFloat
- AgentIntegrationSetupService
- .share
- AppKit
- .opacity
- Sendable
- .displayedStateLabel
- String
- RecordSink
- ClipboardPasteboardReadResult
- OverlayPresentationSessionTests
- .event
- .sessionID
- String
- AgentBridgeClient
- AgentPromptEditor
- ManualMediaRemoteDeadlineScheduler
- CaseIterable
- .ingest
- .makeProcessor
- AgentBridgeClientProfile
- AgentUISnapshotTests
- AppDelegate
- .install
- ExpandedScrollEventRoutingPolicyTests
- AgentIntegrationProvider
- AppendOnlyRecordTailer.swift
- DelimitedRecordFramer
- FileDropProviderLoader
- XCTestCase
- AgentCapability
- Meaningful regression history
- ArtworkAccentColorCache
- AgentAttentionEvent
- Package.swift
- package_app.sh
- SequenceClientTransport
- .apply
- AgentBridgeDiscoveryReader
- AgentEventType
- CodexRolloutRecoveryParser
- ShortcutsStore
- AgentRelayCommandTests
- AudioVisualizerView
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- .makeSession
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- .normalize
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- AGENTS.md
- extraction-spec.md
- STABLE_INVARIANTS.md
- .progress
- AgentInteractiveCapability
- AgentEvent
- .handleCollapsedScrollWheel
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- AgentPresentationTests
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- CodexAppServerProvider
- ClaudeInteractiveProvider
- .assertFailure
- Foundation
- ClipboardHistoryPresentationState
- AgentUsage
- .parse
- .openActiveMediaSource
- AgentBridge
- Agent Activity Integration Architecture
- AgentEventStoreLimits
- 3. Phase gates
- ClaudeInteractiveProviderTests
- Agent Capability Matrix
- Agent Event Schema Draft
- AgentActivityGlowCoordinator
- AgentBridgeNetworkExchange
- .signedRequest
- MenuBarController
- Error
- Data
- IslandHostingView
- IslandLayoutStore
- .reload
- Bool
- AgentBridgeClientError
- CompactIslandView
- NetworkCounters
- AgentRelayExitCode
- AgentBridgeEnvelopeBuildError
- YouTubeMetadataProvider
- AgentBridgeHTTPRequestParser
- .normalize
- SettingsSection
- AgentProducerPolicy
- LaunchAtLoginController.swift
- LockedValue
- AgentState
- SupportedApp
- AgentApprovalController
- AgentBridgeIngress
- CodexJSONValue
- AgentInteractiveProviderEvent
- MediaController.swift
- AgentManagedSessionController
- AgentNotch Reference Review
- AgentEventValidationError
- AgentEventPayload
- Claude Managed Control Review — 2026-09-27
- AgentEventStore
- AgentBridgeHTTPStatus
- AppLaunchService
- ClaudeCodeStreamingClient
- ObservableObject
- .session
- IslandSurfaceBackground
- Agent Activity Feature Phase Plan
- CodexAppServerClient
- AgentPromptTextView
- Agent Workspace Execution Plan — 2026-09-27
- AgentSession
- ClaudeCodeStreamEnvelope
- LiveActivityStore
- AgentSourceHealthRow
- CollapsedLiveActivityPrioritySource
- AnimationPreset
- AgentProducerHandle
- ControlledClipboardPersistence
- Fresh critical audit instructions
- FileClipboardHistoryPersistence
- String
- AutoCollapseDelayPreset
- OverlayWindowController.swift
- AgentConsoleBottomPositionPreferenceKey
- .testRealListenerUsesLoopbackEphemeralPortAndIngestsSignedEvent
- Claude Managed Control Review — 2026-09-28
- Codex Managed Model Control Review — 2026-09-28
- CodexAppServerError
- .decode
- AgentIntegrationSetupError
- RecordingFileShelfDefaults
- .remainingTime
- CodexListedThread
- AgentApprovalPolicyMode
- SystemAgentNotificationFeedback
- summary.md
- .pause
- AgentInteractiveRequestToken
- .init
- IslandRootView.swift
- AgentIntegrationOperationalState
- XCTest

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 344 edges
2. `AgentSession` - 187 edges
3. `OverlayWindowController` - 147 edges
4. `AgentManagedSessionController` - 143 edges
5. `AgentEventStore` - 128 edges
6. `AgentIngestionCoordinator` - 115 edges
7. `Change Log` - 110 edges
8. `MediaController` - 105 edges
9. `AgentApprovalController` - 96 edges
10. `AgentProvider` - 93 edges

## Surprising Connections (you probably didn't know these)
- `A1 — Normalized domain, `AgentEventStore`, replay harness` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `2. Transport and API` --references--> `AgentIngestionCoordinator`  [INFERRED]
  research/CLAUDE_MANAGED_CONTROL_REVIEW_2026-09-27.md → Sources/DynamicIsland/Agents/AgentIngestionCoordinator.swift
- `10. Phase 6 recommendation` --references--> `ClaudeInteractiveProvider`  [INFERRED]
  research/CLAUDE_MANAGED_CONTROL_REVIEW_2026-09-27.md → Sources/DynamicIsland/Agents/ClaudeInteractiveProvider.swift
- `A4.1 Claude recovery authority` --references--> `ClaudeTranscriptRecoveryAdapter`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/Agents/ClaudeTranscriptRecovery.swift
- `2026-07-03 - Common App Launch Resolver` --references--> `AppLaunchService`  [INFERRED]
  context.md → Sources/DynamicIsland/App/AppLaunchService.swift

## Import Cycles
- None detected.

## Communities (207 total, 17 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (162): AnyPublisher, Never, AppSettings, .activitiesEnabled, .agentActivityEnabled, .agentApprovalAlertsEnabled, .agentCompletionAlertsEnabled, .agentPeekDurationSeconds (+154 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.08
Nodes (37): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, IslandGestureAction, collapse, .displayName, expand, .id, mediaNextTrack (+29 more)

### Community 2 - "UInt64"
Cohesion: 0.10
Nodes (16): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, UInt64, CPUCounters, Bool, Date, Double, Int (+8 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.20
Nodes (7): ArtworkFlipPresentationState, .queuedSnapshot, ArtworkPresentationSnapshot, QueuedTransition, ArtworkFlipPresentationStateTests, Bool, String

### Community 4 - "SettingsView"
Cohesion: 0.15
Nodes (28): content, HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsView (+20 more)

### Community 5 - "IslandRootView"
Cohesion: 0.05
Nodes (47): Animation, 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 11C.9 - Predictive Space Motion Resampling, Phase 12A - Final Island Content Transition Sequencing, Phase 13A - Expanded Visibility Controls, IslandModules, AirDropURLAccumulator (+39 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryPersistence"
Cohesion: 0.12
Nodes (14): ClipboardHistoryPersistence, ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed (+6 more)

### Community 8 - "TimerController"
Cohesion: 0.10
Nodes (20): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration (+12 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.10
Nodes (20): Bool, Duration, Never, String, Task, TimeInterval, Void, SystemTimerNotificationCenterClient (+12 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.06
Nodes (33): ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint, ClipboardHistoryPayload, .byteCount (+25 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.08
Nodes (27): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry (+19 more)

### Community 13 - "ClipboardHistoryStore"
Cohesion: 0.13
Nodes (16): ClipboardHistoryStore, AnyCancellable, async, Never, Set, Task, Timer, Void (+8 more)

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
Cohesion: 0.22
Nodes (6): TimerCompletionNotificationPreferences, MockTimerNotificationCenterClient, Bool, String, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (15): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge (+7 more)

### Community 19 - "OverlayGeometrySignature"
Cohesion: 0.18
Nodes (9): Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12B - Native Overlay Cleanup And Runtime Optimization, CustomStringConvertible, ExpandedPresentationKind, agentsWorkspace, standard, OverlayGeometrySignature, .currentGeometrySignature (+1 more)

### Community 20 - "AgentIntegrationRouter"
Cohesion: 0.08
Nodes (33): Comparable, AgentIngestionResult, AgentIntegrationPrecedence, mcpFallback, providerNative, secondaryObservation, AgentIntegrationRouter, AgentMCPObservation (+25 more)

### Community 21 - "Change Log"
Cohesion: 0.04
Nodes (65): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut (+57 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "Int"
Cohesion: 0.06
Nodes (40): Identifiable, Int, AgentConsoleEntry, AgentConsoleEntryKind, agent, approval, command, error (+32 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (36): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+28 more)

### Community 25 - "ClipboardHistoryEntry"
Cohesion: 0.10
Nodes (19): Calendar, UUID, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body (+11 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (49): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+41 more)

### Community 27 - "Int"
Cohesion: 0.09
Nodes (16): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer (+8 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.11
Nodes (26): 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer (+18 more)

### Community 29 - "OverlayWindowController"
Cohesion: 0.08
Nodes (27): CFTimeInterval, DispatchWorkItem, NSPanel, NSPoint, Native overlay, geometry and input, IslandOverlayPanel, .canBecomeKey, .canBecomeMain (+19 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (12): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int (+4 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (4): MediaArbitratorTests, Bool, NSImage, String

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.11
Nodes (18): Phase 11A - Battery Live Activity, BatteryActivityProvider, BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Any, Bool (+10 more)

### Community 33 - "AgentSessionInstanceID"
Cohesion: 0.11
Nodes (17): AgentSessionInstanceID, AgentActivityDashboardView, .body, AgentDashboardContentView, .body, AgentsPagePresentationState, .chromeVisible, .transcriptReady (+9 more)

### Community 34 - "AgentBridgeAuthenticator"
Cohesion: 0.09
Nodes (25): OSStatus, AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull (+17 more)

### Community 35 - "Phase Workflow For Future Work"
Cohesion: 0.07
Nodes (31): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment (+23 more)

### Community 36 - "AppendOnlyRecordTailer"
Cohesion: 0.12
Nodes (14): DispatchSourceFileSystemObject, NoticeHandler, RecordHandler, A2.1 ingress boundary and A2.2 handoff, AppendOnlyFileIdentity, AppendOnlyRecordTailer, AppendOnlyRecordTailerHealth, failure (+6 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.08
Nodes (24): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, Double, MediaModuleView, .activePlayerView, .artistFontSize, .artworkSize, .constrainedActivePlayerView (+16 more)

### Community 38 - "View"
Cohesion: 0.11
Nodes (22): 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor, 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix, 2026-07-04 - Phase 6A Single Adaptive Island Panel, 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership, 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing, Phase 12C.2 - Notch-Aware Body-Relative Content Insets, Phase 13B.2 - Native In-Island Clipboard Interface, Views (+14 more)

### Community 39 - "AgentEmbeddedConsoleView"
Cohesion: 0.08
Nodes (31): AgentConsoleCoordinateSpace, AgentConsoleExternalApprovalRow, .body, AgentConsoleMode, .canInterrupt, interactive, observed, .showsComposer (+23 more)

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.18
Nodes (10): .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, String, URL (+2 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "AgentMCPObservationAdapter"
Cohesion: 0.09
Nodes (28): AgentMCPAdapterLimits, AgentMCPAdapterRefreshResult, AgentMCPObservationAdapter, AgentMCPObservationDecoder, AgentMCPSourceConnecting, AgentMCPSourceConnection, AgentMCPSourceDescriptor, AgentMCPSourceDiscovering (+20 more)

### Community 43 - "String"
Cohesion: 0.09
Nodes (20): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, BrowserScriptTarget, Decision, MediaArbitrator, MediaCandidate, .sourceKey, MediaController, .currentArtworkPresentationIdentity (+12 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "DynamicIsland Project Context"
Cohesion: 0.11
Nodes (16): App Entry, Collapsed, Current Architecture, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context, Expanded (+8 more)

### Community 46 - "AppSettingsTests"
Cohesion: 0.12
Nodes (3): AppSettingsTests, String, UserDefaults

### Community 47 - "CGFloat"
Cohesion: 0.09
Nodes (24): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline, Evidence and graph limits, SwiftUI rendering and presentation (+16 more)

### Community 48 - "AgentIntegrationSetupService"
Cohesion: 0.17
Nodes (12): AgentIntegrationBackupEnvelope, AgentIntegrationSetupPaths, AgentIntegrationSetupService, .fileManager, AgentIntegrationSetupSnapshot, Bool, FileManager, Int (+4 more)

### Community 49 - ".share"
Cohesion: 0.40
Nodes (4): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL

### Community 50 - "AppKit"
Cohesion: 0.10
Nodes (5): AppKit, DynamicIslandApp, Key, SwiftUI, UniformTypeIdentifiers

### Community 51 - ".opacity"
Cohesion: 0.09
Nodes (33): 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, .body, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, .percentText (+25 more)

### Community 52 - "Sendable"
Cohesion: 0.04
Nodes (89): Codable, Equatable, Hashable, 1. Domain contracts, Sendable, AgentBridgeSharedError, invalidNonce, randomUnavailable (+81 more)

### Community 53 - ".displayedStateLabel"
Cohesion: 0.17
Nodes (11): .body, .body, AgentProgressRail, .body, .body, .body, .body, Color (+3 more)

### Community 54 - "String"
Cohesion: 0.27
Nodes (7): .result, invalidResponse, CodexAvailableModel, CodexManagedThread, Bool, Int, String

### Community 55 - "RecordSink"
Cohesion: 0.17
Nodes (11): AppendOnlyRecordTailerTests, Fixture, NoticeSink, openDescriptorCount(), RecordSink, .strings, Bool, Int (+3 more)

### Community 56 - "ClipboardPasteboardReadResult"
Cohesion: 0.10
Nodes (21): ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult (+13 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (10): 2. Existing DynamicIsland invariants, OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent (+2 more)

### Community 58 - ".event"
Cohesion: 0.06
Nodes (40): Bool, Result, String, Void, AgentIngestionError, capabilityCapacity, generationConflict, identityConflict (+32 more)

### Community 59 - ".sessionID"
Cohesion: 0.18
Nodes (8): AgentActivityDescriptor, AgentReductionResult, AgentEventReducerTests, Set, String, TimeInterval, Int, TimeInterval

### Community 60 - "String"
Cohesion: 0.15
Nodes (9): AgentCollapsedShellPresentation, AgentSessionPresentation, String, TimeInterval, .collapsedPresentationProfile, .sessionTitle, .sessionTitle, .title (+1 more)

### Community 61 - "AgentBridgeClient"
Cohesion: 0.11
Nodes (16): AgentBridgeClient, AgentBridgeClientResult, accepted, rejected, AgentBridgeClientTransport, Date, Int, String (+8 more)

### Community 62 - "AgentPromptEditor"
Cohesion: 0.15
Nodes (12): NSObject, NSScrollView, NSTextViewDelegate, NSViewRepresentable, .submissionValue, AgentPromptDraftPolicy, AgentPromptEditor, Coordinator (+4 more)

### Community 63 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.06
Nodes (44): AnyObject, 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending (+36 more)

### Community 64 - "CaseIterable"
Cohesion: 0.05
Nodes (37): CaseIterable, 2026-07-11 - Phase 9D Theme Simplification, AgentApprovalPolicyChoice, askEveryTime, autoApprove, DefaultExpandedTab, activities, .displayName (+29 more)

### Community 65 - ".ingest"
Cohesion: 0.18
Nodes (4): AgentEventStoreTests, Int, String, TimeInterval

### Community 66 - ".makeProcessor"
Cohesion: 0.26
Nodes (6): AgentBridgeEnvelopeIntegrationTests, StaticString, String, UInt, Any, String

### Community 67 - "AgentBridgeClientProfile"
Cohesion: 0.17
Nodes (10): AgentBridgeClientProfile, AgentBridgeDiscoveryRecord, AgentBridgeProtocol, Date, Int, Int32, String, UInt16 (+2 more)

### Community 68 - "AgentUISnapshotTests"
Cohesion: 0.20
Nodes (10): AnyView, AgentCompactAttentionTrailingView, .body, AgentUISnapshotTests, Bool, CGSize, Color, String (+2 more)

### Community 69 - "AppDelegate"
Cohesion: 0.10
Nodes (19): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSWindowDelegate, AppDelegate, .liveActivitySettingsPublisher, LiveActivitySettingsSnapshot (+11 more)

### Community 70 - ".install"
Cohesion: 0.12
Nodes (10): AgentHookConfigurationPlanner, AgentIntegrationSetupState, blocked, configured, helperUnavailable, .label, needsSetup, repairRequired (+2 more)

### Community 71 - "ExpandedScrollEventRoutingPolicyTests"
Cohesion: 0.14
Nodes (6): IslandCanvasCoordinateSpace, ExpandedContentScrollSequenceOwnership, Owner, island, ExpandedScrollEventRoutingPolicyTests, Bool

### Community 72 - "AgentIntegrationProvider"
Cohesion: 0.15
Nodes (15): AgentIntegrationConfigurationExpectation, absent, digest, AgentIntegrationProvider, claude, codex, .desiredEvents, .displayName (+7 more)

### Community 73 - "AppendOnlyRecordTailer.swift"
Cohesion: 0.08
Nodes (27): Dispatch, AppendOnlyRecordLimits, AppendOnlyRecordStartPolicy, boundedCatchUp, fromEnd, AppendOnlyRecordTailerFailure, identityRace, ioFailure (+19 more)

### Community 74 - "DelimitedRecordFramer"
Cohesion: 0.20
Nodes (7): BoundedRecordRing, .orderedRecords, DelimitedRecordFramer, Output, Int, Void, DelimitedRecordFramerTests

### Community 75 - "FileDropProviderLoader"
Cohesion: 0.18
Nodes (9): NSSecureCoding, completion, FileDropProviderLoader, FileDropURLAccumulator, .urls, SendableItemProvider, NSItemProvider, TimeInterval (+1 more)

### Community 76 - "XCTestCase"
Cohesion: 0.07
Nodes (21): E, AgentBridgeDiscoveryPublisher, FileManager, String, URL, AgentBridgeDiscoveryTests, String, UInt16 (+13 more)

### Community 77 - "AgentCapability"
Cohesion: 0.06
Nodes (33): Date, AgentCapabilities, .all, AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage (+25 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (17): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+9 more)

### Community 80 - "AgentAttentionEvent"
Cohesion: 0.06
Nodes (47): 7. Attention presentation contract, AgentAttentionCoordinator, Date, Never, Task, TimeInterval, Void, AgentAttentionBadge (+39 more)

### Community 83 - "SequenceClientTransport"
Cohesion: 0.23
Nodes (10): AgentBridgeClientRequest, AgentBridgeSharedClientTests, Outcome, failure, response, SequenceClientTransport, SequenceProfileProvider, Duration (+2 more)

### Community 84 - ".apply"
Cohesion: 0.12
Nodes (13): AgentEventReducer, SemanticResult, applied, rejected, Bool, Date, String, Value (+5 more)

### Community 85 - "AgentBridgeDiscoveryReader"
Cohesion: 0.08
Nodes (27): dev_t, ino_t, AgentBridgeClientProfileProviding, AgentBridgeDiscoveryFileReading, AgentBridgeDiscoveryFileSnapshot, AgentBridgeDiscoveryReader, Bool, Date (+19 more)

### Community 86 - "AgentEventType"
Cohesion: 0.07
Nodes (30): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+22 more)

### Community 87 - "CodexRolloutRecoveryParser"
Cohesion: 0.07
Nodes (31): CodexRolloutRecoveryAdapter, CodexRolloutRecoveryError, invalidUsage, malformedRecord, missingSession, unsupportedRecord, CodexRolloutRecoveryParser, Any (+23 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.07
Nodes (31): 2026-07-05 - Phase 8C.10 Gesture Responsiveness And Artwork Flip, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, LauncherShortcut, ShortcutsStore, .shortcuts, String, UUID (+23 more)

### Community 89 - "AgentRelayCommandTests"
Cohesion: 0.11
Nodes (13): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000) (+5 more)

### Community 90 - "AudioVisualizerView"
Cohesion: 0.14
Nodes (16): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing (+8 more)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - ".makeSession"
Cohesion: 0.08
Nodes (22): AgentLocalRepositoryChoice, .id, AgentProjectSessionSummary, AgentSessionLauncherProjection, AgentSessionLauncherView, .body, .currentSessionIDs, .liveSessions (+14 more)

### Community 94 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 95 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 96 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 97 - ".normalize"
Cohesion: 0.13
Nodes (9): CodexHookNormalizer, Any, Bool, Date, Int, String, capability, CodexHookNormalizerTests (+1 more)

### Community 103 - ".progress"
Cohesion: 0.22
Nodes (6): Double, TimerProgressColorStage, high, low, mid, TimerProgressFormattingTests

### Community 104 - "AgentInteractiveCapability"
Cohesion: 0.05
Nodes (40): AgentDiscoveredSessionDescriptor, AgentDiscoveredSessionRuntimeState, active, idle, notLoaded, systemError, AgentInteractiveCapability, accountUsage (+32 more)

### Community 105 - "AgentEvent"
Cohesion: 0.07
Nodes (20): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, Bool, Date, Int (+12 more)

### Community 107 - "LiveActivitySettingsSubscriberTests"
Cohesion: 0.25
Nodes (3): LiveActivitySettingsSubscriberTests, String, UserDefaults

### Community 108 - "ShelfFileTile"
Cohesion: 0.13
Nodes (16): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 4C Tray File Actions Context Menu, EmptyMediaLauncherView, .body, FileShelfActions, MediaLauncherButton, .body, .body (+8 more)

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.24
Nodes (7): FileDropPolicy, FileShelfTemporaryStorage, Bool, String, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "AgentPresentationTests"
Cohesion: 0.07
Nodes (15): AgentOperationAggregation, AgentUsagePresentation, .gaugeProgress, .gaugeValueText, .isQuotaUsage, .isStale, .progress, Bool (+7 more)

### Community 111 - "ServerFactorySpy"
Cohesion: 0.11
Nodes (27): AgentBridgeNetworkError, listenerCancelled, listenerFailed, missingPort, AgentBridgeLifecycleTests, DeferredServerSpy, .startCount, DiscoverySpy (+19 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.11
Nodes (19): AgentBridgeEnvelopeError, emptyBatch, eventTooLarge, generationConflict, invalidAuthority, invalidCapability, invalidEventType, invalidPayload (+11 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.17
Nodes (12): DispatchQueue, Network, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, AgentBridgeServing (+4 more)

### Community 114 - "CodexAppServerProvider"
Cohesion: 0.10
Nodes (9): CodexAppServerProvider, Any, Date, Double, Set, String, CodexAppServerClientTests, String (+1 more)

### Community 115 - "ClaudeInteractiveProvider"
Cohesion: 0.13
Nodes (5): ClaudeInteractiveProvider, Bool, Int, Set, String

### Community 116 - ".assertFailure"
Cohesion: 0.17
Nodes (3): AgentBridgeHTTPParserTests, StaticString, UInt

### Community 117 - "Foundation"
Cohesion: 0.08
Nodes (6): AgentBridgeShared, ClaudeHookShared, CodexHookShared, Darwin, Foundation, IOKit.ps

### Community 118 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 119 - "AgentUsage"
Cohesion: 0.09
Nodes (27): CodingKey, AgentUsage, .allSamples, .isEmpty, .samples, .scopedEntries, AgentUsageMetric, cachedInputTokens (+19 more)

### Community 120 - ".parse"
Cohesion: 0.10
Nodes (18): CryptoKit, ClaudeTranscriptRecoveryAdapter, ClaudeTranscriptRecoveryError, malformedRecord, missingSession, unsupportedRecord, ClaudeTranscriptRecoveryParser, OperationKind (+10 more)

### Community 121 - ".openActiveMediaSource"
Cohesion: 0.17
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 122 - "AgentBridge"
Cohesion: 0.22
Nodes (10): Runtime, AgentBridge, LaunchMaterial, ProducerRuntime, Runtime, AgentBridgeServerFactory, Error, UUID (+2 more)

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.10
Nodes (20): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 3. Component boundaries, 4. Per-event authority, 5. Local bridge decision, 6. Privacy and security boundaries (+12 more)

### Community 124 - "AgentEventStoreLimits"
Cohesion: 0.08
Nodes (22): AgentEventApplication, applied, duplicate, ignoredAfterTerminal, ignoredWeakerEvidence, rejected, staleGeneration, AgentEventBatchApplication (+14 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.11
Nodes (18): 3. Phase gates, A0 — Research and architecture, A10 — Source app/editor association and Open action, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2.1 — Ingestion coordination and source registry, A2.2 — Relay client and append-only ingestion primitives, A2 — Authenticated local Agent Bridge (+10 more)

### Community 127 - "Agent Capability Matrix"
Cohesion: 0.12
Nodes (16): 1. Method and version boundary, 2. Primary supported integration surfaces, 3. Capability matrix, 4. Event-specific authority, 5. Local storage audit (content redacted), 6. Source application association, 7. Design implications, 8. Official sources (+8 more)

### Community 128 - "Agent Event Schema Draft"
Cohesion: 0.12
Nodes (16): 2. State vocabulary, 3. Session identity, 4. Normalized event types, 5. Versioned transport envelope, 6. Capability model, 7. Privacy projection, 8. Replay fixture contract, 9. Deferred decisions (+8 more)

### Community 129 - "AgentActivityGlowCoordinator"
Cohesion: 0.22
Nodes (6): AgentActivityGlowCoordinator, Never, Task, TimeInterval, Void, AgentActivityGlowCoordinatorTests

### Community 130 - "AgentBridgeNetworkExchange"
Cohesion: 0.24
Nodes (8): AgentBridgeNetworkExchange, AgentBridgeNetworkTransport, Duration, NWConnection, Result, UInt16, Void, AgentBridgeClientResponse

### Community 131 - ".signedRequest"
Cohesion: 0.31
Nodes (4): AgentBridgeHTTPRequest, AgentBridgeAuthenticationTests, AgentBridgeTestSupport, Int64

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "Error"
Cohesion: 0.04
Nodes (53): Error, AgentBridgeClientTransportError, connectTimedOut, malformedResponse, requestTimedOut, responseTooLarge, unavailable, AgentBridgeDiscoveryReadError (+45 more)

### Community 134 - "Data"
Cohesion: 0.10
Nodes (12): Security, AgentBridgeRequestAuthentication, Data, Bool, Int, Int64, String, CodexHookStandardInput (+4 more)

### Community 135 - "IslandHostingView"
Cohesion: 0.07
Nodes (24): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, NSHostingView, NSSize, NSTrackingArea (+16 more)

### Community 136 - "IslandLayoutStore"
Cohesion: 0.20
Nodes (8): 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, Composition, state and settings, IslandModule, IslandLayoutStore, Bool, CGFloat, CGRect, CGSize

### Community 137 - ".reload"
Cohesion: 0.23
Nodes (3): Bool, T, UserDefaults

### Community 139 - "AgentBridgeClientError"
Cohesion: 0.12
Nodes (16): AgentBridgeClientError, authenticationFailed, discoveryUnavailable, invalidInput, malformedResponse, timedOut, transportUnavailable, AttemptError (+8 more)

### Community 140 - "CompactIslandView"
Cohesion: 0.07
Nodes (38): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, AgentCompactRoutineLeadingView, .body (+30 more)

### Community 141 - "NetworkCounters"
Cohesion: 0.16
Nodes (8): ifaddrs, NetworkCounters, Self, TimeInterval, Interface, NetworkCounterSamplingTests, UInt32, UnsafeMutablePointer

### Community 142 - "AgentRelayExitCode"
Cohesion: 0.10
Nodes (19): Int32, AgentRelayCommand, AgentRelayCommandResult, AgentRelayExitCode, accepted, authenticationFailed, bridgeUnavailable, discoveryUnavailable (+11 more)

### Community 143 - "AgentBridgeEnvelopeBuildError"
Cohesion: 0.11
Nodes (13): CoreFoundation, AgentBridgeEnvelopeBuilder, AgentBridgeEnvelopeBuildError, emptyBatch, emptyInput, eventTooLarge, inputTooLarge, malformedEnvelope (+5 more)

### Community 144 - "YouTubeMetadataProvider"
Cohesion: 0.30
Nodes (9): CodingKeys, authorName, thumbnailURL, title, OEmbedResponse, String, URL, YouTubeMetadata (+1 more)

### Community 145 - "AgentBridgeHTTPRequestParser"
Cohesion: 0.24
Nodes (10): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, Bool (+2 more)

### Community 146 - ".normalize"
Cohesion: 0.10
Nodes (16): ClaudeHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook, ClaudeHookNormalizer (+8 more)

### Community 147 - "SettingsSection"
Cohesion: 0.12
Nodes (16): SettingsSection, advanced, agents, appearance, clipboard, gestures, .id, island (+8 more)

### Community 148 - "AgentProducerPolicy"
Cohesion: 0.06
Nodes (37): AgentAuthorityDomain, activity, interaction, lifecycle, liveness, metadata, operation, usage (+29 more)

### Community 149 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 150 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 151 - "AgentState"
Cohesion: 0.13
Nodes (14): AgentState, completed, failed, idle, interrupted, .isTerminal, planning, planReady (+6 more)

### Community 152 - "SupportedApp"
Cohesion: 0.14
Nodes (14): SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName, edge, .fallbackPaths (+6 more)

### Community 153 - "AgentApprovalController"
Cohesion: 0.08
Nodes (34): AgentBridgePermissionDecision, allow, deny, AgentApprovalControlKey, AgentApprovalController, AgentApprovalControlRequest, .id, AgentApprovalControlResult (+26 more)

### Community 154 - "AgentBridgeIngress"
Cohesion: 0.11
Nodes (23): Decodable, AgentBridgeIngress, AgentBridgePermissionRequestProcessor, AgentBridgeRequestProcessor, Bool, Date, Result, String (+15 more)

### Community 155 - "CodexJSONValue"
Cohesion: 0.08
Nodes (25): CodexAppServerEvent, notification, serverRequest, CodexJSONValue, array, .arrayValue, bool, .boolValue (+17 more)

### Community 156 - "AgentInteractiveProviderEvent"
Cohesion: 0.15
Nodes (12): AgentInteractiveProviderEvent, accountUsageChanged, approvalRequested, normalized, providerFailure, threadAvailable, transcript, transcriptDelta (+4 more)

### Community 157 - "MediaController.swift"
Cohesion: 0.08
Nodes (29): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, Index, Array, ArtworkFlipPhase, firstHalf, idle, secondHalf, ArtworkFlipPresentationEffect (+21 more)

### Community 158 - "AgentManagedSessionController"
Cohesion: 0.07
Nodes (31): S, AgentInteractiveProvider, AgentManagedSessionDescriptor, .sessionID, AgentManagedTranscriptEntry, AgentManagedSessionController, .accountUsage, .activeManagedSessionIDs (+23 more)

### Community 159 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 160 - "AgentEventValidationError"
Cohesion: 0.15
Nodes (13): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+5 more)

### Community 161 - "AgentEventPayload"
Cohesion: 0.11
Nodes (33): AgentBridgeWirePayload, .populatedFieldCount, AgentApprovalRequest, AgentApprovalResolution, AgentCommandEvent, AgentEventPayload, activity, approvalRequest (+25 more)

### Community 162 - "Claude Managed Control Review — 2026-09-27"
Cohesion: 0.15
Nodes (12): 10. Phase 6 recommendation, 1. Supported official mechanism, 2. Transport and API, 3. Lifecycle and session semantics, 4. Streaming visible responses and tool events, 5. Approvals and user input, 6. Model control, 7. Usage and context (+4 more)

### Community 163 - "AgentEventStore"
Cohesion: 0.12
Nodes (12): State ownership, AgentEventStore, AgentIngestionCoordinator, CheckedContinuation, Never, StoreSink, AgentManagedSessionControllerTests, PersistentSnapshotFakeProvider (+4 more)

### Community 164 - "AgentBridgeHTTPStatus"
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 165 - "AppLaunchService"
Cohesion: 0.44
Nodes (4): AppLaunchService, Bool, String, URL

### Community 166 - "ClaudeCodeStreamingClient"
Cohesion: 0.21
Nodes (10): ClaudeCodeStreamingClient, Run, AsyncStream, Never, Pipe, Process, String, Task (+2 more)

### Community 167 - "ObservableObject"
Cohesion: 0.29
Nodes (6): ObservableObject, AgentIntegrationDiagnosticsController, AgentWorkspaceSelection, AnyCancellable, Set, .selectedSession

### Community 168 - ".session"
Cohesion: 0.26
Nodes (6): AgentSourceAssociationResolver, AgentSourceOpenTarget, String, AgentSourceAssociationTests, Set, String

### Community 169 - "IslandSurfaceBackground"
Cohesion: 0.11
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 170 - "Agent Activity Feature Phase Plan"
Cohesion: 0.20
Nodes (10): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, A3.1 implementation refinement — Codex structured recovery, A3 implementation refinement — Codex authoritative hooks, A4.1 implementation refinement — Claude transcript recovery, A4.5 implementation refinement — bounded OTLP JSON enrichment (+2 more)

### Community 171 - "CodexAppServerClient"
Cohesion: 0.13
Nodes (15): .data, CodexAppServerClient, rpcError, transportClosed, object, PendingRequest, AsyncStream, CheckedContinuation (+7 more)

### Community 172 - "AgentPromptTextView"
Cohesion: 0.28
Nodes (4): NSTextView, AgentPromptTextView, NSEvent, NSRect

### Community 173 - "Agent Workspace Execution Plan — 2026-09-27"
Cohesion: 0.14
Nodes (13): Agent Workspace Execution Plan — 2026-09-27, Frozen invariants, Iteration rule, Phase 1 — Gesture-safe session scrolling, Phase 2 — Agents-specific expanded geometry, Phase 3.5 — Real-device workspace stabilization, Phase 3 — Enclosed workspace + session selection, Phase 4 — Embedded agent console UI (+5 more)

### Community 174 - "AgentSession"
Cohesion: 0.05
Nodes (61): .activeSessions, .sessionsRequiringAttention, .availableModels, Bool, AgentSession, .isActive, .isOpen, AgentDashboardLayoutProjection (+53 more)

### Community 175 - "ClaudeCodeStreamEnvelope"
Cohesion: 0.36
Nodes (4): ClaudeCodeStreamEnvelope, ClaudeCodeStreamEvent, message, transportFailed

### Community 176 - "LiveActivityStore"
Cohesion: 0.27
Nodes (6): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int, String

### Community 177 - "AgentSourceHealthRow"
Cohesion: 0.60
Nodes (3): AgentSourceHealthRow, .awaitingGuidance, .body

### Community 178 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 179 - "AnimationPreset"
Cohesion: 0.25
Nodes (8): AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow, subtle

### Community 180 - "AgentProducerHandle"
Cohesion: 0.07
Nodes (41): RawRepresentable, AgentEventProvenance, AgentIdentityConflict, AgentIngestionEvent, .sessionID, AgentIngestionLimits, AgentProducerDescriptor, AgentProducerEpoch (+33 more)

### Community 181 - "ControlledClipboardPersistence"
Cohesion: 0.22
Nodes (7): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, Bool, Int, TimeInterval

### Community 182 - "Fresh critical audit instructions"
Cohesion: 0.18
Nodes (9): Interpreter guard for subcommands, Path, Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits (+1 more)

### Community 183 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 184 - "String"
Cohesion: 0.27
Nodes (7): SystemStatsSnapshot, LiveStatusIndicator, .body, StatsPageView, .body, String, .trimmedForCollapsedPreview

### Community 185 - "AutoCollapseDelayPreset"
Cohesion: 0.25
Nodes (8): AutoCollapseDelayPreset, .displayName, fast, .id, .impliedSeconds, manual, normal, relaxed

### Community 186 - "OverlayWindowController.swift"
Cohesion: 0.33
Nodes (5): QuartzCore, ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicy

### Community 187 - "AgentConsoleBottomPositionPreferenceKey"
Cohesion: 0.38
Nodes (5): PreferenceKey, AgentConsoleBottomPositionPreferenceKey, AgentConsoleScrollRegionPreferenceKey, CGFloat, CGRect

### Community 188 - ".testRealListenerUsesLoopbackEphemeralPortAndIngestsSignedEvent"
Cohesion: 0.48
Nodes (3): HTTPURLResponse, AgentBridgeNetworkTests, URL

### Community 190 - "Claude Managed Control Review — 2026-09-28"
Cohesion: 0.33
Nodes (5): Capability matrix, Claude Managed Control Review — 2026-09-28, Identity and safety, Production decision, Scope

### Community 191 - "Codex Managed Model Control Review — 2026-09-28"
Cohesion: 0.33
Nodes (5): Codex Managed Model Control Review — 2026-09-28, Context, Inventory, Selection semantics, Verified sources

### Community 192 - "CodexAppServerError"
Cohesion: 0.22
Nodes (7): CodexAppServerError, executableNotFound, launchFailed, malformedMessage, notRunning, requestTimedOut, transportClosed

### Community 193 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

### Community 194 - "AgentIntegrationSetupError"
Cohesion: 0.17
Nodes (12): AgentIntegrationSetupError, backupInvalid, backupUnavailable, changedExternally, fileTooLarge, helperUnavailable, invalidHooks, invalidJSON (+4 more)

### Community 195 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 198 - "AgentApprovalPolicyMode"
Cohesion: 0.20
Nodes (9): Set, AgentApprovalPolicyKey, AgentApprovalPolicyMode, askEveryTime, autoApprove, .displayName, .isAutomatic, AgentApprovalPolicyState (+1 more)

### Community 202 - "AgentInteractiveRequestToken"
Cohesion: 0.15
Nodes (6): AgentInteractiveRequestToken, integer, string, Int64, Encoder, AsyncStream

### Community 209 - "IslandRootView.swift"
Cohesion: 0.06
Nodes (47): EnvironmentKey, Gesture, AgentNotchGlowBorder, .frameInterval, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier (+39 more)

### Community 210 - "AgentIntegrationOperationalState"
Cohesion: 0.13
Nodes (13): AgentIntegrationOperationalState, active, awaitingFirstEvent, blocked, degraded, failed, .label, notConfigured (+5 more)

### Community 215 - "XCTest"
Cohesion: 0.10
Nodes (6): Combine, DynamicIsland, Array, .single, Element, XCTest

## Knowledge Gaps
- **1245 isolated node(s):** `PackageDescription`, `package_app.sh script`, `unavailable`, `connectTimedOut`, `requestTimedOut` (+1240 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1645 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryPersistence`, `.reload`, `CompactIslandView`, `ClipboardHistoryStore`, `.normalizeAndSaveDouble`, `IslandNavigationStore`, `FileShelfStore`, `Change Log`, `Int`, `DynamicIslandLiveActivity`, `OverlayWindowController`, `AgentSessionInstanceID`, `AgentEventStore`, `MediaModuleView`, `View`, `ObservableObject`, `FileDropProviderLoaderTests`, `String`, `DynamicIsland Project Context`, `AppSettingsTests`, `CGFloat`, `AppKit`, `AnimationPreset`, `String`, `AutoCollapseDelayPreset`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `CaseIterable`, `AgentUISnapshotTests`, `AppDelegate`, `IslandRootView.swift`, `ShortcutsStore`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `AgentActivityGlowCoordinator`, `IslandGestureAction`, `.signedRequest`, `ArtworkFlipPresentationState`, `IslandRootView`, `Data`, `IslandEscapeRouter`, `UInt64`, `SystemClipboardPasteboardClient`, `NotchGeometryService`, `ClipboardHistoryStore`, `NetworkCounters`, `CollapsedLiveActivitySelectorTests`, `.start`, `.normalize`, `FileShelfStore`, `AgentProducerPolicy`, `AgentApprovalController`, `ClipboardHistoryEntry`, `MediaAutomationExecutor`, `ClipboardImageNormalizerTests`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `AgentSessionInstanceID`, `AgentEventStore`, `.session`, `FileDropProviderLoaderTests`, `AgentMCPObservationAdapter`, `.refresh`, `AppSettingsTests`, `CGFloat`, `AgentIntegrationSetupService`, `LiveActivityStore`, `AgentProducerHandle`, `RecordSink`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `.event`, `.sessionID`, `.testRealListenerUsesLoopbackEphemeralPortAndIngestsSignedEvent`, `AgentBridgeClient`, `ManualMediaRemoteDeadlineScheduler`, `.ingest`, `.makeProcessor`, `AgentUISnapshotTests`, `ExpandedScrollEventRoutingPolicyTests`, `DelimitedRecordFramer`, `ArtworkAccentColorCache`, `AgentAttentionEvent`, `SequenceClientTransport`, `AgentBridgeDiscoveryReader`, `CodexRolloutRecoveryParser`, `AgentRelayCommandTests`, `.makeSession`, `.normalize`, `.progress`, `AgentEvent`, `LiveActivitySettingsSubscriberTests`, `AgentPresentationTests`, `ServerFactorySpy`, `CodexAppServerProvider`, `.assertFailure`, `ClipboardHistoryPresentationState`, `.parse`, `.openActiveMediaSource`, `ClaudeInteractiveProviderTests`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **Why does `Data` connect `Data` to `AgentBridgeNetworkExchange`, `.signedRequest`, `ClipboardHistoryPersistence`, `SystemClipboardPasteboardClient`, `ClipboardHistoryPayload`, `ClipboardHistoryStore`, `AgentRelayExitCode`, `AgentBridgeEnvelopeBuildError`, `YouTubeMetadataProvider`, `AgentBridgeHTTPRequestParser`, `.normalize`, `AgentApprovalController`, `ClipboardHistoryEntry`, `ClipboardImageNormalizerTests`, `AgentBridgeAuthenticator`, `AppendOnlyRecordTailer`, `ClaudeCodeStreamingClient`, `FileDropProviderLoaderTests`, `AgentMCPObservationAdapter`, `CodexAppServerClient`, `AgentIntegrationSetupService`, `ControlledClipboardPersistence`, `FileClipboardHistoryPersistence`, `ClipboardPasteboardReadResult`, `RecordSink`, `.event`, `AgentBridgeClient`, `.decode`, `.makeProcessor`, `AgentBridgeClientProfile`, `.install`, `DelimitedRecordFramer`, `SequenceClientTransport`, `AgentBridgeDiscoveryReader`, `CodexRolloutRecoveryParser`, `AgentRelayCommandTests`, `.normalize`, `ServerFactorySpy`, `.assertFailure`, `.parse`, `AgentBridge`?**
  _High betweenness centrality (0.064) - this node is a cross-community bridge._
- **Are the 31 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 31 INFERRED edges - model-reasoned connections that need verification._
- **Are the 19 inferred relationships involving `AgentSession` (e.g. with `1. Domain contracts` and `.scheduleCompletion()`) actually correct?**
  _`AgentSession` has 19 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `unavailable` to the rest of the system?**
  _1245 weakly-connected nodes found - possible documentation gaps or missing edges._