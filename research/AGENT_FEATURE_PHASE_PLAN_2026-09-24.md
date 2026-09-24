# Agent Activity Feature Phase Plan

- Status: dependency-gated implementation plan
- Date: 2026-09-24
- Architecture: [AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md](AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md)
- Contracts: [AGENT_EVENT_SCHEMA_DRAFT_2026-09-24.md](AGENT_EVENT_SCHEMA_DRAFT_2026-09-24.md)
- Provider evidence: [AGENT_CAPABILITY_MATRIX_2026-09-24.md](AGENT_CAPABILITY_MATRIX_2026-09-24.md)

## 1. Rules for every implementation phase

Every phase A1–A11 starts from the committed, pushed, clean exit of its dependency and builds only its declared layer. It must include focused deterministic tests and adversarial cases, then run the full suite, debug build, release build, packaging and codesign. It performs applicable honest manual validation, updates Graphify when production architecture changed, reviews every changed line, reports before progressing, commits, pushes, verifies local/upstream/remote equality, and ends clean.

No phase may fabricate provider data, silently edit user configuration, weaken the single-panel/two-state island architecture, or use an unsupported approval/action mechanism. If a provider/version cannot meet an exit gate, that adapter remains capability-reduced or observation-only; the phase does not paper over the gap with heuristics.

## 2. Dependency map

```text
A0 research/contracts
        │
        ▼
A1 normalized model + reducer + replay
        │
        ▼
A2 authenticated bridge
        │
        ├─────────────┐
        ▼             ▼
A3 Codex adapter   A4 Claude adapter
        └──────┬──────┘
               ▼
       A5 attention coordinator
               ▼
       A6 transient shell UI
               ▼
       A7 expanded activity UI
               ▼
       A8 usage/capability UI
               ▼
       A9 safe actions (optional per provider)
               ▼
       A10 source association/open
               ▼
       A11 setup, migration, hardening
```

A3 and A4 can be developed in either order after A2, but A5 requires at least one validated real adapter and replay coverage for both provider vocabularies. A9 does not block observation/UI delivery; unsupported providers remain read-only.

## 3. Phase gates

### A0 — Research and architecture

Entrance: clean `feature/agent-activity` at frozen checkpoint `239291a17c70b0d76864a6fbcb79240dd44c7fd2`.

Deliverables: the five dated research/design documents; pinned AgentNotch audit and license result; current provider matrix; authority, identity, event, privacy, bridge, presentation and failure contracts; replay fixtures specification; A1–A11 gates.

Exit: docs cross-reference without contradiction; no production/test/Graphify changes; baseline 344 tests and builds remain green; no blocker to normalized replay-only A1; committed and pushed clean.

### A1 — Normalized domain, `AgentEventStore`, replay harness

Entrance: A0 contracts committed; open issues are provider-specific and do not change core identity or envelope semantics.

Scope: implement value types, state reducer, generation ownership, event authority metadata, deduplication/reordering, capability provenance, bounded memory, privacy projection and deterministic replay clock/harness. Add only sanitized normalized fixtures listed in the schema draft. No bridge, provider file reads, process scans, settings or UI.

Adversarial tests: duplicate/conflicting IDs, out-of-order pairs, stale generations, native-ID collision, simultaneous same-repo and mixed-provider sessions, malformed/unknown versions, flood/eviction, capability downgrade, restart/replay determinism and approval expiry.

Exit: every fixture produces exact snapshots and attention candidates; no full sensitive content crosses the normalization boundary; limits are enforced; full validation and Graphify pass; commit/push clean.

### A2 — Authenticated local Agent Bridge

Entrance: A1 envelope decoder/reducer and replay tests stable.

Scope: loopback-only ephemeral HTTP listener, protected discovery, per-install Keychain secret/token design, authentication/replay defense, strict endpoints/limits/timeouts, bounded concurrency, decode-before-ack, health and deterministic shutdown. Test double must avoid real network where possible; loopback integration tests are allowed. No provider adapter or UI.

Adversarial tests: wrong/missing auth, replay nonce, clock skew, oversized/chunked/compressed payload, slow client, malformed batch, concurrency/fairness, port collision, stale discovery, crash/restart epoch and shutdown with active handlers.

Exit: packet/socket inspection proves loopback-only; no arbitrary execution/file access; provider failure cannot affect other app features; full validation, security review, Graphify, commit/push clean.

### A3 — Codex adapter

Entrance: A2 authenticated ingestion stable; supported minimum Codex version and surface matrix frozen for this phase.

Scope: official App Server/structured stream and hook/OTel mappings as supported; bounded recovery from local state only where necessary. Correlate thread/turn/item/tool/approval/plan/subagent/usage IDs. Detect configuration but do not modify it. No UI.

Adversarial tests: independent CLI/IDE sessions, resume/fork, two threads same repo, App Server disconnect/reconnect, hook+OTel duplicates, out-of-order item completion, stale SQLite/rollout data, partial line/rotation, schema drift, hosted-tool gap, quota absence and version mismatch.

Exit: replayed raw Codex fixtures normalize deterministically; completion/interruption/approval semantics match official evidence; unsupported sources advertise reduced capabilities; CPU/watchers bounded; full validation, Graphify, commit/push clean.

### A4 — Claude adapter

Entrance: A2 stable; minimum Claude versions mapped for base and newer hook events.

Scope: HTTP hooks as lifecycle authority, stream-json/Agent SDK mapping for launched sessions, OTel enrichment, and version-pinned bounded transcript recovery. Correlate session/prompt/tool/agent/task IDs. Detect setup only; no config writes or UI.

Adversarial tests: local-version skew, hook+OTel duplicate, CLI/VS Code/Desktop source differences, resume with sequence reset, partial/truncated/rotated JSONL, permission vs slow tool, subagent/task lifecycle, interruption uncertainty, cloud hook reachability loss and config change.

Exit: raw Claude fixtures normalize deterministically with declared capability reductions; no timeout becomes permission/success; no transcript content retained; teardown and sleep/wake verified; full validation, Graphify, commit/push clean.

### A5 — Agent Attention Coordinator

Entrance: A1 store and at least one real adapter validated; both provider normalized fixture families available.

Scope: pure coordinator/reducer for attention priority, persistent obligations, per-session/global coalescing, sound policy, `ContinuousClock` retract deadlines, generation invalidation, aggregate overflow and expand/disable lifecycle. No shell rendering or sound playback.

Adversarial tests: newer event invalidates old deadline, expansion during peek, sleep beyond deadline, ten simultaneous completions, provider flood fairness, approval resolved while visible, stale/duplicate completion and settings disable.

Exit: deterministic no-sleep tests prove exactly-once sound intent and stale callback rejection; ordinary tools never ding; full validation, Graphify, commit/push clean.

### A6 — Transient peek, glow and ding

Entrance: A5 presentation snapshots/timing stable.

Scope: inject attention into the existing single root/panel; collapsed width-first morph, minimal height change, lower contour bloom/fade, native restrained sound, existing expansion click path, geometry/hit-test updates and Reduce Motion. No expanded agent module.

Adversarial tests: state remains only collapsed/expanded, click-through outside current shell, rapid replacement/retract, overlay disable, expand/collapse, no duplicate sound, no idle animation, notch/non-notch/multiple-display geometry.

Exit: automated geometry/presentation tests plus manual panel, click-through, sound, display and sleep/wake checks; unrelated modules behave identically; full validation, Graphify, commit/push clean.

### A7 — Expanded Agent Activity UI

Entrance: A6 integrates attention without destabilizing shell lifecycle.

Scope: capability-neutral module/cards for session list, mixed providers, project/source/model/state, activity, operation, elapsed time, pending attention and bounded history. Clicking peek expands to this normal module path through existing navigation rules. No usage/quota controls or approval buttons.

Adversarial tests: zero/one/many sessions, same project, mixed providers, selection replacement, session disappearance, long redacted text, unavailable fields, accessibility, narrow layouts and no monolithic state ownership.

Exit: replay harness drives every UI state deterministically; no raw provider model in SwiftUI; manual keyboard/VoiceOver/layout validation; full validation, Graphify, commit/push clean.

### A8 — Usage, context and quota presentation

Entrance: A7 card boundaries and runtime capability provenance stable.

Scope: optional usage cards with unit/scope/source/freshness. No hard-coded context limits or prices. Missing/unknown/stale metrics are hidden or explicitly unavailable, never zero.

Adversarial tests: partial metrics, reset/decrease, model switch, resumed session, stale sample, quota unavailable, conflicting sources, overflow and capability withdrawal.

Exit: every visible metric traces to authoritative evidence; unsupported providers show no fabricated UI; full validation, Graphify, commit/push clean.

### A9 — Safe approval/action broker

Entrance: exact supported provider/source/version action APIs documented and testable; security review approves threat model. If none qualifies, record observation-only result and do not implement fake controls.

Scope: separate authenticated action envelope, request/session/generation binding, nonce/expiry, exactly-once decision, disconnect handling and provider-specific brokers. UI controls appear only under `approvalControl`.

Adversarial tests: double click, stale/expired/wrong-session request, provider replacement/disconnect, replay, reordered resolution, timeout, malicious payload and default-deny/observation-only behavior.

Exit: no keystroke/mouse injection; Session A cannot affect B; unsupported surfaces remain read-only; focused penetration review, full validation, Graphify, commit/push clean.

### A10 — Source app/editor association and Open action

Entrance: sessions carry source evidence/provenance and app actions remain independent of approval control.

Scope: verified bundle/process/workspace association for supported Terminal, iTerm, VS Code, Cursor, JetBrains, Codex and Claude surfaces; extend bundle-ID-first `AppLaunchService` only as needed. Exact window/session open only with documented mechanism.

Adversarial tests: two windows same app/repo, PID reuse, app restart, unknown foreground app, missing app, renamed workspace, source mismatch and malicious bundle metadata.

Exit: guessed identity never creates an action; activation/open failures are harmless; manual source matrix reports exact coverage; full validation, Graphify, commit/push clean.

### A11 — Setup UX, migration and hardening

Entrance: adapters define explicit configuration requirements/health and all earlier layers are independently stable.

Scope: AI Agents settings/status, integration on/off, completion/approval/sound/usage toggles, peek duration, detect/diff/confirm/backup/minimal patch/verify/rollback flows, provider version checks, migrations, diagnostics and performance hardening. Do not add unsupported controls.

Adversarial tests: comments/custom config preserved, concurrent external edit, missing/readonly/symlink config, rollback, provider upgrade/schema change, uninstall, bridge secret rotation, sleep/wake, crash/restart, flood, resource teardown and privacy redaction.

Exit: setup never overwrites wholesale or exposes secrets; off means no watchers/listener/animations; performance budgets below pass; manual clean install/upgrade/deny/rollback/uninstall matrices pass; full validation, Graphify, commit/push clean.

## 4. A11 measurable release gates

- Idle integration CPU below 0.5% five-minute average on a representative Apple-silicon Mac.
- No healthy-source polling; fallback intervals and catch-up obey architecture budgets.
- No unbounded event/history/request/JSONL/gzip allocation.
- Zero main-actor raw JSON/protobuf parsing.
- No active watcher, listener handler, timer, glow animation or stale discovery record after disable/stop.
- Privacy review verifies no prompts, source, full commands/outputs, credentials or account identifiers in store/logs/UI by default.
- Ten-session/flood and sleep/wake test matrices do not starve existing media, timer, Clipboard, File Shelf, Stats, gesture, layout or overlay behavior.

## 5. Known non-blocking research gaps

These must be resolved in their owning phase, not guessed in A1:

- whether DynamicIsland can subscribe to independently launched Codex clients through the shared App Server daemon;
- minimum Claude version needed for each desired hook and the migration story from local 2.1.94;
- verified exact-window association for IDE/Desktop sources;
- provider-supported third-party quota semantics;
- bidirectional approval support per source.

None blocks A1 because normalized identity, reduction, replay, privacy and capability absence are provider-independent.
