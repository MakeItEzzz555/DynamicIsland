# Agent Activity Integration Architecture

- Status: Phase A0 architecture decision record; no production implementation
- Date: 2026-09-24
- Companion documents: [capability matrix](AGENT_CAPABILITY_MATRIX_2026-09-24.md), [event schema](AGENT_EVENT_SCHEMA_DRAFT_2026-09-24.md), [reference review](AGENTNOTCH_REFERENCE_REVIEW_2026-09-24.md), [phase plan](AGENT_FEATURE_PHASE_PLAN_2026-09-24.md)

## 1. Decision summary

DynamicIsland will integrate agent activity through provider adapters that emit a privacy-reduced, versioned normalized event model. An `AgentEventStore` will be the only reducer/state owner. An `AgentAttentionCoordinator` will derive transient presentation from store output. Provider adapters, bridge code, and filesystem/process observers will never manipulate SwiftUI directly.

The preferred ingestion order is event-specific, not a single global ranking:

1. official lifecycle/action stream or hook for the event it owns;
2. official structured telemetry for observations it defines authoritatively;
3. official client protocol/structured CLI stream;
4. local structured transcript as a version-pinned compatibility adapter;
5. verified process/editor metadata for source enrichment;
6. bounded heuristic fallback, which may degrade to `unknown`/`idle` but cannot override stronger evidence.

Codex App Server is the richest official live protocol for sessions connected through it; Codex hooks and OTel cover independent supported clients after guided opt-in. Claude HTTP hooks are the primary lifecycle feed because the official hook lifecycle spans terminal, IDE, Desktop, and cloud execution contexts, while Claude OTel enriches usage/tool facts. Local transcripts remain fallback because Anthropic explicitly calls their format internal and version-variable.

## 2. Existing DynamicIsland invariants

Current source and the project history establish these non-negotiable boundaries:

1. One stable `IslandOverlayPanel`/`NSPanel` remains the only host. Agent UI does not create another panel, popover, or window.
2. `IslandStateStore` remains exactly `.collapsed` and `.expanded`.
3. Agent attention is transient metadata layered onto collapsed rendering, never a third global island state.
4. `IslandLayoutStore` and `NotchGeometryService` remain the native-to-SwiftUI geometry path. Agent peek dimensions enter this path as a collapsed presentation profile; views do not independently query screens.
5. `OverlayWindowController` keeps window-level `ignoresMouseEvents` plus hosting hit-test protection. Interactive regions must track the currently visible shell, including a transient wider shell, without making the transparent canvas clickable.
6. Existing expansion/collapse, media/artwork, timer, Live Activity, Clipboard, File Shelf, Stats, and gestures remain independent. Agent state cannot drive or reset those controllers.
7. Every delayed attention/glow/retract callback is generation-owned. Older callbacks cannot mutate a newer event, a newly expanded island, or a disabled overlay.

Patterns to reuse:

- `OverlayPresentationSession` and artwork/clipboard generation checks for stale-callback rejection;
- the single authoritative shell/content timeline in `IslandRootView`;
- `IslandModules`/`AppDelegate` single-instance ownership rather than view-created stores;
- `TimerCompletionNotificationCoordinator`'s injectable boundary and native sound policy as a testing pattern, not as agent-notification infrastructure;
- `AppLaunchService`'s bundle-ID-first activation pattern, extended only after verified source association exists;
- capability snapshots such as `LiveActivitySettingsSnapshot` for coherent multi-setting reactions.

## 3. Component boundaries

```text
provider hook / App Server / OTel / transcript watcher
                    │
                    ▼
              AgentAdapter(s)
       validate, correlate, normalize
                    │ AgentEvent
                    ▼
              AgentEventStore
       identity, ordering, reducer, history
            │                   │
            ▼                   ▼
 AgentAttentionCoordinator   Expanded agent modules
 policy + generations        read-only projections
            │
            ▼
 collapsed transient presentation
```

### Adapter contract

Each `AgentAdapter` provides:

- `provider`
- `capabilities` with provenance and scope
- `start()` / `stop()` with idempotent lifecycle and complete watcher/task teardown
- `ingest(_:)` for bounded raw records
- `normalize(_:)` producing zero or more `AgentEvent` values
- `health` including configuration, source version, last successful event, drops, and schema mismatch
- `configurationStatus` without editing configuration

Adapters have no reference to `IslandStateStore`, `IslandLayoutStore`, views, audio, or AppKit windows. The event store is the sole state reducer. The attention coordinator consumes committed store changes and is the sole owner of peek/glow/sound/retract policy.

### State ownership

- `AgentEventStore`: session identity, generation, operation correlation, ordering, deduplication, bounded history, capabilities, and projections.
- `AgentAttentionCoordinator`: significant-event classification, coalescing, attention generation, sound throttle, persistent badge obligations, monotonic retract deadline.
- `AgentBridge`: authenticated local transport and ingress limits; no provider semantics and no arbitrary execution.
- provider adapters: raw-source parsing and provider-specific correlation only.
- SwiftUI: renders immutable projections and emits user intent. It never parses raw events.

Mutable production owners should be main-actor-isolated only where UI publication requires it. Parsing, JSON decoding, and file tailing occur off the main actor; a small validated normalized event crosses to the store.

## 4. Per-event authority

| Normalized event | Authoritative source | Enrichment | Fallback | Correlation and deduplication |
|---|---|---|---|---|
| `sessionStarted` / `sessionResumed` | Provider hook or connected official protocol | OTel session metadata | transcript session header; bounded process observation | provider native session ID + lifecycle source/producer epoch |
| `sessionEnded` | explicit hook/protocol end | process disappearance only as health | bounded inactivity marks disconnected, never completed | session generation + end event ID |
| `agentWorking` / `thinking` | protocol item/turn state when explicit | OTel API/interaction activity | recent structured transcript append | prompt/turn ID; latest stronger state wins |
| `planning` / `planReady` | explicit plan item/hook/task state | none | transcript plan item only when version-mapped | plan/turn correlation; final structured plan wins |
| `toolStarted` / `toolCompleted` | pre/post hook or protocol item lifecycle | OTel result/duration | transcript tool use/result | provider tool-use/item ID; start/completion pair idempotent |
| `commandStarted` / `commandCompleted` | command item lifecycle or shell hooks | OTel result/duration | transcript command record | command/tool-use ID; never command text alone |
| `approvalRequested` / `approvalResolved` | permission hook/protocol request and resolution | OTel decision | transcript only if stable for pinned version | request/item/tool-use ID + generation; exactly one resolution |
| `waitingForUser` | official user-input request/elicitation | none | explicit structured transcript marker | request ID + generation |
| `taskCompleted` / `taskFailed` / `interrupted` | explicit turn/task completion status | OTel terminal API failure | transcript terminal record | turn/task ID; timeout cannot synthesize success |
| `subagentStarted` / `subagentEnded` | subagent hooks/protocol child items | OTel agent IDs | version-pinned transcript | child agent ID + parent session/generation |
| `usageUpdated` | official protocol or OTel counters | transcript token record | none | metric scope + provider sample identity; monotonic where documented |

When hooks and telemetry report the same operation, the correlation ID collapses them into one lifecycle. Hook/protocol state owns lifecycle; telemetry may enrich duration/usage but cannot reopen, re-complete, or downgrade it. A heuristic timeout can mark source health stale and display `unknown`; it cannot declare task success or resolve an approval.

## 5. Local bridge decision

### Selected architecture

A2 should implement a small HTTP/1.1 service bound only to an ephemeral loopback address, with a protected discovery record and per-install authentication. This is selected over XPC because external provider hooks and cross-language tooling can POST HTTP without a signed helper; over a Unix-domain socket because Claude has a first-class HTTP-hook surface and provider OTLP commonly targets HTTP; and over a fixed OTLP port because port 4318 may already be occupied.

The service binds `127.0.0.1` and, only if equivalently constrained/tested, `::1`; never `0.0.0.0`. The OS chooses an available high port. DynamicIsland atomically writes a mode-0600 discovery record under its Application Support directory containing protocol version, port, process instance ID, and no reusable secret. The long-lived 256-bit per-install secret belongs in Keychain. Hook setup receives a narrowly scoped credential reference or short-lived token; exact distribution is an A2 security decision and must not place plaintext credentials in the repository.

Requests carry protocol version, timestamp, nonce, body digest, and HMAC (or a short-lived bearer token minted from the install secret). The bridge rejects replayed nonces, excessive clock skew, wrong content type, oversized bodies, invalid schemas, slow clients, and authentication failure before parsing provider payload. Authentication failures are rate-limited and never echo secrets.

Endpoints are narrowly allowlisted (`/v1/events`, `/v1/health` and, later, a distinct action response path). There is no shell, file-read, path traversal, URL fetch, or generic RPC endpoint. Maximums are defined in the schema draft. Concurrency is bounded; overload returns 429 and does not block UI. Shutdown stops accepting, drains only bounded in-flight validation, cancels tasks, removes the discovery record if it still belongs to this process, and leaves provider sessions unaffected.

### OTLP

A2 may expose a separate authenticated OTLP/HTTP-compatible ingress only after fixtures prove exact bounded decoding. It should not impersonate a global collector at fixed port 4318. Provider OTLP and lifecycle hooks can coexist: OTLP enriches, hooks own lifecycle.

### Alternatives

- Unix-domain socket: excellent local security and collision behavior, but not directly supported by standard HTTP hooks/OTLP exporters; retain as a future internal transport.
- XPC: strong macOS identity but unsuitable as the only interface for arbitrary CLI hook processes without a helper and signing lifecycle.
- fixed localhost port: rejected due to collisions, cross-user exposure risk, and accidental attachment to another service.

## 6. Privacy and security boundaries

Defaults retain no full prompt, source code, tool output, shell output, environment, raw transcript line, or provider/account token. Command/tool data is reduced before entering the store. No event leaves the Mac. Logs contain IDs, event kinds, sizes, and error categories only.

The bridge authenticates the producer, but an authenticated provider payload remains untrusted. Adapters enforce schema/version/size limits and strip content. Config setup in A11 is detect → diff → user confirmation → backup where appropriate → minimal patch → verification → rollback. It never overwrites whole Codex or Claude config files and never silently enables content-rich telemetry.

Approval control is disabled by default. A9 may enable it only when the provider exposes a documented action channel bound to the exact request/session/generation. No terminal keystrokes, accessibility clicks, or inferred button coordinates are permitted. Failures and uncertainty default to observation-only, never approval.

## 7. Attention presentation contract

Conceptual values:

- `AgentAttentionPresentation`: event summary, session instance, priority, style, created time, retract deadline, persistent badge obligation.
- `AgentAttentionPriority`: `quiet`, `informational`, `success`, `actionRequired`, `failure`.
- `AgentAttentionGeneration`: monotonic coordinator-owned token.
- `AgentAttentionSoundPolicy`: `none`, `oncePerEvent`, with global/session throttles and user setting.
- `AgentAttentionGlowPolicy`: semantic provider/event accent, bloom/fade timing, Reduce Motion behavior.

Flow:

```text
collapsed shell
→ significant committed event
→ attention generation N widens the existing collapsed shell
→ content and subtle lower-contour glow appear
→ optional native restrained ding once
→ glow decays
→ ContinuousClock deadline around five seconds
→ if N still owns presentation, retract to normal collapsed geometry
```

Clicking a transient presentation calls the existing normal expansion path and yields `.expanded`; the attention presentation is dismissed without creating a new island state. Expansion, overlay disablement, or a newer event invalidates the old retract task. Sleep/wake uses a monotonic deadline: a wake after expiry retracts immediately. The visible shell frame must update the existing layout/hit-test path throughout the morph.

Preliminary policy:

| Event | Peek | Sound | Persistent compact obligation |
|---|---:|---:|---:|
| ordinary working/thinking/tool/command | no; quiet compact status | no | no |
| plan ready | yes, ~5 s | once | optional unread dot until viewed |
| completed/tests passed | yes, success | once | no after peek unless unread policy later requires it |
| approval required | yes, attention | once | badge until correlated resolution |
| user input required | yes, attention | once | badge until correlated resolution |
| failure/tests failed | yes, error | once | indicator until viewed/resolved/new run |
| interrupted | coalesce informationally | normally no | only if user action remains |

Coalesce same-session events within 750 ms by priority; keep the highest priority and newest safe summary. Across sessions, queue at most three significant items and then present an aggregate (`3 agents need attention`). Sound is globally throttled to one per 1.5 seconds and once per stable attention event ID. Tool churn never sounds. Ten simultaneous completions become one aggregate peek/sound, while per-session history remains intact.

## 8. Expanded Agent Activity contract

A7 adds one module composed of small cards, not a monolithic view:

- session summary/list supporting one, many, and mixed providers;
- identity card: provider, verified source, project, model, state, elapsed time;
- current activity card: privacy-safe command/tool and pending approval;
- usage card shown only for supported metrics;
- recent activity list from bounded normalized history;
- completion/failure summary.

Optional UI is capability-gated. No quota is shown without `quotaUsage`. No Approve/Deny appears without `approvalControl`. `Open Source App` appears only with `verifiedSourceIdentity` and `sourceAppOpen`. Unsupported values are omitted, not displayed as zero.

## 9. Source association and Open action

Verified association can come from provider entrypoint metadata, official IDE/app protocol metadata, a provider hook field, or a process tree tied to the authenticated session producer. The currently foreground application is enrichment only and never verified identity.

Opening uses bundle identifiers and `NSWorkspace`, following `AppLaunchService`: Terminal/iTerm, VS Code/Cursor, a verified JetBrains product, Codex app, or Claude app can be activated only when its bundle ID was verified for that session. When a workspace URL/path is supported by the app's documented URL scheme or `NSWorkspace` open configuration, use it; otherwise focus the verified app without claiming a precise session/window. Guess-based action buttons are forbidden.

## 10. Performance budgets

Initial A11 acceptance budgets, measured with 10 active sessions and synthetic bursts:

- idle CPU attributable to integration below 0.5% averaged over five minutes on a representative Apple-silicon Mac;
- no polling faster than 2 seconds, and no polling when an event-driven source is healthy; filesystem fallback scans no more than once per 10 seconds and only provider session directories;
- tail only appended bytes; initial catch-up capped at 1 MiB or 2,000 lines per session, then require explicit replay/import;
- bridge body 1 MiB, event 64 KiB, batch 100, at most 16 in-flight requests, bounded queues with observable drops;
- parsing/normalization off main actor; main-actor reducer batches no more than 50 events per run-loop turn;
- memory limits from the schema draft; no raw payload retention;
- glow animates only while visible, stops completely when idle/backgrounded, and respects Reduce Motion;
- watcher descriptors/tasks return to baseline after adapter stop, sleep/wake, config change, and provider uninstall.

### Settings and setup contract

A11 may add one **AI Agents** settings area, composed from runtime capabilities rather than provider assumptions:

- master Agent activity on/off;
- Codex status and setup health;
- Claude status and setup health;
- completion alerts, approval alerts, sounds, and usage metrics toggles;
- transient peek duration, defaulting to approximately five seconds.

These controls are not created before A11. Turning the master switch off must stop adapters, watchers, bridge ingress, attention tasks and animation work without changing provider configuration. Provider setup follows detect → show exact diff → obtain confirmation → back up where appropriate → minimally patch → verify → offer rollback. Existing comments, unrelated keys, formatting and externally managed policy must be preserved. A provider configuration changed outside DynamicIsland is re-detected and never overwritten automatically.

## 11. Failure model

| Failure | Safe degradation |
|---|---|
| provider not installed or hook missing | integration reports unavailable/setup needed; rest of app unchanged |
| provider schema changes | adapter quarantines unknown version, records bounded health error, retains last known session without fabricating updates |
| malformed/truncated JSONL | retain incomplete trailing bytes until append; cap buffer; quarantine invalid complete line and continue at next boundary |
| bridge unavailable/auth failure/collision | provider continues normally; hook failure is non-destructive; DynamicIsland shows degraded health only |
| config changed externally | detect via file coordination/watch; stop relying on removed configuration; never rewrite automatically |
| session/IDE/process disappears | mark source disconnected after bounded reconciliation; never synthesize successful completion |
| sleep/wake | revalidate deadlines, file identities, offsets, producer epochs, and pending attention; catch up boundedly |
| duplicate/out-of-order event | deterministic dedup/reorder rules; correlation and authority prevent state regression |
| session ID reuse | generation and immutable metadata conflict handling isolate the new incarnation |
| provider/agent crash | fail/disconnect only when authoritative; otherwise health becomes stale/unknown |
| DynamicIsland restart | new bridge process epoch, bounded catch-up from structured sources, no acceptance of old authenticated callbacks; no persisted sensitive history in initial phases |
| flood | per-provider fair queues, limits, aggregation, drops with health counters; one provider cannot starve the other or UI |
| capability misreport | require provenance and runtime validation; disable dependent UI/action on contradiction |

Starting after a session began is handled by App Server/thread listing where supported or bounded transcript/OTel catch-up; absent proof, show discovered active session with partial history, not a fictional start time. Restart mid-session follows the same rule.

## 12. Adversarial conclusions and deferred risks

- Missing hooks are expected, not fatal; fallback sources are clearly weaker.
- Telemetry duplicates hooks by design; operation IDs deduplicate and lifecycle authority remains with hooks/protocol.
- Old sessions cannot overwrite new sessions because every mutation carries generation and producer ownership.
- An approval expiring while visible invalidates both the persistent badge action and any future control; the peek may remain informational until retract.
- Simultaneous sessions/providers are first-class store entries, never merged by repository.
- Port 4318 is not assumed available; the bridge chooses an ephemeral loopback port.
- AgentNotch licensing remains a hard boundary for copying; only independently described concepts are used.

Genuinely deferred: exact provider support for attaching App Server to independently launched Codex clients; stable source identity for every Codex/Claude Desktop or JetBrains session; official quota APIs usable by a third-party local app; and safe action-control availability per source. These do not block A1 because A1 implements provider-independent reduction and replay only.
