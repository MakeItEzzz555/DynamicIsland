# Graph Report - DynamicIsland  (2026-09-28)

## Corpus Check
- 180 files · ~506,461 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 5799 nodes · 17359 edges · 205 communities (188 shown, 17 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 2459 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2fe2b25c`
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
- .title
- FileDropProviderLoaderTests
- What You Must Do When Invoked
- YouTubeMetadataProvider
- String
- .refresh
- IslandLayoutStore
- AppSettingsTests
- CGFloat
- AgentIntegrationSetupService
- Bool
- CollapsedLiveActivityPrioritySource
- IslandRootView.swift
- Sendable
- .reload
- .opacity
- RecordSink
- ClipboardPasteboardReadResult
- OverlayPresentationSessionTests
- .event
- .sessionID
- AgentSession
- AgentBridgeClient
- DynamicIsland Project Context
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
- AgentBridgeDiscoveryPublisher
- AgentCapability
- Meaningful regression history
- .loadFileURLs
- AgentAttentionEvent
- Package.swift
- package_app.sh
- SequenceClientTransport
- AgentState
- AgentBridgeDiscoveryReader
- AgentEventType
- AgentEventValidationError
- ShortcutsStore
- AgentRelayCommandTests
- MediaCandidate
- graphify reference: query, path, explain
- Evidence-supported pre-audit risks
- NetworkCounters
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
- AgentEvent
- .ingestAtomically
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- .allowsCollapsedDrop
- AgentPresentationTests
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- AgentBridge
- ClaudeInteractiveProvider
- .assertFailure
- Foundation
- ClipboardHistoryPresentationState
- AgentUsage
- .parse
- AgentBridgeEnvelopeBuildError
- AgentBridgeIngress
- Agent Activity Integration Architecture
- .installAgentActivityObservers
- 3. Phase gates
- ClaudeCodeStreamingClient
- Agent Capability Matrix
- Agent Event Schema Draft
- IslandHostingView
- Error
- .signedRequest
- MenuBarController
- AgentBridgeDiscoveryReadError
- Data
- AgentBridgeModels.swift
- Agent Activity Feature Phase Plan
- .resolve
- AgentBridgeClientError
- SettingsWindowController
- .displayedStateLabel
- AgentRelayExitCode
- AgentNotch Reference Review
- ArtworkPresentationCoordinator
- .openActiveMediaSource
- .normalize
- IslandSurfaceBackground
- XCTestCase
- LaunchAtLoginController.swift
- LockedValue
- .remainingTime
- .normalize
- AgentSessionID
- AgentIngestionEvent
- CodexJSONValue
- ClaudeCodeStreamEnvelope
- CodexAppServerProvider
- AgentManagedSessionController
- NowPlayingMediaProvider
- String
- PersistentSnapshotFakeProvider
- Claude Managed Control Review — 2026-09-27
- AgentEventStore
- AgentIntegrationOperationalState
- Array
- Run
- CodexAppServerClient
- .session
- .ingest
- SwiftUI
- CodexAppServerError
- NowPlayingMediaProvider.swift
- Agent Workspace Execution Plan — 2026-09-27
- AgentSessionRowEmphasis
- ClipboardHistoryPersistenceFinalizationResult
- AgentIntegrationSetupError
- AgentBridgeHTTPStatus
- UInt64
- String
- IslandModules
- AgentInteractiveRequestToken
- AgentEmbeddedConsoleView
- .body
- String
- CollapsedPreviewKind
- Fresh critical audit instructions
- AgentIntegrationSetupState
- CodexListedThread
- .routine
- Claude Managed Control Review — 2026-09-28
- Codex Managed Model Control Review — 2026-09-28
- DedicatedTimerPageView
- .event
- FileClipboardHistoryPersistence
- ObservableObject
- CodexHookNormalizationError
- .events
- Array
- 3. Session identity
- summary.md
- AgentOTLPJSONError
- ClaudeCodeStreamingError
- .decode
- CodexRolloutRecoveryError

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 342 edges
2. `AgentSession` - 165 edges
3. `OverlayWindowController` - 147 edges
4. `AgentManagedSessionController` - 140 edges
5. `AgentEventStore` - 122 edges
6. `Change Log` - 110 edges
7. `AgentIngestionCoordinator` - 106 edges
8. `MediaController` - 105 edges
9. `AgentApprovalController` - 91 edges
10. `AgentProvider` - 85 edges

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

## Communities (205 total, 17 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (162): AnyPublisher, Never, AppSettings, .activitiesEnabled, .agentActivityEnabled, .agentApprovalAlertsEnabled, .agentCompletionAlertsEnabled, .agentPeekDurationSeconds (+154 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (39): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, IslandGestureAction, collapse, .displayName, expand, .id (+31 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.17
Nodes (9): 2026-07-04 - Phase 5D Stats Tab, Bool, Double, Int, Timer, SystemStatsController, .isPolling, SystemStatsHistory (+1 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.20
Nodes (7): ArtworkFlipPresentationState, .queuedSnapshot, ArtworkPresentationSnapshot, QueuedTransition, ArtworkFlipPresentationStateTests, Bool, String

### Community 4 - "SettingsView"
Cohesion: 0.14
Nodes (31): Owner, content, island, HelpText, .body, PriorityStepperRow, .body, SettingsGroup (+23 more)

### Community 5 - "IslandRootView"
Cohesion: 0.07
Nodes (33): 2026-07-04 - Phase 5J Single Visual Surface Morph, 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, CollapsedPreviewActivityRow, .iconColor, CollapsedPreviewContent, CollapsedPreviewRow (+25 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.12
Nodes (16): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date (+8 more)

### Community 8 - "TimerController"
Cohesion: 0.11
Nodes (18): ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration, Int (+10 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.10
Nodes (20): Bool, Duration, Never, String, Task, TimeInterval, Void, SystemTimerNotificationCenterClient (+12 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.07
Nodes (31): ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint, ClipboardHistoryPayload, .byteCount (+23 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.07
Nodes (33): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, NSEdgeInsets, NSScreen (+25 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.13
Nodes (15): ClipboardHistoryArchive, ClipboardHistoryStoreTests, ControlledClipboardPersistence, .data, .deleteCount, .saveCount, FakeClipboardPasteboardClient, MemoryClipboardPersistence (+7 more)

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (19): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+11 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.13
Nodes (5): CollapsedLiveActivitySelectorTests, Bool, Date, Int, String

### Community 16 - "IslandNavigationStore"
Cohesion: 0.09
Nodes (20): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, agents (+12 more)

### Community 17 - ".start"
Cohesion: 0.20
Nodes (8): TimerCompletionNotificationPreferences, MockTimerNotificationCenterClient, Bool, String, Void, TestError, schedulingFailed, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (15): 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge (+7 more)

### Community 19 - "SupportedApp"
Cohesion: 0.13
Nodes (20): 2026-07-03 - Common App Launch Resolver, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName (+12 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.15
Nodes (12): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, .expandedPageMorphDuration, ExpandedIslandView, .airDropTargetBinding, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation, .pageSwitchAnimation (+4 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (66): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish (+58 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (17): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+9 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (36): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+28 more)

### Community 25 - "ClipboardHistoryEntry"
Cohesion: 0.11
Nodes (18): Calendar, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body, .emptyState (+10 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (49): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+41 more)

### Community 27 - "Int"
Cohesion: 0.11
Nodes (12): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+4 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.12
Nodes (24): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+16 more)

### Community 29 - "OverlayWindowController"
Cohesion: 0.08
Nodes (26): CFTimeInterval, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5J.4 Final Media Fit And Mouse Leave Rect Fix, 2026-07-04 - Phase 5J.5 Final Expanded Hover Tolerance Tightening, 2026-07-11 - Phase 9C Liquid Glass Visual Repair, Phase 13B.2 - Native In-Island Clipboard Interface, DispatchWorkItem, NSPoint (+18 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (12): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int (+4 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (4): MediaArbitratorTests, Bool, NSImage, String

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.10
Nodes (19): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Any (+11 more)

### Community 33 - "AgentProducerHandle"
Cohesion: 0.09
Nodes (29): AgentIngestionLimits, AgentProducerHandle, AgentSourceHealthError, identityConflict, invalidEvent, policyRejected, producerFailure, schemaMismatch (+21 more)

### Community 34 - "AgentBridgeAuthenticator"
Cohesion: 0.08
Nodes (25): OSStatus, AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull (+17 more)

### Community 36 - "AppendOnlyRecordTailer"
Cohesion: 0.12
Nodes (14): DispatchSourceFileSystemObject, NoticeHandler, RecordHandler, A2.1 ingress boundary and A2.2 handoff, AppendOnlyFileIdentity, AppendOnlyRecordTailer, failure, AppendOnlyRecordTailerSignalToken (+6 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.04
Nodes (65): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, AlbumArtworkView, .body (+57 more)

### Community 38 - "Phase Workflow For Future Work"
Cohesion: 0.08
Nodes (24): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration (+16 more)

### Community 39 - ".title"
Cohesion: 0.24
Nodes (3): AgentPrivacyProjection, Int, String

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.18
Nodes (9): .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, String, URL, UserDefaults (+1 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "YouTubeMetadataProvider"
Cohesion: 0.30
Nodes (9): CodingKeys, authorName, thumbnailURL, title, OEmbedResponse, String, URL, YouTubeMetadata (+1 more)

### Community 43 - "String"
Cohesion: 0.09
Nodes (21): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, BrowserScriptTarget, Decision, MediaArtworkFlipDirection, next, previous, MediaArtworkFlipRequest, .isExpired (+13 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandLayoutStore"
Cohesion: 0.07
Nodes (27): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, App Entry, Current Architecture, Geometry (+19 more)

### Community 46 - "AppSettingsTests"
Cohesion: 0.10
Nodes (3): AppSettingsTests, String, UserDefaults

### Community 47 - "CGFloat"
Cohesion: 0.19
Nodes (10): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, IslandShellLayout, IslandShellRadii, IslandShellShape, .animatableData (+2 more)

### Community 48 - "AgentIntegrationSetupService"
Cohesion: 0.17
Nodes (12): AgentIntegrationBackupEnvelope, AgentIntegrationSetupPaths, AgentIntegrationSetupService, .fileManager, AgentIntegrationSetupSnapshot, Bool, FileManager, Int (+4 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.06
Nodes (43): EnvironmentKey, Left, Right, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, CollapsedFileActivityCompactView (+35 more)

### Community 52 - "Sendable"
Cohesion: 0.04
Nodes (96): Codable, Equatable, Hashable, RawRepresentable, 1. Domain contracts, Sendable, AgentBridgePermissionDecision, allow (+88 more)

### Community 53 - ".reload"
Cohesion: 0.29
Nodes (4): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, Bool, T, UserDefaults

### Community 54 - ".opacity"
Cohesion: 0.06
Nodes (44): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, AirDropDropZoneView, .body, .subtitle, .accessibilityLabel, .body (+36 more)

### Community 55 - "RecordSink"
Cohesion: 0.17
Nodes (11): AppendOnlyRecordTailerTests, Fixture, NoticeSink, openDescriptorCount(), RecordSink, .strings, Bool, Int (+3 more)

### Community 56 - "ClipboardPasteboardReadResult"
Cohesion: 0.10
Nodes (21): ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult (+13 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".event"
Cohesion: 0.22
Nodes (9): Success, AgentIngestionCoordinatorTests, Result, Set, StaticString, String, UInt, XCTAssertFailure() (+1 more)

### Community 59 - ".sessionID"
Cohesion: 0.09
Nodes (40): AgentBridgeWirePayload, .populatedFieldCount, AgentActivityDescriptor, AgentApprovalRequest, AgentApprovalResolution, AgentCommandEvent, AgentEventPayload, activity (+32 more)

### Community 60 - "AgentSession"
Cohesion: 0.07
Nodes (61): .activeSessions, .sessionsRequiringAttention, AgentSession, .isActive, .isOpen, AgentDashboardLayoutProjection, AgentAttentionSessionRow, .body (+53 more)

### Community 61 - "AgentBridgeClient"
Cohesion: 0.10
Nodes (17): Network, AgentBridgeClient, AgentBridgeClientResult, accepted, rejected, AgentBridgeClientTransport, AgentBridgeNetworkTransport, Bool (+9 more)

### Community 62 - "DynamicIsland Project Context"
Cohesion: 0.17
Nodes (10): Collapsed, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context, Expanded, Known Fragile Areas, Non-Negotiable Behavior To Preserve (+2 more)

### Community 63 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.12
Nodes (17): ControlledMediaRemoteCallback, ControlledMediaRemoteProvider, Entry, ManualMediaRemoteDeadlineScheduler, .count, .scheduler, MediaRemoteCallbackBridgeTests, MediaRemoteRefreshRecoveryTests (+9 more)

### Community 64 - "CaseIterable"
Cohesion: 0.04
Nodes (54): CaseIterable, 2026-07-11 - Phase 9D Theme Simplification, AgentApprovalPolicyChoice, askEveryTime, autoApprove, AnimationPreset, .displayName, .id (+46 more)

### Community 65 - ".ingest"
Cohesion: 0.19
Nodes (4): AgentEventStoreTests, Int, String, TimeInterval

### Community 66 - ".makeProcessor"
Cohesion: 0.26
Nodes (6): AgentBridgeEnvelopeIntegrationTests, StaticString, String, UInt, Any, String

### Community 67 - "AgentBridgeClientProfile"
Cohesion: 0.19
Nodes (9): AgentBridgeClientProfile, AgentBridgeDiscoveryRecord, AgentBridgeProtocol, Date, Int, Int32, String, UInt16 (+1 more)

### Community 68 - "AgentUISnapshotTests"
Cohesion: 0.19
Nodes (13): AnyView, AgentCompactAttentionLeadingView, .body, AgentCompactAttentionTrailingView, .body, .body, AgentUISnapshotTests, Bool (+5 more)

### Community 69 - "AppDelegate"
Cohesion: 0.10
Nodes (19): Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, AppDelegate, .liveActivitySettingsPublisher, LiveActivitySettingsSnapshot, Any, AnyCancellable, Bool (+11 more)

### Community 71 - "ExpandedScrollEventRoutingPolicyTests"
Cohesion: 0.09
Nodes (18): QuartzCore, ExpandedContentScrollSequenceOwnership, ExpandedContentScrollSequencePhase, momentumBegan, momentumCancelled, momentumChanged, momentumEnded, phaseLess (+10 more)

### Community 72 - "AgentIntegrationProvider"
Cohesion: 0.15
Nodes (14): AgentIntegrationConfigurationExpectation, absent, digest, AgentIntegrationProvider, claude, codex, .desiredEvents, .displayName (+6 more)

### Community 73 - "AppendOnlyRecordTailer.swift"
Cohesion: 0.08
Nodes (28): Dispatch, AppendOnlyRecordLimits, AppendOnlyRecordStartPolicy, boundedCatchUp, fromEnd, AppendOnlyRecordTailerFailure, identityRace, ioFailure (+20 more)

### Community 74 - "DelimitedRecordFramer"
Cohesion: 0.20
Nodes (7): BoundedRecordRing, .orderedRecords, DelimitedRecordFramer, Output, Int, Void, DelimitedRecordFramerTests

### Community 75 - "FileDropProviderLoader"
Cohesion: 0.15
Nodes (12): NSSecureCoding, completion, FileDropProviderLoader, FileDropURLAccumulator, .urls, FileShelfTemporaryStorage, SendableItemProvider, NSItemProvider (+4 more)

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.15
Nodes (8): AgentBridgeDiscoveryPublisher, FileManager, String, URL, AgentBridgeDiscoveryTests, String, UInt16, URL

### Community 77 - "AgentCapability"
Cohesion: 0.07
Nodes (31): AgentCapabilities, .all, AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage, costUsage (+23 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.23
Nodes (8): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL, AirDropURLAccumulator, .urls, NSItemProvider, URL

### Community 80 - "AgentAttentionEvent"
Cohesion: 0.05
Nodes (53): Comparable, Int, 7. Attention presentation contract, AgentAttentionCoordinator, Date, Never, Task, TimeInterval (+45 more)

### Community 83 - "SequenceClientTransport"
Cohesion: 0.23
Nodes (10): AgentBridgeClientRequest, AgentBridgeSharedClientTests, Outcome, failure, response, SequenceClientTransport, SequenceProfileProvider, Duration (+2 more)

### Community 84 - "AgentState"
Cohesion: 0.06
Nodes (31): AgentEventReducer, AgentEventStoreLimits, .normalized, SemanticResult, applied, rejected, Bool, Date (+23 more)

### Community 85 - "AgentBridgeDiscoveryReader"
Cohesion: 0.08
Nodes (27): dev_t, ino_t, AgentBridgeClientProfileProviding, AgentBridgeDiscoveryFileReading, AgentBridgeDiscoveryFileSnapshot, AgentBridgeDiscoveryReader, Bool, Date (+19 more)

### Community 86 - "AgentEventType"
Cohesion: 0.07
Nodes (30): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+22 more)

### Community 87 - "AgentEventValidationError"
Cohesion: 0.06
Nodes (31): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+23 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.16
Nodes (11): LauncherShortcut, ShortcutsStore, .shortcuts, String, UUID, .displayedShortcuts, ShortcutEditorRow, .body (+3 more)

### Community 89 - "AgentRelayCommandTests"
Cohesion: 0.11
Nodes (13): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000) (+5 more)

### Community 90 - "MediaCandidate"
Cohesion: 0.09
Nodes (23): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Index, Media and artwork, Array, ArtworkFlipPhase, firstHalf (+15 more)

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "NetworkCounters"
Cohesion: 0.16
Nodes (8): ifaddrs, NetworkCounters, Self, TimeInterval, Interface, NetworkCounterSamplingTests, UInt32, UnsafeMutablePointer

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
Cohesion: 0.19
Nodes (8): Double, TimerProgressColorStage, high, low, mid, TimerProgressFormatting, .body, TimerProgressFormattingTests

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentEvent"
Cohesion: 0.07
Nodes (31): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, AgentEventOrigin, live, localRecovery (+23 more)

### Community 106 - ".ingestAtomically"
Cohesion: 0.07
Nodes (23): Bool, Date, Result, String, Void, AgentIngestionError, capabilityCapacity, generationConflict (+15 more)

### Community 107 - "LiveActivitySettingsSubscriberTests"
Cohesion: 0.25
Nodes (3): LiveActivitySettingsSubscriberTests, String, UserDefaults

### Community 108 - "ShelfFileTile"
Cohesion: 0.23
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, String (+1 more)

### Community 109 - ".allowsCollapsedDrop"
Cohesion: 0.38
Nodes (4): FileDropPolicy, Bool, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "AgentPresentationTests"
Cohesion: 0.07
Nodes (15): AgentGlobalUsagePresentation, AgentUsagePresentation, .gaugeProgress, .gaugeValueText, .isQuotaUsage, .isStale, .progress, .valueText (+7 more)

### Community 111 - "ServerFactorySpy"
Cohesion: 0.11
Nodes (27): AgentBridgeNetworkError, listenerCancelled, listenerFailed, missingPort, AgentBridgeServing, AgentBridgeLifecycleTests, DeferredServerSpy, .startCount (+19 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.11
Nodes (19): AgentBridgeEnvelopeError, emptyBatch, eventTooLarge, generationConflict, invalidAuthority, invalidCapability, invalidEventType, invalidPayload (+11 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.20
Nodes (10): DispatchQueue, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, NWConnection, Result (+2 more)

### Community 114 - "AgentBridge"
Cohesion: 0.17
Nodes (13): HTTPURLResponse, AgentBridge, LaunchMaterial, ProducerRuntime, Runtime, AgentBridgeServerFactory, Error, UUID (+5 more)

### Community 115 - "ClaudeInteractiveProvider"
Cohesion: 0.14
Nodes (5): ClaudeInteractiveProvider, Bool, Int, Set, String

### Community 116 - ".assertFailure"
Cohesion: 0.10
Nodes (14): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequest, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure (+6 more)

### Community 117 - "Foundation"
Cohesion: 0.07
Nodes (16): AgentBridgeShared, AppKit, ClaudeHookShared, CodexHookShared, Combine, CryptoKit, Darwin, Foundation (+8 more)

### Community 118 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 119 - "AgentUsage"
Cohesion: 0.07
Nodes (34): CodingKey, AgentBridgeWireUsageSample, Double, AgentUsage, .allSamples, .isEmpty, .samples, .scopedEntries (+26 more)

### Community 120 - ".parse"
Cohesion: 0.12
Nodes (13): ClaudeTranscriptRecoveryAdapter, ClaudeTranscriptRecoveryParser, OperationKind, command, tool, Any, Bool, Date (+5 more)

### Community 121 - "AgentBridgeEnvelopeBuildError"
Cohesion: 0.11
Nodes (13): CoreFoundation, AgentBridgeEnvelopeBuilder, AgentBridgeEnvelopeBuildError, emptyBatch, emptyInput, eventTooLarge, inputTooLarge, malformedEnvelope (+5 more)

### Community 122 - "AgentBridgeIngress"
Cohesion: 0.24
Nodes (7): AgentBridgeIngress, AgentBridgePermissionRequestProcessor, AgentBridgeRequestProcessor, Bool, Date, Result, String

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.11
Nodes (18): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 5. Local bridge decision, 6. Privacy and security boundaries, 8. Expanded Agent Activity contract (+10 more)

### Community 124 - ".installAgentActivityObservers"
Cohesion: 0.15
Nodes (9): Set, AgentApprovalPolicyKey, AgentApprovalPolicyMode, askEveryTime, autoApprove, .displayName, .isAutomatic, AgentApprovalPolicyState (+1 more)

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
Cohesion: 0.18
Nodes (11): 2. State vocabulary, 4. Normalized event types, 5. Versioned transport envelope, 6. Capability model, 7. Privacy projection, 8. Replay fixture contract, 9. Deferred decisions, Agent Event Schema Draft (+3 more)

### Community 129 - "IslandHostingView"
Cohesion: 0.12
Nodes (15): 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, NSHostingView, NSSize, NSTrackingArea, NSView (+7 more)

### Community 130 - "Error"
Cohesion: 0.15
Nodes (16): Error, AgentBridgeClientTransportError, connectTimedOut, malformedResponse, requestTimedOut, responseTooLarge, unavailable, AgentBridgeNetworkExchange (+8 more)

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
Cohesion: 0.14
Nodes (9): AgentBridgeRequestAuthentication, Data, Bool, Int, Int64, String, AgentBridgeSharedCryptoTests, String (+1 more)

### Community 136 - "AgentBridgeModels.swift"
Cohesion: 0.17
Nodes (14): Decodable, AgentBridgeLimits, AgentBridgeState, degraded, failed, running, starting, stopped (+6 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.20
Nodes (10): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, A3.1 implementation refinement — Codex structured recovery, A3 implementation refinement — Codex authoritative hooks, A4.1 implementation refinement — Claude transcript recovery, A4.5 implementation refinement — bounded OTLP JSON enrichment (+2 more)

### Community 139 - "AgentBridgeClientError"
Cohesion: 0.13
Nodes (15): AgentBridgeClientError, authenticationFailed, discoveryUnavailable, invalidInput, malformedResponse, timedOut, transportUnavailable, AttemptError (+7 more)

### Community 140 - "SettingsWindowController"
Cohesion: 0.22
Nodes (6): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, NSWindowDelegate, SettingsWindowController, Notification, NSWindow

### Community 141 - ".displayedStateLabel"
Cohesion: 0.21
Nodes (9): .body, AgentProgressRail, .body, .body, .body, AgentVisualStyle, Color, Double (+1 more)

### Community 142 - "AgentRelayExitCode"
Cohesion: 0.10
Nodes (19): Int32, AgentRelayCommand, AgentRelayCommandResult, AgentRelayExitCode, accepted, authenticationFailed, bridgeUnavailable, discoveryUnavailable (+11 more)

### Community 143 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 144 - "ArtworkPresentationCoordinator"
Cohesion: 0.20
Nodes (12): ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted, none, queued, staleTransitionDiscarded, transitionCompleted (+4 more)

### Community 145 - ".openActiveMediaSource"
Cohesion: 0.19
Nodes (7): 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, MediaSourceOpenTargetTests

### Community 146 - ".normalize"
Cohesion: 0.10
Nodes (16): ClaudeHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook, ClaudeHookNormalizer (+8 more)

### Community 147 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 148 - "XCTestCase"
Cohesion: 0.08
Nodes (26): AgentAuthorityDomain, activity, capability, interaction, lifecycle, liveness, metadata, operation (+18 more)

### Community 149 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 150 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 152 - ".normalize"
Cohesion: 0.09
Nodes (14): CodexHookNormalizer, CodexHookStandardInput, CodexPermissionHookOutput, Any, Bool, Date, FileHandle, Int (+6 more)

### Community 153 - "AgentSessionID"
Cohesion: 0.10
Nodes (16): AgentApprovalControlKey, AgentApprovalControlRequest, .id, Bool, Date, Duration, String, .activeManagedSessionIDs (+8 more)

### Community 154 - "AgentIngestionEvent"
Cohesion: 0.19
Nodes (11): AgentIngestionEvent, .sessionID, AgentSessionContinuity, CodexRolloutRecoveryParser, Any, Date, Double, Int (+3 more)

### Community 155 - "CodexJSONValue"
Cohesion: 0.09
Nodes (20): CodexJSONValue, array, .arrayValue, bool, .boolValue, .doubleValue, integer, .intValue (+12 more)

### Community 156 - "ClaudeCodeStreamEnvelope"
Cohesion: 0.39
Nodes (4): ClaudeCodeStreamEnvelope, ClaudeCodeStreamEvent, message, transportFailed

### Community 157 - "CodexAppServerProvider"
Cohesion: 0.10
Nodes (10): CodexAppServerProvider, Any, Bool, Date, Double, Set, String, CodexAppServerClientTests (+2 more)

### Community 158 - "AgentManagedSessionController"
Cohesion: 0.09
Nodes (25): S, AgentInteractiveProvider, AgentManagedSessionController, .accountUsage, .interactiveCapabilities, .isAvailable, .managedProvider, .managedProviders (+17 more)

### Community 159 - "NowPlayingMediaProvider"
Cohesion: 0.13
Nodes (15): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, MediaRemoteClient, .isAvailable, MediaRemoteDictionary, MediaRemoteProviding, NowPlayingMediaProvider (+7 more)

### Community 160 - "String"
Cohesion: 0.31
Nodes (7): AgentOTLPJSONDecoder, AgentTelemetryObservation, .isEmpty, Any, Date, Double, String

### Community 161 - "PersistentSnapshotFakeProvider"
Cohesion: 0.04
Nodes (57): AgentDiscoveredSessionDescriptor, AgentDiscoveredSessionRuntimeState, active, idle, notLoaded, systemError, AgentInteractiveCapability, accountUsage (+49 more)

### Community 162 - "Claude Managed Control Review — 2026-09-27"
Cohesion: 0.15
Nodes (12): 10. Phase 6 recommendation, 1. Supported official mechanism, 2. Transport and API, 3. Lifecycle and session semantics, 4. Streaming visible responses and tool events, 5. Approvals and user input, 6. Model control, 7. Usage and context (+4 more)

### Community 163 - "AgentEventStore"
Cohesion: 0.18
Nodes (13): State ownership, AgentApprovalController, CheckedContinuation, Never, Task, Void, AgentEventStore, AgentIngestionCoordinator (+5 more)

### Community 164 - "AgentIntegrationOperationalState"
Cohesion: 0.10
Nodes (17): AgentIntegrationDiagnostics, AgentIntegrationOperationalState, active, awaitingFirstEvent, blocked, degraded, failed, .label (+9 more)

### Community 165 - "Array"
Cohesion: 0.67
Nodes (3): Array, .single, Element

### Community 166 - "Run"
Cohesion: 0.31
Nodes (7): Run, Never, Pipe, Process, String, Task, Void

### Community 167 - "CodexAppServerClient"
Cohesion: 0.10
Nodes (17): .data, CodexAppServerClient, launchFailed, rpcError, transportClosed, object, PendingRequest, AsyncStream (+9 more)

### Community 168 - ".session"
Cohesion: 0.26
Nodes (6): AgentSourceAssociationResolver, AgentSourceOpenTarget, String, AgentSourceAssociationTests, Set, String

### Community 169 - ".ingest"
Cohesion: 0.15
Nodes (9): AgentTelemetryFusion, AgentTelemetryFusionOutcome, applied, deferredNoSession, ignoredEmpty, rejected, Result, AgentTelemetryFusionTests (+1 more)

### Community 170 - "SwiftUI"
Cohesion: 0.12
Nodes (9): Activities and utility modules, Build and tests, Clipboard engine and persistence, Composition, state and settings, Current architecture baseline, Evidence and graph limits, DynamicIslandApp, IslandModule (+1 more)

### Community 171 - "CodexAppServerError"
Cohesion: 0.15
Nodes (16): .result, CodexAppServerError, executableNotFound, invalidResponse, malformedMessage, notRunning, requestTimedOut, transportClosed (+8 more)

### Community 172 - "NowPlayingMediaProvider.swift"
Cohesion: 0.25
Nodes (11): Completion, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending, MediaRemoteDeadlineScheduler, MediaRemoteDeadlineToken, Bool, CheckedContinuation (+3 more)

### Community 173 - "Agent Workspace Execution Plan — 2026-09-27"
Cohesion: 0.14
Nodes (13): Agent Workspace Execution Plan — 2026-09-27, Frozen invariants, Iteration rule, Phase 1 — Gesture-safe session scrolling, Phase 2 — Agents-specific expanded geometry, Phase 3.5 — Real-device workspace stabilization, Phase 3 — Enclosed workspace + session selection, Phase 4 — Embedded agent console UI (+5 more)

### Community 174 - "AgentSessionRowEmphasis"
Cohesion: 0.19
Nodes (9): AgentSessionRowEmphasis, attention, hovered, selected, selectedAttention, standard, AgentWorkspaceSelection, Set (+1 more)

### Community 175 - "ClipboardHistoryPersistenceFinalizationResult"
Cohesion: 0.23
Nodes (9): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+1 more)

### Community 176 - "AgentIntegrationSetupError"
Cohesion: 0.17
Nodes (12): AgentIntegrationSetupError, backupInvalid, backupUnavailable, changedExternally, fileTooLarge, helperUnavailable, invalidHooks, invalidJSON (+4 more)

### Community 177 - "AgentBridgeHTTPStatus"
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 178 - "UInt64"
Cohesion: 0.27
Nodes (4): UInt64, CPUCounters, Date, SystemStatsProvider

### Community 179 - "String"
Cohesion: 0.07
Nodes (32): Identifiable, AgentApprovalPresentation, AgentCompactPresentation, AgentConsoleEntry, AgentConsoleEntryKind, agent, approval, command (+24 more)

### Community 180 - "IslandModules"
Cohesion: 0.15
Nodes (8): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, Phase 11C.3 - Diagnostic WindowServer Transition Trace, NSPanel, 2. Existing DynamicIsland invariants, IslandModules, IslandOverlayPanel, .canBecomeKey, .canBecomeMain

### Community 181 - "AgentInteractiveRequestToken"
Cohesion: 0.22
Nodes (7): AgentInteractiveRequestToken, integer, string, Int64, CodexAppServerEvent, notification, serverRequest

### Community 182 - "AgentEmbeddedConsoleView"
Cohesion: 0.04
Nodes (52): NSObject, NSScrollView, NSTextView, NSTextViewDelegate, NSViewRepresentable, PreferenceKey, AgentConsoleBottomPositionPreferenceKey, AgentConsoleCoordinateSpace (+44 more)

### Community 184 - "String"
Cohesion: 0.12
Nodes (20): String, SystemStatsFormatting, SystemStatsSnapshot, .visualizerAccentColor, StatsLineChart, .body, StatsMetricCard, .body (+12 more)

### Community 185 - "CollapsedPreviewKind"
Cohesion: 0.25
Nodes (8): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, CollapsedPreviewKind, battery, fileDrop, liveActivity, media, none, timer

### Community 186 - "Fresh critical audit instructions"
Cohesion: 0.18
Nodes (9): Interpreter guard for subcommands, Path, Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits (+1 more)

### Community 187 - "AgentIntegrationSetupState"
Cohesion: 0.29
Nodes (7): AgentIntegrationSetupState, blocked, configured, helperUnavailable, .label, needsSetup, repairRequired

### Community 189 - ".routine"
Cohesion: 0.25
Nodes (4): AgentCollapsedShellPresentation, CGFloat, Self, .collapsedPresentationProfile

### Community 190 - "Claude Managed Control Review — 2026-09-28"
Cohesion: 0.33
Nodes (5): Capability matrix, Claude Managed Control Review — 2026-09-28, Identity and safety, Production decision, Scope

### Community 191 - "Codex Managed Model Control Review — 2026-09-28"
Cohesion: 0.33
Nodes (5): Codex Managed Model Control Review — 2026-09-28, Context, Inventory, Selection semantics, Verified sources

### Community 192 - "DedicatedTimerPageView"
Cohesion: 0.27
Nodes (7): DedicatedTimerPageView, .controlsFontSize, .controlsSpacing, .timerControlRow, .timerControlStack, .titleFontSize, .usesCompactLayout

### Community 193 - ".event"
Cohesion: 0.33
Nodes (4): AgentIngestionTestSupport, Set, String, TimeInterval

### Community 194 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 195 - "ObservableObject"
Cohesion: 0.50
Nodes (3): ObservableObject, AgentIntegrationDiagnosticsController, AnyCancellable

### Community 196 - "CodexHookNormalizationError"
Cohesion: 0.29
Nodes (7): CodexHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook

### Community 198 - "Array"
Cohesion: 0.67
Nodes (3): Array, .single, Element

### Community 199 - "3. Session identity"
Cohesion: 0.33
Nodes (5): 3. Session identity, Collisions, Generation rules, Logical key, Project identity

### Community 201 - "AgentOTLPJSONError"
Cohesion: 0.33
Nodes (6): AgentOTLPJSONError, emptyPayload, excessiveCardinality, excessiveDepth, malformedJSON, payloadTooLarge

### Community 202 - "ClaudeCodeStreamingError"
Cohesion: 0.33
Nodes (6): ClaudeCodeStreamingError, executableNotFound, launchFailed, malformedMessage, turnAlreadyRunning, unsupported

### Community 203 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

### Community 204 - "CodexRolloutRecoveryError"
Cohesion: 0.40
Nodes (5): CodexRolloutRecoveryError, invalidUsage, malformedRecord, missingSession, unsupportedRecord

## Knowledge Gaps
- **1198 isolated node(s):** `PackageDescription`, `package_app.sh script`, `unavailable`, `connectTimedOut`, `requestTimedOut` (+1193 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1574 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `SettingsWindowController`, `NotchGeometryService`, `.normalizeAndSaveDouble`, `ClipboardHistoryStoreTests`, `IslandNavigationStore`, `FileShelfStore`, `ExpandedIslandView`, `Change Log`, `Int`, `DynamicIslandLiveActivity`, `OverlayWindowController`, `AgentEventStore`, `MediaModuleView`, `FileDropProviderLoaderTests`, `SwiftUI`, `String`, `IslandLayoutStore`, `AppSettingsTests`, `CGFloat`, `IslandModules`, `.reload`, `.opacity`, `String`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `CaseIterable`, `DedicatedTimerPageView`, `ObservableObject`, `AgentUISnapshotTests`, `AppDelegate`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `.allowsCollapsedDrop`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Why does `Data` connect `Data` to `Error`, `.signedRequest`, `ClipboardHistoryStore`, `SystemClipboardPasteboardClient`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `AgentRelayExitCode`, `.normalize`, `.normalize`, `ClipboardHistoryEntry`, `AgentIngestionEvent`, `ClipboardImageNormalizerTests`, `String`, `AgentBridgeAuthenticator`, `AppendOnlyRecordTailer`, `Run`, `CodexAppServerClient`, `FileDropProviderLoaderTests`, `YouTubeMetadataProvider`, `ClipboardHistoryPersistenceFinalizationResult`, `AgentIntegrationSetupService`, `Sendable`, `RecordSink`, `ClipboardPasteboardReadResult`, `AgentBridgeClient`, `FileClipboardHistoryPersistence`, `AgentBridgeClientProfile`, `.makeProcessor`, `.install`, `DelimitedRecordFramer`, `.decode`, `SequenceClientTransport`, `AgentBridgeDiscoveryReader`, `AgentRelayCommandTests`, `.ingestAtomically`, `AgentBridge`, `.assertFailure`, `Foundation`, `.parse`, `AgentBridgeEnvelopeBuildError`?**
  _High betweenness centrality (0.064) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `CaseIterable`, `IslandHostingView`, `AppSettings`, `IslandRootView`, `IslandEscapeRouter`, `AppDelegate`, `ExpandedScrollEventRoutingPolicyTests`, `SettingsWindowController`, `IslandLayoutStore`, `NotchGeometryService`, `ExpandedIslandView`, `Change Log`, `IslandModules`, `CollapsedPreviewKind`, `DynamicIslandLiveActivity`, `.routine`, `DynamicIsland Project Context`, `OverlayPresentationSessionTests`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **Are the 31 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 31 INFERRED edges - model-reasoned connections that need verification._
- **Are the 17 inferred relationships involving `AgentSession` (e.g. with `1. Domain contracts` and `.activeSessions`) actually correct?**
  _`AgentSession` has 17 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `unavailable` to the rest of the system?**
  _1198 weakly-connected nodes found - possible documentation gaps or missing edges._