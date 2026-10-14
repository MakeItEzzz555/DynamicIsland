# Native release integration — 2026-10-14

## Preserved inputs and Git ownership

Integration checkout: `/Users/makeiteasy3/DynamicIsland-worktrees/native-release-integration`, branch `release/native-island-integration`. A fresh independent common repository was created outside Documents; the existing repository's broken Codex checkpoint ref was left intact. Original rescue/audio/Claude worktrees were never edited, reset, cleaned, stashed or switched.

- Production origin/main: `2ad101e960401202adc1ec748cfedebf6707571e` (fresh fetch).
- Camera PR #32: `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`, open, target fix/live-activities; its #31 lineage is included through ancestry, without merging either PR.
- Rescue snapshot: `e567b8b`; the current rescue source/test/scripts match it. Only native-ux-rescue.md differed, so that validation document was carried forward separately.
- Clipboard/Camera/File Tray/activity widgets A–F: Claude `2de2824`.
- Claude G plus copied Codex audio: `f0a1b544bf54a44524e8c2ef8602b44a166f89f2`.
- Original Codex backend: `fedfc065ab82a486f9da3d87b85b22f3cbf3a5a8`.
- Focused notch menu: `dee5b3aaf09a8530d76d0c0259947d1c02f3f428` (26 focused tests, 0 failures), pushed with matching remote SHA before integration.
- Merge A–G: `732800c`; original audio provenance merge: `273ce19`.

Rescue copied.sha256 manifest hash: `aab83ad10d30293653c47cbb7a05a4743956d886fe7ba206dcca42084e35c3a7`
Full source/index preservation records: `/tmp/dynamicisland-release-preservation.json`. Original rescue and audio index/HEAD/files remain unchanged. Claude independently advanced from 2de2824 to f0a1b54 while work was running; those changes are its own committed milestone G, not integration writes into its worktree.

## Reconciliation

The rescue was applied once through e567b8b. Range-diff and merge-base inspection show camera/#31 lineage shared unchanged. Backend contents at original fedfc065 and Claude cf4bd26 are byte-identical for Audio sources, native tests, package usage-description patch and the contract. The original backend branch was merged for provenance; there is one set of types/files, not two capture services. The uncommitted alternative Codex renderer was excluded. Claude's gradient/visualizer and widgets remain authoritative.

The only textual A–G merge conflict was in IslandRootView's delayed collapsed-hover guard. Resolution retains BOTH the native-menu ownership veto and Claude's visualizer hover veto, so a pause/play target cannot expand the shell and menu tracking cannot mutate it.

## Reviewed integration corrections

- Native editor release no longer invokes resignKey directly. Apple's installed NSWindow.h explicitly documents resignKeyWindow as an override point that must not be invoked directly. Public app activation/key-window ordering is limited to explicit editable keyboard targets; native deactivation releases owned keyboard engagement. A stale/non-key editor cannot deactivate another active editor.
- Main eligibility follows the mounted editable responder; ordinary island/button/menu interaction does not acquire it. This preserves the preferred input window across reactivation instead of returning key to another main window.
- Native fixture window transitions are settled BEFORE a click. Subsequent typing stays immediate. Keyboard windows are visible on the active screen instead of offscreen, so key-window assertions exercise an actual usable surface. Original assertions remain; additional assertions check exact responder and key ownership in every repeat.
- Added production AgentPromptEditor hierarchy coverage: immediate character, Return, Shift-Return, delete, private named-pasteboard paste (general clipboard unchanged), IME Return suppression and responder retention.
- G's task-group timer did not enforce a three-second quit timeout because structured concurrency waits for its children. The misleading race/claim was removed; normal termination awaits Codex's shutdown, including pending teardown. A hung native HAL cleanup remains a manual audio-safety gate; no forced process killing was added.
- Capture status distinguishes silent unverified buffers from established non-silent access. Tooltip no longer claims capture is off while media is paused or Reduce Motion is active. Output-change suspension is described accurately.
- Call visualizers and Settings previews do not subscribe to live spectrum. Replayed identical publications are ignored before presentation smoothing, avoiding re-subscription redraw churn.
- Native hosted audio tests attach Claude's real renderer to a window, use Codex's fake mailbox/controller lifecycle, verify low/high measured bands change its PNG and verify injected live providers do not change synthetic previews. No live audio or private media is captured.

## Gates and deferred stages

Claude H (lock-screen Settings preparation/final Settings ownership checkpoint) has not been supplied as a committed completion artifact. A clarification was requested; its active worktree is untouched. The Settings Live Audio row from the alternative local renderer is not blindly transplanted over H. G already supplies a functioning explicit Live Audio context-menu switch.

Private SkyLight surfaces remain unimplemented/disabled. No independent per-app gain controls or mixer are enabled. System-volume follow-up belongs on a separate focused branch AFTER this composition reaches its stable checkpoint; it is not silently represented as completed.

Human acceptance still requires authorization to replace the running app and request live camera/system-audio access. No replacement, permission request, TCC reset, signing-identity change, private helper installation or main merge was performed. Physical notch, Finder four-zone drags, actual camera sharing, real audio/music response and cross-application human keyboard delivery remain distinct from synthetic hosted evidence.

Validation results and package/CI evidence are appended after completion.


## Current verified checkpoint

- Debug build passed: 8.56 seconds.
- Final native adapter run: 22 tests, zero failures, zero skipped, 4.753 seconds. Includes 11 keyboard tests (both previously recurring failures plus the new real composer hierarchy/main policy), two window-hosted audio tests and nine notch-menu tests.
- Full Swift suite: 2,494 cases; 2,452 passed, 42 skipped, zero failures, 235.606 seconds. No assertion was weakened to obtain this result. Earlier failing runs are retained in `/tmp/dynamicisland-release-focused.log` and keyboard diagnostic logs; they are not hidden as historical passes.
- DSP synthetic 512-frame processing: mean 1179.808µs, p95 2204.750µs, 10,666µs audio interval. This is a real synthetic processing measurement, not live HAL/display-pacing acceptance.
- Camera v4 synthetic stationary pinch: prior displaced anchor 35.718pt vs stabilized 0pt in the 640×360 / .15… .85 calibration fixture; one press, zero ghost drags. No camera images/landmarks were recorded, and no physical gesture acceptance is claimed.

Logs: `/tmp/dynamicisland-release-debug.log`, `/tmp/dynamicisland-release-full.log`, `/tmp/dynamicisland-release-onscreen-input.log`. Native menu test posts Escape only to its own app queue; named-pasteboard fixture does not read/change the user's general clipboard. No normal app replacement was performed. A normal process was independently observed at PID 75630, `/private/tmp/dynamicisland-package-wuBiGy/DynamicIsland.app`; that process change was outside this integration work.

## Packaged acceptance and signing

Release build passed (343.59s); isolated packaging passed at `/tmp/dynamicisland-native-integration-package-03v3ugqz/DynamicIsland.app`. All three helpers passed strict verification and the app passed deep/strict verification. The package is ad-hoc signed, has no TeamIdentifier/hardened-runtime claim, and is not Developer ID/notarized production proof. Info.plist retains honest NSAudioCaptureUsageDescription and NSCameraUsageDescription, minimum macOS 14.6. No signing identity was changed.

The awake-display packaged keyboard probe found post-event access already authorized, but could not acquire visible isolated peer/composer ownership; it sent ZERO input events. Cross-process acceptance is NOT verified. Its mounted normal-beat helper delivered two display callbacks over 15.702ms; this is not pixel-level production collapse timing. Report: `/tmp/dynamicisland-native-integration-keyboard-acceptance/keyboard-acceptance.json`.

Packaged Settings acceptance passed native green-button fullscreen entry, keyboard exit, restored regular frame, minimize/restore, close/reopen route retention, native Back/Forward, panel-size reset, workspace editor Escape/cancellation, file popup ownership/cleanup and isolated preference persistence. Camera stayed off. Captured only its own Settings window with public ScreenCaptureKit; no personal desktop content. VoiceOver remains unverified. Warm native display-link delivery mean 26.410ms / p95 155.767ms / maximum 169.469ms; cold p95 167.054ms. These are observable callback gaps, not evidence of smooth pixel pacing. Report/screenshots: `/tmp/dynamicisland-native-integration-settings-acceptance/`.

Reviewing these screenshots found the old right-click Settings/Hide choice no longer matched the restored authoritative context-menu route. The integration removes those misleading controls and documents the fixed native menu instead. The persisted key/schema is retained untouched for compatibility. Acceptance was updated to verify those obsolete controls are absent; the real native menu tests continue to verify dispatch and disabled Clipboard behavior.

Graphify AST update ran only in the isolated integration checkout (17,944 nodes / 52,579 edges). Its parser flagged a pre-existing MediaAdvancedControls.swift construct; Swift builds succeed. Generated graph/cache output is intentionally excluded from the new source commit.

Ponytail review inspected exact keyboard/menu/audio changes and their connected lifecycle/callers/tests. Confirmed fixes are recorded above. Expected load is one local Mac/user; no new dependencies, polling loops or duplicate services. Release verdict remains BLOCKED by Claude H/final ownership checkpoint, physical keyboard/menu/Finder/camera/audio acceptance, observed display callback gaps and production signing readiness. System-volume external observation/coalescing and genuine per-app routing are NOT implemented by this integration.

## Release-diff hygiene

The rescue snapshot's generated graph changes are excluded from the eventual main diff by an index-only restoration in the OWNED integration repository, commit bb287fd. This leaves the generated/current graph files on disk and preserves every original checkout, index and checkpoint ref. No source/user file was deleted. The original rescue/audio hashes, index hashes and HEADs reverified unchanged; final record `/tmp/dynamicisland-release-preservation-final.json`. Claude's eight differences are exclusively its independently committed G milestone; no file is missing.

Final review after the narrow Settings correction: 41 focused tests passed, zero failures, zero skipped (5.213s). No other production writer or local build was launched by this agent. Required Debug/full/Release/package rerun results follow below; historical results above are identified separately.

The first final rerun after removing obsolete controls reported 2,494 cases / 42 skipped / 2 failures: SettingsAuditTests correctly found the legacy key misclassified as behavioral, and the historically intermittent SettingsWindowTests local button failed to dispatch. The audit now classifies the retained hidden key as deprecated (same stored schema). The native Settings fixture waits for observable app/key-window acquisition and lays out its hosted surface before sending input; the press assertion is unchanged. A focused rerun then exposed the menu fixture's missing production becomesKeyOnlyIfNeeded/hidesOnDeactivate configuration; the fixture now matches actual OverlayWindowController.configure. The no-key-steal, native Escape and button action assertions are retained.

## Integration correction files

Production: App/DynamicIslandApp.swift, App/SettingsNativeAcceptance.swift, Overlay/OverlayWindowController.swift, Views/AgentConsoleViews.swift, Views/LiveAudioVisualization.swift, Views/ModuleViews.swift, Views/SettingsAudit.swift, Views/SettingsReferencePages.swift, Views/SettingsReferencePreviews.swift (all under Sources/DynamicIsland).

Tests: AudioWidgetIntegrationTests.swift (new), IslandKeyboardAcquisitionTests.swift, LiveAudioVisualizationTests.swift, NotchContextMenuTests.swift, SettingsWindowTests.swift (all under Tests/DynamicIslandTests). Documentation: this record and the preserved newer native-ux-rescue.md. Menu commit dee5b3a has its independent nine-file scope recorded in docs/validation/notch-context-menu.md.

Audit/menu/Settings recovery focused result: 24 cases / 23 passed / 1 skipped / zero failures, 2.332s. The skip is the opt-in Settings audit file-writing test, not native acceptance.

## Final-source regression blocker

After the audit and fixture corrections, Debug passed (6.304s). The complete final-source run executed 2,494 cases, 42 skipped, and ONE failing native Settings input case with THREE assertions: testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy could not acquire active-app/key-window ownership within the bounded readiness window, then the original button count remained zero. All other cases passed; the Settings audit and native menu ownership/Escape assertions are green. Run duration 198.108s (Swift command), 196.170s (XCTest). Log `/tmp/dynamicisland-release-final-full.log`; previous audit/input failures retained in `/tmp/dynamicisland-release-final-full-pre-audit.log`.

This is the previously reproduced native Settings input/activation blocker, not evidence that it is harmless. No assertions were weakened, no test was disabled/skipped and no repeated full runs were used to conceal it. The earlier 2,494/zero-failure run above remains historical. Final release/merge readiness is BLOCKED even if hosted isolated input cases or remote CI happen to pass.

Final synthetic DSP measurement: mean 897.368µs, p95 1230.583µs for 512 frames against the 10,666µs interval. Actual HAL/audio interruption acceptance remains unverified.

Final Release build passed (191.09s); fresh isolated package passed (7.037s) at `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-native-release-final-package-psgjp7gs/DynamicIsland.app`. Executable SHA-256: `7ec48ca1dfdc7779ce48c0b90300d92ccc97eb422dde87a3dbff2a3aac0faf68`. All three strict helper signatures and the app deep/strict signature passed. It remains ad-hoc signed; no hardened runtime/TeamIdentifier/notarization claim. Package/plist/signature record: `/tmp/dynamicisland-release-final-package-verification.json`.

The FINAL package's Settings acceptance passed fullscreen/minimize/restore/close/reopen, editor cancellation and file-popup cleanup again. `obsoleteNotchChoicesAbsent=true`; camera remained off. Warm display callback mean 21.238ms / p95 140.811ms / max 151.675ms, so pixel pacing is still not accepted. Reports/screenshots: `/tmp/dynamicisland-native-release-final-settings/`. This successful packaged Settings run does not erase the separate full-suite native activation failure.

Reviewed source checkpoint includes the focused menu, both provenance merges and these integration corrections. Safe to preserve/push as a DRAFT integration checkpoint; NOT approved to ship/merge. Final remote SHA/CI and current main divergence are reported in the PR after push. No live application replacement or privacy permission prompt was performed.
