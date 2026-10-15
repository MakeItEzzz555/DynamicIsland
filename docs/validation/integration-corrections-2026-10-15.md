# DynamicIsland: post-limit integration corrections (2026-10-15)

## Scope / provenance

Local integration branch `fix/complete-integration-acceptance-20261015`, based on `integration/lockscreen-media-send-mixer` after commit `eb709a5`. Changes were copied from Claude's *uncommitted* lock-screen work without touching its worktree, followed by reviewed cherry-picks `9712c4f` (slider gesture ownership) and `608e5b1` (agent wing icon size). This work does **not** merge into `main` or replace the running app.

- **Expanded-island media:** `eb709a5` selectively reverts the accidental `cf670a1` redesign. Compact (1x1), Standard (2x1) and Large (2x2), their editing/persistence and `CompactMediaLayoutTests` are restored.
- **Lock Screen media:** Standard and Large are separate **lock-screen-only** sizes; independent persistence, native Settings preview, transport controls, artwork, visualizer, scrubber and supported volume.
- **Secure artwork:** the media target is resolved and captured at the locked artwork click; only a confirmed macOS unlock triggers one launch. Pending intents are discarded on timeout, unsafe ownership changes or feature disable. No password handling or application launch from previews.
- **Per-app mixer:** pill drags register control regions in the existing canvas gesture system. Global page swipe navigation is rejected for drags starting inside them. Independent Core Audio routing is preserved.
- **Agents:** primary Thinking Orb and Claude/Codex provider icons are 22pt; secondary orbs 16pt; geometry tests ensure outer-edge anchoring and physical-notch clearance. First-visit Send repair from `91e1dd0` remains intact.

## Validation evidence

- Focused combined test run: **197 tests, 0 failures** (`/private/tmp/dynamicisland-integration-takeover-focused.log`).
- Source-open/Lock Screen coordinator tests after click-target hardening: **14 tests, 0 failures** (`/private/tmp/dynamicisland-integration-takeover-open-source.log`).
- Full Swift test suite: **2,617 tests, 45 skipped, 1 failed**. The only failed test was `SettingsWindowTests.testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy`, due to XCTest app/key-window activation not acquired after the entire suite, clearly reported as **INCONCLUSIVE (environment)**. Assertion was not weakened or skipped.
- The same native Settings test, run in its own fresh XCTest process: **1 passed**, the click was dispatched and asserted, **0 failures** (`/private/tmp/dynamicisland-settings-pointer-isolated-20261015.log`).
- Full run log: `/private/tmp/dynamicisland-takeover-full-suite.log`.
- **Release packaging: passed** (240.43 seconds). The packaged app and every helper passed `codesign --verify --strict`; `codesign --verify --deep --strict` passed on the application. Identity: `com.local.dynamicisland`, **ad-hoc signed** (Developer ID / notarization not claimed).
- Isolated package path: `/private/tmp/dynamicisland-final-integration-20261015/DynamicIsland.app`.
- Release log: `/private/tmp/dynamicisland-final-package-20261015.log`. The user's active DynamicIsland installation has not been replaced.

## Mandatory physical acceptance (not yet executed on the new package)

1. **Unlocked media:** restore previous Compact, Standard and Large compositions, size switching, persistence, all supported actions and artwork click to foreground the correct media app.
2. **Lock Screen Standard/Large:** verify both sizes with actual Spotify/Music playback, controls and visualizer. When artwork is clicked while locked, the app must **not** launch until the macOS password/Touch ID unlock completes; it must then launch the originally selected app once. Cancel/timeout/fast user switching must not launch.
3. **Mixer:** independently attenuate Spotify and browser, 100% to 0% in both directions. Verify **the island tab remains unchanged** and ordinary swipes outside pills still navigate.
4. **Agent first visit:** enter Agents, type, hover/drag on Send without visiting Terminal. Send must animate fluidly and accept clicks from the first visit.
5. **Notch wings:** Thinking Orbs/avatars and Claude/Codex icons remain equally legible at the outer left/right edges, clear of the physical notch, across hover, multiple agents, collapsed/expanded states and Reduce Motion.
6. **Privacy/cleanup:** no sensitive private data on the secure screen; password input focus remains; unlock morph and teardown clean; no stale secure windows after quit.

Known limitations retained: private SkyLight is experimental and OS-gated; application volume on Boom virtual output may display a macOS recording indicator; newly discovered audio-helper processes can play at unity for about 150 ms before attenuation. These are not silently advertised as fully production-verified.

Do **not** merge into `main` until GitHub CI and the relevant manual acceptance items are completed.
