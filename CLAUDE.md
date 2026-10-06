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
- Widget sizes are semantic grid classes (2026-10-06): Compact = 1x1 square, Standard = 2x1, Large = 2x2, all derived from one per-surface unit in `WidgetGridMetrics` (Island 162 pt, Agents 236 pt, x `expandedCardScale`; gutter `spacing(8)`). `WorkspaceWidgetLayoutProjection` packs spans with a row-major cursor that never moves backwards (user order is authoritative, no masonry reshuffle); `stacksBelowPrevious` places a region under its anchor; usage widgets are band strips whose size changes density (56/72/96 pt), not span. Narrow hosts wrap or shrink the unit; never rewrite saved sizes. Size is never a scale factor: widgets read `\.workspaceWidgetPlacement.presentationSize` and compose a dedicated layout per class; do not add widget-name layout conditionals in the projection.
- Compact Chat/Terminal is a read-only summary (`AgentCompactSessionSummary`); only the heavy surface is unmounted, exactly like the stack's hidden page, so the managed session, transcript and PTY survive size changes. Feed density by size is `AgentWorkspaceFeedDensity` (Compact keeps a pending approval visible).
- Drag intent is `WorkspaceDropResolver.resolveIntent` (left/right insert, above/below `.stack`, hysteresis); the editor previews the exact drop result and edit-mode geometry resizes the shell directly.
- Drag stability rules: the pointer is resolved against the committed draft projected at the *drag-start* size (`WorkspaceDropResolver.dragReferencePoint`), editing projections are top-anchored, and while a drag is active the shell may grow but never shrink below its drag-start size (`IslandLayoutStore.workspaceDragFloor`, cleared on drop/cancel). Breaking any of these reintroduces preview -> resize -> retarget oscillation (the stack-below band was unusable). Reorder/resize use bounce-free `.smooth` springs so retargeting keeps velocity; Reduce Motion returns nil.
- Keyboard/focus ownership: the island is a non-activating panel. A click that makes a native text input first responder (editable `NSTextView` or `InteractiveTerminalView`, see `IslandKeyboardFocusPolicy`) must also make the panel key (`IslandOverlayPanel.sendEvent` claims key one run-loop turn later); otherwise keystrokes stay with the active app. Never widen that policy to the SwiftUI hosting view or buttons - that would steal the user's keyboard on ordinary clicks.
- Text-input focus only *holds* the expanded island open on pointer exit when the user engaged the field (click or keystroke). Automatic focus (showing the Terminal stack page focuses SwiftTerm) must never publish `setTextInputFocused(true)`; `InteractiveTerminalView.userEngaged` / `AgentPromptTextView.publishEngagement` gate it. Leaving the field or the app releases the hold.
- Every child-exit acknowledgement must survive lost SwiftUI completions: collapse and workspace-geometry children exits both use isolated exit clocks, and a *newer* collapse generation while children are hidden acknowledges immediately (`ExpandedChildExitTracker.drive`).
- Timer ruler: idle selection minimum is 1 s for every input path and zoom level; only an active countdown may present 0 (completion). Each input source (pointer drag, wheel gesture) owns its own selection session (`TimerRulerInputOwnership`); a new gesture settles any foreign/stale session first so a lower-bound rebased anchor is never reused.
- Agent Chat height is content-adaptive (`AgentChatHeightPolicy`): the visible Chat reports `cell - viewport + content` (or `cell - spacer surplus` for resumable surfaces) through `\.agentChatHeightReporter` into `IslandLayoutStore.agentChatHeightHint`, which the projection uses for the region containing Chat. Quantized (4 pt); at/after the cap (the Chat region's own grid cell height) it reports nil so long transcripts keep the previous geometry. Terminal page and edit mode clear it; Compact Chat ignores it. Hint changes resize the shell live (no children-exit handoff) and a stationary pointer is never treated as leaving the island after a content-driven resize (`pointerAtContentResize`).
- The island hugs its children: outside edit mode, a grid narrower than the shell (widened by the notch-safe header minimum) scales its unit uniformly, capped at `WorkspaceWidgetLayoutProjection.fillScaleCap` (1.5x), so Compact stays square, Standard stays 2:1 and there are no side gutters up to the cap. The resolver passes the header width as `preferredContentSize(minimumWidth:)` so heights agree. Sections and usage strips are centered; edit mode keeps intrinsic, top-anchored geometry (drag reference frame).
- Workspace Apply = commit once, end editing, then the owner's `onApplyCompleted` (collapse via the normal request path). The editor never touches shell state; Cancel never collapses.
- Building inside the iCloud-synced `Documents` checkout can hang in `dsymutil`/`open()` while the file provider is busy; build/test with `--scratch-path` outside `Documents` when that happens.
- Context usage is intentionally not presented (see context.md 2026-10-05 for evidence); usage widgets show provider 5h/Week quota only.
- Workspace schema 2 treats Combined/Codex/Claude usage as ordinary placement-owned widgets. Do not reserve a second permanent usage strip outside `WorkspaceConfiguration`; removing all usage widgets must reclaim all of that height.
- Packaged native widget drags depend on the exported private UTType `app.dynamicisland.workspace-widget` generated by `Scripts/package_app.sh`. If a source drag starts but hover/drop preview never updates before release, verify the Info.plist type declaration before changing resolver geometry.
- `AgentStreamingTextView` keeps an `appliedText` cache and `AgentStreamingTextState.update` fast-paths identical text. Preserve this: SwiftUI/AppKit can call `updateNSView` repeatedly with a huge unchanged transcript, and re-bridging/rescanning it can pin the main thread. Active/Reduce-Motion changes and animation-run expiry must still be processed on the unchanged-text path.
- Compact Media is an artwork-first square laid out by the pure `MediaCompactLayout` (artwork 45-56% of the width, centered at the top; title/artist/source; transport; short progress; optional volume/times). It drops content by priority rather than scaling, and the view places each element at its planned frame. Keep that plan as the only source of Compact Media geometry.
- Standard Media (2x1) is laid out by the pure `MediaStandardLayout`: artwork on the left (header-row height, up to 30% of the width), title / artist / platform + visualizer directly above the transport and centered on the controls' axis (symmetric width, at least 45% of the cell, never over the artwork), then transport and full-width progress (inline times) and volume anchored to the bottom; a short cell drops volume, then progress, before crushing the artwork. Large Media is a centered vertical composition whose slider tracks use `MediaWidgetMetrics.sliderWidth` (min(cell x 0.70, 300), floor 96). Artwork is never shrunk with the sliders.
- The edit-mode size control (`WorkspaceWidgetSizeControl`, plus the context menu and accessibility actions) changes only the editor draft: neighbours and the shell preview immediately, Apply persists, Cancel restores.

- Workspace geometry liveness (`WorkspaceGeometryLiveness`) is fed from the values `@Published` *emits*: subscribers run in willSet, so reading the store inside a sink sees the old value. Reading `workspaceLayoutPreview` there made Agents edit entry take the committed-layout children-exit handoff (a ~1.5 s pitch-black shell). Never decide liveness by re-reading the store in a sink.
- Orphan rows: a region that is alone in every grid row it occupies is centered in its section at its semantic size (never stretched). Stack-below regions and anchors with a stacked dependent keep their column. The editor preview and the commit use the same projection, so the preview shows the centered result.
- `WidgetGridMetrics.columns(fitting:)` uses an epsilon: a width of exactly N units must fit N columns.
- Decoration cadence comes only from `IslandFrameCadence`: expanded decorations follow the display refresh rate, always-on collapsed effects (notch glow, collapsed visualizer) run at 60 Hz, Low Power Mode caps at 30 Hz, inactive-app and Reduce Motion pausing still apply. Do not reintroduce fixed 1/24-1/30 caps; interactive motion stays on retargetable SwiftUI springs.

### Capture ownership (2026-10-06)

- Camera Mirror capture starts only from an explicit Start/Allow (`CameraMirrorConsumerLease.startExplicitly` / `open()`). Appearing, re-expanding, tab switches, remounts and edit mode never start it (`attachPreviewConsumer` only counts consumers). Losing the last mirror stops mirror-owned capture and clears the request; island collapse calls `CameraPreviewController.islandDidCollapse()` from the composition root, which stops mirror capture even if SwiftUI kept the mirror mounted and cancels an in-flight start. Only the Settings preview's explicit `open()` owner survives collapse.
- Screen Recording: ad-hoc builds get a new cdhash on every rebuild, so an existing TCC entry stops matching and `CGRequestScreenCaptureAccess` returns false without a prompt. `ScreenCaptureRequestLedger` remembers per build identity that a request was made, so a relaunched copy shows the remove-and-re-add guidance (`notActive`) instead of looping back to "Allow". The recorder pipeline itself is covered by the gated `ScreenRecordingLiveTests`. A stable `LOCAL_SIGN_IDENTITY` keeps grants across rebuilds.

## Behavior that must be preserved (from context.md)

- `IslandStateStore` stays limited to `.collapsed` and `.expanded`.
- One physical collapsed swipe left/right = exactly one media next/previous command; collapsed swipe down expands without momentum-tail collapse.
- Keep the artwork image/revision guards: album flips wait for the real new artwork, and visualizer accent color is keyed from the displayed artwork revision.
- Expanded shell keeps its elastic spring; inner expanded content uses blur/scale/opacity without spring bounce.
- The panel and shell are intentionally shadowless.

## Project history docs

`context.md` is a long, dated change log of phases, rejected approaches, and design decisions — search it (don't read it whole) when touching overlay, gesture, or media behavior. Its documented phase workflow is: keep changes scoped, `swift build`, `swift test`, package if relevant, then append a dated entry to `context.md`. `summary.md` summarizes the latest agent-interaction phase. The README's project-structure tree is out of date (it predates `Agents/` and the relay targets).
