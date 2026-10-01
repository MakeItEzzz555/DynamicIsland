# Floating Basket Phase 6 — finalization and acceptance evidence

Date: 2026-10-01 / 2026-10-02 local
Branch: `feature/agents-ui-overhaul-continuation`
Finalization starting HEAD: `ff19e4c0d7077831ba48cb928be33de40c3f839a`

## Scope recovered

The interrupted run had already committed the core Floating Basket implementation:

- `096dc14 feat(basket): add basket domain, file ownership and jiggle detection`
- `c8e9b9b feat(basket): add floating basket panel, switcher and shelf integration`
- `ff19e4c test(basket): add display-matrix renders and fix list height clipping`

This continuation reviewed and finalized that work only. Calendar, Voice, Screen Recording, Agents and later roadmap phases were not reimplemented.

## Source-first references actually inspected

Exact local Droppy reference files:

- `Droppy/FloatingBasketWindowController.swift`
- `Droppy/BasketState.swift`
- `Droppy/DragMonitor.swift`
- `Droppy/BasketQuickActionsBar.swift`
- `Droppy/BasketDragContainer.swift`

The source review reconfirmed the relevant behavior used by DynamicIsland: per-Basket state, multi-Basket identity/accent behavior, hidden-Basket recovery, drag-pasteboard jiggle detection with a 0.5 s window, quick-action target ownership, file-promise materialization, and floating window lifecycle.

### User-provided Droppy recordings inspected

All four supplied recordings were sampled into contact sheets and inspected.

- `Screen Recording 2026-09-29 at 8.58.03 PM.mov` was directly relevant. It shows the detached floating Basket, item presentation, the quick-action bolt below the Basket, context interaction, notch/Shelf presentation and Quickshare UI.
- `Screen Recording 2026-09-29 at 9.04.02 PM.mov` was directly relevant. The Droppy demo shows “Drop it on the notch” and “Or shake it” Basket discovery/reveal behavior, including notched/notchless product presentation.
- The 2026-01-12 recording was Discord-oriented rather than Basket reference material.
- The 2026-09-28 recording was AgentNotch/approval-oriented rather than Basket reference material.

ExploreSwiftUI was not needed for a new correction in this finalization: the regenerated production Basket renders were already coherent after the committed list-height fix, so no speculative component rewrite was introduced merely to use another source.

The tracked project guidance already preserves the future UI source policy: Droppy source first, ExploreSwiftUI where a proven native pattern is relevant, then supplied Droppy recordings for visual/motion evidence, while retaining stronger DynamicIsland backend authority and documenting intentional divergence.

## Basket architecture / ownership

`BasketManager` owns domain mutation; `BasketPresenter` composes the drag monitor, jiggle decisions, windows, switcher and quick actions; each Basket has independent `BasketState` and one floating AppKit panel.

Verified ownership semantics:

- Adding an original file to a Basket never silently moves or deletes the original.
- Removing a stable original from Basket state does not delete it.
- App-owned materialized temporary files are deleted only after their last ownership surface releases them.
- Shelf → Basket and Basket → Shelf transfer DynamicIsland surface ownership without moving the original filesystem object.
- Basket → Basket transfer preserves temporary-file ownership correctly.
- On-disk Rename succeeds before Basket state records the new URL.
- Background-removal/compression result ownership returns to the exact requesting Basket.
- Stale drop claims cannot mutate a closed Basket; orphaned temporary promise output is cleaned safely.

Basket contents themselves are not currently persisted across app relaunch. Therefore relaunch recovery applies only where current persistence policy actually records state; no fake Basket-content restore was claimed.

## Finalization defects found and fixed

### 1. Asynchronous panel dismissal could leave an orphaned visible Basket

The previous `FloatingBasketWindowController.dismiss` delayed `orderOut` through a work item capturing the controller weakly. A Basket identity can disappear while that exit animation is pending; if the controller deallocated first, the panel could remain visible.

Fix: the dismissal work item now captures the actual `NSPanel`, so panel teardown no longer depends on controller lifetime.

Regression test: `BasketPresenterLifecycleTests.testDismissOrdersOutPanelEvenIfControllerIsReleasedDuringAnimation` presents a real Basket panel, starts the asynchronous dismissal, releases the controller and proves the panel still orders out.

### 2. Concurrent switcher file-promise drops could release another Basket's hold

The switcher previously kept only a set of claim IDs. Resolving/failing one ambiguous claim could fall back to clearing `.dropInFlight` on every Basket. With concurrent async file-promise materializations, one completion could therefore release another Basket's hold and allow premature auto-hide.

Fix: `BasketSwitcherClaimRegistry` maps each claim to its exact Basket UUID. Completion/failure releases only the exact target's hold, and every claim resolves once.

Regression test: `BasketPresenterLifecycleTests.testSwitcherClaimsReleaseOnlyTheirExactBasket`.

### 3. Drag monitor teardown explicitly pinned

A new jiggle test starts the production monitor, establishes a real simulated file-drag generation, calls `stop()`, and verifies the timer stops, the drag ends exactly once and repeated teardown remains idempotent.

Finalization repair commit:

- `f51906a fix(basket): harden async panel and drop claim lifecycle`

## Jiggle / shake behavior

Verified current architecture:

- no Accessibility permission is required;
- detection is based on pointer movement plus the drag pasteboard;
- source-backed jiggle time window is 0.5 s;
- sensitivity determines required direction changes;
- normal mouse movement and unsupported payloads do not trigger;
- one drag generation triggers at most once;
- a new physical drag gets a new generation;
- suppressed internal Basket drag-outs cannot recursively summon another Basket;
- teardown cancels the timer and ends active drag state exactly once.

Jiggle decision tests also verify hidden Baskets with items are revealed before creating another Basket, single-Basket mode does not create duplicates, and two visible Baskets resolve to the switcher.

## Window / lifecycle review

The floating panel uses runtime screen/visible-frame placement rather than Mac model checks. Tests cover pointer-screen placement, off-screen clamping, display removal and resize preserving top-center geometry.

The finalization repair removes the identified async orphan-window path. Multi-Basket identities remain one-controller/one-window, with presenter reconciliation and hidden-Basket menu recovery as the current authority.

Physical click/drag acceptance remains manual because the available remote connector does not provide direct GUI mouse/drag control. A DynamicIsland instance was already running during finalization, so it was deliberately not terminated or replaced for synthetic click-through evidence.

## Snapshot / visual review

Regenerated with:

`DYNAMIC_ISLAND_BASKET_SNAPSHOT_DIR=/tmp/di-basket-phase6 swift test --filter BasketSnapshotTests`

Result: 2 snapshot-generation tests, 0 failures, producing 31 production-component PNGs.

Actually inspected representative images for:

- empty Basket
- one item
- three-item collapsed stack
- expanded grid
- expanded list on 4K geometry
- multi-selection
- drag-targeted state
- second-Basket accent identity
- Basket switcher
- 14-inch-class notched geometry
- 16-inch-class notched geometry
- 1080p / 1440p / 4K external-display fixtures

Observed result: no row/thumbnail clipping, labels remained inside panels, expanded list rows and file sizes fit, grid spacing was coherent, targeted/selection borders were visible, accent identity was clear and no representative display overflow was seen. No new visual source correction was justified after inspection.

## Settings / Shelf integration

Focused validation keeps the existing Shelf and quick-action behavior green. The Basket Settings preview remains a sandboxed production-component preview and does not invoke real actions.

`SettingsAuditTests`: 9 executed, 1 explicit audit-writer skip, 0 failures. Existing zero-dead-setting / live-preview invariants remain green.

## Calendar / Voice / Screen Recording regression status

These areas were verification-only.

Focused results:

- `CalendarEventsControllerTests`: 7 / 0 failures
- `CalendarSnapshotTests`: 1 / 0 failures
- `VoiceTranscriptionControllerTests`: 26 / 0 failures
- `VoicePermissionIsolationTests`: 2 / 0 failures
- `ScreenRecordingTests`: 23 / 0 failures
- `ScreenRecordingAccessTests`: 6 / 0 failures

No entitlement or architecture change was made to these features.

## Focused Basket / Shelf validation

Passing focused suites after final repairs:

- `BasketManagerTests`: 19 / 0
- `BasketPresenterLifecycleTests`: 2 / 0
- `BasketOwnershipTests`: 8 / 0
- `BasketJiggleTests`: 8 / 0
- `FileShelfStoreTests`: 12 / 0
- `FileTrayQuickActionTests`: 10 / 0
- `BackgroundRemovalControllerTests`: 16 / 0
- `SettingsAuditTests`: 9 executed, 1 skip, 0 failures

## Full validation

Final full gate after the repair:

- `git diff --check`: pass
- `swift build`: pass
- `swift test`: **1576 tests executed, 32 skipped, 0 failures, 0 unexpected**
- `swift build -c release`: pass

Known unrelated compiler warnings remain in pre-existing paths (including Swift sendability diagnostics and a deprecated snapshot capture API); this Phase 6 finalization did not broaden scope merely to silence unrelated warnings.

## Package / signing

`Scripts/package_app.sh`: pass.
Generated `Info.plist`: `plutil -lint` pass.
All three packaged helper signatures verify strictly.

Deep strict verification of the app directly inside the synced `~/Documents` working tree reports the known:

`resource fork, Finder information, or similar detritus not allowed`

A clean copy outside the synced folder was stripped of extended attributes, ad-hoc re-signed and then passed:

`codesign --verify --deep --strict`

Classification: known synced-folder metadata/xattr issue, not an application signing failure.

## Graphify

The interrupted Graphify refresh was completed after source stabilization.

Final graph update reported:

- 11,399 nodes
- 33,510 edges
- 354 communities

Only canonical/current graph outputs are intended for the Graphify commit. Historical graph-copy files, `last_query_stamp`, and unrelated interrupted AST cache noise are not part of the Phase 6 source work.

## Manual real-device checks remaining

Because no direct GUI drag/click control is exposed through the connected remote tool, these are still:

**IMPLEMENTED — MANUAL REAL-DEVICE ACCEPTANCE REQUIRED**

- real shake/jiggle summons Basket during Finder drag;
- add/remove real file;
- Shelf → Basket via production UI;
- context menu;
- grid/list toggle;
- auto-hide;
- menu-bar hidden-Basket recovery;
- multi-Basket switcher;
- display positioning across the user's physical displays.

The current app process was left running rather than disrupted merely for simulated UI evidence.

## Intentional divergences / future work

- DynamicIsland preserves its typed ownership ledger and background-operation routing rather than adopting weaker source-reference state.
- No fake persistence was added to Basket contents.
- No unrelated later roadmap phase was started.
- No new entitlement, Quickshare/cloud upload or external transmission authority was introduced.

## Git boundary

No push.
No merge.
No rebase.
No PR-state change.
