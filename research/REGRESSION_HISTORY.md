# Meaningful regression history

> Prepared 2026-09-19. Verified checkout: `df2bd0c29d06e8a01ec974459a118b232c8e22bc`, branch `phase-13c1-correctness-hotfix`. Local `origin/main` is `fbd1778ec025d9fa46d5f5f4f85c609b8375681b`; its Sources/, Tests/, Package.swift and Scripts/ match this HEAD. Only README differs (three removed lines). No checkout, pull or production edits were performed. `context.md` was already modified; historical evidence below includes that working-tree document. Source claims were checked in unchanged HEAD source. Recheck these summaries after implementation changes.

Historical assertions below are attributed to context.md phase headings; current enforcement was checked separately. Context includes implementation reports and unperformed manual matrices, not a guarantee of observed UI success. Git corroborates milestone changes; many intermediate experiments are context-only, so no individual commit is asserted for them.

## Stable panel and click-through — 6A/6B, 6B.2

- **Problem/symptoms:** split visual/hit/interactive surfaces complicated handoff; adaptive physical panel resizing changed local origin/pivot; transparent host areas blocked underlying clicks.
- **Failed/insufficient approaches:** animated coordinate rebasing and resizing; view-level hitTest alone did not provide complete window click-through.
- **Root cause:** visual surface coordinates and native window input bounds had different owners/lifetimes.
- **Stable solution:** one stable host panel, panel-local surface frames, SwiftUI visual morph plus window mouse passthrough and hosting hit gate.
- **Files:** OverlayWindowController, IslandLayoutStore, IslandRootView. Git `0166c86` / `e2f5609` single-panel milestones.
- **Do not reintroduce:** split hit panels, normal-morph physical resize, hidden input canvas.

## Spaces compensation experiments — 11C.3–11C.11, 12B

- **Problem/symptoms:** overlay persistence/motion during desktop/fullscreen Space transitions motivated native membership and manual correction experiments.
- **Failed/insufficient approaches:** WindowServer polling, counter-translation, predictive resampling, sample-and-hold locking, probe/render panels and display links. Context does not establish a unique universal root cause or a manually proven A/B winner.
- **Root cause/evidence:** competing motion/render/lifecycle owners introduced substantial complexity; historical matrices remained unperformed by Codex.
- **Stable solution:** native `.statusBar` + fullScreenAuxiliary/canJoinAllSpaces/ignoresCycle; 12B deleted compensation machinery and canJoinAllApplications experiment. Git `16c2d69`, `daf74ff`.
- **Files:** OverlayWindowController; deleted SpaceTransitionCompensationMath is not current code.
- **Do not reintroduce:** compensation systems or old flags from history as though still active; native behavior still requires manual Spaces verification.

## Shadow/shoulder second silhouette — 12B.1, 12C

- **Problem/symptoms:** shell shadow appeared as an unwanted translucent second layer/ghost corners; decorative ellipse/blob wings complicated notch integration.
- **Failed/insufficient approaches:** earlier shoulder assets, ellipse tuning, inward cuts and separate positioning.
- **Root cause:** separate decorative silhouette/shadow did not track the intended single integrated shell.
- **Stable solution:** shadowless panel/shell and one continuous symmetric animatable IslandShellShape. Old NotchShoulderBlend file/settings/assets removed. Git `daf74ff`, `b18fce0`.
- **Files:** IslandRootView, IslandThemeBackground, panel configure.
- **Do not reintroduce:** shadow around the shell or historical shoulder layer architecture.

## Notch core / collapsed activity width — 10B, 12C.1–6

- **Problem/symptoms:** compact timer/media/battery/file layout could misalign or put content beneath hardware notch; later content-aware left/right widths were visually unbalanced.
- **Failed/insufficient approaches:** generic compact padding/width and successive approximate timer/notch rail layouts; old heuristics were superseded.
- **Root cause:** geometry and rendered content did not share the physical notch exclusion and activity width model.
- **Stable solution:** actual centered empty notch core, shared activity-specific profile, equal wings using larger side requirement, 5pt leading padding and 4pt safety; media visualizer 27pt. Git `cd74a4b`, `b18fce0`, `4d888ba`.
- **Files:** NotchGeometryService, IslandLayoutStore, compact rendering in IslandRootView.
- **Do not reintroduce:** independent view width heuristics, body content under notch, asymmetric active wings.

## Hidden mounted secondary preview — 10B.2, 10C

- **Problem/symptoms:** hidden preview row could remain mounted and affect regular collapsed size/hit behavior.
- **Failed/insufficient approaches:** opacity/visibility treatment without removing inactive row from layout.
- **Root cause:** logical preview inactivity did not match tree lifetime.
- **Stable solution:** select one regular winner; conditional preview content/row only when hover preview active. Git `c59e5c7`, `cd74a4b`.
- **Files:** CollapsedLiveActivitySelector, CollapsedPreviewContent.mounted, CompactIslandView.
- **Do not reintroduce:** an opacity-zero secondary row in regular collapsed tree.

## Shell/content ghosting and tab handoff — 6B.3–5, 12A–12A.2

- **Problem/symptoms:** visible content at the wrong shell phase, duplicated reveal schedules and tab page overlap/flicker.
- **Failed/insufficient approaches:** nested mount/reveal delays, secondary overall presentation timer, ghost handoff layer; earlier timing ratios are obsolete.
- **Root cause:** independent shell/content/tab timing ownership and stale delayed callbacks.
- **Stable solution:** root owns overall contentVisible; mount hidden, derive timing from shared shell duration, preserve mandatory opacity gate. Tabs own displayed/pending page with generation guard and 0.12/0.01/0.14s handoff. 12B removes ghost layer.
- **Files:** IslandRootView, ExpandedIslandView, IslandContentTransitionTiming, controller requestCollapseWithSequencing.
- **Do not reintroduce:** second overall reveal timer or replace current ratios with old strict sequencing assumptions.

## Double media command / expansion tail — 8C.3–15

- **Problem/symptoms:** long/strong physical swipes or momentum produced duplicate next/previous commands; downward expansion tail could immediately trigger collapse.
- **Failed/insufficient approaches:** SwiftUI-only trackpad detection, threshold-immediate dispatch, early one-shot resets and lockout-only attempts; 8C.13 repair was reverted.
- **Root cause:** native scroll stream had multiple paths and tail/session lifetime exceeded immediate-threshold handling.
- **Stable solution:** shared end-of-swipe accumulation, reset before issuing one command, quiet finish and post-command lock, separate immediate downward expansion, expanded recent-expansion tail guard. Git `de337d3` milestone.
- **Files:** OverlayWindowController swipe/reset/finish functions.
- **Do not reintroduce:** threshold command inside every event path. Current lockout is 0.60s despite context header's 0.05s; do not silently retune.

## Paused media instability / stale async enrichment — 3.1–3.4

- **Problem/symptoms:** paused Spotify/Music alternated with paused browser fallback; late YouTube/artwork results could overwrite selected source.
- **Failed/insufficient approaches:** fixed provider preference and metadata-enrichment-based selection; a single missed native poll still caused a paused switch after initial arbitration repair.
- **Root cause:** selection identity, publication generation and delayed enrichment were not consistently tied together.
- **Stable solution:** playing wins; preserve valid current paused identity; two-poll/0.35s paused switch gate; async updates require matching identity and generation.
- **Files:** MediaController, MediaArbitrator, MediaPausedSwitchGate, MediaPublishGuard, YouTubeMetadataProvider.
- **Do not reintroduce:** async callbacks selecting sources or generation-free assignment. Historical 'atomic publishing' is a design claim, not proof all Published notifications are one transaction.

## Artwork early handoff / independent state — 8C.15, 13A.1

- **Problem/symptoms:** cover or visualizer color changed before flip midpoint; remount/alternate ViewThatFits instance could reveal raw incoming artwork.
- **Failed/insufficient approaches:** early key-driven swap, view-owned displayed/pending state, raw artwork fallback and force assignment during active flip.
- **Root cause:** raw detection and visible presentation were coupled; multiple artwork views had independent lifetime/state.
- **Stable solution:** one controller-owned coordinator and pure reducer, old snapshot frozen for 0.19s first half, transaction at ±90° midpoint, latest update queued, generation-guarded callbacks, accents derived from presented image. Git `0a56ae3`.
- **Files:** MediaController artwork state/coordinator, ModuleViews.FlippingAlbumArtworkView, compact/expanded accent consumers.
- **Do not reintroduce:** local presented state, raw image fallback, request consumption at each view startup.

## Clipboard duplicate tick / approximate transition — 13B.2

- **Problem/symptoms:** duplicate copied indicator shifted row content; approximate Clipboard animation disagreed with Island lifecycle.
- **Failed/insufficient approaches:** separate trailing success label and Clipboard-specific asymmetric transition/modifier.
- **Root cause:** duplicated feedback presentation and separate timing/animation implementation.
- **Stable solution:** one fixed copy-button checkmark and generation-guarded feedback; reuse innerBlurScaleClean/shared delay/durations; mounted removal plus 0.025s buffer. Git `1a7a0b6` contains interface milestone, not separate commits for each experiment.
- **Files:** ClipboardHistoryView, ClipboardHistoryPresentationState, ExpandedIslandView.
- **Do not reintroduce:** a second copied tick or a similar-looking independently timed transition.

## Clipboard scrolling blocked by Island input — 13B.2

- **Problem/symptoms:** native rows would not scroll despite ScrollView.
- **Failed/insufficient approaches:** GestureMask, mounted-state callback/global-lock guards, SwiftUI sibling isolation alone.
- **Actual root cause:** ancestor recognizer competed before guarded callback; additionally AppKit local scroll monitor returned nil before SwiftUI and hosting scroll override could avoid super.
- **Stable solution:** sibling overlay outside base gesture subtree plus transient mounted-lifetime AppKit suppression; handlers return false, local event passes through, hosting calls super; clear accumulated expanded deltas on suppression boundaries.
- **Files:** IslandRootView, IslandLayoutStore, OverlayWindowController/IslandHostingView, ClipboardHistoryView.
- **Do not reintroduce:** consume scroll first and attempt to repair with SwiftUI gestures; no event reposting/manual offsets needed.

## Clipboard Escape swallowed before SwiftUI — 13C.1

- **Problem/symptoms:** first Escape collapsed Island instead of closing Clipboard.
- **Failed/insufficient approach:** SwiftUI onExitCommand fallback cannot see a consumed AppKit event.
- **Actual root cause:** existing local key monitor unconditionally consumed expanded Escape and started collapse.
- **Stable solution:** one controller-owned IslandEscapeRouter, mounted presentation registration, deterministic dismissal requests; repeated removal Escape idempotent; collapse only after no presentation registered. Git `df2bd0c`.
- **Files:** State/IslandEscapeRouter, OverlayWindowController local key monitor, ExpandedIslandView lifecycle.
- **Do not reintroduce:** extra key monitor, visibility-only registration, collapse on a second Escape before removal finishes.

## Long scheme-less text misclassified as URL — 13C.1

- **Problem/symptoms:** 20,000-character word was dropped though under text limit.
- **Failed/insufficient approach:** URL(string:) != nil used as sufficient URL classification before 16KiB bound.
- **Actual root cause:** Foundation can construct relative URLs from scheme-less strings.
- **Stable solution:** require scheme/non-file/absolute candidate before URL-size check; others fall through to unchanged 2MiB text path. Git `df2bd0c`.
- **Files:** ClipboardPasteboardClient.readURL/readText and named pasteboard tests.
- **Do not reintroduce:** size-check a generic URL-constructible string before classifying it.

## AppSettings normalization recursion — 7A.1

- **Problem/symptoms:** launch crash after settings expansion.
- **Failed/insufficient approach:** inout clamp helpers reassigned observer-backed property and re-entered didSet.
- **Root cause:** normalization mutation recursively invoked itself.
- **Stable solution:** suppression guard, key-path helpers, explicit normalized saves under normalizeAll.
- **Files:** AppSettings normalization helpers.
- **Do not reintroduce:** observer-triggered normalization without reentrancy guard.
