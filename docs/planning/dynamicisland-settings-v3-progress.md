# Settings v3 implementation checkpoint

> Historical checkpoint below: the reference package has since been restored. See the current restored-reference section at the end and `docs/settings-parity/v3-acceptance-matrix.md` for current scope and results. The original 2,275-test evidence remains intact.

## Authority and preserved work

Branch: `feature/camera-hand-navigation`. Starting HEAD: `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`.

The new instructions appended to `dynamicisland-settings-rebuild-execution-plan.md` have been read and preserved. They name the v3 reference package, but do not contain its documents, frames or acceptance scenario definitions. `CODEX_START_HERE_v3.md`, the full master plan, both implementation addenda, the frame audit and Settings reference frames have not been located. The supplied island recording does not show the Settings pages.

**V3-01 through V3-15 remain undefined and unverified.** This checkpoint does not replace those specifications or claim a complete v3 rebuild. Reference-specific pages, controls and visual comparisons require the actual package. Existing work, user preferences, active app sessions and the Git index remain intact. No commit, push or merge is part of this checkpoint.

## Implemented independent requirements

1. Native Settings window: resize, standard close/minimize buttons, fullscreen eligibility, minimum content size, retained window, autosaved position/size and minimized reopening. The SwiftUI root follows the window instead of imposing a fixed 920×700 surface. Three AppKit window tests cover configuration, frame restoration and hosting size; actual packaged fullscreen/minimize interaction remains a manual check.
2. Correct Settings island preview fixture: supply its production preview dependencies rather than render an empty shell. This fixes test evidence; it is not a new Settings interaction.
3. Stable island footprint during widget dragging: replace the old minimum-size floor with an exact drag-start width and height. Both Media and Agents editors use the same layout-store authority. Prospective placement previews continue inside that footprint; drop/cancel resumes intrinsic sizing through the existing shell motion.
4. Drag cleanup: leaving edit mode clears the drag, target, intent and geometry hold, including when AppKit retires the source before its end callback. Existing Apply/Cancel persistence remains authoritative.

No new layout engine, animation dependency, camera session, file-operation backend or preference schema was introduced.

## Audited inherited capabilities

| Requirement | Current evidence | Limit |
|---|---|---|
| Context-sensitive conversion | Existing quick actions resolve explicit selection or a sole item. Native ImageIO offers supported PNG/JPEG/HEIC/TIFF targets and preserves originals; real JPEG output is decoded in tests. | No claim of document/audio/video conversion or exact v2 menu fidelity without the specification. |
| Compression | Existing background-operation controller runs real ZIP compression, with independent operation IDs, progress, cancellation and cleanup. Tests create real archives and cancel a running `ditto` operation using synthetic files. | Visual references for the requested contextual presentation are missing. |
| Horizontal/vertical widget placement | Existing directional drop resolver, column stacking, preview/application and persistence tests cover both axes. | Model/hosted evidence does not establish physical drag fidelity against the missing video frames. |
| Native motion and accessibility | Existing editor springs and Reduce Motion behavior are retained; accessible arrangement actions remain present. | No claim that timing matches Droppy or that all Settings previews are fully interactive. |
| Settings persistence and coverage | Existing Settings audit covers 202 published AppSettings entries; the prior focused Settings run passed 67 tests. | Reference-specific control coverage cannot be mapped yet. |

## Evidence collected in this checkpoint

- Focused workspace/file-operation run: 71 tests, zero failures, one opt-in screenshot test skipped. The run explicitly enabled real compression cancellation/concurrency tests.
- Native editor regression: actual hosted SwiftUI/AppKit drag-source callbacks reach the layout store, hold both axes, release on end/external edit exit and perform no persistence writes. Callback injection is not a physical WindowServer drag.
- Performance: 200 frozen-slot hover/preview resolutions took about 43 ms; 20 hosted edit/cancel cycles produced 40 editor body evaluations, zero surviving handles and zero persistence writes. A 300-projection benchmark averaged about 0.070 ms per projection. These are model/fixture timings, not display frame pacing or packaged-app CPU measurements.
- Native renders: 54 workspace/preview images and 11 operation-state images generated in `/tmp/dynamicisland-settings-v3-validation-245wz_3t/`. Inspected populated island preview, Tray preview and compression progress. They are native component renders, not Droppy comparisons or full packaged Settings screenshots.
- AST graph update succeeded in `/tmp/dynamicisland-v3-graph-validation-r3afx0gf/`; original dirty graph files were not changed.
- Preservation checkpoint: all 398 pre-existing recorded dirty/untracked file hashes, including the user's appended plan, remained unchanged. Intended new changes are outside that pre-existing dirty-file set.

## Final checkpoint validation

- Final full suite with real compression and native render checks enabled: **2,275 tests, 35 opt-in skips, zero failures** in about 171 seconds. Log: `/tmp/dynamicisland-settings-v3-validation-245wz_3t/full-suite-production-router.log`.
- Additional focused geometry/native editor run after fixture changes: 15 tests, zero failures. Existing native Add/Cancel/Done/Reset assertions still verify exact persistence counts.
- Earlier combined render runs exposed a test-order-sensitive failure in the fixture's hand-built click events. Isolated partitions and the standard full suite passed. The fixture now uses the production `CameraInteractionRouter`, its native nonactivating window contract and AppKit event pump; the final combined run passes. No production Button action or business controller was bypassed. The exact internal AppKit reason for the old event-construction failure was not established.
- Debug build passed. Release build passed (about 147 seconds). `Scripts/package_app.sh` completed in an isolated output directory.
- Package: `/tmp/dynamicisland-settings-v3-validation-245wz_3t/package/DynamicIsland.app`. All three helper strict signatures and app deep/strict signature passed. The ad-hoc test package was not automatically launched and does not replace the installed app.
- `git diff --check` passed. All 398 pre-existing recorded file hashes remain unchanged, including the user's appended plan, graph files and unrelated generated work. Branch/HEAD/index unchanged.
- Scoped Ponytail review against HEAD `1cd01b4d3a90b49f497176d0c9c19f91eda904a1` plus this intended working diff traced both editor callers, preview/drag callbacks, geometry scheduling, drop/cancel/Apply, Settings window ownership and native test isolation. No blocking finding remains in the checkpoint's changes. Actual packaged window behavior, physical dragging and reference fidelity remain unchecked.
- The final AST graph update was performed in the isolated graph copy. The original dirty graph remains untouched.
- No commit/push/merge occurred; no new CI result is claimed for the uncommitted working tree.

## Remaining acceptance

- Provide the reference-package folder containing the start document, full v3 master plan, addenda, audit and frames; reconcile it with the preserved execution plan before making reference-specific changes.
- Actual packaged Settings fullscreen/minimize/close/reopen and physical widget-drag observation.
- Reference-matched screenshots, interactive preview acceptance, v2 inherited scenarios and V3-01 through V3-15.
- Packaged-app motion/frame-pacing and resource measurements after the reference-driven implementation is available.

## Restored-reference continuation — 2026-10-13

The missing-reference condition above is historical and resolved for Settings: all eight specification files and all 89 Settings frames are installed. The complete v3 master, embedded v2/addenda and standalone frame audit have been read. The duplicated video SHA is recorded in `docs/settings-parity/reference-ledger.md`. Supplemental workspace video/frames and contextual-file still remain missing; their written scope is implemented independently and video fidelity is not claimed.

### Current implementation

- Eleven native sidebar pages in three reference groups, native toolbar/history, persistent route/sidebar and per-page scroll restoration; all existing feature panes remain under Modules.
- Production Settings window, native app menu commands, green-button fullscreen and Ctrl-Cmd-F exit, resize/restoration and retained reopen. Panel-size reset affects the Settings window, independently of shell/motion reset.
- Actual menu bar/Dock access preferences, asynchronous coalesced login-item status checks, General notch picture choices using protected interaction authority, timed shelf-reference retention with protected selection/actions and original preservation.
- Original offline media, clipboard and timer previews, shared production workspace editor with transactional Done/Cancel, real shortcut draft editing/reorder and per-conversation Messages fixture interaction. No camera, real message, Apple Events, recording or provider session starts in previews.
- Declarative Local module import with descriptor-bound bounded JSON reads, exact schema/capability validation, review, SHA receipt, persistence/removal. Code/plugins/archives are not executed.
- Separate lock/unlock sample sound preferences with explicit system-sound audition; unsupported secure Lock Screen integration is disclosed.
- Shared production Multi/High Alert sample rendering; three external-display visibility choices and independent fullscreen-overlay policy for the existing single island window. Exact approval/focus/HUD/menu/drag/transient ownership defers hiding until its release events. No second Terminal host or duplicated island is created.
- Reviewed privacy-filtered appearance + workspace transfer, strict rejection of future/lossy layouts, legacy appearance compatibility, persisted page/vertical placement, and rollback on failed persistence. Two-stage typed-confirmation preference reset preserves personal content/privacy/access/credentials and sessions; camera navigation stops explicitly as described. Introduction replay routes to actual Settings; changelog links to the project's releases.
- Six ordered audio tiles (five native encoders available, MP3 unavailable), actual stereo-video extraction, native image conversion/ZIP, original/collision preservation, cancellation cleanup and optional chosen conversion folder. Physical popover/folder-picker acceptance remains unchecked.

### Validation checkpoint

The original **2,275 tests / 35 skips / zero failures** baseline is preserved above. The first complete continuation run passed **2,321 tests / 35 skips / zero failures** in 183.988 seconds. A final review then added protected menu/sheet/drag release notifications and enabled only the safe in-memory Messages reply scenario; **47 affected tests / one skip / zero failures** passed. The final full repetition, Release/package/signature and packaged native results will be recorded below after completion. Current preference audit covers **215** published entries.

All **394** recorded protected graphify, .playwright, research and pasted-plan files compare unchanged against the resume snapshot. Branch and HEAD remain `feature/camera-hand-navigation` / `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`; index remains empty. No commit, push or merge occurred.

This is an implementation checkpoint, **not a completed v3 parity claim**. The current page/scenario ledger and exact outstanding independent features are in `docs/settings-parity/v3-acceptance-matrix.md` and `00-inventory.md`. Native screenshots, callback timings or unit tests do not establish full VoiceOver, physical widget dragging, external display/Spaces behavior or missing-video fidelity.

### Native fixture correction found during final repetition

The second 2,321-test repetition exposed two hosted editor test failures (eight assertions): the fixture queued down/up into one event pump, rather than modeling the temporal separation of a confirmed physical pinch. The first full run had passed. This timing/focus dependency is fixture evidence; it is not a proven production camera failure. The fixture now models a real temporally confirmed pinch: one down is delivered/pumped before the later up, with an assertion that **exactly one down/up lifecycle** reached the owned window. It does not retry clicks, weaken business assertions or change production pointer/drag routing. The connected hosted editor/window/camera routing run passed **33 tests / zero failures** (20.392s), including an explicit exactly-one-down/up delivery assertion. Settings native input now also follows production app activation. Final full suite repetition remains required.

### Compact file actions and foreground-app privacy continuation

- FileActionPresenter replaces the page-bound SwiftUI popover. Accepted drops and toolbar requests now share one native popup anchored to the actual island region, without requiring expansion/Tray mounting. Exact approvals, HUD/focus/native/menu/drag/morph ownership defer it. Popup focus survives a native folder chooser; current request identity and owner are released after native closure, preserving a newer pending drop. Reduce Motion suppresses the popup animation.
- Timed native fixture release now uses a single 80ms common-mode Timer, so AppKit's synchronous tracking loop can receive mouse-up. This fixes the blocking behavior found in the intermediate fixture. The 36 connected native tests pass; a complete **2,325-test / 35-skip / zero-failure** run then passed in 190.423s. These are real hosted events, not physical hand/Finder acceptance.
- General Hide in apps uses the existing installed-app scanner and public foreground activation events. Add/remove/reorder and bounded deduplicated bundle IDs persist. Own-app hiding is rejected; protected exact/native interaction defers suppression; no background sessions are terminated. Exclusion/privacy configuration survives the explicit hard reset and is excluded from appearance transfer. **35 focused tests / one skip / zero failures** pass; the latest full repetition is running. The preference audit now covers **216** published entries.
- Prior packaged native results are in `/tmp/dynamicisland-settings-v3-resumed-native/settings-acceptance.json`: all window/history/picture/display-selection/editor-cancel booleans pass, one own-window SCK capture succeeds, and the latest callbacks still exceed the motion budget. The newest popup/app-exclusion code requires another Release/package/native repetition.

Latest combined full validation: **2,326 tests, 35 skips, zero failures** (194.595 seconds execution, 194.950 seconds reported total), log `/tmp/dynamicisland-v3-app-exclusions-full-suite.log`. Current Release rebuild is running; the newest popup and app-exclusion package/native evidence must be repeated before marking this milestone verified. Original protected files/HEAD/index remain unchanged.

### Resumed native verification and Clipboard behavior — 2026-10-13

- The owned destination chooser now cancels on File Actions disappearance and ignores late responses; 38 connected file/audio/editor/window/display tests passed with zero failures.
- Debug passed (3.50s), Release passed (146.68s); an isolated package and all three strict helper plus deep/strict app signatures passed. Package pointer: `/tmp/dynamicisland-v3-continuation-package-path`.
- Packaged native popup presentation/ownership/cleanup and native Settings history/picture-choice/preferences/panel-size reset passed. This run did **not** accept fullscreen, minimize or close: public CoreGraphics reports `mainDisplayActive=0`, `mainDisplayAsleep=1`; there were zero display callbacks and the window was not enumerated by ScreenCaptureKit. Prior awake-display passes are retained separately. The user has been asked to wake the display; no display/TCC changes were made automatically. Evidence pointer: `/tmp/dynamicisland-v3-continuation-native-path`.
- Inspected the actual native popup screenshot: AppKit selected the minimum 360pt fitting width, hiding two of the six audio tiles behind horizontal scrolling and truncating the explanatory caption. Production presentation now requests a screen-bounded 570pt width and wraps the caption; connected native width assertion passes. Settings previews remain flexible.
- Added the reference Clipboard Behavior group and real Copy + favorite preference, off by default. Only a successful history-item pasteboard write may mark it favorite; incoming monitoring never favorites items. Existing favorites are preserved at the 50-favorite boundary. Preference reload, archive restoration, reset preservation, failed writes and exact capacity are tested. The 217-published-preference audit passes.
- Clipboard/audit/navigation/transfer focus: 57 tests, one opt-in skip, zero failures (1.645s). The following native-width/Clipboard/audit/navigation run passed; exact count is in `/tmp/dynamicisland-v3-native-width-focused.log`. Full suite and Release repetition for this newest behavior are running.
- All 394 protected graphify/.playwright/research/pasted-plan files compare unchanged. HEAD and index remain unchanged; no commit, push or merge.

- Newest full suite executed **2,328 tests / 42 skips / one failure** (182.253s). The exact failure is the pre-existing live visibility test `MetalSendInteractionTests.testEnabledNativeHostUnpausesClockAndUnmountPausesIt`: its window was occluded while the main display was asleep. No assertion or production animation behavior was weakened. An awake-display repeat is required; the earlier 2,326/35/zero run remains prior evidence only. The command correctly stopped before Release on this failure; affected preview/Clipboard/popup/audit tests and Release are now running separately.
- Copy + favorite is also synchronized into the isolated synthetic Clipboard preview; its existing test now exercises favorite-on-copy and explicit unfavorite, without monitoring or accessing the system pasteboard. This synchronization was added after the full-suite test binary was compiled, so its focused repetition is required separately.

- Preview synchronization/native popup/Clipboard/audit repetition passed **49 tests / one opt-in skip / zero failures** (6.073s). Native-width/Clipboard/audit/navigation run passed **55 tests / one skip / zero failures** (6.074s). Counts overlap and are not added together.
- Isolated AST graph update passed: 16,172 nodes / 47,981 edges / 439 communities; original graph files remain protected. Log: `/tmp/dynamicisland-v3-copy-favorite-graph-update.log`.

### Basket instant appearance and Shelf automatic expansion continuation

- Added durable Basket Instant appear (default off) through the existing 10Hz external-file drag monitor and existing Basket summon callback. No new monitor or file ownership system. It fires once at drag start, suppresses later shakes for that generation, resets on release/stop, and retains unsupported/self-owned drag rejection. Mid-drag preference changes do not rearm a fired gesture. The existing shake setting is disabled while instant appearance owns summoning. Focused Basket/manager/audit/Clipboard preview run: **43 tests / one skip / zero failures** (1.635s).
- Restored the existing dormant `expandOnHover` preference as the native Shelf Auto-expand control. Existing hover delay/generation/session checks route only informational-background hover through the existing geometry-preparing expansion callback. Message peek/composer and exact compact approvals keep their hover interaction. Shared production callback rejects protected approval/HUD/native/menu/file-drag/focused-reply ownership before expansion. No generic taller-hover policy or camera input engine was added. Focused regression is running.
- Newest Clipboard package (before Basket/Auto-expand): `/tmp/dynamicisland-v3-clipboard-package-path`; Release passed (169.25s), all helper strict/app deep-strict signatures passed. New native screenshot confirms all six tiles and full caption fit; popup presentation/ownership/cleanup passes. Native evidence pointer `/tmp/dynamicisland-v3-clipboard-native-path`. Main display remained asleep; logical fullscreen entry was reported but displayed-window/fullscreen fidelity and minimize/close are not accepted from this run.

- Combined Basket/hover/geometry/communications/audit/preview regressions passed **62 tests / one opt-in skip / zero failures** (3.059s). Auto-expand persistence and category reset are now explicitly checked. Newest Debug/Release repetition is running; newest Basket/Auto-expand package does not yet exist. The audited preference count is **218**.

- Category-reset/hover/Basket/audit repetition passed **34 tests / one opt-in skip / zero failures** (2.922s); Debug passed (1.12s). No known blocking finding remains in the new policy logic: delayed hover is generation/session scoped, interactive hover never auto-expands, the controller revalidates exact/native ownership, and Instant appear is drag-generation scoped. Current full-suite acceptance is still blocked by the asleep-display live visibility failure; the passing old baseline is not substituted for this result.

- Scoped Ponytail review traced new Clipboard copy callers (full History and compact widget), preview isolation/reset/export keys, File Actions chooser cancellation and native owner release, Basket monitor/start/stop/suppression/presenter/retention, and Root hover scheduling through production geometry preparation and protected ownership. Existing bodies/frames, shell tokens and camera input routing remain authoritative. No code or permission bypass was introduced. Reviewed baseline SHA: `1cd01b4d3a90b49f497176d0c9c19f91eda904a1` plus these uncommitted changes. Physical Finder/Basket/hover behavior, VoiceOver and complete v3 fidelity remain unchecked.

- Latest Basket/Auto-expand Debug/Release passed (1.12s / 170.08s). All modifications remain uncommitted on the preserved branch. Package/native repetition and final preservation checks are underway. Awake-display full-suite/live window/physical hover/Basket acceptance is still required; independent v3 gaps remain in the inventory.

- Latest isolated package: `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-settings-v3-basket-hover-package-8hn8c1bn/DynamicIsland.app`. All three strict helper signatures and deep/strict app signature passed. Latest native mounted content/compact popup checks are in `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-settings-v3-basket-hover-native-e3l8qwv5/`. Popup show/owner/cleanup and persisted native choices pass. CoreGraphics still reports main display inactive/asleep; SCK cannot enumerate this window. Logical fullscreen enter/exit returns true, but displayed fullscreen/animation/minimize/close acceptance is **not** claimed.
- Latest graph copy update passed: 16,179 nodes / 48,009 edges / 447 communities. Original 394 protected files remain unchanged.
- Because Auto-expand touches the shared root expansion callback, another complete regression run is required and is running on the latest test binary. The existing live-visible Metal check may still fail while the display is asleep; it has not been disabled or weakened.

### Final resumed milestone evidence — 2026-10-13

- Latest full regression on Basket/Auto-expand/Clipboard behavior: **2,331 tests / 42 opt-in or environment skips / one failure** (181.204s). Log: `/tmp/dynamicisland-v3-basket-hover-full-suite.log`. Exact failure remains `MetalSendInteractionTests.testEnabledNativeHostUnpausesClockAndUnmountPausesIt` at line 69: the live host is occluded and the app inactive while the public main-display readiness check reports asleep/inactive. No assertion was weakened and no green-suite result is claimed. Awake-display repetition is required.
- Latest Debug, Release (170.08s), isolated packaging, three helper strict signatures and app deep/strict signature passed. The freshest package and native artifact paths are recorded above. Current native visibility is not accepted while the display is asleep. Focused counts overlap: 62 tests / one skip / zero failures and 34 tests / one skip / zero failures cover the newest behavior and category reset.
- Final preservation: branch `feature/camera-hand-navigation`, HEAD `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`, empty index, all 394 protected files unchanged. No commit, push or merge.
- Git integrity issue surfaced during final `diff --check`: two base objects became unreadable. Additive `git -c gc.auto=0 fetch --refetch origin` restored those source objects; `git diff --check` and HEAD tree reads now pass. Fetch still returned an error for a missing internal `refs/codex/turn-diffs/checkpoints/...` object, so fetch is **not** recorded as successful. No refs were deleted, no garbage collection/reset/clean was run, and no legacy worktree files were edited. The checkpoint reference remains an explicit tooling issue requiring separate recovery.
- Next verified-phase gate: wake/unlock the display, repeat the live-visible Metal/full-suite and native window/motion checks, and physically test external-file Instant appear and safe Auto-expand. Full v3 scope remains incomplete; remaining independent controls, global shortcuts, provider dependencies and missing-video fidelity are documented in the acceptance/inventory ledgers. This checkpoint does not turn the physical gate into a claim that all remaining implementation is complete.


## Phase v3.4 — Native productivity runtime checkpoint (2026-10-14)

### Preservation and approval boundary

Branch remains `feature/camera-hand-navigation`, HEAD `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`. Before edits, 460 pre-existing dirty/untracked file hashes were recorded in the checkpoint referenced by `/tmp/dynamicisland-v34-preservation-path`. No branch/index/checkpoint refs, permission grants, dependencies or persisted schemas have been changed. All unrelated work, sessions and preferences remain intact.

The user's v3.4 boundary says **“Ask before changing permissions, persisted schemas, dependencies or unrelated file ownership.”** Approval was requested for three additive UserDefaults keys: Shelf open-after-drop (default off), Shelf/primary-Basket reference synchronization (default off), and supported Shelf/Basket/Clipboard shortcut bindings (default empty). No answer has arrived. Runtime controllers, native recording UI and guarded entry points are prepared and reviewable, but production Settings/persistence/startup wiring is deliberately pending this specific approval. These behaviors are **not** described as completed production integrations.

### P0 evidence

- Public display readiness at the start of this phase: on-console/active/unlocked, main display awake.
- Previously failing Metal visibility check passes unchanged: one test, zero failures, 0.420s (`/tmp/dynamicisland-v34-metal.log`).
- Pre-runtime-change full regression passes: **2,331 tests / 42 skips / zero failures**, 162.791s (`/tmp/dynamicisland-v34-p0-full-suite.log`). This is the phase-start baseline, not validation of subsequent changes.
- Isolated packaged `--validate-settings` acceptance passed actual fullscreen enter/exit, green-button/key handling, minimize/restore, close/reopen, native preference choices and file-popup ownership/cleanup. Its report is under the directory referenced by `/tmp/dynamicisland-v34-p0-native-path`. Public ScreenCaptureKit captured only that process's Settings window; no normal live services or capture owner was started, and no other app was terminated.
- Physical external Finder drops, Basket Instant appear, Shelf hover expansion, widget dragging, multi-display/Spaces and complete VoiceOver remain unverified. Native fixture interaction is not physical acceptance.

### P1/P2/P3 runtime changes

- New `ShelfBasketSynchronization` uses existing Shelf/Basket stores and the shared temporary-file ledger. Opt-in runtime synchronization shares additions with the primary Basket, preserves selections, keeps removals local, never creates/opens a Basket and cancels queued work on disable. Additional Baskets remain independent. Existing capacity rules remain authoritative.
- Collapsed/expanded Shelf drop handlers now claim the same drag generation before asynchronous loading and complete only once. Cancellation, overlay-generation invalidation or disabled intake reject late publication; cleanup goes through `discardIfUnowned`, preserving borrowed originals and files retained by another owner. One exact accepted-file request owns any transient auto-open intent. The user preference remains pending approval.
- Fixed a prior automatic-hover guard that rejected accepted external drag expansion through a shared callback. Automatic hover now has its own guarded callback; accepted drops reuse the original geometry-preparing expansion authority.
- Prepared real public Carbon hotkey registration plus a native focused AppKit recorder for Shelf, Basket and Clipboard. Known enabled symbolic/system bindings and internal duplicates are rejected; exclusive-registration failures preserve the prior binding. One press delivers one action; release, stale IDs, Settings recording, cancellation and shutdown are handled. No event tap, Accessibility injection, dependency or permission change is introduced. Detection of every app/system shortcut conflict is not claimed. Production persistence, Settings mounting and app-startup wiring remain pending approval.
- Real presentation entry points reuse existing Overlay/Basket/Clipboard controllers and reject protected approval, text/composer, camera, HUD, file-drag, editor, menu and transient-window ownership. No alternate business actions are introduced.
- Escape cancels active file conversion through its existing task. Popup close restores the presenting responder only when focus is otherwise unclaimed. A new native corner test exposed an actual right-edge popup overflow; the presenter now bounds its native window to the presenting display after show. The assertion was retained and now passes.
- Final focused runtime set: **24 tests / zero failures**, 6.738s (`/tmp/dynamicisland-v34-final-focused.log`). It includes actual Carbon register/unregister/event-target routing, hosted native key-down/up recorder, protected owners, coalesced reference synchronization, stale/duplicate drops, native popup bounds/focus and all five supported native audio encoders. MP3 remains unavailable on this Mac.

### Observable performance and limits

Phase-start packaged acceptance measured 31.92s elapsed, 13.29s user CPU, 1.49s system CPU, 434,896,896-byte maximum RSS and 171,297,856-byte peak memory footprint. Its native display-link callbacks were cold mean 32.17ms / p95 180.09ms and warm mean 19.30ms / p95 113.35ms. The run includes screenshot rendering, page construction and deliberate settling; these numbers do not establish idle CPU, pixel presentation, physical input latency or smoothness. Outliers prevent claiming a frame budget met. Production-motion tokens and Reduce Motion remain unchanged.

### Final validation

Latest runtime Debug build passed (0.99s). Current full-suite, Release, fresh isolated package, signatures, native repetition and preservation results are recorded below when complete. No commit/push/merge or CI run is authorized or performed.

- Latest post-change full suite: **2,347 tests / 42 skips / two failures**, 178.128s (`/tmp/dynamicisland-v34-full-suite.log`). Failures: unchanged live-visible Metal assertion (app inactive/native window occluded) and SettingsWindow native local-pointer activation count (0 versus 1). Subsequent public CoreGraphics readiness check reports active=0, asleep=1 and session locked. The start-of-phase awake success is not substituted for this result; current green full-suite/native acceptance requires waking/unlocking and repetition. No assertion, test or production animation was weakened.

### Exact v3.4 intended file scope

Existing files patched without replacing prior work:
- `Sources/DynamicIsland/Modules/BasketPresenter.swift`
- `Sources/DynamicIsland/Modules/FileDragSession.swift`
- `Sources/DynamicIsland/Modules/FileShelfStore.swift`
- `Sources/DynamicIsland/Modules/FileTrayQuickActions.swift`
- `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
- `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
- `Sources/DynamicIsland/Overlay/FileActionPresenter.swift`
- `Sources/DynamicIsland/Views/IslandRootView.swift`
- `Sources/DynamicIsland/Views/FileActionPanel.swift`
- `Tests/DynamicIslandTests/FileActionPresenterTests.swift`

New runtime/test files:
- `Sources/DynamicIsland/Modules/ShelfBasketSynchronization.swift`
- `Sources/DynamicIsland/Modules/ProductivityGlobalShortcuts.swift`
- `Sources/DynamicIsland/Views/ProductivityShortcutRecorder.swift`
- `Tests/DynamicIslandTests/ShelfBasketSynchronizationTests.swift`
- `Tests/DynamicIslandTests/ShelfDropClaimTests.swift`
- `Tests/DynamicIslandTests/ProductivityGlobalShortcutTests.swift`

Evidence-only documents updated: this progress report, `docs/settings-parity/v3-acceptance-matrix.md` and `docs/settings-parity/00-inventory.md`. `AppSettings`, app-startup wiring, camera, Agent, media and notification source changes already present at phase start were preserved; no new changes were made to them.

### Scoped Ponytail / Apple Design / Taste review

Reviewed HEAD `1cd01b4d3a90b49f497176d0c9c19f91eda904a1` plus the intended v3.4 runtime/test changes. Traced both drop callers through one generation claim/completion, existing ownership cleanup, pending-file-action presentation, primary-Basket publishers and coalesced cancellation, exact protected owners, Carbon callback lifetime/registration rollback/stale IDs, native recorder release/cancel, and native popup close/focus. Load assumed: one local user, three global commands, existing bounded Shelf/Basket capacity. The newly exposed corner-placement defect was fixed and its native regression passes. No unrelated refactor or new dependency was needed.

Native principles retained: existing geometry/motion authority, interruptible ownership, Reduce Motion, explicit focused recording, keyboard cancellation and accessibility labels. Actual VoiceOver, physical multi-display, Finder/widget drags and sustained displayed motion are not established by these tests. Prepared opt-in controllers are intentionally not mounted as fake working Settings controls. **Verdict: prepared runtime changes pass focused validation; complete production delivery remains gated on preference-key approval and awake/physical acceptance.**

- Final shortcut review caught a concrete internal-menu conflict: Command-Control-F (Fullscreen) and Command-Shift-Z (Redo) were not protected by the three-command duplicate check. Candidate bindings now also match existing native menus/current keyboard layout, including standard menu factories before a Settings menu is mounted. Added regression assertions pass in the 24-test focused set (6.785s). The current final rebuild/regression repeats follow this correction.
- Locked-display packaged repetition: native file-popup show/ownership/cleanup and mounted page rendering succeed; mainDisplayActive=false/mainDisplayAsleep=true, fullscreen/minimize/close acceptance false and the Settings window was not enumerated for WindowServer capture. Report under `/tmp/dynamicisland-v34-native-path`; these blocked results are not substituted with the earlier awake result.

### Final correction verification

- Final Debug build passes (8.85s). After the native-menu conflict correction, the final full regression reports **2,347 tests / 42 skips / two failures**, 178.735s (`/tmp/dynamicisland-v34-full-suite-final.log`). The same live-visible Metal and native Settings local-click assertions fail while the Mac remains locked/asleep. All added v3.4 tests pass inside this run. The previous full result is historical; the newest result is not green.
- The focused 24-test set passed in 6.785s before the final one-line `NSApplication.shared` initialization hardening; the final full run verifies that hardening and all new tests. Historical focused results are not presented as a later run.
- Isolated source graph update passed: 16,309 nodes / 48,410 edges / 418 communities. Original `graphify-out` and `.playwright-cli` hashes remain unchanged.

### Next unfinished milestone / exact gates

1. **Approval:** add three opt-in preference keys (two default-off booleans and one default-empty, strictly validated three-action binding map). Then connect the prepared services through the existing app lifecycle, mount real native controls in Shelf/Basket/Clipboard/Shortcuts, and verify persistence/category reset/relaunch. Existing archive schemas and preferences stay intact; no new dependency is proposed. This stage is waiting on the user's explicit persisted-schema approval, not on implementation uncertainty.
2. **Awake display:** wake/unlock, rerun the unchanged Metal/native local-click checks and final full suite; repeat current packaged fullscreen/minimize/close/reopen. No sleep/security setting or assertion will be changed to obtain a passing result.
3. **Physical acceptance:** external Finder drag single delivery, Basket Instant appear, safe Shelf auto-expand/open-after-drop, native popup focus/Escape, real widget dragging, multi-display placement and actual global keyboard shortcuts. These require a user-controlled awake interaction session; synthetic/window-local events cannot establish them.

P1/P2 production activation is incomplete until gate 1 is approved and implemented. P0's current displayed acceptance remains blocked on gate 2. No entire v3/parity completion or green CI is claimed.

- Final corrected Release build passes (149.45s). `Scripts/package_app.sh` completes in the isolated directory `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-v34-package-zxfeqd0p/`; installed app and privacy identity are not replaced. All three helpers pass strict verification and the app passes deep/strict verification (`/tmp/dynamicisland-v34-signatures-final.json`). Packaged executable SHA-256: `20779f8afb04926c36175deb319753714834c40b37e8c78987ea5bbf9d8f9f14`. Existing Release warnings in FaceTime, Messages and the pre-existing Productivity Settings view are outside this phase and remain documented by the build log.

- Final corrected package `--validate-settings` completes with native file-popup show/owner/cleanup all true and mounted page renders under `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-v34-native-final-5xch01f8`. The main display remains inactive/asleep; fullscreen/minimize/close and WindowServer capture remain blocked. Native render evidence cannot prove displayed transitions or physical drag behavior. Process measurements are in `/tmp/dynamicisland-v34-native-final.log`; screenshots are synthetic own-window content only.

- Final preservation: 460 pre-existing dirty/untracked hashes checked; 448 unrelated files unchanged, 12 intended recorded-file patches, zero unexpected changes. All graph/.playwright/reference-research hashes remain unchanged. Branch/HEAD/index retained, no commit/push/merge. `git diff --check` passes. Exact intended current-file hashes are recorded separately in `/tmp/dynamicisland-v34-final-manifest.json` for review; the code map was updated only in the isolated graph copy.
- Latest locked native harness measured 65.54s elapsed / 12.67s user CPU / 1.28s system CPU / 362,577,920-byte max RSS / 149,326,784-byte peak footprint; it delivered **zero display callbacks**, so no frame-pacing/smoothness inference is valid. Logical fullscreen flags entered/exited, but displayed fullscreen remains unverified; minimize/close acceptance false. Latest native popup render was inspected: six ordered format tiles are visible, unsupported MP3 is disabled, native destination and ZIP controls fit. This is synthetic mounted-content evidence, not Finder or pixel/video fidelity acceptance.


## 2026-10-14 — Detached lower navigation and normal-first collapse

Implemented centered black navigation outside/below the shell, removed internal Clipboard/Settings buttons, retained notch-menu authority and workspace edit/reset transactions, removed the internal header footprint, enlarged shoulders 19→28 pt and lower radius 24→40 pt. Camera precision bounds include the footer; camera-triggered expansion remains prohibited. Normal-first collapse holds back activity content/sidecars until the existing closing spring completes; generation guards cover interruption. Agent Send has hover glow with the existing motion tokens and 34 pt target. Settings previews reflect the detached controls.

Focused UI/regression run: 188 passed; final connected callers: 61 passed; notification fixture regression: 32 passed. Final complete suite: 2405 cases, 2362 passed, 42 skipped, 1 native input failure with the display asleep; assertions unchanged. Debug/Release/package and strict helper/app signatures pass. No commit/push/merge. Fresh isolated package and detailed evidence: `docs/validation/detached-navigation-and-collapse.md`. Physical production collapse timing, hover glow and notch/footer usability remain unverified on the asleep display.

Final review also eliminated a no-op second morph when no activity waits (55 affected checks passed). Final production-source full suite: 2,405 cases / 2,362 passed / 42 skipped / 1 native Settings input failure. Metal Send native visibility passed. The final rebuilt isolated package and strict signatures pass; the display remains asleep, so visible packaged inspection is blocked.
