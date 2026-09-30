# Recorder timeline + collapse choreography — 2026-10-01

Branch `feature/agents-ui-overhaul-continuation`, from `f66fed0`.

## 1. Static recordings collapsed to ~one frame

### Evidence
- ScreenCaptureKit PTS is on the host clock: live stream, PTS vs
  `CMClockGetTime(CMClockGetHostTimeClock())` within ±5 ms over 144 frames.
- SCK delivers `SCFrameStatus.complete` only when content changes; idle frames
  carry no image and are (correctly) dropped.
- `finish()` ended the writer session at `latestDuration` = last complete
  frame PTS + one frame, so a ~3.5 s static recording produced 0.017 s.
- Pause/resume used the last/next *changed* frame as boundaries; the UI timer
  only advanced on changed frames (00:00 on a static screen).
- AVFoundation experiment (1 frame at t=0, H.264/MP4):
  `endSession(atSourceTime: 3 s)` alone → asset and video track 3.000 s;
  zero-tolerance decodes at 0.5/1.5/2.5/2.95 s return the held frame. A
  duplicate frame at exactly the end time adds nothing; one past it adds a sample.

### Fix
`ScreenRecordingTimelineClock` separates the sample timeline (host clock) from
the recording session timeline. Pause, resume and Stop are stamped with the host
clock when the user acts; samples captured during a pause or after Stop are not
recorded; `finish(stoppedAt:)` ends the session at the active recording end
(pauses excluded, never before the last appended frame). No pixel buffers are
retained and no duplicate frames are encoded (proven unnecessary above). A 2 Hz
queue-owned ticker publishes the active duration to the UI; `pause()` returns
the exact frozen boundary.

### Real ScreenCaptureKit results (`ScreenRecordingLiveTests`, tolerance ±0.35 s)
| Case | Expected | Measured |
|---|---|---|
| Static test-owned window, 3 s | 3.0 s | 3.037 / 3.058 s |
| Static window 1.2 + pause 1.2 + 1.2 | 2.4 s (wall 3.6) | 2.510 / 2.522 s |
| Area = window rect, 2 s | 2.0 s, 960×640 px @2x | 2.137 / 2.100 s, 960×640 |
| Display + system audio (afplay), 2 s | audio track + samples | 2.10 / 2.15 s, 1 track, 98 / 101 AAC packets |
| Display, changing, pause/resume (existing) | 0.5–3 s | pass |

Microphone: not exercised — microphone TCC status is "not determined" and
granting it requires the user's explicit answer to the macOS prompt.

## 2. Collapse did not mirror expansion

### Root cause
`requestCollapseWithSequencing` set `isExpandedContentExiting` and called
`islandState.collapse()` in the same run-loop turn; the state sink then started
the shell contraction (`beginVisualMorph(.collapsed)`, `isCollapseShellOnly`),
so children were squeezed by the shrinking shell and page bodies gated on
`!isCollapseShellOnly` vanished at once. Expanded page changes toward a smaller
shell committed the geometry one run-loop turn after selection while the
outgoing page was still fading.

### Fix (same SSOT: `ExpandedIslandMotion` / `IslandContentTransitionTiming`)
- `collapsePlan`: child exit = the running `InnerBlurScaleCleanModifier` removal
  (0.4 × shell + 0.015 s stagger; Reduce Motion 0.10 s fade, no scale/blur); the
  shell commits only after it. Slow/Fast/custom speed scale it via shellDuration.
- `IslandCollapseRequest`: generation-guarded pending collapse; an expansion
  during the exit cancels it and restores children; stale commits are rejected.
- `shrinkingPagePlan`: outgoing exit → shell contraction → incoming mount after
  the shell lands. Growing changes and expansion are unchanged.
- Droppy reference: `DroppyAnimation.expandClose` spring(0.36, 0.97), reduced
  easeOut 0.24; DynamicIsland keeps its own shell SSOT/curve and applies the
  close ordering, not a second animation system.

Deterministic checks sample every 1/120 s for Island, Agents, Tray, Timer,
Stats, Tools, Messages → collapsed and Agents → Island: no child visible once
the shell moves, top edge and centre invariant, no shell growth/overshoot.

## 3. Physical acceptance

Not performed. The Mac was unlocked at the start of this run, but launching
the re-signed build raised a login-keychain password prompt for
`com.local.dynamicisland.agent-bridge` (ad-hoc signature churn) that only the
user can answer, and the session locked again before UI checks could run.
Outstanding for the user: Screen Record tile click/panel lifecycle, HUD at
0/50/100 %, collapse at Slow motion.

## 4. Environment note
`~/Documents` is File-Provider managed: `com.apple.FinderInfo` /
`fileprovider` xattrs can reappear on `dist/DynamicIsland.app` after
`Scripts/package_app.sh`'s `xattr -cr`, making in-place `codesign --verify`
fail intermittently. Clean-copy verification (`ditto --norsrc --noextattr`)
is stable.
