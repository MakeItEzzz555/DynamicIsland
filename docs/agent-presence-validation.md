# Agent Presence, Voice and Visual Effects validation

Checkpoint: `87232da600581f840bf9887a4a2a77d61d03c781`, branch
`feature/agents-ui-overhaul-continuation`. Source tree clean before audit;
unrelated Graphify, Claude and research files left untouched.

## Checkpoint audit (before edits)

| Requirement | Classification | Evidence / action |
| --- | --- | --- |
| Native single shell, resolver, store, identity architecture, sidecars | Complete | Checkpoint changes presentation only; preserve architecture. |
| Nine orb drawings, compact sizing, speed | Complete | Nine Canvas branches and normalized speed; enlarge preview to 64pt. |
| Domain and activity mapping | Partial | All domain cases handled; hints ignored during tool execution and some thinking cases; stale hints need filtering. |
| Terminal/static orb, accessibility | Partial | Terminal pause exists; label accidentally literal; visibility/inactive pause missing. |
| Avatar shapes, face, basic controls/accessories | Partial | 18 cases preserved; square/round glasses identical, actual shape preference ignored. |
| Deterministic avatar identity | Regression-risk | Seed is literal text, giving every session the same avatar. |
| Advanced avatar lighting, texture, motion | Missing | No configuration or renderer for requested controls. |
| Voice recorder, meter, permission/lifecycle | Complete | Existing AVAudioRecorder metering, no second capture; errors remove activities. |
| Voice sensitivity, gate, attack/release, palettes | Complete | Envelope implementation and eight native palettes. |
| Processing beam | Partial | Moves but samples stopped microphone; no distinct focused geometry. |
| Voice animation/static/inactive behavior | Partial | Reduce Motion and toggle pause; inactive/visibility pause missing. |
| Metal presets, rim, glow, accessibility | Complete | Native SwiftUI gradients; no GPU Metal dependency required. |
| Entire send hit target, disabled/press | Regression-risk | Label 30pt inside 34pt wrapper; simultaneous drag; disabled metal still ticks. |
| Real compact routine/attention presence | Partial | Production views wired; provider disappears behind glyph and project, redundant status dot. |
| Appearance organization, persistence/reset, isolated previews | Partial | Existing AppSettings JSON and isolated previews work; Thinking Orb heading and advanced controls missing. |
| Animation cost | Regression-risk | Local TimelineViews avoid root publications but idle/list and disabled controls tick; add pause and lower compact cadence. |
| Accessibility and keyboard/approval behavior | Partial | Command-Return retained; fix literal label and disable all decorative movement with Reduce Motion. |
| Tests and native visual validation | Partial | Basic mapping/envelope/persistence tests exist; identity test cannot catch constant seed; broaden behavioral and interaction checks. |

## Native implementation decisions

Preserve the checkpoint's SwiftUI/Canvas rendering and AVAudioRecorder meter.
Keep state mapping presentation-only. Use additive optional avatar configuration
so checkpoint JSON remains decodable. Texture is a bounded, deterministic 2D
fiber drawing, with controls describing its visible geometry; lighting is native
gradient/rim/shadow treatment, not a 3D physical simulation. No dependency,
transport, signing, entitlement or domain persistence changes.

## Final validation (2026-10-02)

- Full `swift test`: **1,567 passed / 0 failed / 33 skipped**, 1,600 total.
  Skips are opt-in live providers/approvals, system permissions, performance
  measurement and snapshot exports. No tests removed or weakened.
- Opt-in native acceptance: **7 passed / 0 failed / 1 skipped**. Enables
  Agents performance, AgentVisual/AgentUI/Phase5 snapshots, sidecar and
  notched/notchless orbit snapshots. The real microphone test skips because
  authorization is undetermined (`0`) for the test process; an input device
  (MacBook Pro Microphone) is present. No permission prompt was forced.
- `swift build -c release`: succeeds. `Scripts/package_app.sh`: succeeds with
  its existing ad-hoc signing. `codesign --verify --deep --strict --verbose=2`
  validates the app and all three relay helpers after clearing generated
  extended attributes. The iCloud-backed output directory can reattach
  `com.apple.FinderInfo`; clear bundle metadata before verification/export.
  Signing identity, entitlements and packaging source remain unchanged.
- Graphify AST update succeeds; generated graph files intentionally unstaged.

Behavioral regressions cover all domain states, active activity hints,
managed connection/submission, terminal/wait motion policy, stale completed
hints, compatible checkpoint JSON, settings persistence/reset, advanced
clamping, invalid accessory colors, recorder-only metering, cancellation
cleanup and mic-independent processing geometry. Native NSWindow mouse events
activate Send at its center, four rim points and four padded corners; disabled
Send never submits and the static fallback submits correctly. Existing
Command-Return, workflow, approvals, resolver and transcript tests pass.

Native decisions: compact cadence 15fps; ordinary session rows static;
metal animation only during enabled hover; lifecycle pausing uses AppKit
application notifications, not SwiftUI scenePhase (this app has no SwiftUI
scene). Voice remains reactive at 8fps while inactive. Texture uses at most
120 static fibers. No decorative ticks publish to domain/root stores.
Reduce Motion disables pointer turn, hover/press scaling and continuous
decorative motion. Compact jumps and squash/stretch are bounded.

The existing 36-session performance harness passes. For 200 streamed deltas:
45 transcript publications, 6 dashboard evaluations, 468.4ms main-thread CPU
over 1718.6ms elapsed. Typing 38 characters uses 136.9ms main-thread CPU.
Leaving the page produces zero dashboard/console body evaluations. These
are local debug measurements, not a claimed before/after speedup.

Review outputs (temporary, not committed):
`/tmp/dynamicisland-presence-visual/`, `/tmp/dynamicisland-presence-ui/`,
`/tmp/dynamicisland-presence-sidecars/`, `/tmp/dynamicisland-presence-layout/`.
Inspected native renders include nine 64pt orb states, eighteen avatars,
eight voice palettes, tighter processing versus listening beams, all send
presets/disabled state, compact working/completed/failed/attention,
multi-session/long-transcript layouts, and Reduce Motion.

Actual rebuilt app launched on Built-in Retina Display (1147×745 points,
hardware-notch safe inset 24pt). Inspected collapsed presence with battery
sidecar, expanded Agents, provider switching, transcript scroll and isolated
Settings sample content through native screenshots and AX controls.

Remaining acceptance: real microphone amplitude and the full
collapsed → listening → processing → agent result sequence require microphone
authorization and a controlled live provider session. Live provider-specific
thinking/planning/search/tool/command/approval transitions were covered by
production-view renders and lifecycle tests, not all manually induced in
the running app. An external notchless display was unavailable; its layout
was simulated. OS-level Reduce Motion and prolonged hover/transition/flicker
soak still need a human hardware acceptance pass. No automatic voice-to-agent
submission was added to the existing voice transcription workflow.

Recommended next phase: **Live Codex/Claude + Microphone End-to-End Acceptance**,
including both complete shell transition sequences and prolonged animation/
transcript-scroll checks before release promotion.
