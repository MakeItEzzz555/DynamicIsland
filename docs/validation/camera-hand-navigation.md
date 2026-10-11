# Camera hand navigation validation

Stacked on PR #31 (`ef0fd9d8048160111996d4fc169221cdd27e0893`). Camera Navigation is opt-in and starts only from its explicit Settings switch. Camera Mirror, explicit preview ownership and navigation leases share the existing capture engine. No second capture session is created for navigation.

## Input and privacy

The shared session temporarily attaches a YUV-preferring `AVCaptureVideoDataOutput`. A serial queue runs one `VNDetectHumanHandPoseRequest` at a time, with one hand and a 20 FPS deadline. Late video frames are discarded. Only the latest numeric result reaches the main actor; the pointer has its own small observed presentation store rather than republishing the island layout at 60 Hz.

Vision coordinates are mirrored once, with aspect-correct distances, scale-normalized pinch thresholds, optional numeric calibration and velocity-adaptive filtering. Final coordinates stay inside native hit bounds. Pinch confirmation/hysteresis, cancellation, handedness changes, tracking loss and generation rejection prevent repeated or stale clicks. Palm swipes require neutral rearming, including across brief pose flicker or tracking loss. Two-finger scroll is a separate, optional pose.

Events enter the application's local AppKit queue and the existing island window. A window gate checks generation, current interaction eligibility and physical input ownership. Physical mouse, button, keyboard, wheel and raw trackpad input take priority; native menus/popovers also suspend injection. No camera event is posted to the global session and camera tab input cannot activate the physical-pointer anchor.

Standard native Slider tracking reads the real cursor, so its narrow adapter uses the mounted, enabled control's target/action. The Media editing bridge preserves the existing scrub transaction and one seek on release; cancellation calls the existing scrub cancellation. Native scrolling uses the existing `NSScrollView` viewport. Scroll and magnetic assist default off. Magnetism requires an enabled native control inside a registered region and is disabled during a press/drag.

Workspace and file drag sources use WindowServer drag sessions that follow the real cursor. Camera input is blocked from starting these sessions; editor/file dragging is unsupported. Ordinary editor buttons retain their existing behavior.

No camera images, screenshots or landmark arrays are saved, logged or uploaded. Preferences/calibration contain only numeric bounds and settings. Diagnostics contain bounded numeric timing/state information. Synthetic Settings pointer previews own no camera.

## Deterministic validation

Final focused run: 121 tests, zero failures. The broader recording/navigation/editor fence also passed, followed by the full suite: 2,228 tests, 42 existing skips, zero failures.

Native fixtures use a non-activating panel and first-mouse behavior matching the island. They cover Button hit targets, native text focus without text entry, Media buttons, Slider target/binding/editing/cancellation, native drag gestures, Timer ruler, tabs, exact Messages reply/confirmation, Agent Send/Stop fake transports, exact approval, scroll, stale cancellation, raw-touch/physical-input precedence, cursor immobility and rejection of global editor drag sessions. These are hosted fixtures, not physical hand-gesture acceptance.

## Packaged camera probe

Run the packaged executable with `--validate-camera-navigation <temporary-directory>`. It only starts capture if current camera authorization is already granted and preserves a device currently used by another application. It saves numeric JSON only, separates initial model preparation from steady measurement, and validates navigation/Mirror session sharing and final-owner cleanup.

The first cold probe exposed a large initial Vision cost (2.75 FPS averaged over the initial ten seconds); a warmed probe measured 14.16 FPS, mean 18.48 ms / p95 32.82 ms with the original relative throttle. Native measurements prompted the deadline scheduler and explicit preparation status. The final packaged probe measured 19.89 FPS after preparation, mean 17.02 ms / p95 32.16 ms Vision latency and 5.61 ms p95 main-thread scheduling delay. Initial inference in this warmed run took 196.49 ms. Resident memory was 56.61 MB at measurement start, 139.47 MB at measurement end and 123.28 MB after capture stopped (these are samples, not a leak or peak-memory claim).

Current permission was authorized. The shared-session identity, Mirror-close/navigation survival, navigation-stop/Mirror survival and final-owner/device release checks all passed. No hand was observed. Debug, Release, isolated packaging, three helper strict signatures and app deep/strict signature checks passed. The canonical `dist` app and running PR #31 application were preserved.

Physical hand direction, pinch/drag, swipe/rearm, scroll separation, mouse/trackpad priority and visual/calibration feel require a user with a hand in front of the running camera. Zero hand observations are not evidence that gestures work. Both PRs remain unmerged.

## Primary API references

- [Apple hand-pose detection](https://developer.apple.com/documentation/vision/detecting-hand-poses-with-vision)
- [Local AppKit event queue](https://developer.apple.com/documentation/appkit/nsapplication/postevent(_:atstart:))
- [Video-output pixel formats](https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput)
- [Vision request cancellation](https://developer.apple.com/documentation/vision/vnrequest/cancel())
