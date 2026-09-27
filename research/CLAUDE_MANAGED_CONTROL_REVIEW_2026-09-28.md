# Claude Managed Control Review — 2026-09-28

## Scope

This review covers authoritative local Claude control for DynamicIsland. Production Claude managed control remains disabled in this phase. No Terminal keystroke automation, AppleScript typing, screen scraping, cookie scraping, or undocumented private IPC is accepted.

Installed baseline inspected on the real Mac:

- Claude Code 2.1.283
- CLI exposes resume/session/model selection, stream-json input/output, partial messages, host permission prompts, background sessions, and stop-related commands.

Current official Claude documentation identifies the Claude Agent SDK as the supported programmable Claude Code integration boundary. The SDK is available for TypeScript/Python; the official docs also describe subprocess CLI integration for other languages, but the SDK is preferred for typed lifecycle, permissions, interruption, session, and model control.

Official references:
- https://code.claude.com/docs/en/agent-sdk/overview
- https://code.claude.com/docs/en/agent-sdk/sessions
- https://code.claude.com/docs/en/agent-sdk/user-input
- https://code.claude.com/docs/en/agent-sdk/streaming-output

## Capability matrix

| Capability | Status | Official mechanism / finding |
| --- | --- | --- |
| Start | SUPPORTED | Agent SDK query/client session |
| Resume | SUPPORTED | SDK resume by session ID |
| Submit | SUPPORTED | streaming input / SDK query |
| Interrupt | SUPPORTED | SDK query/client interruption control |
| Stream visible output | SUPPORTED | typed assistant messages + partial streaming |
| History | SUPPORTED | persisted sessions / official session APIs |
| Tool events | SUPPORTED | typed SDK assistant/tool events |
| Approval resolution | SUPPORTED | host canUseTool / permission callback |
| Model discovery/selection | SUPPORTED | SDK-supported model inventory/control where exposed by current SDK |
| Usage | PARTIAL | per-result/token/cost evidence; not equivalent to Codex idle 5h/weekly quota |
| Context | SUPPORTED/PARTIAL | SDK context usage where supported; selected-session scoped |

## Production decision

Do not enable the current experimental Swift ClaudeInteractiveProvider in the app merely because CLI stream-json exists. The preferred production design is:

ClaudeInteractiveProvider
→ bounded authenticated local helper
→ pinned official Claude Agent SDK
→ Claude Code process/session

The helper should own typed SDK query/client lifecycle, stream only bounded provider-neutral events, and never forward raw stderr or hidden reasoning.

The existing experimental provider code may remain as research scaffolding, but it is not registered by DynamicIslandApp until the SDK-helper boundary and real-device lifecycle/approval tests are complete.

## Identity and safety

- Claude SDK session UUID → AgentSessionID.nativeID.
- Resume must preserve exact UUID unless the user explicitly forks.
- User-visible text may stream; thinking/reasoning blocks must be excluded.
- Approval callback must correlate exact provider/session/request and resolve once.
- No Claude account quota should be fabricated from Codex or inferred from unrelated telemetry.
