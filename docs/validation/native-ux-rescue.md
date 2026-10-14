# Native UX rescue checkpoint — 2026-10-14

Branch: `feature/camera-hand-navigation`. Starting HEAD: `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`. This phase layers changes on the uncommitted Settings/camera/navigation tree. No commit, push, merge, branch change, preference reset or termination of another normal app instance.

## Implemented scope

### Keyboard ownership

- The nonactivating island panel uses `becomesKeyOnlyIfNeeded = true`. The editable native Agents text view explicitly opts in through `needsPanelToBecomeKey` and `acceptsFirstResponder`.
- The panel acquires key status and the exact clicked text responder synchronously before forwarding the click. The previous deferred `makeKey` callback is removed. Ordinary button clicks do not claim keyboard ownership.
- Native editor engagement is published only when its window is key and it is the exact first responder. Deferred publications revalidate that identity. Each native Agents editor owns a unique focus lease in `IslandLayoutStore`; dismantling an old session editor cannot clear a new editor's hold. Existing native input callers keep their existing default owner.
- Key resignation releases engagement without destroying the draft. The overlay's Escape monitor now releases the exact composer before the general collapse route. Active presentations keep their existing Escape authority; marked IME composition receives native Escape instead. Dismantling releases only the exact editor's ownership. Automatic responder changes do not create an engagement hold.
- Draft editing remains enabled during submitting/working/stopping states. Submission still requires the existing ready state and exact session controller. Harmless updates preserve selection; marked IME text is not overwritten, and marked Return is not converted into Send.
- Optional Debug diagnostics (`DYNAMIC_ISLAND_KEYBOARD_DIAGNOSTICS=1`) contain window identity, key state and responder type only, never text or keystroke contents.

Apple authority: [NSPanel.becomesKeyOnlyIfNeeded](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded), [NSView.needsPanelToBecomeKey](https://developer.apple.com/documentation/appkit/nsview/needspaneltobecomekey).

### Detached navigation

- Normal shell-to-navigation gap changes from 8 to 3 pt. The production footer and Settings preview share this metric. Panel budget and File Tray's separate preceding accessory row continue using the existing metrics.
- Hover containment includes padded controls and narrow vertical corridors between adjacent rendered rows, limited to their shared horizontal extent. Accessory removal removes its own region immediately.
- Pointer passthrough and host hit-testing use exact rendered shell/accessory frames, with no expanded-shell hover padding in click eligibility. A hover corridor does not capture a desktop click. Native menus, focused editing, transient owners and file drags retain their existing protection.

### Collapse/activity sequence

- Child exit still precedes contraction. The normal collapsed profile still hides waiting activity content/sidecars.
- The normal-return gate now responds to the existing spring's logical completion rather than waiting for its entire removal tail. A visible host then observes two actual `NSView.displayLink` callbacks before resolving the newest waiting activity.
- No new spring, motion preset or delay preference is introduced. Unchanged activity geometry still skips the extra morph. Inactive/occluded presentation does not wait for display callbacks that cannot arrive.
- Normal-return generation is checked before scheduling the display beat and again before completion. Expansion/suspension cancel the display link and normal-return token. Display readiness follows the host's display, including external displays.
- Two display callbacks are **not** proof of two pixel-perfect normal-sized frames. Pixel-level production timing, interruptions and visual continuity remain native acceptance work.

Apple authority: [logical animation completion](https://developer.apple.com/documentation/swiftui/animationcompletioncriteria/logicallycomplete), [view display link](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)).

## Exact changed implementation files

- `Sources/DynamicIsland/Agents/AgentInteractiveControl.swift`
- `Sources/DynamicIsland/Views/AgentConsoleViews.swift`
- `Sources/DynamicIsland/Views/IslandRootView.swift`
- `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
- `Sources/DynamicIsland/Overlay/ExpandedHoverContainment.swift`
- `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
- `Sources/DynamicIsland/App/DynamicIslandApp.swift`
- `Sources/DynamicIsland/App/IslandKeyboardNativeAcceptance.swift` (new inert acceptance entry point)

New tests: `IslandKeyboardAcquisitionTests.swift`, `DetachedNavigationReachabilityTests.swift`, `NormalCollapseDisplayBeatTests.swift`.

## Native acceptance entry point

With an awake, unlocked, **idle** Mac, run the fresh packaged executable with:

```sh
"<fresh-package>/DynamicIsland.app/Contents/MacOS/DynamicIsland" --validate-keyboard /tmp/dynamicisland-keyboard-acceptance
```

This starts an inert production composer and its own isolated peer process. It does not start Agent transports, normal app services or camera capture. Public CoreGraphics events are posted only with existing event-post authorization, an active isolated peer and a visible owned fixture window. No permission is requested. Only tagged event counts and fixture submissions are recorded; text is never serialized. Only the owned peer is terminated. Cursor/application restoration avoids overriding a new physical user's input/activation.

`keyboard-acceptance.json` reports peer activation, exact composer ownership, immediate WindowServer key delivery, Escape release, three reopen cycles and native display-beat callback timing. A successful fixture report does not establish physical production session switching, paste/IME behavior, full island collapse geometry or Spaces acceptance.

## Current results and limitations

- Noninteractive final focused run: **35 tests, 0 failures, 0 skips** (0.071 s), `/tmp/dynamicisland-rescue-pure-final.log`.
- An earlier awake native run passed all seven then-existing composer cases and display-beat cases. It still failed the existing `SettingsWindowTests.testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy` assertion. That source and assertion are unchanged.
- The subsequent broader run: 74 cases, three failed cases/five assertion failures (18.217 s). Failures: system cursor changed during the camera no-cursor-movement check; composer engagement/release; one of three Return/reopen cycles. The cursor assertion directly demonstrates physical movement during this run; other failures need an idle rerun rather than an assumed cause.
- Display readiness changed between awake and asleep during early runs. New keyboard/display-link tests explicitly skip asleep-display fixtures and retain their behavioral assertions. Existing tests were not weakened.
- Current full-suite and cross-process acceptance results must be recorded after the final source freeze. Historical 2,405-case results from the preceding navigation phase are historical.
- Physical keyboard/paste/IME/session switching, menus/Spaces, hover trajectories with File Tray drags, external displays, and pixel-level normal-to-activity timing remain unverified until an idle native interval.

## Desktop camera dependency

The requested new desktop input capability is not implemented in this checkpoint. The user's message ends at “One authority coordinator selects”; output-selection, permissions, safety and acceptance requirements after that sentence are missing. The existing island-local camera backend, v4 gesture pipeline, single capture session, calibration and expansion prohibition remain intact. No desktop mode preference or default enablement has been added.

## Review and preservation

Apple Design/Taste review applies native keyboard intent, reachable grouping, consistent spatial anchors, existing motion and Reduce Motion. Ponytail review follows connected panel/editor/layout callers, stale callbacks, scoped focus owners, hidden-display behavior, passthrough and inert probe boundaries.

Starting hashes and source snapshots: path in `/tmp/dynamicisland-rescue-preservation-path`. Build/package/signature evidence: `/tmp/dynamicisland-rescue-final-checks.json`. Final preservation results and source-review hashes are recorded separately in `/tmp/`; unrelated graph output is refreshed only in an isolated copy.

## Final executable checkpoint

- Current-source connected checks: **62 cases: 61 passed, 1 optional audit-generation skip, 0 failures** (3.268 s). `/tmp/dynamicisland-rescue-final-callers.log`.
- Complete-suite run before the final fixture, passthrough and Escape corrections: **2,420 cases: 2,373 passed, 43 skipped, 4 failed cases / 10 assertion failures** (216.562 s). `/tmp/dynamicisland-rescue-fullSuite.log`. The acceptance-fixture dependency failure was fixed without changing its audit assertion; that audit and affected caller checks now pass. Three native input cases still require an idle reproduction: `CameraPreviewControllerTests.testV4PinchFormationClicksNativeButtonAtAnchorOnceAndLossCannotClick`, `IslandKeyboardAcquisitionTests.testResignKeyReleasesEngagementWithoutDestroyingDraft`, and `IslandKeyboardAcquisitionTests.testReturnShiftReturnDeleteAndRepeatedReopenUseExactEditor`. The suite is **not green**, and it was not rerun after the final caller corrections.
- Final `git diff --check`: 0. Debug: 0 (3.994 s). Release: 0 (204.508 s). Isolated packaging: 0. All three helper strict signatures: 0. App deep/strict signature: 0.
- Fresh current package: `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-native-ux-rescue-package-brconkkz/DynamicIsland.app`. Previous package paths are superseded.
- The packaged global-event keyboard probe was **not run** during the user's active input session. No cross-process or physical production acceptance is claimed. Pixel-level collapse timing remains unmeasured; two display callbacks are a scheduling contract, not pixel evidence.
- Final review hashes: `/tmp/dynamicisland-rescue-review.json`; preservation audit: `/tmp/dynamicisland-rescue-preservation-final.json`. 491 pre-existing dirty/untracked files remain byte-identical, six pre-existing files changed intentionally, no files are missing or unexpectedly changed, and HEAD/index remain unchanged. Other changed source files were clean at the starting checkpoint or are new intended files.
- AST graph refresh succeeded in the isolated graph copy; original dirty graph and Playwright output remain untouched. No commit, push, merge or current-source CI run.
- Next gate: provide the missing desktop-camera specification after “One authority coordinator selects” and an awake, unlocked, idle interval for native acceptance and exact-failure reproduction.


## Settings entry repair — 2026-10-14

The user's current packaged build did not reliably expose the top-center actions menu. The production background NSView is a lower sibling underneath full-frame SwiftUI content; hit-testing through that content is not a reliable menu route. The previous menu region also stopped at the physical camera cutout.

The panel now routes only an exact enabled notch-region left press to the existing production background menu before ordinary content dispatch. Window identity, hidden ancestry, native-control exclusions, shell contour and morph gating are revalidated. Ordinary background/control clicks and existing right-click behavior retain their routes. No additional Settings controller, menu implementation, event monitor, global click, preference or dependency was introduced.

The menu region includes at most 6 pt of existing empty notch clearance, bounded by contentTop and the shell bounds. Non-notched displays expose a 120 pt maximum centered region only within existing top padding. It never extends into page content or outside the shell.

Current-source focused results: **14 passed, 0 failed, 0 skipped**, 1.940 s (`/tmp/dynamicisland-notch-focused.log`). The new native-hosted tests mount production IslandSurface content in IslandOverlayPanel, verify collapsed and expanded routing behind full-frame native content, invoke the actual Settings menu action, and reject content, corner, excluded-native-control and disabled/stale menu routes. Existing native content hit-testing and detached navigation tests pass. These tests prove routing and menu action authority; they do not claim a human production click or menu-tracking acceptance.

Immediate recovery: reopening the exact running package with `open -a` invoked the existing applicationShouldHandleReopen path. System Events inspection reported the real **DynamicIsland Settings** window and the process was frontmost. No normal app process was terminated. The running copy still predates this source repair until a user-controlled restart into the fresh isolated package.


Repair build results: Debug passed (5.08 s), Release passed (189.50 s), isolated package passed, all three helper strict signatures and app deep/strict signature passed. Fresh package: `/tmp/dynamicisland-notch-settings-package-Lhe6aj/DynamicIsland.app`.

Connected caller run: **43 cases: 40 passed, 1 skipped, 2 failed cases / 4 assertion failures**, 12.059 s (`/tmp/dynamicisland-notch-connected.log`). The two failures reproduce the already-recorded keyboard cases `testResignKeyReleasesEngagementWithoutDestroyingDraft` and `testReturnShiftReturnDeleteAndRepeatedReopenUseExactEditor`. All notch, background, detached navigation and camera-native routing cases passed. No assertion was weakened. A new complete suite was not run for this narrow repair; the prior full-suite failures remain unresolved.

Ponytail review: exact panel dispatch, existing menu callback, geometry callers and native exclusions reviewed. No controller/business authority was duplicated. Physical notch/menu selection on the repaired package remains unverified pending a user-controlled restart; the existing running app is intentionally retained. HEAD, index and all unrelated source/preferences remain intact. The required graph query refreshed only `graphify-out/cache/last_query_stamp`; graph refresh otherwise ran exclusively in the isolated graph copy (16,673 nodes / 49,659 edges).


## Notch gesture conflict correction — 2026-10-14

The preceding Settings-entry repair intercepted notch mouse-down and immediately opened a menu in both presentation states. That prevented the user's saved click/hold/double-click behavior. This correction retains exact notch routing but treats a press as a lifecycle: down arms the 550 ms hold, drag beyond 10 pt cancels, and up terminates the hold. The panel routes drag/up to the same weakly owned native handler. Generation/configuration/detachment cancellation remains in place; the scheduled hold also checks the physical left button is still down.

Collapsed short click invokes the existing expansion callback only when Expand on Click is enabled. Collapsed holds invoke the existing configured long-press authority; release after a hold cannot also expand. Expanded short click opens the existing menu only after the system double-click interval, so a second click can cancel that pending menu and invoke the existing configured double-click action. Expanded holds invoke their configured action. Accessibility activation follows collapsed click authority. No preference was changed.

Read-only preference evidence: Pointer/Trackpad source, gestures enabled, Expand on Click enabled, Expand on Hover disabled, confirmation disabled; both long-press mappings are Open Settings. Expanded double-click is saved as None and therefore intentionally has no action.

Current-source focused suite: **32 passed, 0 failed, 0 skipped**, 2.155 s (`/tmp/dynamicisland-notch-gesture-tests.log`). New panel lifecycle regressions cover collapsed click versus hold, release-after-hold suppression, expanded double-click, movement cancellation, and collapsed accessibility activation. Existing geometry, menu authority, navigation and gesture coordinator tests passed. Human hold/double-click acceptance remains pending; deterministic lifecycle completion is not a claim of physical input acceptance. No full-suite rerun or CI claim in this bounded repair.
