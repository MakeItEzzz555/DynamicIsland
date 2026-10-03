# Agents workspace architecture

Checkpoint phase: October 3, 2026. Branch `feature/agents-ui-overhaul-continuation`.

## Surface roles

DynamicIsland still has only the persistent `collapsed` and `expanded` shells. Agents workspace emphasis is an internal expanded-layout allocation, not a third island state.

- **Primary chat:** selected managed/observed session transcript. A semantic Libraries.dev ThinkingOrb is the agent/activity glyph. The active surface is wrapped by the native Libraries.dev BorderBeam. Model and reasoning-effort controls live in this surface.
- **Right workspace:** one retained surface with **Feed** and **Terminal** pages. Page switching changes presentation only; the terminal process controller is not recreated.
- **Feed:** curated operational traffic from Codex and Claude. Stable Libraries.dev BotAvatar identity is derived from `provider + native session ID + generation`. Approvals, denials, command/tool lifecycles, provider state changes, interruptions and terminal outcomes belong here; transcript text does not.
- **Terminal:** the existing embedded terminal process/controller. Selecting Terminal focuses/reveals the retained terminal; changing pages must not restart the process.
- **Usage strip:** three paired categories, each Codex then Claude: 5-hour remaining, weekly remaining, and selected-session context used.

## Ownership

Provider/session truth remains in the existing ingestion/store path. Workspace presentation never creates a second provider state machine.

- Session identity: `provider + native session ID + generation`.
- Approval authority: exact provider request. UI says Approved/Denied only after Codex `serverRequest/resolved` or Claude `tool_result`; timeout, shutdown and transport failure cannot manufacture a decision.
- Feed history is bounded in memory and stores semantic summaries/IDs, not prompts, transcripts, filesystem paths or secrets.
- Chat/Terminal interaction intent and Feed/Terminal workspace selection are presentation state retained by AppDelegate across shell remounts.
- Terminal process lifetime is independent from visual page visibility.
- Record Activities remains a separate opt-in bounded persistence feature; the Feed does not broaden it.

## Motion

The workspace uses the installed transitions.dev guidance:
- tab/content handoff: 250 ms, smooth-out cubic-bezier equivalent;
- internal width allocation: 300 ms, smooth-out;
- feed insertion: 8 pt + opacity;
- Reduce Motion removes spatial/decorative transitions.

The ThinkingOrb communicates *what* an agent is doing. BorderBeam communicates that the selected chat surface is actively processing. BotAvatar identifies actors in the operational Feed. These roles are intentionally separate.

## Rendering and performance

BorderBeam is adapted from the official MIT Libraries.dev SwiftUI port at revision `d06640864eb4adc2fe240f899a44ee6210779782`. The package's shader/spec tables are preserved. On macOS/SwiftPM the shader is runtime-compiled once per process through Metal because the local toolchain does not compile the upstream stitchable resource in this package configuration.

Beam and avatar/orb animation are presentation-local; they do not publish provider/domain state. Hidden right-workspace pages are retained for identity but marked inactive so visual animation can pause. Feed updates are isolated from transcript publication.

## Acceptance boundary

Automated/fixture evidence validates layout, provider isolation, exact approval ownership, usage grouping, gesture routing, Beam GPU execution, performance publication isolation, bounded lifecycle teardown and deterministic review states. It does not substitute for final human packaged pointer/motion/Reduce Motion inspection or quota-blocked live providers.
