# Native customizable workspace checkpoint

Baseline: `3189b4472790240d4908902ee8348ff0f0a44b49`, branch `feature/agents-ui-overhaul-continuation`, draft PR #24. This phase keeps the collapsed/expanded shell and existing feature controllers.

## Product boundary

Customize workspace enters a transient edit transaction on Media/Island or Agents. The header context menu opens Customize tabs and Reset to Default Layout. Done normalizes and saves; Cancel, leaving the page, or collapsing discards unfinished edits. Boundaries, native drag handles, removal controls and a compact palette exist only during editing. An invalid outside drop restores the prior valid placement. This phase has no detached windows and no implicit cross-window movement. The model can express supported cross-surface moves, but the current editor offers targets within its visible host.

## One model, independent configuration

`WorkspaceConfiguration` schema 1 contains stable `WidgetID`, kind, surface, order, visibility, composition groups, navigation order/visibility and customized hosts. It persists JSON through `WorkspaceCustomizationStore`; safe decoding, legacy CSV migration, normalization, duplicate/unknown item handling and defaults keep corrupt preferences recoverable. Chat and the primary home surface remain available. Widget visibility never depends on a standalone tab's visibility: hiding Timer's tab leaves Timer placements intact. Existing global feature/settings availability still gates the palette and navigation.

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

## Timer integration contract

The existing `FocusTimerView` is adopted unchanged as an adapter for the existing Timer API. Timer is eligible in Media and Agents independently of its navigation tab. No changes in this lane touch `Modules/TimerController.swift` or introduce Claude-owned TimerRuler files. Taller ticks and continuous synchronized ruler movement await Claude's isolated commit.

When that SHA is available: inspect its diff and ownership, review Timer lifecycle/monotonic-time/Reduce Motion changes, cherry-pick the focused commit onto this feature branch, resolve only the adapter registration in `ExpandedIslandView.islandWidget` and the supplied Agents `timerWidget`, passing the same `modules.timer`; run Timer tests and customization/process regressions, then Release/package/sign/launch validation. Do not merge or mark PR #24 ready.

## Evidence and validation

Validation results are recorded at the end of this checkpoint after execution. Native NSHostingView/NSWindow fixtures and real test-owned PTYs are distinct from packaged live acceptance. Provider events in fixtures are deterministic inputs. Performance counters measure CPU/body publications; they are not display FPS or GPU frame pacing evidence.
