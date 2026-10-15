# Thinking Orb identity and release continuation — 2026-10-15

## Ownership and provenance

This isolated release candidate descends from `403ef80c51e6d8a0dff25e66affc45a12198691f`, preserving the integrated Lock Screen, Send, media sizing, slider ownership and wing sizing fixes. Worktree: `/private/tmp/DynamicIsland-orb-identity-20261015`; branch: `fix/agent-orb-identity-20261015`.

The user reassigned completion to Codex after Claude exhausted its tokens. Codex owns implementation and orchestration; one bounded Codex reviewer independently audited the existing release objectives, implemented the separately owned audio correction, and reviewed the orb correction. The main Codex agent independently reviewed the audio patch. There is **no Claude approval and no Claude–Codex consensus**. The earlier dual-agent supervisor run and its uncommitted Settings lanes were preserved.

The dirty camera/Settings/communications checkout, installed application, active user sessions and permissions were not changed. No push, PR update, merge or installed-app replacement is part of this continuation.

## Duplicate Thinking Orb cause and correction

`AgentEventStore.sessions` intentionally retains historical generations. Its `activeSessions` property excludes retired generations, but `AgentCompactPresentation.make` received the complete history and filtered only each snapshot's state. A retired generation that still said `working` or `thinking` therefore remained eligible. `AgentCompactRoutineTrailingView.otherSessions` correctly treats different full instance IDs as different views, so a retired generation became another mini orb beside the Claude icon. A current permission state could also reorder the current generation ahead of the retired one.

The fix is in the shared compact projection, before activity filtering, priority sorting, summary, visible limit and overflow. It selects the highest generation per full provider/native session ID. Thus a new idle or terminal generation cannot revive an old active orb, and genuine independent sessions, including two Claude sessions or equal native IDs from different providers, remain distinct. History and all existing orb rendering, state mapping and animation code are retained.

The routine and permission branches in `IslandRootView.compactIslandContent` are mutually exclusive. `AgentCompactPermissionContent` creates no orb. No duplicate view was hidden and no permission capability was broadened.

## Additional release correction

Independent review found `ApplicationAudioDiscovery.reconcileRouting` and the coalesced slider loop could continue after `await` following disable. They could recreate audio taps while the switch was off. A routing lifetime generation now invalidates that work across off/on transitions, separately from discovery refresh generations. Pending slider ownership is generation-bound so an old completion cannot erase a new slider request. Existing gain curves, saved levels, engine teardown and error handling are preserved.

Three deterministic tests suspend fake hardware tap creation and exercise disable during reconciliation, disable with a queued slider level, and rapid off/on with a new slider owner. They check actual fake-engine routing and output samples, not only the switch label. They do not establish physical audibility.

## Regression and native evidence

- Before the orb correction, the first two identity tests failed with 14 assertions. Log: `/private/tmp/dynamicisland-orb-before-fix.log`.
- The initial corrected focused run passed 115 tests, including all three audio interleavings. Log: `/private/tmp/dynamicisland-orb-focused.log`. Additional overflow and Reduce Motion coverage was added afterward; final complete-suite evidence is recorded below after execution.
- `AgentPresentationTests` covers repeated snapshots, newest-generation selection before inactivity filtering, distinct same-provider and cross-provider identities, and distinct-agent overflow.
- `AgentOrbLifecycleTests` exercises three resumed generations, permission arrival/resolution, native production-root expansion/collapse, and Reduce Motion. The native fixture starts an inert managed provider, registers an exact actionable permission in `AgentApprovalController`, checks the exact owner/key, resolves it and confirms delivery. The actual trailing SwiftUI view is rendered and its width checked for an extra orb.
- The native root fixture supplies the morph-completion edge normally emitted by `OverlayWindowController`. Earlier blank root captures came from the fixture omitting that edge and overwriting initial collapsed captures with its incomplete returned-collapse state; they are not acceptance evidence. Final captures use distinct transition names.
- Native fixtures use synthetic agent data, in-memory settings, no real provider transport, and no user approval decisions. They do not replace physical Mac acceptance or establish live provider behavior.
- Final mounted-native capture run: **3 tests passed, zero failures** in 65.951 seconds. Log: `/private/tmp/dynamicisland-orb-native.log`; captures: `/private/tmp/dynamicisland-orb-native-20261015/`. The main agent inspected initial and returned-collapse Thinking/Working, exact-owner permission controls, expanded Agents, resumed generation 2, and Reduce Motion captures. Single-agent compact captures show one left orb and one right Claude icon, without a historical secondary orb. The permission surface shows its existing owner and controls without adding an orb. Representative files: `normal-generation-2-thinking-2-collapsed.png`, `normal-generation-1-permission-2-collapsed.png`, `reduced-generation-2-resolved-2-collapsed.png`. This is production-root SwiftUI/AppKit fixture evidence, not installed-app/live-provider or physical-input acceptance.

### Complete-suite result

One isolated full run executed **2,630 tests, 45 skipped, 6 failed assertions in 2 test cases**; exit status 1. The unchanged failures were `IslandKeyboardAcquisitionTests.testReturnShiftReturnDeleteAndRepeatedReopenUseExactEditor` (panel key ownership on reopen, five assertions) and `SettingsWindowTests.testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy` (app/key activation not acquired, one assertion). Log: `/private/tmp/dynamicisland-orb-full-suite.log`. All new orb and audio tests passed in this run. This is **not** a passing full-suite gate.

A fresh-process run of the two affected classes executed **17 tests, one failure**: every keyboard acquisition test passed, while Settings still could not acquire active/key-window ownership before native click dispatch. Log: `/private/tmp/dynamicisland-orb-native-input-isolated.log`. Existing validation documents (`native-audio-foundation.md`, `widget-ux-overhaul.md`, `native-ux-completion.md`) record the same native input failures on earlier revisions. The new orb fixture does not activate/deactivate the application or change activation policy. This evidence does not establish a production regression caused by the orb change, nor does it close native acceptance. No assertions, deadlines or skips were weakened.

## Review of carried-forward release objectives

The independent Codex reviewer inspected connected production callers and tests for Lock Screen privacy and deferred artwork activation, Agents Send first visit, per-app gain, desktop/Lock Screen Standard and Large media composition, slider regions and page-swipe guards, wing icon metrics/layout, and packaging. Its only concrete must-fix finding was the audio lifecycle race corrected here. The main agent reviewed that implementation; the peer's orb code verdict was approve. The peer also independently inspected the corrected native captures. Both Codex code reviews approve the intended seven-file change, with no remaining concrete critical/high finding. The release verdict remains blocked by the failed full-suite/native input and physical acceptance gates. Final committed-SHA acknowledgement is kept in the final reviewer handoff and `/private/tmp/dynamicisland-orb-final-review.json`; Claude has not reviewed this candidate.

## Release packaging

Canonical `Scripts/package_app.sh` completed successfully; Release build time **264.44 seconds**. Package: `/private/tmp/dynamicisland-orb-release-20261015/DynamicIsland.app`; log: `/private/tmp/dynamicisland-orb-release-package.log`. `codesign --verify --deep --strict --verbose=2` passed for the app, and separate `codesign --verify --strict --verbose=2` checks passed for all three relay helpers. Signing is ad-hoc; Developer ID/notarization is not claimed. The package has not replaced or launched over the installed app. Generated Graphify outputs were refreshed and excluded from the delivery diff.

## Gates retained

Physical acceptance remains required for authenticated Lock Screen artwork handoff/password focus and Standard/Large controls, first-visit physical Send interaction, audible two-app gain and output routing, slider/tab gestures, and notch-wing geometry on the actual display. No secure-screen test, user audio cutover or permission change was performed.

The draft PR remains unmerged. This local candidate has not been pushed, so final-head remote CI and remote SHA agreement cannot be claimed. The previous private SkyLight/platform and audio route limitations in `integration-corrections-2026-10-15.md` still apply. Claude sign-off is unavailable under the user's revised workflow.
