# AgentNotch Reference Review

- Status: read-only reference audit; no source copied
- Accessed: 2026-09-24
- Repository owner: AppGram
- Pinned commit: [`4139d6fd7b90a060b90b17ed20e0878b0641cc1a`](https://github.com/AppGram/agentnotch/commit/4139d6fd7b90a060b90b17ed20e0878b0641cc1a)
- Companion decisions: [DynamicIsland architecture](AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md)

The pinned commit was verified from upstream `main` and is the exact source reviewed. AgentNotch is useful behavioral reconnaissance, not a dependency or implementation donor.

## 1. Architecture observed

AgentNotch combines three independent ingestion/state paths:

- `ClaudeCodeManager` (about 1,534 lines) polls Claude project/IDE state, discovers recent JSONL sessions, tails files, and maintains both per-session and legacy selected/global state.
- `CodexManager` (about 608 lines) polls Codex session directories, parses `session_meta`, tails rollout JSONL, and also maintains per-session plus selected/global state.
- `TelemetryCoordinator` (about 1,140 lines) accepts OTLP logs/metrics and maps loosely typed attributes into one global source, tool, token, and completion model.

The main `AgentNotchContentView` (about 1,686 lines) coordinates managers, sizing, hover/peek, glow, completion, permissions, usage and unrelated presentation features. These sizes are descriptive evidence of concentrated responsibility, not criticism based on line count alone.

Primary source files:

- [CodexManager.swift](https://github.com/AppGram/agentnotch/blob/4139d6fd7b90a060b90b17ed20e0878b0641cc1a/AgentNotch/Core/Codex/CodexManager.swift)
- [ClaudeCodeManager.swift](https://github.com/AppGram/agentnotch/blob/4139d6fd7b90a060b90b17ed20e0878b0641cc1a/AgentNotch/Core/ClaudeCode/ClaudeCodeManager.swift)
- [TelemetryCoordinator.swift](https://github.com/AppGram/agentnotch/blob/4139d6fd7b90a060b90b17ed20e0878b0641cc1a/AgentNotch/Core/Telemetry/TelemetryCoordinator.swift)
- [OTLPHTTPServer.swift](https://github.com/AppGram/agentnotch/blob/4139d6fd7b90a060b90b17ed20e0878b0641cc1a/AgentNotch/Core/Telemetry/OTLPHTTPServer.swift)
- [OTLPDecoder.swift](https://github.com/AppGram/agentnotch/blob/4139d6fd7b90a060b90b17ed20e0878b0641cc1a/AgentNotch/Core/Telemetry/OTLPDecoder.swift)
- [AgentNotchContentView.swift](https://github.com/AppGram/agentnotch/blob/4139d6fd7b90a060b90b17ed20e0878b0641cc1a/AgentNotch/Views/Notch/AgentNotchContentView.swift)

## 2. Mechanism classification

| Mechanism | Classification | Reason / DynamicIsland treatment |
|---|---|---|
| provider-neutral session/activity model | **ADOPT AS CONCEPT** | A common vocabulary is essential. DynamicIsland will use typed events and one keyed reducer rather than parallel global state. |
| hybrid official telemetry plus local discovery | **ADAPT TO DYNAMICISLAND** | Put each source behind an adapter, apply event-specific authority/deduplication, require consent/authentication and limits. |
| incremental JSONL tailing | **ADAPT TO DYNAMICISLAND** | Useful fallback, but add carry buffers, UTF-8 boundary handling, inode/truncate/rotation recovery, source-version gates and deterministic fixtures. |
| multi-session discovery and compact indicators | **ADOPT AS CONCEPT** | Multiple simultaneous sessions/providers are core. Ordering, selection and identity must be deterministic. |
| terminal and IDE coexistence | **ADOPT AS CONCEPT** | Source is an attribute of a native session, never inferred only from workspace path. |
| project/workspace and branch enrichment | **ADOPT AS CONCEPT** | Helpful UI metadata, but neither project nor branch is a session identifier. |
| source/provider color semantics | **ADAPT TO DYNAMICISLAND** | Restrained semantic accents using the existing shell/theme language, accessibility and energy rules. |
| temporary closed→peek→open interaction | **ADAPT TO DYNAMICISLAND** | Preserve the user outcome, but implement peek as transient collapsed presentation metadata; `IslandStateStore` stays collapsed/expanded. |
| lower-notch glow and ding | **ADAPT TO DYNAMICISLAND** | Short bloom/slow fade, event priority, Reduce Motion, no idle high-FPS animation, sound coalescing. |
| expanded session/tool/usage UI | **ADOPT AS CONCEPT** | Build small capability-gated cards; do not reproduce the monolithic view. |
| explicit permission attention | **ADOPT AS CONCEPT** | Only structured provider permission events can create `waitingForApproval`; retain badge until resolution. |
| five-second permission inference from long-running tools | **REJECT** | A slow Bash/Edit/MCP call is not proof of an approval prompt. |
| timeout completion as authoritative truth | **REJECT** | Timeouts may mark health/possible idle only; they cannot produce successful completion. |
| hard-coded recent five-minute session window | **REJECT** | Loses long sessions and makes restart recovery nondeterministic. Use lifecycle, bounded indexing and explicit recency policy. |
| hard-coded context limits and pricing | **REJECT** | Provider/model semantics change. Display only sourced metrics with capability/freshness provenance. |
| Claude web-cookie quota scraping | **REJECT** | Undocumented endpoint and session-cookie handling add unacceptable fragility and secret risk. |
| Keychain for supported credentials | **ADOPT AS CONCEPT** | Appropriate for the local bridge secret and documented opt-in provider credentials only. |
| IDE/process focus heuristics | **REFERENCE ONLY** | Bundle/PID lookup is useful enrichment but not enough for exact session/window identity or action controls. |
| global singleton/selected/per-session duplicate state | **REJECT** | One authoritative `AgentEventStore`, with selection and UI as derived state. |
| fixed open size/single-screen sampling | **REFERENCE ONLY** | DynamicIsland already has adaptive notch geometry and screen-change handling. |
| private CGS maximum-level panel behavior | **REJECT** | Preserve the supported existing `NSPanel` architecture. |
| perpetual 15/25 FPS glow/session-dot animation | **REJECT** | Animate only during visible transitions; idle has no display-loop cost. |
| source code or asset reuse | **REJECT** pending license resolution | Architectural concepts only; implementation is independent. |

## 3. Discovery and identity weaknesses

Both provider managers rescan every ten seconds and only consider files modified within five minutes. Claude IDE discovery decodes lock files and accepts live PIDs, while terminal sessions are synthesized from recent JSONL filenames. Claude identity is based on `ideName:firstWorkspace`; multiple editor processes/windows on the same workspace can collide. IDE-to-JSONL association selects the most recently modified workspace file rather than proving a PID/window/session relationship.

Editor activation uses bundle/name/PID matching for a small hard-coded set. Terminal sessions fall back to an application-name match and have no window association. This is useful as a fallback hint but cannot support a verified “Open exact source session” action.

The multi-session commit discovers more sessions, but the reviewed UI does not call the managers' selection API; Claude dots focus an IDE rather than select session details, and Codex lacks equivalent dots. With multiple startup sessions, expanded detail may therefore remain stale or empty.

DynamicIsland response: use `(provider, nativeSessionID, generation)` identity, keep source/project as attributes, quarantine collisions, and capability-gate app activation as defined in the [schema draft](AGENT_EVENT_SCHEMA_DRAFT_2026-09-24.md).

## 4. Completion and permission weaknesses

Claude permission is inferred when certain active tools exceed five seconds, with a hard-coded always-approved list. One timer services all sessions. Completion combines `stop_reason`, interruption-text matching, a three-second thinking timeout and ten-second tool timeout. Global idle timers can be reset by one session and then mutate every session.

The telemetry path declares completion after 30 seconds without activity or 15 seconds after an `active_time` metric, force-completes every active call as successful, and inserts a synthetic completion tool. These mechanisms conflate inactivity, blocked permission, source loss and success.

DynamicIsland response: provider hooks/protocol own permission and completion; telemetry enriches; heuristics may only degrade health to stale/unknown. Each open operation is keyed by session generation and provider correlation ID.

## 5. JSONL robustness weaknesses

The reviewed tailers watch write/extend but not rename/delete/truncate. They advance offsets before line framing/parsing, keep no carry buffer for a line split across file events, and silently discard malformed/unknown records. A partial final line can therefore be permanently lost. History reads are bounded but brittle: Claude/Codex line/byte cutoffs can omit relevant metadata, and Codex searches only an early prefix for session metadata.

Required adaptation:

- hold trailing incomplete bytes until newline;
- decode on complete UTF-8 boundaries;
- advance committed offset only after framing;
- detect inode replacement, shrink/truncate and rotation;
- limit catch-up bytes/lines and parse off main actor;
- retain unknown-version health evidence without raw content;
- test partial writes, malformed lines, rotation, sleep/wake, concurrent append and teardown.

## 6. OTLP/server weaknesses

The reference HTTP server accepts logs/metrics but not traces. It does not visibly enforce method/content type, chunked-transfer behavior, header/body/decompressed-size caps, or idle timeouts; gzip can expand without a bound. It returns 200 before asynchronous decoding finishes, so decode failure cannot affect acknowledgement. Stop cancels the listener but not active handlers. Decoder coverage discards multiple resource/scope/value/metric forms.

The listener is constructed from a port without an explicit loopback endpoint restriction; this is an inference from source, not a network test. Global telemetry state lets interleaved providers overwrite source/model/tokens/completion. Missing call IDs become random IDs, duplicate starts remain duplicate visible calls, and mismatched results can be ignored.

DynamicIsland response: authenticated ephemeral loopback bridge, strict request limits, per-provider fair queues, decode-before-ack, complete shutdown ownership, typed versioned envelopes, deterministic IDs and per-session state. See the [bridge decision](AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md#5-local-bridge-decision).

## 7. UI and lifecycle weaknesses

AgentNotch's useful `closed`/`peeking`/`open` interaction lives in a separate view model, while its panel is allocated at a fixed open size on the main screen and uses private CGS space/level behavior. It has no evident screen-change or sleep/wake re-establishment. Numerous view-owned delayed tasks are only partly cancelled on disappearance; permission hiding includes an untracked delayed task. A power monitor has a stop method that is not invoked.

DynamicIsland already has safer foundations: one adaptive host panel, `NotchGeometryService`, `IslandLayoutStore`, visibility-generation gating, shape-aware input controls, and controller-owned state. The only adopted behavior is transient attention; it must use coordinator generation ownership and the existing shell path.

## 8. Usage and configuration weaknesses

Reference context limits are manually configured, usage formulas do not necessarily equal provider context occupancy, and pricing tables become stale. Claude quota access asks for a browser session cookie and polls undocumented web endpoints. Some enable/disable settings do not stop singleton scanners, and an in-flight usage refresh can re-arm polling after stop.

DynamicIsland response: no fabricated context/quota/cost; every optional metric has capability, source and freshness. Setup is explicit minimal config patching with rollback. Adapter `stop()` must cancel watchers, requests, callbacks and re-arm paths, with tests.

## 9. Licensing result

The pinned README says “MIT License — see LICENSE,” but the pinned tree contains no root `LICENSE`, `LICENSE.md`, `COPYING`, or equivalent. GitHub repository metadata reports no recognized license, while `Info.plist` says “All rights reserved.” Two files name external sources/licenses without corresponding repository notices.

Sources:

- [README license claim](https://github.com/AppGram/agentnotch/blob/4139d6fd7b90a060b90b17ed20e0878b0641cc1a/README.md#L121-L123)
- [GitHub repository metadata](https://api.github.com/repos/AppGram/agentnotch)
- [Pinned recursive tree](https://api.github.com/repos/AppGram/agentnotch/git/trees/4139d6fd7b90a060b90b17ed20e0878b0641cc1a?recursive=1)
- [Info.plist notice](https://github.com/AppGram/agentnotch/blob/4139d6fd7b90a060b90b17ed20e0878b0641cc1a/Info.plist#L31-L32)

Conclusion: the README alone does not establish a sufficiently reliable license grant. AgentNotch remains reference-only. No source, implementation, visual asset, or proprietary resource may be copied or transplanted. DynamicIsland's design is independently derived from public provider APIs and its existing architecture. License ambiguity does not block A1 because A1 uses only this independently specified normalized model.

## 10. Strongest ideas retained

- source-aware, multi-provider, multi-session awareness;
- a normalized activity stream with project/model/tool/usage enrichment;
- compact session indicators and an expanded activity surface;
- transient attention for completion/permission events;
- provider-semantic visual accents;
- combining explicit live events with bounded recovery sources.

The concrete implementation choices—identity, authority, authenticated bridge, privacy projection, generation ownership, capability gating and replay-first development—come from DynamicIsland's requirements and current provider documentation, not from copied AgentNotch code.
