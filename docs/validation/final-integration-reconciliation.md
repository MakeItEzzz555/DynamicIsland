# Final integration source reconciliation — 2026-10-17

This is a source and preservation receipt. Fresh full-suite, package, signature, CI and native outcomes belong to the final validation handoff; this document alone does not declare those gates passed.

## Baseline and preservation

Original worktree: `DynamicIsland-main`, branch `feature/camera-hand-navigation`, HEAD `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`. It remains in place with its original index and valuable unfinished work. A verified archive outside the repository captures 71 tracked changes and 438 untracked files, including source/tests/docs and generated data. Initial Git status, binary working/index diffs, file hashes, worktree metadata and archive checks are retained with it. A plain read of one iCloud placeholder returned zero bytes despite a nonzero file size; integration uses the verified populated archive, not an apparent empty read.

GitHub independently confirms PR #43 merged candidate `6d48ac274e1abce73c0e8f3e33d7582d911e6dd4` as `dba6bf175b090a89f89f2f16fe9da15d2ec98e85`; PR #42 is closed without merge. The original `origin/main` is stale at `2ad101e`. Its packed Codex checkpoint reference points at unavailable object `f9eb537de3ed0453b91d5264ea30544266670e0a`, which breaks all-ref traversal. No reference was deleted or repaired. A separate same-repository clone, verified against remote main, avoids that unrelated reference defect.

Integration branch: `review/final-stabilization-20261017` in the isolated `final-stabilization-20261017` worktree. A separate detached baseline reproduces tests against unchanged merged main. No branch switch or destructive operation occurred in the original checkout; TuckBit and the other DynamicIsland evaluation worktree are outside this task.

## Complete changed-file classification

| Original files | Disposition |
|---:|---|
| 73 | Preserved working bytes already identical to merged main |
| 13 | Three-way comparison resolves byte-for-byte to merged main |
| 28 | Explicitly reviewed older variants superseded by connected newer main implementation/tests |
| 395 | Generated/history/research/browser artifacts retained in original checkout and backup, excluded from delivery |

The 28 decisions were reviewed against actual callers, not feature names. They preserve modern keyboard acquisition and native menu ownership, one Metal-owned Send glow, orbit-specific accessory geometry, protected sidecar hover, repeated popup fitting, operation status, per-app Clipboard filtering/native sharing, audio teardown, experimental Lock Screen gating and all 220 audited settings. Older variants would restore retired double-click/notch-choice controls, duplicate an existing `onClick` argument, add a disconnected persistent Tray bar, remove stronger IME/key/popup tests, or replace current Lock Screen UI with an obsolete unavailable/demo page. Every original variant remains recoverable. No source/test change was discarded from the original worktree.

## Confirmed repairs

- **Agents draft ownership:** On accepted asynchronous Send, the old composer unconditionally cleared the exact session's cache, even after a replacement composer saved a newer draft. Two hosted native regressions failed on main (four assertions); unchanged acceptance and rejection controls passed. Clear the cache only when it still equals the submitted original draft. Interfaces, transports and approval ownership are unchanged.
- **Live Audio privacy:** Sleep/wake, session activity and screen unlock shared one Boolean. Wake could overwrite an inactive/locked condition. A pending visualizer swap grace also deferred privacy suspension. Separate those gates, require explicit unlock after observed sleep/session loss, bypass visibility grace for consent/privacy/playback suspension, and prevent an explicit enable from starting capture while locked. Tests use an injected backend and process-local notifications, never actual capture or distributed lock events.
- **Deferred artwork launch:** Queued unlock handlers could execute after a newer lock/uncertain state and launch the captured source. Invalidate stale state deliveries, cancel requests synchronously on replacement unsafe states, hide/redact immediately on uncertainty, and invalidate pending deliveries at termination. Keep the post-`@Published` hop because publication precedes assignment. Experimental opt-in, source identity, timeout, private SkyLight safety and preview actions remain intact.

The four privacy regressions failed six assertions on unchanged production source. The first repaired connected module run passed 21 tests; additional sleep/enable negatives are included in the final source. An expanded 270-case check had 267 passes, two optional skips and one native Settings environment failure: app/key-window activation was declined after earlier native fixtures. The exact unchanged Settings assertion passed alone in a fresh process. Existing CI already requires that same fresh-process step; its assertion is neither weakened nor converted to a skip.

## Merged-main CI failure investigation

Run [38878879396](https://github.com/MakeItEzzz555/DynamicIsland/actions/runs/38878879396) failed in `testA9RelocationPrefersExistingDatabaseOverAnObsoleteParentDirectory`: fixture INSERT returned SQLite status 10 rather than 101 (`extended=3850`, disk I/O error, `errno=9`), followed by the missing-row timeout. It was one failed case with two reported assertions in the 2,686-case bulk step; the subsequent fresh Settings step was not reached.

Unchanged merged-main local evidence: the exact case passed; all 21 resilience cases passed; a separate diagnostic repeated the exact relocation scenario 100 times in one process and passed. That temporary diagnostic exists only in the detached baseline, not the delivery diff. The failure's root cause is **not established**. No production patch, timeout relaxation, retry-on-error, assertion weakening or new skip was invented for it. Final-head CI remains an independent required gate, and a passing rerun cannot prove an intermittent cause fixed.

## Review and acceptance boundaries

Three bounded reviews covered Settings reconciliation; keyboard/navigation/camera ownership; and Cycle 1 archive, promised-file, sharing, audio and Lock Screen boundaries. Two reviewers later hit provider allowance limits; final implementation integration/review and verification are performed by the primary Codex agent. Do not infer their approval of the later exact diff.

Existing archive traversal/symlink/staging/cancellation, promised-file ownership, native sharing lifetime, retained per-app audio and Window Snap tests are retained. Review found no additional reproduced defect in those scopes. No new notification/meeting production wiring, permission schema, external host, library, roadmap wave or broad UI rewrite is included.

Native validation must distinguish source/model tests, hosted AppKit fixtures, isolated packaged fixtures and physical production acceptance. Inert acceptance entry points run before ordinary services. Preserve the currently running/installed app and `rc-6d48ac2` package. Never reset TCC, approve prompts, lock the desktop, start live media/calls/camera, or terminate another instance for this check. A rendered fixture is not proof of physical IME, webcam gestures, password focus, real banners/audio, promised Finder drags, multi-display placement or pixel-level collapse timing.

Use the existing Debug/Release/package workflow with an isolated output directory, strict app/helper signatures and ZIP integrity. Run required GitHub CI only on the reviewed exact pushed branch. No merge, public release or installation is authorized by validation.
