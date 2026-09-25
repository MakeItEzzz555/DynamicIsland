# Agent Event Schema Draft

- Status: Phase A0 design proposal; not implemented
- Date: 2026-09-24
- Depends on: [integration architecture](AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md)
- Feeds: [phase plan](AGENT_FEATURE_PHASE_PLAN_2026-09-24.md), especially A1 and A2

This document freezes the provider-independent vocabulary and versioned ingestion contract that A1 and A2 should implement. It does not claim that every provider can emit every field. Optional data is capability-gated; absence is represented as absence, never as invented data.

## 1. Domain contracts

The names below are conceptual Swift contracts. Exact declarations belong to A1.

| Contract | Required meaning |
|---|---|
| `AgentProvider` | Stable namespace: `codex`, `claude`, or a future reverse-DNS/custom value. |
| `AgentSource` | Verified entry point: `terminal`, `vscode`, `jetbrains`, `desktopApp`, `cloud`, or `unknown`. A guessed foreground app must remain `unknown`. |
| `AgentSessionID` | Composite logical identity, not a project path: provider + provider-native session ID. |
| `AgentSessionGeneration` | Monotonic local incarnation for one logical session. It separates resumed/reconnected ownership from stale producers. |
| `AgentSession` | Current reduced state, identity, project context, capabilities, activity, attention obligations, and bounded recent history. |
| `AgentState` | Provider-independent state listed below. |
| `AgentEvent` | Validated normalized input applied by the store reducer. |
| `AgentEventID` | Stable provider ID where available; otherwise adapter-generated deterministic digest over identity, native correlation, type, and stable source ordinal. |
| `AgentActivity` | Current human-readable, privacy-reduced activity: kind, title, optional summary, started time, and correlation ID. |
| `AgentTool` | Tool name, lifecycle, correlation ID, and privacy-safe category; arguments/results are not retained by default. |
| `AgentCommand` | Redacted executable/command summary, lifecycle, correlation ID, and optional exit status; no full stdout/stderr. |
| `AgentApproval` | Stable request correlation, type, summary, lifecycle, expiry, and whether provider-supported response control exists. |
| `AgentUsage` | Only observed metrics, each tagged with unit, scope, source, observed time, and optional limit. |
| `AgentCapability` | Runtime evidence that a particular session/provider can supply or perform an optional feature. |
| `AgentAttentionEvent` | Significant normalized event eligible for peek/badge/sound policy. |
| `AgentProjectContext` | Canonical local root when verified, privacy-safe display name, optional repository identity and branch, and source association evidence. |

Identifiers are value types and must be `Hashable`, `Codable`, and `Sendable`. Raw provider payloads must not leak beyond the adapter boundary.

## 2. State vocabulary

The normalized state set is:

- `idle`: session exists and has no active turn or unresolved attention obligation.
- `thinking`: provider has explicit model/reasoning activity but no more specific active operation.
- `planning`: provider explicitly reports plan construction or update.
- `working`: active turn with no more specific state.
- `runningTool`: a non-command tool is active.
- `runningCommand`: a shell/process command is active.
- `waitingForApproval`: an unresolved provider approval request exists.
- `waitingForUser`: explicit non-approval user input is required.
- `planReady`: a provider-authoritative plan is ready for user review.
- `completed`: the relevant task/turn ended successfully.
- `failed`: the relevant task/turn ended unsuccessfully.
- `interrupted`: user/provider cancellation or disconnection explicitly interrupted work.

There is no generic `peeking` state: peeking is presentation metadata. `completed`, `failed`, and `interrupted` are terminal for a generation until an authoritative continuation/resume event begins a newer generation or active turn. `planReady`, `waitingForApproval`, and `waitingForUser` persist until a correlated resolution or generation invalidation.

### Legal transitions

Start or resume may enter `idle`, `working`, `thinking`, or `planning`. Active states may move among `thinking`, `planning`, `working`, `runningTool`, and `runningCommand`. Any active state may enter a waiting state when explicitly reported. A correlated resolution returns to the most recent still-active parent state, otherwise `working`. An authoritative successful, failed, or interrupted end enters its matching terminal state. A new turn/resume increments turn ownership and may leave a terminal state. A weaker source cannot move a terminal or waiting state contradicted by stronger evidence.

Reducers must reject:

- events for an older generation;
- completions whose correlation has no open operation in that generation;
- approval resolutions for another session/generation/request;
- heuristic idle/completion over an unresolved structured operation;
- any action response after resolution, expiry, disconnect, or generation replacement.

## 3. Session identity

### Logical key

`AgentSessionID = (provider, nativeSessionID)`.

`AgentSessionInstanceID = (provider, nativeSessionID, generation)` owns mutable state. `source` and `projectIdentity` are attributes and correlation checks, not substitutes for the native ID. This permits:

- two sessions in one repository;
- Codex and Claude in the same repository;
- CLI and IDE sessions simultaneously;
- multiple editor windows;
- resumed sessions retaining logical history while receiving a new local generation;
- subagents carrying their own native child ID plus `parentSessionID`/`parentAgentID`.

### Generation rules

Generation increases when a new authoritative session start conflicts with an ended/disconnected incarnation, when an adapter reconnect cannot prove continuity, when a native ID is reused with incompatible immutable metadata, or when the store restores a session whose producer epoch cannot be authenticated. Ordinary resume with an authoritative matching native ID may retain the logical session but must establish a fresh producer epoch and reject callbacks from the prior epoch.

The A2.1 ingestion coordinator allocates generation before the A1 store validates/reduces the normalized event; adapters and wire clients cannot decrement, jump or choose it. Each registered source has a credential-independent source-instance identity and a producer epoch. A coordinator-issued opaque lease binds `(provider, nativeSessionID, generation, producer evidence)`. Producer restart may retain a generation only when compatible immutable continuity is proven.

### Project identity

Project identity is the canonicalized filesystem root plus repository identity when observable. It is never the session key. Path canonicalization resolves standardization/symlinks only when safe and does not require reading repository content. A display name may be redacted independently. Branch metadata is mutable enrichment and cannot split or merge sessions.

### Collisions

If the same provider/native ID appears concurrently with incompatible verified source/root metadata, quarantine the later stream as an identity conflict, expose degraded adapter health, and do not merge it. If native identity is absent, an adapter may create a scoped provisional ID from its producer/process identity; it must be marked provisional and replaced only through an explicit alias event. Project path alone is never an acceptable fallback ID.

## 4. Normalized event types

The initial vocabulary is:

`sessionStarted`, `sessionResumed`, `sessionEnded`, `agentWorking`, `thinking`, `planning`, `toolStarted`, `toolCompleted`, `commandStarted`, `commandCompleted`, `approvalRequested`, `approvalResolved`, `waitingForUser`, `userInputResolved`, `planReady`, `taskCompleted`, `taskFailed`, `interrupted`, `subagentStarted`, `subagentEnded`, `usageUpdated`, `projectContextUpdated`, `capabilitiesUpdated`, and `heartbeat`.

`heartbeat` may update health/liveness but cannot imply progress or completion. Adapters should normalize provider-specific events to the narrowest supported semantic event. If a provider only proves that a turn stopped, it must not label that as whole-task completion.

## 5. Versioned transport envelope

Conceptual JSON shape:

```json
{
  "protocolVersion": 1,
  "schemaVersion": 1,
  "eventID": "provider-stable-or-derived-id",
  "provider": "codex",
  "source": "terminal",
  "nativeSessionID": "opaque-provider-id",
  "sessionGeneration": 3,
  "eventType": "toolStarted",
  "timestamp": "2026-09-24T12:34:56.789Z",
  "receivedTimestamp": "2026-09-24T12:34:56.812Z",
  "correlationID": "opaque-tool-id",
  "sequence": 42,
  "capabilities": ["toolLifecycle"],
  "payload": {
    "tool": { "name": "Bash", "category": "command" }
  }
}
```

Wire clients do not get to choose `receivedTimestamp`; the bridge stamps it. Wire `producerID`, provider, source, authority, capabilities and generation are claims. Authentication supplies producer identity separately; A2.1 checks claims against server-side policy and resolves continuity to a locally allocated generation. `sessionGeneration`, when present, is only an assertion and cannot allocate or advance state.

### Limits and validation

- Maximum decoded event: 64 KiB; maximum HTTP request/batch: 1 MiB; maximum 100 events per batch. Reject before unbounded allocation.
- UTF-8 only. IDs: 1–256 bytes after normalization. Provider/source/type: allowlisted ASCII tokens, maximum 64 bytes. Human-readable title/summary: maximum 512/2,048 Unicode scalar values.
- Nesting depth: 12; object keys: 128 per object; arrays: 256 entries unless a narrower schema applies.
- Unknown top-level fields are ignored and retained nowhere. Unknown payload fields are ignored. Unknown `protocolVersion` is rejected. A known protocol with a newer `schemaVersion` is accepted only when required fields and event type are understood.
- Non-finite numbers, invalid dates, missing identity, impossible enum values, oversized strings, or schema-invalid payloads are rejected with a bounded diagnostic that contains no payload content.
- Provider timestamps more than five minutes in the future are clamped for display ordering to `receivedTimestamp` and flagged. Timestamps older than the session start remain admissible for replay but cannot resurrect an ended generation.

### Ordering, duplicates, and replay

Ordering authority is: provider monotonic sequence within its documented scope; otherwise causal correlation; then provider timestamp; then bridge receive ordinal. A sequence is never compared across processes when provider documentation says it resets. Arrival order alone is not semantic order.

The store keeps a bounded deduplication index by `(provider, eventID)` and an open-operation index by correlation ID. Exact duplicates are idempotent. Same ID with different normalized content is a protocol violation. A completion arriving before its start is held in a small bounded reorder window (proposal: two seconds or 64 events per session), then either reconciled or recorded as orphaned without corrupting current state.

Replay input uses the same validation and reducer path as live input, with a deterministic receive clock. Replayed events are marked `origin: replay`; production builds must not mix replay producers into live sessions.

## 6. Capability model

Capabilities are scoped to a provider, source, session, and generation, with provenance. Initial flags include:

- `sessionLifecycle`, `explicitThinking`, `planLifecycle`, `toolLifecycle`, `commandLifecycle`
- `approvalObservation`, `approvalControl`, `userInputObservation`
- `subagentLifecycle`, `taskLifecycle`
- `tokenUsage`, `contextUsage`, `quotaUsage`, `costUsage`
- `projectContext`, `gitMetadata`, `verifiedSourceIdentity`, `sourceAppOpen`

Capabilities are not promises made by an adapter class. They are evidence-derived runtime values ledgered by producer/source instance. Withdrawal from source A does not remove source B's proof; when all valid evidence disappears, the effective capability disappears. A provider schema downgrade or policy revocation removes only affected evidence and the UI must immediately hide/disable dependent controls. Security-sensitive `approvalControl` remains unavailable until A9 registers a supported action surface; an arbitrary authenticated bridge claim cannot create it.

## 7. Privacy projection

The default normalized model does not retain complete prompts, source code, full tool input/output, full shell commands, stdout, stderr, environment variables, account identifiers, or raw provider records.

Allowed default fields are task title when explicitly supplied, privacy-reduced tool name/category, redacted command summary, project display name, model, state, timestamps, approval summary, and supported aggregate usage. Paths display only a configured project name by default. Command summaries remove arguments likely to contain paths, URLs, tokens, inline scripts, or user content; if a useful safe summary cannot be made, display `Running command`.

Raw input lives only through decode/normalize and is released. Diagnostics use event ID/type/error class, not payload fragments. No cloud transmission is part of the design.

Initial bounded-memory proposal: at most 32 live/recent sessions, 200 normalized history entries per session, 2,000 entries globally, and 24 hours of completed-session retention in memory. A1 tests eviction deterministically. Persistence is out of scope until separately designed and opt-in.

## 8. Replay fixture contract

A1 creates version-controlled, sanitized fixtures that contain only the envelope above. Required sequences:

- Codex: start → reasoning → command → result → plan ready → approval → resolution → continuation → tests → completion.
- Claude: start → thinking → Todo/task → tool → permission → resolution → subagent → completion.
- Race/adversarial: exact duplicate, conflicting duplicate, out-of-order completion, stale generation, delayed tool completion, session replacement, two simultaneous same-project sessions, mixed providers, malformed payload, unknown protocol/schema/event, abrupt termination, source clock skew, and flood beyond limits.

Each fixture declares expected store snapshots after every event, attention outputs, diagnostics, and capability changes. Provider adapters later add raw-provider-to-normalized fixture layers, but all UI phases continue to depend on normalized replay fixtures rather than live installations.

## 9. Deferred decisions

- Exact Swift enum associated values and file layout belong to A1.
- Cryptographic transport authentication belongs to A2; the envelope never carries the secret in its payload.
- Provider raw schema mappings belong to A3/A4.
- Approval decision messages belong to A9 and require a separate authenticated action envelope with nonce, expiry, exactly-once semantics, and supported provider control.
