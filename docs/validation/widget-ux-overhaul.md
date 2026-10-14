# Widget, File Tray and live-activity UX overhaul — validation log

Branch `claude/widget-ux-overhaul` in `~/DynamicIsland-worktrees/widget-ux-overhaul` (outside iCloud `Documents`).

## Milestone A — baseline and preservation (2026-10-14)

- Rescue checkout `~/Documents/DynamicIsland-main` (`feature/camera-hand-navigation` @ `1cd01b4`) was **not modified**: HEAD and index unchanged, nothing reset, cleaned or stashed. A live Codex session (pid 2947) was still editing it and building Release during the snapshot.
- Snapshot mechanism: `git worktree add -b claude/widget-ux-overhaul … 1cd01b4`, then a NUL-safe `rsync --files-from` of the 71 modified tracked files and 55 untracked source/test/doc files. `graphify-out/` cache and `.playwright-cli/` output were excluded.
- Verification: a SHA-256 of every copied file was re-checked against the rescue checkout immediately after the copy, with 0 mismatches at 13:28:20. The manifest is in `~/DynamicIsland-worktrees/rescue-snapshot-manifest/` (`files.z`, `copied.sha256`, `when.txt`).
- The snapshot is committed as `e567b8b` on the isolated branch only.
  - To revert, drop the branch or worktree.
  - To bring later Codex edits forward, diff the rescue checkout against `copied.sha256` and apply that delta.
- Baseline `swift build` (debug) of the snapshot: passed.

Not yet available:
- `docs/contracts/native-audio-widget-contract.md` (Codex) does not exist yet.
- Reference screenshots: only #1 (Droppy shelf row with camera) at `~/Desktop/Screenshot 2026-10-14 at 12.21.46 PM.png` and #6 (lock screen, `research/visual-references/agents/lock-screen/`) were found. #2–#5 (file context menu, per-app volume ×2, other) were not on disk.

## Milestone B — three-size Camera widget

Implementation:
- `IslandWidget.camera`:
  - media surface only
  - always offered; the widget itself shows disabled, denied and no-camera states
  - palette tint added
  - persisted through the existing lossy `WorkspaceConfiguration`, so an older build drops only that placement
- Sizes come from the shared `WidgetGridMetrics.span` (Compact 1×1, Standard 2×1 at the same row height, Large 2×2). There are no hard-coded screenshot pixels and no new sizing system.
- `CameraWidgetView` (`Views/CameraWidgetView.swift`):
  - One rounded, continuous rectangle using `WorkspaceEditorChrome.cornerRadius` × display scale, the same token as the editor chrome.
  - Live frames come from the existing `CameraPreviewView`: `AVCaptureVideoPreviewLayer`, `.resizeAspectFill`, mirrored. There is no stretching and no extra border.
  - Capture uses the existing `CameraMirrorConsumerLease` on the single `CameraPreviewController` session. No new session is created. Appearing only registers a consumer.
  - Start, Allow and Retry are explicit. Collapse ends the request (`islandDidCollapse`). Stop records a user close.
- If hand navigation owns the running session, the widget shows its frames but **does not offer Stop**, because that Stop could not turn the camera off. A hand glyph explains the owner instead. This prevents the widget and gesture navigation from competing for capture ownership.
- States:
  - live
  - starting
  - Allow (permission not requested)
  - Open Settings (denied or restricted)
  - Start (authorized and idle)
  - Retry (failed)
  - disabled
  - no camera
  - Settings sample, which never touches capture
- Large adds a hover-revealed camera picker when more than one device is present. Every size shows a hover-revealed Stop and offers a context menu.
- VoiceOver: label "Camera", the value is the state, and a named action (Start camera / Stop camera). Reduce Motion uses `WorkspaceMotion.smoothContent(reduceMotion:)`.

Tests:
- `CameraWidgetTests`: 6 tests covering
  - the resolver for every permission and phase, including "running without a session is not live"
  - media-only eligibility
  - persistence round-trip at every size, plus lossy decoding of unknown kinds
  - the size grammar: Standard is 2 Compact widths at the same height; Large is 2×2
- Focused run: 42 tests, 0 failures.
- Accidental full-suite run on this source: **2,431 tests, 42 skipped, 2 failures**. Both are the pre-existing rescue cases `IslandKeyboardAcquisitionTests.testResignKeyReleasesEngagementWithoutDestroyingDraft` and `testReturnShiftReturnDeleteAndRepeatedReopenUseExactEditor`. The second focused rerun reproduced the same two; `CameraPreviewControllerTests` passed. They are unchanged and unrelated to the camera widget, and need an idle-machine reproduction.
- Visual check: an uncommitted `ImageRenderer` scratch rendered the ready, Allow, denied and no-camera states at all three sizes. That caught unpadded action buttons, which were fixed.

Native acceptance not done:
- live capture in the widget, which needs your approval to start the camera
- hover controls
- the context menu inside the panel
- the device picker
- interplay with active hand navigation on real hardware

## Milestone C — File Tray context menu and multi-file operations

Implementation:
- `FileTrayItemMenu` (`Views/ModuleViews.swift`) is a SwiftUI `contextMenu`, rendered by AppKit as a native `NSMenu`, so submenus and keyboard navigation are native.
- Targets: if the clicked item is part of the selection, the menu acts on the whole selection, otherwise on the clicked item. Right-click never changes the selection.
- Sections:
  1. Open (all targets) · Open With (single item; "No other applications" when empty) · Quick Look (all targets) · Show in Finder (selects all targets).
  2. Copy · Share (a `ShareLink` submenu backed by the native sharing services).
  3. **Create New Files** (originals never change):
     - Convert To ▸: only formats every selected image supports; audio formats for one audio/video file. "More Options…" opens the existing File Actions panel. Inapplicable selections show an explanatory disabled line.
     - Extract Text: images only; on-device Vision; the text goes to the clipboard.
     - Remove Background: only when `FileTrayActionTargets` says it is available (one image).
     - Create ZIP Archive.
     - New Folder with Copies.
  4. **Change Files on Disk**: Rename… (single item) · Save a Copy To… · Move To….
  5. **Tray Only**: Copy Path(s) · Copy File Name · Move to Basket · Remove from Tray (Keeps File).
  6. File Tray Settings….
- Not added: a cloud provider entry (no working provider exists) and a separate "Compress". In this codebase Compress *is* the verified ZIP; there is no image or video size-reduction back end, and a fake one was not shipped.
- Shared operations (`Modules/FileTrayOperations.swift`, an extension of `FileShelfStore`, reused by milestone D):
  - Each operation writes new collision-safe outputs, adds them to the Tray and selects them.
  - `operationStatus` (working / succeeded / failed) is shown as one row in the Tray.
  - `succeeded` is published only once the output exists **and** the Tray accepted it. A full Tray, a partial batch failure or zero outputs are reported as failures with exact counts.
- Folder creation **copies**: "New Folder" (collision-safe) is created beside the first item, the items are copied in (the existing `FileShelfDiskOperations.copy`, which rolls back its own copies), and the folder is added and selected. On failure only the folder this call created is removed.
- ZIP: `BackgroundOperationController.startCompression` gained an optional `onCompleted` callback, and existing callers are unchanged. The archive joins the Tray only after the `ditto` + `unzip` verification completes, so progress and cancellation remain in the existing background-operation UI.

Tests: `FileTrayOperationsTests`, 10 cases on real temporary files, none of the user's files.
- Convert: original byte-identical, output added and selected.
- Partial batch failure: "Added 1; 1 failed", corrupt input unchanged.
- Duplicate name: never overwrites; `dup 2.jpg`.
- Folder copies with a collision → `New Folder 2`.
- Folder rollback on a missing source.
- Unwritable destination (0555): no side effects.
- ZIP: the status stays `working` until the archive exists; the source stays in the Tray.
- A full Tray is reported, not claimed.
- Unsupported conversion: refused without writing.
- Vision OCR reads rendered text.

Connected suites (BackgroundOperationCenter, FileShelf*, FileAudioConversion, FileActionPresenter, BasketManager): 56 tests, 0 failures.

Native acceptance not done:
- the physical right-click menu inside the island panel
- submenu traversal while the island stays open (milestone E owns the collapse lease)
- the Share sheet
- Finder reveal
- app restart and Tray restore with the new outputs

## Milestone D — four-zone drag overlay and basket access

Implementation:
- `FileDropZonesOverlay`: a fixed 2×2 grid of **Keep in Tray**, **Convert**, **Share** and **Create ZIP**.
  - Geometry never changes during a drag; only fill, stroke and label weight change.
  - Labels are centred, each zone has its own `.onDrop`, and Reduce Motion falls back to opacity.
  - It replaces the old single "Drop files here" highlight over the expanded Tray. The unused `FileDropHighlightView` was deleted.
- Each zone is **one transaction on the existing drop model**: `claimShelfDrop` (one claim per drag generation; a second zone cannot claim) → `completeShelfDrop` adds the files to the Tray → the zone's action runs on exactly the accepted files.
  - Keep: add only. `completeShelfDrop(requestActions: false)` keeps the File Actions panel closed.
  - Convert: add, then the existing File Actions panel, which is the format-selection flow.
  - Share: add, then the existing `FileDragActionExecutor` share picker, anchored to the persistent Tray view because the zone disappears on drop.
  - ZIP: add, then the shared `createZIP` from milestone C.
  - A stale or disallowed drop reports "The drop was not added to the Tray". Nothing claims success because an animation finished.
- Zones register a dedicated drag region, `FileDragSourceRegion.trayDropZone`. Moving from the shelf target onto a zone, or between zones, therefore never ends the drag session. That avoids an overlay ↔ target flicker loop.
- Basket access: a **Basket** button in the Tray header, shown only while the Tray has files and `floatingBasketEnabled` is on.
  - It calls `BasketPresenter.showPrimaryBasket()` through the existing `BasketShelfTransfer` environment hook, which gained `showBasket`. There is no second basket store.
  - It is keyboard focusable and has a VoiceOver label.

Tests:
- `FileDropZoneTests`, 4 cases:
  - the zone region keeps the session while the shelf target leaves, and the session ends once the zone leaves
  - Keep adds without opening File Actions; Convert opens them
  - a second claim is refused and a stale claim adds nothing
  - labels
- Connected Basket / FileDrag / ShelfDropClaim / FileTray suites: 102 tests, 0 failures.

Native acceptance not done:
- real Finder drags over each zone (hover highlight, multi-file, file promises, cancel by dragging away)
- the share picker anchoring
- the basket opening from the header
- interaction with the below-shell AirDrop/Messages/Mail/Share orbit while dragging

`ImageRenderer` cannot draw `.onDrop`-backed views (it shows a placeholder), so the overlay's look needs a live check.

## Milestone E — collapse ownership

Finding: the central, reason-scoped hold already exists, so no parallel system was added. Hover-exit collapse is decided only by `ExpandedHoverContainment.decide` over `currentExpandedHoverHolds` (`OverlayWindowController`). Each requested case maps to an existing hold:

| Interaction | Hold |
|---|---|
| Native context menus and submenus, including File Tray, camera device and share pickers | `menuTracking` (`NSMenu` begin/end tracking) |
| Drop zones and active file drop | `fileDrag` (`FileDragSessionController.isActive`, including the new `trayDropZone` region) |
| File Actions / conversion panel | `transientInteraction` owner `.fileActionPanel(UUID)` |
| Rename popover, calendar overlay, other `NSPopover`s | `nativePopover` |
| **Move To… / Save a Copy To… / conversion destination (`NSOpenPanel`/`NSSavePanel`)** | `nativePopover`. **This was a gap and is fixed here** |
| Keyboard editing, agent composer | `textInput` (key panel + engaged editor; native UX rescue rules unchanged) |
| Workspace editor, Agents launcher, calendar picker, camera navigation | existing `TransientInteractionOwner` cases |
| ZIP progress | No hold: a running ZIP continues after collapse in the background-operation center. Holding the island open for its duration would leave it stuck open. |
| Audio slider drags | Deferred to milestone G, as a `TransientInteractionOwner` case added with the slider itself |

Every hold is released by its own lifecycle: menu end notification, owner `false`, window close, focus loss or drag-session reset, so ordinary auto-collapse resumes after the last one ends. Escape priority is the native UX rescue's ordering, unchanged.

Tests: `NativePopoverContainmentTests.testTransientNativeWindowClassifier` adds open/save panel cases, including that a closed panel releases the hold. Containment and reachability suites: 17 tests, 0 failures.

Native acceptance not done: traversing menu gaps; leaving the island into an open panel and back; Escape order with a panel open.

## Milestone F — contextual collapsed previews and orbs-only agents

Implementation:
- `CollapsedActivityHoverPolicy` gained `.activityPreview(height:)`, which grows the collapsed shell **downward only**, by the preview's content height (48–70 pt), at a minimum width of 300.
  - Precedence: an exact agent approval comes first (unchanged), then message reply and peek, then call controls, then activity previews.
  - With `collapsedHoverPreviewEnabled` off, no preview is built and the old hover behavior, including expand-on-hover, is unchanged.
  - A preview replaces whole-island hover expansion for that activity only.
- `CollapsedActivityPreview` is a pure model built only from existing state:
  - **Media:** title and artist as readable 13 / 11.5 pt marquees (slow 24 pt/s with a 1.6 s rest; static and middle-truncated under Reduce Motion). Elapsed · remaining is centred, and shown only when the source reports progress.
  - **Battery:** the Mac's name (`SCDynamicStoreCopyComputerName`, a local lookup), the percentage and the charging state. No time estimate, because none is reliable.
  - **Timer:** the live activity's title and detail.
  - **Agent:** project, provider glyph, the displayed state ("Thinking", "Running command", "Awaiting approval"…) and the running command's executable name, or the running tool's name, via `AgentPrivacyProjection`. Arguments, paths and secrets never appear.
- The preview reuses the existing message-peek pipeline: the generation-guarded delayed hover, `layoutStore.updateCollapsedPreview` for the shell frame and hit region, and the existing animation. It no longer requires a message entry.
- Collapsed visualizer (`CollapsedVisualizerPlaybackControl`):
  - Hover dims and blurs the bars and reveals Pause or Play. Clicking calls `MediaController.playPause()`.
  - The glyph follows the *observed* `isPlaying`, so a failed command never shows a false state.
  - It is only enabled when transport control is available, and exposes a VoiceOver action.
  - While the visualizer is hovered, the media preview and hover auto-expansion are suppressed. They resume when the pointer moves back onto the rest of the island.
- Routine agent pill, **orbs only**:
  - Leading: the primary orb plus the provider glyph, 33 pt.
  - Trailing: mini orbs for the other visible sessions and a `+N` badge, or one state glyph, 16 pt.
  - This replaces the 62–112 pt name and state-label wings. Names, states and commands are in the hover preview and in VoiceOver labels.
  - Attention and approval pills are **unchanged**, so an urgent approval is never hidden.

Tests: `CollapsedActivityPreviewTests`, 6 cases:
- media times only with real progress
- battery and timer read from the activity; non-preview kinds give nil
- agent command sanitised (`curl` out of a full command line with a bearer token)
- the policy's downward growth and precedence (approval and message still win)
- previews stay at or under 70 pt
- orbs-only agent widths

Connected collapsed, agent, notch-geometry, layout and Settings preview suites: 193 tests, 0 failures, 3 pre-existing skips. A scratch render of all four previews was inspected and not committed.

Native acceptance not done:
- the pointer path between the island and a grown preview (flicker)
- visualizer hover → pause → play on real players
- whether a click on Pause inside the collapsed island ever falls through to click-to-expand
- notchless and external displays
- the multi-session orb row

### Full-suite checkpoint after F (`ad8d098`)

- `swift test`: **2,451 tests, 42 skipped, 4 failed cases (10 assertion failures)**, 184.6 s.
  - The 2 known `IslandKeyboardAcquisitionTests` cases, unchanged.
  - `SettingsWindowTests.testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy`: passed 2/2 in isolation; the native-input flake also seen in Codex's runs.
  - `WorkspaceNativeEditorTests.testNativeAddCancelDoneAndResetOnlyPersistCommittedTransaction`: failed while the machine was loaded right after a Release build. Afterwards it passed 3/3 on this commit and 3/3 on the pre-F commit `1236f62` (temporary worktree). It is a synthetic-event timing test whose fixture hosts only `IslandWidgetEditor`, which F does not touch.
- `swift build -c release`: passed (258 s).
- Packaging and signing: not run in this checkpoint.

## Milestone G — real audio visualizer integration

Backend:
- Codex's `feature/native-audio-foundation` @ `fedfc06` was cherry-picked unchanged: `a063866`→`cd88511`, `b401e2d`→`8f10ab1`, `fedfc06`→`cf4bd26`. Author metadata is preserved.
- `git diff fedfc06 HEAD -- Sources/DynamicIsland/Audio Tests/DynamicIslandTests/NativeAudio*.swift Scripts/package_app.sh` is empty.
- No DSP or capture code was changed, and no second capture engine was added. Codex's 19 `NativeAudio*` tests pass on this branch.
- Codex's uncommitted worktree changes were not integrated.

Implementation (contract revision 2):
- **Ownership:**
  - `AppDelegate` owns one lazy `AudioSpectrumController`. Creating it only subscribes to sleep and session-resign notifications.
  - It is passed through `IslandModules.audioSpectrum` and injected as `\.liveSpectrum` (`(any LiveSpectrumProviding)?`).
  - Settings previews and tests have no provider, so they always show the decorative fallback.
- **Explicit start only:**
  - The **Live Audio** toggle (`LiveAudioMenuItems`) lives in every media visualizer's context menu, collapsed and expanded. On calls `startFromUserAction()` and Off calls `stop()`.
  - Nothing starts capture from `onAppear`, preview creation, subscriptions or launch.
  - No second "enabled" value is persisted, so after a relaunch Live Audio is off until the user turns it on again.
  - The menu header shows the real state:
    - Off · decorative
    - Starting…
    - Live, or Live · no sound right now
    - Stopped for sleep or lock (no automatic resume)
    - System Audio Recording is off, with Open Privacy & Security… offered only after an explicit `.permissionDenied`
    - Needs macOS 14.2 or later
    - No audio frames arrived
- **Drive** (`LiveVisualizerMode`): bars are live only while `availability == .capturing`, a frame exists, **and** `MediaController` reports the track playing.
  - Silence gives `.liveSilent`: low bars, never "paused".
  - Other apps' audio never animates a paused track.
  - Call visualizers are never live.
  - Off, starting, suspended or failed give the existing decorative animation, labelled in VoiceOver ("Decorative animation, not measuring audio") and in a tooltip.
- **Binding:**
  - `SpectrumBarMapper` maps the eight ascending bands onto the bar count by linear interpolation: 8 bars equal the bands exactly; 7 collapsed and 12 expanded interpolate, so every bar is independent.
  - Values are clamped to 0…1 with NaN/∞ treated as 0, and a 0.12 floor.
  - `SpectrumBarSmoother` is presentation-only, fast attack (0.72) and slow release (0.24) per 30 Hz frame.
- **Color:**
  - `ArtworkAccentColorExtractor.secondaryColor` picks the artwork half that differs most from the primary color.
  - Grayscale art gets a tonal gray partner, never an invented hue. Halves that are too close get a hue-shifted partner.
  - It is computed in the existing cache's background pass.
  - `VisualizerGradient` interpolates sRGB components from the first bar to the last, passing smoothly through the centre. It is solid when there is no partner, or when the accent mode is not artwork.
- **Reduce Motion** gives `.still`: no live or decorative motion, and a VoiceOver label.
- **Milestone F preserved:**
  - The collapsed hover Pause/Play wraps the visualizer unchanged, and its glyph is a tested function of the observed `isPlaying`.
  - Media, agent and other previews, the orbs-only agent pill and the collapsed geometry are untouched (connected suites pass).
- **Termination:**
  - `applicationShouldTerminate` always returns `.terminateLater` and awaits `shutdown()`, which also awaits teardown still pending after Off or sleep. It then replies.
  - An idle controller returns at once, and a 3 s race guarantees that a stuck HAL call never blocks quitting.
- **Per-app volume:** no slider UI exists or was added. `ApplicationVolumeProviding` stays a contract only, with no implementation, so nothing claims per-app control.

Tests: `LiveAudioVisualizationTests`, 12 cases:
- Binding: 8 bars match the bands exactly; other counts interpolate without a repeating pattern; invalid values clamp.
- Smoother: attack beats release and still settles; a bar-count change adopts the target.
- Drive: live only while capturing and playing; silence gives `liveSilent`; never for calls; never without a frame.
- Reduce Motion is still, with labels.
- Status for every availability and permission. "No frames" never offers privacy settings.
- Lifecycle with a counting fake backend:
  - Creation, subscription and menu rendering start nothing.
  - The switch starts exactly once, even on a double toggle.
  - Off tears down, clears the frame, and late frames cannot relight it.
- Gradient endpoints and midpoint.
- Secondary color for grayscale, distinct and near-identical artwork.
- The hover glyph follows the observed state.

Results:
- Focused audio, preview and media suites: 57 tests, 0 failures, 1 pre-existing skip.
- Full `swift test` at the pre-commit source: **2,481 tests, 43 skipped, 5 failed cases (12 assertions)**, all native-input timing cases:
  - `IslandKeyboardAcquisitionTests` (4 cases): all 9 keyboard tests passed in isolation twice afterwards.
  - `SettingsWindowTests` pointer: failed twice in isolation, then passed 2/2 on this source and 2/2 on the pre-G commit `2de2824`.
  - None of these touch audio or visualizer code.
- `git diff --check`: clean. `swift build -c release`: passed (237.6 s). `Scripts/package_app.sh`: passed.
- `codesign --verify --strict` passed for all three helpers; `codesign --verify --deep --strict` passed for the app.
- The packaged `Info.plist` contains Codex's `NSAudioCaptureUsageDescription`.

Not done, deliberately: no live audio permission was requested, the running app was not replaced, and no capture ran. Native acceptance remains:
- the TCC prompt
- bars following real music
- silence handling
- sleep stopping capture
- the quit path with an active tap
- the gradient on real artwork

### Integration instructions

1. This branch already contains Codex's `fedfc06` content as `cd88511..cf4bd26`. Do **not** also merge `feature/native-audio-foundation`'s uncommitted overlay files, which are Codex's local test baseline.
2. If `feature/native-audio-foundation` gains new commits, cherry-pick only those commits onto this branch, then re-run `swift test --filter 'NativeAudio|LiveAudioVisualization'`.
3. Files touched by G that the rescue checkout may also change:
   - `App/DynamicIslandApp.swift` (new `audioSpectrum` lazy var, `IslandModules(... audioSpectrum:)`, `applicationShouldTerminate`)
   - `Views/IslandRootView.swift` (`.environment(\.liveSpectrum, …)`, `visualizerSecondaryColor`)
   - `Views/ModuleViews.swift` (`AudioVisualizerView`, `visualizerSecondaryColor`)
   - `Modules/ArtworkAccentColorExtractor.swift`
   - `Modules/IslandModule.swift`

   Apply rescue deltas from `~/DynamicIsland-worktrees/rescue-snapshot-manifest/copied.sha256` as a diff on top; resolve conflicts by keeping both sides' additions.
4. A Settings v3 "Live Audio" row (and optionally a menu-bar item) should bind to the same `LiveSpectrumProviding` start/stop, with no persisted flag, once Settings ownership (milestone H) is resolved.
