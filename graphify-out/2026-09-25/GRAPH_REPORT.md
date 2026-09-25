# Graph Report - DynamicIsland  (2026-09-25)

## Corpus Check
- 140 files · ~173,905 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 2, .plist 1)

## Summary
- 4205 nodes · 11865 edges · 152 communities (138 shown, 14 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1479 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `563f75ff`
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
- .init
- ClipboardImageNormalizerTests
- MediaArbitratorTests
- BatteryActivitySnapshot
- AgentIngestionCoordinator
- AgentBridgeAuthenticator
- XCTest
- AppendOnlyRecordTailer
- MediaModuleView
- Phase Workflow For Future Work
- MediaCandidate
- FileDropProviderLoaderTests
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
- Bool
- RecordSink
- ClipboardPasteboardReadResult
- OverlayPresentationSessionTests
- .event
- .sessionID
- .opacity
- AgentBridgeClient
- IslandHostingView
- ManualMediaRemoteDeadlineScheduler
- CaseIterable
- AgentEventStore
- .makeProcessor
- AgentBridgeDiscoveryRecord
- Data
- AppDelegate
- UInt64
- ExpandedScrollEventRoutingPolicyTests
- DynamicIslandLiveActivityKind
- AppendOnlyRecordTailer.swift
- DelimitedRecordFramer
- FileDropProviderLoader
- AgentBridgeDiscoveryPublisher
- AgentCapability
- Meaningful regression history
- .loadFileURLs
- ShortcutsModuleView
- Package.swift
- package_app.sh
- SequenceClientTransport
- .apply
- AgentBridgeSharedDiscoveryTests
- AgentEventType
- AgentEventValidationError
- ShortcutsStore
- AgentRelayCommandTests
- MediaController.swift
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
- CountdownLifecycleEvent
- RecordingFileShelfDefaults
- AgentEvent
- AgentBridgeDiscoveryFileSnapshot
- LiveActivitySettingsSubscriberTests
- ShelfFileTile
- FileShelfTemporaryStorage
- NetworkCounters
- ServerFactorySpy
- AgentBridgeEnvelopeError
- AgentBridgeNetworkServer
- AgentBridge
- ClipboardHistoryPresentationState
- .assertFailure
- Foundation
- AudioVisualizerView
- AgentBridgeClientProfile
- AgentBridgeEnvelopeBuildError
- AgentBridgeHTTPRequestParser
- AgentEvidenceAuthority
- Agent Activity Integration Architecture
- Double
- 3. Phase gates
- LiveActivityStore
- Agent Capability Matrix
- Agent Event Schema Draft
- .constrainedActivePlayerLayout
- AgentBridgeNetworkExchange
- .signedRequest
- MenuBarController
- AgentBridgeDiscoveryReadError
- .canonicalMessage
- AgentBridgeHTTPStatus
- Agent Activity Feature Phase Plan
- .resolve
- AgentBridgeClientError
- SwiftUI
- .decode
- AgentRelayExitCode
- AgentNotch Reference Review
- ModuleViews.swift
- XCTestCase
- AgentBridgeCredentialError
- AgentBridgeAuthenticationError
- .presentation
- LaunchAtLoginController.swift
- LockedValue
- .remainingTime

## God Nodes (most connected - your core abstractions)
1. `AppSettings` - 331 edges
2. `OverlayWindowController` - 136 edges
3. `Change Log` - 110 edges
4. `MediaController` - 105 edges
5. `IslandRootView` - 75 edges
6. `ExpandedIslandView` - 67 edges
7. `AgentEventStore` - 66 edges
8. `AgentEvent` - 64 edges
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
- `Stable native overlay architecture` --references--> `IslandRootView`  [INFERRED]
  README.md → Sources/DynamicIsland/Views/IslandRootView.swift

## Import Cycles
- None detected.

## Communities (152 total, 14 thin omitted)

### Community 0 - "AppSettings"
Cohesion: 0.02
Nodes (155): AnyPublisher, Never, AppSettings, .activitiesEnabled, .airDropFallbackRevealInFinder, .airDropZoneEnabled, .allowFileDropsOnCollapsedIsland, .allowFileDropsOnExpandedTray (+147 more)

### Community 1 - "IslandGestureAction"
Cohesion: 0.07
Nodes (40): 2026-07-05 - Phase 8C Gesture Infrastructure Foundation, CoreGraphics, Gesture, .now, IslandGestureAction, collapse, .displayName, expand (+32 more)

### Community 2 - "SystemStatsController"
Cohesion: 0.11
Nodes (13): 2026-07-04 - Phase 5D Stats Tab, 2026-07-04 - Phase 7A Comprehensive Settings Foundation, CPUCounters, Bool, Date, Double, Int, Timer (+5 more)

### Community 3 - "ArtworkFlipPresentationState"
Cohesion: 0.20
Nodes (6): ArtworkFlipPresentationState, .queuedSnapshot, ArtworkPresentationSnapshot, QueuedTransition, ArtworkFlipPresentationStateTests, Bool

### Community 4 - "SettingsView"
Cohesion: 0.12
Nodes (32): HelpText, .body, PriorityStepperRow, .body, SettingsGroup, .body, SettingsView, .advancedSection (+24 more)

### Community 5 - "IslandRootView"
Cohesion: 0.06
Nodes (35): 2026-07-04 - Phase 5I.2 Animation Performance Polish, 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix, 2026-07-04 - Phase 5J Single Visual Surface Morph, 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish, 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation, Phase 11C.9 - Predictive Space Motion Resampling, Phase 13A - Expanded Visibility Controls, Phase 13B.2 - Native In-Island Clipboard Interface (+27 more)

### Community 6 - "IslandEscapeRouter"
Cohesion: 0.17
Nodes (11): Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix, IslandEscapeRoute, collapseIsland, dismissPresentation, passThrough, IslandEscapeRouter, IslandEscapeRoutingPolicy, IslandOverlayPresentation (+3 more)

### Community 7 - "ClipboardHistoryStore"
Cohesion: 0.09
Nodes (25): AnyObject, ClipboardHistoryPersistence, ClipboardHistoryFinalPersistenceOperation, delete, save, ClipboardHistoryPersistenceFinalizationCompletion, ClipboardHistoryPersistenceFinalizationResult, completed (+17 more)

### Community 8 - "TimerController"
Cohesion: 0.12
Nodes (16): 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish, ContinuousClock, CountdownClock, Duration, Int, MainActor, Never, Task (+8 more)

### Community 9 - "SystemClipboardPasteboardClient"
Cohesion: 0.13
Nodes (9): NSPasteboard, NSPasteboardItem, ClipboardHistoryLimits, ClipboardSensitivePasteboardTypes, Bool, Set, SystemClipboardPasteboardClient, .changeCount (+1 more)

### Community 10 - "TimerCompletionNotificationCoordinator"
Cohesion: 0.10
Nodes (20): Bool, Duration, Never, Task, TimeInterval, Void, SystemTimerNotificationCenterClient, TimerCompletionNotificationCoordinator (+12 more)

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
Nodes (19): .activitiesRefreshIntervalSeconds, .autoCollapseGraceSeconds, .collapsedHeight, .collapsedHoverPreviewDelay, .collapsedHoverPreviewHeight, .collapsedSize, .collapsedWidth, .contentStaggerAmount (+11 more)

### Community 15 - "CollapsedLiveActivitySelectorTests"
Cohesion: 0.14
Nodes (4): CollapsedLiveActivitySelectorTests, Bool, Date, Int

### Community 16 - "IslandNavigationStore"
Cohesion: 0.13
Nodes (16): 2026-07-04 - Phase 4A Island/Tray Page Navigation, 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop, 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception, 2026-07-05 - Phase 8C.1 Exact Gesture Actions, ExpandedIslandPage, .accessibilityLabel, island, stats (+8 more)

### Community 17 - ".start"
Cohesion: 0.25
Nodes (4): MockTimerNotificationCenterClient, Bool, Void, TimerCompletionNotificationTests

### Community 18 - "FileShelfStore"
Cohesion: 0.15
Nodes (12): 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab, 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout, FileShelfStore, AnyCancellable, Set, URL, UserDefaults, FileShelfModuleView (+4 more)

### Community 19 - "SupportedApp"
Cohesion: 0.09
Nodes (24): 2026-07-03 - Common App Launch Resolver, 2026-07-04 - Phase 3 Album Artwork Source Open, AppLaunchService, SupportedApp, arc, brave, .bundleIdentifier, chrome (+16 more)

### Community 20 - "ExpandedIslandView"
Cohesion: 0.15
Nodes (11): 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation, ExpandedIslandView, .airDropTargetBinding, .body, .clipboardBackdropAnimation, .contentVisibilityAnimation, .tabAnimationsEnabled, .tabFadeInAnimation (+3 more)

### Community 21 - "Change Log"
Cohesion: 0.06
Nodes (58): 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup, 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix, 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning, 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend, 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend, 2026-07-04 - Phase 5H Correction Remove Inward Cut, 2026-07-04 - Phase 5H Paused For Later Visual Polish, 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph (+50 more)

### Community 22 - "ExpandedIslandLayoutMetrics"
Cohesion: 0.06
Nodes (32): Phase 12C.1 - Integrated Notch Content Safe Areas, ExpandedIslandLayoutMetrics, .compactScale, .dividerHeight, .dividerWidth, .innerHeight, .innerWidth, .liveActivitiesMaxHeight (+24 more)

### Community 23 - "ArtworkAccentColorCache"
Cohesion: 0.12
Nodes (16): 2026-07-04 - Phase 5G Native Visualizer And Artwork Color, ArtworkAccentColorCache, ArtworkAccentColorExtractor, ArtworkColorSample, Bool, Color, Double, Int (+8 more)

### Community 24 - "DynamicIsland"
Cohesion: 0.05
Nodes (37): Adaptive notch-aware island, App integration, Architecture, Build, Collapsed, Collapsed hover preview, Content-aware collapsed geometry, Current development status (+29 more)

### Community 25 - "ClipboardHistoryEntry"
Cohesion: 0.12
Nodes (17): Calendar, ObservableObject, ClipboardHistoryEntry, Date, UUID, ClipboardHistoryRowPresentation, ClipboardHistoryView, .body (+9 more)

### Community 26 - "MediaAutomationExecutor"
Cohesion: 0.06
Nodes (44): Clock, ScriptRunner, Entry, MediaAutomationBackoff, MediaAutomationBrowserOperation, .operation, MediaAutomationBrowserResult, MediaAutomationCancellation (+36 more)

### Community 27 - "Int"
Cohesion: 0.10
Nodes (13): 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix, ReferenceWritableKeyPath, .clipboardHistoryMaximumItems, .collapsedPriorityPausedMedia, .collapsedPriorityPausedTimer, .collapsedPriorityPlayingMedia, .collapsedPriorityRecentFiles, .collapsedPriorityRunningTimer (+5 more)

### Community 28 - "DynamicIslandLiveActivity"
Cohesion: 0.13
Nodes (20): Candidate, CollapsedIslandContentMode, battery, fileTray, inactive, media, timer, CollapsedLiveActivityPrioritySettings (+12 more)

### Community 29 - ".init"
Cohesion: 0.11
Nodes (12): Phase 11C.3 - Diagnostic WindowServer Transition Trace, Phase 11C.4 - WindowServer Space-Transition Counter-Translation, NSPanel, NSRect, NSView, Native overlay, geometry and input, IslandOverlayPanel, .canBecomeKey (+4 more)

### Community 30 - "ClipboardImageNormalizerTests"
Cohesion: 0.09
Nodes (12): CFDictionary, CGImageSource, ImageIO, ClipboardImageNormalizer, ClipboardImageResourcePolicy, Any, Bool, Int (+4 more)

### Community 31 - "MediaArbitratorTests"
Cohesion: 0.18
Nodes (3): MediaArbitratorTests, Bool, NSImage

### Community 32 - "BatteryActivitySnapshot"
Cohesion: 0.09
Nodes (18): Phase 11A - Battery Live Activity, IOKit.ps, BatteryActivityProvider, BatteryActivitySnapshot, .activityState, .isEligible, .isLowPower, Any (+10 more)

### Community 33 - "AgentIngestionCoordinator"
Cohesion: 0.05
Nodes (75): RawRepresentable, AgentIngestionCoordinator, Bool, CheckedContinuation, Date, Never, Result, Void (+67 more)

### Community 34 - "AgentBridgeAuthenticator"
Cohesion: 0.18
Nodes (9): AgentBridgeAuthenticator, .rememberedNonceCount, AgentBridgeCrypto, NonceEntry, Bool, Date, Int, Int64 (+1 more)

### Community 35 - "XCTest"
Cohesion: 0.13
Nodes (8): AppKit, Combine, DynamicIsland, Array, .single, Element, UniformTypeIdentifiers, XCTest

### Community 36 - "AppendOnlyRecordTailer"
Cohesion: 0.11
Nodes (17): DispatchSourceFileSystemObject, NoticeHandler, RecordHandler, A2.1 ingress boundary and A2.2 handoff, AppendOnlyFileIdentity, AppendOnlyRecordStartPolicy, boundedCatchUp, fromEnd (+9 more)

### Community 37 - "MediaModuleView"
Cohesion: 0.07
Nodes (28): 2026-07-03 - Phase 2 Empty Media Launcher State, 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling, 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout, EmptyMediaLauncherView, .body, MediaLauncherButton, .body, MediaModuleView (+20 more)

### Community 38 - "Phase Workflow For Future Work"
Cohesion: 0.08
Nodes (27): 2026-07-03 - Context File Added, 2026-07-03 - Current Uncommitted Overlay/Animation Work, 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse, 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection, 2026-07-03 - Phase 2.5 Now Playing Provider Architecture, 2026-07-04 - Atoll Reference-Guided Morph Cleanup, 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment, 2026-07-04 - Phase 2.7 Media Source Arbitration (+19 more)

### Community 39 - "MediaCandidate"
Cohesion: 0.22
Nodes (4): 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority, MediaArbitrator, MediaCandidate, .sourceKey

### Community 40 - "FileDropProviderLoaderTests"
Cohesion: 0.19
Nodes (8): .fileDropTargetBinding, .filesTargetBinding, ControlledDataRepresentation, FileDropProviderLoaderTests, NSItemProvider, URL, UserDefaults, Void

### Community 41 - "What You Must Do When Invoked"
Cohesion: 0.06
Nodes (32): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+24 more)

### Community 42 - "YouTubeMetadataProvider"
Cohesion: 0.14
Nodes (15): CodingKey, CodingKeys, files, imagePNG, text, type, url, CodingKeys (+7 more)

### Community 43 - "String"
Cohesion: 0.10
Nodes (16): 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip, BrowserScriptTarget, MediaController, .currentArtworkPresentationIdentity, MediaPlayer, .displayName, music, .playPauseCommand (+8 more)

### Community 44 - ".refresh"
Cohesion: 0.27
Nodes (5): ManualCountdownClock, .now, Duration, MainActor, TimerControllerTests

### Community 45 - "IslandStateStore"
Cohesion: 0.07
Nodes (24): 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout, 2026-07-04 - Phase 5H Notch-Integrated Island Shape, App Entry, Collapsed, Current Architecture, Current Stable Baseline, Current UI/Interaction Requirements, Debugging Notes (+16 more)

### Community 47 - "CGFloat"
Cohesion: 0.07
Nodes (33): AnimatablePair, 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell, Phase 12C - Integrated Atoll-Style Notch Shell Geometry, LinearGradient, Activities and utility modules, Build and tests, Clipboard engine and persistence, Current architecture baseline (+25 more)

### Community 48 - "View"
Cohesion: 0.13
Nodes (20): AirDropDropZoneView, .subtitle, DedicatedTimerPageView, .controlsFontSize, .controlsSpacing, .titleFontSize, .usesCompactLayout, ExpandedHeaderButton (+12 more)

### Community 49 - "OverlayWindowController"
Cohesion: 0.07
Nodes (33): CFTimeInterval, 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish, 2026-07-04 - Phase 5J.4 Final Media Fit And Mouse Leave Rect Fix, 2026-07-04 - Phase 5J.5 Final Expanded Hover Tolerance Tightening, 2026-07-11 - Phase 9C Liquid Glass Visual Repair, Phase 12B - Native Overlay Cleanup And Runtime Optimization, Phase 12C.5 - Content-Aware Physical-Notch Activity Wings, CustomStringConvertible (+25 more)

### Community 50 - "CollapsedLiveActivityPrioritySource"
Cohesion: 0.15
Nodes (13): CollapsedLiveActivityPrioritySource, chargingBattery, .defaultPriority, .defaultRank, .displayName, fullBattery, .id, lowBattery (+5 more)

### Community 51 - "IslandRootView.swift"
Cohesion: 0.07
Nodes (33): EnvironmentKey, CollapsedPreviewActivityRow, .body, .iconColor, CollapsedPreviewLabel, .body, CollapseShellOnlyEnvironmentKey, EnvironmentValues (+25 more)

### Community 52 - "Sendable"
Cohesion: 0.03
Nodes (121): Codable, Equatable, Hashable, Identifiable, 1. Domain contracts, Sendable, AgentReductionResult, Date (+113 more)

### Community 53 - ".reload"
Cohesion: 0.26
Nodes (3): Bool, T, UserDefaults

### Community 54 - "Bool"
Cohesion: 0.08
Nodes (28): Phase 12C.3 - Hardware Notch Center Exclusion, Left, Right, CollapsedBatteryActivityCompactView, .iconColor, CollapsedFileActivityCompactView, .accessibilityLabel, .fileText (+20 more)

### Community 55 - "RecordSink"
Cohesion: 0.17
Nodes (11): AppendOnlyRecordTailerTests, Fixture, NoticeSink, .values, openDescriptorCount(), RecordSink, .strings, Bool (+3 more)

### Community 56 - "ClipboardPasteboardReadResult"
Cohesion: 0.10
Nodes (21): ClipboardImageCapture, ClipboardImageRepresentation, encoded, oversized, ClipboardPasteboardCapture, image, ready, ClipboardPasteboardReadResult (+13 more)

### Community 57 - "OverlayPresentationSessionTests"
Cohesion: 0.15
Nodes (9): OverlayPresentationSession, .canPresentOverlay, Int, TimeInterval, OverlayPresentationSessionTests, Bool, NSEvent, TimeInterval (+1 more)

### Community 58 - ".event"
Cohesion: 0.22
Nodes (11): Success, AgentIngestionCoordinatorTests, Array, .single, Element, Result, Set, StaticString (+3 more)

### Community 59 - ".sessionID"
Cohesion: 0.09
Nodes (39): AgentBridgeWirePayload, .populatedFieldCount, AgentActivityDescriptor, AgentApprovalRequest, AgentApprovalResolution, AgentCommandEvent, AgentEventPayload, activity (+31 more)

### Community 60 - ".opacity"
Cohesion: 0.09
Nodes (33): Animation, 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish, 2026-07-04 - Phase 6B.5 Stable Inner Content Staging, .body, AnyTransition, .blurBounce, .compactMediaContent, BlurBounceModifier (+25 more)

### Community 61 - "AgentBridgeClient"
Cohesion: 0.12
Nodes (15): AgentBridgeClient, invalidInput, AgentBridgeClientResult, accepted, rejected, AgentBridgeClientTransport, AgentBridgeNetworkTransport, Bool (+7 more)

### Community 62 - "IslandHostingView"
Cohesion: 0.13
Nodes (13): 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing, 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures, 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture, 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix, 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix, Known Fragile Areas, NSHostingView, NSSize (+5 more)

### Community 63 - "ManualMediaRemoteDeadlineScheduler"
Cohesion: 0.06
Nodes (42): 2026-07-04 - Phase 3.4 Album Artwork Stability, CopyAppDisplayNameFunction, GetNowPlayingInfoFunction, Completion, value, MediaRemoteCallbackBridge, MediaRemoteCallbackState, .isPending (+34 more)

### Community 64 - "CaseIterable"
Cohesion: 0.04
Nodes (51): CaseIterable, 2026-07-11 - Phase 9D Theme Simplification, AnimationPreset, .displayName, .id, instant, normal, .shellDuration (+43 more)

### Community 65 - "AgentEventStore"
Cohesion: 0.16
Nodes (7): AgentEventStore, .activeSessions, .sessionsRequiringAttention, Bool, AgentEventStoreTests, Int, TimeInterval

### Community 66 - ".makeProcessor"
Cohesion: 0.28
Nodes (5): AgentBridgeRequestProcessor, AgentBridgeEnvelopeIntegrationTests, StaticString, UInt, Any

### Community 67 - "AgentBridgeDiscoveryRecord"
Cohesion: 0.31
Nodes (5): AgentBridgeDiscoveryRecord, Date, Int, Int32, UInt16

### Community 68 - "Data"
Cohesion: 0.09
Nodes (11): Data, FileClipboardHistoryPersistence, FileManager, URL, ControlledClipboardPersistence, .data, .deleteCount, .saveCount (+3 more)

### Community 69 - "AppDelegate"
Cohesion: 0.11
Nodes (19): 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix, 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation, Phase 13B.1 - Clipboard History Engine, NSApplicationDelegate, 2. Existing DynamicIsland invariants, Composition, state and settings, AppDelegate, .liveActivitySettingsPublisher (+11 more)

### Community 70 - "UInt64"
Cohesion: 0.23
Nodes (5): UInt64, SystemStatsFormatting, SystemStatsSnapshot, StatsPageView, .body

### Community 72 - "DynamicIslandLiveActivityKind"
Cohesion: 0.33
Nodes (6): DynamicIslandLiveActivityKind, battery, fileTray, media, system, timer

### Community 73 - "AppendOnlyRecordTailer.swift"
Cohesion: 0.09
Nodes (25): Dispatch, AppendOnlyRecordLimits, AppendOnlyRecordTailerFailure, identityRace, ioFailure, notRegularFile, parentUnavailable, permissionDenied (+17 more)

### Community 74 - "DelimitedRecordFramer"
Cohesion: 0.20
Nodes (7): BoundedRecordRing, .orderedRecords, DelimitedRecordFramer, Output, Int, Void, DelimitedRecordFramerTests

### Community 75 - "FileDropProviderLoader"
Cohesion: 0.16
Nodes (10): NSSecureCoding, completion, FileDropProviderLoader, FileDropURLAccumulator, .urls, SendableItemProvider, NSItemProvider, TimeInterval (+2 more)

### Community 76 - "AgentBridgeDiscoveryPublisher"
Cohesion: 0.19
Nodes (6): AgentBridgeDiscoveryPublisher, FileManager, URL, AgentBridgeDiscoveryTests, UInt16, URL

### Community 77 - "AgentCapability"
Cohesion: 0.10
Nodes (20): AgentCapability, approvalControl, approvalObservation, commandLifecycle, contextUsage, costUsage, explicitThinking, gitMetadata (+12 more)

### Community 78 - "Meaningful regression history"
Cohesion: 0.12
Nodes (15): AppSettings normalization recursion — 7A.1, Artwork early handoff / independent state — 8C.15, 13A.1, Clipboard duplicate tick / approximate transition — 13B.2, Clipboard Escape swallowed before SwiftUI — 13C.1, Clipboard scrolling blocked by Island input — 13B.2, Double media command / expansion tail — 8C.3–15, Hidden mounted secondary preview — 10B.2, 10C, Long scheme-less text misclassified as URL — 13C.1 (+7 more)

### Community 79 - ".loadFileURLs"
Cohesion: 0.21
Nodes (7): 2026-07-05 - Phase 8A File Shelf Tray Polish, Bool, URL, Bool, AirDropURLAccumulator, .urls, URL

### Community 80 - "ShortcutsModuleView"
Cohesion: 0.23
Nodes (10): MediaButton, .body, ShortcutsModuleView, .body, .displayedShortcuts, .hiddenShortcutCount, .shortcutTileHeight, CGFloat (+2 more)

### Community 83 - "SequenceClientTransport"
Cohesion: 0.24
Nodes (9): AgentBridgeClientRequest, AgentBridgeSharedClientTests, Outcome, failure, response, SequenceClientTransport, SequenceProfileProvider, Duration (+1 more)

### Community 84 - ".apply"
Cohesion: 0.09
Nodes (15): AgentEventReducer, AgentEventStoreLimits, .normalized, SemanticResult, applied, rejected, Bool, Date (+7 more)

### Community 85 - "AgentBridgeSharedDiscoveryTests"
Cohesion: 0.15
Nodes (12): AgentBridgeSharedDiscoveryTests, FixedDiscoveryFileReader, Bool, Int, mode_t, StaticString, uid_t, UInt (+4 more)

### Community 86 - "AgentEventType"
Cohesion: 0.05
Nodes (42): AgentEventType, agentWorking, approvalRequested, approvalResolved, capabilitiesUpdated, commandCompleted, commandStarted, heartbeat (+34 more)

### Community 87 - "AgentEventValidationError"
Cohesion: 0.07
Nodes (31): AgentEventValidationError, invalidApprovalResolution, invalidCorrelationID, invalidEventID, invalidGeneration, invalidProvider, invalidSessionID, invalidSubagentID (+23 more)

### Community 88 - "ShortcutsStore"
Cohesion: 0.24
Nodes (4): LauncherShortcut, ShortcutsStore, .shortcuts, UUID

### Community 89 - "AgentRelayCommandTests"
Cohesion: 0.11
Nodes (13): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000) (+5 more)

### Community 90 - "MediaController.swift"
Cohesion: 0.07
Nodes (38): 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard, 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair, Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff, Index, Media and artwork, Array, ArtworkFlipPhase, firstHalf (+30 more)

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

### Community 103 - "CountdownLifecycleEvent"
Cohesion: 0.14
Nodes (11): CountdownLifecycleEvent, cancelled, completed, scheduled, Double, TimerProgressColorStage, high, low (+3 more)

### Community 104 - "RecordingFileShelfDefaults"
Cohesion: 0.25
Nodes (3): RecordingFileShelfDefaults, Any, UserDefaults

### Community 105 - "AgentEvent"
Cohesion: 0.09
Nodes (22): 3. Component boundaries, Adapter contract, State ownership, AgentEvent, .effectiveTimestamp, .fingerprint, .instanceID, .payloadIsCompatible (+14 more)

### Community 106 - "AgentBridgeDiscoveryFileSnapshot"
Cohesion: 0.18
Nodes (13): dev_t, ino_t, AgentBridgeClientProfileProviding, AgentBridgeDiscoveryFileReading, AgentBridgeDiscoveryFileSnapshot, AgentBridgeDiscoveryReader, Bool, Date (+5 more)

### Community 108 - "ShelfFileTile"
Cohesion: 0.23
Nodes (8): 2026-07-04 - Phase 4C Tray File Actions Context Menu, FileShelfActions, ShelfFileTile, .body, .displayName, .fileImage, Bool, URL

### Community 109 - "FileShelfTemporaryStorage"
Cohesion: 0.23
Nodes (6): FileDropPolicy, FileShelfTemporaryStorage, Bool, URL, .canAcceptExpandedFileDrop, .canAcceptCollapsedFileDrop

### Community 110 - "NetworkCounters"
Cohesion: 0.16
Nodes (8): ifaddrs, NetworkCounters, Self, TimeInterval, Interface, NetworkCounterSamplingTests, UInt32, UnsafeMutablePointer

### Community 111 - "ServerFactorySpy"
Cohesion: 0.23
Nodes (9): AgentBridgeLifecycleTests, DiscoverySpy, .records, .removedLaunchIDs, ServerFactorySpy, .createdCount, AgentBridgeServerFactory, Error (+1 more)

### Community 112 - "AgentBridgeEnvelopeError"
Cohesion: 0.06
Nodes (35): Error, AgentBridgeClientTransportError, connectTimedOut, malformedResponse, requestTimedOut, responseTooLarge, unavailable, AgentBridgeSharedError (+27 more)

### Community 113 - "AgentBridgeNetworkServer"
Cohesion: 0.20
Nodes (10): DispatchQueue, NWListener, ObjectIdentifier, RequestHandler, AgentBridgeNetworkConnection, AgentBridgeNetworkServer, NWConnection, Result (+2 more)

### Community 114 - "AgentBridge"
Cohesion: 0.17
Nodes (12): HTTPURLResponse, AgentBridge, Runtime, AgentBridgeServerFactory, Error, UUID, AgentBridgeDiscoveryPublishing, AgentBridgeHTTPResponse (+4 more)

### Community 115 - "ClipboardHistoryPresentationState"
Cohesion: 0.34
Nodes (4): ClipboardHistoryPresentationState, .topmostOverlayPresentation, Int, ClipboardHistoryPresentationStateTests

### Community 116 - ".assertFailure"
Cohesion: 0.18
Nodes (3): AgentBridgeHTTPParserTests, StaticString, UInt

### Community 117 - "Foundation"
Cohesion: 0.10
Nodes (12): AgentBridgeShared, CoreFoundation, CryptoKit, Darwin, Foundation, Security, AgentBridgeDiscoveryError, insecurePermissions (+4 more)

### Community 118 - "AudioVisualizerView"
Cohesion: 0.33
Nodes (7): 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix, AudioVisualizerView, .body, .shouldAnimateContinuously, .visualizerOpacity, Double, TimeInterval

### Community 119 - "AgentBridgeClientProfile"
Cohesion: 0.16
Nodes (7): AgentBridgeClientProfile, AgentBridgeProtocol, AgentBridgeSharedNetworkIntegrationTests, StaleThenCurrentProfileProvider, Int, URL, Duration

### Community 120 - "AgentBridgeEnvelopeBuildError"
Cohesion: 0.12
Nodes (11): AgentBridgeEnvelopeBuilder, AgentBridgeEnvelopeBuildError, emptyBatch, emptyInput, eventTooLarge, inputTooLarge, malformedEnvelope, malformedJSON (+3 more)

### Community 121 - "AgentBridgeHTTPRequestParser"
Cohesion: 0.18
Nodes (10): AgentBridgeHTTPParseResult, failure, needMore, request, AgentBridgeHTTPRequestParser, ParsedHeaders, ParseFailure, .result (+2 more)

### Community 122 - "AgentEvidenceAuthority"
Cohesion: 0.06
Nodes (39): Comparable, Decodable, Int, 7. Attention presentation contract, AgentBridgeIngress, Bool, Date, Result (+31 more)

### Community 123 - "Agent Activity Integration Architecture"
Cohesion: 0.14
Nodes (14): 10. Performance budgets, 11. Failure model, 12. Adversarial conclusions and deferred risks, 1. Decision summary, 4. Per-event authority, 5. Local bridge decision, 6. Privacy and security boundaries, 8. Expanded Agent Activity contract (+6 more)

### Community 124 - "Double"
Cohesion: 0.16
Nodes (14): .percentText, .visualizerAccentColor, .body, StatsLineChart, .body, StatsMetricCard, .body, Double (+6 more)

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

### Community 129 - ".constrainedActivePlayerLayout"
Cohesion: 0.27
Nodes (6): Double, ClickableAlbumArtworkButton, .artwork, .body, .constrainedActivePlayerView, .regularActivePlayerView

### Community 130 - "AgentBridgeNetworkExchange"
Cohesion: 0.28
Nodes (7): AgentBridgeNetworkExchange, Duration, NWConnection, Result, UInt16, Void, AgentBridgeClientResponse

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
Cohesion: 0.25
Nodes (5): AgentBridgeRequestAuthentication, Bool, Int, Int64, AgentBridgeSharedCryptoTests

### Community 136 - "AgentBridgeHTTPStatus"
Cohesion: 0.14
Nodes (14): AgentBridgeHTTPStatus, accepted, badRequest, conflict, internalServerError, methodNotAllowed, notFound, ok (+6 more)

### Community 137 - "Agent Activity Feature Phase Plan"
Cohesion: 0.40
Nodes (5): 1. Rules for every implementation phase, 2. Dependency map, 4. A11 measurable release gates, 5. Known non-blocking research gaps, Agent Activity Feature Phase Plan

### Community 139 - "AgentBridgeClientError"
Cohesion: 0.14
Nodes (14): AgentBridgeClientError, authenticationFailed, discoveryUnavailable, malformedResponse, timedOut, transportUnavailable, AttemptError, authentication (+6 more)

### Community 140 - "SwiftUI"
Cohesion: 0.15
Nodes (8): 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry, 2026-07-05 - Settings Window Activation Fix, NSObject, NSWindowDelegate, SettingsWindowController, Notification, NSWindow, SwiftUI

### Community 141 - ".decode"
Cohesion: 0.50
Nodes (3): AgentBridgeEnvelopeDecoder, Any, Int

### Community 142 - "AgentRelayExitCode"
Cohesion: 0.18
Nodes (10): Int32, AgentRelayExitCode, accepted, authenticationFailed, bridgeUnavailable, discoveryUnavailable, invalidInput, serverRejected (+2 more)

### Community 143 - "AgentNotch Reference Review"
Cohesion: 0.18
Nodes (11): 10. Strongest ideas retained, 1. Architecture observed, 2. Mechanism classification, 3. Discovery and identity weaknesses, 4. Completion and permission weaknesses, 5. JSONL robustness weaknesses, 6. OTLP/server weaknesses, 7. UI and lifecycle weaknesses (+3 more)

### Community 144 - "ModuleViews.swift"
Cohesion: 0.13
Nodes (14): AlbumArtworkView, .body, AudioVisualizerVariant, .barWidth, compact, expanded, .maximumBarHeight, .size (+6 more)

### Community 145 - "XCTestCase"
Cohesion: 0.25
Nodes (3): IslandStateStoreTests, MediaSourceOpenTargetTests, XCTestCase

### Community 146 - "AgentBridgeCredentialError"
Cohesion: 0.22
Nodes (6): OSStatus, AgentBridgeCredentialError, invalidStoredSecret, keychain, randomGeneration, SystemAgentBridgeCredentialStore

### Community 147 - "AgentBridgeAuthenticationError"
Cohesion: 0.22
Nodes (9): AgentBridgeAuthenticationError, invalidNonce, invalidSignature, invalidTimestamp, missingHeaders, replay, replayCacheFull, timestampOutsideWindow (+1 more)

### Community 149 - "LaunchAtLoginController.swift"
Cohesion: 0.40
Nodes (3): ServiceManagement, LaunchAtLoginController, Bool

### Community 150 - "LockedValue"
Cohesion: 0.60
Nodes (3): LockedValue, .value, Value

## Knowledge Gaps
- **951 isolated node(s):** `PackageDescription`, `package_app.sh script`, `unavailable`, `connectTimedOut`, `requestTimedOut` (+946 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1221 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `String` to `AppSettings`, `IslandGestureAction`, `ArtworkFlipPresentationState`, `SettingsView`, `IslandRootView`, `TimerController`, `SystemClipboardPasteboardClient`, `TimerCompletionNotificationCoordinator`, `ClipboardHistoryPayload`, `ClipboardHistoryStoreTests`, `.normalizeAndSaveDouble`, `CollapsedLiveActivitySelectorTests`, `IslandNavigationStore`, `.start`, `FileShelfStore`, `SupportedApp`, `Change Log`, `ArtworkAccentColorCache`, `ClipboardHistoryEntry`, `MediaAutomationExecutor`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaArbitratorTests`, `BatteryActivitySnapshot`, `AgentIngestionCoordinator`, `AgentBridgeAuthenticator`, `MediaModuleView`, `Phase Workflow For Future Work`, `MediaCandidate`, `FileDropProviderLoaderTests`, `YouTubeMetadataProvider`, `IslandStateStore`, `AppSettingsTests`, `View`, `OverlayWindowController`, `CollapsedLiveActivityPrioritySource`, `IslandRootView.swift`, `Sendable`, `.reload`, `Bool`, `RecordSink`, `.event`, `.sessionID`, `.opacity`, `AgentBridgeClient`, `ManualMediaRemoteDeadlineScheduler`, `CaseIterable`, `AgentEventStore`, `.makeProcessor`, `AgentBridgeDiscoveryRecord`, `Data`, `AppDelegate`, `UInt64`, `DynamicIslandLiveActivityKind`, `FileDropProviderLoader`, `AgentBridgeDiscoveryPublisher`, `AgentCapability`, `ShortcutsModuleView`, `SequenceClientTransport`, `.apply`, `AgentBridgeSharedDiscoveryTests`, `AgentEventType`, `AgentEventValidationError`, `ShortcutsStore`, `MediaController.swift`, `ServerSpy`, `SettingsSection`, `RecordingFileShelfDefaults`, `AgentEvent`, `AgentBridgeDiscoveryFileSnapshot`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`, `ServerFactorySpy`, `AgentBridgeEnvelopeError`, `AgentBridge`, `AgentBridgeClientProfile`, `AgentBridgeEnvelopeBuildError`, `AgentBridgeHTTPRequestParser`, `AgentEvidenceAuthority`, `Double`, `LiveActivityStore`, `.constrainedActivePlayerLayout`, `AgentBridgeNetworkExchange`, `.signedRequest`, `.canonicalMessage`, `AgentBridgeHTTPStatus`, `AgentRelayExitCode`, `XCTestCase`, `.remainingTime`?**
  _High betweenness centrality (0.413) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `AppSettings` to `IslandGestureAction`, `.constrainedActivePlayerLayout`, `MenuBarController`, `IslandRootView`, `SettingsView`, `ClipboardHistoryStore`, `SwiftUI`, `NotchGeometryService`, `.normalizeAndSaveDouble`, `ClipboardHistoryStoreTests`, `IslandNavigationStore`, `FileShelfStore`, `ExpandedIslandView`, `Change Log`, `ClipboardHistoryEntry`, `Int`, `DynamicIslandLiveActivity`, `.init`, `MediaModuleView`, `FileDropProviderLoaderTests`, `String`, `IslandStateStore`, `AppSettingsTests`, `CGFloat`, `View`, `OverlayWindowController`, `.reload`, `Bool`, `ClipboardPasteboardReadResult`, `OverlayPresentationSessionTests`, `CaseIterable`, `AppDelegate`, `UInt64`, `ShortcutsModuleView`, `LiveActivitySettingsSubscriberTests`, `ShelfFileTile`, `FileShelfTemporaryStorage`?**
  _High betweenness centrality (0.116) - this node is a cross-community bridge._
- **Why does `OverlayWindowController` connect `OverlayWindowController` to `CaseIterable`, `AppSettings`, `IslandRootView`, `AppDelegate`, `IslandEscapeRouter`, `SwiftUI`, `IslandStateStore`, `NotchGeometryService`, `ExpandedIslandView`, `Change Log`, `Bool`, `OverlayPresentationSessionTests`, `DynamicIslandLiveActivity`, `.init`, `IslandHostingView`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `AppSettings` (e.g. with `2026-07-04 - Phase 7A.2 Expanded Island Settings Entry` and `2026-07-05 - Phase 7A.4 Island Size Settings Wiring`) actually correct?**
  _`AppSettings` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 29 inferred relationships involving `OverlayWindowController` (e.g. with `2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix` and `2026-07-04 - Phase 5H Notch-Integrated Island Shape`) actually correct?**
  _`OverlayWindowController` has 29 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `package_app.sh script`, `unavailable` to the rest of the system?**
  _951 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppSettings` be split into smaller, more focused modules?**
  _Cohesion score 0.024731182795698924 - nodes in this community are weakly interconnected._