# Gesture-first workspace validation — 2026-10-08

The patch passes local builds and automated checks. Physical trackpad and
packaged interactive acceptance remain pending; this is not a complete UX sign-off.

Starting commit: `8182e18dc05b34abc4dcd59fbdc1014ce5b08c4a`.
Branch: `feature/agents-ui-overhaul-continuation`.
The remote feature branch was fast-forwarded to `9a272e4`, then reconciled with
main by history-only merge `781301b` because their committed trees were identical.
Main has zero commits missing from the reconciled feature branch.

## Audit and implementation plan

The mandatory CLAUDE.md, context.md, native customizable workspace document and
source parity manifest were read. The implementation followed these owners:

| Responsibility | Existing authority retained |
| --- | --- |
| Page order, availability and selection | IslandNavigationStore, including existing cyclic next/previous behavior |
| Pointer, two-finger, right workspace and native scroll routing | OverlayWindowController and IslandGestureCoordinator |
| Page/content/window transition | Existing navigation observation and ExpandedShellMorph |
| Widget editing, Apply/Cancel, semantic cells | WorkspaceCustomizationStore and WorkspaceWidgetLayoutProjection |
| Shell dimensions and header lanes | ExpandedPresentationProfile, ExpandedHeaderLayout and display metrics |
| Clipboard | Existing ClipboardHistoryStore and history presentation |
| Settings | Existing SettingsWindowController and AppSettings persistence |
| Preview composition | SettingsPreviewSandbox and production views/resolvers |
| Media timing and command authority | MediaController, MediaAutomationExecutor and SpotifyLibraryController |

Recent history and each corresponding navigation, gesture, preview, editor,
header and seek path were reviewed before changes. No second navigation store,
clipboard database, gesture monitor or shell animation engine was introduced.

## Previews and chrome

Existing Island, Media, Timer, Agents and Live Activity previews now read real
settings, persisted workspace placements and production semantic geometry.
Live Activity layout uses the real notch/composite/sidecar resolvers and compact
renderers. Representative data remains explicitly labeled.

Production shell/content motion is reused. OS Reduce Motion remains authoritative;
the preview simulation supplements it without overriding the read-only OS
environment value. Visualizer work also observes the preview motion preference.

Preview persistence is memory-only. Calendar/provider/app-scanner dependencies
are inert, terminals refuse process creation, and preview transcript views skip
shared viewport persistence/restoration. Timer mounting cannot migrate user
preferences, Clipboard cannot take search focus, and Reminder previews do not
refresh the real provider. Preview interactions and timer ruler registrations
are disabled.

`showNavigationControls` and `threeFingerTabNavigationEnabled` default true.
Hiding controls enables paging; disabling paging restores visible controls.
An invalid persisted pair restores controls while preserving the explicit
paging opt-out. The three-finger preference is independent of legacy gesture
and camera input opt-in settings.

Hidden headers leave the view hierarchy. Their row height, spacing and width
floor are zero, while notch clearance and the existing bottom padding remain.
Semantic cell size comes from display metrics. A feedback bug was found and
removed: fitting a single-unit cell against a two-unit host estimate had shrunk
the widget again when the shell became narrow.

Measured using production resolvers, with a 1512×982 pt display, 2× backing scale,
32 pt top safe area and 186 pt hardware notch:

| Case | Shown shell | Hidden shell | Editing shell | Widget in all three modes |
| --- | ---: | ---: | ---: | ---: |
| Compact Media | 548×221.17 | 223.36×215.28 | 334.97×284.25 | 161.36×161.36 |
| Standard Chat | 675.56×466.20 | 675.56×460.30 | 689.56×529.27 | 613.56×406.38 |
| Large Terminal | 1089.92×466.20 | 1089.92×460.30 | 1103.92×529.27 | 406.38×406.38 |

Compact Media reclaims 324.64 pt width; all three reclaim 5.90 pt height.
These are resolver measurements, not claims of physical screen acceptance.
Temporary measurement instrumentation was removed and the original test file
SHA-256 restored exactly.

## Input and recovery

Raw public NSTouch callbacks on the existing hosting view track exactly three
indirect contacts from one device, including resting fingers. Identity equality
is stable across event snapshots. Direction locks after 0.015 normalized travel;
horizontal dominance must exceed 1.5 and paging commits at 0.08 normalized travel.
Opposing contacts, vertical/diagonal starts, replaced identities and extra fingers
are rejected. One sequence can commit once until all contacts lift.

Associated scroll tails cannot become media/right-workspace gestures. Native
ScrollViews still receive their events. Mouse-button dragging, registered native
controls, editing, drops and shell transition states veto paging starts.
The existing navigation transaction changes page and shell geometry together.

A 0.55 s hold, with at most 10 pt travel, enters editing from safe shell padding.
The AppKit input view is a lower sibling with exact geometry and shell-path hit
filtering; the entire content area and native control regions are excluded.
Mounted native NSTextView hit-path tests verify this production stacking.
Apply/Cancel remain available while regular navigation stays hidden.

AppKit cannot reliably associate mouse clicks with trackpad finger counts.
The chosen fallback is a native menu exposing Settings, Clipboard, editing and
page commands, with an exact hardware-notch region and visible padding recovery.
The camera cutout itself has no visible pixels; physical notch interaction is
not claimed as verified. The menu bar permanently exposes accessible recovery
commands, including restoring navigation.
See [Apple's touch-event documentation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html).

## Spotify reproduction and repair

The former app's AppleScript command was replayed against an authenticated,
running Spotify session. Live duration values were milliseconds (for example
280000); player position was seconds. The existing duration conversion was kept.

The actual endpoint failure reproduced without a next-track command:

| Seek margin | Duration, seconds | Observation after 2 seconds |
| --- | ---: | --- |
| 0 ms | 216.923 | Same track, reported playing, stuck at 216.923004150391 |
| 100 ms | 216.923 | Same track, reported playing, stuck at 216.923004150391 |
| 250 ms | 216.923 | Naturally advanced; new track position 1.552 s |
| 500 ms | 167.227 | Naturally advanced; new track position 1.226 s |

Five more 250 ms seeks advanced naturally on consecutive tracks with durations
279.933, 114.991, 250.000, 209.466 and 298.866 seconds. Their new-track positions
were approximately 1.59, 1.48, 1.50, 1.48 and 1.50 seconds after observation.
250 ms is the smallest successful tested candidate, not an assertion that every
possible smaller interval fails. Repeat/shuffle settings were not changed.

The old slider bounds were `0...max(duration, 1)` and release sought to the
provider position that dragging had overwritten. Exact endpoint positions were
allowed. Scrubbing now captures track, source, native ID, generation and real
duration; it updates only a local preview and consumes one release seek.
Track/duration/source/capability changes cancel stale gestures until release.
There is no pending optimistic position that can hold the provider at an end.

Spotify's slider/seek upper bound is `max(0, duration - 0.250)` seconds.
Music keeps `0...duration`. Provider timing and labels retain the real duration.
Tiny Spotify tracks have a disabled zero-range slider. Every seek rejects invalid
numbers and revalidates context; local commands also validate native track and
duration on their serial execution worker.

Spotify conversion clamps seconds, floors to integer milliseconds, then caps
again at `max(0, duration_ms - 250)`. Provider duration milliseconds are recovered
with nearest quantization to avoid a binary floating-point comparison error.
Authenticated API writes verify the track, duration and explicit active device;
an error or mismatch is never retried through AppleScript. No automatic next-track
workaround was added. Normalized progress always resolves to 0...1; invalid timing
resolves to zero and availability is checked separately.

## Validation and outstanding acceptance

- Integrated focused run: 100 tests, zero failures; final navigation/recovery
  run: 16 tests, zero failures (overlapping tests, not 116 unique tests).
- Final full working-tree suite: 2071 executed, 42 skipped, zero failures.
- Debug build and Release build: passed on Xcode 26.2 build 17C52 / Swift 6.2.3.
- Canonical temporary package: `/tmp/dynamicisland-ux-package/DynamicIsland.app`.
- Strict app and all three helper signature checks: passed, ad-hoc signed.
- AST graph updated; graph changes are deliberately unstaged. The graph parser
  reports a partial Swift extraction warning for MediaAdvancedControls despite
  successful Swift compilation.
- An earlier full run exposed one filesystem-watcher timeout; an unmodified
  final full rerun passed. No watcher code or timeout was changed.
- Existing CI run 37626095153 failed in Swift 6.1.2 SIL lowering with signal 11,
  not a normal source diagnostic. CI now explicitly selects the locally verified
  Xcode 26.2 available in the [hosted runner image](https://raw.githubusercontent.com/actions/runner-images/macos-15-arm64/20260907.0337/images/macos/macos-15-arm64-Readme.md).

The first two hosted Xcode 26.2 runs compiled successfully. Their test failures
exposed existing fixture assumptions: short teardown sleeps race scheduled
completion tasks, ImageRenderer snapshot allocation and frozen avatar replay
do not measure live 120 Hz frame pacing, and an occluded native window correctly
pauses its decorative clock. Production timing and rendering were unchanged.
Tests now observe published completion, retain always-on finite geometry and
exact rasterization checks, and establish/diagnose native window visibility
before asserting animation. Snapshot cost remains an explicit diagnostic via
`DYNAMIC_ISLAND_DECORATION_PERF=1`; no portable wall-time threshold is claimed.
The corrected fixture checks passed locally: 19 completion/decoration tests
(one explicit benchmark skip), two native Send interaction tests, and the
separately enabled snapshot-cost diagnostic. The first post-correction full run
had three failures in unchanged native-layout/mock-process timing tests; its log
was preserved separately rather than counted as passing. An unmodified complete
rerun passed all 2069 tests, with 42 skipped. The extra skip is the explicit
snapshot benchmark; clean CI omits two unrelated dirty Calendar tests.

Later hosted validation exposed the same completion task-start race: a fixed
1.1-second test sleep sometimes ended before the child's one-second debounce.
The test now captures the published presentation, verifies at least one second
with ContinuousClock, and verifies a three-second peek from its own timestamps.
Voice recovery expiry likewise awaits publication while preserving the existing
weak-controller release assertion. Production debounce and expiry are unchanged.

The recreated-file watcher failure was independently reproduced as real data
loss. A file can be opened while empty and written before its DispatchSource
registration becomes active. Unmodified production missed 29 of 400 writes,
persisting beyond two seconds until manual reconciliation. A one-time registered
file-source callback into the existing lifecycle/token-validated read path
recovered all 400 in the same matrix. The narrow fix adds no polling, sleeps,
retry layer or replacement watcher architecture. The recreated-write regression
exercises this gap rather than hiding it with an increased timeout.
The retained repeated-run trace lost 23 of 400 original-source writes and passed
all 400 patched-source writes. The integrated 30-recreation regression and the
attention/voice checks passed in a 56-test focused run. Final Debug and full
working-tree validation passed: 2070 tests, 42 skipped, zero failures.

Hosted attempts also intermittently failed the existing rapid Terminal remount
fixture. A controlled two-host SwiftUI handoff reproduced a real orphan recovery
failure: host A retained its visible identity and emulator reference; host B
claimed the emulator, then actual dismantleNSView detached it. A subsequent
updateNSView on A could not reclaim the unowned renderer. Every prerequisite
passed, including the guard against stealing B's owned renderer and exactly one
shell start; only orphan reattachment failed on the original code.

The visible-host guard now permits reclaim when the emulator has no superview.
Owned renderers retain the existing handoff protection. The new real SwiftUI
handoff regression and the unchanged 48-cycle stress test both pass. This proves
and repairs the guard pathology; the earlier hosted stress logs did not capture
each native host, so they cannot alone prove that every observed nil attachment
had this cause. Preview guards were inactive in that fixture.
The final Debug build and full local suite passed after this repair: 2071 tests,
42 skipped, zero failures. Original stress timing and assertions remain intact.

An isolated native SwiftUI slider probe verified that keyboard arrows and native
accessibility increment/decrement deliver editing begin, the value change while
editing, then editing end. This validates the local scrubbing callback ordering,
not complete VoiceOver acceptance. An isolated visibility probe confirmed that
window occlusion bit 2 absent pauses frames and present allows frames; activation
was not required on the local runtime. These probes did not close the installed
app or its child sessions.

Physical three-finger delivery (especially a non-key collapsed panel), system
gesture conflicts, packaged pointer/gesture/preview acceptance, packaged Spotify
slider tests, repeat/shuffle cases and interactive Reduce Motion remain pending.
The installed app owns a live Codex server and Terminal shell; it was not closed
or overwritten without approval. The actual Spotify command reproduction and
mounted AppKit tests do not substitute for those remaining gates.

Unrelated Calendar, AppsMediaDeck, FileTrayQuickActionBar, RightWorkspace,
ScreenRecording, Calendar tests and summary.md hashes match their starting values.
No unrelated files or graph output are staged. No TCC reset, credential change,
force push or history rewrite was performed.

PR #25 had already been merged externally at `5eb8f0b` on 2026-10-07T07:16:17Z;
it cannot be kept open/unmerged by this phase. The existing feature review is
PR #24, verified open and draft. No PR was merged by this work.

## Final Terminal ownership repair — 2026-10-08

The later hosted trace disproved the sufficiency of the orphan-only guard:
the newest visible native mount remained in its window with a matching emulator
reference, but the emulator itself had no superview/window. An older presentation
disappeared after the newer presentation appeared. A deterministic two-host
SwiftUI fixture reproduced both the stale acquisition and subsequent orphaning.

TerminalSessionController now retains one MainActor TerminalMountCoordinator.
Its lease combines native host identity with an ordered presentation/host
generation. The Agents parent captures its immutable presentation generation
before conditional Terminal children exist; creating a child late cannot promote
a retiring parent. Host order resolves remounts within one parent. Acquire and
native reparenting are synchronous; stale acquire/release are no-ops. Releasing
the current owner preserves the generation watermark. Unexpected detachment can
be reclaimed by the current lease, never by a retired host. Keyboard engagement
also ignores window updates from a retired mount. The retained emulator,
controller, PTY, cwd, environment and scrollback do not change on handoff.

Six focused lease tests include the required A1 -> B2 -> late A acquire/release,
current-owner orphan recovery, same-parent remounts, keyboard independence and an
actual SwiftUI parent whose older Terminal child is created after the newer
parent owns the emulator. The hosted stale-visibility regression and current
lease reclaim fixture preserve one shell start. The original 48-cycle stress
fixture and its timing are unchanged; investigation-only tracing is removed.
Twenty consecutive executions passed all 960 cycles with zero failures. The
focused Terminal/integration/geometry suite executed 55 tests, one existing
opt-in snapshot skip, zero failures. Recent-feature regressions executed 118
tests, one existing live-provider skip, zero failures. The full local suite
executed 2078 tests, 42 skipped, zero failures. Debug, Release, canonical temporary
packaging and strict helper/app signatures passed. Final-head CI is reported in
the handoff; physical acceptance remains subject to the active sessions and
input limitations documented above.
