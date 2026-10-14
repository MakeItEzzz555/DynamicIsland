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
