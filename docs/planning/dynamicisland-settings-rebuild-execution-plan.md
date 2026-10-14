# DynamicIsland Settings and Droppy reference implementation

## Status and authority

Started on `feature/camera-hand-navigation` at `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`. Preserve this branch, existing work, active application/Agent/Terminal sessions, preference keys and permission grants. No commit, push or merge has occurred in this phase.

The requested authoritative document, `DynamicIsland_Settings_1to1_Codex_Master_Plan.md`, and its accompanying Settings reference frames have not been supplied or located. Searches covered repository files, Documents/Downloads/Desktop recursively by relevant names, and Spotlight for the exact document. The user-provided 34-second recording covers island behavior rather than Settings pages. A request for the missing material's path is pending.

**Do not infer the missing Settings pages or claim reference fidelity.** The phase sequence below is provisional until reconciled with the authoritative document. Independent window requirements are safe to implement now. The existing island-video plan is in `/tmp/droppy-video-01-implementation-plan.md`; its observations are summarized below so the executable scope is retained.

Prompt Master methodology: one concrete outcome, evidence-backed scope, explicit constraints, ordered phases, measurable completion and exact dependency gates. Apple Design/Taste guidance applies through SwiftUI/AppKit and existing native motion tokens, with no website presets or dependencies. awesome-swift supports discovery; existing native APIs/modules remain preferred. Ponytail reviews connected callers, ownership, persistence and acceptance limits.

## Audited starting architecture

| Responsibility | Existing authority | Preservation contract |
|---|---|---|
| Window lifecycle | `App/SettingsWindowController.swift`; retained by `App/DynamicIslandApp.swift` | One retained Settings window per process; native controls and no unrelated instance termination |
| Categories/sections | `Views/SettingsView.swift`: six categories and all `SettingsSection` cases | Every current pane remains reachable; map to reference navigation after seeing it |
| Durable preferences | `State/AppSettings.swift` and existing domain stores | Keep persisted identities, migrations, independent feature defaults and privacy exclusions |
| Coverage contract | `Views/SettingsAudit.swift`, `SettingsAuditTests` | Every AppSettings preference audited once; enabled controls retain real production readers |
| Production previews | `Views/SettingsPreviews.swift` and `settingsPreviewDependencies()` | Reuse actual presentation components; synthetic fixtures where appropriate; no implicit permission/provider actions |
| Additional settings | Messaging, Productivity, RightWorkspace, AgentAppearance settings views | Preserve exact Messages reply/send confirmation, capability boundaries, Agent sessions/approvals and Terminal ownership |
| Camera | Shared controller/lease architecture and persisted gesture settings | Explicit first permission intent; no second session; preserve Mirror and navigation ownership |
| Recording | Current capture authority, cdhash recovery and recording engine | No permission rewrite, cached-grant shortcut or source/binary identity disruption |
| Island motion/layout | WorkspaceMotion, ExpandedIslandMotion, geometry/layout stores | One navigation/layout/motion authority; fixed notch anchor and Reduce Motion |
| Media/output | MediaAdvancedController/AudioOutputRouter and MediaControlRow | Real CoreAudio options, source-specific actions and one-seek-per-release fences |

The audited window was not resizable, its SwiftUI root was fixed at 920×700, and reopening recentered it. These concrete issues prevent mandatory resize/fullscreen/restoration independently of the absent visual specification.

## Phase 0 — baseline and missing-reference resolution

Completed: record branch/HEAD/status; hash all individually enumerable pre-existing dirty/untracked files; map the Settings callers/tests; use an isolated copy of the graph for querying; locate relevant installed skills. Keep research outputs outside unrelated dirty graph/Playwright directories.

Required next input: exact master-plan and Settings-frame paths. Read the document completely and reconcile its phase order before reference-dependent edits. Index frames by page/state/time and record crop, scale and frame rate. Associate each visible control with an existing setting, production capability or explicit feature gap. Distinguish observed behavior, public source and proposed implementation.

## Phase 1 — native window foundation

Implemented independently:

- Standard titled/closable/miniaturizable/resizable window with fullscreen-primary behavior.
- Existing 920×700 default size; 800×600 minimum content size; flexible SwiftUI root.
- Native frame restore/autosave; center only when no saved frame exists.
- Reopening a minimized Settings window deminiaturizes it; retained reopen preserves position.

Tests use unique temporary frame-autosave names and clean those test names. Verify style/standard controls, native save/restore and hosting resize. These tests establish native configuration/hosting contracts, not complete fullscreen interaction or reference visual acceptance. Actual green-button entry/exit, minimize/restore, close/reopen, live resized layouts and process-relaunch restoration require the packaged acceptance phase.

## Phase 2 — reference inventory and unified navigation

After references arrive, create a page/control inventory with columns: reference frame/state; visible label; navigation path; existing preference/store; production reader/action; preview dependency; persistence/error/permission behavior; acceptance test; remaining gap.

Reproduce observed sidebar/header/subtab/section hierarchy, row spacing, typography, materials, selection/hover/focus states and resize behavior using native controls. Move current sections without discarding functionality. Place DynamicIsland-only Agents, Messages, camera navigation, recording, widgets and diagnostics in coherent reference-compatible sections. Retain useful native recovery access and category-specific defaults.

A visible enabled control must have a real action/binding. An unsupported capability must explain its actual limitation. Do not enable decorative controls, imitate an unavailable provider action, or replace production authority with preview state. Preserve saved preferences when moving/relabeling controls; use migrations only for evidence-backed schema changes.

Acceptance: every current pane/capability remains reachable; keyboard and VoiceOver navigation; selection/focus survives appropriate view changes; existing preferences restore without destructive reset; all reference pages accounted for.

## Phase 3 — controls and interactive previews

Use existing production preview components and SettingsAudit as the coverage spine. Connect changes to the same persisted settings/controllers the running island uses. Maintain synthetic/sandboxed previews for calls, messages, approvals, media, files, camera landmarks and recording; the preview must never place calls, send messages, start capture or request a permission implicitly.

For each control exercise toggle/picker/slider/text behavior, dependent controls, real provider capability, persistence after reconstruction/relaunch, live preview reaction and recovery/error state. Check defaults restore the intended category without resetting workspace layout, excluded apps, sessions or unrelated settings. Validate permissions through explicit actions only.

Acceptance: no enabled dead control, no contradicted preview, no preference lost on navigation, no second camera/draft/session system, no confidential content in diagnostics.

## Phase 4 — recorded island presentation

The existing 34.016667-second reference yields approximate visible shell-edge motion: repeated opens about 450ms, closes 280–300ms, output drawer open about 300ms and close about 370ms. These are presentation observations, not click latency or exact spring response parameters. Output drawer adds approximately 43% visible shell height. Recorded pixel sizes need matched native scale calibration; the complete top-shoulder contour is partly cropped.

Execute the earlier plan in dependency order:

1. Align the existing motion/choreography authority with recorded overlap, asymmetric shell movement and restrained content entrance. Normal at shell speed 1× is the reference baseline; apply existing faster/slower preset intent consistently without slowing direct drag feedback.
2. Fit broader visible shoulders/lower corners using the existing fill/glow/path resolver, fixed top anchor, notch exclusion and Media clearance.
3. Extract/reuse the navigation presentation below the shell in the existing overlay accessory space. Preserve central navigation, current destinations, saved customization, Agent/Message authority, real-click pointer anchoring and camera-local routing. Treat the gap as bounded interaction space; compose with Tray accessories without overlap.
4. Replace output Menu presentation with the recorded lower inline drawer, using the current real output backend. Propagate intrinsic height through existing layout; preserve transport positions, scoped interaction ownership, Escape and truthful selection/error handling.
5. Add the horizontal Apps landing presentation for real existing destinations/capabilities with independent/system artwork. Preserve current tool detail views. Launcher scrolling must not also page the island. Icons visible in the recording do not authorize fabricated Weather/OCR functionality; establish actual capability before wiring those tiles.

Do not copy proprietary assets/decompilation, introduce another overlay window/navigation engine, or transplant unrelated public code. The current public Droppy checkout does not supply identified implementations for every newer control visible in the clip.

## Phase 5 — actual native acceptance and correction

Use a fresh isolated packaged build. Do not replace an installed app or terminate an existing copy that may own sessions. Distinguish acceptance subprocesses from normal app instances.

For Settings, capture each reference page and its changed-control/preview states at matched size, appearance and scale. Compare screenshots, then exercise the underlying behavior; static similarity is not completion. Test keyboard, focus, resize/minimum size, native fullscreen entry/exit, minimize/restore, close/reopen and restored frame after relaunch. Test Reduce Motion, reduced transparency, increased contrast and unsupported/error states. Keep screenshots restricted to the relevant synthetic Settings content.

For island motion, repeat opens/closes, Home/Tray/Apps transitions, drawer open/close, app-row scrolling and mid-animation reversal. Compare normalized frame sequences. Use two recorded pixels for calibrated stable-edge comparison and two frames at 60fps for selected temporal landmarks as proposed targets; document exceptions and recalibrate rather than declare perfect parity prematurely.

Run existing regression fences for camera/Mirror ownership, physical-input precedence, collapsed gestures, Media seek/Spotify margin, exact Agent approvals/Terminal retention, Messages composer/confirmation, recording recovery, editor Apply/Cancel, AirPods, notch/glow and Reduce Motion. Correct observed discrepancies within scope.

## Phase 6 — validation and delivery

During edits run affected focused checks only. At completion: `git diff --check`, Debug build, full suite, Release build, isolated package, strict helper signatures and deep/strict app signature. Ponytail review the exact intended changes and their connected callers/tests before any push. Report actual screenshots, exercised controls and remaining gaps.

Preserve this active branch. Never stage generated/research/pre-existing dirty work implicitly. Commit/push only within the user's authorized delivery scope; no merge is authorized. If pushing, verify local/remote SHA agreement, actual final-head CI, current base divergence and conflict state.

## Explicit gates

- **Current:** missing authoritative Settings master plan and reference frames. Only independent audited requirements can be completed without them.
- **If encountered:** first-time camera/microphone/capture/Automation/Accessibility consent, provider credentials or purchases. Finish deterministic independent work before reporting the exact required user action; do not bypass or reset protections.
- **Physical acceptance:** automated/synthetic checks cannot establish human camera gestures or unseen hardware behavior. Report precisely which live behavior was exercised.

Done means all specified reference states and existing capabilities have traced, working, persistent controls; responsive and safe previews; verified native window behavior; evidence-backed motion fidelity; passing required checks; preserved existing work; and an exact gap report. Compilation or screenshot similarity alone is insufficient.

## Checkpoint validation

- Window foundation compiled in the Debug test build. Three native window tests pass, including frame restoration without an explicit test save call and hosting surface resize.
- Focused Settings/AppSettings run with opt-in audit/render artifacts enabled: **67 tests, zero failures, zero skips**. The preference audit verifies the existing 202 published AppSettings entries remain covered.
- Generated 13 native hosted Settings preview renders and the control audit in the temporary acceptance directory. Inspected island, media and Message-hover renders. The snapshot fixture initially omitted island preview dependencies and rendered an empty shell; it now receives the production preview dependencies. The affected snapshot test was rerun successfully and its populated island render inspected.
- Artifact directory: `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-settings-rebuild-p1wcgd8q/`. These are baseline native component renders, **not** packaged-app screenshots or Droppy comparison evidence.
- `git diff --check` and preservation checks pass: all 393 pre-existing recorded file hashes unchanged; index, branch and HEAD unchanged. Only intended Settings source/tests and this new execution plan differ from the checkpoint baseline.
- Scoped Ponytail review checked the retained-window caller, native autosave, minimized reopen, flexible root and test isolation. No broad redesign was made without references.
- Release build and isolated package completed at `/tmp/dynamicisland-settings-test-i8yunlqu/DynamicIsland.app`; all three helper strict signatures and the app deep/strict signature passed. This ad-hoc test package does not replace the installed app and was not launched automatically.
- Not run yet: full suite/CI, actual fullscreen/minimize interaction, packaged Settings page screenshots or 1:1 comparison. The reference-driven rebuild remains blocked on the missing document and frames; the isolated package is ready for manual window-behavior acceptance.


Upgrade DynamicIsland using the complete **Settings 1:1 Master Plan v3**.

Start with `CODEX_START_HERE_v3.md`, then read the full v3 master plan, both implementation addenda, the frame audit, and all visual references.

Preserve every requirement from v2, including contextual file conversion/compression, stable-footprint widget dragging, horizontal and vertical widget placement, smooth native motion, fully interactive Settings previews, accessibility, and native fullscreen/minimize/close.

Implement the additional v3 details and validate all `V3-01` through `V3-15` scenarios alongside the inherited acceptance tests.

Do not stop at UI mockups or produce fake working controls. Use real SwiftUI/AppKit integrations and verify actual behavior against the references.

Preserve the current branch, existing work, and active functionality. Do not merge any PR without explicit authorization.

Implement in verified phases, with native app testing, screenshot comparisons, performance measurements, documented limitations, and precise progress reports.