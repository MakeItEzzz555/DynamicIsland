# Native customizable workspace checkpoint

Baseline: `3189b4472790240d4908902ee8348ff0f0a44b49`, branch `feature/agents-ui-overhaul-continuation`, draft PR #24. This phase keeps the collapsed/expanded shell and existing feature controllers.

## Product boundary

Customize workspace enters a transient edit transaction on Media/Island or Agents. The header context menu opens Customize tabs and Reset to Default Layout. Done normalizes and saves; Cancel, leaving the page, or collapsing discards unfinished edits. Boundaries, native drag handles, removal controls and a compact palette exist only during editing. An invalid outside drop restores the prior valid placement. This phase has no detached windows and no implicit cross-window movement. The model can express supported cross-surface moves, but the current editor offers targets within its visible host.

## One model, independent configuration

`WorkspaceConfiguration` schema 2 contains stable `WidgetID`, kind, surface, order, visibility, composition groups, navigation order/visibility, customized hosts and the usage-widget migration. It persists JSON through `WorkspaceCustomizationStore`; safe decoding, legacy CSV migration, normalization, duplicate/unknown item handling and defaults keep corrupt preferences recoverable. Chat and the primary home surface remain available. Widget visibility never depends on a standalone tab's visibility: hiding Timer's tab leaves Timer placements intact. Existing global feature/settings availability still gates the palette and navigation.

The editor adopts the existing `IslandWidgetLayout` / `IslandWidgetEditor` files. It does not add a competing engine. Legacy uncustomized surfaces retain their established layout until editing is committed. Surface reset preserves navigation and other hosts; the header's full reset restores all defaults.

## Editing and motion

Native AppKit `NSDraggingSource` handles carry a private widget UTType and a lightweight label proxy. The real controllers stay outside placement. Measured slots freeze at drag start, midpoint insertion and hysteresis resolve targets, and the shared pure resolver computes previews. Drag state and draft layout stay local; pointer movement writes no preferences. Done commits one normalized layout. A palette singleton already present is disabled.

Motion translates transitions.dev card reorder, resize, panel reveal and sliding tabs into 250 ms smooth-out rearrangement and 300 ms edit resize. Reduce Motion removes spatial choreography. Menus, Add/Remove buttons, Move Left/Right, Combine with Chat and Separate from Stack offer alternatives to dragging. VoiceOver receives committed-result announcements; hover does not announce continuously.

## Agents composition and lifetime

Dropping Terminal into the Chat center combines them; insertion beside is a separate highlighted target. Terminal's stack handle can separate it into another valid slot. Chat and Terminal share one region with accessible selectors and horizontal trackpad swipes starting in the stack header. That region avoids stealing transcript vertical scrolling, text selection, composer typing or terminal mouse/keyboard input. Momentum cannot initiate a new page change.

The retained Chat page preserves its editor while swiping. Existing exact-session draft and measured transcript viewport stores handle actual remounts. Terminal mounts its expensive native renderer only when visible, while the existing controller retains the same PTY/process and terminal model. Removing Terminal changes presentation, not process lifetime. Media and Timer widgets receive the existing app-owned controllers. Hidden Chat pauses decorative avatar/Metal activity. Cross-agent approval attention remains reachable, and explicitly opening an approval's Feed restores that destination when hidden.

## Runtime audit disposition

- H1: removed Return/default-action and Escape/cancel-action bindings from approval decisions. Return never grants permission; actual button actions retain the exact existing pipeline.
- M2: replacing/restarting a terminal detaches the retired renderer and its input callback before attaching the live one.
- P1: unchanged retained approval policies emit no publication.
- M3: notch glow pauses and uses a static phase under Reduce Motion.
- M4: history restoration uses measured stable row geometry plus the saved within-row position; late lazy realization corrects the same reading anchor. Missing rows fall back safely.
- N1: panel reposition observes relevant permission geometry signatures and coalesces unchanged attention updates.
- N2: unresolved compact decisions expose Open Feed; failed decisions also permit safe dismissal without manufacturing acknowledgement.
- N3: pending permission selection follows deterministic arrival order, keeping the delivering request stable until acknowledgement.

P1/M2/N3 were reproduced against the baseline with failing focused regressions. Other findings were confirmed by source inspection and tested after integration; they are not claimed as executed pre-fix reproductions. Exact provider/native session/generation/request ownership, one-shot decisions and provider acknowledgement semantics remain in the original approval controller.

## Claude pass audit and adaptive sizing

The continuation audit starts at `d8a751b4cc87b738ee7776dc7a1802033bf3fc2d` and examines both Claude commits `dc0e019` and `d8a751b`. The underlying schema, native edit-only drag proxy, approval fixes and controller ownership are retained.

The usage row previously allowed its GeometryReader to consume spare vertical height. Its fixed intrinsic 66/58-point row keeps the existing 48/40-point gauges and gives the recovered height to the workspace. Customized Chat now uses its actual region height.

The existing presentation profile and notch geometry service now consume the shared widget projection. Required width and height follow visible composition, persisted Compact/Standard/Large sizes, row packing, palette chrome and navigation header requirements. One widget uses its intrinsic centered bounds. Multiple rows grow the shell within the display budget; vertical scrolling occurs only on actual overflow. Optional placement size decodes to Standard for old or unknown values, preserving schema-1 compatibility. Feature availability uses the same filter for sizing and Media's palette. Navigation visibility stays independent.

Customized Media now participates in the same child transition as the original page. Configuration handoff retains the editor/controller tree, acknowledges child removal, commits geometry through the existing panel/canvas morph, then reveals children. Rapid requests update an outstanding exit target instead of falsely completing another exit. Layout preview clearing is surface-owned. Collapse now waits for the actual SwiftUI removal-animation acknowledgement rather than a timer started before the view update. Committed geometry remains fixed while children exit, including when the editor clears its draft preview. Stale/duplicate acknowledgements cannot commit another collapse. No new shell state or additional clipping is introduced. Shell completion, rather than a separate root delay, owns expansion reveal.

History hydration now enforces its actual 2 MiB read bound, exact session filtering, stable fallback IDs, duplicate suppression and both date formats. Transcript realization retries are bounded native-layout events rather than a 16 ms polling loop. BorderBeam's layout, update and delegate draw entry points all reject hidden/occluded surfaces before drawable acquisition; successful submission owns first-frame size readiness.

## Timer ruler integration

Claude's monotonic `TimerTimingSnapshot` and existing app-owned TimerController are retained. The ruler defaults to individual seconds at 9 points per second, with stronger 5/15/60-second ticks and an optional minute zoom. Drag translation uses one captured origin; preferences persist exact seconds at commit, migrating existing minute preferences. Countdown and pause/resume position still derive from the same controller clock. Moving/hiding a widget does not create another timer.

Horizontal ruler drag/wheel ownership is isolated from shell navigation. Named-canvas native control regions are presentation-local and owner-scoped; edit mode disables ruler interaction, including its local wheel monitor. Monitor teardown removes the token and callbacks, and momentum cannot initiate another shell action. Arrow keys and accessibility adjustment select the active tick resolution.

One public `NSHapticFeedbackManager` alignment event is requested per crossed tick, including ticks crossed by fast deltas. This uses no audio, extracted assets, private frameworks or dependencies. Physical sensation depends on haptic-capable hardware. Apple references: [alignment](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager/feedbackpattern/alignment), [perform](https://developer.apple.com/documentation/appkit/nshapticfeedbackperformer/perform(_:performancetime:)). Functional countdown motion remains synchronized under Reduce Motion; decorative snapping is removed.

## Evidence and validation

Validation results are recorded at the end of this checkpoint after execution. Native NSHostingView/NSWindow fixtures and real test-owned PTYs are distinct from packaged live acceptance. Provider events in fixtures are deterministic inputs. Performance counters measure CPU/body publications; they are not display FPS or GPU frame pacing evidence.

### Audit validation, 2026-10-05

- Used graphify scoped navigation/AST update, transitions-dev and transitions-polish for native reorder/resize/removal handoff, accessibility-tester for keyboard adjustment/edit actions, performance-engineer for measurement and bounded lifetime checks, and qa-expert for focused-to-full validation.
- Focused regression run: 181 tests, zero failures. Final geometry/native viewport/PTY/crash run: 40 tests, one optional fixture skipped, zero failures, 11.983 seconds. Opt-in production-view snapshots/performance/real-PTY/memory run: five tests, zero failures.
- Final logged full suite: 1,816 tests, 41 optional tests skipped, zero failures, 57.637 seconds (57.854 seconds suite wall time), `/tmp/di-claude-audit/final/full.log`. An initial console-only full run exited 1 without retained failure detail; the next three full runs exited 0. No claim that this intermittent failure was diagnosed.
- Customized Agents: 38 native typed keys produced no surrounding body evaluations/publications. 200 streaming deltas produced four workspace/Feed/editor evaluations and two managed-controller publications. Transcript publications were intentionally local (50). A 500-word native-renderer scenario produced four surrounding evaluations and two managed publications, 301.7 ms main-thread CPU over 691 ms wall time.
- Twenty renderer handoffs preserved the same real PTY. The 110-cycle bounded workload stayed at 63,294,272–63,949,632 bytes (60.3–61.0 MiB) physical footprint and fell to 57,510,720 bytes (54.8 MiB) after teardown; controller release passed. This is a fixture-process workload, not packaged-process RSS or GPU memory.
- Final Release compilation passed (135.46 seconds). Packaging assembled the bundle but signing in synced `dist` failed because FinderInfo reappeared. `ditto --norsrc` clean copy `/tmp/DynamicIsland-claude-audit.app`, re-signed ad-hoc, passed deep strict verification with all three helpers and launched. This is not Developer ID/notarization.
- Actual packaged GUI: inspected Agents usage/workspace placement, pressed Resume and observed the same named session with Session resumed/connection Feed events and responsive controls, and exercised Media edit/remove/cancel. A temporary single-Timer draft changed the physical shell from 867×362 to 427×289 points, then Cancel restored saved layout. One/two/many and narrow layouts also have explicitly labelled native fixtures in `/tmp/di-claude-audit/layouts`.
- Actual installed Codex 0.160.0 metadata audit: 100 discovered sessions; exact read/resume identity passed for a prior harmless test-owned session; no prompts or approval decisions. Low-level RPC latency was not measured.
- Actual packaged Timer mouse input: a guarded current baseline of 90 seconds became 100 after a fast ten-tick drag, then 97 after a slow three-tick drag, then returned to 90. No countdown controller rewrite was required. Physical haptic sensation was not measured.
- Final packaged Media was recorded through collapse after editing and re-expansion, with sampled frames showing the expanded children absent during shell contraction. The first two recording attempts did not capture a full collapse and are not acceptance evidence. A macOS Documents-access prompt appeared in the final recording and was left for the user; no TCC settings or permissions were changed. Final packaged provider resume was not repeated through that prompt; earlier live resume evidence and final regression tests remain separate.
- Remaining acceptance distinctions: physical haptic sensation, display/GPU frame pacing and OS Reduce Motion switching cannot be inferred from static fixtures. Preference-based Reduce Motion and deterministic interaction/lifecycle checks passed.
- The seven unrelated tracked source/test/summary files match their starting SHA-256 hashes. Generated graph files stay unstaged. `/tmp/DynamicIsland-claude-verify` remains because it contains uncommitted work; it is unsafe to delete merely because the main branch now includes related code.

## Spatial reorder, columns, traits and usage widgets (2026-10-05)

Baseline `0c913a3`. See context.md 2026-10-05 for the collapse-deadlock root causes and the Context decision.

- Drag intent: `resolveIntent` keeps the established midpoint insertion for left/right and adds above/below as `.stack` (shared column) inside a hovered compact widget; the previous axis wins inside an 0.18 bias band so the diagonal never flickers. Frames used for hit resolution stay frozen at drag start; the visible cards animate to the previewed configuration, the hovered card shows an interior edge glow, and the shell follows the prospective size (direct animated reposition while editing). Outside drops cancel; drops commit the preview exactly.
- Model: one optional persisted relation, `stacksBelowPrevious`; legacy layouts decode standalone. Leaving a column promotes the widget below.
- Projection: `WidgetLayoutTraits` per kind (preferred/minimum/solo, fillsHeight, stackable). Units (region or column) pack into rows; small stackable neighbors form a column beside a taller anchor; filling widgets take the row height, others stay centered; a sole widget uses its solo footprint. Widgets receive `WorkspaceWidgetPlacementContext`.
- Media solo: full-size controls are composed from the allocated cell; artwork/title stays deliberately left-weighted with a bounded width-derived inset while transport remains centered and sliders span the available width. Timer rows distribute so controls align with row neighbors.
- Usage widgets: Combined, Codex and Claude quota widgets on Agents and Media share `AgentUsageComposition` with the default Agents row.
- Later packaged acceptance closed the remaining visual gates: the exported `app.dynamicisland.workspace-widget` UTType restored pre-release drag-hover delivery; a held palette drag showed the accent target and prospective layout before release while the shell resized; a draft-only single-Media layout contracted the shell and kept its left-weighted composition; Cancel restored the saved layout.


## Final continuation closure, 2026-10-05

Baseline `c21258c94df14cf9c7d98dead5c0434438192c1b`.

### Resume -> Collapse P0

The resumed-session collapse deadlock had two independent causes. First, child exit was keyed to a Boolean edge instead of the exit generation: a resume/provider publication combined with collapse/cancel/collapse could coalesce `true -> true`, so the new generation never owned a real child-exit completion and a stale acknowledgement was rejected. `ExpandedChildExitTracker` now follows `expandedChildExitGeneration`, acknowledges only the current generation from actual visual removal state, and a repeated collapse re-drives a fresh generation. Second, a successfully committed collapse could leave `isExpandedContentExiting` true because cleanup was delayed behind a morph-generation check; a later collapsed live-activity morph superseded that generation and permanently zeroed the collapsed gesture region. The committed island state now owns ending the exit phase through `IslandCollapseRequest.exitPhaseEnds(at:)`; no timer controls correctness.

Packaged stress performed before this continuation already completed 105 cycles across seven collapse/race scenarios with zero stuck shells after reproducing the pre-fix failure at cycles 9 and 2. The freshly rebuilt final package was additionally exercised through the exact user path: expand Agents -> Resume exact Codex session -> observe `Connected · ready for prompt` -> expanded swipe-up -> compact agent activity -> click compact surface -> same session re-expanded. No black expanded shell, dead interaction state or new crash report occurred. Historical 12:48/12:49 `.ips` files predate the final package run.

### Editor / usage / drag runtime

- Fresh packaged Agents edit mode: 867 x 575 pt shell, horizontal palette, centered 396 x 76 pt usage band, 532.5 x 368.5 pt Chat/Terminal region and 265 x 368.5 pt Feed. The layout remains wider than tall.
- Removing the Combined Usage widget in a draft shrank the shell to 867 x 501 pt and made Add Agent Usage available: usage is a normal removable widget and reserves no hidden permanent band. Cancel restored the saved layout.
- `Scripts/package_app.sh` now exports the private `app.dynamicisland.workspace-widget` UTType. This was the runtime cause of missing drag-hover callbacks: the editor could start a native drag, but packaged drop registration never matched before release without the declaration.
- On the final package a held Focus Timer palette drag over Agents showed the blue target outline and `Add Focus Timer` feedback before release. The prospective layout was visible before drop (Chat/Terminal resized, Timer occupied the prospective slot, Feed moved below) and the shell grew to about 867 x 617 pt. Releasing outside cancelled and left Focus Timer available.
- The Terminal-over-Chat combine region is restricted to Chat's center; outer bands retain directional insertion, with hysteresis only around the active target.

### Media / Timer / notch / adaptive sizing runtime

- Saved Media+Timer packaged layout: 751 x 276 pt shell, two 331 x 202 pt cells; the Timer ruler renders its taller hierarchy and live indicator beside Media.
- Draft-only single Media: shell contracted to 523 x 304 pt, Now Playing to 313 x 175.5 pt. Artwork/title remained left-weighted inside the card, transport centered, full-size controls preserved. Cancel restored the exact saved Media+Timer composition.
- Agents and Media headers were inspected through AX geometry on the packaged app. Navigation and utility controls remained outside the hardware-notch exclusion; the header minimum-width invariant also applies on non-customized pages.
- Trait-driven projection remains authoritative for Compact/Standard/Large sizing, rows/columns, solo intrinsic bounds and fill-height behavior. No widget-name sizing conditionals were added to the views.

### Large transcript continuation

The interrupted Claude pass found a resumed large transcript pinning the app near 99% CPU because `NSViewRepresentable.updateNSView` repeatedly received identical text and paid an O(transcript) bridge/prefix comparison each pass. `AgentStreamingTextView` now caches the last applied Swift `String`, and `AgentStreamingTextState.update` exits early on identical content while still processing active/Reduce-Motion state and run expiry. The fast path does not alter message identity or replay resolved text. On the final package, Agents settled to about 6.4-6.5% CPU after transition in the tested resumable session.

### Final validation

- Focused workspace/collapse/drag/Timer/Streaming set: 78 passed, 0 failed.
- Performance/lifecycle selection: 20 executed, 0 failed, 1 gated skip. Shell-only main-thread CPU ~5.9 ms. The 500-word stream kept four surrounding content evaluations, two managed publications and 20 transcript publications; streaming overlay work totaled ~6.75 ms.
- Full suite: **1,860 tests, 0 failures, 41 gated skips**, 54.096 s suite wall time.
- Release build: PASS.
- `Scripts/validate_agent_visual_fidelity.sh release`: PASS. App and all three helpers passed strict/deep signature verification without xattr recovery on the final run.
- Fresh `dist/DynamicIsland.app` launched and was used for the packaged GUI checks above.
- Remaining distinctions: physical Timer haptic sensation, sustained display/GPU frame pacing, packaged long-duration memory soak, and actual macOS Reduce Motion OFF -> ON -> OFF remain NOT VERIFIED. Deterministic Reduce Motion/accessibility/lifecycle tests pass. No TCC/security setting was bypassed.


## Input, collapse and Timer recovery validation (2026-10-05, after 37f72b0)

- Native text inputs in the non-activating island claim key status after a click (`IslandKeyboardFocusPolicy`); only user-engaged text focus holds the island open, so the automatically focused Terminal stack page no longer vetoes pointer-exit collapse.
- Collapse and workspace children-exit acknowledgements use isolated exit clocks; a newer collapse request recovers immediately when children are hidden.
- Timer selection is >= 1 s for every input path and zoom level; pointer and wheel sessions never share a rebased anchor.
- Packaged evidence: typing (Chat/Terminal/switching), 24/24 Terminal-active collapse cycles with the same PTY PID, Timer lower-bound flicks at all three zoom levels and a 1 s countdown completion. See context.md for details.


## Adaptive Agent Chat, Send and Apply validation (2026-10-05, after c684dcf)

- Agent Chat height is content-adaptive between a readable floor and the previous fixed height (`AgentChatHeightPolicy`, `agentChatHeightHint`); long transcripts keep the previous geometry and scroll; the Terminal stack page keeps its native height.
- Apply commits once, ends editing and collapses the island through the normal sequence; Cancel never collapses.
- Packaged: resumable Chat 408 -> 212 pt, Terminal 408 pt, Chat/Terminal round trip stable, long transcript 408 pt; Send by mouse click and by Return; Apply/Cancel cycles. See context.md.

## Semantic widget sizes and compact Media (2026-10-06, after c6cbe6b)

Replaces the 0.85 / 1.0 / 1.15 scale factors and `WidgetLayoutTraits` with Apple-style size classes. Persisted raw values are unchanged (`compact` / `standard` / `large`, schema 2).

- Grid: `WidgetGridMetrics` is the single source. Unit S = 162 pt (Island) or 236 pt (Agents) x `expandedCardScale`; gutter `spacing(8)`. Compact = S x S, Standard = (2S + g) x S, Large = (2S + g) x (2S + g). A host narrower than a Standard shrinks the unit; narrow displays wrap instead of rewriting saved sizes.
- Packing (`WorkspaceWidgetLayoutProjection`): a row-major cursor places each span in user order (no masonry reshuffle). `stacksBelowPrevious` places a region under its anchor, and packing continues beside the anchor so no cells are stranded. Usage widgets are band strips whose size changes density (56 / 72 / 96 pt), not span. Agents keeps at least three columns when they fit.
- Fill: outside editing, a grid narrower than the notch-safe header minimum scales its unit uniformly (capped at 1.5x), so Compact stays square and Standard stays 2:1. `preferredContentSize(minimumWidth:)` uses the same fill, so resolver and projection heights agree. Editing keeps the intrinsic, top-anchored drag geometry.
- Widgets read `\.workspaceWidgetPlacement.presentationSize` and compose a dedicated layout per class. Size never applies `scaleEffect` and never recreates a controller.
- Editor: `WorkspaceWidgetSizeControl` (three glyphs drawn at 1x1 / 2x1 / 2x2, current size filled, VoiceOver "Compact" / "Standard" / "Large"), the context menu and the accessibility actions all change only the draft. Neighbours and the shell preview with the `.smooth` resize spring (none under Reduce Motion); Apply persists; Cancel restores.

Size contracts:

| Widget | Compact (1x1) | Standard (2x1) | Large (2x2) |
| --- | --- | --- | --- |
| Media | Artwork-first square (`MediaCompactLayout`): artwork 45-56% of width centered at the top; title / artist / source; prev / play-pause / next; short scrubbable progress. Content drops by priority (time labels, volume, separate source line folded into the artist line, progress, source, artist) | `MediaStandardLayout`: artwork on the left; title / artist / platform + visualizer centered beside it; transport, then full-width progress (inline times) and volume filling the rest of the rectangle | Larger artwork, two-line title, full metadata, roomier transport, progress with times beneath, volume |
| Timer | Countdown, short ruler, play/pause, reset | Full mode row, ruler, controls | Mode row, prominent countdown, ruler, full control row |
| Chat | Read-only summary (`AgentCompactSessionSummary`): orb, provider, live state, project, latest sanitized activity, approval attention | Transcript and composer, adaptive height | Same, taller cap |
| Terminal | Summary; the PTY stays alive (the view unmounts like the stack's hidden page) | Interactive terminal | Interactive terminal |
| Feed | One row, preferring a pending approval, plus an earlier-event count | Latest 12 rows | Full bounded history |
| Usage | 40 pt rings, 56 pt strip | 48 pt rings, 72 pt strip | 64 pt rings, 96 pt strip |
| Calendar, Files, Clipboard, Shortcuts, Activities, Workspace | Compose into the allocated cell; lists show what fits | Same | Same, more rows |

## P0 recovery validation (2026-10-06, after ec9de5b)

- Edit-entry black shell: geometry liveness now follows the values `@Published` emits (`WorkspaceGeometryLiveness`). Packaged DEBUG build: before, 6/8 black entries with a connected Chat; after, 0/12, and 0/40 stuck or black across Cancel, resize+Apply and Apply collapse cycles.
- Chat composer (packaged, test-owned Codex session): typing, Shift+Return, Send by real mouse click, Return, and typing after Chat<->Terminal, collapse/expand and Edit->Cancel all passed. Typing after Chat Compact->Standard->Large->Standard was not completed (user input interfered); covered by state-retention design (Compact unmounts only the heavy surface).
- Orphan rows are centered at their semantic size; the editor preview equals the committed geometry (`WorkspaceSemanticSizeTests`).
- Camera explicit intent and the Screen Recording request ledger: unit-tested; packaged acceptance needs camera and Screen Recording grants for a build (see context.md).
- Full suite 1,944 / 0 / 41.

## Standard Media and header rhythm (2026-10-06, after ad41566)

- Standard Media is two columns: artwork left, one centered stack right (metadata -> transport -> progress -> volume). Verified on the packaged build through AX geometry.
- Header-to-content dead band reduced from ~17 pt to ~7 pt via the shared `ExpandedIslandLayoutMetrics` and usage strip heights; still notch-safe.
- Full suite 1,946 / 0 / 41.
