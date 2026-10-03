# Agents workspace architecture

Original reconstruction checkpoint: October 3, 2026. Interaction cleanup continues October 4, 2026 from `a987a9c4139b1be2a05994f9a36a02fb0c2f9869` on `feature/agents-ui-overhaul-continuation`. Validation status for the cleanup is recorded separately below.

## Surface roles

DynamicIsland still has only the persistent `collapsed` and `expanded` shells. Agents workspace emphasis is an internal expanded-layout allocation, not a third island state.

- **Primary chat:** the exact selected managed session transcript, or an explicit provider-verified exact Resume handoff. Non-attachable observation never establishes interactive ownership; it uses the existing New Chat launcher form instead. A semantic Libraries.dev ThinkingOrb remains the persistent top-left high-level activity glyph. The active surface is wrapped by the native Libraries.dev BorderBeam. The selected model is controlled from the compact Agents toolbar; supported next-turn reasoning effort remains inside the chat surface. Assistant transcript rows use the same session's deterministic BotAvatar identity; only the latest active response runs the rich semantic rig, while historical response avatars are frozen.
- **Right workspace:** one retained surface with **Feed** and **Terminal** pages. Page switching changes presentation only; the terminal process controller is not recreated.
- **Feed:** curated operational traffic from Codex and Claude, normally filtered to the currently selected exact session. Stable Libraries.dev BotAvatar identity is derived from `provider + native session ID + generation`. Approvals, denials, command/tool lifecycles, provider state changes, interruptions and terminal outcomes belong here; transcript text does not.
- **Terminal:** the existing `TerminalSessionController` now owns one persistent interactive PTY shell and one retained native SwiftTerm emulator. Chat/Terminal, Feed/Terminal and Tools mount that same emulator; none owns another shell. The native terminal handles keyboard input, ANSI, cursor, selection, scrolling and 2,000-line bounded scrollback. The old one-shot command runner and retained output String are replaced. This manual shell does not replace or bypass provider-managed commands/approvals.
- **Usage strip:** three equal-width paired categories, each Codex then Claude: 5-hour remaining, weekly remaining, and selected-session context used. Normal expanded geometry uses 48-point gauges and steps down to 40 points under width pressure; the strip owns the full row rather than sharing it with session/status chrome.

## Ownership

Provider/session truth remains in the existing ingestion/store path. Workspace presentation never creates a second provider state machine.

- Session identity: `provider + native session ID + generation`.
- Approval authority: exact provider request. UI says Approved/Denied only after Codex `serverRequest/resolved` or Claude `tool_result`; timeout, shutdown and transport failure cannot manufacture a decision.
- Feed history is bounded in memory and stores semantic summaries/IDs, not prompts, transcripts, filesystem paths or secrets.
- Chat/Terminal interaction intent and Feed/Terminal workspace selection are presentation state retained by AppDelegate across shell remounts.
- Terminal process lifetime is independent from visual page visibility.
- Record Activities remains a separate opt-in bounded persistence feature controlled from Settings > Agents; it no longer consumes permanent primary-toolbar space, and the Feed does not broaden it.

## Motion

The workspace uses the installed transitions.dev guidance:
- tab/content handoff: 250 ms, smooth-out cubic-bezier equivalent;
- internal width allocation: 300 ms, smooth-out;
- feed insertion: 8 pt + opacity;
- Reduce Motion removes spatial/decorative transitions.

The ThinkingOrb communicates *what* the selected agent is doing at the chat-header level. BorderBeam communicates that the selected chat surface is actively processing. BotAvatar carries the stable agent identity both beside assistant transcript responses and in the operational Feed; only the latest active response and current Feed activity animate continuously. These roles are intentionally separate.

## Rendering and performance

BorderBeam is adapted from the official MIT Libraries.dev SwiftUI port at revision `d06640864eb4adc2fe240f899a44ee6210779782`. The package's shader/spec tables are preserved. On macOS/SwiftPM the shader is runtime-compiled once per process through Metal because the local toolchain does not compile the upstream stitchable resource in this package configuration.

Beam and avatar/orb animation are presentation-local; they do not publish provider/domain state. Hidden right-workspace pages are retained for identity but marked inactive so visual animation can pause. Feed updates are isolated from transcript publication.

## Acceptance boundary

Automated/fixture evidence validates layout, provider isolation, exact approval ownership, usage grouping, gesture routing, Beam GPU execution, performance publication isolation, bounded lifecycle teardown and deterministic review states. It does not substitute for final human packaged pointer/motion/Reduce Motion inspection or quota-blocked live providers.

## Interaction cleanup: primary Chat and exact-session Feed

### Primary routing

`AgentWorkspaceProjection` is the shared view/test routing boundary. It uses the existing `AgentManagedSessionController` authority and capability checks; it neither creates a transport nor claims control from observed telemetry.

1. Keep an explicitly selected exact managed/composer-ready session.
2. Keep an explicitly selected provider-verified exact resumable candidate; show Resume through the existing controller path. A different managed chat does not override this deliberate selection.
3. If the current selection is unmanageable observation, prefer an available managed chat, then a legitimately resumable candidate.
4. With only non-attachable external observation or no session, present the existing `AgentSessionLauncherView` in its embedded New Chat configuration.

An explicitly selected owner with an authoritative pending or unconfirmed approval remains selected for operational Feed/attention, even when it cannot occupy managed Chat. Its primary surface still uses New Chat. Reconciliation and toolbar controls use the same provider/project projection as Chat, Feed and Context, preventing a managed session in another project from stealing the displayed selection.

The fallback reuses `AgentNewSessionFlow`, provider capabilities, repository/folder choices, model/agent options and explicit Start. It does not auto-start a provider process. The same form is used for Codex and Claude. Its static readiness glow does not imply agent execution.

The observed transcript/banner/footer is absent from the primary route. A legitimate resume handoff does not render a read-only observed transcript or unsupported model/reasoning chips. Backend discovery, normalized ingestion and truthful exact observation identity remain available for operational data. Session/project metadata does not replace `provider + native session ID + generation` identity.

### Selected-session Feed

`AgentWorkspaceFeedStore` remains one bounded normalized history, rather than adding an unbounded cache or subscription per selected session. `AgentWorkspaceFeedProjection` filters ordinary events and approval history by the complete selected instance. Nil selection renders no other session's traffic. Selecting another exact session changes the displayed projection; it does not move ownership of any event.

The Feed supplements the orb with meaningful recent reasoning/planning/search/connection/composition state and command/tool/interruption/completion outcomes. Consecutive equivalent activity is coalesced. Command/tool titles retain only recognized safe labels and exit status, never arbitrary command arguments, raw reasoning, prompt/transcript text, secrets or filesystem paths.

### Cross-session approval attention

The toolbar's `AgentWorkspaceApprovalAttentionControl` projects pending and unconfirmed requests from the existing `AgentApprovalController`. Another session's ordinary events and approval cards stay out of the selected Feed. The global attention affordance navigates to the exact owning provider/session/generation, adjusts the project filter when needed, and selects Feed before any decision is made. Failed/unconfirmed delivery remains discoverable.

Approval ownership and acknowledgement remain unchanged: decisions use the existing exact request, and Approved/Denied appears only after actual provider acknowledgement. The navigation control cannot resolve a request. Resolved approval history stays in the owning session's bounded Feed.

### Motion and input boundaries

The existing transitions.dev reversible selection handoff is reused for New Chat/launcher entry and transcript readiness: 250 ms smooth-out, with no spatial motion under Reduce Motion. No second shell or third persistent island state is introduced. Native composer Return/Shift-Return and deferred responder publication remain separate from terminal input ownership.

### Persistent terminal ownership

SwiftTerm **1.20.0**, revision `5d14406844143538cd8f8851d2d8a67c1fe443e5`, is the native AppKit terminal/emulation dependency ([upstream](https://github.com/migueldeicaza/SwiftTerm)). Its MIT notice ships in `ThirdPartyNotices`; SwiftPM pins the version. No web runtime is involved. The upstream package also resolves swift-argument-parser for its tooling; DynamicIsland links only the SwiftTerm product.

The user account shell is discovered with `getpwuid`, falling back to `/bin/zsh`. Initial cwd comes from the supplied selected project/session context; subsequent selection changes cannot change an already-running shell's cwd. Child-local startup files source normal shell configuration before setting a compact cwd prompt and memory-only history. They never edit global shell configuration. zsh was accepted live; bash/fish have native startup configuration but were not accepted live in this phase.

`NativeTerminalHost` separates view mounting from process lifetime, defers start/focus/publication outside AppKit layout, and coalesces resizing at 16 ms. SwiftTerm updates PTY rows/columns only when integer cell dimensions change. Retiring/hidden hosts cannot steal the emulator from the current visible owner. Explicit restart replaces the old shell/emulator; normal navigation preserves PID, cwd, environment and scrollback. Launch generations reject stale exit/output callbacks. Owned cleanup bags release observers and shell resources without actor-isolated AppKit deinitializers on the macOS 15 back-deployment runtime.

SwiftTerm owns the only scrollback buffer; text export and accessibility viewport text are computed on demand. PTY output does not publish an ObservableObject change per byte. Programmatic OSC 52 clipboard reads/writes are denied; explicit native keyboard copy/paste stays available. Shell output never enters the Agent Feed automatically.

### Evidence: October 4 cleanup

- **PASS — automated/fixture:** both-provider observed-only fallback, exact managed/resume routing, project selection, approval attention retention, exact Feed ownership/coalescing/privacy/bounds and native focus/tab teardown. Focused set: **62 passed / 0 failed / 1 skipped**. Full suite: **1,657 passed / 0 failed / 38 skipped** (1,695 total).
- **PASS — automated/fixture:** nine integration tests use real local PTYs to cover persistent shell/cwd/environment, native keys, history/completion/interrupt, ANSI, pager, resize, bounded output, remount, restart and child teardown. **PASS — live:** packaged terminal acceptance independently confirms the principal interaction paths, including Feed/Terminal and main-tab switches with the same PID; 40 packaged tab cycles completed without a crash.
- **PASS — live:** packaged managed Codex creation, native Return submission, reasoning/connection/command/composition/completion Feed, interruption and subsequent usable interaction. Real provider deny/allow acknowledgement passed through the existing controller acceptance harness; this does not claim a fresh manual packaged approval-card flow.
- **PASS — automated/fixture:** performance harness preserves 200 deltas → six surrounding Agents/Feed evaluations and two managed-controller publications; 38 typed keys → three console evaluations. The bounded 110-cycle fixture released its controller after teardown.
- **BLOCKED — external acceptance dependency:** Claude execution/concurrent providers and consent-dependent microphone/human speech remain separate external gates. **NOT VERIFIED:** fresh actual OS Reduce Motion toggle, detailed uninterrupted motion/GPU pacing and whole-app memory closure. See `agent-presence-validation.md` for measurements and live workload boundaries.
