# Graph Report - DynamicIsland  (2026-09-27)

## Corpus Check
- 172 files · ~401,003 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 5466 nodes · 15940 edges · 201 communities (188 shown, 13 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 2079 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `acaaa882`
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
- OverlayWindowController
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- AgentProducerHandle
- Data
- XCTest
- AppendOnlyRecordTailer
- MediaModuleView
- MediaSnapshot
- MediaSourceIdentity
- FileDropProviderLoader
- What You Must Do When Invoked
- YouTubeMetadataProvider
- String
- .refresh
- IslandStateStore
- AppSettingsTests
- CGFloat
- AgentIntegrationProvider
- Bool
- CollapsedLiveActivityPrioritySource
- IslandRootView.swift
- Sendable
- IslandThemeStyle
- CompactIslandView
- RecordSink
- ClipboardImageCaptureLifecycleTests
- OverlayPresentationSessionTests
- .event
- .sessionID
- AgentProvider
- AgentBridgeClient
- IslandHostingView
- XCTestCase
- CaseIterable
- AgentEventStore
- .makeProcessor
- AgentBridgeClientProfile
- ControlledClipboardPersistence
- AppDelegate
- String
- ExpandedScrollEventRoutingPolicyTests
- DynamicIslandLiveActivityKind
- AppendOnlyRecordTailer.swift
- DelimitedRecordFramer
- completion
- AgentBridgeDiscoveryPublisher
- AgentCapability
- Meaningful regression history
- .loadFileURLs
- AgentSessionInstanceID
- Package.swift
- package_app.sh
- SequenceClientTransport
- .apply
- AgentBridgeDiscoveryReader
- AgentEventType
- AgentEventApplication
- ShortcutsStore
- AgentRelayCommandTests
- ArtworkPresentationCoordinator
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
- AgentIngestionCoordinator
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- AgentPresentation.swift
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- AgentBridge
- ClipboardHistoryPresentationState
- .assertFailure
- Foundation
- AgentState
- Codable
- .parse
- AgentBridgeHTTPRequestParser
- AgentBridgeIngress
- Agent Activity Integration Architecture
- AgentEventPayload
- 3. Phase gates
- LiveActivityStore
- Agent Capability Matrix
- Agent Event Schema Draft
- AgentEmbeddedConsoleView
- Error
- .signedRequest
- MenuBarController
- AgentBridgeDiscoveryReadError
- .canonicalMessage
- AgentBridgeHTTPStatus
- Agent Activity Feature Phase Plan
- .resolve
- AgentBridgeEnvelopeBuildError
- SettingsWindowController
- .decode
- AgentRelayExitCode
- AgentNotch Reference Review
- .session
- Phase Workflow For Future Work
- .normalize
- AgentBridgeAuthenticationError
- AgentProducerPolicy
- LaunchAtLoginController.swift
- LockedValue
- .remainingTime
- .normalize
- AgentApprovalController
- UInt64
- CodexJSONValue
- AgentIngestionError
- CodexAppServerProvider
- AgentManagedSessionController
- NowPlayingMediaProvider
- String
- AgentManagedSessionDescriptor
- IslandLayoutStore
- PersistentSnapshotFakeProvider
- AgentIntegrationOperationalState
- SwiftUI
- IslandSurfaceBackground
- CodexAppServerClient
- AgentEventValidationError
- .ingest
- CodexAppServerError
- String
- .wait
- Agent Workspace Execution Plan — 2026-09-27
- .readBoundedCatchUp
- ClipboardHistoryPersistenceFinalizationResult
- AgentIntegrationSetupError
- CodexAppServerClientTests
- AppLaunchService
- Fresh critical audit instructions
- AgentActivityKind
- SettingsView.swift
- AgentOperationStatus
- ExpandedContentScrollSequencePhase
- AppendOnlyFileIdentity
- CollapsedPreviewKind
- Current architecture baseline
- AgentApprovalState
- CodexListedThread
- CodexRolloutRecoveryAdapter
- FileClipboardHistoryPersistence
- CodexHookNormalizationError
- .pause
- AppendOnlyRecordTailerStatus
- CodexAppServerEvent
- CodexRolloutRecoveryError
- AgentSessionScrollRegionPreferenceKey
- AgentSourceRegistryTests.swift
- Array
- .agentOperationalStatusColor
- summary.md

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 342 edges
2. `OverlayWindowController` - 146 edges
3. `AgentSession` - 125 edges
4. `Change Log` - 110 edges
5. `MediaController` - 105 edges
6. `AgentEventStore` - 95 edges
7. `AgentIngestionCoordinator` - 80 edges
8. `IslandRootView` - 78 edges
9. `ExpandedIslandView` - 69 edges
10. `UInt64` - 68 edges

## Surprising Connections (you probably didn't know these)
- `A1 — Normalized domain, `AgentEventStore`, replay harness` --references--> `AgentEventStore`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/Agents/AgentEventStore.swift
- `A4.1 Claude recovery authority` --references--> `ClaudeTranscriptRecoveryAdapter`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/Agents/ClaudeTranscriptRecovery.swift
- `2026-07-03 - Common App Launch Resolver` --references--> `AppLaunchService`  [INFERRED]
  context.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `A10 — Source app/editor association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_FEATURE_PHASE_PLAN_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift
- `9. Source association and Open action` --references--> `AppLaunchService`  [INFERRED]
  research/AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md → Sources/DynamicIsland/App/AppLaunchService.swift

## Import Cycles
- None detected.

## Communities (201 total, 13 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (162): AnyPublisher, Never, AppSettings, .activitiesEnabled, .agentActivityEnabled, .agentApprovalAlertsEnabled, .agentCompletionAlertsEnabled, .agentPeekDurationSeconds (+154 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.08
Nodes (37): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, IslandGestureAction, collapse, .displayName, expand, .id, mediaNextTrack (+29 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.07
Nodes (23): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, ifaddrs, CPUCounters, NetworkCounters, Bool, Date, Double (+15 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.20
Nodes (7): ArtworkFlipPresentationState, .queuedSnapshot, ArtworkPresentationSnapshot, QueuedTransition, ArtworkFlipPresentationStateTests, Bool, String

### Community 4 - "SettingsView"
Cohesion: 0.17
Nodes (25): content, HelpText, .body, SettingsGroup, .body, SettingsView, .advancedSection, .agentsSection (+17 more)

### Community 5 - "IslandRootView"
Cohesion: 0.07
Nodes (36): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-04 - Phase 5J Single Visual Surface Morph, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock, Phase 11C.9 - Predictive Space Motion Resampling, Phase 12A.2 - Single Authoritative Shell/Content Timeline, Phase 13A - Expanded Visibility Controls, Phase 13B.1 - Clipboard History Engine (+28 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.14
Nodes (15): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date (+7 more)

### Community 8 - "TimerController"
Cohesion: 0.10
Nodes (20): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration (+12 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.07
Nodes (25): ImageIO, NSPasteboard, NSPasteboardItem, ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture (+17 more)

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.10
Nodes (20): Bool, Duration, Never, String, Task, TimeInterval, Void, SystemTimerNotificationCenterClient (+12 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.07
Nodes (29): ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint, ClipboardHistoryPayload, .byteCount (+21 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.08
Nodes (29): 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry (+21 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.17
Nodes (8): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Date, String, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.08
Nodes (19): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+11 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.13
Nodes (5): CollapsedLiveActivitySelectorTests, Bool, Date, Int, String

### Community 16 - "IslandNavigationStore"
Cohesion: 0.12
Nodes (16): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, agents, island, stats, .symbolName (+8 more)

### Community 17 - ".start"
Cohesion: 0.22
Nodes (6): TimerCompletionNotificationPreferences, MockTimerNotificationCenterClient, Bool, String, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults (+8 more)

### Community 19 - "SupportedApp"
Cohesion: 0.14
Nodes (14): SupportedApp, arc, brave, .bundleIdentifier, chrome, .displayName, edge, .fallbackPaths (+6 more)

### Community 20 - "View"
Cohesion: 0.13
Nodes (14): ExpandedHeaderButton, ExpandedIslandPageSwitcher, ExpandedIslandView, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation, .tabAnimationsEnabled, .tabFadeInAnimation (+6 more)

### Community 21 - "Change Log"
Cohesion: 0.05
Nodes (67): Animation, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish (+59 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (17): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+9 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (36): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+28 more)

### Community 25 - "ObservableObject"
Cohesion: 0.09
Nodes (20): Calendar, ObservableObject, UUID, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView (+12 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (49): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+41 more)

### Community 27 - "Int"
Cohesion: 0.11
Nodes (12): ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer, .maxShelfFiles (+4 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.13
Nodes (20): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+12 more)

### Community 29 - "OverlayWindowController"
Cohesion: 0.09
Nodes (24): CFTimeInterval, 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, DispatchWorkItem, NSPanel, NSPoint, IslandOverlayPanel, .canBecomeKey (+16 more)

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
Cohesion: 0.10
Nodes (25): Comparable, RawRepresentable, AgentProducerDescriptor, AgentProducerEpoch, AgentProducerHandle, AgentSourceHealthError, identityConflict, invalidEvent (+17 more)

### Community 34 - "Data"
Cohesion: 0.09
Nodes (19): CryptoKit, OSStatus, Security, Data, AgentBridgeAuthenticator, .rememberedNonceCount, AgentBridgeCredentialError, invalidStoredSecret (+11 more)

### Community 35 - "XCTest"
Cohesion: 0.09
Nodes (4): AppKit, DynamicIsland, UniformTypeIdentifiers, XCTest

### Community 36 - "AppendOnlyRecordTailer"
Cohesion: 0.15
Nodes (10): DispatchSourceFileSystemObject, NoticeHandler, RecordHandler, 6. Privacy and security boundaries, A2.1 ingress boundary and A2.2 handoff, AppendOnlyRecordTailer, AppendOnlyRecordTailerHealth, AppendOnlyRecordTailerSignalToken (+2 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.04
Nodes (59): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, Double, AlbumArtworkView, .body (+51 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.13
Nodes (15): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Phase 2.7 Media Source Arbitration, MediaDetectionProvider, MediaSnapshot, MediaSourceKind, browser, music, spotify (+7 more)

### Community 39 - "MediaSourceIdentity"
Cohesion: 0.10
Nodes (20): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, Index, Media and artwork, Array, ArtworkFlipPhase, firstHalf (+12 more)

### Community 40 - "FileDropProviderLoader"
Cohesion: 0.17
Nodes (12): FileDropProviderLoader, UTType, .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider (+4 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "YouTubeMetadataProvider"
Cohesion: 0.30
Nodes (9): CodingKeys, authorName, thumbnailURL, title, OEmbedResponse, String, URL, YouTubeMetadata (+1 more)

### Community 43 - "String"
Cohesion: 0.10
Nodes (16): BrowserScriptTarget, Decision, MediaCandidate, .sourceKey, MediaController, .currentArtworkPresentationIdentity, MediaPlayer, .displayName (+8 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.07
Nodes (26): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, App Entry, Collapsed, Current Architecture, Current Stable Baseline (+18 more)

### Community 46 - "AppSettingsTests"
Cohesion: 0.12
Nodes (3): AppSettingsTests, String, UserDefaults

### Community 47 - "CGFloat"
Cohesion: 0.09
Nodes (24): AnimatablePair, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, SwiftUI rendering and presentation, Shape, DedicatedTimerPageView, .body, .controlsFontSize, .controlsSpacing (+16 more)

### Community 48 - "AgentIntegrationProvider"
Cohesion: 0.06
Nodes (36): AgentHookConfigurationPlanner, AgentIntegrationBackupEnvelope, AgentIntegrationProvider, claude, codex, .desiredEvents, .displayName, .helperExecutableName (+28 more)

### Community 49 - "Bool"
Cohesion: 0.14
Nodes (3): Bool, Date, NSEvent

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.07
Nodes (34): Phase 13B.2 - Native In-Island Clipboard Interface, EnvironmentKey, Gesture, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, CollapseShellOnlyEnvironmentKey (+26 more)

### Community 52 - "Sendable"
Cohesion: 0.05
Nodes (82): Equatable, 1. Domain contracts, Sendable, AgentBridgeSharedError, invalidNonce, randomUnavailable, AgentBridgeHealth, AgentBridgeIngestionResult (+74 more)

### Community 53 - "IslandThemeStyle"
Cohesion: 0.16
Nodes (9): 2026-07-11 - Phase 9D Theme Simplification, IslandThemeStyle, classicBlack, .displayName, .id, liquidGlass, Bool, T (+1 more)

### Community 54 - "CompactIslandView"
Cohesion: 0.05
Nodes (62): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair, 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair, 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, AgentCompactSummaryLabel (+54 more)

### Community 55 - "RecordSink"
Cohesion: 0.17
Nodes (11): AppendOnlyRecordTailerTests, Fixture, NoticeSink, openDescriptorCount(), RecordSink, .strings, Bool, Int (+3 more)

### Community 56 - "ClipboardImageCaptureLifecycleTests"
Cohesion: 0.19
Nodes (8): ClipboardImageCaptureLifecycleTests, SuspendedClipboardImageProcessor, async, CheckedContinuation, MainActor, Never, Sendable, XCTestExpectation

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".event"
Cohesion: 0.22
Nodes (9): Success, AgentIngestionCoordinatorTests, Result, Set, StaticString, String, UInt, XCTAssertFailure() (+1 more)

### Community 59 - ".sessionID"
Cohesion: 0.15
Nodes (11): AgentReductionResult, AgentEventReducerTests, Set, String, TimeInterval, AgentTestFixture, Date, Int (+3 more)

### Community 60 - "AgentProvider"
Cohesion: 0.05
Nodes (66): AnyView, Identifiable, AgentProvider, claude, codex, .deterministicSortKey, other, .stableName (+58 more)

### Community 61 - "AgentBridgeClient"
Cohesion: 0.09
Nodes (19): AgentBridgeClient, AgentBridgeClientResult, accepted, rejected, AgentBridgeClientTransport, Date, Int, String (+11 more)

### Community 62 - "IslandHostingView"
Cohesion: 0.10
Nodes (17): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, Known Fragile Areas, NSHostingView, NSSize (+9 more)

### Community 63 - "XCTestCase"
Cohesion: 0.12
Nodes (18): ControlledMediaRemoteCallback, ControlledMediaRemoteProvider, Entry, ManualMediaRemoteDeadlineScheduler, .count, .scheduler, MediaRemoteCallbackBridgeTests, MediaRemoteRefreshRecoveryTests (+10 more)

### Community 64 - "CaseIterable"
Cohesion: 0.05
Nodes (44): CaseIterable, AnimationPreset, .displayName, .id, instant, normal, .shellDuration, slow (+36 more)

### Community 65 - "AgentEventStore"
Cohesion: 0.13
Nodes (10): AgentEventStore, .activeSessions, .sessionsRequiringAttention, Bool, AgentActivityDashboardView, .body, AgentEventStoreTests, Int (+2 more)

### Community 66 - ".makeProcessor"
Cohesion: 0.26
Nodes (6): AgentBridgeEnvelopeIntegrationTests, StaticString, String, UInt, Any, String

### Community 67 - "AgentBridgeClientProfile"
Cohesion: 0.14
Nodes (16): AgentBridgeClientProfile, AgentBridgeClientRequest, AgentBridgeClientResponse, AgentBridgeDiscoveryRecord, AgentBridgeProtocol, Date, Int, Int32 (+8 more)

### Community 68 - "ControlledClipboardPersistence"
Cohesion: 0.22
Nodes (7): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, Bool, Int, TimeInterval

### Community 69 - "AppDelegate"
Cohesion: 0.12
Nodes (14): NSApplicationDelegate, 2. Existing DynamicIsland invariants, TimeInterval, AppDelegate, .liveActivitySettingsPublisher, LiveActivitySettingsSnapshot, Any, AnyCancellable (+6 more)

### Community 70 - "String"
Cohesion: 0.19
Nodes (12): SystemStatsSnapshot, LiveStatusIndicator, .body, StatsLineChart, .body, StatsMetricCard, .body, StatsPageView (+4 more)

### Community 71 - "ExpandedScrollEventRoutingPolicyTests"
Cohesion: 0.13
Nodes (9): ExpandedContentScrollSequenceOwnership, ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicy, Owner, island, ExpandedScrollEventRoutingPolicyTests (+1 more)

### Community 72 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 73 - "AppendOnlyRecordTailer.swift"
Cohesion: 0.11
Nodes (19): Dispatch, AppendOnlyRecordLimits, AppendOnlyRecordStartPolicy, boundedCatchUp, fromEnd, AppendOnlyRecordTailerFailure, identityRace, ioFailure (+11 more)

### Community 74 - "DelimitedRecordFramer"
Cohesion: 0.20
Nodes (7): BoundedRecordRing, .orderedRecords, DelimitedRecordFramer, Output, Int, Void, DelimitedRecordFramerTests

### Community 75 - "completion"
Cohesion: 0.23
Nodes (7): NSSecureCoding, completion, FileDropURLAccumulator, .urls, SendableItemProvider, NSItemProvider, TimeInterval

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.15
Nodes (8): AgentBridgeDiscoveryPublisher, FileManager, String, URL, AgentBridgeDiscoveryTests, String, UInt16, URL

### Community 77 - "AgentCapability"
Cohesion: 0.07
Nodes (29): AgentCapabilities, .all, AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage, costUsage (+21 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.23
Nodes (8): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL, AirDropURLAccumulator, .urls, NSItemProvider, URL

### Community 80 - "AgentSessionInstanceID"
Cohesion: 0.07
Nodes (45): Hashable, 7. Attention presentation contract, AgentAttentionCoordinator, Date, Never, Task, Void, AgentAttentionBadge (+37 more)

### Community 83 - "SequenceClientTransport"
Cohesion: 0.21
Nodes (8): AgentBridgeEnvelopeBuilder, Any, String, AgentBridgeSharedClientTests, SequenceClientTransport, SequenceProfileProvider, Int, String

### Community 84 - ".apply"
Cohesion: 0.09
Nodes (17): AgentEventReducer, AgentEventStoreLimits, .normalized, SemanticResult, applied, rejected, Bool, Date (+9 more)

### Community 85 - "AgentBridgeDiscoveryReader"
Cohesion: 0.08
Nodes (26): dev_t, ino_t, AgentBridgeDiscoveryFileReading, AgentBridgeDiscoveryFileSnapshot, AgentBridgeDiscoveryReader, Bool, Date, Int (+18 more)

### Community 86 - "AgentEventType"
Cohesion: 0.06
Nodes (34): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+26 more)

### Community 87 - "AgentEventApplication"
Cohesion: 0.12
Nodes (18): AgentEventApplication, applied, duplicate, ignoredAfterTerminal, ignoredWeakerEvidence, rejected, staleGeneration, AgentEventBatchApplication (+10 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.15
Nodes (11): LauncherShortcut, ShortcutsStore, .shortcuts, String, UUID, ShortcutsModuleView, .body, .displayedShortcuts (+3 more)

### Community 89 - "AgentRelayCommandTests"
Cohesion: 0.13
Nodes (11): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000) (+3 more)

### Community 90 - "ArtworkPresentationCoordinator"
Cohesion: 0.13
Nodes (19): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted, none, queued, staleTransitionDiscarded (+11 more)

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

### Community 97 - "SettingsSection"
Cohesion: 0.12
Nodes (16): SettingsSection, advanced, agents, appearance, clipboard, gestures, .id, island (+8 more)

### Community 103 - ".progress"
Cohesion: 0.22
Nodes (6): Double, TimerProgressColorStage, high, low, mid, TimerProgressFormattingTests

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentReplayHarness"
Cohesion: 0.19
Nodes (5): AgentReplayHarness, Int, AgentReplayHarnessTests, String, TimeInterval

### Community 106 - "AgentIngestionCoordinator"
Cohesion: 0.08
Nodes (33): 3. Component boundaries, Adapter contract, State ownership, AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible (+25 more)

### Community 107 - "LiveActivitySettingsSubscriberTests"
Cohesion: 0.25
Nodes (3): LiveActivitySettingsSubscriberTests, String, UserDefaults

### Community 108 - "ShelfFileTile"
Cohesion: 0.23
Nodes (9): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, String (+1 more)

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.22
Nodes (7): FileDropPolicy, FileShelfTemporaryStorage, Bool, String, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "AgentPresentation.swift"
Cohesion: 0.05
Nodes (40): Int, AgentApprovalPresentation, AgentCollapsedShellPresentation, AgentOperationAggregation, AgentOperationSummary, .displayTitle, AgentPresentationPriority, actionRequired (+32 more)

### Community 111 - "ServerFactorySpy"
Cohesion: 0.22
Nodes (9): AgentBridgeLifecycleTests, DiscoverySpy, .records, .removedLaunchIDs, ServerFactorySpy, .createdCount, AgentBridgeServerFactory, Error (+1 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.11
Nodes (19): AgentBridgeEnvelopeError, emptyBatch, eventTooLarge, generationConflict, invalidAuthority, invalidCapability, invalidEventType, invalidPayload (+11 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.20
Nodes (10): DispatchQueue, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, NWConnection, Result (+2 more)

### Community 114 - "AgentBridge"
Cohesion: 0.16
Nodes (13): HTTPURLResponse, AgentBridge, LaunchMaterial, ProducerRuntime, Runtime, AgentBridgeServerFactory, Error, UUID (+5 more)

### Community 115 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 116 - ".assertFailure"
Cohesion: 0.19
Nodes (3): AgentBridgeHTTPParserTests, StaticString, UInt

### Community 117 - "Foundation"
Cohesion: 0.08
Nodes (7): AgentBridgeShared, ClaudeHookShared, CodexHookShared, CoreFoundation, Darwin, Foundation, IOKit.ps

### Community 118 - "AgentState"
Cohesion: 0.07
Nodes (31): AgentState, completed, failed, idle, interrupted, .isTerminal, planning, planReady (+23 more)

### Community 119 - "Codable"
Cohesion: 0.07
Nodes (38): Codable, CodingKey, AgentEventOrigin, live, localRecovery, replay, AgentUsage, .allSamples (+30 more)

### Community 120 - ".parse"
Cohesion: 0.10
Nodes (17): ClaudeTranscriptRecoveryAdapter, ClaudeTranscriptRecoveryError, malformedRecord, missingSession, unsupportedRecord, ClaudeTranscriptRecoveryParser, OperationKind, command (+9 more)

### Community 121 - "AgentBridgeHTTPRequestParser"
Cohesion: 0.21
Nodes (10): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, Bool (+2 more)

### Community 122 - "AgentBridgeIngress"
Cohesion: 0.24
Nodes (7): AgentBridgeIngress, AgentBridgePermissionRequestProcessor, AgentBridgeRequestProcessor, Bool, Date, Result, String

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.12
Nodes (17): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 5. Local bridge decision, 8. Expanded Agent Activity contract, 9. Source association and Open action (+9 more)

### Community 124 - "AgentEventPayload"
Cohesion: 0.10
Nodes (40): Decodable, AgentBridgeLimits, AgentBridgeWireCapability, AgentBridgeWireEvent, AgentBridgeWirePayload, .populatedFieldCount, AgentBridgeWireRequest, .eventBatch (+32 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.11
Nodes (18): 3. Phase gates, A0 — Research and architecture, A10 — Source app/editor association and Open action, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2.1 — Ingestion coordination and source registry, A2.2 — Relay client and append-only ingestion primitives, A2 — Authenticated local Agent Bridge (+10 more)

### Community 126 - "LiveActivityStore"
Cohesion: 0.27
Nodes (6): LiveActivityStore, .primaryActivity, LiveActivityStoreTests, Date, Int, String

### Community 127 - "Agent Capability Matrix"
Cohesion: 0.12
Nodes (16): 1. Method and version boundary, 2. Primary supported integration surfaces, 3. Capability matrix, 4. Event-specific authority, 5. Local storage audit (content redacted), 6. Source application association, 7. Design implications, 8. Official sources (+8 more)

### Community 128 - "Agent Event Schema Draft"
Cohesion: 0.12
Nodes (16): 2. State vocabulary, 3. Session identity, 4. Normalized event types, 5. Versioned transport envelope, 6. Capability model, 7. Privacy projection, 8. Replay fixture contract, 9. Deferred decisions (+8 more)

### Community 129 - "AgentEmbeddedConsoleView"
Cohesion: 0.07
Nodes (28): NSObject, NSScrollView, NSTextView, NSTextViewDelegate, NSViewRepresentable, AgentConsoleMode, .canInterrupt, interactive (+20 more)

### Community 130 - "Error"
Cohesion: 0.07
Nodes (32): Error, AgentBridgeClientTransportError, connectTimedOut, malformedResponse, requestTimedOut, responseTooLarge, unavailable, AgentBridgeNetworkExchange (+24 more)

### Community 131 - ".signedRequest"
Cohesion: 0.31
Nodes (4): AgentBridgeHTTPRequest, AgentBridgeAuthenticationTests, AgentBridgeTestSupport, Int64

### Community 132 - "MenuBarController"
Cohesion: 0.31
Nodes (3): NSStatusItem, MenuBarController, Void

### Community 133 - "AgentBridgeDiscoveryReadError"
Cohesion: 0.12
Nodes (16): AgentBridgeDiscoveryReadError, changedDuringRead, invalidAuthentication, invalidHost, invalidIdentifier, invalidPort, invalidProcess, invalidTimestamp (+8 more)

### Community 134 - ".canonicalMessage"
Cohesion: 0.26
Nodes (7): AgentBridgeRequestAuthentication, Bool, Int, Int64, String, AgentBridgeSharedCryptoTests, String

### Community 136 - "AgentBridgeHTTPStatus"
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.20
Nodes (10): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, A3.1 implementation refinement — Codex structured recovery, A3 implementation refinement — Codex authoritative hooks, A4.1 implementation refinement — Claude transcript recovery, A4.5 implementation refinement — bounded OTLP JSON enrichment (+2 more)

### Community 139 - "AgentBridgeEnvelopeBuildError"
Cohesion: 0.08
Nodes (25): AgentBridgeClientError, authenticationFailed, discoveryUnavailable, invalidInput, malformedResponse, timedOut, transportUnavailable, AttemptError (+17 more)

### Community 140 - "SettingsWindowController"
Cohesion: 0.22
Nodes (6): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, NSWindowDelegate, SettingsWindowController, Notification, NSWindow

### Community 141 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

### Community 142 - "AgentRelayExitCode"
Cohesion: 0.10
Nodes (19): Int32, AgentRelayCommand, AgentRelayCommandResult, AgentRelayExitCode, accepted, authenticationFailed, bridgeUnavailable, discoveryUnavailable (+11 more)

### Community 143 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 144 - ".session"
Cohesion: 0.10
Nodes (7): Self, .body, AgentPresentationTests, Date, Double, Set, String

### Community 145 - "Phase Workflow For Future Work"
Cohesion: 0.07
Nodes (22): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-03 - Phase 2 Empty Media Launcher State (+14 more)

### Community 146 - ".normalize"
Cohesion: 0.10
Nodes (16): ClaudeHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook, ClaudeHookNormalizer (+8 more)

### Community 147 - "AgentBridgeAuthenticationError"
Cohesion: 0.22
Nodes (9): AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull, timestampOutsideWindow (+1 more)

### Community 148 - "AgentProducerPolicy"
Cohesion: 0.07
Nodes (31): AgentAuthorityDomain, activity, capability, interaction, lifecycle, liveness, metadata, operation (+23 more)

### Community 149 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 150 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 152 - ".normalize"
Cohesion: 0.11
Nodes (11): CodexHookNormalizer, CodexHookStandardInput, CodexPermissionHookOutput, Any, Bool, Date, FileHandle, Int (+3 more)

### Community 153 - "AgentApprovalController"
Cohesion: 0.13
Nodes (22): AgentBridgePermissionDecision, allow, deny, AgentApprovalControlKey, AgentApprovalController, AgentApprovalControlRequest, .id, AgentApprovalControlResult (+14 more)

### Community 154 - "UInt64"
Cohesion: 0.20
Nodes (11): AgentIngestionEvent, .sessionID, UInt64, CodexRolloutRecoveryParser, Any, Date, Double, Int (+3 more)

### Community 155 - "CodexJSONValue"
Cohesion: 0.07
Nodes (23): AgentInteractiveRequestToken, integer, string, Int64, CodexJSONValue, array, .arrayValue, bool (+15 more)

### Community 156 - "AgentIngestionError"
Cohesion: 0.07
Nodes (28): AgentIngestionError, capabilityCapacity, generationConflict, identityConflict, invalidDescriptor, invalidEvent, invalidProducer, leaseCapacity (+20 more)

### Community 157 - "CodexAppServerProvider"
Cohesion: 0.13
Nodes (6): CodexAppServerProvider, Any, Bool, Date, Double, String

### Community 158 - "AgentManagedSessionController"
Cohesion: 0.18
Nodes (11): AgentInteractiveProvider, AgentManagedSessionController, .isAvailable, Bool, Error, Never, Set, String (+3 more)

### Community 159 - "NowPlayingMediaProvider"
Cohesion: 0.14
Nodes (14): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, MediaRemoteClient, .isAvailable, MediaRemoteDictionary, MediaRemoteProviding, NowPlayingMediaProvider (+6 more)

### Community 160 - "String"
Cohesion: 0.31
Nodes (7): AgentOTLPJSONDecoder, AgentTelemetryObservation, .isEmpty, Any, Date, Double, String

### Community 161 - "AgentManagedSessionDescriptor"
Cohesion: 0.12
Nodes (12): AgentDiscoveredSessionDescriptor, AgentDiscoveredSessionRuntimeState, active, idle, notLoaded, systemError, AgentManagedSessionDescriptor, .sessionID (+4 more)

### Community 162 - "IslandLayoutStore"
Cohesion: 0.18
Nodes (7): 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, IslandCanvasCoordinateSpace, IslandLayoutStore, Bool, CGFloat, CGRect, CGSize

### Community 163 - "PersistentSnapshotFakeProvider"
Cohesion: 0.28
Nodes (3): AgentManagedSessionControllerTests, PersistentSnapshotFakeProvider, Bool

### Community 164 - "AgentIntegrationOperationalState"
Cohesion: 0.12
Nodes (13): AgentIntegrationDiagnostics, AgentIntegrationOperationalState, active, awaitingFirstEvent, blocked, degraded, failed, .label (+5 more)

### Community 165 - "SwiftUI"
Cohesion: 0.12
Nodes (5): Combine, QuartzCore, DynamicIslandApp, Key, SwiftUI

### Community 166 - "IslandSurfaceBackground"
Cohesion: 0.11
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 167 - "CodexAppServerClient"
Cohesion: 0.18
Nodes (11): Pipe, Process, CodexAppServerClient, PendingRequest, AsyncStream, CheckedContinuation, Duration, Never (+3 more)

### Community 168 - "AgentEventValidationError"
Cohesion: 0.12
Nodes (14): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+6 more)

### Community 169 - ".ingest"
Cohesion: 0.21
Nodes (4): AgentSessionContinuity, AgentTelemetryFusion, AgentTelemetryFusionTests, Double

### Community 170 - "CodexAppServerError"
Cohesion: 0.16
Nodes (10): CodexAppServerError, executableNotFound, launchFailed, malformedMessage, notRunning, requestTimedOut, rpcError, transportClosed (+2 more)

### Community 171 - "String"
Cohesion: 0.30
Nodes (5): .result, invalidResponse, CodexManagedThread, CodexManagedTurn, String

### Community 172 - ".wait"
Cohesion: 0.26
Nodes (12): Completion, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending, MediaRemoteDeadlineScheduler, MediaRemoteDeadlineToken, Bool, CheckedContinuation (+4 more)

### Community 173 - "Agent Workspace Execution Plan — 2026-09-27"
Cohesion: 0.14
Nodes (13): Agent Workspace Execution Plan — 2026-09-27, Frozen invariants, Iteration rule, Phase 1 — Gesture-safe session scrolling, Phase 2 — Agents-specific expanded geometry, Phase 3.5 — Real-device workspace stabilization, Phase 3 — Enclosed workspace + session selection, Phase 4 — Embedded agent console UI (+5 more)

### Community 174 - ".readBoundedCatchUp"
Cohesion: 0.31
Nodes (3): OpenFile, Int32, Int64

### Community 175 - "ClipboardHistoryPersistenceFinalizationResult"
Cohesion: 0.23
Nodes (9): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+1 more)

### Community 176 - "AgentIntegrationSetupError"
Cohesion: 0.17
Nodes (12): AgentIntegrationSetupError, backupInvalid, backupUnavailable, changedExternally, fileTooLarge, helperUnavailable, invalidHooks, invalidJSON (+4 more)

### Community 177 - "CodexAppServerClientTests"
Cohesion: 0.27
Nodes (3): CodexAppServerClientTests, String, URL

### Community 178 - "AppLaunchService"
Cohesion: 0.44
Nodes (4): AppLaunchService, Bool, String, URL

### Community 179 - "Fresh critical audit instructions"
Cohesion: 0.18
Nodes (9): Interpreter guard for subcommands, Path, Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits (+1 more)

### Community 180 - "AgentActivityKind"
Cohesion: 0.18
Nodes (11): AgentActivityKind, approval, command, failure, interruption, plan, session, subagent (+3 more)

### Community 181 - "SettingsView.swift"
Cohesion: 0.20
Nodes (9): PriorityStepperRow, .body, .liveActivitiesSection, ShortcutEditorRow, .body, Binding, Int, Void (+1 more)

### Community 182 - "AgentOperationStatus"
Cohesion: 0.20
Nodes (9): AgentOperationStatus, active, cancelled, completed, failed, pending, resolved, unknown (+1 more)

### Community 183 - "ExpandedContentScrollSequencePhase"
Cohesion: 0.20
Nodes (10): ExpandedContentScrollSequencePhase, momentumBegan, momentumCancelled, momentumChanged, momentumEnded, phaseLess, physicalBegan, physicalCancelled (+2 more)

### Community 184 - "AppendOnlyFileIdentity"
Cohesion: 0.25
Nodes (5): AppendOnlyFileIdentity, AppendOnlyRecordTailerIOError, failure, missing, stat

### Community 185 - "CollapsedPreviewKind"
Cohesion: 0.25
Nodes (8): 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, CollapsedPreviewKind, battery, fileDrop, liveActivity, media, none, timer

### Community 186 - "Current architecture baseline"
Cohesion: 0.25
Nodes (7): Activities and utility modules, Build and tests, Clipboard engine and persistence, Composition, state and settings, Current architecture baseline, Evidence and graph limits, IslandModule

### Community 187 - "AgentApprovalState"
Cohesion: 0.25
Nodes (8): AgentApprovalState, approved, cancelled, denied, expired, .isResolved, pending, unknown

### Community 188 - "CodexListedThread"
Cohesion: 0.32
Nodes (4): CodexListedThread, Date, Int, value

### Community 189 - "CodexRolloutRecoveryAdapter"
Cohesion: 0.50
Nodes (3): CodexRolloutRecoveryAdapter, Bool, URL

### Community 190 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 191 - "CodexHookNormalizationError"
Cohesion: 0.29
Nodes (7): CodexHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook

### Community 193 - "AppendOnlyRecordTailerStatus"
Cohesion: 0.33
Nodes (6): AppendOnlyRecordTailerStatus, degraded, failed, stopped, tailing, waitingForFile

### Community 194 - "CodexAppServerEvent"
Cohesion: 0.33
Nodes (5): CodexAppServerEvent, notification, serverRequest, String, .nilIfEmpty

### Community 195 - "CodexRolloutRecoveryError"
Cohesion: 0.40
Nodes (5): CodexRolloutRecoveryError, invalidUsage, malformedRecord, missingSession, unsupportedRecord

### Community 196 - "AgentSessionScrollRegionPreferenceKey"
Cohesion: 0.67
Nodes (3): PreferenceKey, AgentSessionScrollRegionPreferenceKey, CGRect

### Community 197 - "AgentSourceRegistryTests.swift"
Cohesion: 0.50
Nodes (3): Array, .single, Element

### Community 198 - "Array"
Cohesion: 0.67
Nodes (3): Array, .single, Element

## Knowledge Gaps
- **1137 isolated node(s):** `PackageDescription`, `package_app.sh script`, `unavailable`, `connectTimedOut`, `requestTimedOut` (+1132 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1498 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `SettingsWindowController`, `NotchGeometryService`, `.normalizeAndSaveDouble`, `ClipboardHistoryStoreTests`, `IslandNavigationStore`, `FileShelfStore`, `View`, `Change Log`, `ObservableObject`, `Int`, `DynamicIslandLiveActivity`, `OverlayWindowController`, `SwiftUI`, `MediaModuleView`, `FileDropProviderLoader`, `String`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `IslandRootView.swift`, `IslandThemeStyle`, `CompactIslandView`, `ClipboardImageCaptureLifecycleTests`, `OverlayPresentationSessionTests`, `AgentProvider`, `CaseIterable`, `AgentEventStore`, `AppDelegate`, `String`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`?**
  _High betweenness centrality (0.124) - this node is a cross-community bridge._
- **Why does `Data` connect `Data` to `Error`, `.signedRequest`, `.canonicalMessage`, `ClipboardHistoryStore`, `SystemClipboardPasteboardClient`, `ClipboardHistoryPayload`, `.decode`, `AgentRelayExitCode`, `ClipboardHistoryStoreTests`, `.normalize`, `.normalize`, `AgentApprovalController`, `UInt64`, `ObservableObject`, `ClipboardImageNormalizerTests`, `String`, `CodexAppServerClient`, `FileDropProviderLoader`, `CodexAppServerError`, `YouTubeMetadataProvider`, `.readBoundedCatchUp`, `ClipboardHistoryPersistenceFinalizationResult`, `AgentIntegrationProvider`, `RecordSink`, `ClipboardImageCaptureLifecycleTests`, `AgentBridgeClient`, `CodexRolloutRecoveryAdapter`, `FileClipboardHistoryPersistence`, `.makeProcessor`, `AgentBridgeClientProfile`, `ControlledClipboardPersistence`, `DelimitedRecordFramer`, `SequenceClientTransport`, `AgentBridgeDiscoveryReader`, `AgentRelayCommandTests`, `AgentBridge`, `.assertFailure`, `.parse`, `AgentBridgeHTTPRequestParser`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **Why does `IslandRootView` connect `IslandRootView` to `AppSettings`, `IslandGestureAction`, `IslandEscapeRouter`, `SettingsWindowController`, `IslandNavigationStore`, `View`, `Change Log`, `DynamicIsland`, `DynamicIslandLiveActivity`, `OverlayWindowController`, `IslandLayoutStore`, `MediaModuleView`, `String`, `IslandStateStore`, `CGFloat`, `IslandRootView.swift`, `Fresh critical audit instructions`, `CompactIslandView`, `IslandHostingView`, `AppDelegate`, `AgentSessionInstanceID`, `ArtworkPresentationCoordinator`, `FileShelfTemporaryStorage`, `LiveActivityStore`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **Are the 31 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 31 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `unavailable` to the rest of the system?**
  _1137 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppSettings` be split into smaller, more focused modules?**
  _Cohesion score 0.02370673331818526 - nodes in this community are weakly interconnected._