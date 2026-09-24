# Agent Capability Matrix

- Status: verified research snapshot; design implications are labeled
- Accessed: 2026-09-24
- Companion: [architecture](AGENT_INTEGRATION_ARCHITECTURE_2026-09-24.md), [schema draft](AGENT_EVENT_SCHEMA_DRAFT_2026-09-24.md)

## 1. Method and version boundary

Facts were checked against provider-owned documentation, safe read-only local CLI help, and sanitized local state structure. No provider call, login, configuration edit, hook installation, or prompt/transcript content read occurred.

Local versions:

- OpenAI Codex: `codex-cli 0.155.1`.
- Anthropic Claude Code: `2.1.94 (Claude Code)`.

Classification:

- **AVAILABLE**: an official supported surface exists and the local tool confirms the relevant capability where local confirmation is applicable.
- **PARTIAL**: a surface exists but coverage, installed version, entry point, account entitlement, or semantic strength is incomplete.
- **UNAVAILABLE**: no supported equivalent was found for the requested role.
- **UNKNOWN**: safe research could not establish the fact.

Important version caveat: current Anthropic documentation describes features introduced after local Claude Code 2.1.94. Such features are current product capabilities but not evidence about this installed binary. Codex App Server is richly specified but marked experimental.

## 2. Primary supported integration surfaces

### Codex

| Surface | Status | Semantics and use |
|---|---|---|
| App Server JSON-RPC | **AVAILABLE**, experimental | Richest official live thread/turn/item stream, token usage, plan updates, user-input requests, and bidirectional approvals. Transports include stdio, Unix socket, and WebSocket in local help. Best authority only for sessions connected/subscribed through that server. |
| Lifecycle hooks | **AVAILABLE** | Installed feature is stable/enabled. Current hooks cover session, tools, permissions, prompts, compaction, subagents, stop and interrupt. A hook is authoritative at its named boundary but is not a lossless session stream. Hook trust is explicit. |
| `codex exec --json` | **AVAILABLE** | Public JSONL for one non-interactive invocation, including thread/turn/item/error events. It does not passively observe unrelated interactive clients. |
| OpenTelemetry | **AVAILABLE**, opt-in | Structured operational logs/metrics for conversation start, API/stream activity, tool decision/result and tokens. Disabled unless configured; prompts are redacted by default. Enrichment/audit, not full replay. |
| persisted rollout JSONL/SQLite | **PARTIAL** | Detailed local implementation data, useful for bounded recovery. Not treated as a stable public compatibility contract. |
| MCP client | **AVAILABLE** | Tool/data extension for Codex, not a passive lifecycle observer. CLI and IDE share config. |
| MCP server mode | **UNAVAILABLE** in installed help | No installed `codex mcp-server`; App Server and exec-server are different interfaces. |
| process/editor observation | **PARTIAL** | Can enrich verified sessions but cannot establish lifecycle or identity by foreground-app guesses. |

### Claude

| Surface | Status | Semantics and use |
|---|---|---|
| lifecycle hooks | **AVAILABLE** as product; **PARTIAL** locally | Current official hooks cover session, prompt, tool, permission, notification, subagent, task, stop/failure, model/config/CWD/file/worktree, compact and elicitation events. They fire across terminal, IDE, Desktop, and cloud contexts, subject to source/config reachability. Local 2.1.94 predates some current events. HTTP hooks POST the same JSON as command hooks. |
| `--output-format stream-json` / Agent SDK | **AVAILABLE** | Strongest supported programmatic stream for a Claude process launched through it. Not passive observation of arbitrary already-running interactive sessions. |
| OpenTelemetry | **AVAILABLE**, opt-in | Metrics, logs/events and optional traces with session/prompt/tool correlation, token/cost and activity fields. Operational/enrichment surface, not full conversation replay. |
| project transcript JSONL | **PARTIAL** | Officially documented local application data and complete plaintext transcript, but Anthropic states the entry format is internal and changes between versions. Version-pinned fallback only. |
| statusline JSON | **PARTIAL** | Live snapshot can include model, directories, context/cost/Git and conditional usage windows. It is a presentation integration, not a durable event stream. |
| MCP client/server | **AVAILABLE** | Local help includes MCP client management and `claude mcp serve`. MCP is not by itself a session lifecycle feed. |
| Codex-equivalent app server | **UNAVAILABLE** | Closest surfaces are stream-json/Agent SDK, hooks, newer Remote Control, and MCP server mode; none is a general passive local control plane equivalent. |

## 3. Capability matrix

| Capability | Codex 0.155.1 | Claude Code / current product |
|---|---|---|
| session lifecycle and ID | **AVAILABLE**: thread/session IDs and thread→turn→item lifecycle | **AVAILABLE**: session ID, resume/continue/fork and hook/transcript lifecycle |
| project/CWD | **AVAILABLE**: CLI, App Server and persisted metadata | **AVAILABLE**: CLI/status/transcript metadata |
| model identity | **AVAILABLE** | **AVAILABLE** |
| explicit thinking/reasoning state | **PARTIAL**: reasoning items exist; a durable universal `thinking` state across every client is not guaranteed | **PARTIAL**: stream/transcript thinking blocks exist; hooks do not supply one universal thinking-state boundary |
| working/turn state | **AVAILABLE** through App Server/exec stream | **AVAILABLE** for launched stream; **PARTIAL** passively across all independent surfaces |
| tool start/completion | **AVAILABLE**: item lifecycle and pre/post hooks | **AVAILABLE**: pre/post/failure hooks and stream messages, version dependent locally |
| shell command start/completion | **AVAILABLE**: command item/tool hooks | **AVAILABLE**: Bash tool lifecycle/hooks |
| approval request | **AVAILABLE**: App Server request and PermissionRequest hook | **AVAILABLE**: PermissionRequest hook/permission prompt surface |
| approval decision/result | **AVAILABLE**: App Server resolution and OTel decision | **AVAILABLE** at hook/provider boundary; exact control mode/version must be proven before A9 |
| supported bidirectional approval | **AVAILABLE** for an App Server client that owns the request | **PARTIAL**: hooks/permission prompt can decide, but safe ownership for each source/version must be validated |
| plan updates / plan-ready | **AVAILABLE**: plan items and `turn/plan/updated`; “ready” requires explicit final-item rule | **PARTIAL**: plan mode/tasks exist, but one universal plan-ready event was not established for local 2.1.94 |
| explicit waiting for user | **AVAILABLE**: App Server user-input request/MCP elicitation | **PARTIAL**: elicitation/permission hooks cover cases; generic user-input-required semantics vary |
| task/turn completion | **AVAILABLE**: turn/item completion status | **AVAILABLE**: result/Stop; distinguish turn response from whole project task |
| failure | **AVAILABLE**: failed turn with typed error | **PARTIAL** locally: current `StopFailure` is richer than installed-version evidence |
| interruption | **AVAILABLE**: interrupt request and interrupted terminal status | **PARTIAL**: UI interruption exists, but no single stable public terminal event equivalent was verified |
| subagents/workers | **AVAILABLE**: stable local multi-agent feature, hook and parent/child metadata | **PARTIAL** locally: agents/subagent records/hooks exist; newer teams/background monitoring exceed 2.1.94 |
| Todo/task lifecycle | **PARTIAL**: plans/goals/items exist but provider-wide Todo semantics vary | **AVAILABLE** in current hooks (`TaskCreated`/`TaskCompleted`); locally version-gated |
| token usage | **AVAILABLE** | **AVAILABLE** |
| context-window usage | **AVAILABLE** | **AVAILABLE** via status/usage/transcript/OTel surfaces |
| rate-limit/quota usage | **AVAILABLE** surface, values account-dependent | **PARTIAL**, account/version dependent; no stable third-party quota contract proven |
| cost metrics | **PARTIAL**: usage available; pricing-derived cost must not be fabricated | **AVAILABLE** through documented telemetry/status when enabled and entitled; still capability-gated |
| Git branch/repository metadata | **AVAILABLE** | **AVAILABLE** |
| CLI entry point | **AVAILABLE** | **AVAILABLE** |
| VS Code-compatible entry point | **AVAILABLE** product; local artifact presence does not prove active/current | **AVAILABLE** product; local artifact presence does not prove active/current |
| JetBrains entry point | **AVAILABLE** through JetBrains AI Chat integration; per-session telemetry/source identity is **PARTIAL** | **AVAILABLE** plugin; per-session identity is **PARTIAL** |
| native desktop entry point | **AVAILABLE** as ChatGPT/Codex product; not installed locally | **AVAILABLE** as Claude Desktop Code; not installed locally |
| cloud sessions | **AVAILABLE** product; entitlement/live behavior **UNKNOWN** | **AVAILABLE** product; local bridge reachability and entitlement **UNKNOWN** |
| source app identity per session | **PARTIAL** | **PARTIAL** |
| open exact source window/session | **UNKNOWN** for most sources | **UNKNOWN** for most sources |

## 4. Event-specific authority

### Codex

1. App Server notification/response for sessions it owns or subscribes to.
2. `codex exec --json` for the invocation it launched.
3. a lifecycle hook for its specific event boundary.
4. OTel for documented operational/tool/usage facts and enrichment.
5. version-pinned local rollout/SQLite reconstruction.
6. verified process/editor observation; bounded heuristic last.

App Server `turn/completed` differentiates completed/interrupted/failed; `item/*` is the documented source of truth for items; plan updates and `thread/tokenUsage/updated` are explicit. Approval requests are server-initiated JSON-RPC and resolutions are confirmed by `serverRequest/resolved`.

### Claude

1. stream-json/Agent SDK for a process launched through that integration.
2. a hook at its documented lifecycle boundary; HTTP hooks are particularly suitable for the local bridge.
3. OTel for usage/audit facts and correlation.
4. version-pinned transcript JSONL for bounded recovery.
5. statusline for a current presentation snapshot.
6. verified process/editor observation; bounded heuristic last.

Claude hook and OTel records share correlation fields such as `session_id`, `prompt_id`, and `tool_use_id`. OTel `event.sequence` is per process and can repeat/decrease within a resumed session, so ordering uses timestamp plus sequence only within its documented scope.

## 5. Local storage audit (content redacted)

### Codex

Observed structural locations include `sessions/YYYY/MM/...jsonl`, `archived_sessions/`, `attachments/`, `history.jsonl`, `session_index.jsonl`, SQLite read models, config, agents/skills/plugins/rules, caches, shell snapshots and IPC data.

Observed rollout record families: `session_meta`, `turn_context`, `event_msg`, `response_item`, `token_usage_record`, `compacted`, `world_state`, and `inter_agent_communication_metadata`. Metadata shapes include IDs, CWD/workspace roots, model/provider, CLI version, Git, parent/fork/subagent linkage, approval/sandbox profiles, context window, effort, usage and compaction. Content values were not inspected.

`history.jsonl` contains prompt text and is sensitive. It is not an activity integration source. SQLite schemas show thread/turn/item/spawn-edge read models, but schema evolution makes them fallback implementation detail, not an adapter contract.

### Claude

Observed structural locations include per-project session JSONL, history, plans, tasks, todos, session environment, shell snapshots, file history/paste cache, agents/plugins/settings and global app state.

Observed record families: `user`, `assistant`, `system`, `progress`, and plugin/skill match metadata. Metadata includes session/message/prompt/request IDs, CWD, Git branch, model, usage, agent/sidechain identity, version, timestamps and stop reason. Content block kinds include text, thinking, tool use and tool result; values were not read.

Claude history and transcripts can contain full prompt, pasted, tool and output content in plaintext. Routine integration must not ingest those fields. Transcript file append, truncation, partial-line and version drift handling must be fixture-tested before any watcher ships.

### Cross-surface findings

- Codex CLI and IDE share configuration, but compatible config does not prove that every surface shares one observable live stream.
- Claude Desktop uses the same underlying engine but maintains session history separately from CLI; hooks are documented across surfaces, subject to configuration source/reachability.
- Native app/cloud session discovery and local bridge reachability remain source-specific. Do not merge records merely because CWD matches.

## 6. Source application association

Candidate bundle identities must be resolved and tested in A10; no action is designed from foreground guesses. Evidence levels:

- **verified**: provider source/entrypoint field, authenticated hook producer metadata, official IDE protocol, or process ancestry tied to the native session ID;
- **corroborated**: verified executable plus workspace metadata, but no exact window/session binding;
- **guessed**: foreground app or recent application; display only as unknown and provide no action.

Supported conceptual targets are Apple Terminal, iTerm2, VS Code, Cursor, specific JetBrains products, the Codex/ChatGPT app, and Claude Desktop. `NSWorkspace` can activate a verified bundle. Opening an exact workspace/window requires a documented app URL/file-opening mechanism and remains capability-gated.

## 7. Design implications

- A1 must model `PARTIAL` and `UNKNOWN` explicitly; capability absence is normal.
- A2 should accept Claude HTTP hooks and a normalized Codex hook client without requiring either provider to expose sensitive transcript content.
- A3 should prefer App Server/official JSON streams for connected Codex sessions and use hooks/OTel for additional independent sessions; persisted state is recovery fallback.
- A4 must declare a minimum supported Claude version per mechanism. Current docs cannot be assumed on local 2.1.94.
- A8 shows no usage card field without a corresponding runtime capability/provenance.
- A9 remains observation-only except for a provider/source whose documented action channel is live and bound to the exact request.

## 8. Official sources

All sources are provider-owned and accessed 2026-09-24.

OpenAI:

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Advanced configuration and OTel](https://learn.chatgpt.com/docs/config-file/config-advanced)
- [Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Codex IDE](https://learn.chatgpt.com/docs/codex/ide)
- [Codex cloud](https://learn.chatgpt.com/docs/cloud)
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

Anthropic:

- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code monitoring and OTel](https://code.claude.com/docs/en/monitoring-usage)
- [CLI reference](https://code.claude.com/docs/en/cli-reference)
- [Claude directory/application data](https://code.claude.com/docs/en/claude-directory)
- [VS Code integration](https://code.claude.com/docs/en/ide-integrations)
- [JetBrains integration](https://code.claude.com/docs/en/jetbrains)
- [Claude Desktop](https://code.claude.com/docs/en/desktop)
- [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
- [Statusline schema](https://code.claude.com/docs/en/statusline)
- [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview)
- [Agent SDK streaming output](https://code.claude.com/docs/en/agent-sdk/streaming-output)

Local CLI help and sanitized filesystem/schema observations are primary evidence for installed-version claims. They have no URL; the exact commands and versions are recorded above.
