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
