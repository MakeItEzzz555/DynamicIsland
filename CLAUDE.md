# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

DynamicIsland is a native macOS 14.6+ menu-bar (accessory, `LSUIElement`) app written in Swift 6 with SwiftPM only (no Xcode project). It renders a Dynamic Island–style overlay around the MacBook notch using SwiftUI hosted in a single AppKit `NSPanel`.

## Commands

```sh
swift build                      # debug build
swift run DynamicIsland          # run the app (menu bar accessory)
swift test                       # full suite
swift test --filter NotchGeometryServiceTests          # one test class
swift test --filter NotchGeometryServiceTests/testInfersHardwareNotchFromAuxiliaryAreas  # one test
swift build -c release
Scripts/package_app.sh           # -> dist/DynamicIsland.app (ad-hoc signed)
DEVELOPER_ID_APP="Developer ID Application: Name (TEAMID)" Scripts/package_app.sh
```

CI (`.github/workflows/agent-continuation-ci.yml`) runs, in order: `git diff --check HEAD^`, `swift build`, `swift test`, `swift build -c release`, packaging, then `codesign --verify --strict` on the three helpers in `Contents/Helpers/` and `codesign --verify --deep --strict` on the app. Run the same steps locally before claiming a change is done. There is no linter configured.

`Scripts/package_app.sh` owns the generated `Info.plist` (including usage descriptions like `NSAppleEventsUsageDescription`, `NSRemindersUsageDescription`). Entitlements for Developer ID signing are in `Scripts/DynamicIsland.entitlements.plist`. Any new privacy-gated framework needs its usage string added there, and any new executable product must be copied into `Helpers/` and signed there too.

## graphify knowledge graph (from AGENTS.md)

A knowledge graph lives in `graphify-out/`. For codebase questions, first try `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` before raw grepping; read `graphify-out/GRAPH_REPORT.md` only for broad architecture review. Dirty `graphify-out/` files are expected and are not a reason to skip it. After modifying code, run `graphify update .` (AST-only, no API cost).

## Architecture

### Targets (Package.swift)

- `DynamicIsland` — the app. Layered folders under `Sources/DynamicIsland/`: `App` (lifecycle, menu bar, settings window, and the composition root), `Geometry` (notch geometry), `Overlay` (the panel), `State` (settings, collapsed/expanded state, navigation, gestures), `Modules` (feature controllers/stores), `Agents` (AI coding-agent monitoring), `Messaging` (actionable message notifications), `Views` (SwiftUI).
- `AgentBridgeShared` — wire protocol, HMAC request authentication, discovery-file reader, and HTTP client shared by the app and the relays.
- `CodexHookShared` / `ClaudeHookShared` — normalizers that turn raw Codex / Claude Code hook JSON into bridge events.
- `DynamicIslandAgentRelay`, `DynamicIslandCodexHookRelay`, `DynamicIslandClaudeHookRelay` — tiny CLI helpers shipped inside the app bundle and invoked by agent hooks.
- `DynamicIslandTests` — single XCTest target covering everything; shared fakes live in `Tests/DynamicIslandTests/Fixtures/`.

### Composition root

`App/DynamicIslandApp.swift` instantiates every store/controller (media, timer, stats, file shelf, clipboard, productivity controllers, agent stack) and wires their published state into `LiveActivityStore` via `liveActivities.update(...)`/`remove(id:)`. New Live Activity sources are wired here. Live Activities are an internal model, **not** ActivityKit; the collapsed island shows a single winner chosen by deterministic priority, and `LiveActivityLayoutResolver` gives each activity its own left/right width profile around the physical notch.

### Overlay: single stable panel

- One maximum-size transparent `NSPanel` (`Overlay/OverlayWindowController.swift`) stays fixed; SwiftUI (`Views/IslandRootView.swift`) morphs the visible shell between collapsed and expanded. Do not resize/swap windows for expansion or reintroduce split panels, probe panels, or per-frame WindowServer compensation.
- Click-through is implemented by shape-aware hit testing restricted to the visible island surface.
- `NotchGeometryService` derives notch geometry from `NSScreen` safe areas; notchless/external displays get a floating island, never a fake notch.
- `OverlayWindowController` is the most fragile file — only change it when a feature specifically requires it.

### Productivity capabilities

`Modules/IslandCapabilityRegistry.swift` defines `IslandCapabilityID` and a snapshot model (enabled / permission / availability / health / supported actions). Productivity controllers (`KeepAwakeController`, `WindowSnapController`, `TerminalSessionController`, `RemindersController`, …) take the registry in their initializer and publish their status into it, so settings and UI read capability state uniformly.

### Agent monitoring pipeline

1. On start, `AgentBridge` (`Agents/AgentBridge.swift`) reads a secret from the Keychain once, starts a loopback-only (`127.0.0.1`) `NWListener` HTTP server, and publishes per-producer discovery records (e.g. `~/Library/Application Support/DynamicIsland/AgentBridge/claude-hook-v1.json`) containing port, route, and a derived ephemeral key. Helpers never touch the Keychain.
2. Agent hooks invoke a relay helper, which reads bounded stdin, normalizes it (`*HookNormalizer`), loads the discovery record, and sends an HMAC-authenticated request. Relays must **fail open** (exit 0 silently) so they never block the agent.
3. `AgentBridgeIngress` validates protocol version/producer/tokens, then `AgentIngestionCoordinator` (producer registration, leases, source health) feeds `AgentEventStore`, whose reducer drives the views in `Views/Agent*Views.swift`.
4. Beyond hooks, sessions are also recovered/observed from transcripts and rollouts (`ClaudeTranscriptRecovery`, `CodexRolloutRecovery`, `CodexRolloutSessionMonitor`) and can be driven interactively (`AgentManagedSessionController`, `CodexAppServerClient`, `ClaudeCodeStreamingClient`).

Invariants for the agent stack:
- Only the dedicated, authenticated Codex `PermissionRequest` route can return approval decisions (exact session/request correlation, expiry, replay protection, one-shot). Claude and generic producers are observation-only.
- Timeout, shutdown, or transport failure must return **no decision** so the agent keeps its native prompt — never auto-approve on infrastructure failure.
- Displayed command text must be sanitized/bounded (`AgentPrivacyProjection`): no secrets, env values, auth headers, raw output, hidden reasoning, or full paths.
- Don't weaken Keychain storage or HMAC authentication. Repeated Keychain prompts during development are usually caused by signing-identity churn between debug, ad-hoc, and packaged builds.

### Messaging

`MessagingController` talks only through a `MessagingProviderAdapter` and never assumes a capability the adapter doesn't report. `MessagesAppAdapter` (Apple Messages) reads Notification Center records, which requires opting in plus Full Disk Access. It resolves each record to one exact chat through the read-only Messages database (`ReadOnlySQLite`, `MessagesConversationResolver`) and sends through Apple Events (`MessagesAutomation`).

Invariants:
- Conversation identity is provider-native IDs only, never display names or notification titles. If a notification is unresolved or ambiguous, it gets no reply target (Open Messages only).
- Sending uses Apple Events with descriptor parameters: no script interpolation, no Accessibility, no UI scripting. A send reports `.confirmed` only once the outgoing message shows up in that exact chat. If Messages accepts it but it never shows up, the result is `.uncertain`. The draft is cleared only on `.confirmed`.
- Message bodies, recipients and drafts are never logged or persisted. System databases are opened read-only. Nothing asks for permission at launch.

### Expanded content sequencing and workspace layout (2026-10-05)

- Collapse: children exit -> acknowledgement -> shell collapses. The root drives the exit from `layoutStore.expandedChildExitGeneration` via `ExpandedChildExitTracker` and acknowledges the *current* generation from visual state; a repeated collapse request re-drives a fresh generation. Committing either island state ends the exit phase (`IslandCollapseRequest.exitPhaseEnds`). Never gate `isExpandedContentExiting` cleanup on a delayed morph generation, and never add timer-based sequencing.
- Workspace widget sizes come only from `IslandWidget.layoutTraits` through `WorkspaceWidgetLayoutProjection` (columns via `WidgetPlacement.stacksBelowPrevious`, auto-stacking of small widgets, fill/solo rules). Widgets read `\.workspaceWidgetPlacement`; do not add widget-name layout conditionals in views.
- Drag intent is `WorkspaceDropResolver.resolveIntent` (left/right insert, above/below `.stack`, hysteresis); the editor previews the exact drop result and edit-mode geometry resizes the shell directly.
- Drag stability rules: the pointer is resolved against the committed draft projected at the *drag-start* size (`WorkspaceDropResolver.dragReferencePoint`), editing projections are top-anchored, and while a drag is active the shell may grow but never shrink below its drag-start size (`IslandLayoutStore.workspaceDragFloor`, cleared on drop/cancel). Breaking any of these reintroduces preview -> resize -> retarget oscillation (the stack-below band was unusable). Reorder/resize use bounce-free `.smooth` springs so retargeting keeps velocity; Reduce Motion returns nil.
- Building inside the iCloud-synced `Documents` checkout can hang in `dsymutil`/`open()` while the file provider is busy; build/test with `--scratch-path` outside `Documents` when that happens.
- Context usage is intentionally not presented (see context.md 2026-10-05 for evidence); usage widgets show provider 5h/Week quota only.
- Workspace schema 2 treats Combined/Codex/Claude usage as ordinary placement-owned widgets. Do not reserve a second permanent usage strip outside `WorkspaceConfiguration`; removing all usage widgets must reclaim all of that height.
- Packaged native widget drags depend on the exported private UTType `app.dynamicisland.workspace-widget` generated by `Scripts/package_app.sh`. If a source drag starts but hover/drop preview never updates before release, verify the Info.plist type declaration before changing resolver geometry.
- `AgentStreamingTextView` keeps an `appliedText` cache and `AgentStreamingTextState.update` fast-paths identical text. Preserve this: SwiftUI/AppKit can call `updateNSView` repeatedly with a huge unchanged transcript, and re-bridging/rescanning it can pin the main thread. Active/Reduce-Motion changes and animation-run expiry must still be processed on the unchanged-text path.
- Solo Media is intentionally left-weighted (bounded width-derived artwork/title inset, centered transport, full-width sliders); Timer/Media sizing comes from placement traits and the actual allocated cell.

## Behavior that must be preserved (from context.md)

- `IslandStateStore` stays limited to `.collapsed` and `.expanded`.
- One physical collapsed swipe left/right = exactly one media next/previous command; collapsed swipe down expands without momentum-tail collapse.
- Keep the artwork image/revision guards: album flips wait for the real new artwork, and visualizer accent color is keyed from the displayed artwork revision.
- Expanded shell keeps its elastic spring; inner expanded content uses blur/scale/opacity without spring bounce.
- The panel and shell are intentionally shadowless.

## Project history docs

`context.md` is a long, dated change log of phases, rejected approaches, and design decisions — search it (don't read it whole) when touching overlay, gesture, or media behavior. Its documented phase workflow is: keep changes scoped, `swift build`, `swift test`, package if relevant, then append a dated entry to `context.md`. `summary.md` summarizes the latest agent-interaction phase. The README's project-structure tree is out of date (it predates `Agents/` and the relay targets).
