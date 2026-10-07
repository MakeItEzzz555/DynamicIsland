# HUD geometry and recorder presentation — runtime repair, 2026-10-01

Branch `feature/agents-ui-overhaul-continuation`, starting HEAD `56c8be2`.

## 1. Interactive volume / brightness HUD sat too high

### Root cause

`CollapsedPresentationProfile.systemHUD` sized the shell as
`collapsedHeight + 12` and `CollapsedSystemHUDCompactView` vertically centered
its two rows (icon + %, slider) in that box. Height did not depend on the
physical notch. On the user's machine `collapsedHeight` is 29.87 pt while the
notch/menu-bar band is 34 pt, so the shell was 42 pt: the slider landed at
y ≈ 26–30 pt, inside the physical notch band, and the shell ended ~8 pt below
the notch.

### Droppy reference (local source, `~/Downloads/Droppy-main/Droppy`)

- `HUDLayoutCalculator.notchHeight`: physical notch height from
  `safeAreaInsets.top` when both auxiliary top areas exist, else
  `NotchLayoutConstants.dynamicIslandHeight`; SSOT for icon size
  (`notchIconSize` 18 / `dynamicIslandIconSize` 16) and
  `symmetricPadding = max((notchHeight - iconSize) / 2, 6)` (+10 wing corner
  compensation in notch mode).
- `NotchLayoutConstants.physicalNotchHeight = 37` fallback.
- `HUDOverlayView.swift` `NotchHUDView`: content row framed to
  `.frame(height: notchHeight)` — content is attached to the notch band.
- `NotchShelfView.swift`: volume/brightness container height returns
  `notchHeight` (horizontal-only expansion); `hudHeight = 73` constant for the
  legacy HUD.

DynamicIsland keeps its two-row composition (the slider is interactive with
real system write + readback, which Droppy's one-row wing layout does not
replace), so parity is applied to the top band only: the icon/percentage row
occupies the physical top band exactly as Droppy's row occupies `notchHeight`.

### Change

- Shell height = `max(collapsedHeight, notchHeight)` + 24 pt slider band
  (`CollapsedPresentationProfile.systemHUDSliderBandHeight`); the notch term is
  used only for notch-integrated islands. Width profile unchanged.
- Top edge unchanged (still the screen top / notch); the shell grows downward
  only. No NSPanel translation, no new island state.
- View: row fills the top band; the slider is centered in the band below the
  notch edge (9.75 pt above / below the 4.5 pt track); its drag target spans the
  full band.
- Examples: 34 pt band + 29.87 collapsed → 58 pt (was 42); 32 pt notch + 44 →
  68 pt (was 56). Below Droppy's 73 pt legacy HUD height.
- Settings: both HUD previews render `SystemHUDShellPreview` (production
  `IslandSurface` + HUD content at `NotchGeometryService` geometry); the old
  190×32 capsule approximation is gone.

## 2. Productivity → Screen Record appeared to do nothing

### Root cause (runtime evidence, real app, DEBUG instrumentation since removed)

The tile presented `ScreenRecordingSetupView` via a SwiftUI `.sheet` bound to
tile `@State`, inside the borderless non-activating status-bar
`IslandOverlayPanel`. In the real app:

- AppKit did create and attach a `SheetPresentationWindow` (421×275) — but on
  top of the expanded island (black on black), centered over its top.
- Attaching the sheet pushed the top-pinned island panel from y = 627 to
  y = 592 — 35 pt off the screen top.
- The sheet extended below the island shell; moving the pointer onto it
  triggered the island's hover-exit collapse, which unmounted the tile and
  dismissed the sheet (`tile onDisappear` → `sheet content onDisappear`).

### Fix

`ScreenRecordingSetupPresenter` (app-owned, in `ProductivityModules`) presents
the production `ScreenRecordingSetupView` in one dedicated, reused,
non-activating `ScreenRecordingSetupPanel` at status-bar level + 1, centered
under the island on its current screen (anchor from
`OverlayWindowController.screenRecordingSetupAnchor()`), top edge pinned while
content resizes, closed by its close button or Esc. The island's Esc monitor
ignores Esc aimed at other windows. Settings preview tiles are inert. No
permission request and no SCStream until the user acts inside the setup.

## 3. Acceptance evidence

Environment: the Mac was **locked** for the whole session (loginwindow on top,
`CGSSessionScreenIsLocked=1`), so no physical click was possible.

Real app (debug build in an app bundle, temporary DEBUG hook calling exactly
the tile's `setup.present()`, since removed):

- Recorder surface: `ScreenRecordingSetupPanel` level 26, not a sheet, frame
  top 618 below island bottom 627; island panel stayed at y = 627 (top-pinned).
- Survived island collapse; repeated presents → 1 window; close → reopen OK.
- Real permission state (granted), real `SCShareableContent` display list.
- Real display recording: recording → paused → recording → saved; collapsed
  recording Live Activity published with live preview thumbnail; MP4 saved,
  AVFoundation: 1 video track 1352×878, 5 decodable samples.
- WindowServer captures of setup, recording controls and the collapsed island
  activity were reviewed.

Observed, not changed (pre-existing backend behavior): the engine drops
`SCFrameStatus.idle` frames and ends the writer session at the last complete
frame, so a static screen (the lock screen here) yields a very short file
(0.017 s for ~3.5 s). `ScreenRecordingLiveTests` fails its `> 0.5 s` duration
check in this locked environment for that reason; engine/controller are
byte-identical to `56c8be2`, where the test passed in an unlocked session.

## 4. Intermittent HUD height under persistent compact media — 2026-10-01 follow-up

### User evidence

A runtime screenshot showed the interactive Volume/Brightness slider rendered over the compact island while the physical collapsed shell sometimes remained at the shallower persistent-media geometry. This made the slider look as though it stayed behind/inside the notch rather than receiving its dedicated lower slider band.

### Root cause

The physical window controller subscribed to `LiveActivityStore.activities`, but de-duplicated updates using only `collapsedActivityLayoutProfile(activities:)`. A system HUD is intentionally a transient overlay: when compact media remains the persistent primary activity, adding Volume/Brightness does **not** change the media activity profile. Therefore Combine suppressed the geometry refresh even though `collapsedPresentationProfile` had changed from `.normal` to `.systemHUD` and required a taller physical frame.

This explains the intermittent behavior: HUD height worked when the underlying activity/layout profile changed, but could stay shallow when the HUD overlaid an unchanged media primary.

### Fix

Live-activity geometry invalidation now keys on both:

- the persistent `CollapsedActivityLayoutProfile`, and
- the transient `CollapsedPresentationProfile`.

A media → media+HUD transition therefore triggers the collapsed presentation morph and a window `reposition`, while HUD progress-only changes remain de-duplicated because `.systemHUD(value:)` intentionally does not encode the numeric value into shell geometry.

Regression tests prove:

- media + normal presentation != media + interactive-HUD presentation;
- 10% HUD and 100% HUD produce the same physical geometry signature, so repeated key/slider value changes do not restart the window morph.

## 5. Collapse choreography follow-up

The branch already contains `1234f39 fix(motion): make collapse mirror the expansion choreography`. Its contraction contract was revalidated after the HUD fix: all primary pages finish the outgoing shrink/blur/fade before the top-pinned shell contracts, slower presets lengthen both phases, Reduce Motion keeps the ordering without decorative scale/blur, and stale collapse requests cannot hide newer expanded content.

An opt-in reverse choreography renderer was added for Agents, Island, Tray and Tools → collapsed in both full and Reduce Motion modes so future regressions can be inspected frame-by-frame rather than relying only on scalar motion tests.
