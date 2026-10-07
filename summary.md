# Agent Interaction Phase Summary (Phase 5)

- Branch: `feature/agents-ui-overhaul-continuation`; PR #24 remains a Draft and was not merged or pushed.
- Camera: explicit user intent owns capture; passive SwiftUI lifecycle cannot restart the camera after an explicit close.
- Approvals: managed Approve/Deny are delivered to the exact provider request and shown as Approved/Denied only after the provider's exact acknowledgement (Codex `serverRequest/resolved`, Claude `tool_result`). No wall-clock expiry; shutdown, timeout and transport failure never write a decision; unconfirmed deliveries stay visible as failed. External/observed sessions remain observation-only.
- Performance: transcript publication isolated from Agents chrome and coalesced; streaming main-thread cost 9.2x lower, typing no longer re-renders the transcript; measured with `AgentsPerformanceHarnessTests` (`DYNAMIC_ISLAND_AGENT_PERF=1`).
- Usage/provider controls: larger 5h/Week gauges, icon + name provider buttons.
- Record Activities: opt-in, local, bounded (14 days / 20 MB) normalized-event JSON Lines; no prompts, transcripts, paths or secrets.
- Details: `research/AGENTS_PHASE5_2026-10-01.md`.
