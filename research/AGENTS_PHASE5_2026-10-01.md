# Phase 5 — Camera lifecycle, Agents performance, usage UX, Record Activities, approval authority

Branch `feature/agents-ui-overhaul-continuation`, started at `5e9bb6e`.

## 1. Camera Mirror self-reactivation

**Root cause.** The "mirror closed" decision lived only in
`ProductivityDeckView`'s `@State isMirrorPresented` (default `true`), and
Close Mirror / Settings Close / Live Activity stop / disable all funnelled into
the same passive `lease.release()` used by `onDisappear`. Any remount (island
collapse→expand, deck rebuild) reset the state to `true`, the mirror's `.task`
called `attachPreviewConsumer()`, and capture restarted with no user action.
A deactivation that left the mirror mounted also restarted on the next page
re-activation (`onChange(isWorkspacePageActive)`).

Droppy comparison: `CameraManager.previewDidAppear()` is gated by a *persisted*
`isEnabled` preference, so a remount cannot revive a disabled camera. DynamicIsland
had no equivalent persisted intent.

**Fix.** `CameraPreviewController.userIntent` (`undecided / wantsPreview /
closed / interrupted`) changes only on explicit actions. Passive attach may
start capture only while intent allows it (and may still join an
already-running authorized session). Mirror presentation is derived from the
controller. Close records intent synchronously before any await; Settings
preview disappearance releases only its own ownership; unexpected system
stops require explicit Retry; `selectDevice`, `stopCapture` and the
unexpected-stop teardown are generation-safe.

**Evidence.** 13 new regression tests (remount / tab switch / collapse-expand
after close, 50 cycles, close racing in-flight start, consumer + explicit
owner, unexpected stop, device switch racing close, termination, Settings
disable/re-enable) and an opt-in real-camera test: after an explicit close,
10 release/remount cycles over 3 s never restarted the FaceTime HD camera.

## 2. Managed approvals

**Root causes (real-provider evidence).**
1. Managed requests had a 75 s wall-clock expiry. On expiry the controller
   wrote a *Deny the user never chose*, the row disappeared, and a later click
   returned `.missing`. Real Claude CLI, pre-fix code, decision after 90 s:
   file not created (`contents=missing`). Same test post-fix: `late-check`,
   state `approved`.
2. "Approved/Denied" was inferred from *any* later event in the same turn, not
   from the provider.
3. Approval rows resolved via the displayed `session.id`, not the row's key.

**Authoritative acknowledgement.** New provider event
`approvalAcknowledged(nativeSessionID, requestToken)`:
- Codex app-server: `serverRequest/resolved { threadId, requestId }`
  (present in the v2 schema generated from codex-cli 0.159.0).
- Claude Code: the `tool_result` whose `tool_use_id` equals the
  `control_request.request.tool_use_id` that was answered (verified live:
  allow → tool ran; deny → `is_error: true`, "Denied in DynamicIsland").

**State machine.** `awaitingDecision → submitting → (acknowledged → store
Approved/Denied) | failed(decision, reason)`. Failure causes: write error,
turn end, provider failure, transport close before acknowledgement. Failed
rows stay visible with Dismiss; store state `.unknown` ("Decision not
confirmed"). Provider responses are single-use (JSON-RPC id, control_response),
so a failed delivery is never re-sent. A provider acknowledgement that arrives
before the user decides withdraws the request with no wire reply. Shutdown or
cancellation never writes a decision. A decision clicked after its turn ended
is not written.

**Identity.** Unchanged and re-tested: provider + native session + generation
+ active turn + exact request (turn-bound correlation when a native id is
reused after reconnect). Observed/external sessions remain observation-only.

**Validation.** Controller fakes (allow, deny, transport failure, turn end
during submission, provider withdrawal, duplicate request, reused id after
reconnect, stale row, session switch, shutdown, auto-approval, manual);
a protocol-accurate fake Codex app-server process through the production
client/provider/controller (wire log `turn-1:accept`, `turn-2:decline`,
duplicate answered once, stale reused-id button refused); real Claude CLI
deny/allow/late-allow (`AgentLiveApprovalEndToEndTests`).
Real Codex smoke was attempted (`scratchpad codex_smoke.py`, approvalPolicy
`untrusted`): the app-server transport and turn lifecycle worked but the
account returned "You've hit your usage limit … try again at Oct 3rd, 2026
8:37 PM", so no real Codex approval request could be produced.

## 3. Agents performance

**Method.** DEBUG-only `AgentPerformanceProbe` (os_signpost category
`AgentsPerformance` + counters) and the opt-in `AgentsPerformanceHarnessTests`
(`DYNAMIC_ISLAND_AGENT_PERF=1`), which hosts the production
`AgentActivityDashboardView` in a real window with 36 sessions (Codex +
Claude) and an 80-entry transcript, driven by the production controller and
fake providers emitting real provider events. Numbers are main-thread CPU,
median of 5 runs, DEBUG build, identical harness on baseline (`bb35af1` +
instrumentation only) and final code.

| Scenario | Before | After |
|---|---|---|
| Enter Agents (mount → transcript visible) | 434 ms | 397 ms |
| 200 streamed deltas, paced ~200/s | 5070 ms | 550 ms (9.2×) |
| Typing 38 keystrokes | 225 ms | 139 ms |
| Session switch ×11 | 395 ms | 380 ms |
| Provider switch ×10 | 1093 ms | 948 ms |
| Snapshot refresh ×10 (runs every 8 s) | 956 ms | 730 ms |

Counters during streaming (before → after): dashboard/content/control-bar
bodies 279 → 6, provider buttons 408 → 6, console 478 → 103, controller
publications 209 → 2, event-store publications 74 → 2, auto-scroll passes
202 → 47. Typing: console renders 40 → 3. Enter: chrome visible at ~500 ms and
transcript ~80 ms later are the designed shell-motion delays, unchanged.

**Hotspots removed.**
- Transcripts were a `@Published` dictionary on the controller every chrome
  view observes → `AgentTranscriptStore` + per-session `AgentTranscriptFeed`
  observed only by the console; publication coalesced (leading edge, ≤30 Hz,
  lossless).
- Every 8 s discovery refresh re-emitted unchanged metadata for each session →
  emitted only on change or newer provider activity; change-only `@Published`
  writes in snapshot/selection/error paths.
- Per-delta auto-scroll tasks → one settle in flight (plus one trailing).
- Composer draft state re-rendered the transcript on each keystroke →
  `AgentConsoleComposer` owns the draft.
- History hydration ran on every mount → only once the transcript may show.
- Equatable transcript rows.

**Rejected after measurement.** A 24-row visible window (slower with a lazy
stack and destabilized layout against the bottom anchor: harness hangs), an
eager `VStack` (12–17 s per 200 deltas), removing `defaultScrollAnchor`
(not pinned; 11 s per 200 deltas). A sub-pixel feedback edge between the
bottom-position preference and follow state could livelock lazy layout; follow
state is now written only on real change with whole-point positions
(0/20 hangs in the final harness).

## 4. Usage and provider controls

5h and Week gauges 34 → 44 pt (36 pt below 520 pt width); Context 34/30 pt.
Rings inset by half the stroke (no clipping), values/icons scale. Codex/Claude
buttons show `[icon] Name` (26 pt hit height, 74 pt minimum width); only the
buttons themselves fall back to icon-only under genuine width pressure.

## 5. Record Activities

Explicit opt-in (`agentActivityRecordingEnabled`, default off). Control: Record
button in the Agents control bar (red filled record symbol and "Recording"
when on; right-click: Reveal / Clear Recorded Activity) and a Settings toggle.

- **Source:** `AgentEventStore.appliedEventObserver` — every applied normalized
  event from every producer; no parallel event stream.
- **Record fields:** time, provider, native session id + generation, event
  type, resulting state, source, opaque correlation id, leading tool /
  executable identifier, success / exit code, approval state, project folder
  name, model, numeric usage samples.
- **Never written:** prompts, transcripts, agent messages, plan / summary /
  terminal text, command arguments, paths, environment, tokens. Name fields
  are cut to their leading identifier (`Bash(rm -rf …)` → `Bash`).
- **Storage:** `~/Library/Application Support/DynamicIsland/AgentActivity/
  activity-YYYY-MM-DD.N.jsonl`, directory 0700, files 0600, local only.
- **Retention:** files roll at 2 MB; pruned to 14 days and 20 MB total.
- **Cost:** batched writes on a utility queue, synchronous flush at quit; a
  200-event burst costs ~848 ms main-thread CPU off vs ~876 ms on.
