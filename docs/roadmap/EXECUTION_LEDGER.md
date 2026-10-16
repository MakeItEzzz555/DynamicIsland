# DynamicIsland roadmap execution ledger

Single source of truth for roadmap status. Statuses are judged from source and
tests, not documents: DONE = implemented + tests; PARTIAL; NOT STARTED;
BLOCKED (external: hardware, permission, user approval); SUPERSEDED (later
decision cited). "Physical" = needs the user's Mac, hands or ears.

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

| Area | DONE | PARTIAL / NOT STARTED (code-only) | BLOCKED |
|---|---|---|---|
| P0 stability (agents, layout, media, Lock Screen) | Send first visit, orb identity, slider/tab, wing icons, Lock Screen privacy, desktop media restore, per-app gain (code) | — | Physical checks above |
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
| Capability advertised-actions gate + self-contained notch-menu test | Claude | roadmap-cycle-1 @ f9a01f5 | DONE (code) | 40 focused tests x3; mutation: old code fails 3 assertions | Codex (pending) |
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
