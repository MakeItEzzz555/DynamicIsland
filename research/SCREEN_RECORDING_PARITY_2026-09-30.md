# Screen Recording parity audit — 2026-09-30

## Reference status

DynamicIsland's existing local Droppy reference is the audited dd2d16ccbdc6aa22b456e199442b43a07aa446af source snapshot documented in SOURCE_PARITY_MANIFEST.md. The local archive itself has no .git metadata, but its README/LICENSE identify Droppy as GPL-3.0 plus Commons Clause.

That source contains native ScreenCaptureKit usage for Element Capture screenshots, permission handling, and real-time system-audio analysis, but it does **not** contain the newer Droppy 16 full video-recorder implementation. Searches of the public Droppy GitHub source available to this environment for ScreenRecording, SCRecordingOutput, and related recorder symbols did not expose the v16 recorder source.

Therefore the new DynamicIsland recorder is **native behavioral parity**, not a claim of source-level copying of Droppy 16.

## Current official Droppy behavior used as behavioral reference

Authoritative public behavior references checked on 2026-09-30:

- Droppy 16.0 release post (2026-09-27): https://getdroppy.app/blog/droppy-16-0
- Droppy Live Activities documentation: https://getdroppy.app/docs/live-activities
- Droppy vs CleanShot X recording comparison (2026-09-21): https://getdroppy.app/blog/droppy-vs-cleanshot-x

Official Droppy 16 documentation published in September 2026 describes Element Capture recording of:

- a full display;
- a window;
- an area;
- microphone audio;
- system audio;
- a camera bubble;
- recording/privacy Live Activities with screen-recording controls and a video preview;
- transparent-window capture;
- click zoom/highlights, pointer-follow behavior, backgrounds/padding/corners/shadows;
- a post-recording studio with trim/crop/timed zooms/hidden areas/captions/transcription.

The current DynamicIsland phase implements the requested core recorder first and explicitly leaves the editor/studio effects as future parity work rather than faking them. Droppy 16 documents its recorder as requiring macOS 26; DynamicIsland intentionally uses the older documented ScreenCaptureKit + AVAssetWriter path so its core display/window/area recorder remains available on DynamicIsland's macOS 14 deployment target.

## DynamicIsland implementation

Production files:

- Modules/ScreenRecordingEngine.swift
- Modules/ScreenRecordingController.swift
- Views/ScreenRecordingViews.swift
- State/RightWorkspace.swift
- Modules/LiveActivityStore.swift
- Modules/LiveActivityLayoutResolver.swift
- Geometry/NotchGeometryService.swift
- Overlay/OverlayWindowController.swift

Architecture:

1. Explicit user action requests/uses Screen Recording permission.
2. SCShareableContent is the authority for available displays/windows.
3. Display/window/area targets become SCContentFilter + SCStreamConfiguration.
4. DynamicIsland-owned windows are excluded from display/area capture by default.
5. SCStream provides real screen/system-audio/microphone sample buffers.
6. AVAssetWriter writes H.264/AAC MP4 output.
7. ScreenRecordingTimelineClock retimes samples so paused time is removed from the final movie timeline.
8. A recording becomes .recording only after the first real video frame arrives.
9. Preview frames are sampled off the capture queue at about 5 Hz and published to the UI.
10. Stop finalizes the writer and validates the resulting video track/duration with AVFoundation before publishing Saved.
11. The persistent screen-recording Live Activity remains until the recording source ends.

## Target behavior

Core implemented:

- display recording;
- window recording;
- click-drag area recording;
- system audio;
- microphone capture on macOS 15+ with explicit microphone authorization;
- pointer visibility;
- exclude DynamicIsland by default;
- pause/resume;
- Stop & Save;
- real recording-duration timer;
- real sampled preview;
- red recording indicator / dim paused state;
- Productivity workspace integration;
- compact collapsed recording controls.

Not implemented in this phase:

- camera compositing into the recorded movie;
- transparent-window alpha-preserving movie export;
- click zoom/highlights;
- pointer-follow camera;
- styled backgrounds/padding/corners/shadows;
- post-recording editing studio;
- trim/crop/timed zoom/hidden-area timeline;
- captions/transcription.

Those are classified as **PARTIAL / future parity**, not production placeholders.

## Privacy

Recordings are written locally to:

~/Movies/DynamicIsland Recordings/

No recording is uploaded automatically.

Screen Recording permission is never requested at app launch. Microphone permission is only requested from an explicit recording start when the microphone option is enabled.

## Validation contract

Deterministic tests cover:

- recorder state-machine transition legality;
- pause/resume timeline retiming;
- duration formatting;
- persisted Right Workspace normalization when the new tool is added;
- collapsed recorder presentation geometry;
- area coordinate conversion.

The opt-in real test is gated by DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING=1.

It must either produce and validate a real video or skip with the exact TCC/ScreenCaptureKit environment reason. A skip is not counted as real E2E success.

### Current real acceptance — 2026-09-30

On the development Mac, `DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING=1 swift test --filter ScreenRecordingLiveTests` completed against real ScreenCaptureKit authority: capture reached `.recording` only after a video frame, paused, resumed, finalized an MP4, reopened it through AVFoundation, verified a non-empty video track and non-zero duration, then deleted only the test-owned output. Result: **1 test, 0 failures** in about 2.43 seconds.

This is real E2E evidence for the display-recording / pause-resume / finalize path. It does not by itself certify every window, area, system-audio, microphone or multi-display combination.

The production controller now limits recording Live Activity invalidation to whole-second timer changes instead of publishing at capture-frame rate, while the recorder timeline remains sample-timestamp authoritative. Runtime capture failures explicitly stop the active `SCStream` and cancel an unfinished `AVAssetWriter` so failed sessions do not leak capture/writer resources.
