# Claude Managed Control Review — 2026-09-27

## Scope and installed baseline

This review covers authoritative ways for DynamicIsland to control a local Claude Code session. It does not propose terminal keystroke injection, GUI automation, cookie scraping, or parsing private rollout files.

The installed executable is `claude` 2.1.283. Its documented command surface includes non-interactive streaming input/output, session IDs and resume, model selection, partial messages, host-owned permission prompts, background agents, and stop. The official Claude Agent SDK is the stronger integration boundary because it exposes those controls as typed APIs and owns the Claude Code subprocess protocol.

## 1. Supported official mechanism

Use the official [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview) for local managed control. Its streaming-input mode is explicitly intended for persistent interactive sessions, queued input, interruption, permissions, and real-time output. The SDK can use its bundled Claude Code binary or an explicitly selected installed binary.

Anthropic also offers the separate cloud [Managed Agents Sessions API](https://platform.claude.com/docs/en/managed-agents/sessions). It has excellent event, interrupt, approval, and history semantics, but it creates Anthropic Platform sessions in configured environments; it is not an adapter for the user's existing local Claude Code transcripts or subscription-backed CLI session domain. It should not be substituted silently for local Claude Code.

## 2. Transport and API

Recommended Phase 6 transport:

1. DynamicIsland owns one narrowly scoped local Claude provider helper.
2. The helper uses the official TypeScript package `@anthropic-ai/claude-agent-sdk`, pinned to a reviewed version compatible with Claude Code 2.1.283 or newer.
3. DynamicIsland and the helper exchange a small, authenticated, bounded provider-neutral IPC protocol.
4. The helper owns each SDK `Query` process, converts typed SDK messages into bounded events, and never forwards raw stderr or private protocol frames.
5. Provider events converge on `AgentIngestionCoordinator`; the helper is not a second lifecycle store.

Directly implementing the SDK's internal control protocol over `claude --input-format stream-json --output-format stream-json` would couple DynamicIsland to details that the official SDK already owns. The CLI flags are documented, but the SDK is the safer production contract for interruption, model switching, permissions, initialization capabilities, and teardown.

## 3. Lifecycle and session semantics

The SDK supports a new session through `query()` and a persistent interactive process through streaming input. A result or initialization message supplies the authoritative session UUID. A later process can resume that exact conversation with the `resume` option; resume keeps the original session unless the caller explicitly requests a fork. Sessions persist conversation history locally, not filesystem snapshots. See [Work with sessions](https://code.claude.com/docs/en/agent-sdk/sessions).

Recommended mapping:

- Claude SDK session UUID → `AgentSessionID.nativeSessionID`
- one submitted user message → one turn
- assistant result → turn completion, returning the session to idle/resumable
- process/transport failure → managed transport failure, without declaring the persisted session dead
- explicit fork → a new native session identity

Start, resume, submit, and interruption are authoritative. The TypeScript `Query.interrupt()` control stops the active response and returns an interrupt receipt on supporting Claude Code versions. `Query.close()` owns subprocess teardown. The provider must serialize control per exact session and reject stale turn/session correlations.

## 4. Streaming visible responses and tool events

The SDK async stream emits typed user, assistant, result, system, tool-progress, and rate-limit messages. `includePartialMessages` adds streaming assistant events for low-latency text. Completed assistant messages remain authoritative. DynamicIsland should update an in-progress console entry by message/content-block identity and replace it with the completed message, rather than append a row per delta. See [Stream responses in real time](https://code.claude.com/docs/en/agent-sdk/streaming-output).

Only user-visible text, bounded tool summaries, sanitized errors, and lifecycle/status evidence should be projected. Thinking/reasoning blocks must be ignored. Raw protocol data, tool inputs containing secrets, environment values, and stderr must not enter the presentation store.

## 5. Approvals and user input

The SDK's `canUseTool` callback is the official synchronous approval boundary. It pauses the tool request until the host returns either an allow result with the approved input or a deny result with a message. `AskUserQuestion` uses the same callback but is a distinct user-input interaction. See [Handle approvals and user input](https://code.claude.com/docs/en/agent-sdk/user-input).

For DynamicIsland:

- correlate approval to provider + session UUID + exact SDK request/tool-use identity;
- expose only bounded, privacy-projected input;
- resolve once;
- deny or fail safely on teardown/expiry;
- keep Claude capability separate from Codex hook approval authority;
- do not persist SDK permission updates unless a later, explicit approval-policy phase authorizes that scope.

The callback is bypassed when an earlier permission rule auto-allows a tool, so Phase 6 should use an approval-preserving permission configuration and treat the SDK's evaluated flow as authoritative.

## 6. Model control

The SDK exposes `supportedModels()` with provider/account-aware display metadata and `setModel()` for a running streaming-input session. `setModel()` changes the active model through the official control channel; passing `default` or no model clears the override. The initialization result also includes the supported model list. Claude Code's model aliases and organization restrictions remain authoritative. See the [TypeScript Agent SDK reference](https://code.claude.com/docs/en/agent-sdk/typescript) and [Model configuration](https://code.claude.com/docs/en/model-config).

Phase 6 should populate the selector only from `supportedModels()`, store selection per Claude session, invoke `setModel()` on that exact live query, and update UI only after the control call succeeds. Resumed sessions must report their actual initialized model. No static model catalog is needed.

## 7. Usage and context

Per-turn token/cost evidence is available on result messages. In a streaming session, the documented totals can be cumulative across turns, so clients must use the latest total rather than summing results. These values are development/accounting estimates, not subscription billing truth. See [Track cost and usage](https://code.claude.com/docs/en/agent-sdk/cost-tracking).

Current context is authoritative through `Query.getContextUsage()` on supported SDK versions. It returns the same structured categories used by Claude Code's `/context`, including current usage and model window information. Context remains selected-session scoped.

There is no documented SDK equivalent of Codex's idle `account/rateLimits/read` that continuously returns the user's Claude subscription 5-hour/weekly quota windows. `SDKRateLimitEvent` reports utilization/status when a session encounters rate-limit evidence, and `/usage` can be invoked as a session command, but neither should be presented as a general background account-quota API. Therefore Phase 6 should expose Claude account quota only when an official trustworthy source is present, otherwise show unavailable—not borrow Codex metrics or fabricate values.

## 8. History and discovery

The SDK officially exposes `listSessions()` for bounded discovery and `getSessionMessages()` for bounded user/assistant transcript history. Results can be filtered by project and limited; sessions are ordered by recent modification. Resume by UUID restores the full underlying context. See [Work with sessions](https://code.claude.com/docs/en/agent-sdk/sessions) and the [TypeScript reference](https://code.claude.com/docs/en/agent-sdk/typescript).

DynamicIsland should use these APIs rather than parse `~/.claude/projects` JSONL files. Discovery should remain bounded and provider-scoped. Safe history projection must exclude thinking and raw tool payloads, deduplicate streamed/completed messages, and preserve Claude session UUID identity.

## 9. Gaps compared with the current Codex provider

- The local integration requires an official SDK helper/runtime boundary because DynamicIsland is Swift and the supported Claude Agent SDKs are TypeScript/Python.
- Claude does not document a Codex-like idle account rate-limit endpoint for persistent 5-hour/weekly subscription gauges.
- Existing Claude observation-hook sessions must be reconciled carefully with SDK-discovered UUIDs before granting managed capabilities.
- Approval requests arrive through a long-lived callback, so process loss, timeout, reconnect, and one-shot response behavior need dedicated tests.
- `interrupt()` is query/session scoped rather than Codex's explicit thread ID + turn ID request; the controller must still bind it to the exact active managed Claude query.
- Cloud Managed Agents is a different session and billing domain and cannot transparently resume local Claude Code sessions.

## 10. Phase 6 recommendation

Implement `ClaudeInteractiveProvider` behind the existing provider-neutral contract, backed by a small pinned official Agent SDK helper. Start with one owned helper and one managed query per selected/active Claude session, bounded session discovery/history, safe streaming projection, exact resume, submit, interrupt, SDK-reported models, selected-session context, and manual `canUseTool` approvals.

Before enabling the provider in production, prove on the real Mac:

1. start and resume retain the exact SDK session UUID;
2. user input and assistant deltas/finals deduplicate correctly;
3. interruption affects only the selected active query;
4. approval allow/deny is exact, one-shot, and fail-safe across helper loss;
5. SDK-discovered and hook-observed instances converge without duplicate sessions;
6. model selection changes actual SDK behavior and survives the intended session lifecycle;
7. context comes from `getContextUsage()` for the selected Claude session;
8. helper crashes leave persisted sessions resumable and do not leak raw diagnostics;
9. all subprocesses terminate cleanly with no orphans.

Do not begin with Claude Managed Agents cloud sessions unless the product explicitly chooses that separate cloud execution, authentication, environment, and billing model.
