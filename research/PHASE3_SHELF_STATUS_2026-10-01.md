# Phase 3 — File Shelf 2.0 + Drag Quick-Action Orbit

Checkpoint: 2026-10-01. Branch: `feature/agents-ui-overhaul-continuation`.

## Source-first parity

Droppy reference checkout: `/Users/makeiteasy3/Downloads/Droppy-main` (audited private-use reference documented in `SOURCE_PARITY_MANIFEST.md`). Relevant source reviewed: `ShelfQuickActionsBar.swift`, `FilePromiseDropView.swift`, `NotchShelfView.swift`, `ShelfView.swift`, `DragMonitor.swift`, `NotchDragContainer.swift`, `DraggableArea.swift`, `DraggableItemWrapper.swift`, `BasketQuickActionsBar.swift`, `MailHelper.swift`, and `DroppyState.swift`.

Source-backed orbit constants retained: 32 pt circles, 12 pt spacing, transparent bridge area, ~1.18 targeted scale, ~1.05 hover scale, and 0.03 s stagger between action entrances. AppKit `NSFilePromiseReceiver` is used for Photos/Finder promised files rather than relying on SwiftUI `fileURL` drops.

## DynamicIsland architecture

`FileDragSessionController` is the generation-scoped authority for an external drag. Its payload is intentionally independent from `FileShelfStore.selection`; one drop claim may execute at most once. Source region, bridge and action-target ownership keep the orbit alive while the pointer crosses gaps. Stale async promise completions cannot execute an action for a newer drag.

`FilePromiseDropNSView` accepts direct file URLs and native file promises. Promised files materialize inside DynamicIsland-owned temporary storage; partial multi-file promise failure is fail-closed, and only app-owned temporary materializations are cleaned. Stable Finder/Desktop originals are never deleted.

## Drag orbit

During a relevant external drag, the normal selection-backed Tray quick-action row morphs to a source-backed orbit below the island. Production orbit actions are AirDrop, Messages, Mail and native Share. Hover/target state magnifies the circle and projects a concise explanation into the Tray while preserving Shelf state.

Quickshare is deliberately absent: uploading a user's file to a third-party host remains `REQUIRES APPROVAL`. Basket and Compress are also not advertised without their later production authorities. Existing Remove Background / Convert / Share remain selection-backed Tray actions and are not allowed to substitute Shelf selection for an external drag payload.

System authority probe on the development Mac found native AirDrop, Messages and Mail sharing services present and `canPerform(withItems:) == true` for a real temporary file. This proves local service availability, not a completed user handoff; physical drop/compose acceptance remains manual.

## File Shelf 2.0

Implemented real core operations: deterministic Command/Shift multi-selection, Select All, folders as real Shelf items, Quick Look, Open, Open With, Copy, Rename, Copy To, Move To, Reveal in Finder, Copy Path, Copy File Name and Remove from Shelf. Rename/move retarget Shelf selection and persistence. Remove from Shelf never deletes stable originals; only DynamicIsland-owned temporary materializations are eligible for cleanup.

Literal Droppy hierarchical folder browsing, OCR, ZIP/unzip, compression progress, cloud Quickshare, pinned/watched folders and Floating Basket remain outside this checkpoint. Long-running conversion/compression/upload progress belongs to Phase 4 Background Operation Center rather than being faked here.

## Validation contract

Focused coverage includes external-drag generation safety, exact-payload execution, bridge lifetime, native pasteboard URL bridging, promise storage ownership, Photos-style provider representations, stable Shelf ordering/range selection, folders, collision-safe rename/copy/move, static Tray authority and accessory-owner coexistence.

Opt-in orbit rendering uses `DYNAMIC_ISLAND_FILE_DRAG_SNAPSHOT_DIR`. It renders idle production Tray plus notched/notchless drag entrance, fully visible orbit, AirDrop hover/target, Messages target and Reduce Motion states. Generated frames are inspected rather than merely counted.

Real Finder/Desktop/Photos drag-and-drop plus the actual AirDrop/Messages/Mail compose UI require physical GUI interaction. If that cannot be performed by the execution environment, classify those paths as `IMPLEMENTED — MANUAL REAL-DEVICE ACCEPTANCE REQUIRED`, not real E2E verified.

No new entitlement, Full Disk Access scope, cloud host, upload behavior, dependency, push, merge or rebase is authorized by this phase.
