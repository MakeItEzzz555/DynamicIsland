# Camera hand navigation validation

Stacked on PR #31 (`ef0fd9d8048160111996d4fc169221cdd27e0893`). AppSettings is the sole durable activation authority: `gesturesEnabled && gestureInputSource == .camera`. An authorized camera resumes on selection or relaunch; undetermined permission waits for the explicit Allow Camera button. Camera Mirror, explicit preview ownership and navigation leases share the existing capture engine. No second capture session is created for navigation.

## Input and privacy

The shared session temporarily attaches a YUV-preferring `AVCaptureVideoDataOutput`. A serial queue runs one `VNDetectHumanHandPoseRequest` at a time, with one hand and a 20 FPS deadline. Late video frames are discarded. Only the latest numeric result reaches the main actor; the pointer has its own small observed presentation store rather than republishing the island layout at 60 Hz.

Vision coordinates are mirrored once, with aspect-correct distances, scale-normalized pinch thresholds, optional numeric calibration and velocity-adaptive filtering. Final coordinates stay inside native hit bounds. Pinch confirmation/hysteresis, cancellation, handedness changes, tracking loss and generation rejection prevent repeated or stale clicks. Palm swipes require neutral rearming, including across brief pose flicker or tracking loss. Two-finger scroll is a separate, optional pose.

Events enter the application's local AppKit queue and the existing island window. A window gate checks generation, current interaction eligibility and physical input ownership. Physical mouse, button, keyboard, wheel and raw trackpad input take priority; native menus/popovers also suspend injection. No camera event is posted to the global session and camera tab input cannot activate the physical-pointer anchor.

Standard native Slider tracking reads the real cursor, so its narrow adapter uses the mounted, enabled control's target/action. The Media editing bridge preserves the existing scrub transaction and one seek on release; cancellation calls the existing scrub cancellation. Native scrolling uses the existing `NSScrollView` viewport. Scroll and magnetic assist default off. Magnetism requires an enabled native control inside a registered region and is disabled during a press/drag.

Workspace and file drag sources use WindowServer drag sessions that follow the real cursor. Camera input is blocked from starting these sessions; editor/file dragging is unsupported. Ordinary editor buttons retain their existing behavior.

No camera images, screenshots or landmark arrays are saved, logged or uploaded. Preferences/calibration contain only numeric bounds and settings. Diagnostics contain bounded numeric timing/state information. Synthetic Settings pointer previews own no camera.

## Deterministic validation

Original `d2be7c0` focused run: 121 tests, zero failures. The broader recording/navigation/editor fence also passed, followed by the full suite: 2,228 tests, 42 existing skips, zero failures.

Native fixtures use a non-activating panel and first-mouse behavior matching the island. They cover Button hit targets, native text focus without text entry, Media buttons, Slider target/binding/editing/cancellation, native drag gestures, Timer ruler, tabs, exact Messages reply/confirmation, Agent Send/Stop fake transports, exact approval, scroll, stale cancellation, raw-touch/physical-input precedence, cursor immobility and rejection of global editor drag sessions. These are hosted fixtures, not physical hand-gesture acceptance.

## Packaged camera probe

Run the packaged executable with `--validate-camera-navigation <temporary-directory>`. It only starts capture if current camera authorization is already granted and preserves a device currently used by another application. It saves numeric JSON only, separates initial model preparation from steady measurement, and validates navigation/Mirror session sharing and final-owner cleanup.

The first cold probe exposed a large initial Vision cost (2.75 FPS averaged over the initial ten seconds); a warmed probe measured 14.16 FPS, mean 18.48 ms / p95 32.82 ms with the original relative throttle. Native measurements prompted the deadline scheduler and explicit preparation status. The final packaged probe measured 19.89 FPS after preparation, mean 17.02 ms / p95 32.16 ms Vision latency and 5.61 ms p95 main-thread scheduling delay. Initial inference in this warmed run took 196.49 ms. Resident memory was 56.61 MB at measurement start, 139.47 MB at measurement end and 123.28 MB after capture stopped (these are samples, not a leak or peak-memory claim).

At the original `d2be7c0` validation, permission was authorized. The shared-session identity, Mirror-close/navigation survival, navigation-stop/Mirror survival and final-owner/device release checks all passed. No hand was observed in that original probe. Debug, Release, isolated packaging, three helper strict signatures and app deep/strict signature checks passed. The canonical `dist` app and running PR #31 application were preserved.

Physical hand direction, pinch/drag, swipe/rearm, scroll separation, mouse/trackpad priority and visual/calibration feel require a user with a hand in front of the running camera. Zero hand observations are not evidence that gestures work. Both PRs remain unmerged.

## Primary API references

- [Apple hand-pose detection](https://developer.apple.com/documentation/vision/detecting-hand-poses-with-vision)
- [Local AppKit event queue](https://developer.apple.com/documentation/appkit/nsapplication/postevent(_:atstart:))
- [Video-output pixel formats](https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput)
- [Vision request cancellation](https://developer.apple.com/documentation/vision/vnrequest/cancel())

## Activation/runtime repair

The physical report exposed a real gap: selecting Camera only saved/displayed the choice, while a separate transient toggle started navigation. That toggle is removed. The production AppDelegate constructs the controller with AppSettings; one Combine subscription reconciles both saved settings, including their initial publication. Lease release/acquisition is serialized, and generations invalidate stale permission, capture and frame completion. Repeated publication does not restart an errored camera; Check Again is the explicit retry.

First sample receipt is reported before Vision inference. A two-second generation-scoped watchdog distinguishes missing sample buffers from model preparation and is cancelled by the first sample, device change or stop. Runtime diagnostics distinguish off, starting, preparing, no hand, tracking, physical input, waiting for island, permission required, no frames and camera failure. Public NSRunningApplication observation reports other copies without terminating or blocking their non-camera services; the current acceptance subprocess is excluded.

Focused repair validation: 127 tests, zero failures. Full suite: 2,243 tests, 42 existing skips, zero failures. Debug, Release, isolated package, three helper strict signatures and app deep/strict signature passed. The correctness review covered activation ownership, async generations, frame delivery and input arbitration. Generated graph/browser files were excluded and no graph refresh was run under the explicit preservation instruction.

Fresh package: `/tmp/dynamicisland-camera-runtime-repair-package/DynamicIsland.app`. Its numeric acceptance report is `/tmp/dynamicisland-camera-runtime-repair-acceptance/camera-navigation.json`. The probe uses the real OverlayWindowController/IslandRootView and its panel, with inert non-camera services, empty Spotify credentials and input delivery disabled. No messages, Agent controls, Media actions or real pinch actions were executed.

Actual report: configured source Camera; desired navigation true; permission authorized; capture running; one navigation owner; output attached; first frame received; Vision 19.87 FPS, 23.93 ms mean / 38.54 ms p95; valid hand observed; pointer presentation produced. The pointer overlay was mounted in both collapsed and expanded production layouts, above content and excluded from hit testing. Two other normal DynamicIsland copies were detected. Shared-session identity, both independent owner-release directions and final-owner cleanup all passed.

The two existing app processes (89535 and 90186) were preserved. Physical right/up direction, pinch/drag, swipe/scroll separation and mouse priority require the user to exercise the repaired normal app. When safe for existing Agent/Terminal sessions, quit the older copies manually, then run `open -n /tmp/dynamicisland-camera-runtime-repair-package/DynamicIsland.app`; Enable gesture navigation ON and source Camera are sufficient. Permission is already granted. Both PRs remain unmerged.

## Physical gesture UX repair

The user verified real frames, hand detection, pointer movement, pinch click and pinch drag on `2d0ffdd17249`. Open-palm paging was unreliable, could lose the pointer during a page morph, and collapsed expansion failed. The gesture-only repair preserves capture/session ownership, Vision cadence, coordinate mapping, smoothing and the local Button/Slider routing.

Collapsed mode never displays a pointer. A confirmed pinch press emits a semantic expansion through `expandFromCollapsedPreparingGeometry()`, independent of mouse hit-testing and Expand on click. A held pinch cannot click the newly expanded content. Compact exact approvals, active hover composers and interactive HUDs block expansion; their existing control authority is unchanged.

Expanded precision mode retains pinch click/drag. Palm and two-finger navigation modes hide the pointer immediately. Palm evidence requires index/middle extension plus an optional extended finger, or a wide unpinched thumb/index separation when optional fingertips are missing. Confirmation takes at least two accepted observations across 80 ms; up to two degraded frames/120 ms are tolerated. Two explicitly folded optional fingers remain a distinct scroll pose. Returning to a stable unpinched pointing pose for 150 ms rearms navigation and restores the pointer; a held palm cannot repeat.

Swipes measure palm travel, not fingertip motion. Minimum travel is 0.65 hand scales, bounded to 0.08–0.16 normalized camera units; average velocity must reach 0.25 units/s, with 1.6 axis dominance within an 80–850 ms gesture window. Left defaults to next page, right to previous, and down to sequenced collapse. Up remains unbound. Camera collapse respects text focus, other transient owners, native menus/popovers, file drag and exact approval protection. Opening a palm during a pinch cancels once and requires pointing rearm before navigation.

Valid observations continue through page/shell morphs and physical-input suspension. Injection and pointer visibility pause without resetting the filter or navigation lifecycle. Latest normalized coordinates remap into the new island frame. Physical input cancels the current pinch safely; release of physical ownership restores pointing without a new camera session.

Camera Gestures uses native persisted pickers/switches for collapsed pinch, left/right/down palm bindings, optional scroll and expanded pointer visibility. Previous horizontal-swipe opt-out, pointer settings and numeric calibration migrate without reset. Diagnostics expose detected pose, candidate, last semantic action/time, rearm and bounded movement/velocity values; there is no continuous log or camera image storage.

Focused validation: 144 tests, zero failures, including realistic 20 FPS pose flicker, gradual opposite swipes, jitter/diagonal rejection, single expansion/collapse, protected ownership, pointer recovery through morph/resizing and physical arbitration, plus existing native click/drag/Media/Message/Agent/approval fixtures and Mirror sharing. Human swipe/collapse/expand acceptance on the new package remains pending; native fixtures and the read-only camera probe are not substituted for that check.

Final local validation: Debug and Release builds, full suite (2,260 tests, 42 existing skips, zero failures), isolated package, all three helper strict signatures and app deep/strict signature pass. Apple Design/Taste/Ponytail review was limited to the changed gesture ownership, visibility, recovery, Settings and connected callers/tests. No blocking correctness findings remained.

Fresh package: `/tmp/dynamicisland-camera-gesture-repair-package/DynamicIsland.app`. Numeric read-only report: `/tmp/dynamicisland-camera-gesture-repair-acceptance/camera-navigation.json`. Actual capture is authorized, output attached, first frame received and a valid hand observed at 20.42 FPS, 23.50 ms mean/38.51 ms p95. Both production overlay mounts, shared-session identity, independent Mirror/navigation handoffs and final-owner cleanup pass. No precision pointer was produced during this sample; the report does not identify the sampled pose or prove human gesture acceptance. The normal production package was subsequently launched for the user's gesture exercise. No other process was terminated, no TCC identity was reset, and no images were stored.
