# Detached navigation and normal-first collapse — 2026-10-14

Base HEAD: `1cd01b4d3a90b49f497176d0c9c19f91eda904a1` on `feature/camera-hand-navigation`. No branch switch, commit, push, merge, preference reset, permission request, app replacement or termination of another copy.

## Implemented behavior

- Page controls live outside the shell, centered beneath it, in a black capsule. The existing page store, selected states, motion, native buttons and clicked-tab pointer anchoring remain authoritative. Workspace customization moves alongside the lower tabs; toggle, Customize Tabs and Reset retain the expanded editor's own transaction authority.
- Clipboard and Settings buttons no longer occupy the expanded header. The existing native notch dropdown retains both actions. Native menu/keyboard accessibility routes are preserved.
- No internal header row or tab-to-content gap remains. Content uses the existing notch lane and 6 pt optical top clearance; semantic widget frames are unchanged. Side/bottom clearance accommodates the enlarged corners.
- Expanded concave shoulder: 28 pt (previously 19). Expanded lower radius: 40 pt (previously 24). Existing shared fill/clip/stroke/glow path and native spring tokens remain in use. Local public Droppy source confirms an expanded lower radius of 40; its default top radius is 10. The larger shoulder is an independent visual adjustment, not a claim of measured trial-build identity.
- The NSPanel reserves the footer even for narrow widgets. Existing accessory ownership, passthrough, hover bridge and stable panel morphing apply. Tray actions retain their own row above navigation. Page-count changes update the panel budget. Camera precision mapping includes navigation; the camera expansion prohibition remains unchanged.
- Collapse follows existing child exit, then targets the normal collapsed profile with no activity content, sidecars or hover preview. The existing closing spring's `.removed` completion releases the normal-return hold and resolves the newest waiting activity. Return generations reject stale completions; reopen and shutdown cancel the hold. No motion preset, speed or delay is changed.
- Enabled Agent Send hover includes a visible cyan/white glow, using the existing hover spring and 34 pt action target. Disabled/pressed states do not retain hover glow; Reduce Motion retains visual feedback without scale motion.

## Changed files

Production: `Views/IslandRootView.swift`, `Overlay/OverlayWindowController.swift`, `Overlay/IslandLayoutStore.swift`, `Geometry/NotchGeometryService.swift`, `Views/AgentVisualEffects.swift`, `Views/SettingsPreviews.swift`, and one interaction-frame getter in `State/CameraNavigationController.swift`.

Tests: new `DetachedIslandNavigationTests.swift`; updated geometry/preview expectations in `IslandShellRadiiTests`, `CompactHeaderAndClearanceTests`, `IslandNavigationControlsTests`, `ZeroChromeWorkspaceGeometryTests`, `SettingsNavigationStructureTests`, `SettingsUXPolishTests`; `MetalSendFeedbackTests`; bounded SQLite wait in the shared `MessagingAuthorityTests.swift` temporary fixture writer. The latter fixes an observed `SQLITE_BUSY` race with monitoring reads; assertions and production notification code remain unchanged.

## Evidence and review

- 188 focused tests passed (10.639 s), including camera pinch/drag/palm, native tab/edit dispatch, notch-menu routing, top/corner geometry, unchanged widget sizes, mounted previews, Media/native controls and Send visibility.
- Final connected-callers check: 61 passed (7.922 s) after preserving editor toggle/reset ownership and footer exit animation.
- Notification fixture correction: 32 passed (3.250 s), including all 21 monitor resilience cases. Before correction the isolated A9 writer reproducibly returned SQLite status 5 rather than 101, then failed to observe the nonexistent row.
- Native hosted production surface/media/footer render: `/tmp/dynamicisland-detached-nav-native.png`. Synthetic media; no provider commands, desktop capture, camera frames or private data. This demonstrates real SwiftUI/AppKit rendering and composition, not physical production-window acceptance.
- Native footer input dispatch passed for every available tab and customization; zero system cursor movements. Existing clicked-tab, physical input, approval, message and camera ownership regressions are retained.
- Ponytail review covered connected geometry, page-count changes, popup authority, editor reset/toggle ownership, hover containment, collapse interruption, generation cancellation and input arbitration. Base SHA and file hashes: `/tmp/dynamicisland-detached-nav-review.json`.

## Final validation

Final run results and preservation evidence are recorded below when complete. The initial full run reported 2,405 cases: 2,360 passed, 42 skipped, 3 failed cases / 4 assertion failures. Two cases require a visible active native host; one was the corrected temporary SQLite writer race. CoreGraphics subsequently reported displayActive=0 / displayAsleep=1. Native assertions were not weakened.

## Remaining physical acceptance

Keep the Mac awake/unlocked, open the fresh package, and observe the production overlay: lower-tab reachability and page morphs; notch dropdown; enabled Send hover glow; normal-size collapse before the waiting activity grows; interruption by immediate reopen; corner/shoulder appearance on the physical display. Existing other copies/sessions must be managed by the user. No full physical acceptance, shipped-Droppy 1:1 animation match or VoiceOver walkthrough is claimed from fixtures.

### Earlier validation before the no-activity return guard

- Final complete suite: 2405 cases; 2361 passed, 42 skipped, 2 failed / 2 assertion failures (193.292 s). Only failures: `MetalSendInteractionTests.testEnabledNativeHostUnpausesClockAndUnmountPausesIt` and `SettingsWindowTests.testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy`, with the display asleep. The notification case and all resilience tests pass in this full run. Full native suite is not green.
- `git diff --check`: exit 0. Debug: exit 0 (4.424 s). Release: exit 0 (167.612 s). Packaging: exit 0; all three helper strict signatures and app deep/strict signature: exit 0. The subsequent fixture-only change does not alter packaged production source.
- Fresh package: `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-detached-navigation-package-lxis9alw/DynamicIsland.app`. No installed bundle was replaced.
- Packaged visible UI inspection: blocked by displayActive=0 / displayAsleep=1. The user's awake/unlocked display confirmation is pending; no fullscreen or physical visual acceptance is fabricated.
- No CI or remote branch updates: changes remain uncommitted as authorized.

### Final current-source validation

- Review removed a no-op activity morph when the normal-return completion sees unchanged geometry. No waiting activity means no additional interaction suspension. Final affected checks: 55 passed (2.483 s).
- Complete suite on the final production source: 2405 cases; 2362 passed, 42 skipped, 1 failed (225.142 s). The sole failing case is `SettingsWindowTests.testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy` (line 70). Metal Send native visibility passed in this run. The final display probe still reports active=0 / asleep=1; active packaged inspection is blocked. No assertion was changed to obtain a pass.
- Final `git diff --check`: 0. Debug: 0 (4.162 s). Release: 0 (169.533 s). Package: 0. Three strict helper verifications: 0. App deep/strict verification: 0.
- **Use this package:** `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-detached-navigation-package-9aye5m1t/DynamicIsland.app`. Earlier package paths in the historical evidence section are superseded.
- The current source/test review hashes and preservation audit are outside the repo in `/tmp/dynamicisland-detached-nav-review.json` and `/tmp/dynamicisland-detached-nav-preservation-final.json`. Original dirty graph files are retained; AST graph refresh runs in the isolated validation copy.

### Native UX rescue follow-up

The current uncommitted follow-up reduces the detached gap to 3 pt and separates click-through hover corridors from rendered accessory hit regions. The normal-first sequence now uses logical closing-spring completion followed by two actual display callbacks, with current-token validation before scheduling and completion. Existing spring presets and child-exit authority are unchanged. This supersedes the earlier `.removed` timing statement, not its historical validation results. See `native-ux-rescue.md` for current tests and unverified native gates.
