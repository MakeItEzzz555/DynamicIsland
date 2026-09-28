# Graph Report - DynamicIsland  (2026-09-28)

## Corpus Check
- 184 files · ~511,157 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 5942 nodes · 17828 edges · 203 communities (189 shown, 14 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 2521 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ae914958`
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
- IslandSurfaceBackground
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
- MediaSnapshot
- IslandRootView.swift
- FileDropProviderLoaderTests
- What You Must Do When Invoked
- AgentMCPObservationAdapter
- String
- .refresh
- IslandStateStore
- AppSettingsTests
- CGFloat
- AgentIntegrationSetupService
- ExpandedIslandView
- AgentEventPayload
- CompactIslandView
- Codable
- .reload
- .opacity
- RecordSink
- ClipboardImageCaptureLifecycleTests
- OverlayPresentationSessionTests
- .event
- .sessionID
- View
- AgentBridgeClient
- AgentPromptEditor
- ManualMediaRemoteDeadlineScheduler
- CaseIterable
- .ingest
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
- AgentAttentionEvent
- Package.swift
- package_app.sh
- SequenceClientTransport
- .apply
- AgentBridgeDiscoveryReader
- AgentEventType
- Sendable
- ShortcutsStore
- AgentRelayCommandTests
- Phase Workflow For Future Work
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
- AgentReplayHarness
- AgentIngestionError
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- AgentPresentationTests
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- .testRealListenerUsesLoopbackEphemeralPortAndIngestsSignedEvent
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
- .init
- Error
- .signedRequest
- MenuBarController
- AgentBridgeDiscoveryReadError
- Data
- AgentUsagePresentation
- Agent Activity Feature Phase Plan
- IslandLayoutStore
- AgentBridgeEnvelopeBuildError
- SettingsWindowController
- String
- AgentRelayExitCode
- AudioVisualizerView
- CodexAppServerProvider
- AgentAttentionCoordinator
- .normalize
- AgentEventValidationError
- AgentProducerPolicy
- LaunchAtLoginController.swift
- LockedValue
- LiveActivityStore
- .normalize
- AgentApprovalController
- UInt64
- CodexJSONValue
- ClaudeCodeStreamEnvelope
- ArtworkPresentationCoordinator
- AgentManagedSessionController
- .session
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
- AgentBridgeSharedDiscoveryTests
- CodexAppServerClient
- AppLaunchService
- Agent Workspace Execution Plan — 2026-09-27
- AgentSession
- ClipboardHistoryPersistenceFinalizationResult
- AgentIntegrationSetupError
- AgentBridgeHTTPStatus
- CollapsedLiveActivityPrioritySource
- Identifiable
- CodexRolloutRecoveryAdapter
- .resolve
- AgentEmbeddedConsoleView
- AgentConsoleBottomPositionPreferenceKey
- String
- AppendOnlyRecordTailerSignalToken
- Fresh critical audit instructions
- AgentIntegrationSetupState
- .pause
- ClaudeCodeStreamingError
- Claude Managed Control Review — 2026-09-28
- Codex Managed Model Control Review — 2026-09-28
- DynamicIslandLiveActivityKind
- AgentBridgeAuthenticationError
- FileClipboardHistoryPersistence
- ObservableObject
- ClaudeHookNormalizationError
- AgentSourceHealthRow
- .remainingTime
- 3. Session identity
- summary.md
- .events
- .decode

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 342 edges
2. `AgentSession` - 165 edges
3. `OverlayWindowController` - 147 edges
4. `AgentManagedSessionController` - 141 edges
5. `AgentEventStore` - 125 edges
6. `AgentIngestionCoordinator` - 112 edges
7. `Change Log` - 110 edges
8. `MediaController` - 105 edges
9. `AgentApprovalController` - 91 edges
10. `AgentProvider` - 89 edges

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
Cohesion: 0.09
Nodes (16): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, IOKit.ps, CPUCounters, Bool, Date, Double, Int (+8 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.13
Nodes (18): ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted, none, queued, staleTransitionDiscarded, transitionCompleted (+10 more)

### Community 4 - "SettingsView"
Cohesion: 0.14
Nodes (31): Owner, content, island, HelpText, .body, PriorityStepperRow, .body, SettingsGroup (+23 more)

### Community 5 - "IslandRootView"
Cohesion: 0.06
Nodes (37): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 11C.9 - Predictive Space Motion Resampling, Phase 12B - Native Overlay Cleanup And Runtime Optimization, Phase 13A - Expanded Visibility Controls, CollapsedPreviewContent, CollapsedPreviewKind, battery (+29 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.13
Nodes (15): ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date, Int (+7 more)

### Community 8 - "TimerController"
Cohesion: 0.11
Nodes (19): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration (+11 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.08
Nodes (22): ImageIO, NSPasteboard, NSPasteboardItem, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture (+14 more)

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.10
Nodes (20): Bool, Duration, Never, String, Task, TimeInterval, Void, SystemTimerNotificationCenterClient (+12 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.06
Nodes (32): ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint, ClipboardHistoryPayload, .byteCount (+24 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.06
Nodes (36): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, NSEdgeInsets, NSScreen, AgentCollapsedShellPresentation (+28 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.12
Nodes (17): ClipboardHistoryArchive, ClipboardHistoryStoreTests, ControlledClipboardPersistence, .data, .deleteCount, .saveCount, ControlledClipboardPersistenceError, requestedFailure (+9 more)

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.09
Nodes (16): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedWidth, .contentStaggerAmount, .expandedHeight (+8 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.13
Nodes (5): CollapsedLiveActivitySelectorTests, Bool, Date, Int, String

### Community 16 - "IslandNavigationStore"
Cohesion: 0.11
Nodes (17): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, ExpandedIslandPage, .accessibilityLabel, agents, island, stats, .symbolName (+9 more)

### Community 17 - ".start"
Cohesion: 0.21
Nodes (8): TimerCompletionNotificationPreferences, MockTimerNotificationCenterClient, Bool, String, Void, TestError, schedulingFailed, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.14
Nodes (14): 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, CompactShelfBadge, .body (+6 more)

### Community 19 - "SupportedApp"
Cohesion: 0.14
Nodes (14): SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName, edge, .fallbackPaths (+6 more)

### Community 20 - "AgentIntegrationRouter"
Cohesion: 0.07
Nodes (33): Comparable, AgentIngestionResult, AgentIntegrationPrecedence, mcpFallback, providerNative, secondaryObservation, AgentIntegrationRouter, AgentMCPObservation (+25 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (59): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish (+51 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "IslandSurfaceBackground"
Cohesion: 0.07
Nodes (35): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool (+27 more)

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
Cohesion: 0.09
Nodes (16): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer (+8 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.13
Nodes (20): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+12 more)

### Community 29 - "OverlayWindowController"
Cohesion: 0.08
Nodes (23): CFTimeInterval, DispatchWorkItem, NSPoint, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedGestureCandidateScreenRegion, .collapsedInteractiveSurfaceFrame, .collapsedScrollThreshold (+15 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (11): CFDictionary, CGImageSource, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int, ClipboardImageNormalizerTests (+3 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (4): MediaArbitratorTests, Bool, NSImage, String

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.11
Nodes (18): Phase 11A - Battery Live Activity, BatteryActivityProvider, BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Any, Bool (+10 more)

### Community 33 - "AgentProducerHandle"
Cohesion: 0.06
Nodes (41): Bool, Result, String, Void, AgentEventProvenance, AgentIdentityConflict, AgentIngestionEvent, .sessionID (+33 more)

### Community 34 - "AgentBridgeAuthenticator"
Cohesion: 0.20
Nodes (10): AgentBridgeAuthenticator, .rememberedNonceCount, AgentBridgeCrypto, NonceEntry, Bool, Date, Int, Int64 (+2 more)

### Community 35 - "XCTest"
Cohesion: 0.08
Nodes (7): AppKit, Combine, DynamicIsland, FileDropProviderTestError, requestedFailure, UniformTypeIdentifiers, XCTest

### Community 36 - "AppendOnlyRecordTailer"
Cohesion: 0.12
Nodes (17): DispatchSourceFileSystemObject, NoticeHandler, RecordHandler, AppendOnlyFileIdentity, AppendOnlyRecordStartPolicy, boundedCatchUp, fromEnd, AppendOnlyRecordTailer (+9 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.09
Nodes (24): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, Double, MediaModuleView, .activePlayerView, .artistFontSize, .artworkSize, .constrainedActivePlayerView (+16 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.14
Nodes (14): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, MediaDetectionProvider, MediaSnapshot, MediaSourceKind, browser, music, spotify, system (+6 more)

### Community 39 - "IslandRootView.swift"
Cohesion: 0.06
Nodes (40): Animation, EnvironmentKey, AirDropDropZoneView, .subtitle, CollapseShellOnlyEnvironmentKey, DedicatedTimerPageView, .controlsFontSize, .controlsSpacing (+32 more)

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.22
Nodes (7): ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, String, URL, UserDefaults, Void

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "AgentMCPObservationAdapter"
Cohesion: 0.05
Nodes (49): CodingKey, Decodable, AgentMCPAdapterError, invalidIdentity, invalidSchema, invalidUsage, malformedJSON, payloadTooLarge (+41 more)

### Community 43 - "String"
Cohesion: 0.09
Nodes (20): BrowserScriptTarget, Decision, MediaArtworkFlipRequest, .isExpired, MediaCandidate, .sourceKey, MediaController, .currentArtworkPresentationIdentity (+12 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.05
Nodes (38): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, App Entry, Collapsed, Current Architecture, Current Stable Baseline (+30 more)

### Community 46 - "AppSettingsTests"
Cohesion: 0.12
Nodes (3): AppSettingsTests, String, UserDefaults

### Community 47 - "CGFloat"
Cohesion: 0.13
Nodes (15): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline, Evidence and graph limits, SwiftUI rendering and presentation (+7 more)

### Community 48 - "AgentIntegrationSetupService"
Cohesion: 0.16
Nodes (11): AgentIntegrationBackupEnvelope, AgentIntegrationSetupPaths, AgentIntegrationSetupService, .fileManager, AgentIntegrationSetupSnapshot, Bool, FileManager, Int (+3 more)

### Community 49 - "ExpandedIslandView"
Cohesion: 0.13
Nodes (14): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-04 - Phase 5J Single Visual Surface Morph, Phase 12A.2 - Single Authoritative Shell/Content Timeline, .expandedPageMorphDuration, ExpandedIslandView, .airDropTargetBinding, .body, .clipboardBackdropAnimation (+6 more)

### Community 50 - "AgentEventPayload"
Cohesion: 0.13
Nodes (32): AgentBridgeWirePayload, .populatedFieldCount, AgentActivityDescriptor, AgentApprovalRequest, AgentApprovalResolution, AgentCommandEvent, AgentEventPayload, activity (+24 more)

### Community 51 - "CompactIslandView"
Cohesion: 0.10
Nodes (23): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CollapsedFileActivityCompactView (+15 more)

### Community 52 - "Codable"
Cohesion: 0.07
Nodes (57): Codable, Hashable, RawRepresentable, 1. Domain contracts, AgentActivity, AgentActivityKind, approval, command (+49 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (3): Bool, T, UserDefaults

### Community 54 - ".opacity"
Cohesion: 0.09
Nodes (35): 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, Phase 12A - Final Island Content Transition Sequencing, .body, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier (+27 more)

### Community 55 - "RecordSink"
Cohesion: 0.17
Nodes (11): AppendOnlyRecordTailerTests, Fixture, NoticeSink, openDescriptorCount(), RecordSink, .strings, Bool, Int (+3 more)

### Community 56 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.19
Nodes (8): ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, CheckedContinuation, MainActor, Never, Sendable, XCTestExpectation

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.17
Nodes (8): OverlayPresentationSession, .canPresentOverlay, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval, Void

### Community 58 - ".event"
Cohesion: 0.19
Nodes (12): Success, AgentIngestionCoordinatorTests, Array, .single, Element, Result, Set, StaticString (+4 more)

### Community 59 - ".sessionID"
Cohesion: 0.16
Nodes (9): AgentReductionResult, AgentEventReducerTests, Set, String, TimeInterval, AgentTestFixture, Int, String (+1 more)

### Community 60 - "View"
Cohesion: 0.06
Nodes (57): AgentDashboardLayoutProjection, AgentAttentionSessionRow, .body, AgentCLIControlBar, .body, .selectedSession, AgentCompactAttentionLeadingView, .body (+49 more)

### Community 61 - "AgentBridgeClient"
Cohesion: 0.12
Nodes (16): AgentBridgeClient, AgentBridgeClientResult, accepted, rejected, Bool, Date, Int, String (+8 more)

### Community 62 - "AgentPromptEditor"
Cohesion: 0.10
Nodes (17): NSObject, NSScrollView, NSTextView, NSTextViewDelegate, NSViewRepresentable, .submissionValue, AgentPromptDraftPolicy, AgentPromptEditor (+9 more)

### Community 63 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.06
Nodes (44): AnyObject, 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending (+36 more)

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
Cohesion: 0.14
Nodes (16): AgentBridgeClientProfile, AgentBridgeClientRequest, AgentBridgeClientResponse, AgentBridgeDiscoveryRecord, AgentBridgeProtocol, Date, Int, Int32 (+8 more)

### Community 68 - "AgentUISnapshotTests"
Cohesion: 0.19
Nodes (11): AnyView, AgentCompactAttentionTrailingView, .body, AgentDashboardStack, AgentUISnapshotTests, Bool, CGSize, Color (+3 more)

### Community 69 - "AppDelegate"
Cohesion: 0.11
Nodes (20): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, 2. Existing DynamicIsland invariants, Composition, state and settings, AppDelegate, .liveActivitySettingsPublisher (+12 more)

### Community 70 - "AgentIntegrationSetupTests"
Cohesion: 0.19
Nodes (4): AgentHookConfigurationPlanner, Any, AgentIntegrationSetupTests, String

### Community 71 - "ExpandedScrollEventRoutingPolicyTests"
Cohesion: 0.09
Nodes (18): QuartzCore, ExpandedContentScrollSequenceOwnership, ExpandedContentScrollSequencePhase, momentumBegan, momentumCancelled, momentumChanged, momentumEnded, phaseLess (+10 more)

### Community 72 - "AgentIntegrationProvider"
Cohesion: 0.14
Nodes (14): AgentIntegrationConfigurationExpectation, absent, digest, AgentIntegrationProvider, claude, codex, .desiredEvents, .displayName (+6 more)

### Community 73 - "AppendOnlyRecordTailer.swift"
Cohesion: 0.09
Nodes (23): Dispatch, AppendOnlyRecordLimits, AppendOnlyRecordTailerFailure, identityRace, ioFailure, notRegularFile, parentUnavailable, permissionDenied (+15 more)

### Community 74 - "DelimitedRecordFramer"
Cohesion: 0.20
Nodes (7): BoundedRecordRing, .orderedRecords, DelimitedRecordFramer, Output, Int, Void, DelimitedRecordFramerTests

### Community 75 - "FileDropProviderLoader"
Cohesion: 0.19
Nodes (9): NSSecureCoding, completion, message, FileDropProviderLoader, SendableItemProvider, NSItemProvider, TimeInterval, UTType (+1 more)

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.15
Nodes (8): AgentBridgeDiscoveryPublisher, FileManager, String, URL, AgentBridgeDiscoveryTests, String, UInt16, URL

### Community 77 - "AgentEvent"
Cohesion: 0.05
Nodes (46): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, AgentEventOrigin, live, localRecovery (+38 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.19
Nodes (8): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL, Bool, AirDropURLAccumulator, .urls, URL

### Community 80 - "AgentAttentionEvent"
Cohesion: 0.08
Nodes (39): 7. Attention presentation contract, AgentAttentionBadge, AgentAttentionEvent, .id, AgentAttentionGeneration, AgentAttentionPolicyEngine, AgentAttentionPolicyOptions, AgentAttentionPolicyResult (+31 more)

### Community 83 - "SequenceClientTransport"
Cohesion: 0.19
Nodes (9): CoreFoundation, AgentBridgeEnvelopeBuilder, Any, String, AgentBridgeSharedClientTests, SequenceClientTransport, SequenceProfileProvider, Int (+1 more)

### Community 84 - ".apply"
Cohesion: 0.09
Nodes (15): AgentEventReducer, AgentEventStoreLimits, .normalized, Bool, Date, Int, String, TimeInterval (+7 more)

### Community 85 - "AgentBridgeDiscoveryReader"
Cohesion: 0.11
Nodes (19): dev_t, ino_t, AgentBridgeClientProfileProviding, AgentBridgeDiscoveryFileReading, AgentBridgeDiscoveryFileSnapshot, AgentBridgeDiscoveryReader, Bool, Date (+11 more)

### Community 86 - "AgentEventType"
Cohesion: 0.06
Nodes (31): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+23 more)

### Community 87 - "Sendable"
Cohesion: 0.04
Nodes (73): Equatable, Sendable, AgentBridgePermissionDecision, allow, deny, AgentBridgeSharedError, invalidNonce, randomUnavailable (+65 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.07
Nodes (30): 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, LauncherShortcut, ShortcutsStore, .shortcuts, String, UUID, AlbumArtworkView (+22 more)

### Community 89 - "AgentRelayCommandTests"
Cohesion: 0.14
Nodes (10): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000) (+2 more)

### Community 90 - "Phase Workflow For Future Work"
Cohesion: 0.07
Nodes (28): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration, 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability (+20 more)

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

### Community 105 - "AgentReplayHarness"
Cohesion: 0.19
Nodes (5): AgentReplayHarness, Int, AgentReplayHarnessTests, String, TimeInterval

### Community 106 - "AgentIngestionError"
Cohesion: 0.08
Nodes (22): AgentIngestionError, capabilityCapacity, generationConflict, identityConflict, invalidDescriptor, invalidEvent, invalidProducer, leaseCapacity (+14 more)

### Community 107 - "LiveActivitySettingsSubscriberTests"
Cohesion: 0.25
Nodes (3): LiveActivitySettingsSubscriberTests, String, UserDefaults

### Community 108 - "ShelfFileTile"
Cohesion: 0.19
Nodes (11): 2026-07-04 - Phase 4C Tray File Actions Context Menu, EmptyMediaLauncherView, FileShelfActions, .body, ShelfFileTile, .body, .displayName, .fileImage (+3 more)

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.18
Nodes (9): FileDropPolicy, FileDropURLAccumulator, .urls, FileShelfTemporaryStorage, Bool, String, URL, .canAcceptExpandedFileDrop (+1 more)

### Community 110 - "AgentPresentationTests"
Cohesion: 0.08
Nodes (6): .progressMetric, AgentPresentationTests, Date, Double, Set, String

### Community 111 - "ServerFactorySpy"
Cohesion: 0.10
Nodes (29): Network, AgentBridgeNetworkError, listenerCancelled, listenerFailed, missingPort, AgentBridgeServing, AgentBridgeLifecycleTests, DeferredServerSpy (+21 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.11
Nodes (19): AgentBridgeEnvelopeError, emptyBatch, eventTooLarge, generationConflict, invalidAuthority, invalidCapability, invalidEventType, invalidPayload (+11 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.20
Nodes (10): DispatchQueue, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, NWConnection, Result (+2 more)

### Community 114 - ".testRealListenerUsesLoopbackEphemeralPortAndIngestsSignedEvent"
Cohesion: 0.39
Nodes (3): HTTPURLResponse, AgentBridgeNetworkTests, URL

### Community 115 - "ClaudeInteractiveProvider"
Cohesion: 0.14
Nodes (5): ClaudeInteractiveProvider, Bool, Int, Set, String

### Community 116 - ".assertFailure"
Cohesion: 0.11
Nodes (13): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, Bool (+5 more)

### Community 117 - "Foundation"
Cohesion: 0.06
Nodes (14): AgentBridgeShared, ClaudeHookShared, CodexHookShared, Darwin, Foundation, Security, AgentBridgeDiscoveryError, insecurePermissions (+6 more)

### Community 118 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 119 - "AgentUsage"
Cohesion: 0.07
Nodes (32): AgentUsage, .allSamples, .isEmpty, .samples, .scopedEntries, AgentUsageKey, AgentUsageMetric, cachedInputTokens (+24 more)

### Community 120 - ".parse"
Cohesion: 0.12
Nodes (13): ClaudeTranscriptRecoveryAdapter, ClaudeTranscriptRecoveryParser, OperationKind, command, tool, Any, Bool, Date (+5 more)

### Community 121 - ".openActiveMediaSource"
Cohesion: 0.11
Nodes (12): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 3 Album Artwork Source Open, MediaSourceOpenTarget, app, bundleIdentifier, .debugDescription, youtube, .body (+4 more)

### Community 122 - "AgentBridge"
Cohesion: 0.14
Nodes (17): Runtime, AgentBridge, AgentBridgeIngress, AgentBridgePermissionRequestProcessor, AgentBridgeRequestProcessor, LaunchMaterial, ProducerRuntime, Runtime (+9 more)

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.11
Nodes (18): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 5. Local bridge decision, 6. Privacy and security boundaries, 8. Expanded Agent Activity contract (+10 more)

### Community 124 - "AgentEventApplication"
Cohesion: 0.09
Nodes (21): AgentEventApplication, applied, duplicate, ignoredAfterTerminal, ignoredWeakerEvidence, rejected, staleGeneration, AgentEventBatchApplication (+13 more)

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

### Community 129 - ".init"
Cohesion: 0.07
Nodes (24): 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, Debugging Notes, Phase 11C.4 - WindowServer Space-Transition Counter-Translation (+16 more)

### Community 130 - "Error"
Cohesion: 0.14
Nodes (15): Error, AgentBridgeClientTransport, AgentBridgeClientTransportError, connectTimedOut, malformedResponse, requestTimedOut, responseTooLarge, unavailable (+7 more)

### Community 131 - ".signedRequest"
Cohesion: 0.34
Nodes (4): AgentBridgeHTTPRequest, AgentBridgeAuthenticationTests, AgentBridgeTestSupport, Int64

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "AgentBridgeDiscoveryReadError"
Cohesion: 0.12
Nodes (16): AgentBridgeDiscoveryReadError, changedDuringRead, invalidAuthentication, invalidHost, invalidIdentifier, invalidPort, invalidProcess, invalidTimestamp (+8 more)

### Community 134 - "Data"
Cohesion: 0.08
Nodes (19): OSStatus, AgentBridgeRequestAuthentication, Data, Bool, Int, Int64, String, ClaudeHookStandardInput (+11 more)

### Community 136 - "AgentUsagePresentation"
Cohesion: 0.12
Nodes (13): AgentOperationAggregation, .primarySessions, .recentSessions, AgentUsagePresentation, .gaugeProgress, .gaugeValueText, .isQuotaUsage, .isStale (+5 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.20
Nodes (10): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, A3.1 implementation refinement — Codex structured recovery, A3 implementation refinement — Codex authoritative hooks, A4.1 implementation refinement — Claude transcript recovery, A4.5 implementation refinement — bounded OTLP JSON enrichment (+2 more)

### Community 138 - "IslandLayoutStore"
Cohesion: 0.16
Nodes (9): 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 3. Component boundaries, Adapter contract, IslandCanvasCoordinateSpace, IslandLayoutStore, Bool, CGFloat, CGRect (+1 more)

### Community 139 - "AgentBridgeEnvelopeBuildError"
Cohesion: 0.08
Nodes (24): AgentBridgeClientError, authenticationFailed, discoveryUnavailable, invalidInput, malformedResponse, timedOut, transportUnavailable, AttemptError (+16 more)

### Community 140 - "SettingsWindowController"
Cohesion: 0.22
Nodes (6): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, NSWindowDelegate, SettingsWindowController, Notification, NSWindow

### Community 141 - "String"
Cohesion: 0.19
Nodes (9): AgentSessionPresentation, String, TimeInterval, .sessionTitle, .sessionTitle, .title, .body, .body (+1 more)

### Community 142 - "AgentRelayExitCode"
Cohesion: 0.10
Nodes (19): Int32, AgentRelayCommand, AgentRelayCommandResult, AgentRelayExitCode, accepted, authenticationFailed, bridgeUnavailable, discoveryUnavailable (+11 more)

### Community 143 - "AudioVisualizerView"
Cohesion: 0.14
Nodes (16): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size, .spacing (+8 more)

### Community 144 - "CodexAppServerProvider"
Cohesion: 0.10
Nodes (8): CodexAppServerProvider, AsyncStream, Int, Set, String, CodexAppServerClientTests, String, URL

### Community 145 - "AgentAttentionCoordinator"
Cohesion: 0.21
Nodes (6): AgentAttentionCoordinator, Date, Never, Task, TimeInterval, Void

### Community 146 - ".normalize"
Cohesion: 0.15
Nodes (7): ClaudeHookNormalizer, Any, Bool, Date, Int, String, ClaudeHookNormalizerTests

### Community 147 - "AgentEventValidationError"
Cohesion: 0.12
Nodes (14): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+6 more)

### Community 148 - "AgentProducerPolicy"
Cohesion: 0.07
Nodes (31): AgentAuthorityDomain, activity, interaction, lifecycle, liveness, metadata, operation, usage (+23 more)

### Community 149 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 150 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 151 - "LiveActivityStore"
Cohesion: 0.27
Nodes (6): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int, String

### Community 152 - ".normalize"
Cohesion: 0.13
Nodes (9): CodexHookNormalizer, Any, Bool, Date, Int, String, capability, CodexHookNormalizerTests (+1 more)

### Community 153 - "AgentApprovalController"
Cohesion: 0.10
Nodes (25): AgentApprovalControlKey, AgentApprovalController, AgentApprovalControlRequest, .id, AgentApprovalControlResult, accepted, missing, Bool (+17 more)

### Community 154 - "UInt64"
Cohesion: 0.19
Nodes (9): UInt64, CodexRolloutRecoveryParser, Any, Date, Double, Int, String, AsyncStream (+1 more)

### Community 155 - "CodexJSONValue"
Cohesion: 0.08
Nodes (21): AgentInteractiveRequestToken, integer, string, Int64, CodexJSONValue, array, .arrayValue, bool (+13 more)

### Community 156 - "ClaudeCodeStreamEnvelope"
Cohesion: 0.43
Nodes (3): ClaudeCodeStreamEnvelope, ClaudeCodeStreamEvent, transportFailed

### Community 157 - "ArtworkPresentationCoordinator"
Cohesion: 0.27
Nodes (6): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, ArtworkPresentationCoordinator, .displayedSnapshot, UUID, Void, .gestureCallbacks

### Community 158 - "AgentManagedSessionController"
Cohesion: 0.08
Nodes (27): S, AgentInteractiveProvider, AgentManagedTranscriptEntry, AgentManagedSessionController, .accountUsage, .interactiveCapabilities, .isAvailable, .managedProvider (+19 more)

### Community 159 - ".session"
Cohesion: 0.26
Nodes (6): AgentSourceAssociationResolver, AgentSourceOpenTarget, String, AgentSourceAssociationTests, Set, String

### Community 160 - "String"
Cohesion: 0.31
Nodes (7): AgentOTLPJSONDecoder, AgentTelemetryObservation, .isEmpty, Any, Date, Double, String

### Community 161 - "AgentInteractiveProviderEvent"
Cohesion: 0.06
Nodes (43): AgentDiscoveredSessionDescriptor, AgentDiscoveredSessionRuntimeState, active, idle, notLoaded, systemError, AgentInteractiveCapability, accountUsage (+35 more)

### Community 162 - "Claude Managed Control Review — 2026-09-27"
Cohesion: 0.15
Nodes (12): 10. Phase 6 recommendation, 1. Supported official mechanism, 2. Transport and API, 3. Lifecycle and session semantics, 4. Streaming visible responses and tool events, 5. Approvals and user input, 6. Model control, 7. Usage and context (+4 more)

### Community 163 - "AgentEventStore"
Cohesion: 0.12
Nodes (12): State ownership, AgentEventStore, AgentIngestionCoordinator, CheckedContinuation, Never, StoreSink, AgentManagedSessionControllerTests, PersistentSnapshotFakeProvider (+4 more)

### Community 164 - "AgentIntegrationOperationalState"
Cohesion: 0.14
Nodes (13): AgentIntegrationOperationalState, active, awaitingFirstEvent, blocked, degraded, failed, .label, notConfigured (+5 more)

### Community 165 - "AgentSourceRegistryTests.swift"
Cohesion: 0.50
Nodes (3): Array, .single, Element

### Community 166 - "Run"
Cohesion: 0.31
Nodes (7): Run, Never, Pipe, Process, String, Task, Void

### Community 167 - "CodexAppServerError"
Cohesion: 0.14
Nodes (11): .data, CodexAppServerError, executableNotFound, launchFailed, malformedMessage, notRunning, requestTimedOut, rpcError (+3 more)

### Community 168 - "XCTestCase"
Cohesion: 0.17
Nodes (12): E, AgentIntegrationRouterTests, Collection, .single, EventCapture, Element, Result, StaticString (+4 more)

### Community 169 - "AgentState"
Cohesion: 0.13
Nodes (14): AgentState, completed, failed, idle, interrupted, .isTerminal, planning, planReady (+6 more)

### Community 170 - "AgentBridgeSharedDiscoveryTests"
Cohesion: 0.23
Nodes (7): AgentBridgeSharedDiscoveryTests, Bool, Int, mode_t, String, uid_t, UInt16

### Community 171 - "CodexAppServerClient"
Cohesion: 0.09
Nodes (28): .result, CodexAppServerClient, invalidResponse, CodexAppServerEvent, notification, serverRequest, CodexAvailableModel, CodexListedThread (+20 more)

### Community 172 - "AppLaunchService"
Cohesion: 0.38
Nodes (5): 2026-07-03 - Common App Launch Resolver, AppLaunchService, Bool, String, URL

### Community 173 - "Agent Workspace Execution Plan — 2026-09-27"
Cohesion: 0.14
Nodes (13): Agent Workspace Execution Plan — 2026-09-27, Frozen invariants, Iteration rule, Phase 1 — Gesture-safe session scrolling, Phase 2 — Agents-specific expanded geometry, Phase 3.5 — Real-device workspace stabilization, Phase 3 — Enclosed workspace + session selection, Phase 4 — Embedded agent console UI (+5 more)

### Community 174 - "AgentSession"
Cohesion: 0.09
Nodes (21): .activeSessions, .sessionsRequiringAttention, Bool, .activeManagedSessionIDs, Bool, AgentSession, .isActive, .isOpen (+13 more)

### Community 175 - "ClipboardHistoryPersistenceFinalizationResult"
Cohesion: 0.23
Nodes (9): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+1 more)

### Community 176 - "AgentIntegrationSetupError"
Cohesion: 0.17
Nodes (12): AgentIntegrationSetupError, backupInvalid, backupUnavailable, changedExternally, fileTooLarge, helperUnavailable, invalidHooks, invalidJSON (+4 more)

### Community 177 - "AgentBridgeHTTPStatus"
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 178 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 179 - "Identifiable"
Cohesion: 0.07
Nodes (32): Identifiable, Int, AgentCompactPresentation, AgentConsoleEntry, AgentConsoleEntryKind, agent, approval, command (+24 more)

### Community 180 - "CodexRolloutRecoveryAdapter"
Cohesion: 0.50
Nodes (3): CodexRolloutRecoveryAdapter, Bool, URL

### Community 182 - "AgentEmbeddedConsoleView"
Cohesion: 0.08
Nodes (30): AgentConsoleCoordinateSpace, AgentConsoleExternalApprovalRow, .body, AgentConsoleMode, .canInterrupt, interactive, observed, .showsComposer (+22 more)

### Community 183 - "AgentConsoleBottomPositionPreferenceKey"
Cohesion: 0.38
Nodes (5): PreferenceKey, AgentConsoleBottomPositionPreferenceKey, AgentConsoleScrollRegionPreferenceKey, CGFloat, CGRect

### Community 184 - "String"
Cohesion: 0.10
Nodes (26): SystemStatsSnapshot, CollapsedPreviewActivityRow, .body, .iconColor, CollapsedPreviewLabel, .body, .visualizerAccentColor, SafeSystemImage (+18 more)

### Community 186 - "Fresh critical audit instructions"
Cohesion: 0.18
Nodes (9): Interpreter guard for subcommands, Path, Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits (+1 more)

### Community 187 - "AgentIntegrationSetupState"
Cohesion: 0.29
Nodes (7): AgentIntegrationSetupState, blocked, configured, helperUnavailable, .label, needsSetup, repairRequired

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
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 193 - "AgentBridgeAuthenticationError"
Cohesion: 0.22
Nodes (9): AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull, timestampOutsideWindow (+1 more)

### Community 194 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 195 - "ObservableObject"
Cohesion: 0.50
Nodes (3): ObservableObject, AgentIntegrationDiagnosticsController, AnyCancellable

### Community 196 - "ClaudeHookNormalizationError"
Cohesion: 0.07
Nodes (24): CryptoKit, ClaudeHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook (+16 more)

### Community 197 - "AgentSourceHealthRow"
Cohesion: 0.60
Nodes (3): AgentSourceHealthRow, .awaitingGuidance, .body

### Community 199 - "3. Session identity"
Cohesion: 0.33
Nodes (5): 3. Session identity, Collisions, Generation rules, Logical key, Project identity

### Community 203 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

## Knowledge Gaps
- **1225 isolated node(s):** `PackageDescription`, `package_app.sh script`, `unavailable`, `connectTimedOut`, `requestTimedOut` (+1220 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1612 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppSettings` connect `AppSettings` to `.init`, `IslandGestureAction`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `SettingsWindowController`, `NotchGeometryService`, `.normalizeAndSaveDouble`, `ClipboardHistoryStoreTests`, `IslandNavigationStore`, `FileShelfStore`, `Change Log`, `Int`, `DynamicIslandLiveActivity`, `OverlayWindowController`, `AgentEventStore`, `MediaModuleView`, `IslandRootView.swift`, `FileDropProviderLoaderTests`, `String`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `AgentSession`, `ExpandedIslandView`, `CompactIslandView`, `.reload`, `String`, `ClipboardImageCaptureLifecycleTests`, `OverlayPresentationSessionTests`, `CaseIterable`, `ObservableObject`, `AgentUISnapshotTests`, `AppDelegate`, `ShortcutsStore`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Why does `Data` connect `Data` to `Error`, `.signedRequest`, `ClipboardHistoryStore`, `SystemClipboardPasteboardClient`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `AgentRelayExitCode`, `.normalize`, `.normalize`, `ClipboardHistoryEntry`, `UInt64`, `ClipboardImageNormalizerTests`, `String`, `AgentBridgeAuthenticator`, `AppendOnlyRecordTailer`, `Run`, `CodexAppServerError`, `FileDropProviderLoaderTests`, `AgentMCPObservationAdapter`, `CodexAppServerClient`, `AgentBridgeSharedDiscoveryTests`, `ClipboardHistoryPersistenceFinalizationResult`, `AgentIntegrationSetupService`, `CodexRolloutRecoveryAdapter`, `RecordSink`, `ClipboardImageCaptureLifecycleTests`, `AgentBridgeClient`, `FileClipboardHistoryPersistence`, `AgentBridgeClientProfile`, `.makeProcessor`, `AgentIntegrationSetupTests`, `DelimitedRecordFramer`, `.decode`, `SequenceClientTransport`, `AgentBridgeDiscoveryReader`, `Sendable`, `AgentRelayCommandTests`, `ServerFactorySpy`, `.assertFailure`, `Foundation`, `.parse`, `AgentBridge`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `IslandGestureAction`, `SystemStatsController`, `.signedRequest`, `ArtworkFlipPresentationState`, `Data`, `IslandEscapeRouter`, `SystemClipboardPasteboardClient`, `NotchGeometryService`, `ClipboardHistoryStoreTests`, `CollapsedLiveActivitySelectorTests`, `CodexAppServerProvider`, `.start`, `.normalize`, `FileShelfStore`, `AgentProducerPolicy`, `IslandSurfaceBackground`, `.normalize`, `AgentApprovalController`, `ClipboardHistoryEntry`, `UInt64`, `LiveActivityStore`, `MediaAutomationExecutor`, `ClipboardImageNormalizerTests`, `.session`, `BatteryActivitySnapshot`, `AgentProducerHandle`, `MediaArbitratorTests`, `AgentEventStore`, `FileDropProviderLoaderTests`, `AgentBridgeSharedDiscoveryTests`, `AgentMCPObservationAdapter`, `.refresh`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `Identifiable`, `.resolve`, `RecordSink`, `ClipboardImageCaptureLifecycleTests`, `OverlayPresentationSessionTests`, `.event`, `.sessionID`, `AgentBridgeClient`, `ManualMediaRemoteDeadlineScheduler`, `.ingest`, `.makeProcessor`, `AgentUISnapshotTests`, `AgentIntegrationSetupTests`, `ExpandedScrollEventRoutingPolicyTests`, `DelimitedRecordFramer`, `AgentBridgeDiscoveryPublisher`, `AgentAttentionEvent`, `SequenceClientTransport`, `.apply`, `AgentRelayCommandTests`, `NetworkCounters`, `.progress`, `AgentReplayHarness`, `AgentIngestionError`, `LiveActivitySettingsSubscriberTests`, `AgentPresentationTests`, `ServerFactorySpy`, `.testRealListenerUsesLoopbackEphemeralPortAndIngestsSignedEvent`, `.assertFailure`, `ClipboardHistoryPresentationState`, `.parse`, `.openActiveMediaSource`, `ClaudeCodeStreamingClient`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **Are the 31 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 31 INFERRED edges - model-reasoned connections that need verification._
- **Are the 17 inferred relationships involving `AgentSession` (e.g. with `1. Domain contracts` and `.activeSessions`) actually correct?**
  _`AgentSession` has 17 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `unavailable` to the rest of the system?**
  _1225 weakly-connected nodes found - possible documentation gaps or missing edges._