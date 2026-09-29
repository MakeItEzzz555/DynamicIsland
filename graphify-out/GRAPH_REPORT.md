# Graph Report - DynamicIsland  (2026-09-29)

## Corpus Check
- 193 files · ~528,384 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 6313 nodes · 18835 edges · 198 communities (185 shown, 13 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 2683 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7166b1c8`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- AppSettings
- IslandGestureAction
- SystemStatsController
- ArtworkFlipPresentationState
- SettingsView
- IslandRootView
- AgentEventPayload
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
- Bool
- AgentIntegrationRouter
- Change Log
- SystemHUDController
- Identifiable
- DynamicIsland
- ClipboardHistoryEntry
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- OverlayWindowController
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- AgentProjectGroupPresentation
- Bool
- Data
- Phase Workflow For Future Work
- UInt64
- MediaModuleView
- ExpandedIslandView
- AgentEmbeddedConsoleView
- FileDropProviderLoader
- What You Must Do When Invoked
- AgentMCPObservationAdapter
- String
- .refresh
- IslandLayoutStore
- AppSettingsTests
- IslandRootView.swift
- AgentIntegrationSetupService
- AgentManagedTranscriptEntry
- SystemAgentNotificationFeedback
- AudioVisualizerView
- Sendable
- AgentEventValidationError
- String
- RecordSink
- ClipboardPasteboardReadResult
- OverlayPresentationSessionTests
- .event
- .sessionID
- CodexRolloutRecoveryAdapter
- AgentBridgeClient
- CollapsedPresentationProfile
- ManualMediaRemoteDeadlineScheduler
- CaseIterable
- .ingest
- .makeProcessor
- AgentBridgeClientProfile
- AgentUISnapshotTests
- LaunchAtLoginController.swift
- AgentIntegrationSetupTests
- ExpandedScrollEventRoutingPolicyTests
- AgentIntegrationProvider
- AppendOnlyRecordTailer.swift
- DelimitedRecordFramer
- .loadURL
- XCTestCase
- AgentEventType
- Meaningful regression history
- IslandSurfaceBackground
- AgentAttentionCoordinator
- Package.swift
- package_app.sh
- SequenceClientTransport
- .apply
- AgentBridgeDiscoveryReader
- Complete Droppy parity checklist
- CodexRolloutRecoveryParser
- ShortcutsStore
- AgentRelayCommandTests
- CodexRolloutSessionMonitor
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
- PersistentSnapshotFakeProvider
- AgentReplayHarness
- DROPPY_PARITY_MASTER_PLAN_2026-09-29.md
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
- AgentBridgeDiscoveryPublisher
- .parse
- .openActiveMediaSource
- AgentBridge
- Agent Activity Integration Architecture
- AgentEventStoreLimits
- 3. Phase gates
- ClaudeInteractiveProviderTests
- Agent Capability Matrix
- Agent Event Schema Draft
- Phase roadmap
- Phase 10 — Rich live activities
- .signedRequest
- MenuBarController
- Error
- .canonicalMessage
- IslandHostingView
- AgentApprovalPolicyMode
- .reload
- ControlledClipboardPersistence
- AgentBridgeEnvelopeBuildError
- CompactIslandView
- Phase 9 — Productivity extensions
- AgentRelayExitCode
- String
- AgentUsage
- MediaController
- .normalize
- SettingsSection
- Hashable
- Productivity extensions parity
- LockedValue
- AgentState
- SupportedApp
- AgentApprovalController
- AgentBridgeIngress
- CodexJSONValue
- .events
- MediaController.swift
- AgentManagedSessionController
- AgentNotch Reference Review
- Supplemental visual acceptance references — 2026-09-29
- .pause
- Claude Managed Control Review — 2026-09-27
- AgentEventStore
- FileClipboardHistoryPersistence
- Reference evidence
- ClaudeCodeStreamingClient
- ClaudeCodeStreamingError
- AppLaunchService
- AgentOTLPJSONError
- Agent Activity Feature Phase Plan
- CodexAppServerClient
- .allowsCollapsedDrop
- Agent Workspace Execution Plan — 2026-09-27
- AgentSession
- ClaudeCodeStreamEnvelope
- AppDelegate
- AgentIntegrationDiagnostics
- Architecture additions
- ClipboardHistoryPersistenceFinalizationResult
- AgentIngestionCoordinator
- AgentManagedInteractionState
- Fresh critical audit instructions
- Reminders / calendar / clock parity
- Claude Managed Control Review — 2026-09-28
- Codex Managed Model Control Review — 2026-09-28
- CodexAppServerError
- AgentIntegrationSetupError
- RecordingFileShelfDefaults
- CodexListedThread
- .resolve
- AgentIntegrationSetupState
- summary.md
- .loadFileURLs
- AgentInteractiveRequestToken
- String
- AgentIntegrationOperationalState
- Array

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 352 edges
2. `AgentSession` - 188 edges
3. `OverlayWindowController` - 147 edges
4. `AgentManagedSessionController` - 146 edges
5. `AgentEventStore` - 130 edges
6. `AgentIngestionCoordinator` - 117 edges
7. `Change Log` - 110 edges
8. `MediaController` - 105 edges
9. `AgentApprovalController` - 98 edges
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
- `A10 — Source app/editor association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift

## Import Cycles
- None detected.

## Communities (198 total, 13 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (166): AnyPublisher, Never, AppSettings, .activitiesEnabled, .agentActivityEnabled, .agentApprovalAlertsEnabled, .agentCompletionAlertsEnabled, .agentPeekDurationSeconds (+158 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.05
Nodes (49): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, CoreGraphics, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter (+41 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.07
Nodes (23): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+15 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.20
Nodes (7): ArtworkFlipPresentationState, .queuedSnapshot, ArtworkPresentationSnapshot, QueuedTransition, ArtworkFlipPresentationStateTests, Bool, String

### Community 4 - "SettingsView"
Cohesion: 0.14
Nodes (29): content, HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsView (+21 more)

### Community 5 - "IslandRootView"
Cohesion: 0.06
Nodes (38): Animation, 2026-07-04 - Phase 5J Single Visual Surface Morph, 2026-07-04 - Phase 6A Single Adaptive Island Panel, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, CollapsedPreviewRowContent, ExpandedHeaderButton, ExpandedIslandPageButton (+30 more)

### Community 6 - "AgentEventPayload"
Cohesion: 0.11
Nodes (36): AgentBridgeWirePayload, .populatedFieldCount, AgentActivityDescriptor, AgentApprovalRequest, AgentApprovalResolution, AgentCommandEvent, AgentEventPayload, activity (+28 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.12
Nodes (15): ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date, Int (+7 more)

### Community 8 - "TimerController"
Cohesion: 0.11
Nodes (19): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration (+11 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.12
Nodes (9): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, ClipboardPasteboardWriteResult, Bool, Int, SystemClipboardPasteboardClient, .changeCount (+1 more)

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.09
Nodes (22): AnyObject, Bool, Duration, Never, String, Task, TimeInterval, Void (+14 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.07
Nodes (30): ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint, ClipboardHistoryPayload, .byteCount (+22 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.09
Nodes (22): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth (+14 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.17
Nodes (8): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Date, String, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.09
Nodes (16): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedWidth, .contentStaggerAmount, .expandedHeight (+8 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.06
Nodes (24): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Any (+16 more)

### Community 16 - "IslandNavigationStore"
Cohesion: 0.11
Nodes (18): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, ExpandedIslandPage, .accessibilityLabel, agents, island, stats (+10 more)

### Community 17 - ".start"
Cohesion: 0.26
Nodes (5): MockTimerNotificationCenterClient, Bool, String, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (14): 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge, .body (+6 more)

### Community 19 - "Bool"
Cohesion: 0.14
Nodes (3): Bool, Date, NSEvent

### Community 20 - "AgentIntegrationRouter"
Cohesion: 0.05
Nodes (46): Comparable, AgentIngestionError, capabilityCapacity, generationConflict, identityConflict, invalidDescriptor, invalidEvent, invalidProducer (+38 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (54): 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish (+46 more)

### Community 22 - "SystemHUDController"
Cohesion: 0.09
Nodes (22): AudioObjectID, AudioToolbox, CoreAudio, Float32, IOKit, IOKit.graphics, Any, Bool (+14 more)

### Community 23 - "Identifiable"
Cohesion: 0.09
Nodes (22): Identifiable, AgentConsoleEntry, AgentConsoleEntryKind, agent, approval, command, error, plan (+14 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (36): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+28 more)

### Community 25 - "ClipboardHistoryEntry"
Cohesion: 0.11
Nodes (19): Calendar, Phase 13B.2 - Native In-Island Clipboard Interface, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body (+11 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (49): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+41 more)

### Community 27 - "Int"
Cohesion: 0.10
Nodes (15): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .collapsedSize (+7 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.06
Nodes (42): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, system, timer (+34 more)

### Community 29 - "OverlayWindowController"
Cohesion: 0.08
Nodes (28): CFTimeInterval, 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12B - Native Overlay Cleanup And Runtime Optimization, DispatchWorkItem, NSPanel, NSPoint, Native overlay, geometry and input (+20 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (11): CFDictionary, CGImageSource, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int, ClipboardImageNormalizerTests (+3 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (4): MediaArbitratorTests, Bool, NSImage, String

### Community 32 - "AgentProjectGroupPresentation"
Cohesion: 0.10
Nodes (21): AgentDashboardPresentation, AgentProjectGroupPresentation, .primarySessions, .recentSessions, .showsRecentSection, .subagentCount, AgentSessionRowEmphasis, attention (+13 more)

### Community 34 - "Data"
Cohesion: 0.10
Nodes (17): OSStatus, Data, AgentBridgeAuthenticator, .rememberedNonceCount, AgentBridgeCredentialError, invalidStoredSecret, keychain, randomGeneration (+9 more)

### Community 35 - "Phase Workflow For Future Work"
Cohesion: 0.09
Nodes (25): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration (+17 more)

### Community 36 - "UInt64"
Cohesion: 0.12
Nodes (15): DispatchSourceFileSystemObject, NoticeHandler, RecordHandler, A2.1 ingress boundary and A2.2 handoff, AppendOnlyFileIdentity, AppendOnlyRecordTailer, AppendOnlyRecordTailerHealth, AppendOnlyRecordTailerSignalToken (+7 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.07
Nodes (28): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, .body, MediaLauncherButton, .body, MediaModuleView, .activePlayerView (+20 more)

### Community 38 - "ExpandedIslandView"
Cohesion: 0.04
Nodes (59): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor, 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix, 2026-07-04 - Phase 6A.2 Single-Panel Native Morph Correction, 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership, 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, Phase 12A - Final Island Content Transition Sequencing (+51 more)

### Community 39 - "AgentEmbeddedConsoleView"
Cohesion: 0.04
Nodes (50): NSObject, NSScrollView, NSTextView, NSTextViewDelegate, NSViewRepresentable, PreferenceKey, AgentApprovalPresentation, AgentConsoleApprovalRow (+42 more)

### Community 40 - "FileDropProviderLoader"
Cohesion: 0.19
Nodes (11): FileDropProviderLoader, UTType, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, String (+3 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "AgentMCPObservationAdapter"
Cohesion: 0.06
Nodes (45): Decodable, AgentMCPAdapterError, invalidIdentity, invalidSchema, invalidUsage, malformedJSON, payloadTooLarge, unsupportedObservation (+37 more)

### Community 43 - "String"
Cohesion: 0.12
Nodes (16): Decision, MediaArbitrator, MediaArtworkFlipDirection, next, previous, MediaArtworkFlipRequest, .isExpired, MediaCandidate (+8 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandLayoutStore"
Cohesion: 0.05
Nodes (39): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, App Entry (+31 more)

### Community 46 - "AppSettingsTests"
Cohesion: 0.09
Nodes (3): AppSettingsTests, String, UserDefaults

### Community 47 - "IslandRootView.swift"
Cohesion: 0.04
Nodes (56): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, EnvironmentKey, Gesture, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline (+48 more)

### Community 48 - "AgentIntegrationSetupService"
Cohesion: 0.16
Nodes (11): AgentIntegrationBackupEnvelope, AgentIntegrationSetupPaths, AgentIntegrationSetupService, .fileManager, AgentIntegrationSetupSnapshot, Bool, FileManager, Int (+3 more)

### Community 49 - "AgentManagedTranscriptEntry"
Cohesion: 0.13
Nodes (13): AgentManagedTranscriptEntry, AgentManagedTranscriptRole, agent, command, error, plan, status, tool (+5 more)

### Community 51 - "AudioVisualizerView"
Cohesion: 0.14
Nodes (16): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing (+8 more)

### Community 52 - "Sendable"
Cohesion: 0.04
Nodes (103): Codable, Equatable, 1. Domain contracts, Sendable, AgentBridgeHealth, AgentBridgeIngestionResult, AgentBridgeState, degraded (+95 more)

### Community 53 - "AgentEventValidationError"
Cohesion: 0.09
Nodes (15): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+7 more)

### Community 54 - "String"
Cohesion: 0.31
Nodes (5): .result, invalidResponse, CodexManagedThread, Int, String

### Community 55 - "RecordSink"
Cohesion: 0.17
Nodes (12): AppendOnlyRecordTailerTests, Fixture, NoticeSink, .values, openDescriptorCount(), RecordSink, .strings, Bool (+4 more)

### Community 56 - "ClipboardPasteboardReadResult"
Cohesion: 0.10
Nodes (22): ImageIO, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image, ready (+14 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".event"
Cohesion: 0.19
Nodes (12): Success, AgentIngestionCoordinatorTests, Array, .single, Element, Result, Set, StaticString (+4 more)

### Community 59 - ".sessionID"
Cohesion: 0.16
Nodes (9): AgentReductionResult, AgentEventReducerTests, Set, String, TimeInterval, AgentTestFixture, Int, String (+1 more)

### Community 60 - "CodexRolloutRecoveryAdapter"
Cohesion: 0.27
Nodes (6): AppendOnlyRecordStartPolicy, boundedCatchUp, fromEnd, CodexRolloutRecoveryAdapter, Bool, URL

### Community 61 - "AgentBridgeClient"
Cohesion: 0.10
Nodes (21): AgentBridgeClient, AgentBridgeClientResult, accepted, rejected, AgentBridgeClientTransport, AgentBridgeNetworkExchange, AgentBridgeNetworkTransport, Bool (+13 more)

### Community 62 - "CollapsedPresentationProfile"
Cohesion: 0.13
Nodes (15): CustomStringConvertible, AgentCollapsedShellPresentation, CollapsedPresentationKind, agentAttention, agentRoutine, normal, CollapsedPresentationProfile, .minimumFloatingWidth (+7 more)

### Community 63 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.06
Nodes (43): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending, MediaRemoteClient (+35 more)

### Community 64 - "CaseIterable"
Cohesion: 0.04
Nodes (54): CaseIterable, 2026-07-11 - Phase 9D Theme Simplification, AgentApprovalPolicyChoice, askEveryTime, autoApprove, AnimationPreset, .displayName, .id (+46 more)

### Community 65 - ".ingest"
Cohesion: 0.17
Nodes (4): AgentEventStoreTests, Int, String, TimeInterval

### Community 66 - ".makeProcessor"
Cohesion: 0.26
Nodes (6): AgentBridgeEnvelopeIntegrationTests, StaticString, String, UInt, Any, String

### Community 67 - "AgentBridgeClientProfile"
Cohesion: 0.16
Nodes (10): AgentBridgeClientProfile, AgentBridgeDiscoveryRecord, AgentBridgeProtocol, Date, Int, Int32, String, UInt16 (+2 more)

### Community 68 - "AgentUISnapshotTests"
Cohesion: 0.18
Nodes (10): AnyView, AgentWorkspaceVerticalLayoutProjection, CGFloat, AgentUISnapshotTests, Bool, CGSize, Color, String (+2 more)

### Community 69 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 70 - "AgentIntegrationSetupTests"
Cohesion: 0.19
Nodes (4): AgentHookConfigurationPlanner, Any, AgentIntegrationSetupTests, String

### Community 71 - "ExpandedScrollEventRoutingPolicyTests"
Cohesion: 0.07
Nodes (21): QuartzCore, IslandCanvasCoordinateSpace, ExpandedContentScrollSequenceOwnership, ExpandedContentScrollSequencePhase, momentumBegan, momentumCancelled, momentumChanged, momentumEnded (+13 more)

### Community 72 - "AgentIntegrationProvider"
Cohesion: 0.19
Nodes (11): AgentIntegrationProvider, claude, codex, .desiredEvents, .displayName, .helperExecutableName, .id, .synchronousEvents (+3 more)

### Community 73 - "AppendOnlyRecordTailer.swift"
Cohesion: 0.08
Nodes (25): Dispatch, AppendOnlyRecordLimits, AppendOnlyRecordTailerFailure, identityRace, ioFailure, notRegularFile, parentUnavailable, permissionDenied (+17 more)

### Community 74 - "DelimitedRecordFramer"
Cohesion: 0.20
Nodes (7): BoundedRecordRing, .orderedRecords, DelimitedRecordFramer, Output, Int, Void, DelimitedRecordFramerTests

### Community 75 - ".loadURL"
Cohesion: 0.21
Nodes (6): NSSecureCoding, FileDropURLAccumulator, .urls, SendableItemProvider, NSItemProvider, TimeInterval

### Community 76 - "XCTestCase"
Cohesion: 0.07
Nodes (25): E, AgentActivityGlowCoordinator, Never, Task, TimeInterval, Void, AgentSourceAssociationResolver, AgentSourceOpenTarget (+17 more)

### Community 77 - "AgentEventType"
Cohesion: 0.03
Nodes (64): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+56 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - "IslandSurfaceBackground"
Cohesion: 0.06
Nodes (35): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool (+27 more)

### Community 80 - "AgentAttentionCoordinator"
Cohesion: 0.06
Nodes (40): 7. Attention presentation contract, AgentAttentionCoordinator, Date, Never, Task, TimeInterval, Void, AgentAttentionGeneration (+32 more)

### Community 83 - "SequenceClientTransport"
Cohesion: 0.16
Nodes (13): AgentBridgeEnvelopeBuilder, Any, String, AgentBridgeClientRequest, AgentBridgeSharedClientTests, Outcome, failure, response (+5 more)

### Community 84 - ".apply"
Cohesion: 0.13
Nodes (11): AgentEventReducer, SemanticResult, applied, rejected, Bool, Date, String, Value (+3 more)

### Community 85 - "AgentBridgeDiscoveryReader"
Cohesion: 0.08
Nodes (27): dev_t, ino_t, AgentBridgeClientProfileProviding, AgentBridgeDiscoveryFileReading, AgentBridgeDiscoveryFileSnapshot, AgentBridgeDiscoveryReader, Bool, Date (+19 more)

### Community 86 - "Complete Droppy parity checklist"
Cohesion: 0.13
Nodes (15): Agents parity / beyond Droppy, Capture parity, Clipboard parity, Complete Droppy parity checklist, Conversion / smart export parity, Core notch / shell behavior, Extension / integration parity, File Shelf parity (+7 more)

### Community 87 - "CodexRolloutRecoveryParser"
Cohesion: 0.17
Nodes (9): CodexRolloutRecoveryParser, Any, Date, Double, Int, Set, String, AsyncStream (+1 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.12
Nodes (15): LauncherShortcut, ShortcutsStore, .shortcuts, String, UUID, ShortcutsModuleView, .body, .displayedShortcuts (+7 more)

### Community 89 - "AgentRelayCommandTests"
Cohesion: 0.11
Nodes (13): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000) (+5 more)

### Community 90 - "CodexRolloutSessionMonitor"
Cohesion: 0.17
Nodes (14): CodexRolloutCandidate, CodexRolloutSessionDiscovery, CodexRolloutSessionMonitor, Date, Duration, FileManager, Int, Never (+6 more)

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
Cohesion: 0.07
Nodes (22): CodexHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook, CodexHookNormalizer (+14 more)

### Community 103 - ".progress"
Cohesion: 0.21
Nodes (7): Double, TimerProgressColorStage, high, low, mid, TimerProgressFormatting, TimerProgressFormattingTests

### Community 104 - "PersistentSnapshotFakeProvider"
Cohesion: 0.05
Nodes (47): AgentDiscoveredSessionDescriptor, AgentDiscoveredSessionRuntimeState, active, idle, notLoaded, systemError, AgentInteractiveCapability, accountUsage (+39 more)

### Community 105 - "AgentReplayHarness"
Cohesion: 0.13
Nodes (11): AgentReplayFixture, AgentReplayHarness, AgentReplayResult, .finalAttentionEvents, .finalSessions, AgentReplayStepResult, Int, String (+3 more)

### Community 106 - "DROPPY_PARITY_MASTER_PLAN_2026-09-29.md"
Cohesion: 0.14
Nodes (13): Already strong / preserve, Definition of complete parity, Gap matrix against current DynamicIsland, Implementation ordering rule, Licensing boundary, Missing, Partial, Phase dependency correction (+5 more)

### Community 107 - "LiveActivitySettingsSubscriberTests"
Cohesion: 0.25
Nodes (3): LiveActivitySettingsSubscriberTests, String, UserDefaults

### Community 108 - "ShelfFileTile"
Cohesion: 0.23
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, String (+1 more)

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.38
Nodes (4): FileShelfTemporaryStorage, Bool, String, URL

### Community 110 - "AgentPresentationTests"
Cohesion: 0.07
Nodes (11): AgentOperationAggregation, AgentWorkspaceSelection, Bool, Set, .selectedSession, .progressMetric, AgentPresentationTests, Date (+3 more)

### Community 111 - "ServerFactorySpy"
Cohesion: 0.10
Nodes (29): Network, AgentBridgeNetworkError, listenerCancelled, listenerFailed, missingPort, AgentBridgeServing, AgentBridgeLifecycleTests, DeferredServerSpy (+21 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.05
Nodes (45): AgentBridgeEnvelopeDecoder, Any, Int, AgentBridgeEnvelopeError, emptyBatch, eventTooLarge, generationConflict, invalidAuthority (+37 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.18
Nodes (11): DispatchQueue, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, NWConnection, Result (+3 more)

### Community 114 - "CodexAppServerProvider"
Cohesion: 0.11
Nodes (9): CodexAppServerProvider, Any, Date, Double, Set, String, CodexAppServerClientTests, String (+1 more)

### Community 115 - "ClaudeInteractiveProvider"
Cohesion: 0.14
Nodes (5): ClaudeInteractiveProvider, Bool, Int, Set, String

### Community 116 - ".assertFailure"
Cohesion: 0.11
Nodes (13): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, Bool (+5 more)

### Community 117 - "Foundation"
Cohesion: 0.05
Nodes (10): AgentBridgeShared, AppKit, ClaudeHookShared, CodexHookShared, Combine, Darwin, DynamicIsland, Foundation (+2 more)

### Community 118 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 119 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.15
Nodes (8): AgentBridgeDiscoveryPublisher, FileManager, String, URL, AgentBridgeDiscoveryTests, String, UInt16, URL

### Community 120 - ".parse"
Cohesion: 0.12
Nodes (13): ClaudeTranscriptRecoveryAdapter, ClaudeTranscriptRecoveryParser, OperationKind, command, tool, Any, Bool, Date (+5 more)

### Community 121 - ".openActiveMediaSource"
Cohesion: 0.17
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 122 - "AgentBridge"
Cohesion: 0.17
Nodes (13): HTTPURLResponse, Runtime, AgentBridge, LaunchMaterial, ProducerRuntime, Runtime, AgentBridgeServerFactory, Error (+5 more)

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.11
Nodes (18): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 5. Local bridge decision, 6. Privacy and security boundaries, 8. Expanded Agent Activity contract (+10 more)

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

### Community 129 - "Phase roadmap"
Cohesion: 0.14
Nodes (14): Phase 0 — Reference lock + parity inventory, Phase 11 — Actionable notifications and messaging, Phase 12 — Media parity completion, Phase 13 — Personalization / widget layout, Phase 14 — Release polish, Phase 1 — System HUD foundation, Phase 2 — Capture suite, Phase 3 — File Shelf 2.0 + drag quick-action orbit (+6 more)

### Community 130 - "Phase 10 — Rich live activities"
Cohesion: 0.18
Nodes (11): Agents, AirPods, Calendar / Meetings, Camera/microphone indicators, Clock, Downloads, File operations, Phase 10 — Rich live activities (+3 more)

### Community 131 - ".signedRequest"
Cohesion: 0.34
Nodes (4): AgentBridgeHTTPRequest, AgentBridgeAuthenticationTests, AgentBridgeTestSupport, Int64

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "Error"
Cohesion: 0.03
Nodes (63): CryptoKit, Error, Security, AgentBridgeClientTransportError, connectTimedOut, malformedResponse, requestTimedOut, responseTooLarge (+55 more)

### Community 134 - ".canonicalMessage"
Cohesion: 0.24
Nodes (7): AgentBridgeRequestAuthentication, Bool, Int, Int64, String, AgentBridgeSharedCryptoTests, String

### Community 135 - "IslandHostingView"
Cohesion: 0.15
Nodes (10): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, Known Fragile Areas, NSHostingView, NSSize, NSTrackingArea, NSView, IslandHostingView, .intrinsicContentSize (+2 more)

### Community 136 - "AgentApprovalPolicyMode"
Cohesion: 0.22
Nodes (9): Set, AgentApprovalPolicyKey, AgentApprovalPolicyMode, askEveryTime, autoApprove, .displayName, .isAutomatic, AgentApprovalPolicyState (+1 more)

### Community 137 - ".reload"
Cohesion: 0.35
Nodes (3): Bool, T, UserDefaults

### Community 138 - "ControlledClipboardPersistence"
Cohesion: 0.22
Nodes (7): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, Bool, Int, TimeInterval

### Community 139 - "AgentBridgeEnvelopeBuildError"
Cohesion: 0.08
Nodes (25): CoreFoundation, AgentBridgeClientError, authenticationFailed, discoveryUnavailable, invalidInput, malformedResponse, timedOut, transportUnavailable (+17 more)

### Community 140 - "CompactIslandView"
Cohesion: 0.05
Nodes (64): 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, .body (+56 more)

### Community 141 - "Phase 9 — Productivity extensions"
Cohesion: 0.22
Nodes (9): Background Removal, Camera / Notchface, Finder + Alfred, High Alert / Keep Awake, Menu Bar Manager, Phase 9 — Productivity extensions, Terminal, Voice Transcribe (+1 more)

### Community 142 - "AgentRelayExitCode"
Cohesion: 0.10
Nodes (19): Int32, AgentRelayCommand, AgentRelayCommandResult, AgentRelayExitCode, accepted, authenticationFailed, bridgeUnavailable, discoveryUnavailable (+11 more)

### Community 143 - "String"
Cohesion: 0.14
Nodes (12): AgentOTLPJSONDecoder, AgentSessionContinuity, AgentTelemetryFusion, AgentTelemetryObservation, .isEmpty, Any, Date, Double (+4 more)

### Community 144 - "AgentUsage"
Cohesion: 0.06
Nodes (38): CodingKey, AgentUsage, .allSamples, .isEmpty, .samples, .scopedEntries, AgentUsageMetric, cachedInputTokens (+30 more)

### Community 145 - "MediaController"
Cohesion: 0.06
Nodes (29): 2026-07-05 - Phase 8C.10 Gesture Responsiveness And Artwork Flip, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, BrowserScriptTarget, MediaController, .currentArtworkPresentationIdentity, MediaPlayer (+21 more)

### Community 146 - ".normalize"
Cohesion: 0.11
Nodes (11): ClaudeHookNormalizer, ClaudeHookStandardInput, Any, Bool, Date, FileHandle, Int, String (+3 more)

### Community 147 - "SettingsSection"
Cohesion: 0.12
Nodes (16): SettingsSection, advanced, agents, appearance, clipboard, gestures, .id, island (+8 more)

### Community 148 - "Hashable"
Cohesion: 0.05
Nodes (60): Hashable, RawRepresentable, AgentAuthorityDomain, activity, interaction, lifecycle, liveness, metadata (+52 more)

### Community 149 - "Productivity extensions parity"
Cohesion: 0.22
Nodes (9): Background Removal, Camera / Notchface, Finder / Alfred / Shortcuts, Keep Awake / High Alert, Menu Bar Manager, Productivity extensions parity, Terminal, Voice Transcribe (+1 more)

### Community 150 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 151 - "AgentState"
Cohesion: 0.06
Nodes (40): AgentState, completed, failed, idle, interrupted, .isTerminal, planning, planReady (+32 more)

### Community 152 - "SupportedApp"
Cohesion: 0.14
Nodes (14): SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName, edge, .fallbackPaths (+6 more)

### Community 153 - "AgentApprovalController"
Cohesion: 0.09
Nodes (28): AgentBridgePermissionDecision, allow, deny, AgentApprovalControlKey, AgentApprovalController, AgentApprovalControlRequest, .id, AgentApprovalControlResult (+20 more)

### Community 154 - "AgentBridgeIngress"
Cohesion: 0.26
Nodes (7): AgentBridgeIngress, AgentBridgePermissionRequestProcessor, AgentBridgeRequestProcessor, Bool, Date, Result, String

### Community 155 - "CodexJSONValue"
Cohesion: 0.08
Nodes (18): CodexJSONValue, array, .arrayValue, bool, .boolValue, .doubleValue, integer, .intValue (+10 more)

### Community 157 - "MediaController.swift"
Cohesion: 0.08
Nodes (28): 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Index, Media and artwork, Array, ArtworkFlipPhase, firstHalf, idle (+20 more)

### Community 158 - "AgentManagedSessionController"
Cohesion: 0.07
Nodes (30): ObservableObject, S, AgentModelSelectionScope, turnAndSubsequent, AgentManagedSessionController, .accountUsage, .activeManagedSessionIDs, .interactiveCapabilities (+22 more)

### Community 159 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 160 - "Supplemental visual acceptance references — 2026-09-29"
Cohesion: 0.22
Nodes (9): Expanded Media — Playing Next, Live Activity layout architecture update, Media layout acceptance update, Queue-expanded, Settings preview additions, Side-by-side compact Live Activities, Standard, Supplemental recording observations (+1 more)

### Community 161 - ".pause"
Cohesion: 0.43
Nodes (3): 3. Lifecycle and session semantics, .timerControlRow, .timerControlStack

### Community 162 - "Claude Managed Control Review — 2026-09-27"
Cohesion: 0.17
Nodes (11): 10. Phase 6 recommendation, 1. Supported official mechanism, 2. Transport and API, 4. Streaming visible responses and tool events, 5. Approvals and user input, 6. Model control, 7. Usage and context, 8. History and discovery (+3 more)

### Community 163 - "AgentEventStore"
Cohesion: 0.20
Nodes (4): AgentEventStore, .activeSessions, .sessionsRequiringAttention, AgentManagedSessionControllerTests

### Community 164 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 165 - "Reference evidence"
Cohesion: 0.29
Nodes (7): DynamicIsland — Droppy-Parity Master Plan, Public source supports, Purpose, Reference evidence, Screen recording 1 observations, Screen recording 2 observations, User-requested parity beyond what is currently present in the public source

### Community 166 - "ClaudeCodeStreamingClient"
Cohesion: 0.21
Nodes (10): ClaudeCodeStreamingClient, Run, AsyncStream, Never, Pipe, Process, String, Task (+2 more)

### Community 167 - "ClaudeCodeStreamingError"
Cohesion: 0.29
Nodes (6): ClaudeCodeStreamingError, executableNotFound, launchFailed, malformedMessage, turnAlreadyRunning, unsupported

### Community 168 - "AppLaunchService"
Cohesion: 0.34
Nodes (6): 2026-07-03 - Common App Launch Resolver, AppLaunchService, Bool, String, URL, .body

### Community 169 - "AgentOTLPJSONError"
Cohesion: 0.33
Nodes (6): AgentOTLPJSONError, emptyPayload, excessiveCardinality, excessiveDepth, malformedJSON, payloadTooLarge

### Community 170 - "Agent Activity Feature Phase Plan"
Cohesion: 0.17
Nodes (10): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, A3.1 implementation refinement — Codex structured recovery, A3 implementation refinement — Codex authoritative hooks, A4.1 implementation refinement — Claude transcript recovery, A4.5 implementation refinement — bounded OTLP JSON enrichment (+2 more)

### Community 171 - "CodexAppServerClient"
Cohesion: 0.13
Nodes (17): CodexAppServerClient, rpcError, CodexAppServerEvent, notification, serverRequest, transportClosed, object, PendingRequest (+9 more)

### Community 172 - ".allowsCollapsedDrop"
Cohesion: 0.40
Nodes (3): FileDropPolicy, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 173 - "Agent Workspace Execution Plan — 2026-09-27"
Cohesion: 0.14
Nodes (13): Agent Workspace Execution Plan — 2026-09-27, Frozen invariants, Iteration rule, Phase 1 — Gesture-safe session scrolling, Phase 2 — Agents-specific expanded geometry, Phase 3.5 — Real-device workspace stabilization, Phase 3 — Enclosed workspace + session selection, Phase 4 — Embedded agent console UI (+5 more)

### Community 174 - "AgentSession"
Cohesion: 0.05
Nodes (76): Int, .availableModels, AgentSession, .isActive, .isOpen, AgentCompactPresentation, AgentDashboardLayoutProjection, AgentActivityDashboardView (+68 more)

### Community 175 - "ClaudeCodeStreamEnvelope"
Cohesion: 0.33
Nodes (4): ClaudeCodeStreamEnvelope, ClaudeCodeStreamEvent, message, transportFailed

### Community 176 - "AppDelegate"
Cohesion: 0.06
Nodes (33): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, NSWindowDelegate, 2. Existing DynamicIsland invariants (+25 more)

### Community 177 - "AgentIntegrationDiagnostics"
Cohesion: 0.26
Nodes (4): AgentIntegrationDiagnostics, AgentSourceHealthRow, .awaitingGuidance, .body

### Community 178 - "Architecture additions"
Cohesion: 0.40
Nodes (5): A. Island Feature Registry, Architecture additions, B. Integration Capability Registry, C. Unified Live Activity model, D. Background task/operation center

### Community 179 - "ClipboardHistoryPersistenceFinalizationResult"
Cohesion: 0.23
Nodes (9): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+1 more)

### Community 180 - "AgentIngestionCoordinator"
Cohesion: 0.07
Nodes (26): 3. Component boundaries, Adapter contract, State ownership, AgentIngestionCoordinator, Bool, CheckedContinuation, Date, Never (+18 more)

### Community 181 - "AgentManagedInteractionState"
Cohesion: 0.18
Nodes (11): AgentManagedInteractionState, .allowsPromptSubmission, .canInterrupt, checkingAttachment, connecting, failed, observed, ready (+3 more)

### Community 182 - "Fresh critical audit instructions"
Cohesion: 0.18
Nodes (9): Interpreter guard for subcommands, Path, Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits (+1 more)

### Community 183 - "Reminders / calendar / clock parity"
Cohesion: 0.50
Nodes (4): Calendar, Clock, Reminders, Reminders / calendar / clock parity

### Community 190 - "Claude Managed Control Review — 2026-09-28"
Cohesion: 0.33
Nodes (5): Capability matrix, Claude Managed Control Review — 2026-09-28, Identity and safety, Production decision, Scope

### Community 191 - "Codex Managed Model Control Review — 2026-09-28"
Cohesion: 0.33
Nodes (5): Codex Managed Model Control Review — 2026-09-28, Context, Inventory, Selection semantics, Verified sources

### Community 192 - "CodexAppServerError"
Cohesion: 0.25
Nodes (7): CodexAppServerError, executableNotFound, launchFailed, malformedMessage, notRunning, requestTimedOut, transportClosed

### Community 194 - "AgentIntegrationSetupError"
Cohesion: 0.17
Nodes (12): AgentIntegrationSetupError, backupInvalid, backupUnavailable, changedExternally, fileTooLarge, helperUnavailable, invalidHooks, invalidJSON (+4 more)

### Community 195 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 197 - "CodexListedThread"
Cohesion: 0.16
Nodes (10): CodexAvailableModel, CodexListedThread, CodexManagedTurn, CodexThreadItemEntry, String, .nilIfEmpty, Bool, Date (+2 more)

### Community 199 - "AgentIntegrationSetupState"
Cohesion: 0.29
Nodes (7): AgentIntegrationSetupState, blocked, configured, helperUnavailable, .label, needsSetup, repairRequired

### Community 201 - ".loadFileURLs"
Cohesion: 0.19
Nodes (9): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL, Bool, AirDropURLAccumulator, .urls, NSItemProvider (+1 more)

### Community 202 - "AgentInteractiveRequestToken"
Cohesion: 0.29
Nodes (4): AgentInteractiveRequestToken, integer, string, Int64

### Community 209 - "String"
Cohesion: 0.13
Nodes (20): SystemStatsSnapshot, AgentNotchGlowBorder, .frameInterval, .visualizerAccentColor, StatsLineChart, .body, StatsMetricCard, .body (+12 more)

### Community 210 - "AgentIntegrationOperationalState"
Cohesion: 0.13
Nodes (13): AgentIntegrationOperationalState, active, awaitingFirstEvent, blocked, degraded, failed, .label, notConfigured (+5 more)

### Community 215 - "Array"
Cohesion: 0.67
Nodes (3): Array, .single, Element

## Knowledge Gaps
- **1354 isolated node(s):** `PackageDescription`, `package_app.sh script`, `unavailable`, `connectTimedOut`, `requestTimedOut` (+1349 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1762 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `.reload`, `NotchGeometryService`, `CompactIslandView`, `.normalizeAndSaveDouble`, `ClipboardHistoryStoreTests`, `IslandNavigationStore`, `MediaController`, `FileShelfStore`, `SystemHUDController`, `Int`, `DynamicIslandLiveActivity`, `OverlayWindowController`, `AgentManagedSessionController`, `MediaModuleView`, `ExpandedIslandView`, `FileDropProviderLoader`, `String`, `.allowsCollapsedDrop`, `IslandLayoutStore`, `AppSettingsTests`, `IslandRootView.swift`, `AppDelegate`, `AgentSession`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `CaseIterable`, `AgentUISnapshotTests`, `String`, `ShortcutsStore`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`?**
  _High betweenness centrality (0.107) - this node is a cross-community bridge._
- **Why does `Data` connect `Data` to `.signedRequest`, `Error`, `.canonicalMessage`, `ClipboardHistoryStore`, `SystemClipboardPasteboardClient`, `ControlledClipboardPersistence`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `AgentRelayExitCode`, `String`, `.normalize`, `AgentApprovalController`, `ClipboardHistoryEntry`, `ClipboardImageNormalizerTests`, `UInt64`, `FileClipboardHistoryPersistence`, `ClaudeCodeStreamingClient`, `FileDropProviderLoader`, `AgentMCPObservationAdapter`, `CodexAppServerClient`, `AgentIntegrationSetupService`, `ClipboardHistoryPersistenceFinalizationResult`, `Sendable`, `RecordSink`, `ClipboardPasteboardReadResult`, `CodexRolloutRecoveryAdapter`, `AgentBridgeClient`, `.makeProcessor`, `AgentBridgeClientProfile`, `AgentIntegrationSetupTests`, `DelimitedRecordFramer`, `SequenceClientTransport`, `AgentBridgeDiscoveryReader`, `CodexRolloutRecoveryParser`, `AgentRelayCommandTests`, `.normalize`, `ServerFactorySpy`, `AgentBridgeEnvelopeError`, `.assertFailure`, `.parse`, `AgentBridge`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `IslandGestureAction`, `SystemStatsController`, `.signedRequest`, `ArtworkFlipPresentationState`, `.canonicalMessage`, `SystemClipboardPasteboardClient`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `String`, `CollapsedLiveActivitySelectorTests`, `.start`, `.normalize`, `FileShelfStore`, `Hashable`, `Identifiable`, `AgentApprovalController`, `ClipboardHistoryEntry`, `MediaAutomationExecutor`, `ClipboardImageNormalizerTests`, `MediaArbitratorTests`, `AgentEventStore`, `FileDropProviderLoader`, `AgentMCPObservationAdapter`, `.refresh`, `IslandLayoutStore`, `AppSettingsTests`, `IslandRootView.swift`, `AppDelegate`, `AgentIngestionCoordinator`, `AgentEventValidationError`, `RecordSink`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `.event`, `.sessionID`, `AgentBridgeClient`, `ManualMediaRemoteDeadlineScheduler`, `.ingest`, `.makeProcessor`, `AgentUISnapshotTests`, `AgentIntegrationSetupTests`, `.resolve`, `ExpandedScrollEventRoutingPolicyTests`, `DelimitedRecordFramer`, `IslandSurfaceBackground`, `AgentAttentionCoordinator`, `SequenceClientTransport`, `AgentBridgeDiscoveryReader`, `CodexRolloutRecoveryParser`, `AgentRelayCommandTests`, `CodexRolloutSessionMonitor`, `.makeSession`, `.normalize`, `.progress`, `AgentReplayHarness`, `LiveActivitySettingsSubscriberTests`, `AgentPresentationTests`, `ServerFactorySpy`, `CodexAppServerProvider`, `.assertFailure`, `ClipboardHistoryPresentationState`, `AgentBridgeDiscoveryPublisher`, `.parse`, `.openActiveMediaSource`, `AgentBridge`, `ClaudeInteractiveProviderTests`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Are the 32 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 32 INFERRED edges - model-reasoned connections that need verification._
- **Are the 19 inferred relationships involving `AgentSession` (e.g. with `1. Domain contracts` and `.scheduleCompletion()`) actually correct?**
  _`AgentSession` has 19 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `unavailable` to the rest of the system?**
  _1354 weakly-connected nodes found - possible documentation gaps or missing edges._