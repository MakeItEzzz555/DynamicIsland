# DynamicIsland roadmap execution ledger

Single source of truth for roadmap status. Statuses are judged from source and
tests, not documents. DONE requires the acceptance criteria, independent review
and required validation; code existence alone is insufficient. ACTIVE includes
partially implemented or unreviewed work. NOT STARTED means no implementation.
BLOCKED requires a concrete external dependency. Superseded items retain a cited
later decision. "Physical" means the user's Mac, hands or ears. The area matrix
below inventories code evidence; it does not declare every area DONE.

Canonical plan: `research/DROPPY_PARITY_MASTER_PLAN_2026-09-29.md` (its gap
matrix is out of date; this ledger supersedes it).

## Baseline (2026-10-16)

- Release candidate: `6a6c53d` on `fix/complete-integration-acceptance-20261015`
  (PR #42, open, not merged). Claude and Codex independently approved this
  exact SHA (Codex response recorded in the cycle-0 review). GitHub CI run
  38807432765: 2,629 tests, 45 skipped, 0 failures.
- Cycle integration branch: `integration/roadmap-cycle-1` (worktree
  `~/DynamicIsland-worktrees/roadmap-cycle-1`), based on `6a6c53d`.
- Main checkout `~/Documents/DynamicIsland` (on `main`, 843 dirty files,
  5 prunable worktree records) is user/agent-owned and untouched.
- Settings v3 files are Codex-owned; Claude does not edit them.

## Release / physical gates (all PENDING, user-controlled)

| Gate | Status |
|---|---|
| Six physical checks for PR #42 (hover orb, desktop + Lock Screen media, artwork-after-unlock, slider vs tabs, first-visit Send, Lock Screen controls) | PENDING (user) |
| Orb fix with a real Claude permission prompt | PENDING (user) |
| Per-app volume by ear (two apps, Boom route) | PENDING (user) |
| Full local suite with the session unlocked (locked screen breaks window-activation tests) | PENDING (needs unlocked Mac) |
| App replacement, merge, release | PENDING (explicit approval) |
| Notarization | BLOCKED (Developer ID credentials) |

## Approvals needed (BLOCKED until the user decides)

- General notification HUD production wiring (branch
  `feature/notifications-meeting-v5-nextphase-20261015` @ 4945b08, bridge +
  tests ready; default-off prefs + allow-list).
- Settings v3.4 schema keys (Codex lane): Shelf open-after-drop, Shelf/Basket
  sync, shortcut bindings. Global shortcuts for Window Snap/Terminal/Voice/
  capture depend on this.
- Quickshare upload host/privacy policy.
- Lyrics source/license (LRCLIB).
- Calendar hardened-runtime entitlement for Developer ID builds.
- Codex dual-orchestrator run halted at `blocked_requires_human` (Settings
  lanes in `dual-claude` / `dual-codex`, uncommitted, preserved).

## Status by area (from cycle-1 audits at 6a6c53d)

| Area | Implemented code evidence | Remaining code work | External gates |
|---|---|---|---|
| P0 stability (agents, layout, media, Lock Screen) | Send first visit, orb identity, slider/tab, wing icons, Lock Screen privacy, desktop media restore, per-app gain | Retained audio teardown/re-enable and disable-error follow-up (Codex candidate below) | Physical checks above |
| P1 System HUD | volume/mute/brightness/coalesce, caps/battery/focus/output device, toggles, preview | HUD style choice; mic/camera in-use indicator | keyboard backlight; external-display brightness (DDC); AirPods battery |
| P2 Capture | screen recording (display/window/area, audio, pause, writer-confirmed stop) | screenshots; annotation editor; post-capture Copy/Add to Shelf/Share; countdown; destination | mic path (TCC not granted) |
| P3 File Shelf | drop/promises/persistence, multi-select, folders, Quick Look, rename, OCR, AirDrop/share, tray 2x2 drop zones | **drag orbit view (model ready on `roadmap/w1-drag-orbit-actions` 7216a4c, no view)**; web URLs; keyboard arrows; pinned/watched/details; delete-to-Trash | — |
| P4 Conversion | operation center (ZIP), image + audio formats | extraction kind; conversions as operations (wave 1 W2); resize/quality/metadata; video (AVAssetExportSession) | WebP output (platform) |
| P5 Basket | full feature set | keyboard basket switcher | physical drag acceptance |
| P6 Clipboard | history/search/tags/favorites/exclusions/persistence | source-app filter, color, share, add text/image to tray (wave 1 W3); link/PDF/video previews | paste into front app (Accessibility) |
| P7 Settings | sandboxed live previews | Settings v3 (Codex) | v3.4 schema approval |
| P8 Extensions | capability registry, 8 adapters | **advertised-actions gate (fixed f9a01f5)**; adapters for Music/Spotify/Messages/Calendar/agents; detail page; Finder Services + URL route | persistence of enable state (schema) |
| P9 Productivity | Window Snap, Keep Awake, Terminal, Voice, Background Removal, Camera | Keep Awake schedules; Voice share; external terminal choice; move-to-next-display | hotkeys (schema); Menu Bar Manager (deferred by plan) |
| P10 Live activities | power, reminders, timer, recording, file ops, agents, collision tests | meeting "starts soon" activity; mic/camera in-use; downloads | AirPods battery; downloads folder permission |
| P11 Messaging | Messages adapter, authority, drafts, FDA onboarding | real app icon, exact conversation open, WhatsApp/Telegram open-only | general HUD wiring (approval) |
| P12 Media | arbitration, controls, favorite/shuffle/repeat, visualizer, Lock Screen panel | AirPods-vs-media rule | lyrics (license) |
| P13 Personalization | widget editor, default compact activity | side placement beyond timer; per-display rules | — |
| P14 Polish | packaging/signing, snapshots, Reduce Motion coverage | first-launch permission onboarding; idle CPU budget measurement | notarization; VoiceOver/Spaces physical matrix |

## Cycle log

### Cycle 1 (2026-10-16)

| Item | Owner | Worktree / SHA | Status | Evidence | Reviewer |
|---|---|---|---|---|---|
| Capability advertised-actions gate + self-contained notch-menu test | Claude | roadmap-cycle-1 @ f9a01f5 | ACTIVE (independent review pending) | 40 focused tests x3; mutation: old code fails 3 assertions | Codex (pending) |
| Drag orbit: Add to Basket / Compress model + wiring | worker W1 | roadmap/w1-drag-orbit-actions @ 7216a4c | HELD (no view yet) | 101 focused x3 | — |
| Extraction + conversion as background operations | worker W2 | roadmap/w1-operation-center-kinds | ACTIVE | — | Codex (pending) |
| Clipboard 2.0 gaps | worker W3 | roadmap/w1-clipboard-2 | ACTIVE | — | Codex (pending) |

## Continuation

1. Collect W2/W3, review, merge into `integration/roadmap-cycle-1`.
2. Codex review of the integrated SHA via `codex exec -s read-only` (stdin
   closed: `< /dev/null`); record its verdict here.
3. Wave 2 candidates: drag orbit view (on 7216a4c), screenshot capture +
   post-capture actions, mic/camera in-use indicator or meeting activity,
   image resize/quality options, Messages real icon + exact conversation.


### Codex takeover checkpoint (2026-10-16)

The actual interactive Claude session reported its weekly limit at
`2026-10-16T06:04:22.908Z`, with reset October 18 at 21:00 Asia/Nicosia.
Codex is now the primary integration owner under the user's earlier explicit
instruction to continue when Claude is unavailable. This changes scheduling,
not the final joint-review gate. No final Claude approval may be inferred.

Current integrated SHA: `eaea1e508cebe17a85a49e60daef90df208d1500` on
`integration/roadmap-cycle-1`.

- W2 extraction/conversion: `19cba51`, merged at `614fb3d`; security correction
  `33b55ad` uses the same parser for ZIP validation/extraction, checks resolved
  symlink chains and normalizes comparisons. Independent review is ACTIVE.
- W3 Clipboard additions: `83d7d29`, merged at `7a81eaf`; native sharing
  ownership/picker lifetime needs independent review before acceptance.
- W1 model/services: `7216a4c`, merged at `eaea1e5` with an automatic merge of
  the distinct BasketPresenter methods. The native orbit remains ACTIVE and
  is explicitly assigned below; backend tests do not close its acceptance.
- GitHub baseline CI was verified directly: run `38807432765` at `6a6c53d`
  runs 2,629 tests (45 skips, zero failures), plus the unchanged Settings
  pointer case in a fresh process (one pass). Release/package/signatures pass.
  These results do not validate the newer wave.
- PR #42 was restored to Draft per the user's explicit gate. Verified OPEN,
  `isDraft=true`, unchanged head `6a6c53d`. No source push or merge into main.

#### Single task ownership registry

| Packet / acceptance | Owner | Allowed paths / worktree | Status / dependencies |
|---|---|---|---|
| Integration, ledger, final suites/package, checkpoints | Root Codex | `roadmap-cycle-1`; `docs/roadmap/EXECUTION_LEDGER.md`, `docs/agentic/` | ACTIVE; source integration after focused validation/review |
| Audio retained teardown: no same-app replacement over owned resources; retry unity; truthful disable errors; preserve working renderer updates | Root Codex | `/private/tmp/DynamicIsland-orb-identity-20261015`; `Audio/ApplicationGainEngine.swift`, `Audio/ApplicationAudioDiscovery.swift`, `ApplicationGainEngineTests.swift` | ACTIVE; candidate `1997c9f` plus low-finding correction, final review pending |
| Move to next display: native menu, cyclic display selection, size/visible-bounds preservation and permission failure | Root Codex | Same isolated worktree; `Modules/WindowSnapController.swift`, `Views/ProductivityDeckView.swift`, `WindowSnapControllerTests.swift` | ACTIVE; three regressions pass; physical multi-display check pending |
| Wave-1 security/clipboard/capability independent review | Codex `release_review` | Read-only exact `33b55ad`; no edits/builds/apps | ACTIVE; returns concrete findings and exact-SHA verdict |
| Native reachable drag orbit with one drop/action, unavailable targets omitted, native accessory/bridge ownership, Reduce Motion | Codex `native_drag_orbit` | `/private/tmp/DynamicIsland-native-drag-orbit-20261016`, base `eaea1e5`; new orbit view, `IslandRootView.swift`, focused tests; LayoutStore only if justified | ACTIVE; no Audio/Clipboard/WindowSnap/operation edits |

No extra worker was started for the retained stale `codex app-server --stdio`
process: it is an idle application server, not an active roadmap worker.
Two Codex workers are currently assigned; no competing full suite is running.
Every writing worker uses an isolated worktree. Root alone integrates.

#### Actual review responses and evidence

A separate actual Claude CLI reviewer, session
`e066b2c7-03f3-4a70-96e0-42e6ff99acde`, returned **code APPROVE, release not
approved** for `1997c9f`, including `091ff6d`. This is not acknowledgement by
the unavailable interactive Claude primary and does not cover later commits.
Response: `/private/tmp/dynamicisland-claude-audio-review.json`.

Its one low-severity finding is being corrected: existing same-process gain
updates allocate no HAL objects and should remain usable despite an older
retained tap. The new regression failed before correction. The engine's two
original regressions failed six assertions before the engine patch; the caller
regression failed two before the disable-error patch. The final connected
Audio + WindowSnap + Productivity filter currently passes **62 tests, zero
skips/failures**. Log: `/private/tmp/dynamicisland-audio-display-final-focused.log`.
An earlier optional workspace screenshot case was skipped because its output
environment variable was absent; it is not counted as native acceptance.

#### Next executable tasks

1. Commit the focused audio review correction and next-display implementation;
   independently review exact SHAs and integrate without overwriting `f9a01f5`.
2. Resolve confirmed wave-1 review findings, especially native clipboard sharing
   ownership and archive containment, with targeted regressions.
3. Integrate the native drag orbit after code and native-fixture review.
4. Advance remaining code-only items from the area matrix in isolated waves.
   Preserve the user's approval boundaries on schema keys, external hosts and
   notification production wiring; do not mark a proposed candidate approved.
5. After the assembled cycle has no unresolved high/critical findings, run one
   isolated full suite and the existing strict native pointer case, then Release
   packaging/signatures on the exact final SHA. Record actual failures/skips.
6. Final Claude review remains BLOCKED by the recorded weekly quota; physical
   checks, Developer ID and release actions retain their explicit gates.
