# Agent Workspace Execution Plan — 2026-09-27

Branch: `feature/agents-ui-overhaul`

This plan evolves as implementation findings land. Existing agent-ingestion/security invariants remain authoritative unless a concrete correctness defect requires a narrowly scoped change.

## Product objective

Turn the Agents tab into a persistent, high-density workspace that remains useful between sessions and can safely manage interactive Codex work without regressing DynamicIsland shell geometry, trackpad gestures, privacy, or provider authority.

## Regression noted — 2026-09-27

Observed on the current feature branch:
- Provider diagnostics showed Codex configured but awaiting first accepted event.
- Live Codex sessions were not appearing.
- Health counters showed rejected/dropped events with `Invalid event`.
- Root cause: after DynamicIsland restarts while an existing Codex session is already running, later official hook events can arrive without a fresh `SessionStart`; the coordinator requires a session lease to exist first and rejects those otherwise-valid events.
- Required fix: trusted official-hook activity may recover a missing local lease by inserting a coordinator-owned recovery-origin session bootstrap before the first active event. Generic/unverified producers must not gain this behavior.
- The temporary Preview dashboard is no longer part of the product direction and must be removed; standby usage placeholders may remain truthful.

## Phase 1 — Gesture-safe session scrolling

Goal: make the agent session workspace vertically scrollable without breaking existing two-finger island gestures elsewhere.

Plan:
- Keep usage/provider overview outside the scrolling session viewport.
- Register the exact session-scroll viewport with `IslandLayoutStore` in canonical panel-local coordinates.
- Route scroll sequences that begin inside that viewport to content.
- Latch ownership through the full gesture and momentum tail so a list scroll cannot turn into an island collapse mid-sequence.
- Preserve existing island swipe handling outside the registered viewport.
- Clear region/latch when Agents is hidden, island collapses, or content exits.
- Add routing/region tests.

Gate:
- Vertical two-finger scrolling inside the session viewport never triggers expand/collapse.
- Existing expanded gestures remain unchanged everywhere outside it.

## Phase 2 — Agents-specific expanded geometry

Goal: give Agents roughly 10% more room while preserving one canonical shell.

Plan:
- Add an expanded presentation profile owned by canonical geometry, not by the Agents view.
- Agents resolves approximately 1.10x expanded geometry; all other tabs stay at 1.00x.
- Morph the same shell entering/leaving Agents.
- Scale typography/components modestly rather than blindly scaling every value 10%.
- Respect notch geometry, Reduce Motion, and animation settings.

Gate:
- No second panel/shell.
- Leaving Agents restores exact standard expanded geometry.

## Phase 3 — Enclosed workspace + session selection

Goal: create a bounded scrollable session workspace beneath the fixed overview.

Plan:
- Active sessions first, recent sessions second.
- Add deterministic selected-session state.
- Preserve project grouping and attention precedence.
- Use DEBUG/test-only screenshot fixtures and deterministic synthetic data for multi-session inspection.
- Add subtle selection and useful session context.

Gate:
- Multiple projects/sessions are usable in one viewport.
- Selection survives updates when possible and falls back deterministically otherwise.

## Phase 4 — Embedded agent console UI

Goal: provide an in-island conversational/control surface without exposing hidden reasoning or unsafe raw output.

Plan:
- Selected-session structured transcript/activity timeline.
- Multiline prompt composer with selection, copy/paste, Cmd+Enter send, Shift+Enter newline.
- Interrupt/stop affordance while a managed turn is active.
- Acquire keyboard focus only when the composer is intentionally focused; release it on collapse/dismiss.
- DEBUG/test fixture consoles are inspectable but cannot execute real work.
- Render only provider-supported user-visible content and privacy-projected structured activity.

Gate:
- Composer is fully keyboard-usable without making normal island interaction steal focus.

## Phase 5 — Official Codex interactive control plane

Goal: manage Codex sessions from DynamicIsland through a supported control surface rather than GUI automation.

Plan:
- Verify the current official Codex app-server/control protocol before implementation.
- Introduce a provider-neutral interactive-provider interface.
- Distinguish managed sessions from externally observed sessions.
- Managed Codex sessions can start/resume turns, receive prompts, stream supported events, and interrupt.
- Existing hooks remain useful for observation and permission integration.
- No terminal keystroke injection or private credential scraping.

Gate:
- A Codex task can be started and followed up from DynamicIsland with authoritative session correlation.

## Phase 6 — Session-scoped auto-approve

Goal: let a user explicitly opt into uninterrupted approval handling for one controllable session.

Plan:
- Off by default.
- Optional safe-only policy only if authoritative structured semantics support it.
- Explicit all-for-this-session mode requires confirmation before first activation.
- Scope to exact provider/session/generation.
- Automatically disable on session end, generation change, disconnect, app restart, or explicit disable.
- Every automatic decision remains visible in activity history.
- Generic/unverified producers and unsupported providers never gain control.
- Never bypass macOS/system administrator dialogs.

Gate:
- Multiple genuine Codex permission requests can be auto-approved for one opted-in session without affecting any other session.

## Phase 7 — Integrated visual + interaction polish

Goal: finish the complete Agents workspace to the target quality level.

Plan:
- Fixed usage overview + bounded session workspace + selected-session console/composer.
- Refine typography, row density, session selection, approval controls, auto-approve status, idle/recent live states, DEBUG/test screenshot fixtures, and subtle attention glow.
- Expand deterministic screenshots for scroll, selection, console, auto-approve, and long histories.
- Run full build/test/package/signature validation and real-device manual checks.

Gate:
- No release-blocking UI, gesture, control, privacy, or security issues remain.

## Frozen invariants

Unless a concrete defect is found, preserve:
- normalized event ingestion and lifecycle truth;
- session identity `(provider, native session ID, generation)`;
- authority/capability evidence;
- stale-generation rejection;
- privacy projection;
- authenticated HMAC bridge and replay protection;
- provider-specific approval authority;
- one collapsed + one expanded island state;
- one canonical shell/panel.

## Iteration rule

Each phase gets:
1. a limited hot-path source audit,
2. a focused implementation commit,
3. focused tests,
4. validation before broadening scope.

If a phase uncovers a prerequisite, add it to this plan before expanding scope.
