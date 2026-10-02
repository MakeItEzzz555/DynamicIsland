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


## Live End-to-End Acceptance (2026-10-02–03)

Starting HEAD verified: `ae13216f9e87a79fc190daff198427fcf15bd07e` on
`feature/agents-ui-overhaul-continuation`. This is **partial acceptance**, not
release promotion. Unrelated local files and generated Graphify data remain
unstaged. No provider credentials, transports, session identity, signing
policy, entitlements, dependencies or visual rendering were changed.

### Machine and builds

Apple Silicon MacBook Pro, arm64, macOS 15.7.4 (24G517); built-in hardware-notch
Retina display, 1147×745 logical points, 24pt safe top inset. Runtime inspection
used the native packaged Release application, AX controls and desktop captures.
Real-provider tests used Debug XCTest with the installed authenticated CLIs.
Snapshots and the 36-session performance fixture are explicitly simulated.
An external notchless display was unavailable.

### Real microphone and permission evidence

The previously packaged app actually reached **Recording → Transcribing →
No speech was recognized**, using its existing AVAudioRecorder and on-device
Speech path. Stop and Cancel were visible during their appropriate phases;
the final recoverable error showed Record again, with no stale LIVE state.
This was ambient/silence input, **not** an accepted quiet/normal/loud human
speech sample. Successful transcription and speech-envelope tuning are still
unproven. No second capture session, synthetic audio, privacy reset or consent
bypass was used.

Bundle ID remains `com.local.dynamicisland`; microphone/Speech usage
explanations are present. Packaging retains its existing local ad-hoc policy
and no hardened runtime. The rebuilt package launched successfully and Record
reached **Waiting for permission** with a real macOS microphone consent dialog.
Automation stopped at that dialog and asked the user to choose Allow/Don't
Allow. An ad-hoc rebuild requiring consent again is documented by the existing
packaging script. No entitlement/signing defect was established.

XCTest's separate process still reports microphone authorization `0` and
legitimately skips live capture, despite the input device being present.
Development-launch recording, denied/unavailable hardware, successful speech
completion and cancellation during actual transcription have not received
complete manual acceptance. Automated lifecycle/cleanup tests remain passing.

### Real Codex / Claude and session evidence

The live controller harness starts **actual installed providers**, writes only
an owned temporary project, and consumes their real normalized events. It does
not inject session states or activity hints. Codex passed file creation with
exact contents, interruption, and resume from a fresh controller into the exact
native session. Observed normalized states: **idle, working, runningCommand,
waitingForApproval, completed, interrupted**. The runtime logger records
identity/generation, pure orb mapping and actual activity kind/status, including
short-lived publications between polling intervals. Working/command mapped to
working; idle/wait/terminal states mapped to static breathing. Connection and
resume were real operations; separate thinking/planning/search/composing/plan
ready event transitions were not naturally observed and are not claimed.

A second real Codex test proved native app-server **deny → complete → allow →
complete**, exact session/request targeting and duplicate resolution returning
missing. Denied file stayed absent; allowed file had exact requested contents;
the store recorded denied/approved and cleared pending approvals. To elicit
native approvals deterministically it selects the offered `gpt-5.5` model and
uses per-process read-only/on-request/user-review overrides, with external
code-mode/hooks/guardian disabled **only for that test subprocess**. Production
launch configuration and the user's CLI config remain unchanged. Earlier probes
using the default external tool host did not yield native pending requests to
the isolated test controller; those probes were not counted as passes.

Claude started a real session and returned **You've hit your weekly limit**,
with reset **Oct 4 at 9pm (Asia/Nicosia)**. The original both-provider run failed
its Claude file/interrupt/resume assertions for that external quota. It also
exposed an ambiguous Codex test prompt whose trailing period was written into
the file; delimiters now make the exact expected contents unambiguous, without
relaxing the assertion. Final Codex-only reruns explicitly exclude Claude.
Claude task execution, successful resume and live approvals remain blocked.

The running app ingested this real root Codex session, real tool/approval events
and expanded transcript. Provider buttons, compact activity/battery sidecar,
attention and expanded navigation were inspected. Independent real Codex
acceptance sessions retained their native identity/generation across resume.
A successful simultaneous Codex + Claude workload, completion arbitration,
selection stability across multiple active providers, and every step of the
full shell transition sequence are **not fully accepted**. Test-generated native
view fixtures cover them separately; they are not substitutes for live evidence.

### Reproduced defect and scoped fix

During actual recording, collapsed presence continued showing routine agent
**Awaiting update**, hiding the microphone visualization. Resolver policy gave
agent activity priority 130, recording 125 and transcription 105. The existing
resolver now gives explicitly active recording minimum 140 and transcription
135. It preserves normal sidecars and source-owned cleanup; removing voice
restores the agent. A regression test uses production recording/transcription
activities, checks both input orders and unchanged sidecars. Blocking attention
policy is preserved. No shell/visual/controller rewrite was performed.

Final rebuilt microphone/processing coexistence requires consent and a human
speech sample; the policy fix is automated-test verified, not yet fully accepted
against the rebuilt package's real beam.

### Actual Reduce Motion and sustained runtime

The real System Settings Accessibility → Display switch was inspected OFF,
then switched ON. A fresh native NSWorkspace query confirmed `true`; the running
app remained usable without restart, displaying Tools/Voice, Ready, Record and
textual status. This is actual OS-setting evidence, not an injected environment.
Detailed pointer/jump/spin/Metal/beam motion acceptance remains limited by the
pending microphone consent and automation interference. Static rendering and
motion-policy tests separately pass. The original OFF setting is restored
before handoff; no unrelated accessibility preference is changed.

The original packaged app stayed running for **at least 76 minutes**, including
real root activity, approval/transcript traffic, collapsed/expanded navigation,
recording and processing. An early five-second sample showed physical footprint
56.9MiB (peak 58.3MiB), with substantial main-thread idle waiting and no sampled
hang. At ~7 minutes ps reported 24% CPU / 91,776KiB RSS; at ~76 minutes, 30.1% /
174,640KiB after transcript/session and Speech work. These are observations,
**not proof of a leak or a no-regression soak pass**; workloads and retained data
changed. A controlled post-cleanup plateau and repeated transition/flicker/
scroll soak are still needed. No speculative performance refactor was made.

Final simulated performance acceptance (36 sessions) passed: 200 streamed deltas,
47 transcript publications, 6 dashboard evaluations, 631.1ms main-thread CPU /
1896ms elapsed. Typing 38 keys: 141.3ms CPU / 250.6ms elapsed. Leaving the page
produced no dashboard/console evaluations. Results are local Debug measurements,
not a claimed before/after improvement.

### Final automated and release validation

- Full suite: **1,568 passed / 0 failed / 34 skipped**, 1,602 total. Compared with
  checkpoint, one passing voice/agent resolver regression and one opt-in Codex
  approval test were added. No test was deleted or weakened.
- Native opt-in acceptance: **7 passed / 0 failed / 1 skipped**, 8 total. The
  microphone test skips for the XCTest process authorization described above.
- Final selected real Codex acceptance: **2 passed / 0 failed / 1 skipped** across
  the live session and native approval runs; excluded Claude is the skip. The
  earlier genuine Claude quota failure remains recorded above, not relabeled.
- After the source fix, targeted resolver/voice tests: **53 passed / 0 failed /
  0 skipped**. Graphify AST update succeeded; outputs remain unstaged.
- Safely cleaned generated SwiftPM products with `swift package clean`. Fresh
  Release compilation of all four products passed. Packaging's final ad-hoc
  signature initially failed because iCloud reattached `com.apple.FinderInfo`
  to the generated app. Established generated-bundle-only metadata cleanup
  and re-signing recovered it. Deep strict signature verification then passed
  for the app and all three helpers; a temporary export also passed verification.
  No signing-policy changes were made. Rebuilt packaged app launched and its
  native Voice page/OS consent path were smoke-tested.
- Final native visual review regenerated and inspected: all nine orbs, avatar,
  listening versus focused processing beam, metal send; remaining avatar/
  palette/settings and UI/layout exports are available as simulated artifacts.

Evidence is temporary, not committed: `/tmp/dynamicisland-live-acceptance/`
(native-final.log, performance-final.json, visual-final/, ui-final/, sidecars-final/,
layout-final/, processing-expanded.png, os-reduce-motion-on.png,
rebuilt-microphone-consent.png and signed package export).
Full-suite log: `/tmp/dynamicisland-final-review-full.log`.

### Remaining acceptance dependencies

**BLOCKED — external acceptance dependency**: fresh packaged microphone OS
consent, a controlled human speech sample/successful transcription, and Claude
quota reset. Pending human input must not be replaced with fabricated audio or
mock provider states. Full voice → result → agent workflow, live multi-provider
success and approval differences, natural planning/search/composing/plan-ready,
physical microphone-unavailable/error paths, detailed OS-motion visual acceptance
and a controlled sustained performance plateau remain unaccepted.

Recommended next phase: **Close live acceptance blockers and complete the human
speech, Claude/multi-provider, detailed motion and controlled soak pass before
release promotion.** Keep the PR Draft and do not merge.
