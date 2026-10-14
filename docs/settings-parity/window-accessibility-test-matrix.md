# Native window and accessibility acceptance

Production `--validate-settings` runs a real Settings NSWindow with isolated preferences, offline providers, empty Agent events and no capture owner. It never terminates another app copy or starts normal services. Native content PNGs and an additional public ScreenCaptureKit capture of only this process's window are in `/tmp/dynamicisland-settings-v3-resumed-native/`. This packaged run predates the newest independent compact file-popup and app-exclusion milestone; repeat acceptance is required for those changes.

| Check | Packaged native result |
|---|---|
| Singleton reopen / native close / minimize / restore | Pass; actual Cmd-W/Cmd-M menu equivalents and retained reopen |
| Native fullscreen enter/exit | Pass; local press on the actual green button and Ctrl-Cmd-F exit |
| Frame restoration / native resize | Pass; regular frame restored after fullscreen; separate native panel-size reset restores 720×700 content |
| History / picture choice / preference persistence | Pass; native Back/Forward and General notch choice clicks |
| Three external-display choice cards | Native click/persistence pass; actual display visibility/Spaces remains physical |
| Workspace sheet / Escape / Cancel | Pass; production editor sheet opens and Escape preserves placement |
| Independent sidebar/detail scrolling | Pass in recorded per-page checks; full keyboard-only walkthrough incomplete |
| VoiceOver and tall popup navigation | Partial AppKit labels inspected; full SwiftUI/VoiceOver/tall-menu acceptance not run |
| Contrast/transparency/Reduce Motion/larger text | Captures include light/dark/Reduce Motion; complete preference walkthrough pending |
| Multi-display disconnect / Spaces | Requires appropriate physical display setup |
| Real concurrent Agent/Terminal/recording activity | Existing sessions untouched; native fixture does not establish live concurrency acceptance |

Native loop metrics: 32.653s wall, 13.427s user CPU, 1.583s system CPU, maximum resident memory 391,577,600 bytes (~373.46 MiB). These describe an active screenshot/navigation acceptance workload, not five-minute steady-state use or idle.

Latest repetition evidence: `/tmp/dynamicisland-v3-continuation-native-path` points to the new isolated package run. Compact File Actions presentation/owner/cleanup passed. Main display was asleep (`CGDisplayIsActive=0`, `CGDisplayIsAsleep=1`), so current minimize/close/fullscreen and display-callback checks did not pass. No awake-display repetition is claimed. Prior successful packaged evidence above is retained. The display must be awake/unlocked for repetition; tests do not wake it or reset permissions.

Newest package/native repetition (including Basket Instant appear and Shelf Auto-expand) is recorded in the progress report and `/tmp/dynamicisland-v3-basket-hover-native-path`. Compact popup show/ownership/cleanup remains passing. `mainDisplayActive=false` and `mainDisplayAsleep=true`; logical fullscreen flags may change, but displayed behavior and keyboard minimize/close are not accepted from this run.
