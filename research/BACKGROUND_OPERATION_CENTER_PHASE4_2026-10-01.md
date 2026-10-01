# Phase 4 — Background Operation Center

Date: 2026-10-01  
Baseline: `31e74302b8c6d80f5d4574fd78e67372c15c9453` on `feature/agents-ui-overhaul-continuation`.

## Architecture

Phase 4 adds a reusable background-operation domain instead of putting long-running file state in Shelf views.

- `BackgroundOperation` has a stable UUID identity plus an execution generation, kind, sources, destination, state, progress, timestamps, result/failure, and cancellation capability.
- Lifecycle is explicit: `queued → preparing → running → completed / failed / cancelled`.
- Progress supports truthful determinate values and indeterminate work. Generation-scoped updates reject stale callbacks, and determinate progress cannot regress.
- `BackgroundOperationController` owns concurrent operations, exact-operation cancellation, deterministic presentation ordering, recent terminal history, and Live Activity projection.
- Active operations are never evicted by recent-history trimming.
- Operations are intentionally in-memory in this phase. Relaunch does not claim to resume interrupted work.

## Compression authority

The first real workload is Shelf-selection-backed ZIP compression.

- Local authority: `/usr/bin/ditto`.
- Archive verification: `/usr/bin/unzip -tqq`.
- No upload or network authority is involved.
- Single files produce `<name>.zip`; single folders preserve the folder root; multi-selection produces `Archive.zip`.
- Existing destinations receive Finder-like suffixes such as `Archive 2.zip`.
- Multi-selection is copied into a DynamicIsland-owned staging directory before archiving so mixed files/folders preserve useful top-level names.
- The final archive is not published until compression finishes, cancellation is rechecked, and the archive validates successfully.
- Originals are never removed or modified.

## Cancellation and temporary ownership

Each running compression has an exact operation ID. Cancellation terminates only that operation's active `Process`.

DynamicIsland-owned intermediates live under:

`FileManager.default.temporaryDirectory/DynamicIsland/BackgroundOperations/<operation-id>`

That directory is removed on success, failure, or cancellation. User-owned sources are outside this ownership boundary and are never deleted by cleanup.

## Island integration

Background operations project through the existing `LiveActivityStore` and `LiveActivityLayoutResolver` as `.backgroundOperation`.

- Active operations prefer a trailing sidecar and may fall back to the other side or primary slot.
- Width pressure removes the operation sidecar before replacing a Media primary.
- Selecting an operation sidecar routes to the Tray.
- The expanded Shelf contains a compact Operation Center with status, real determinate progress when available, indeterminate state otherwise, exact Cancel, and completed Open / Show in Finder actions.
- Reduce Motion and accessibility labels/values are supported.

The external drag orbit remains a separate authority. AirDrop, Messages, Mail, and Share still operate on the external drag payload; Compress operates only on the resolved Shelf selection.

## Validation

Focused production tests cover real ZIP creation, mixed file/folder archives, collision naming, missing sources, identity isolation, stale-generation progress rejection, operation-specific cancellation, terminal-state protection, deterministic presentation, and Live Activity publication.

An opt-in real-process stress suite also verifies:

- two real compressions can run concurrently without sharing cancellation/state;
- a running 96 MB incompressible `ditto` archive can be terminated;
- cancellation leaves the original intact;
- no partial final ZIP is published;
- the operation-owned temporary directory is cleaned.

Snapshot coverage includes preparing, indeterminate, 25/50/90 percent, completed, failed, cancelled, two simultaneous operations, Reduce Motion, and notched/floating Live Activity combinations with Media, Timer, Battery, and Agents.

## Deferred

Phase 4 does not enable Quickshare/cloud upload, Floating Basket, OCR, watched folders, or extraction. Existing image conversion remains real ImageIO work but has not been migrated into the Background Operation Center because the current conversion path does not expose a truthful long-running progress/cancellation authority.

