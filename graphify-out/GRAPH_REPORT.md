# Graph Report - DynamicIsland  (2026-09-26)

## Corpus Check
- 159 files · ~199,611 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 4799 nodes · 13854 edges · 188 communities (174 shown, 14 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1752 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `87611afc`
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
- ObservableObject
- MediaAutomationExecutor
- Int
- DynamicIslandLiveActivity
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- AgentProducerHandle
- AgentBridgeAuthenticator
- XCTest
- AppendOnlyRecordTailer
- MediaModuleView
- MediaSnapshot
- Phase Workflow For Future Work
- FileDropProviderLoader
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
- AgentAttentionEvent
- Equatable
- .reload
- CompactIslandView
- RecordSink
- ClipboardPasteboardReadResult
- OverlayPresentationSessionTests
- .event
- .sessionID
- IslandPointerGestureModifier
- AgentBridgeClient
- IslandHostingView
- ManualMediaRemoteDeadlineScheduler
- CaseIterable
- AgentEventStore
- .makeProcessor
- Sendable
- ControlledClipboardPersistence
- AppDelegate
- UInt64
- ExpandedScrollEventRoutingPolicyTests
- DynamicIslandLiveActivityKind
- AppendOnlyRecordTailer.swift
- DelimitedRecordFramer
- completion
- AgentBridgeDiscoveryPublisher
- AgentCapability
- Meaningful regression history
- .loadFileURLs
- AgentIntegrationSetupService
- Package.swift
- package_app.sh
- SequenceClientTransport
- .apply
- AgentBridgeSharedDiscoveryTests
- AgentEventType
- AgentEventValidationError
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
- AgentEvent
- AgentBridgeDiscoveryReader
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- NetworkCounters
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- .start
- ClipboardHistoryPresentationState
- .assertFailure
- Foundation
- .parse
- AgentBridgeClientProfile
- AgentIngestionCoordinator
- AgentBridgeHTTPRequestParser
- AgentBridgeModels.swift
- Agent Activity Integration Architecture
- .normalize
- 3. Phase gates
- LiveActivityStore
- Agent Capability Matrix
- Agent Event Schema Draft
- .normalize
- Error
- .signedRequest
- MenuBarController
- AgentBridgeDiscoveryReadError
- Data
- AgentBridgeHTTPStatus
- Agent Activity Feature Phase Plan
- .resolve
- AgentBridgeEnvelopeBuildError
- SettingsWindowController
- .decode
- AgentRelayExitCode
- AgentNotch Reference Review
- AgentIngestionEvent
- XCTestCase
- AgentBridgeAuthenticationError
- AgentProvider
- MediaRemoteClient
- LaunchAtLoginController.swift
- LockedValue
- .remainingTime
- AgentIntegrationOperationalState
- AgentIntegrationProvider
- AgentIngestionModels.swift
- AgentIntegrationSetupTests
- .session
- .stateLabel
- AgentActivityViews.swift
- AgentSessionCard
- IslandSurfaceBackground
- NowPlayingMediaProvider
- IslandLayoutStore
- IslandOverlayPanel
- AgentState
- ClipboardHistoryPersistenceFinalizationResult
- AgentIngestionError
- AgentIntegrationSetupError
- AgentActivityKind
- AgentBridgeClientTransportError
- ExpandedIslandPage
- AgentSourceHealthError
- SwiftUI
- FileClipboardHistoryPersistence
- Fresh critical audit instructions
- ClaudeHookNormalizationError
- AgentSourceHealthState
- AgentIntegrationSetupState
- AgentPresentationPriority
- AgentOTLPJSONError
- ShortcutEditorRow
- ClaudeTranscriptRecoveryError
- CodexRolloutRecoveryError
- .subscript
- 5. Local bridge decision
- AgentActivityDashboardView
- AgentSourceRegistryTests.swift

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 340 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 105 edges
5. `AgentEventStore` - 79 edges
6. `AgentSession` - 75 edges
7. `IslandRootView` - 75 edges
8. `ExpandedIslandView` - 69 edges
9. `AgentIngestionCoordinator` - 66 edges
10. `AgentEvent` - 65 edges

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

## Communities (188 total, 14 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (162): AnyPublisher, Never, AppSettings, .activitiesEnabled, .agentActivityEnabled, .agentApprovalAlertsEnabled, .agentCompletionAlertsEnabled, .agentPeekDurationSeconds (+154 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.08
Nodes (38): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, .now, IslandGestureAction, collapse, .displayName, expand, .id (+30 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.13
Nodes (12): 2026-07-04 - Phase 5D Stats Tab, CPUCounters, Bool, Date, Double, Int, Timer, SystemStatsController (+4 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.14
Nodes (17): ArtworkFlipPresentationEffect, displayedDirectly, firstHalfStarted, midpointCommitted, none, queued, staleTransitionDiscarded, transitionCompleted (+9 more)

### Community 4 - "SettingsView"
Cohesion: 0.16
Nodes (24): HelpText, .body, SettingsGroup, .body, SettingsView, .advancedSection, .agentsSection, .appearanceSection (+16 more)

### Community 5 - "IslandRootView"
Cohesion: 0.05
Nodes (51): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, Composition, state and settings, IslandModule, IslandModules, CollapsedPreviewContent (+43 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.13
Nodes (14): ClipboardHistoryPersistence, ClipboardHistoryPersistenceWriter, ClipboardHistoryStore, AnyCancellable, async, Bool, Date, Int (+6 more)

### Community 8 - "TimerController"
Cohesion: 0.09
Nodes (24): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, CountdownLifecycleEvent, cancelled, completed, scheduled, Duration (+16 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (8): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, Bool, Int, SystemClipboardPasteboardClient, .changeCount, ClipboardPasteboardClientTests

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.09
Nodes (22): AnyObject, NSObject, Bool, Duration, Never, Task, TimeInterval, Void (+14 more)

### Community 11 - "ClipboardHistoryPayload"
Cohesion: 0.07
Nodes (25): Decoder, Encoder, ClipboardHistoryEntryKind, files, image, text, url, ClipboardHistoryFingerprint (+17 more)

### Community 12 - "NotchGeometryService"
Cohesion: 0.12
Nodes (18): 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix, 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix, 2026-07-05 - Phase 7A.4 Island Size Settings Wiring, NSEdgeInsets, NSScreen, CollapsedActivityLayoutProfile, .symmetricWingContentWidth, CollapsedActivityResolvedGeometry (+10 more)

### Community 13 - "ClipboardHistoryStoreTests"
Cohesion: 0.18
Nodes (7): ClipboardHistoryArchive, ClipboardHistoryStoreTests, FakeClipboardPasteboardClient, MemoryClipboardPersistence, .data, Date, UserDefaults

### Community 14 - ".normalizeAndSaveDouble"
Cohesion: 0.09
Nodes (16): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedWidth, .contentStaggerAmount, .expandedHeight (+8 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.16
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.21
Nodes (6): 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, IslandNavigationStore, Bool, Int, .body

### Community 17 - ".start"
Cohesion: 0.25
Nodes (4): MockTimerNotificationCenterClient, Bool, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, FileShelfStore, AnyCancellable, Set, URL (+8 more)

### Community 19 - "SupportedApp"
Cohesion: 0.09
Nodes (25): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 3 Album Artwork Source Open, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome (+17 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.14
Nodes (12): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, 2026-07-04 - Phase 5J Single Visual Surface Morph, ExpandedIslandView, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation, .tabAnimationsEnabled, .tabFadeInAnimation (+4 more)

### Community 21 - "Change Log"
Cohesion: 0.04
Nodes (71): Animation, 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish (+63 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (36): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+28 more)

### Community 25 - "ObservableObject"
Cohesion: 0.10
Nodes (19): Calendar, ObservableObject, UUID, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView (+11 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (47): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+39 more)

### Community 27 - "Int"
Cohesion: 0.09
Nodes (16): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer (+8 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.14
Nodes (19): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+11 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.10
Nodes (10): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int (+2 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.19
Nodes (3): MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.10
Nodes (17): Phase 11A - Battery Live Activity, BatteryActivityProvider, BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Any, Bool (+9 more)

### Community 33 - "AgentProducerHandle"
Cohesion: 0.11
Nodes (21): AgentProducerHandle, AgentSourceHealthSnapshot, AgentSourceInstanceID, AgentSourceKind, authenticatedBridge, heuristicFallback, officialHook, officialLifecycleProtocol (+13 more)

### Community 34 - "AgentBridgeAuthenticator"
Cohesion: 0.18
Nodes (9): AgentBridgeAuthenticator, .rememberedNonceCount, AgentBridgeCrypto, NonceEntry, Bool, Date, Int, Int64 (+1 more)

### Community 35 - "XCTest"
Cohesion: 0.08
Nodes (5): AppKit, Combine, DynamicIsland, UniformTypeIdentifiers, XCTest

### Community 36 - "AppendOnlyRecordTailer"
Cohesion: 0.11
Nodes (17): DispatchSourceFileSystemObject, NoticeHandler, RecordHandler, A2.1 ingress boundary and A2.2 handoff, AppendOnlyFileIdentity, AppendOnlyRecordStartPolicy, boundedCatchUp, fromEnd (+9 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.04
Nodes (59): 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, Double, AlbumArtworkView, .body (+51 more)

### Community 38 - "MediaSnapshot"
Cohesion: 0.12
Nodes (13): 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, MediaSnapshot, MediaSourceKind, browser, music, spotify, system, unknown (+5 more)

### Community 39 - "Phase Workflow For Future Work"
Cohesion: 0.10
Nodes (21): 2026-07-03 - Common App Launch Resolver, 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration (+13 more)

### Community 40 - "FileDropProviderLoader"
Cohesion: 0.18
Nodes (11): FileDropProviderLoader, UTType, .airDropTargetBinding, .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider (+3 more)

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (23): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Part A - Structural extraction for code files, Part B - Semantic extraction (parallel subagents) (+15 more)

### Community 42 - "String"
Cohesion: 0.10
Nodes (22): CodingKey, CodingKeys, files, imagePNG, text, type, url, MediaPlayer (+14 more)

### Community 43 - "MediaController"
Cohesion: 0.08
Nodes (22): 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability, 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, BrowserScriptTarget, Decision, MediaArbitrator, MediaArtworkFlipRequest, .isExpired, MediaCandidate (+14 more)

### Community 44 - ".refresh"
Cohesion: 0.29
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.08
Nodes (24): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, App Entry, Collapsed, Current Architecture, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes, DynamicIsland Project Context (+16 more)

### Community 47 - "CGFloat"
Cohesion: 0.09
Nodes (23): AnimatablePair, Interpreter guard for subcommands, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, EnvironmentKey, Path, Activities and utility modules, Build and tests, Clipboard engine and persistence (+15 more)

### Community 48 - "View"
Cohesion: 0.05
Nodes (71): AirDropDropZoneView, .body, .subtitle, CollapsedBatteryActivityCompactView, .accessibilityLabel, .body, .iconColor, .percentText (+63 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.08
Nodes (22): CFTimeInterval, 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity, DispatchWorkItem, NSPoint, NSRect, OverlayWindowController, .collapsedGestureCandidateRegion, .collapsedGestureCandidateScreenRegion (+14 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "AgentAttentionEvent"
Cohesion: 0.06
Nodes (49): Int, RawRepresentable, 7. Attention presentation contract, AgentAttentionCoordinator, Date, Never, Task, TimeInterval (+41 more)

### Community 52 - "Equatable"
Cohesion: 0.05
Nodes (69): Comparable, Equatable, Hashable, Identifiable, 1. Domain contracts, .activeSessions, .sessionsRequiringAttention, AgentActionControlAssessment (+61 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (3): Bool, T, UserDefaults

### Community 54 - "CompactIslandView"
Cohesion: 0.18
Nodes (13): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CompactCollapsedSideSlotGeometry, .usesPhysicalNotchRegions, CompactCollapsedSideSlotLayout, .body (+5 more)

### Community 55 - "RecordSink"
Cohesion: 0.17
Nodes (11): AppendOnlyRecordTailerTests, Fixture, NoticeSink, .values, openDescriptorCount(), RecordSink, .strings, Bool (+3 more)

### Community 56 - "ClipboardPasteboardReadResult"
Cohesion: 0.10
Nodes (21): ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult (+13 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.16
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".event"
Cohesion: 0.22
Nodes (11): Success, AgentIngestionCoordinatorTests, Array, .single, Element, Result, Set, StaticString (+3 more)

### Community 59 - ".sessionID"
Cohesion: 0.14
Nodes (11): AgentActivityDescriptor, AgentReductionResult, AgentSessionID, AgentEventReducerTests, Set, TimeInterval, AgentPrivacyProjectionTests, TimeInterval (+3 more)

### Community 60 - "IslandPointerGestureModifier"
Cohesion: 0.13
Nodes (16): Gesture, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier, ExpandedTabContentTransitionModifier, .blur, .scale (+8 more)

### Community 61 - "AgentBridgeClient"
Cohesion: 0.09
Nodes (19): Network, AgentBridgeClient, invalidInput, AgentBridgeClientResult, accepted, rejected, AgentBridgeClientTransport, Bool (+11 more)

### Community 62 - "IslandHostingView"
Cohesion: 0.09
Nodes (17): 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, Known Fragile Areas, Phase 13B.2 - Native In-Island Clipboard Interface, NSHostingView, NSSize (+9 more)

### Community 63 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.13
Nodes (16): ControlledMediaRemoteCallback, ControlledMediaRemoteProvider, Entry, ManualMediaRemoteDeadlineScheduler, .count, .scheduler, MediaRemoteCallbackBridgeTests, MediaRemoteRefreshRecoveryTests (+8 more)

### Community 64 - "CaseIterable"
Cohesion: 0.04
Nodes (51): CaseIterable, 2026-07-11 - Phase 9D Theme Simplification, AnimationPreset, .displayName, .id, instant, normal, .shellDuration (+43 more)

### Community 65 - "AgentEventStore"
Cohesion: 0.16
Nodes (6): AgentEventStore, Bool, AgentSessionInstanceID, AgentEventStoreTests, Int, TimeInterval

### Community 66 - ".makeProcessor"
Cohesion: 0.29
Nodes (4): AgentBridgeEnvelopeIntegrationTests, StaticString, UInt, Any

### Community 67 - "Sendable"
Cohesion: 0.09
Nodes (48): Codable, Sendable, AgentBridgeHealth, AgentBridgeWirePayload, .populatedFieldCount, UInt16, AgentApprovalRequest, AgentApprovalResolution (+40 more)

### Community 68 - "ControlledClipboardPersistence"
Cohesion: 0.22
Nodes (7): ControlledClipboardPersistence, .data, .deleteCount, .saveCount, Bool, Int, TimeInterval

### Community 69 - "AppDelegate"
Cohesion: 0.14
Nodes (13): Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, AppDelegate, .liveActivitySettingsPublisher, DynamicIslandApp, LiveActivitySettingsSnapshot, Any, AnyCancellable (+5 more)

### Community 70 - "UInt64"
Cohesion: 0.20
Nodes (5): UInt64, SystemStatsFormatting, SystemStatsSnapshot, StatsPageView, .body

### Community 71 - "ExpandedScrollEventRoutingPolicyTests"
Cohesion: 0.23
Nodes (5): ExpandedScrollEventRoute, islandGesture, passThroughToContent, ExpandedScrollEventRoutingPolicyTests, Bool

### Community 72 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 73 - "AppendOnlyRecordTailer.swift"
Cohesion: 0.09
Nodes (25): Dispatch, AppendOnlyRecordLimits, AppendOnlyRecordTailerFailure, identityRace, ioFailure, notRegularFile, parentUnavailable, permissionDenied (+17 more)

### Community 74 - "DelimitedRecordFramer"
Cohesion: 0.20
Nodes (7): BoundedRecordRing, .orderedRecords, DelimitedRecordFramer, Output, Int, Void, DelimitedRecordFramerTests

### Community 75 - "completion"
Cohesion: 0.19
Nodes (7): NSSecureCoding, completion, FileDropURLAccumulator, .urls, SendableItemProvider, NSItemProvider, TimeInterval

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.12
Nodes (13): AgentBridgeDiscoveryPublisher, FileManager, URL, AgentOTLPJSONDecoder, AgentTelemetryObservation, .isEmpty, Any, Bool (+5 more)

### Community 77 - "AgentCapability"
Cohesion: 0.07
Nodes (29): AgentCapabilities, .all, AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage, costUsage (+21 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.24
Nodes (7): 2026-07-05 - Phase 8A File Shelf Tray Polish, AirDropService, Bool, URL, AirDropURLAccumulator, .urls, URL

### Community 80 - "AgentIntegrationSetupService"
Cohesion: 0.16
Nodes (11): AgentIntegrationBackupEnvelope, AgentIntegrationSetupPaths, AgentIntegrationSetupService, .fileManager, AgentIntegrationSetupSnapshot, Bool, FileManager, Int (+3 more)

### Community 83 - "SequenceClientTransport"
Cohesion: 0.23
Nodes (6): AgentBridgeEnvelopeBuilder, Any, AgentBridgeSharedClientTests, SequenceClientTransport, SequenceProfileProvider, Int

### Community 84 - ".apply"
Cohesion: 0.10
Nodes (12): AgentEventReducer, AgentEventStoreLimits, .normalized, SemanticResult, applied, rejected, Bool, Date (+4 more)

### Community 85 - "AgentBridgeSharedDiscoveryTests"
Cohesion: 0.19
Nodes (9): AgentBridgeSharedDiscoveryTests, Bool, mode_t, StaticString, uid_t, UInt, UInt16, Void (+1 more)

### Community 86 - "AgentEventType"
Cohesion: 0.06
Nodes (31): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+23 more)

### Community 87 - "AgentEventValidationError"
Cohesion: 0.06
Nodes (33): AgentBridgeIngestionResult, AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID (+25 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.16
Nodes (10): LauncherShortcut, ShortcutsStore, .shortcuts, UUID, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount (+2 more)

### Community 89 - "AgentRelayCommandTests"
Cohesion: 0.13
Nodes (12): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000) (+4 more)

### Community 90 - "ArtworkPresentationCoordinator"
Cohesion: 0.40
Nodes (4): ArtworkPresentationCoordinator, .displayedSnapshot, UUID, Void

### Community 91 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 92 - "Evidence-supported pre-audit risks"
Cohesion: 0.33
Nodes (5): A. Carried-forward candidates confirmed in current source, B. Structural and maintenance risks, C. Documentation and testing gaps, Evidence-supported pre-audit risks, Interpretation boundaries

### Community 93 - "ServerSpy"
Cohesion: 0.14
Nodes (17): AgentBridgeNetworkError, listenerCancelled, listenerFailed, missingPort, DeferredServerSpy, .startCount, .factory, .handlers (+9 more)

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
Cohesion: 0.21
Nodes (7): 5. Local storage audit (content redacted), Claude, Codex, Cross-surface findings, Double, TimerProgressFormatting, TimerProgressFormattingTests

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.29
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentEvent"
Cohesion: 0.08
Nodes (23): AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible, Bool, Date, Int (+15 more)

### Community 106 - "AgentBridgeDiscoveryReader"
Cohesion: 0.14
Nodes (16): dev_t, ino_t, AgentBridgeClientProfileProviding, AgentBridgeDiscoveryFileReading, AgentBridgeDiscoveryFileSnapshot, AgentBridgeDiscoveryReader, Bool, Date (+8 more)

### Community 108 - "ShelfFileTile"
Cohesion: 0.23
Nodes (8): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, URL

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.22
Nodes (6): FileDropPolicy, FileShelfTemporaryStorage, Bool, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "NetworkCounters"
Cohesion: 0.16
Nodes (8): ifaddrs, NetworkCounters, Self, TimeInterval, Interface, NetworkCounterSamplingTests, UInt32, UnsafeMutablePointer

### Community 111 - "ServerFactorySpy"
Cohesion: 0.22
Nodes (9): AgentBridgeLifecycleTests, DiscoverySpy, .records, .removedLaunchIDs, ServerFactorySpy, .createdCount, AgentBridgeServerFactory, Error (+1 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.08
Nodes (24): AgentBridgeIngress, AgentBridgeRequestProcessor, Bool, Date, Result, AgentBridgeEnvelopeError, emptyBatch, eventTooLarge (+16 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.19
Nodes (11): DispatchQueue, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, AgentBridgeServing, NWConnection (+3 more)

### Community 114 - ".start"
Cohesion: 0.18
Nodes (12): HTTPURLResponse, AgentBridge, LaunchMaterial, ProducerRuntime, Runtime, AgentBridgeServerFactory, Error, UUID (+4 more)

### Community 115 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 116 - ".assertFailure"
Cohesion: 0.19
Nodes (3): AgentBridgeHTTPParserTests, StaticString, UInt

### Community 117 - "Foundation"
Cohesion: 0.08
Nodes (9): AgentBridgeShared, ClaudeHookShared, CodexHookShared, CoreFoundation, CryptoKit, Darwin, Foundation, IOKit.ps (+1 more)

### Community 118 - ".parse"
Cohesion: 0.11
Nodes (12): ClaudeTranscriptRecoveryAdapter, ClaudeTranscriptRecoveryParser, OperationKind, command, tool, Any, Bool, Date (+4 more)

### Community 119 - "AgentBridgeClientProfile"
Cohesion: 0.13
Nodes (11): AgentBridgeClientProfile, AgentBridgeDiscoveryRecord, AgentBridgeProtocol, Date, Int, Int32, UInt16, AgentBridgeSharedNetworkIntegrationTests (+3 more)

### Community 120 - "AgentIngestionCoordinator"
Cohesion: 0.13
Nodes (13): AgentIngestionCoordinator, Bool, CheckedContinuation, Date, Never, Result, Void, AgentIdentityConflict (+5 more)

### Community 121 - "AgentBridgeHTTPRequestParser"
Cohesion: 0.18
Nodes (10): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, .result (+2 more)

### Community 122 - "AgentBridgeModels.swift"
Cohesion: 0.13
Nodes (18): Decodable, AgentBridgeHTTPResponse, .data, AgentBridgeLimits, AgentBridgeState, degraded, failed, running (+10 more)

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.12
Nodes (17): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 3. Component boundaries, 4. Per-event authority, 6. Privacy and security boundaries, 8. Expanded Agent Activity contract (+9 more)

### Community 124 - ".normalize"
Cohesion: 0.11
Nodes (10): ClaudeHookNormalizer, ClaudeHookStandardInput, Any, Bool, Date, FileHandle, Int, DynamicIslandClaudeHookRelayMain (+2 more)

### Community 125 - "3. Phase gates"
Cohesion: 0.11
Nodes (18): 3. Phase gates, A0 — Research and architecture, A10 — Source app/editor association and Open action, A11 — Setup UX, migration and hardening, A1 — Normalized domain, `AgentEventStore`, replay harness, A2.1 — Ingestion coordination and source registry, A2.2 — Relay client and append-only ingestion primitives, A2 — Authenticated local Agent Bridge (+10 more)

### Community 126 - "LiveActivityStore"
Cohesion: 0.27
Nodes (6): LiveActivityStore, .primaryActivity, Double, LiveActivityStoreTests, Date, Int

### Community 127 - "Agent Capability Matrix"
Cohesion: 0.17
Nodes (12): 1. Method and version boundary, 2. Primary supported integration surfaces, 3. Capability matrix, 4. Event-specific authority, 6. Source application association, 7. Design implications, 8. Official sources, Agent Capability Matrix (+4 more)

### Community 128 - "Agent Event Schema Draft"
Cohesion: 0.12
Nodes (16): 2. State vocabulary, 3. Session identity, 4. Normalized event types, 5. Versioned transport envelope, 6. Capability model, 7. Privacy projection, 8. Replay fixture contract, 9. Deferred decisions (+8 more)

### Community 129 - ".normalize"
Cohesion: 0.09
Nodes (15): CodexHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook, CodexHookNormalizer (+7 more)

### Community 130 - "Error"
Cohesion: 0.09
Nodes (25): Error, AgentBridgeNetworkExchange, AgentBridgeNetworkTransport, Duration, NWConnection, Result, UInt16, Void (+17 more)

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
Cohesion: 0.14
Nodes (8): AgentBridgeRequestAuthentication, Data, Bool, Int, Int64, AgentBridgeSharedCryptoTests, Int, UInt32

### Community 136 - "AgentBridgeHTTPStatus"
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.20
Nodes (10): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, A3.1 implementation refinement — Codex structured recovery, A3 implementation refinement — Codex authoritative hooks, A4.1 implementation refinement — Claude transcript recovery, A4.5 implementation refinement — bounded OTLP JSON enrichment (+2 more)

### Community 139 - "AgentBridgeEnvelopeBuildError"
Cohesion: 0.09
Nodes (23): AgentBridgeClientError, authenticationFailed, discoveryUnavailable, malformedResponse, timedOut, transportUnavailable, AttemptError, authentication (+15 more)

### Community 140 - "SettingsWindowController"
Cohesion: 0.22
Nodes (6): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, NSWindowDelegate, SettingsWindowController, Notification, NSWindow

### Community 141 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

### Community 142 - "AgentRelayExitCode"
Cohesion: 0.18
Nodes (10): Int32, AgentRelayExitCode, accepted, authenticationFailed, bridgeUnavailable, discoveryUnavailable, invalidInput, serverRejected (+2 more)

### Community 143 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 144 - "AgentIngestionEvent"
Cohesion: 0.19
Nodes (9): AgentIngestionEvent, .sessionID, AgentSessionContinuity, CodexRolloutRecoveryParser, Any, Date, Double, Int (+1 more)

### Community 145 - "XCTestCase"
Cohesion: 0.13
Nodes (14): AgentAuthorityDomain, activity, capability, interaction, lifecycle, liveness, metadata, operation (+6 more)

### Community 146 - "AgentBridgeAuthenticationError"
Cohesion: 0.11
Nodes (15): OSStatus, AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull (+7 more)

### Community 147 - "AgentProvider"
Cohesion: 0.14
Nodes (10): AgentTelemetryFusion, Result, AgentProvider, claude, codex, .deterministicSortKey, other, .stableName (+2 more)

### Community 148 - "MediaRemoteClient"
Cohesion: 0.13
Nodes (19): CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, value, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending, MediaRemoteClient (+11 more)

### Community 149 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 150 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

### Community 152 - "AgentIntegrationOperationalState"
Cohesion: 0.10
Nodes (18): AgentIntegrationDiagnostics, AgentIntegrationOperationalState, active, awaitingFirstEvent, blocked, degraded, failed, .label (+10 more)

### Community 153 - "AgentIntegrationProvider"
Cohesion: 0.15
Nodes (14): AgentIntegrationConfigurationExpectation, absent, digest, AgentIntegrationProvider, claude, codex, .desiredEvents, .displayName (+6 more)

### Community 154 - "AgentIngestionModels.swift"
Cohesion: 0.14
Nodes (14): AgentIngestionLimits, AgentIngestionResult, AgentProducerDescriptor, AgentTelemetryFusionOutcome, applied, deferredNoSession, ignoredEmpty, rejected (+6 more)

### Community 155 - "AgentIntegrationSetupTests"
Cohesion: 0.23
Nodes (3): AgentHookConfigurationPlanner, Any, AgentIntegrationSetupTests

### Community 156 - ".session"
Cohesion: 0.19
Nodes (5): .usageMetrics, AgentPresentationTests, Date, Double, Set

### Community 157 - ".stateLabel"
Cohesion: 0.18
Nodes (10): AgentSessionPresentation, Bool, .body, .body, .attentionSection, .header, AgentStatusBadge, .body (+2 more)

### Community 158 - "AgentActivityViews.swift"
Cohesion: 0.16
Nodes (16): AgentCompactOverviewView, .body, AgentCompactSessionIndicator, AgentMetadataChip, .body, AgentOperationRow, .body, .statusColor (+8 more)

### Community 159 - "AgentSessionCard"
Cohesion: 0.14
Nodes (18): AgentOperationPresentation, AgentSessionCard, .activeCommands, .activeTools, .hasOperations, .hasVisibleUsage, .pendingApprovals, .recentOperations (+10 more)

### Community 160 - "IslandSurfaceBackground"
Cohesion: 0.12
Nodes (17): 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, LinearGradient, ShellShape, IslandSurfaceBackground, .body, .bottomDepth, .classicBlack, .classicBlackColor (+9 more)

### Community 161 - "NowPlayingMediaProvider"
Cohesion: 0.22
Nodes (7): 2026-07-04 - Phase 3.4 Album Artwork Stability, MediaRemoteDictionary, MediaRemoteProviding, NowPlayingMediaProvider, Double, NSDictionary, NSImage

### Community 162 - "IslandLayoutStore"
Cohesion: 0.23
Nodes (9): 2026-07-04 - Phase 5H Notch-Integrated Island Shape, 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, IslandLayoutStore, Bool, CGFloat, CGRect (+1 more)

### Community 163 - "IslandOverlayPanel"
Cohesion: 0.14
Nodes (12): Phase 11C.4 - WindowServer Space-Transition Counter-Translation, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible, NSPanel, QuartzCore, 2. Existing DynamicIsland invariants, ExpandedScrollEventRoutingPolicy, IslandOverlayPanel (+4 more)

### Community 164 - "AgentState"
Cohesion: 0.14
Nodes (14): AgentState, completed, failed, idle, interrupted, .isTerminal, planning, planReady (+6 more)

### Community 165 - "ClipboardHistoryPersistenceFinalizationResult"
Cohesion: 0.23
Nodes (9): ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed, failed, timedOut (+1 more)

### Community 166 - "AgentIngestionError"
Cohesion: 0.15
Nodes (13): AgentIngestionError, capabilityCapacity, generationConflict, identityConflict, invalidDescriptor, invalidEvent, invalidProducer, leaseCapacity (+5 more)

### Community 167 - "AgentIntegrationSetupError"
Cohesion: 0.17
Nodes (12): AgentIntegrationSetupError, backupInvalid, backupUnavailable, changedExternally, fileTooLarge, helperUnavailable, invalidHooks, invalidJSON (+4 more)

### Community 168 - "AgentActivityKind"
Cohesion: 0.18
Nodes (11): AgentActivityKind, approval, command, failure, interruption, plan, session, subagent (+3 more)

### Community 169 - "AgentBridgeClientTransportError"
Cohesion: 0.20
Nodes (9): AgentBridgeClientTransportError, connectTimedOut, malformedResponse, requestTimedOut, responseTooLarge, unavailable, Outcome, failure (+1 more)

### Community 170 - "ExpandedIslandPage"
Cohesion: 0.20
Nodes (9): ExpandedIslandPage, .accessibilityLabel, agents, island, stats, .symbolName, timer, .title (+1 more)

### Community 171 - "AgentSourceHealthError"
Cohesion: 0.25
Nodes (8): AgentSourceHealthError, identityConflict, invalidEvent, policyRejected, producerFailure, schemaMismatch, staleProducer, storeRejected

### Community 172 - "SwiftUI"
Cohesion: 0.25
Nodes (5): PriorityStepperRow, .body, .liveActivitiesSection, Int, SwiftUI

### Community 173 - "FileClipboardHistoryPersistence"
Cohesion: 0.32
Nodes (3): FileClipboardHistoryPersistence, FileManager, URL

### Community 174 - "Fresh critical audit instructions"
Cohesion: 0.29
Nodes (6): Exact next prompt, Finding format (required for each), Fresh critical audit instructions, Scope, Start and evidence order, Validation and limits

### Community 175 - "ClaudeHookNormalizationError"
Cohesion: 0.29
Nodes (7): ClaudeHookNormalizationError, emptyInput, inputTooLarge, invalidHook, malformedJSON, outputTooLarge, unsupportedHook

### Community 176 - "AgentSourceHealthState"
Cohesion: 0.29
Nodes (7): AgentSourceHealthState, degraded, failed, healthy, stale, starting, stopped

### Community 177 - "AgentIntegrationSetupState"
Cohesion: 0.29
Nodes (7): AgentIntegrationSetupState, blocked, configured, helperUnavailable, .label, needsSetup, repairRequired

### Community 178 - "AgentPresentationPriority"
Cohesion: 0.29
Nodes (7): AgentPresentationPriority, actionRequired, failure, idle, recent, thinking, working

### Community 179 - "AgentOTLPJSONError"
Cohesion: 0.33
Nodes (6): AgentOTLPJSONError, emptyPayload, excessiveCardinality, excessiveDepth, malformedJSON, payloadTooLarge

### Community 180 - "ShortcutEditorRow"
Cohesion: 0.40
Nodes (5): ShortcutEditorRow, .body, Binding, Void, WritableKeyPath

### Community 181 - "ClaudeTranscriptRecoveryError"
Cohesion: 0.40
Nodes (4): ClaudeTranscriptRecoveryError, malformedRecord, missingSession, unsupportedRecord

### Community 182 - "CodexRolloutRecoveryError"
Cohesion: 0.40
Nodes (5): CodexRolloutRecoveryError, invalidUsage, malformedRecord, missingSession, unsupportedRecord

### Community 184 - ".subscript"
Cohesion: 0.50
Nodes (3): Index, Array, Element

### Community 185 - "5. Local bridge decision"
Cohesion: 0.50
Nodes (4): 5. Local bridge decision, Alternatives, OTLP, Selected architecture

### Community 186 - "AgentActivityDashboardView"
Cohesion: 0.50
Nodes (4): AgentActivityDashboardView, .body, .emptyState, CGFloat

### Community 187 - "AgentSourceRegistryTests.swift"
Cohesion: 0.50
Nodes (3): Array, .single, Element

## Knowledge Gaps
- **1050 isolated node(s):** `PackageDescription`, `package_app.sh script`, `unavailable`, `connectTimedOut`, `requestTimedOut` (+1045 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1349 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `TimerController`, `TimerCompletionNotificationCoordinator`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `.start`, `FileShelfStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `ObservableObject`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `AgentProducerHandle`, `AgentBridgeAuthenticator`, `MediaModuleView`, `MediaSnapshot`, `FileDropProviderLoader`, `MediaController`, `IslandStateStore`, `AppSettingsTests`, `View`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `AgentAttentionEvent`, `Equatable`, `.reload`, `CompactIslandView`, `RecordSink`, `.event`, `.sessionID`, `AgentBridgeClient`, `IslandHostingView`, `ManualMediaRemoteDeadlineScheduler`, `CaseIterable`, `AgentEventStore`, `.makeProcessor`, `Sendable`, `AppDelegate`, `UInt64`, `DynamicIslandLiveActivityKind`, `completion`, `AgentBridgeDiscoveryPublisher`, `AgentCapability`, `AgentIntegrationSetupService`, `SequenceClientTransport`, `.apply`, `AgentBridgeSharedDiscoveryTests`, `AgentEventType`, `AgentEventValidationError`, `ShortcutsStore`, `ArtworkPresentationCoordinator`, `ServerSpy`, `SettingsSection`, `RecordingFileShelfDefaults`, `AgentEvent`, `AgentBridgeDiscoveryReader`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `ServerFactorySpy`, `AgentBridgeEnvelopeError`, `.start`, `.parse`, `AgentBridgeClientProfile`, `AgentIngestionCoordinator`, `AgentBridgeHTTPRequestParser`, `AgentBridgeModels.swift`, `.normalize`, `LiveActivityStore`, `.normalize`, `Error`, `.signedRequest`, `Data`, `AgentBridgeHTTPStatus`, `AgentRelayExitCode`, `AgentIngestionEvent`, `XCTestCase`, `AgentProvider`, `MediaRemoteClient`, `.remainingTime`, `AgentIntegrationOperationalState`, `AgentIntegrationProvider`, `AgentIngestionModels.swift`, `AgentIntegrationSetupTests`, `.session`, `.stateLabel`, `AgentActivityViews.swift`, `AgentSessionCard`, `NowPlayingMediaProvider`, `IslandOverlayPanel`, `AgentState`, `AgentIntegrationSetupError`, `AgentActivityKind`, `ExpandedIslandPage`, `AgentSourceHealthError`, `SwiftUI`, `AgentSourceHealthState`, `AgentIntegrationSetupState`, `ShortcutEditorRow`, `.collapsedPreviewContent`?**
  _High betweenness centrality (0.463) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `SettingsWindowController`, `NotchGeometryService`, `.normalizeAndSaveDouble`, `ClipboardHistoryStoreTests`, `IslandNavigationStore`, `FileShelfStore`, `ExpandedIslandView`, `Change Log`, `ObservableObject`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaModuleView`, `FileDropProviderLoader`, `String`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `View`, `OverlayWindowController`, `.reload`, `CompactIslandView`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `AgentActivityDashboardView`, `IslandPointerGestureModifier`, `CaseIterable`, `AppDelegate`, `UInt64`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`?**
  _High betweenness centrality (0.107) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `CaseIterable`, `AppSettings`, `IslandLayoutStore`, `IslandOverlayPanel`, `IslandRootView`, `IslandEscapeRouter`, `AppDelegate`, `SettingsWindowController`, `IslandStateStore`, `NotchGeometryService`, `ExpandedIslandView`, `Change Log`, `CompactIslandView`, `OverlayPresentationSessionTests`, `DynamicIslandLiveActivity`, `.init`, `IslandHostingView`?**
  _High betweenness centrality (0.058) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `unavailable` to the rest of the system?**
  _1050 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppSettings` be split into smaller, more focused modules?**
  _Cohesion score 0.02370673331818526 - nodes in this community are weakly interconnected._