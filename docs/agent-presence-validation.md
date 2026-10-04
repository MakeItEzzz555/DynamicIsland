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

## Live Acceptance Closure & Release Gate — 2026-10-03

Baseline: `8b2e0b013ea748fd7068a68cd2bdc7b56a9f5c38`, branch
`feature/agents-ui-overhaul-continuation`. Fetch confirmed the same remote
checkpoint; no newer work was reset/rebased. Environment: macOS 15.7.4
(24G517), arm64, built-in Retina hardware notch, 1147×745 logical display,
24pt safe-area top. Debug XCTest and the checkpoint/final Release packages
are distinguished below. PR #24 remains open and Draft. This is a verified
fix checkpoint, **not release promotion or a claim that every live gate closed**.

### Skills and native motion acceptance

Actively applied installed `transitions-dev` and `transitions-polish`, including
Card Resize, Panel Reveal and Plus Menu Morph guidance: preserve one surface,
match timing to interaction, hand off content after shell geometry commits,
keep interruption/replay cleanup deterministic, maintain a stable hover target,
and suppress decorative travel under Reduce Motion. Audited existing native
shell/content timing and cancellation paths and applied these checks to the
device navigation workload. Existing 0.40s normal shell/0.24s reduced shell
timings and content staging were retained; CSS values were not transplanted
into SwiftUI. Graphify, accessibility-tester, qa-expert, performance-engineer
and ui-designer guidance supported scoped inspection, text feedback, evidence
classification, repeatable workloads and existing visual-system consistency.
No framework/dependency or animation redesign was introduced.

**PASS — live (representative endpoints)**: checkpoint package repeatedly
expanded/collapsed and switched Island → Agents → Tools with real root Codex
activity. Two 40-cycle batches produced 79 complete cycles; one first-batch
cycle had no successful AX actions during competing pointer/approval activity.
The second batch completed all 120 section actions. Compact presence retained
its battery sidecar; expanded provider/session rows and transcript were visible.
This checks endpoints and repeated usability, not frame-by-frame timing.

**PASS — live (OS propagation)**: actual Accessibility → Display Reduce Motion
OFF → ON → OFF. Fresh NSWorkspace queries confirmed ON without restarting the
app and final restored OFF. ON retained textual agent status and actual
Listening/LIVE recording feedback with a minimal beam. Recording started, but
the automated cancel/navigation sequence was interrupted by other pointer
activity; successful cleanup of that particular sequence is not claimed.
The checkpoint process subsequently exited before the rebuilt package launched.
**NOT VERIFIED**: uninterrupted detailed jank/opacity/hover/pointer-motion
acceptance for every requested transition. Existing motion/layout/Reduce Motion
tests and regenerated images remain **PASS — automated/simulated** evidence.

### Microphone and recording evidence

**PASS — live, checkpoint Release package**: real microphone recording was
started using production Voice controls; collapsed Listening/LIVE and the beam
remained visible while ordinary Codex activity existed. Stop reached actual
no-speech recovery and the next Record control was available. A separate repeated
record/cancel cycle successfully invoked Record and Cancel. No generated audio
or second capture session was used. Ambient/silence capture is not a controlled
human speech sample. The requested phrase/normal-versus-louder speech response
was not supplied, so amplitude calibration and successful controlled speech
transcription remain **BLOCKED — external acceptance dependency: human input**.

Final rebuilt Release package launched (PID 90279) and real AX Tools → Voice →
Record succeeded, reaching **Waiting for permission**. macOS then displayed a
Keychain dialog for existing `com.local.dynamicisland.agent-bridge` access; a
local human Allow/Deny decision was requested. No password, credential, consent,
privacy preference or Keychain policy was changed by automation.
**BLOCKED — external acceptance dependency: OS Keychain/permission decision**
for final rebuilt recording/transcription smoke acceptance. No success is
inferred from the earlier binary's permission grant. A premature helper attempt
found no running app during relaunch and failed; it was a harness launch-order
failure, not a product pass. The final packaged process was explicitly confirmed
before the successful controls/permission attempt.

**BLOCKED — external acceptance dependency: development microphone consent**:
the existing opt-in production-recorder test reported authorization raw value 0
(not determined) for XCTest and skipped without prompting. Debug app microphone
launch is **NOT VERIFIED**; this test-process result is not equivalent to it.

**PASS — live, development ScreenCaptureKit acceptance: 5/0/0**. Existing tests
captured actual display, static test window and selected area; validated movie
dimensions/duration, pause/resume excluding paused time, and system-audio track
with 98 written audio samples. This is real capture through production recording
controllers in the Debug test process. Full packaged screen-recording + agent +
microphone shell coexistence is **NOT VERIFIED**, not inferred from these tests.

### Provider evidence

**PASS — live, real Codex: 2 passed / 0 failed / 1 skipped** (excluded Claude).
Actual app-server creation, command/file output, normalized idle/working/command/
approval/completed/interrupted states, stop and exact-native-session resume
passed. Native deny left the denied file absent and request denied; native allow
created only the intended file and marked its exact request approved. Native ID
and generation stayed stable across resume. These are real provider events,
although driven by the existing acceptance test controller rather than manual
composer entry. Production approval policy/transport/identity were unchanged.
The running packaged app separately displayed real root Codex activity and
discovered acceptance-session rows. Natural thinking/planning/search/composing/
plan-ready transitions were not observed and remain **NOT VERIFIED — live**.

**BLOCKED — external acceptance dependency: Claude quota**. A real read-only
Haiku request returned HTTP/API 429: “You've hit your weekly limit”, resetting
Oct 4 at 9pm (Asia/Nicosia). No repeated quota retries or credential changes.
Successful Claude execution/resume and concurrent Codex + Claude acceptance
remain blocked. Fixture provider/session switching is classified separately.

### Controlled memory follow-up

Repeated native device workload: each cycle expands if needed, switches Agents,
Island and Tools, then leaves/collapses; real root agent traffic continues.
Each 40-cycle batch lasted approximately 208s including settling. Checkpoint
package RSS KiB at cycles 0/10/20/30/40:

| Batch | 0 | 10 | 20 | 30 | 40 |
| --- | ---: | ---: | ---: | ---: | ---: |
| First | 201072 | 204496 | 210320 | 214784 | 220544 |
| Second | 221152 | 225824 | 231696 | 241824 | 248672 |

Instantaneous CPU samples were 22.7–40.1%. RSS did not settle within those batches.
A subsequent 3s process sample reported 132.8MiB physical footprint, peak
174.3MiB, and most main-thread samples waiting in mach messaging. RSS and physical
footprint are different metrics; neither is an allocation-retention diagnosis.
A restricted `leaks` scan reported 18 objects/2272 bytes (CoreVideo,
CoreAnimation and strings), exit 1, with read-only inspection restrictions.
That small report does not explain the larger RSS changes. Real session/history,
ongoing events and SwiftUI/AppKit/media caches confound attribution.
**NOT VERIFIED: whole-app sustained memory plateau/unbounded-retention closure.**
No speculative session or animation optimization was performed.

**PASS — automated/simulated, bounded lifecycle soak: 1/0/0**, 110 cycles/151s:
32 fixed sessions (the established per-provider discovery cap), replaced 80-entry
transcript, streamed fixture deltas, completion/interruption, two-session
switching, production dashboard remounts and fixture-level listening/processing
beam mounts. Physical footprint MiB at cycles 10/30/50/70/90/110:
45.2/46.4/47.3/47.3/47.2/47.7; after teardown 43.7. Controller/subscriptions
released. This establishes bounded behavior for this workload, not a no-leak
claim for the full shell. The initial new harness incorrectly expected 36
single-provider sessions despite the existing discovery cap; its failed run
was rejected. Setup now uses that canonical cap with exact-count assertions;
production limits and existing tests were not relaxed. Measurement JSON does
not hardcode a pass independent of XCTest results.

The combined native acceptance's streaming measurement was slower (10,695ms
main-thread CPU, 200 publications/9 dashboard evaluations). An isolated repeat
of the unchanged workload passed in 6.19s: 200 deltas, 44 transcript publications,
6 dashboard evaluations, 391ms CPU/1625.5ms streaming wall time; typing 38 keys
144.3ms CPU/251.4ms wall. Leaving produced no dashboard/console evaluations.
This repeat is consistent with baseline coalescing; the mixed-run measurement
is retained rather than hidden. Competing native windows/OS interactions make
cross-run timing attribution unreliable. No speculative performance fix followed.

### Scoped defects and fixes

1. Permission/preparation/recovery published no compact voice activity, letting
   ordinary agent status take its place. Added presentation-only static
   `voiceStatus` through the existing resolver/generic compact route: textual
   permission/preparation notice and an 8s recovery notice, with no LIVE beam or
   fake recorder. Progress/cancel removes it; generation guarding prevents stale
   cleanup after retry. Existing recording/transcription priority is preserved,
   as are blocking agent attention, sidecars and the single shell. Resolver and
   controller regressions pass; final device permission remains externally blocked.
2. SpeechFrameworkTranscriber kept its last task/request/continuation until
   cancel, while controller success/failure did not release them. Terminal
   current-generation success/failure now calls the existing cancellation cleanup.
   Tests verify cleanup, static recovery expiry, permission cancellation and no
   accidental capture. This fixes bounded last-recognition retention; it does
   not establish that recognition caused the earlier whole-app memory growth.

### Final validation and release gate

- Full suite: **1,570 passed / 0 failed / 35 skipped**, 1,605 total. Two new voice
  regressions pass; the new opt-in soak adds one ordinary-suite skip and passes
  when enabled. No existing test deleted or weakened.
- Focused resolver/voice: **55/0/0**; voice rerun after resource cleanup **29/0/0**.
- Native opt-in acceptance: **7/0/1**; the microphone consent skip above is real.
- Selected real Codex: **2/0/1**; real development screen capture: **5/0/0**;
  bounded fixture soak: **1/0/0**. These sets overlap other suites; do not sum them.
- Release compilation and project packaging pass. Synced-directory FinderInfo
  reappeared and initially failed strict verification. Generated-bundle-only
  xattr cleanup followed immediately by unchanged ad-hoc signing recovered it.
  App plus all three helpers and temporary exported app passed deep strict
  verification. No entitlements/signing policy/dependencies changed.
- Final package launch and Tools/Voice/Record controls pass; terminal microphone
  smoke remains blocked at the OS interaction above. Graphify AST update passed;
  generated graph/research/build/skill files remain outside the phase commit.

Temporary evidence: `/tmp/dynamicisland-closure/` (`full.log`, `native-final.log`,
`development-recording.log`, `soak-final.json`, `performance-final.json`,
`performance-isolated.json`, `packaged-soak.sample`, regenerated `visual-final/`, `ui-final/`, `sidecars-final/`,
and strictly verified package export). Native screenshots additionally reside
under `/tmp/dynamicisland-live-acceptance/`. No recordings/build artifacts are
committed. Remaining release gates: human consent/speech, Claude/concurrent
provider success, uninterrupted detailed motion and whole-app memory follow-up.
Recommended next phase: **Human-assisted live release acceptance and allocation
profiling of the full shell before release promotion**. Keep PR Draft/unmerged.


## Phase 2 — Whole-App Memory Closure + Human-Assisted Release Acceptance

October 3, 2026. Baseline/remote: `907da403e1b67e3c2999e794cbe302fa4d5e133d`,
branch `feature/agents-ui-overhaul-continuation`. No newer commits were present
after fetch. Environment: MacBookPro18,3, Apple M1 Pro (8 cores), 32 GB RAM,
macOS 15.7.4 (24G517), hardware notch, 1147×745 logical display.
All unrelated graph/cache/research/skill/user files remain outside this commit.

### Whole-app verdict and controlled workload

**PASS — live: bounded allocation for the measured fixed whole-app workload.**
This is decision B for these measurements, not a universal no-leak claim.
Repeated shell/section mounts reached a substantially flatter RSS range after
warm-up; native malloc object counts decreased. No reproducible unbounded
ownership defect was isolated, so no production cache flushing, lifecycle
rewrite or speculative allocation optimization was made. Unbounded session
creation, every media/capture/provider path, and a much longer identical
workload remain **NOT VERIFIED**.

Measurements target actual Release packaged process PID 90279, launched at
04:34. Each cycle uses production input/AX controls: expand if necessary,
Agents → Island → Tools, Escape/cursor leave, then settle. Three batches of
20 cycles include 20-second batch idle periods and a final 60-second cleanup
idle. The repeat completed **60/60 cycles in 386.74 seconds**, with one AX
window throughout. Real root Codex activity continued; no fixture session or
domain-state injection was used. This is UI idle, not a claim of zero ongoing
agent/audio work. Later native FD inspection confirmed an existing microphone
recording, created at 04:36, remained active during the workload. The workload
therefore also includes sustained recorder/metering presence, but neither
controlled speech nor a fresh recording lifecycle is inferred from that fact.

| Checkpoint | RSS KiB | Physical footprint MiB |
| --- | ---: | ---: |
| Repeat initial | 207936 | 108.49 |
| Initial collapsed idle | 207936 | 109.57 |
| Batch 1 cycle 10 | 208032 | 110.03 |
| Batch 1 cycle 20 | 208144 | 109.91 |
| Batch 1 idle | 208144 | 110.13 |
| Batch 2 cycle 10 | 208176 | 109.16 |
| Batch 2 cycle 20 | 212832 | 111.02 |
| Batch 2 idle | 209888 | 111.14 |
| Batch 3 cycle 10 | 208032 | 111.24 |
| Batch 3 cycle 20 | 208048 | 111.25 |
| Batch 3 idle | 208048 | 111.80 |
| Post-cleanup | 208048 | 111.55 |
| Final 60-second idle | 211280 | 111.52 |

Repeat RSS range: 203.1–207.8 MiB; final 206.3 MiB. Physical footprint
rose about 3 MiB and flattened near 111.5 MiB rather than repeating the
earlier 40-cycle RSS slope. Instantaneous CPU was approximately 18–35% with
real background agent/recording work; this is not an idle CPU benchmark.

An earlier run is retained separately: initial RSS 190560 KiB, initial physical
footprint 94.71 MiB; by batch 2 idle, RSS 211552 KiB / footprint 108.77 MiB.
It stopped after 43 successful cycles when the Island navigation control was
missing. That failed complete-workload attempt is **NOT VERIFIED**, not counted
as a passing 60-cycle batch. A driver mouse-exit race was corrected by entering
an already expanded shell before section navigation. No product change followed.

Native `vmmap -summary` before/after both runs provides allocation evidence:

| Native observation | Initial | Post-workload |
| --- | ---: | ---: |
| Physical footprint / peak | 94.8 / 101.2 MiB | 111.5 / 119.1 MiB |
| Total malloc allocation count | 349218 | 339226 |
| Total malloc allocated | 54.7 MiB | 56.6 MiB |
| Total malloc fragmentation | 9676 KiB | 19.9 MiB |
| Default-zone allocation count | 348139 | 338130 |
| Default-zone allocated | 52.7 MiB | 50.1 MiB |
| Default-zone fragmentation | 8028 KiB (13%) | 21.9 MiB (31%) |
| AttributeGraph malloc | 101 allocations / 47 KiB | 101 allocations / 47 KiB |
| CoreAnimation | 1248 KiB / 18 regions | 1264 KiB / 19 regions |
| IOSurface resident | 2720 KiB / 14 regions | 7008 KiB / 16 regions |

These aggregates support allocator spare capacity/fragmentation and bounded
render-buffer growth rather than per-cycle retained controllers. They do not
identify allocation backtraces or prove every additional byte intentional.
`heap -s` succeeded: one each of AppDelegate, OverlayWindowController,
IslandHostingView, AgentManagedSessionController, AgentTranscriptFeed,
VoiceTranscriptionController and ScreenRecordingController; nine NSTimers.
This is a post-workload census, not a timer leak comparison or retain-path proof.

A six-minute Instruments-compatible Allocations attachment was attempted.
`xctrace` ultimately returned exit 2, “Failed to attach to target”; there are no
allocation stack samples to interpret. No signing/security policy was changed
to bypass attachment restrictions. The failed trace is not a profiling PASS.

Reproducible native driver: `Scripts/profile_native_lifecycle.swift`. Compile:
`xcrun swiftc Scripts/profile_native_lifecycle.swift -o /tmp/dynamicisland-native-lifecycle`;
run `/tmp/dynamicisland-native-lifecycle <packaged-app-PID> <temporary-output-dir>`.
Requires existing AX permission and this hardware-notch layout, with no
simultaneous human pointer input. Native `proc_pid_rusage`/`ps` samples are
written atomically; missing controls/modal/foreign frontmost application abort
rather than count fake cycles. The driver never selects approvals, grants
permission, requests AX consent, or changes system preferences. Its reports
require inspection; they do not hardcode a PASS.

### Skills and motion classification

Applied transitions-dev and transitions-polish guidance to the acceptance:
single native shell, geometry/content handoff, correct expanded endpoints,
close/cancellation cleanup, hover stability, motion lifecycle and meaningful
Reduce Motion feedback. Relevant transition references: card resize, panel
reveal and menu morph; CSS/runtime packages were not introduced. Performance
engineering drove native measurement before hypotheses; QA kept fixture and
real-device results separate; accessibility guidance checked actual runtime
setting/consent boundaries; Graphify supplied scoped ownership navigation. No
additional specialized Swift/Instruments skill was installed.

**PASS — live:** repeated expanded Agents/Island/Tools navigation and collapse
endpoints in the completed native workload.
**NOT VERIFIED:** detailed uninterrupted timing/jank/opacity/hover acceptance
for all requested transitions. Screenshot sequences were attempted; expansion
failed its endpoint assertion in repeats, and simultaneous user pointer input
was observed. Those incomplete runs were rejected. The experimental frame
capture mode was removed from the committed memory driver. No product motion
defect was established and no animation implementation changed.

Actual macOS Reduce Motion was OFF during the workload and remained OFF. The
Phase 1 real OFF → ON → OFF acceptance remains valid baseline evidence; it is
not reported as a new Phase 2 ON pass. Full transition/environment regressions
are **PASS — automated/fixture**. No system setting was altered in Phase 2.

### Live provider and human gates

**PASS — live, real Codex:** existing acceptance rerun passed 2/0/1, including
creation, commands, normalized activity, exact-request deny then allow,
interruption and exact-session resume. The Claude test was explicitly excluded
and skipped; request/session/generation ownership and security policy remain
unchanged. These real provider events are driven by acceptance controllers,
not a claim of manually inspecting every natural thinking/search/plan state.

**BLOCKED — external acceptance dependency: Claude quota.** One actual read-only
Haiku request returned “You've hit your weekly limit”, reset October 4 at
21:00 Asia/Nicosia. No repeated quota attempts or credential changes. Genuine
concurrent Codex + Claude acceptance remains externally quota-blocked.

**BLOCKED — external acceptance dependency: controlled human speech.** The
requested sentence and normal/louder speech confirmation were not supplied.
The checkpoint package displayed real Listening/LIVE/beam while ordinary agent
activity continued, but ambient capture and a still-open recorder do not
prove controlled transcription, amplitude calibration or the full next-action
sequence. Human participation was requested; no consent or Keychain decision
was automated.

**BLOCKED — external acceptance dependency: development microphone consent.**
Native opt-in preflight again reported microphone authorization raw value 0
for XCTest and skipped without prompting. Debug app recording acceptance is
**NOT VERIFIED**; the XCTest preflight is not equivalent to it.

**PASS — live:** real development ScreenCaptureKit acceptance rerun, 5/0/0,
including display/window/area capture, movie validation, pause/resume and
system audio. Existing production controller teardown is exercised. This
does not imply every packaged capture/voice/agent coexistence sequence passed.

The existing packaged process was gracefully quit after profiling. Normal
`applicationWillTerminate` calls the existing voice cancellation cleanup;
PID 90279 exited, releasing its recording FD and process resources. No user
recording was manually deleted, no second microphone session was introduced,
and no teardown code was changed. Recognition terminal/recovery behavior
continues to have passing focused automated coverage.

### Validation and release results

- Focused voice/layout/motion smoke: **76 passed / 0 failed / 0 skipped**.
- Full suite: **1570 passed / 0 failed / 35 skipped**, 1605 total. Inventory and
  skip count are unchanged from Phase 1.
- Native opt-in: **7 passed / 0 failed / 1 skipped** (actual microphone consent).
- Selected real Codex: **2 passed / 0 failed / 1 skipped** (Claude excluded).
- Real screen capture: **5 passed / 0 failed / 0 skipped**.
- Bounded fixture soak: **1 passed / 0 failed / 0 skipped**, 110 cycles /
  151 seconds, 32 fixed sessions and an 80-entry transcript. Physical footprint
  cycles 10/30/50/70/90/110: 46.5/47.2/47.9/48.1/48.1/48.1 MiB; after
  teardown 44.1 MiB. Controller released. **PASS — automated/fixture**,
  separately from the whole-app native workload.
- Native profiling driver compiles; no product source/test changes or weakened
  tests. These test sets overlap; do not sum them.
- Release build and project packaging: **PASS** under unchanged ad-hoc policy.
  Initial deep strict verification rejected reattached generated FinderInfo.
  Clearing xattrs only from the generated app restored verification without
  changing its signature: app and all three helpers **PASS**. A temporary
  package export also passed deep strict verification.
- **PASS — live:** rebuilt package launch, executable confirmed under `dist`,
  PID 61134. Its native Tools action succeeded, but the subsequent Voice
  navigation lost its expanded endpoint during simultaneous user pointer
  input. Final rebuilt microphone consent/record/transcribe controls are
  **NOT VERIFIED** in this phase; no new permission decision or speech PASS
  is inferred from the checkpoint recording. Detailed UI/speech acceptance
  requires a short uninterrupted human-assisted window.
- Graphify AST update completed; generated graph files are left unstaged.

No demonstrated product defect was fixed in Phase 2. The only additions are
this evidence record and a fail-closed reproducible native memory driver.
The earlier driver mouse-exit/input/endpoint errors were harness defects,
not permission or app-state passes. The incomplete screenshot experiment
was removed rather than presenting it as accepted motion.

Remaining gates: controlled human speech and final rebuilt/development
microphone acceptance; Claude quota and concurrent provider execution;
uninterrupted detailed motion; longer whole-app profiling with additional
resource/session churn and allocation ownership if further growth appears.
Keep PR #24 Draft/open/unmerged. Recommended next phase: **Human-assisted
release acceptance after Claude quota reset**, with a quiet pointer window
and the documented fixed-workload memory baseline before release promotion.

Evidence is local under `/tmp/dynamicisland-phase2/`: full/native/Codex/capture
logs, initial/post-workload vmmap, native heap census, completed
`workload-repeat/memory.json`, rejected first workload and motion captures.
No recordings, traces, build products, screenshots, Graphify caches or
credentials are included in the phase commit.


## Phase 3 — Libraries.dev native fidelity

Baseline: `06b36a20963e2a097748c9ea01bb19c79c9c7d76`, fetched and equal to the remote feature branch before edits. PR #24 was verified Draft/open/unmerged. Environment: the same arm64 hardware-notch Mac, macOS 15.7.4 (24G517), SwiftPM debug tests and unchanged ad-hoc Release package. Unrelated local files, research recordings, installed skills and Graphify outputs remain outside this phase's staged delta.

### Reference, implementation and fidelity review

**PASS — automated/fixture:** actual public TypeScript and official native source inspected at `Jakubantalik/Libraries.dev@d06640864eb4adc2fe240f899a44ee6210779782`, thinking-orbs 0.3.2 / bot-avatars 0.2.2. MIT metadata and notices inspected; the full notice is copied into the app's local native resource bundle. No React/npm/WebView runtime, external package or new rendering framework was added. The preimplementation matrix and exact parity gaps are recorded in [libraries-native-parity.md](libraries-native-parity.md).

The nine orb engines, 20/64 presets and 18 distinct body SVG paths replace the prior generic drawing. Golden coverage verifies 72 cases / 70,115 values within 0.0001. Independent inline tuning, reference monochrome ink, speed, theme, freeze, real-state mappings and Canvas-local state handoff are retained. Bot rig uses current upstream gaze/eye lead, deterministic seed, state cross-animation, staged jump/spin/landing and projected faces. Native shading supports all five materials, lighting/fur controls, accessories, custom paths, held poses and whirl. Existing appearance JSON remains compatible; optional additions normalize, persist and reset through AppSettings.

**PASS — live reference inspection:** opened the authoritative public `/bots` preview in the actual browser and compared its clover/flower/ghost/square bodies with the native grids. Source inspection, rather than screenshots alone, established silhouette, rig, palette, face placement and light concepts. Direct comparison prompted denser native fleece and a softer fringe. That review then caught a reflected bitmap film and regular tuft lattice on asymmetric native bodies; orientation and combing were corrected, with an alpha-based asymmetric-triangle regression test. A headless browser attempt was rejected after failing to produce an image; it contributes no acceptance evidence. The `/orbs` navigation was attempted, but its settled browser preview was not accepted; mathematical/source comparison and native grids are the orb fidelity evidence.

**PASS — automated/fixture:** final review harness renders 18 PNG grids plus a deterministic 45-frame motion GIF, covering dark/light, all nine orbs at 20/64, all 18 bodies × three states × five materials, eye/mouth modes, seeds, compact/primary working frames, accessories and held poses. Existing compact/expanded Agents snapshots also render. ImageRenderer originally displayed a red/yellow unsupported-view placeholder for AppKit visibility probes; an isolated frozen-time render environment omits those adapters in deterministic snapshots. Real hosted views retain visibility/pointer tracking. No real session is mutated by previews.

**Parity limitations:** fabric is a bounded native perceptual approximation, not the browser's full multi-film signed-distance/fibre-lighting shader. Native accessory vectors approximate attached three-dimensional meshes; extreme-pose occlusion differs. Native whirl sampling and CoreGraphics rasterisation differ from browser strokes. Compact bodies intentionally reduce jump amplitude and reserve hat space inside clipped shell/row bounds. 64-point primary rendering is supported in Appearance/review; normal CLI/compact identity placements remain small to preserve transcript space. Exact shader/pixel parity is not claimed.

### Integration, motion and accessibility

**PASS — live:** the first rebuilt package launched from `dist` (PID 31661), displayed real ingested Codex running-command/tool presence in the hardware-notch compact island, and opened the expanded Agents CLI with correct provider labels and session-owned transcript. The existing workload completed 60 expand → Agents → Island → Tools → collapse cycles and rejected no endpoint. Subsequent settled screenshots showed the expanded native CLI. The live pass exposed a missing selected-session toolbar identity glyph; it was added at 18/22 points and re-rendered in final fixture acceptance, without changing session selection or provider controls. Final live inspection of that toolbar delta remains blocked by the later Keychain dialog.

**PASS — automated/fixture:** visible working rows no longer pause because they are not emphasized or because the menu-bar app is inactive. Each animation owns local timing; bounded player reuse preserves identity/phase through compact/expanded handoff. Offscreen/occluded hosts suspend, resumed clocks do not catch up long gaps, duplicate ticks do not advance twice, explicit held/paused poses freeze, and pointer targets do not consume button or scroll hit testing. Relevant layout/resolver, motion, Metal hit-target, state, identity, persistence and lifecycle tests pass. Accessibility exposes one provider/state image description, not decorative layers. The CLI keeps provider identity plus the stable avatar and useful inline activity indication.

Transition guidance was actually applied from `transitions-dev` and `transitions-polish`: stable outer pointer geometry, local transform/opacity handoff, persistent character state, Reduce Motion suppression and cancellation/resume without catch-up. Upstream hand-tuned rig timings were preserved rather than mechanically replaced with motion tokens or a generic spring. Performance-engineer, accessibility-tester, qa-expert and Graphify guidance were also used. No second shell or persistent island state was introduced.

**BLOCKED — external acceptance dependency: Keychain decision.** After rebuilding/relaunching, macOS displayed a password/Allow/Deny dialog for `com.local.dynamicisland.agent-bridge`. Human action was requested. No password, consent decision, Keychain item, TCC entry or signing policy was changed. UI automation stopped when the dialog was observed. A six-second motion recording was inspected and rejected as working-animation evidence because the dialog covered the intended state. **NOT VERIFIED:** final packaged uninterrupted working animation, pointer/click interaction, complete continuity and actual Reduce Motion OFF → ON → OFF for the new renderer. The actual setting was checked OFF and left OFF; earlier Phase 1 ON acceptance does not certify these new visuals. Static Reduce Motion policy and pause/resume logic have automated coverage.

### Performance and allocation evidence

**PASS — automated/fixture:** 2,160 orb-engine frames / 338,602 dots measured about 0.46 ms mean and 1.51 ms p99 in the final focused debug run. These are geometry-generation timings, not GPU presentation/frame-drop measurements. Rendering caches are bounded: 48 forms, eight pending serial bakes, 24 fibre images (<4 MiB), 64 custom paths/seats and 64 identity players. StateObject keeps render buffers stable across SwiftUI struct reconstruction. No per-frame Task, independent capture session or unbounded timer/observer creation was added. Host/render teardown tests release their objects.

**PASS — live workload execution; NOT VERIFIED — unrestricted whole-app memory closure:** same fail-closed native Phase 2 driver, three batches × 20 shell/section cycles, 20-second idle gaps and final 60-second idle, 387 seconds total. No synthetic session state was injected into the package. This run preceded the final toolbar/fleece-coordinate corrections; those changes were separately regression-tested, but this is not reported as a final-package long soak.

| Checkpoint | RSS KiB | Physical footprint MiB | CPU % (ps sample) |
|---|---:|---:|---:|
| initial | 126592 | 62.91 | 33.3 |
| idleBaseline | 126304 | 63.07 | 26.5 |
| batch1-cycle10 | 134448 | 69.52 | 33.7 |
| batch1-cycle20 | 135840 | 71.13 | 33.2 |
| batch1-idle | 135872 | 71.38 | 26.4 |
| batch2-cycle10 | 138352 | 73.33 | 33.3 |
| batch2-cycle20 | 141184 | 76.07 | 32.2 |
| batch2-idle | 141264 | 75.82 | 24.9 |
| batch3-cycle10 | 145024 | 79.21 | 31.8 |
| batch3-cycle20 | 145456 | 79.60 | 28.5 |
| batch3-idle | 145472 | 79.42 | 23.5 |
| postCleanup | 145472 | 79.42 | 23.3 |
| finalIdle | 145504 | 79.22 | 22.9 |

RSS grew from 126,304 KiB after initial idle to 145,504 KiB after final idle (+18.75 MiB); the final ten cycles + idle changed by 480 KiB. Footprint ended at 79.22 MiB. CPU was roughly 23–34%, comparable in scale to the Phase 2 driver (about 19–35%); this is whole-process work including live ingestion, not an isolated GPU benchmark. Late flattening is encouraging but too short to establish an unlimited plateau.

Read-only native `heap -s` and `vmmap -summary` were taken for PID 31661 after workload. Census showed three BotAvatarSim/Player objects, two AvatarRenderContext/RenderState objects and one visibility observer bag, rather than one retained renderer per cycle. vmmap reported about 24.3 MiB allocated in malloc zones and 32.5 MiB dirty fragmentation (58%); allocator retention contributes materially to RSS. A single census cannot assign all growth to caches or prove absence of another leak. No arbitrary flushing or speculative app-wide refactor was made.

**PASS — automated/fixture, separately:** existing 110-cycle bounded controller/render workload, 32 fixed sessions and 80 transcript entries, 151 seconds. Footprint cycles 10/30/50/70/90/110: 44.96/46.49/46.88/47.03/47.27/47.69 MiB; after teardown 43.24 MiB. Controller released. This is not whole-app proof. The final native performance harness rerun supplies supplementary transcript/provider/session switching measurements.

### Regression and release gate

- Focused final renderer/layout/motion/send controls: **77 passed / 0 failed / 0 skipped**.
- Full final suite: **1586 passed / 0 failed / 36 skipped**, 1622 total. Baseline was 1570/0/35: added 15 fidelity tests, one golden-vector test and one opt-in parity test (skipped by default). Existing tests/skips were not weakened or replaced.
- Parity/integration render opt-in: **3 passed / 0 failed / 0 skipped**.
- Native opt-in: **7 passed / 0 failed / 1 skipped**; microphone authorization raw value 0. No consent prompt was forced.
- Real Codex acceptance: **2 passed / 0 failed / 0 skipped**, selected Codex creation/command/interruption/exact-session resume and real deny/allow tests. Claude was not selected; this is a narrower filter than the prior 2/0/1 set, not a converted Claude skip.
- Bounded fixture soak: **1 passed / 0 failed / 0 skipped**.
- Release build / packaging / deep strict signature: **PASS**, unchanged ad-hoc signing, app plus three native helpers. Native MIT notice bundled. Final source package is built; later UI controls remain subject to the Keychain gate above. Earlier package launch is live evidence, not a claim that all final controls passed.
- Graphify AST update completed; generated graph/cache files remain unstaged.

Remaining gates: human Keychain decision, final packaged working/motion/pointer/Reduce Motion acceptance and longer representative memory/GPU profiling; complete fabric/accessory shader/mesh parity remains explicitly approximate. Previous controlled-speech/development microphone and Claude/concurrent-provider release gates remain external limitations and are not reclassified by this visual phase. Keep PR #24 Draft/open/unmerged. Recommended next phase: **human-assisted native fidelity and release-gate acceptance**, with an uninterrupted pointer window and allocation/GPU follow-up before promotion. No next product phase was started.

Local evidence: `/tmp/dynamicisland-phase3` (focused/full/native/Codex/parity/package/signature logs, native grids/GIF, real workload memory.json, heap/vmmap and rejected motion video). No screenshots, recordings, build products, Graphify caches or credentials are included in this commit.

## Phase 4 — native fidelity release gate and Codex semantic routing

Baseline `883f2b6971a7d842435d159b4b765a4b3b95ba57`, fetched equal to the feature remote; PR #24 verified Draft/open/unmerged. Environment: arm64 hardware-notch Mac, macOS 15.7.4 (24G517), October 3, 2026, SwiftPM debug tests and the existing ad-hoc Release policy. Phase 5 camera ownership, exact provider acknowledgement, transcript publication isolation and bounded/private activity recording remain intact. Unrelated files and `summary.md` were preserved outside this phase's staging.

### Demonstrated defect and smallest fix

The mapper inferred search/connection/composition from activity prose, and the Codex adapter discarded reasoning/item-level composition events. This violated real semantic routing. Optional provider-neutral processing metadata now travels through the existing ingestion/reducer/store. Nested item correlation, typed commandActions, reasoning, plans, composition, background work and scoped connections select the orb while existing blocking/command/tool precedence remains authoritative. Cleared/empty plans remove planning evidence instead of leaving shaping active. Terminal paths clear processing; previews never mutate sessions. No approval delivery semantics, transport identity, renderer implementation, camera policy or privacy collection scope changed.

The installed Codex 0.160.0 JSON schema was generated and inspected alongside the official app-server documentation. Global MCP startup lacks a session owner and is ignored. Synthesizing/weaving is supported only when typed evidence exists; no timed demonstration or text guessing was added. The full semantic matrix and limitations are in [libraries-native-parity.md](libraries-native-parity.md).

### Live provider and resource acceptance

**PASS — live:** real exact-session Codex semantic test, 38.52 seconds. Observed provider sequence included scoped startup → connecting, reasoning start → solving, structured repository search → searching, file read → listening, Python command → working, agent message → composing, completed turn → no active processing animation. The recorded run returned from commands to still-active composition; it did not emit planning/shaping or a second post-tool reasoning item. These states are not falsely reported as live. Raw event → reducer fixtures separately prove return to underlying reasoning when provider evidence remains active. Evidence: `live-semantic-sequence.json`, filtered by the exact provider/native-session/generation; the earlier unfiltered observer run is excluded from exact-session acceptance.

**PASS — live:** selected real Codex creation/command/interruption/exact-session resume and deny/allow tests, **2/0/0**, 120.43 seconds. Stop produced interrupted/ready and a static terminal orb policy; the exact session resumed and completed. Deny/allow uses existing exact provider acknowledgement. This does not replace packaged approval/animation coexistence inspection.

**PASS — live:** development screen-capture lifecycle, **5/0/0**, including area crop, system audio, pause/resume, static-window duration and teardown. Development camera ownership, **3/0/0**, including explicit close/remount remaining stopped and independent owner/reopen. These are real devices/resources exercised by opt-in XCTest, not simulated captures or final packaged camera UI acceptance.

**PASS — live, partial:** rebuilt app PID 72780 launched from `dist`; Tools → Voice → Record initially reached “Waiting for permission” and macOS Allow/Don't Allow. Human action was requested. Later inspection showed compact “Listening / LIVE”; Stop reached Transcribing, then “No speech was recognized”, with Record available again and no stale LIVE state. No controlled test utterance was supplied, so this is real recording/transcription/no-speech recovery, not successful human-speech acceptance or measured speech-envelope response.

**PASS — live, partial:** a subsequent recording attempt after ad-hoc package replacement displayed microphone consent again. A later snapshot showed real Listening/LIVE; Stop again returned to “No speech was recognized” with Record usable. Two real recording/no-speech recovery paths were therefore observed, with human consent decisions left to the user. Cancellation was not accepted: the macro did not produce a verified Cancel action and is excluded as cancellation evidence.

**BLOCKED — external acceptance dependency:** controlled human speech and final-package microphone identity acceptance remain pending. These recordings ran in the process launched before the last cleared-plan packaging step and do not certify that later identity's consent. No TCC, Keychain, password or signing policy changed. Development mic opt-in skipped because authorization was undetermined (raw value 0). The earlier Keychain service `com.local.dynamicisland.agent-bridge` did not display a dialog in this launch; that is not evidence its consent-dependent path is closed.

**BLOCKED — external acceptance dependency: Claude quota.** One minimal real Haiku invocation returned the weekly limit, resetting October 4 at 21:00 Asia/Nicosia. No retries or credential changes. Concurrent real Codex + Claude acceptance remains blocked. Provider/generation isolation is independently regression-tested and is not reported as live concurrency.

### Packaged motion and accessibility

**PASS — live:** rebuilt package launch, compact real Codex presence, expanded Tools/Voice controls and permission-state text. The controlled navigation report contains **four** successful expand → Agents → Island → Tools → collapse cycles, then a fifth aborted with `missingControl("Show Island page")` during desktop interference. The aborted 38.78-second run is not a completed 60-cycle soak or an uninterrupted motion pass.

**NOT VERIFIED:** final packaged orb/avatar continuous animation and semantic visual transitions, toolbar identity continuity, pointer/click, exact approval UI coexistence and GPU frame pacing. Concurrent desktop input and then the real permission dialog prevented a clean uninterrupted acceptance window. No consent-obscured clip is accepted as motion proof. The real Accessibility Display page was opened and inspected; an ON attempt did not change the setting (NSWorkspace remained false, defaults readback 0). Reduce Motion stayed OFF; OFF → ON → OFF was not completed. No blind repeated toggling or privacy changes followed. Existing static policy, phase/lifecycle, visibility, reduced-motion and interaction geometry tests remain passing fixture evidence.

Applied skills: transitions-dev and transitions-polish (native stable hit geometry, local state handoff, terminal cleanup and Reduce Motion; no timer-driven recipe demo), performance-engineer (measure before optimize), accessibility-tester (text/state and static policy), qa-expert (strict evidence separation) and Graphify (scoped queries and AST update). No subjective visual retiming or renderer rewrite was justified. Existing fabric/light, mesh/occlusion, whirl and rasterisation differences remain documented.

### Whole-app memory and frame-pacing evidence

**NOT VERIFIED — whole-app memory closure.** PID 72780 measurements:

| Checkpoint | RSS KiB | Footprint | Qualification |
|---|---:|---:|---|
| initial | 85,648 | 43.02 MiB | Startup, before settled ingestion/render caches |
| 21.33-second idle baseline | 113,584 | 62.33 MiB | Before controlled section cycles |
| process age 13:28 | 142,528 | not sampled simultaneously | After live provider tests, snapshots and pending microphone consent |
| 15-minute heap census | not sampled simultaneously | 73.5 MiB; peak 79.4 MiB | Mixed workload, not post-teardown |

Initial/post native heap allocations: **162,521 / 171,475 nodes**, **28,374,640 / 29,535,888 bytes**. AvatarSim/Player census remained **4/4**; AvatarRenderContext decreased **2 → 1**, RenderState **2 → 1**, visibility observer bag **1 → 0**. Post vmmap footprint was 72.6 MiB (79.4 MiB peak), malloc allocated 26.7 MiB and dirty fragmentation 19.7 MiB (43%), versus initial 27.5 MiB allocated / 9.66 MiB fragmentation (27%). These differently timed censuses support a material allocator-retention contribution, not a complete explanation for RSS. This is stronger evidence against one retained renderer per appearance, not proof every allocation owner is bounded. Whole-process RSS increased during real ingestion, warm-up, UI work and consent; the run has no controlled repeated-batch plateau or final app teardown. RSS alone does not identify a leak. No arbitrary cache flushing or speculative ownership change was made.

**PASS — automated/fixture, separately:** 110-cycle bounded soak, 32 sessions and 80 transcript entries, 154 seconds; footprint at cycles 10/30/50/70/90/110: **47.47 / 48.78 / 49.27 / 49.25 / 49.25 / 50.14 MiB**, after teardown **45.78 MiB**; controller released. This is not whole-app closure.

**PASS — automated/fixture:** 2,160 geometry frames / 338,602 dots, about **0.46 ms mean / 1.51 ms p99**. Native cache bounds and resource teardown remain covered. **NOT VERIFIED — GPU/frame pacing:** native Animation Hitches capture/export tooling ran for 15 seconds against the earlier process, but exported app commit/hitch tables contained no useful rows; global display-surface rows do not establish this app's frame rate. No GPU/hitch PASS is inferred from an empty trace or engine timings.

**PASS — automated/fixture:** combined native `DYNAMIC_ISLAND_AGENT_PERF=1` measured 200 streaming deltas → 47 transcript publications, six dashboard/chrome evaluations, **595.3 ms main-thread CPU / 1,790.9 ms wall**. A justified isolated follow-up, without snapshot-generation load, measured **510.3 ms CPU / 1,777.1 ms wall**, 45 transcript publications and six chrome evaluations. Typing 38 keys caused three console evaluations, not a transcript-wide update per key (148.8 ms CPU). Publication isolation remains intact; the isolated run is about **9.9×** faster than the old 5,070 ms CPU baseline. Neither timing run is GPU/frame-pacing proof.

### Final regression and release evidence

- Focused renderer/semantic/layout/motion/send: **86 passed / 0 failed / 1 skipped**.
- Full suite: **1,595 passed / 0 failed / 37 skipped**, 1,632 total. Baseline 1,586/0/36; nine deterministic semantic/isolation tests added and one honest opt-in live semantic skip. Existing skips/failures were not reclassified.
- Native acceptance: **7/0/1**; development mic undetermined.
- Parity/integration: **3/0/0**; deterministic review artifacts only.
- Selected real Codex: **2/0/0**; separate semantic real-provider opt-in **1/0/0**.
- Real screen capture: **5/0/0**; real camera ownership: **3/0/0**.
- Bounded fixture soak: **1/0/0**.
- Isolated transcript performance harness: **1/0/0**.
- Release build passed (100.48 seconds). The final script's bundle signing initially failed on generated Finder metadata. Clearing only generated package metadata and reapplying the same ad-hoc bundle signature completed packaging; deep strict verification passed for app plus three helpers. The final signed package launched as PID **99608**, with startup/compact shell inspected. No application/security data was reset. Earlier recording/control evidence is separated from final-package consent and uninterrupted visual acceptance as described above.
- Graphify AST update completed; graph/cache output remains unstaged. Validation runner accepts a phase-specific evidence directory and exposes semantic/performance/capture/camera modes.

Local evidence: `/tmp/dynamicisland-phase4` contains tests, exact-session semantic sequence, parity/native grids, performance/soak JSON, aborted navigation memory.json, heap/vmmap and diagnostic trace exports. Generated evidence, recordings, caches and credentials are excluded from the commit. Remaining release gates: human microphone/Keychain path, controlled speech, quiet packaged animation/pointer/Reduce Motion/approval inspection, real concurrent Claude after quota reset, and controlled whole-app allocation/GPU follow-up. Recommended next phase: **finish these human-assisted acceptance gates**, not another product feature. PR #24 remains Draft/open/unmerged; release is not promoted.


## Agents workspace reconstruction — BorderBeam / Feed / Terminal

Date: October 3, 2026. Supplied baseline: `883f2b6971a7d842435d159b4b765a4b3b95ba57`. The branch legitimately advanced to `32d7430369b4be6509dc50a561a7bf363023e277` before the workspace continuation because the event-driven Codex ThinkingOrb routing was committed first; no valid work was reset. PR #24 remains a Draft and is not to be merged during this acceptance phase.

### Workspace implementation

- Main selected-agent chat uses the semantic ThinkingOrb and the native Libraries.dev BorderBeam. Beam activity follows normalized session/provider state, not transcript text, and does not falsely imply execution while approval/user/terminal blocking states are authoritative.
- Model and reasoning-effort controls moved inside the chat surface. Codex reasoning effort is read from the provider's advertised model catalog and submitted as a validated exact-generation next-turn override; unsupported providers/models do not invent choices.
- The expanded right workspace retains **Feed** and **Terminal** pages in one surface. It preserves the existing terminal process controller and scrollback/focus identity rather than creating duplicate terminals.
- The Feed aggregates curated operational traffic from both providers, uses deterministic BotAvatar identity, bounds in-memory history, excludes prompts/transcripts/paths/secrets, and hosts managed approval/denial UI. Provider/session/generation/request ownership remains exact.
- Usage is six compact indicators in three semantic pairs: Codex + Claude 5-hour remaining; Codex + Claude weekly remaining; Codex + Claude selected-session context used.
- The right workspace has its own registered scroll region. Vertical Feed/Terminal scrolling is routed to content instead of the global collapse gesture; horizontal routing remains island/workspace owned according to the existing policy.
- Final visual audit corrected collapsed active-agent presence to explicit ThinkingOrb rendering. BotAvatar is now confined to operational Feed identity for this workspace role split.

### Motion and accessibility

Applied installed `transitions-dev` and `transitions-polish` guidance: retained surfaces, stable hit geometry, 250 ms smooth-out Feed/Terminal handoff, 300 ms smooth-out width allocation, and local 8-point/opacity Feed insertion. No additional persistent island shell state was introduced.

System Reduce Motion readback was `0` (OFF) and was left unchanged. **NOT VERIFIED:** actual OFF → ON → OFF acceptance for this new workspace; changing the user's system accessibility preference was intentionally not automated. Fixture policy tests confirm that Reduce Motion removes spatial workspace transitions and continuous decorative motion while preserving state/function.

### Test and performance evidence

- Full final regression: **1,665 passed / 0 failed / 38 skipped**. Supplied pre-workspace baseline: 1,586/0/36. Added coverage remains explicit; no failing test was converted to a skip.
- Provider/controller/client targeted suite: **94/0/0**.
- Workspace presentation: **7/0/0**.
- Feed ownership/approval/history: **11/0/0**.
- BorderBeam native/GPU: **12/0/0**.
- Semantic/visual/workspace/Beam selected pass: **52 passed / 0 failed / 1 skipped** (the skip is the opt-in real Codex semantic task).
- Expanded scroll/gesture + right workspace + transcript follow: **42/0/0**.
- Workspace 23-scenario deterministic review export: **1/0/0**. Offscreen snapshots produced expected `CAMetalLayer nextDrawable` warnings and are not counted as live Metal presentation evidence.
- Performance harness: **1 passed / 0 failed / 1 bounded-soak opt-in skip** in the ordinary run. For 200 streamed deltas, only six dashboard/content/controlbar/feed/selected view evaluations occurred; managed controller published twice while transcript coalescing published 73 times. Typing 38 keys caused three console evaluations. The new Feed/Beam/Orb surfaces did not republish provider state per animation frame.
- Bounded lifecycle soak run separately with opt-in: **1/0/0**, 110 cycles / ~100 s, 32 fixed sessions, 80 transcript entries. Footprint: cycle 10 **43,879,168 B**; 30 **45,058,816 B**; 50 **45,337,408 B**; 70 **45,370,176 B**; 90 **44,419,904 B**; 110 **44,469,056 B**; after teardown **39,914,304 B**. Controller released. Classification remains **PASS — automated/fixture**, not whole-app live memory closure.

### Release/package/signature

Production Release build completed. The first package-signing pass hit the known generated metadata error: `resource fork, Finder information, or similar detritus not allowed`. This was confined to the generated `dist/DynamicIsland.app`. Clearing only generated bundle xattrs and reapplying the same existing ad-hoc signatures recovered packaging. Deep strict verification then passed for the app and all three helper executables. Existing build warnings (deprecated `NSUnarchiver` and two pre-existing Sendable warnings) remain warnings, not new build failures.

The currently running `dist` process was started before the rebuilt package, so it is explicitly excluded as final-package launch evidence. No existing app process was killed merely to manufacture a launch result.

### External / human gates

**BLOCKED — external acceptance dependency: Codex quota.** The active Codex CLI reported the user's usage limit and a later retry time during this phase. No repeated live-provider task was fired merely to consume quota.

**BLOCKED — external acceptance dependency: Claude/concurrent providers.** The earlier Claude weekly quota gate has not been reclassified by fixture coverage.

**NOT VERIFIED:** final rebuilt-package uninterrupted Beam/orb animation, pointer/click interaction, Feed approval coexistence under real provider traffic, actual Reduce Motion OFF → ON → OFF, and unrestricted whole-app/GPU frame-pacing closure. Human consent/Keychain/microphone gates from the prior acceptance record also remain separate and are not converted into PASS here.

Generated snapshots, performance logs, soak reports, package logs, Graphify output, recordings, `.agents`, `.claude` and user research material remain outside this phase's intended commit. See `docs/agent-workspace-architecture.md`, `docs/border-beam-native-source.md` and `docs/libraries-native-parity.md`.


## Post-crash Agents workspace completion audit — 2026-10-03

This audit reopens the workspace checkpoint after a real packaged-app crash while switching between Agents and other primary pages. The prior checkpoint must not be treated as final acceptance for page switching or keyboard submission.

### Real crash evidence and lifecycle hardening

The user's crash report is `~/Library/Logs/DiagnosticReports/DynamicIsland-2026-10-03-222628.ips`. It records `EXC_BREAKPOINT / SIGTRAP` on the main thread during an AppKit/SwiftUI display transaction. The stack enters `NSView addSubview:` / SwiftUI `NSHostingView.swiftui_addRenderedSubview` while AppKit is updating constraints. The report does not expose a trustworthy high-level exception reason, so this audit does **not** claim one exact root cause.

The phase had one concrete re-entrancy risk in that path: the native agent prompt editor synchronously published text-input focus state from `becomeFirstResponder`, `resignFirstResponder`, and `dismantleNSView` while SwiftUI could already be removing/remounting the Agents host. Those focus publications feed `IslandLayoutStore` and therefore can trigger layout-observed state changes inside the same AppKit display cycle. Focus publication/teardown is now deferred one main-run-loop turn. Terminal focus publications use the same deferred discipline.

A new hosted `NSWindow`/ `NSHostingView` regression repeatedly mounts and unmounts the full Agents workspace while the native prompt editor owns first responder, alternates Feed/Terminal, and performs 48 remount cycles. **PASS — automated/native-host:** 48/48 cycles, no exception.

**PASS — live packaged app:** the final rebuilt app completed **40/40 cycles** of `Agents → Island → Tools`, i.e. 120 successful primary-page changes, using bounded Accessibility control discovery. The app remained alive and no DynamicIsland diagnostic report newer than the original 22:26:28 crash was created. An initial acceptance helper run hung while recursively walking AX; it was stopped and replaced with bounded-depth/bounded-retry discovery. One later first-cycle attempt timed out waiting for a navigation control during the page morph; after adding a bounded retry window the exact same final package completed 40/40. Neither automation limitation is counted as an application pass/failure.

### Return-key behavior

**Agent composer:** plain Return is now the primary submit action. Command-Return remains supported. Shift-Return inserts a newline. Option/Control Return are not treated as send shortcuts. Accessibility/help text was updated to match.

The native prompt editor test hosts the actual Agents view in an `NSWindow`, makes the real `NSTextView` first responder, types `plain return sends`, dispatches keyCode 36 with no modifiers, and verifies the provider-accepted user transcript entry. **PASS — automated/native-host.** A fresh live Codex send is still blocked by the user's current Codex usage limit, so fixture/native-host evidence is not relabeled as live provider acceptance.

**Terminal:** the generic SwiftUI `TextField.onSubmit` was not reliable inside the island's nonactivating panel. The Terminal input is now an AppKit-backed `NSTextField` with an `NSTextFieldDelegate`; the field editor explicitly handles `insertNewline:`, updates the SwiftUI binding on real edits, accepts focus requests from both Terminal entry paths, and clears the live field editor only after `TerminalSessionController` accepts the command. Failed launches preserve the command text.

**PASS — live packaged app:** selecting Agents → Terminal, focusing the real Terminal field and pressing Return executed a harmless command to **Exited 0**, cleared the input, and produced `TERMINAL_ENTER_OK`. **PASS — automated/native-host:** the same path launches the fixture process controller and asserts the native field becomes empty after successful submission.

Terminal scope remains explicit: this surface reuses `TerminalSessionController`, so it is a repeatable shell-command runner with selected-project cwd, streamed output, Stop, status and optional history. It is **not a PTY emulator** and does not replace the provider-driven agent CLI.

### Phase requirement audit

| Requirement | Final audit |
| --- | --- |
| Single collapsed/expanded island shell | PASS — no additional persistent shell state introduced |
| BorderBeam around selected agent chat | PASS — native Libraries.dev port, actual-GPU tests remain green |
| ThinkingOrb for selected chat / compact active presence | PASS |
| BotAvatar for operational Feed identity | PASS — deterministic provider/native-session/generation identity |
| Model + reasoning controls inside chat | PASS — provider-advertised options and exact-generation next-turn reasoning selection |
| Right workspace only Feed / Terminal | PASS |
| Feed contains curated operational traffic, not a second transcript | PASS — bounded/redaction/ownership tests |
| Feed approvals/denials preserve exact provider acknowledgement | PASS — request/session/provider/generation fail-closed tests |
| Six usage indicators: Codex+Claude 5h / Week / Context | PASS — remaining/remaining/used semantics and unavailable-state tests |
| Terminal preserves process/controller ownership across page switching | PASS |
| Terminal selectable/focusable and Return executes | PASS — live packaged + native-host |
| Agent composer Return sends; Shift-Return newline | PASS — native-host; live provider blocked by quota |
| Transcript + right workspace vertical scrolling stay isolated from collapse gestures | PASS — routing suites |
| Horizontal workspace/global gesture ownership preserved | PASS |
| Feed/Terminal and width-emphasis transitions follow installed transition guidance | PASS — deterministic policy/hosted transition coverage; Reduce Motion removes spatial transitions |
| Agents ↔ other primary-page switching does not crash | PASS — final packaged 40-cycle/120-transition live stress; no new crash report |
| Transcript streaming does not republish whole Agents chrome | PASS — final performance harness |
| Provider/session/generation isolation | PASS — deterministic multi-provider tests |
| Codex semantic activity → Orb mapping | PASS — deterministic; prior live provider evidence preserved |
| Claude provider-neutral isolation/mapping | PASS — deterministic; live Claude/concurrent-provider still externally blocked |
| Bounded lifecycle / teardown | PASS — exact-source 110-cycle soak; controller released |
| Release build / package / strict signature | PASS after generated-bundle xattr cleanup and same ad-hoc signing policy |
| Actual Reduce Motion OFF→ON→OFF | NOT VERIFIED — system readback remained OFF (0), unchanged |
| Fresh live Codex agent Return on final package | BLOCKED — usage limit |
| Fresh live Claude + concurrent Codex/Claude | BLOCKED — external quota/provider availability |
| Existing microphone/Keychain human acceptance gates | unchanged / external |

### Final validation after fixes

- Phase-targeted audit: **188 executed / 0 failed / 1 skipped**. The skip is the explicit opt-in real Codex semantic task.
- Clean full suite, with no packaged DynamicIsland process running: **1,669 passed / 0 failed / 38 skipped**.
- One full-suite run while the packaged app was concurrently active hit the existing `MetalSendInteractionTests` timing-sensitive click case (three cascading assertions in one test). The exact test immediately passed in isolation, and the subsequent clean full suite passed 1,669/0/38. No test was weakened, skipped or changed to hide that event.
- Final performance harness: 200 deltas → **6** Agents content/controlbar/dashboard/Feed/selected evaluations and **2** managed-controller publications; transcript coalescing published 63 times. Typing 38 keys → **3** console evaluations.
- Exact-source bounded lifecycle soak: **1/0/0**, 110 cycles / ~98 s, 32 sessions, 80 transcript entries. Physical footprint cycles 10/30/50/70/90/110: **44,010,176 / 45,370,112 / 45,681,408 / 46,484,224 / 46,664,448 / 46,779,136 B**; after teardown **41,175,808 B**; controller released.
- Final Release build: PASS. Existing unrelated compile warnings remain warnings.
- Generated `dist/DynamicIsland.app` can reacquire Finder metadata in the synced directory; clearing only generated bundle xattrs and reapplying the same ad-hoc signatures restores deep/strict verification. No Keychain, TCC, entitlement or signing-policy changes were made.

The correct next work is human/external acceptance closure (final live Codex send after quota reset, Claude/concurrent provider availability, actual Reduce Motion OFF→ON→OFF, and remaining consent-dependent microphone/Keychain checks), not another workspace redesign.

### Follow-up completeness audit after user crash report

A second requirement-by-requirement review found two phase gaps that were not covered by the earlier completion checkpoint:

1. **Hover feedback:** Feed/Terminal workspace tabs, workspace emphasis, and Chat/Terminal interaction controls now have explicit stable hover feedback using the existing workspace transition timing. Hover changes color/background only; hit geometry does not resize, so the earlier hover-collapse class of bugs is not reintroduced.
2. **Terminal scrollback/memory:** `TerminalSessionController` no longer erases output at every accepted command. Successful commands append a shell-style command header and preserve prior output in the retained terminal surface. Scrollback is bounded to **120,000 characters** with an explicit trim marker, preventing unbounded RAM growth. Failed launches do not erase or append to scrollback.

Terminal ownership remains unchanged: one existing `TerminalSessionController`, one running command at a time, selected-project cwd, streamed stdout/stderr, Stop, copy/selection, native Return execution and retained output across Feed/Terminal switches. It remains a shell-command surface rather than a PTY emulator; no second terminal process architecture or SwiftTerm runtime was introduced.

Latest-source verification after these follow-up changes:

- Focused terminal/crash/input set: **36 executed / 0 failed / 1 skipped**.
- Expanded phase audit (workspace, approvals, provider control, usage, Orb semantics, Beam GPU, shell motion, scroll routing and terminal): **230 executed / 0 failed / 2 skipped**.
- Clean full suite: **1,670 passed / 0 failed / 38 skipped**.
- Performance harness: 200 deltas → **6** surrounding Agents/Feed evaluations and **2** managed-controller publications; 38 typed keys → **3** console evaluations.
- Fresh bounded lifecycle soak: **1/0/0**, 110 cycles / ~98.6 s. Footprint cycles 10/30/50/70/90/110: **42,404,480 / 45,648,512 / 47,598,208 / 48,450,176 / 49,023,680 / 49,203,904 B**; after teardown **42,764,992 B**. Controller released; sessions remained 32 and transcript entries 80.
- Release source build: **PASS**. The synced `dist` folder immediately reattaches `com.apple.FinderInfo`, so deep strict verification there remains filesystem-provider-sensitive. A `ditto --norsrc` clean staging copy at `/tmp/DynamicIsland-postcrash.app`, signed with the same ad-hoc policy, passes deep/strict verification for the app and all three helpers and launches successfully.
- The original real crash remains the newest DynamicIsland diagnostic report. The crash-hardening commit's prior packaged **40/40 Agents → Island → Tools** stress remains live evidence for the unchanged focus/teardown fix. The newest staged package launched successfully, but its expanded navigation controls were not exposed through the bounded AX probe after programmatic shell activation, so a new 40-cycle UI claim is intentionally **not** made.
- Actual Reduce Motion remains **NOT VERIFIED**. Current system state is OFF (`defaults=0`, `NSWorkspace=false`). macOS rejected programmatic writes to `com.apple.universalaccess`; no preference-store bypass was attempted and the original setting remained unchanged.

This follow-up supersedes any earlier implication that hover feedback or repeated-command terminal scrollback were already complete.

## October 4, 2026 — interaction cleanup, exact-session Feed and native PTY

Starting checkpoint: `a987a9c4139b1be2a05994f9a36a02fb0c2f9869`; branch `feature/agents-ui-overhaul-continuation`. PR #24 remains Draft/open/unmerged. This section supersedes the previous command-runner terminal description and records fresh evidence rather than promoting prior phase results.

Environment: arm64 MacBook Pro, hardware-notch display (1147×745 logical points, 24-point top safe area), macOS 15.7.4 (24G517), Swift 6.2.3. Development tests and a newly built Release package were used. Actual Reduce Motion remained OFF and was not changed. No TCC, Keychain, credentials, entitlements or signing-policy changes were made.

### Audit and corrections

- Observed backend discovery/ingestion remains truthful and useful. Its read-only transcript/banner/dead-control primary route is replaced by the existing embedded glowing New Chat form for both providers. Managed sessions and provider-verified exact Resume retain their existing transport/control path; telemetry cannot manufacture control.
- Selection and reconciliation now share the provider/project projection. An explicitly selected exact approval owner remains selected for Feed even when it cannot host managed Chat; that owner's primary surface still uses New Chat. Toolbar controls cannot silently belong to another managed session.
- Normal Feed traffic and resolved approval history use the complete selected identity. Other-owner pending/unconfirmed requests are exposed through the existing approval controller's global attention/navigation, never mixed into selected history. Canonical approval state can recover a pending card even after bounded ordinary history is evicted. Provider acknowledgement semantics were not changed.
- Feed history is one bounded 256-item store with bounded event deduplication, not unbounded per-session caches. Consecutive semantic activity is coalesced. Command/tool summaries keep recognized safe names and exit codes; arguments, filesystem paths, prompts, hidden reasoning, transcripts and secrets are excluded.
- Historical Feed avatars use a frozen local renderer and cannot suspend/reset the visible agent's shared animation rig. Orb and Beam continue to follow normalized selected-session activity, with approval/interruption/terminal precedence intact.
- The single existing terminal controller now owns a real interactive PTY and native SwiftTerm 1.20.0 emulator (MIT, revision `5d14406844143538cd8f8851d2d8a67c1fe443e5`). The one-shot runner is replaced, not run in parallel. One retained emulator owns 2,000-line scrollback; there is no retained duplicate output String. Child-local cwd prompts do not edit user shell files. New project context sets initial cwd only; the live shell subsequently owns cwd/environment/history.
- Focus/start publication is deferred outside responder/layout teardown. Retiring hosts cannot steal a mounted terminal; resize is coalesced and leaves process identity intact. Stale callback generations cannot mutate a restarted shell. PTY cleanup intentionally targets only the unreaped owned child. Programmatic OSC 52 clipboard access is denied while explicit keyboard copy/paste remains supported.
- The strengthened native mount/unmount harness exposed a real macOS 15 Swift back-deployment crash in actor-isolated AppKit/controller deinitialization. Nonisolated owned cleanup bags replace that teardown path. Subsequent focused stress and the complete suite passed; no test was weakened.
- SwiftPM's read-only SwiftTerm shader copy initially prevented generated-package xattr cleanup. Packaging now grants owner write permission only to generated resource copies before the existing metadata cleanup. Dependency checkouts, signing policy and user files are untouched.

### Test accounting correction and final automated results

Older entries mislabeled XCTest's `Executed` total as the number passed. The starting raw log `/tmp/di-phase-audit-full.log` contains **1,670 total, 38 skipped, 0 failed**, therefore **1,632 passed**. This phase's full log contains **1,695 total, 38 skipped, 0 failed**, therefore **1,657 passed**. The inventory increased by 25 tests: workflow +6, Feed +9, controller +1 and real-PTY integration +9. Skips were neither added nor used to hide failures.

| Validation | Passed | Failed | Skipped | Evidence |
| --- | ---: | ---: | ---: | --- |
| Focused workflow/Feed/controller/PTY/native-host set | 62 | 0 | 1 | PASS — automated/fixture; integration cases use real local PTYs |
| Full suite | 1,657 | 0 | 38 | PASS — automated/fixture |
| Native opt-in acceptance | 7 | 0 | 1 | PASS — automated/fixture; legitimate ungranted microphone gate remains skipped |
| Performance harness | 1 | 0 | 0 | PASS — automated/fixture |
| Bounded lifecycle soak | 1 | 0 | 0 | PASS — automated/fixture |
| Real Codex exact-request deny/allow | 1 | 0 | 0 | PASS — live; actual provider through controller acceptance harness |

Nine real-PTY integration cases validate persistent PID/cwd/environment/prompt, native Return/history/Tab/Control-C/Control-L, ANSI parsing, `less` alternate screen, actual PTY resize, bounded large output, shell preservation through 24 host remounts, explicit restart/natural exit and child teardown. The focused native Agents harness exercises 48 mount/tab-switch cycles with agent and terminal focus and separately validates agent Return/Shift-Return versus terminal Return. These are automated integration/host tests, not packaged user acceptance.

Latest performance JSON: 200 streamed deltas → **6** surrounding Agents/Feed evaluations and **2** managed-controller publications (46 coalesced transcript publications); 38 typed keys → **3** console evaluations. Streaming main-thread CPU **398.8 ms**, typing **146.8 ms** in the native run. The independent performance run also passed; publication isolation remains healthy, without claiming a new cross-machine speedup ratio.

The bounded fixture soak ran **110 cycles / about 104 seconds**, with 32 sessions and 80 transcript entries. Physical footprint at cycles 10/30/50/70/90/110: **49,400,320 / 50,727,424 / 50,858,496 / 51,726,848 / 51,350,016 / 50,678,272 bytes**; after teardown **41,388,544 bytes**. Controller release was confirmed. This proves the fixture's bounded lifecycle, not whole-app leak freedom. A 5,000-line PTY output test retained native bounded scrollback and caused zero controller publications after startup.

**PASS — live:** the final packaged app completed **40 Agents → Island → Tools cycles / 120 successful section actions**, including collapse/re-expansion and the retained shell, without a crash. Runtime was approximately 3 minutes 26 seconds plus 3 seconds idle. RSS checkpoints at cycles 0/10/20/30/40/post-idle were **189,728 / 203,936 / 218,224 / 229,328 / 241,792 / 241,936 KiB**. The shell still reported `hello 49184` afterward, preserving its environment and PID through the workload. **NOT VERIFIED:** whole-app memory closure. This batch did not plateau; RSS alone neither identifies a leak nor proves bounded allocation. The short final idle is insufficient for allocator/retention attribution. Process-lifetime CPU values from `ps` are not isolated frame-pacing or idle-CPU measurements.

### Fresh packaged live acceptance

**PASS — live:** the clean Release artifact `/tmp/DynamicIsland-interaction-cleanup.app` launched. In one actual embedded zsh session, the cwd prompt changed after `cd ..` and `cd DynamicIsland`; `pwd`, `printf`/`echo`, `git status`, `git log`, and `swift --version` executed. `export DI_TERMINAL_TEST=hello` survived later commands. A foreground `sleep 30` was interrupted with native Control-C; Up recalled it; Tab completed a partial `/tmp` path; Control-L cleared the display. `less /etc/shells` entered its alternate screen and `q` returned to the same usable shell. Shell PID **49184** remained the same through Feed → Terminal and Agents → Island → Tools → Agents → Terminal, with cwd, exported variable and scrollback preserved. Workspace emphasis changed `stty size` from **13×49** to **13×33** when restored, without shell restart. Native integration covers additional ANSI/bounded-output/restart cases; fresh packaged copy/paste and complete VoiceOver navigation were not manually accepted.

**PASS — live:** existing New Chat created a managed Codex session (visible suffix …3015). A native Agent Return sent a read-only task to discover filenames and run `pwd`/`swift --version`; the actual transcript and selected Feed showed connection, reasoning, command outcomes, composition and completion, without unrelated observed-session traffic. The provider used shell-command items for repository discovery, so this run does **not** prove a distinct live search-item orb transition. A subsequent active provider turn was interrupted; the Feed showed interruption and the composer recovered to ready. The same selected session accepted a subsequent prompt. This interruption observation does not claim the shell command had already started when Stop was pressed.

**PASS — live:** actual Codex approval acceptance denied the exact first request and allowed the exact second request, confirmed provider acknowledgement and filesystem effects only in its test-owned scratch repository. No automatic approval policy was enabled. This is fresh provider/controller acceptance; exact Feed card/attention integration is automated evidence, not a fresh manual packaged cross-agent approval demonstration.

### Release and evidence boundaries

**PASS — automated/fixture:** Release build and packaging succeeded after the generated read-only-resource fix. The synced `dist` bundle immediately reacquired Finder metadata. `ditto --norsrc` produced a clean staging copy, which passed `codesign --verify --deep --strict --verbose=2` for the app and all three helpers using the existing signatures. No signing-policy workaround or privacy reset was used. **PASS — live:** the verified staging artifact launched and supplied the terminal/Codex observations above.

**BLOCKED — external acceptance dependency:** Claude execution and concurrent Codex/Claude remain quota/availability-gated (previous reset reported October 4, 21:00 Asia/Nicosia; this run precedes it). Both-provider routing/observation fallback and isolation are automated, not fabricated live Claude acceptance. Microphone authorization remains not determined in the native test (raw authorization 0); controlled human speech and the prior consent/Keychain-dependent path are not newly accepted. No consent dialog was bypassed or privacy setting changed.

**NOT VERIFIED:** fresh actual macOS Reduce Motion OFF → ON → OFF; original OFF remained intact. Deterministic reduced-motion coverage passed. Detailed uninterrupted motion, final GPU/frame-pacing closure, whole-app leak freedom, non-zsh live shell acceptance and fresh packaged multi-agent approval navigation remain outside the proven evidence. Existing renderer parity/material/accessory differences remain unchanged.

Recommended next work is human-assisted release acceptance for those precise remaining gates, not another workspace reconstruction or product feature phase.


## October 4, 2026 — visual hierarchy and streaming UX refinement

Starting checkpoint: `1b63f912670595e4ab517d0a35f644899ba02c91` on `feature/agents-ui-overhaul-continuation`. This phase refines presentation/streaming while preserving the exact-session Feed, native PTY, New Chat fallback, provider ownership and crash hardening from the prior checkpoint.

### UI and ownership changes

- The primary Agents toolbar is intentionally limited to provider selection, an actually available selected model, session/repository discovery, repository filtering and New Chat. Record Activities, selected-session status text, approval-policy/status/Stop chrome and redundant tail controls no longer consume this row. Record Activities remains reachable from Settings > Agents with the same opt-in/local/14-day/20-MB privacy contract.
- Cross-agent actionable-approval attention moved to the right workspace header next to Feed/Terminal. It still routes through the existing exact project/session selection path; ordinary Feed history remains selected-session scoped.
- The six usage gauges now own the full telemetry row in three equal semantic groups: Codex+Claude 5-hour remaining, Codex+Claude weekly remaining and Codex+Claude selected-session context used. Normal width uses 48-point gauges and width pressure steps to 40 points.
- ThinkingOrb remains the selected chat's persistent top-left high-level semantic activity indicator. Assistant transcript rows now use the same deterministic `provider + native session ID + generation` BotAvatar identity as the Feed. Only the latest active assistant response receives live semantic rig tuning; historical responses are frozen and do not keep continuous animation work alive. Waiting-for-approval/user and terminal outcomes are presented as non-executing avatar states.
- Approval/denial Feed presentation remains content-driven and may use multiple lines. No single-row approval constraint was introduced. Exact provider/session/generation/request ownership and acknowledgement-before-final-state semantics are unchanged.

### Streaming/follow correction

The selected conversation no longer scrolls on unrelated provider/session/approval publications because the dedicated Feed owns those events. Streaming follows the transcript's own latest stable user/agent row ID. A streamed response retains one row/scroll identity while its text grows. Auto-follow now performs one layout yield and one scroll against the latest conversation row, coalescing a burst into at most one additional settle; the old unconditional second bottom-sentinel scroll was removed because it could target newer geometry and place the viewport below the response. Manual history scrolling still disables following, and returning near the bottom or invoking Jump to latest restores it. New row insertion uses a subtle 140 ms opacity/0.995-scale transition; token/delta growth does not repeatedly animate/recreate the row.

### Automated evidence

- Focused hierarchy/streaming/workspace set: **82 passed / 0 failed / 1 skipped** (83 total). The skip is the opt-in snapshot destination when the environment variable is absent.
- Deterministic 23-scenario native workspace review: **1 / 0 / 0**. The review visibly shows the enlarged usage strip, reduced control bar, top-left ThinkingOrb and inline assistant BotAvatar. Offscreen `CAMetalLayer nextDrawable` diagnostics remain fixture limitations and are not live GPU evidence.
- PTY/crash/scroll regression set: **60 passed / 0 failed / 0 skipped**. Nine real-local-PTY integration tests still cover persistent PID/cwd/environment/prompt, native Return/history/Tab/control keys, ANSI, pager, resize, bounded output, remount/restart and teardown. The focused Agents native-host mount/unmount crash regression remains green.
- Performance harness: **PASS — automated/fixture**. For 200 streamed deltas, surrounding Agents content/controlbar/dashboard/Feed/selected views each evaluated **6** times and the managed controller published **2** times; transcript coalescing published **67** times. The growing console evaluated **140** times, as expected for visible response growth. Typing 38 keys produced **3** console evaluations.
- A first post-cleanup full-suite run exposed two suite-load timing assumptions: the managed-interaction test's fixed 20 ms connect delay produced three assertions and the native terminal-host stress missed one mount deadline. Both tests passed immediately in isolation. They were hardened to wait on the actual ready/view condition rather than fixed timing; no production behavior was weakened and no failure was converted to a skip.
- Final clean full suite after that hardening: **1,662 passed / 0 failed / 38 skipped** (1,700 total).
- Bounded lifecycle soak: **PASS — automated/fixture**, 110 cycles / ~98.5 s, fixed 32 sessions and 80 transcript entries. Physical footprint cycles 10/30/50/70/90/110: **44,534,528 / 45,386,496 / 45,468,416 / 44,436,224 / 44,763,904 / 44,796,672 bytes**; after teardown **40,028,928 bytes**. Controller released. This is fixture ownership evidence, not unrestricted whole-app leak proof.

### Release boundary

The Release source build completed successfully with only existing unrelated warnings. The synced `dist` directory again reattached Finder/FileProvider metadata; no security setting or signing policy was changed. A clean `ditto --norsrc` staging copy at `/tmp/DynamicIsland-streaming-refine-final.app`, signed with the existing ad-hoc policy, passed deep/strict verification for the app and all three helpers and launched successfully. The October 3 22:26 crash remains the newest DynamicIsland diagnostic report after the launch smoke.

**NOT VERIFIED / external:** this phase does not claim a fresh uninterrupted packaged animation trace for every BotAvatar semantic tuning, an actual macOS Reduce Motion OFF→ON→OFF human toggle, fresh Claude/concurrent-provider live acceptance, consent-dependent microphone/human-speech closure, or whole-app/GPU frame-pacing closure. Those evidence boundaries remain unchanged rather than being inferred from fixtures.


## October 4 — hierarchy acceptance closure follow-up

Baseline audited: `135932d052f21f045e58a5e4ee11dc7ced0d2316`, a compatible newer commit than the supplied checkpoint. Its reduced toolbar, full-width 48/40-point usage gauges, top-left ThinkingOrb, inline semantic BotAvatar and one-pass latest-message scroll target were preserved. Backend observation remains non-owning, normal Feed filtering remains exact, and Record Activities remains in Settings with unchanged privacy/retention limits.

### Demonstrated corrections and deterministic evidence

- Explicit Jump to latest previously used an unconditional animated scroll. It now uses transitions-dev/transitions-polish's quiet 150 ms handoff and suppresses spatial animation under Reduce Motion. Stream-delta settling remains unanimated.
- Approval context previously stopped after three lines. It now wraps to the full supplied context height; privacy projection and exact decisions are unchanged. Both-provider 240/440-point native review images show the full twelve-line stress context and reachable Deny/Approve controls. This is **PASS — automated/fixture**, not live provider permission acknowledgement.
- A native NSHostingView/NSScrollView regression waits for measured document growth before inspecting every streamed increment. Six growing deltas retain the latest response near the viewport bottom; manual history scrolling stays in place; returning near the bottom resumes following. The latest-message anchor leaves the existing padding/sentinel below it, rather than forcing a second scroll into decorative space. **PASS — automated/fixture**.
- The focused workspace/Feed/approval/avatar/terminal/publication suite initially recorded **79 passed / 0 failed / 1 opt-in snapshot skip**. Three new tests cover Reduce Motion jump policy, actual viewport growth/follow/history/resume, and native approval wrapping/exact ownership. No skip policy changed.

### Actual package/provider observations

**PASS — live:** the clean packaged hierarchy checkpoint at `/tmp/DynamicIsland-streaming-refine-final.app` displayed the enlarged equal usage pairs and concise control row without the Record Activities tail. An exact Codex session resumed, accepted native Return, and produced real 40- and 60-line responses ending in `STREAM_ACCEPTANCE_END` and `FOLLOW_BOTTOM_END`. After Jump to latest, the 60-line response ended visibly at the chat lower edge without overshoot. Manual upward scrolling retained the earlier response and exposed New activity; the explicit jump recovered the latest response. This pass does not establish uninterrupted animation for every semantic state. A subsequent short synthetic-key attempt did not establish a new visible response and is not counted as a live PASS.

### Performance and bounded lifecycle

**PASS — automated/fixture:** `DYNAMIC_ISLAND_AGENT_PERF=1` retained publication isolation. 200 streamed deltas → 6 surrounding Agents/Feed evaluations, 2 managed-controller publications, 46 coalesced transcript publications, 98 console evaluations; streaming main-thread CPU 352.1 ms. 38 typed keys → 3 console evaluations. Report: `/tmp/dynamicisland-hierarchy-closure/performance.json`.

**PASS — automated/fixture:** 110 controlled cycles in 100 seconds, retaining 32 sessions and 80 transcript entries. Physical footprint bytes at cycles 10/30/50/70/90/110: 43,043,584 / 44,944,128 / 46,779,264 / 48,417,664 / 48,532,352 / 47,270,784. After teardown: 42,060,672; controller released. This is physical footprint of the fixture, not whole-app RSS. Offscreen CAMetalLayer drawable-allocation warnings limit presentation evidence. Report: `/tmp/dynamicisland-hierarchy-closure/soak.json`.

**NOT VERIFIED:** whole-app memory closure, GPU/frame pacing, every uninterrupted live semantic avatar animation, and actual OS Reduce Motion OFF→ON→OFF. Actual OFF was preserved. **BLOCKED — external acceptance dependency:** Claude quota/concurrent-provider execution and consent-dependent microphone/controlled human speech retain their prior blockers; no security, TCC or Keychain setting was altered.


### Final regression accounting

Full suite: **1,665 passed / 0 failed / 38 skipped** (1,703 total), versus the audited hierarchy baseline of 1,662 passed / 0 failed / 38 skipped. The +3 are the new jump-policy, real native viewport and approval-context tests. The first full run had one existing rapid mount/unmount harness terminal-mount deadline failure; it passed in isolation and in the second complete run. The assertion now includes cycle/Agents/workspace/emulator-owner diagnostics; its five-second deadline and all assertions remain intact. No failure was converted to a skip. Final full log: `/tmp/dynamicisland-hierarchy-closure-final/full.log`.

Native acceptance: **7 passed / 0 failed / 1 skipped**, unchanged; microphone authorization status 0 prevented the live-recording test. This skip is the existing external consent gate. The native performance repeat retained 200 deltas → 6 surrounding evaluations / 2 managed publications / 51 coalesced transcript publications / 108 console evaluations; streaming main-thread CPU 496.3 ms, and 38 typed keys → 3 console evaluations. Both runs preserve isolation; wall/CPU variation is reported rather than interpreted as GPU/frame-pacing acceptance. Final native log and report: `/tmp/dynamicisland-hierarchy-closure-final/native.log` and `performance.json`.


### Final package and boundaries

Release build: **PASS — automated/fixture**, 130.05 seconds, with existing unrelated compiler warnings. `Scripts/package_app.sh` passed under the unchanged ad-hoc policy. The synced `dist/DynamicIsland.app` immediately reacquired `com.apple.FinderInfo`, so its direct strict verification failed. A generated `ditto --norsrc` copy at `/tmp/DynamicIsland-hierarchy-closure.app` passed **deep/strict signature verification**, including all three helpers, without re-signing that staging copy or changing any security/signing setting. The distinction is intentional; the synced original is not reported as signature-clean.

**PASS — live:** final staged package launch, Agents usage/control hierarchy, Feed→Terminal→Feed controls, real PTY `pwd` output with the correct `~/Documents/DynamicIsland %` prompt, and exact Codex resume control. The final package's fresh streamed prompt was **NOT VERIFIED**: the guarded temporary native-input helper could not locate the intended Agent prompt accessibility element and refused to send, even with a deeper traversal. No keys were redirected to another control. The earlier real 40/60-line Codex acceptance and final native viewport regression remain separate evidence. No Keychain dialog was bypassed.

PR #24 was checked Draft/open/unmerged; unrelated summary, graph outputs, local skill/config files and research recordings are preserved and excluded from this phase commit. Graphify AST update completed. No provider, approval, camera, audio, terminal-process or recorder-privacy implementation was modified by this follow-up.

## October 4 — motion, streaming and renderer closure checkpoint

Starting HEAD `425119b045c6313cc57e3de0ff8dbd9205e42c1b`; branch/remote and Draft/open/unmerged PR #24 were verified before changes. This is a focused renderer/presentation change. Domain ingestion, exact session/approval acknowledgement, selected-session Feed, observed fallback, PTY ownership and recorder privacy are preserved.

### Demonstrated defects and native correction

- **PASS — automated/fixture:** collapse restoration previously depended on a transient yielded scroll and view-local follow state. A lazy document's estimated height could leave the current tail unmeasured. Follow/history intent now persists by exact session; mount and new rows realize the current canonical row, while a marker on that row corrects following after layout. Live acceptance exposed estimated blank document height below a tall response, so following targets the actual row end rather than document height. The native regression now also asserts the final glyphs of three heterogeneous 60/80/100-line responses are visible after remount. Six streaming increments, completion, remount at latest, content received while unmounted, and history remount pass in a real NSHostingView/NSScrollView regression. There is no token-driven animated scroll, fixed offset or restoration sleep.
- **PASS — automated/fixture:** latest text uses append-only TextKit storage and temporary Core Animation word layers with the exact 350/60 ms, 1→0 blur, 0→1 opacity and `(0.22,1,0.36,1)` recipe. First chunks animate once; remounts resolve initial text using a bounded 256-key identity-only mount history. Historical rows remain static. Native tests cover fragments, Unicode, source Markdown, selection, unchanged geometry, interruption/completion, Reduce Motion and actual layer timing functions.
- **PASS — automated/fixture:** a profiling run exposed zero/unbounded measurement probes triggering extensive TextKit work. Those probes are rejected before real text measurement. Foreground-attribute masking also invalidated layout; unresolved glyphs are now excluded only at drawing time, with cached transient overlay images. A separate real native profiling crash identified non-finite Metal geometry during a transient proposal; guarded geometry fixes that crash without disabling Send.
- **PASS — automated/fixture:** hidden staged Agents children are gated at construction. Full transcript/terminal blur was removed. The existing shared shell phase/generation coordinator remains, with no additional 40 ms transcript delay. Only a selected, visible Terminal mounts its host; the same controller/emulator/PTY remains alive throughout presentation changes.

### Production-view measurements

Reports are DEBUG/native-fixture evidence, not display FPS. Baseline `/tmp/di-motion-baseline/performance.json`: entry **441.7 ms CPU / 862.3 ms wall**, paced 200-delta streaming **407.5 ms CPU**. Final `/tmp/di-motion-tail-performance/performance.json`: entry **347.7 ms CPU / 764.9 ms wall**; paced streaming **487.6 ms CPU / 1,781.3 ms wall**. The final harness requires the actual current response to be rendered and visible. An intermediate apparently faster run omitted that condition and is excluded as acceptance. Baseline delta ingestion trimmed whitespace; final ingestion preserves real word boundaries, blank lines and code indentation under the unchanged 8,000-character cap. The final paced stream costs **19.7% more CPU** than the old baseline; this is not concealed or declared a frame-pacing PASS.

**200 deltas → 6 surrounding Agents/Feed evaluations / 2 managed publications / 49 coalesced transcript publications / 56 console evaluations**. **38 keys → 3 console evaluations**. Removing redundant local follow-token mutation reduced console evaluations from 109 to 56 and paced CPU from 531.5 to 487.6 ms in this phase. Domain/transcript isolation remains intact.

`/tmp/di-motion-tail-final/motion.json`: shell-only **10.1 ms CPU / 17.2 ms wall**, zero transcript console evaluations and no mounted terminal. First eligible child construction **237.5 ms CPU / 626.9 ms wall**; warm 20-cycle work remains measurable. Feed→Terminal **22.9 ms CPU / 25.9 ms wall**; Terminal→Feed **74.4 ms CPU / 282.8 ms wall**. The same real PTY PID survives all 20 fixture cycles. **500 words → 6 surrounding evaluations / 2 managed publications / 18 transcript publications / 25 console evaluations**, **283.1 ms CPU / 701.8 ms wall**, with the actual final word rendered. A failed intermediate 500-word experiment consumed ~18 seconds because of TextKit proposal/masking work; the fix rejects unbounded probes and avoids foreground-attribute layout invalidation. CPU sums and host layout calls are not maximum frame-stall or 120 Hz proof.

### Bounded ownership and memory

**PASS — automated/fixture:** 110-cycle fixture, 32 retained sessions / 80 transcript entries, 97 seconds. Physical footprint bytes at cycles 10/30/50/70/90/110: **44,911,296 / 45,959,872 / 47,073,984 / 45,517,504 / 45,435,584 / 44,567,232**; teardown **40,209,088**, controller released. Report `/tmp/di-motion-release-final/soak.json`. The separate 20 renderer-handoff cycles warmed from **58,362,816** to **64,392,128** bytes. These are fixture footprints, not whole-app RSS or proof that every GPU resource is released.

Bounds: 64 transient text runs, 256 mount-identity keys without text, 64 viewport positions, 32 exact-session Metal models, 16 glow sprite entries, two GPU commands in flight, one shared compiled pipeline. SwiftTerm remains the sole bounded terminal scrollback owner. No duplicate transcript/terminal text cache, display link, per-frame Task, domain animation publication or new observer store is introduced. Detached text cancels its boundary wakeup and overlay layers; viewport observation bags unregister their native notifications.

### Reference and accessibility boundaries

**PASS — automated/fixture:** native GPU execution verifies the pinned Metal shader for all three presets and both themes, time progression and zero strength. Native Send interaction tests retain full hit geometry and functionality. Reduce Motion settles streamed words, freezes decorative Metal/pointer motion and preserves static activity/material meaning. Actual OS OFF→ON→OFF remains **NOT VERIFIED**; original OFF is preserved. Upstream pointer-velocity versus native position-driven Gaussian response, rasterization and existing Avatar material/accessory gaps remain documented in the parity record.

### Acceptance limits and final resource correction

**PASS — automated/fixture:** the stable-source full suite recorded **1,675 passed / 0 failed / 39 skipped** (1,714 total), versus 1,665 / 0 / 38 at the starting checkpoint. Seven Streaming Text tests and three native Metal tests add ten regular passes; the new explicitly opt-in motion harness adds one default skip. Existing skip gates remain intact. Focused visual validation recorded **98 / 0 / 1**, motion/GPU/viewport **12 / 0 / 0**, and the publication harness **1 / 0 / 0**. Final resource-only correction validation is recorded below.

**NOT VERIFIED:** whole-app memory closure. The controlled packaged workload completed 40 cycles before its guarded driver aborted at a missing navigation endpoint; it did not complete the planned final idle/teardown. RSS rose from **146,992 KiB** to **171,552 KiB**, physical footprint from **72,616,960** to **91,081,728 bytes**; the cycle-40 idle footprint was **91,638,784 bytes**. These observations do not establish a plateau or diagnose a leak. The bounded fixture plateau is separate evidence.

**NOT VERIFIED:** application GPU/frame pacing and zero-jank/120 Hz acceptance. The 30-second Animation Hitches trace exported no useful hitch/commit rows. A separate Metal trace contained 7,216 global GPU command records without useful attribution to this application/send effect. Empty trace output is not proof of no dropped frames; shader-specific GPU tests do establish actual runtime execution. First child construction and the 19.7% paced-stream CPU increase remain material profiling follow-ups.

An initial final-package launch displayed empty Agents content and stalled accessibility queries. A three-second native sample consistently located the main thread in BorderBeam's one-time resource lookup through SwiftPM `Bundle.module`. The generated accessor probes the app root and then an absolute build-directory fallback; packaging places bundles in `Contents/Resources`. NativeResources now resolves the packaged LibrariesNative bundle first for Beam specification, Beam shader and Metal shader, and uses the SwiftPM fallback only in development/test layouts. This fixes the demonstrated deployment lookup boundary without altering rendering equations or security. The post-correction renderer suite passed **18 / 0 / 0**. Sample: `/tmp/di-motion-release-final/launch-sample.txt`.

Fixture animation and offscreen CAMetalLayer warnings do not establish uninterrupted packaged motion or provider acceptance. Actual OS Reduce Motion OFF→ON→OFF remains **NOT VERIFIED**; consent-dependent microphone/human speech and fresh Claude concurrency remain **BLOCKED — external acceptance dependency**. No privacy or Keychain setting was changed, and stale/intermediate recordings are excluded from final live motion evidence.

### Final corrected package and real session evidence

**PASS — automated/fixture:** after the packaged resource lookup correction, the full suite again passed **1,675 / 0 / 39** (1,714 total), 51.35 seconds. Log `/tmp/di-motion-resource-final/full.log`. Release build passed in **129.72 seconds**; the packaging script completed under the unchanged ad-hoc policy. Direct deep/strict verification of synced `dist` failed on reattached `com.apple.FinderInfo`. The generated `ditto --norsrc` staging copy `/tmp/DynamicIsland-motion-closure.app` passed deep/strict verification, including all three helpers, **without re-signing this final copy**. Earlier provisional staging was re-signed; it is not the final artifact evidence. No signing or security policy was changed.

**PASS — live:** the corrected staged package launched and displayed the actual Agents workspace with Beam, usage/control hierarchy, header activity and inline stable Avatar. The former empty resource-stalled surface is gone. A managed Codex session ending `…9cc6` accepted a prompt through native Send, streamed a real 70-sentence response and completed with `FINAL_MOTION_ACCEPTANCE_END`. Native accessibility reads preserve spaces, punctuation and newlines. The fresh 20-second recording `/tmp/di-motion-final-package-stream.mov` shows reasoning/connecting/composing Feed activity and new words resolving softly; it is separate from deterministic timing and GPU tests. The recorded first response grows in the same row without whole-row flashing. This does not establish all uninterrupted long-response follow/frame-pacing scenarios.

**PASS — live:** after a completed actual collapse/re-expansion, the final response's lines 69–70 and `FINAL_MOTION_ACCEPTANCE_END` are visible at the chat's lower edge, with no two-message offset or blank space below the content. Automated native regressions additionally cover content arriving while unmounted and deliberate history reading. Repeated live collapse while actively streaming/history restoration remains **NOT VERIFIED** in this final package.

**PASS — live:** native Terminal Return ran `pwd`, `cd ..`, `pwd`, environment export/echo and `git status` in one shell. The selected temporary acceptance directory was not a Git repository, so `git status` truthfully returned its normal error. Ctrl-C interrupted `sleep 30`; Up recalled it and Tab expanded `cd app` to the common `cd approval-` prefix without executing it. Feed→Terminal and Agents→Island→Tools→Agents→Terminal retained **PID 57816**, `DI_TERMINAL_TEST=hello`, current cwd and visible scrollback. The final terminal renderer and transcript coexist without a tab-switch crash. Complete final live PTY collapse/expand was not inferred from a mouse exit while native terminal focus retained the expanded surface; the independent 20-cycle real-PTY fixture remains the continuous shell-retention evidence.

**NOT VERIFIED:** final packaged Metal pointer-bend/halo smoothness across repeated re-entry and uninterrupted 120 Hz shell motion. The material is rendered in the corrected app and actual shader execution passes fixture GPU readback; a short pointer movement in the stream recording is insufficient to accept every hover/press/lifecycle path. Disabled Send is intentionally static, enabled draft animates. No quota blocker was encountered on this final Codex response; Claude and human-consent gates remain separate.

**NOT VERIFIED:** a fresh controlled final-package memory run stopped at `missingControl("Show Agents page")` before its first complete cycle; the driver did not send input to another app or classify an incomplete cycle as success. Initial RSS/footprint were **184,896 KiB / 90,786,816 bytes**; after its 20-second idle **186,096 KiB / 85,920,768 bytes**. Report `/tmp/di-motion-final-live-memory/memory.json`. No plateau/teardown conclusion is drawn, and the aborted driver is not repeatedly retried. Neither that run nor the earlier 40-cycle run replaces the bounded fixture ownership evidence.

This is a validated implementation checkpoint with explicit remaining acceptance gates, not a claim that the entire zero-jank/GPU/whole-app-memory definition of done is closed. PR #24 remains Draft/open/unmerged. Unrelated summary, graph outputs, local skill/config files and research recordings remain outside the phase commit.

**PASS — automated/fixture:** an additional real native Send host regression begins with an explicitly paused retained model, verifies visibility resumes its clock and delivers changing material time to the actual MTKView, then verifies unmount pauses it. This checks renderer activation rather than CPU-only material sampling. It passes without changing the user's saved settings. The packaged enabled-material recording `/tmp/di-motion-final-metal-enabled.mov` used the user's saved strength **0.59514** / glow gain **0.43900** rather than silently replacing them with defaults. The short recording does not establish halo/pointer smoothness; that final visual gate stays **NOT VERIFIED**.

**PASS — automated/fixture:** final full regression accounting including the added native Send lifecycle test is **1,676 passed / 0 failed / 39 skipped** (1,715 total). The +11 regular passes relative to the 1,665 baseline are seven Streaming Text, three Metal GPU/rig tests and one native Send activation/frame-delivery/teardown test. The single additional default skip is the opt-in shell motion harness. No failure was converted to a skip. Final log `/tmp/di-motion-final-checkpoint/full.log`.
