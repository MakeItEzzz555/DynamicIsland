# Collapsed communication and recording validation

Baseline: `2ad101e960401202adc1ec748cfedebf6707571e` (main #30), fresh `fix/live-activities` branch. This work does not authorize a merge.

## Call authority

The Xcode 26.2 macOS SDK explicitly marks `CXCallObserver`, `CXCallObserverDelegate`, `CXCall`, and `CXCallController` `API_UNAVAILABLE(macos, tvos)`. A Swift type-check probe targeting arm64 macOS 14.6 failed with `'CXCallObserver' is unavailable in macOS`. Mac Catalyst availability does not make these APIs available to this native SwiftPM/AppKit app. [Apple's observer documentation](https://developer.apple.com/documentation/callkit/cxcallobserver) describes its observation model; the installed SDK supplies the platform availability contract.

No real call state, caller identity, connected timestamp, or call-control authority is exposed here. There is no fabricated call observer or live publisher. Connecting and connected call Settings samples render the production compact component with a green phone and green/yellow variant of the existing decorative AudioVisualizerView. They do not meter call audio or request capture access.

## Messages and hover

The existing Notification Center → exact Messages database resolution → controller queue/draft book → exact-chat Apple Events → outgoing database confirmation path is retained. A fixture integration test reaches `message.current` through the real adapter/controller boundary. Exact and ambiguous resolution, ordering/deduplication, timeout/failure draft retention, confirmed clearing, and per-conversation drafts pass. A known Automation denial removes inline-reply capability without stopping incoming observation.

Collapsed hover uses the same Focus-filtered entry that publishes the activity. The shared production native composer registers its frame through the existing native-control ownership channel using the single-value `onGeometryChange` API (SDK availability macOS 13+, compatible with the app's target). AppKit tests exercise Return, one send to the selected conversation, confirmed clearing, Escape, focus notification, and region release on unmount. They use synthetic native events and fixture providers, not real message sends or physical input.

| Activity | Hover policy |
| --- | --- |
| Media, Timer, Battery, ordinary Agent, recording, other information | No height growth |
| Exact Agent permission | Existing bounded controls, 68 pt content extension; existing 8 pt hover detail suppressed by Reduce Motion |
| Exact replyable Message | Native summary/composer; 128 pt extension below the existing collapsed top band |
| Unreplyable Message | Bounded 92 pt peek, limitation and capability-authorized Open App; no composer |
| Call | No growth; native macOS controls are unsupported |

Interaction frames preserve `maxY` and horizontal center. Generic hover height/media options are hidden and retained only for migration. Message hover enable/delay remains user controlled. Settings provides six inert production scenarios: connecting call, connected call, message, message reply, recording, and exact permission controls, with Reduce Motion rendering.

## Recording authority and recovery

Opening setup does not request permission. Explicit Allow/Start may request once for the current cdhash. A successful grant that still cannot capture offers Relaunch. Persisted stale/denied identity state offers Screen Recording Settings and a passive Check Again without reissuing Allow. The ledger is retained; no cached grant overrides current capture refusal. An unfinished writer is owned before stream-output setup and failed starts remove their uniquely named pending output.

Live validation also exposed a stream accepted without a first video frame. A generation-scoped five-second startup timeout now fails that run, rejects a late first-frame transition, and cleans its unfinished writer. Cleanup captures the exact pending URL before awaiting shutdown, so a delayed callback cannot delete a subsequent run's file.

Local Droppy comparison: `Droppy/PermissionManager.swift` uses the same CG preflight/request APIs and ScreenCaptureKit enumeration, but its `isScreenRecordingGranted` can return a cached `true` while current preflight is false, including after its launch grace period. DynamicIsland does not adopt that behavior.

The packaged acceptance entry point bypasses the normal app delegate, uses isolated in-memory preferences, keeps the installed/running app intact, and does not request permissions or send messages. Run it directly:

```sh
/path/to/DynamicIsland.app/Contents/MacOS/DynamicIsland --validate-live-activities /tmp/dynamicisland-live-activities-acceptance
```

It writes `acceptance.json`, native preview PNGs, and temporary MP4s for inspection. Its cursor comparison uses public CG cursor placement over the test-owned window and restores the pointer. This is recording evidence, not physical gesture acceptance. The installed user app was neither replaced nor terminated.

## Real recording acceptance matrix

The final packaged run (`cdhash 32a450eaa047925cfbac833909267f6152b93b81`) passed CG preflight and ScreenCaptureKit access. Earlier sessions returned no shareable display, delivered no first frame, or recorded black Display/Area pictures; those results were rejected. The final session exposed the display and captured the blue test-owned window. Valid metadata alone was not accepted. No permission request was made by the runner.

| Check | Observed result |
| --- | --- |
| Source enumeration | Passed: display and exact test-owned window enumerated after current permission checks. |
| Display | Passed: 1352×878, 3.133 s, video track duration matches, decoded frame contains the blue test window at its expected screen position. |
| Window | Passed: 960×640, 3.062 s, decoded blue test window. |
| Area | Passed: 960×640, 3.075 s, decoded blue test window at the selected crop. |
| Static timeline | Passed: live static window/area last about 3 s. Production writer test: one frame → 3 s asset and video track, 64×48, decoded successfully. |
| Pause / resume | Passed: 1.5 s recording + 1 s paused + 1.5 s recording → 3.170 s output; paused counter stayed fixed. Deterministic clock tests also pass. |
| Stop / playable output | Passed: all eight exercised source/options runs finalized, loaded video tracks, and decoded frames. |
| Cursor toggle | Passed: real captured pixel difference between cursor-hidden and cursor-shown Area runs, 3.095 / 3.098 s. Pointer restored. |
| System audio | Passed: 3.092 s output, one audio track, 145,920 decoded PCM frames; independent Float PCM check found a nonzero signal after the synthetic Glass sound. |
| Microphone | Not exercised; runner never requests mic access. Enable Microphone audio and Start in the packaged app; grant macOS permission if requested (macOS 15+). |
| Exclude DynamicIsland | Passed: included Area center BGR `[247,130,59]`, excluded `[0,0,0]`; the test-owned window was removed. Existing production filter retained. |
| Failed-start cleanup | Passed: invalid window rejected, no activity remains, no new recording files left in the Movies output directory. Zero-video cancellation and first-frame timeout state checks pass deterministically; final live success did not exercise the no-frame timeout branch. |
| Activity removal | Passed after each live finalization and the invalid-target failure. |

Messages live acceptance is also gated: the packaged probe reported Full Disk Access denied. A new incoming notification and a user-selected exact recipient/text are still needed; no real message was sent. Native preview screenshots and fixture tests do not substitute for those checks.

## Checks

Focused final run: 198 tests, 7 skipped, 0 failures. Full final suite: 2,162 tests, 42 skipped, 0 failures. Skips cover opt-in integrations/hardware evidence; they are not claimed as passes. An earlier full run had one unchanged Metal Send visibility-fixture failure; its isolated recheck (2 tests) and the final full rerun passed. The regression test and production Send behavior were left intact.

Final Debug and Release builds, packaging into a separate `/tmp` directory, three helper strict signatures, and app deep/strict signature passed. Native screenshots were inspected for collapsed density, downward hover geometry, readable controls, and both normal/Reduce Motion presentations. Real VoiceOver navigation and physical trackpad calibration were not exercised.

The full suite includes recent Media clearance, clicked-tab anchoring, Agent priority/Send ownership, centered notch attachment, Gesture Only/two-finger ownership and paging, Clipboard/Settings/Edit mappings, Settings structure, Terminal generations/retention, exact approvals, ThinkingOrb fallback, Spotify scrub/end protection, notch wings/audio-device HUD, shell/glow geometry, semantic widget sizes, editor Apply/Cancel, and Reduce Motion tests. No physical swipe/trackpad acceptance is claimed.

The reviewed delivery SHA, final main divergence, PR state, and final-head CI are recorded in the PR description. Generated graph updates and local acceptance artifacts are excluded from the delivery diff.
