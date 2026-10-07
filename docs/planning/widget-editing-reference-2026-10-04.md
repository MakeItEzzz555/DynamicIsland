# Product memory: native widget and tab editing

Recorded October 4, 2026 from the user's supplied recording and explicit instructions. Read this reference before planning configurable Media/Agents layouts, navigation tabs, the Chat/Terminal stack, or timer improvements. This is a saved requirement/reference, not an implementation claim.

## Source and preserved evidence

- Original: `/Users/makeiteasy3/Desktop/Screen Recording 2026-10-04 at 10.04.49 PM.mov`.
- Preserved copy: [reference.mov](../../research/visual-references/widget-editing-2026-10-04/reference.mov).
- Reviewed sequence: [sequence.png](../../research/visual-references/widget-editing-2026-10-04/sequence.png), 4 samples/sec in row-major order. Also inspected an 8 samples/sec enlarged crop of the editing surface.
- [Manifest and source checksum](../../research/visual-references/widget-editing-2026-10-04/manifest.json).
- Clip: 3.940167 seconds, 1570×858, 60 fps. Timings below are approximate visual observations, not measured animation durations.

## What the recording actually shows

The reference is an island-shaped black surface on a blue promotional page whose caption reads “Make it yours. Pick your widgets, then drag them where you want.” It demonstrates editing inside the island. The recording does not establish which rendering framework the reference uses.

1. **Edit presentation:** widget bounds have dashed rounded outlines. Each placed widget has a small red circular minus badge near its upper-right corner. A compact icon palette sits below the content, inside the island. Visible entries include File Tray, Weather, Now Playing, a caffeination-style widget, Pomodoro, Calendar and Clipboard; several captions are truncated. Present widgets have small blue checkmarks on their palette icons. At the palette's right are an outlined X button and a filled blue checkmark/Done button. The X affordance is visible, but its cancellation behavior is not exercised.
2. **Add, roughly 0.00–0.25 s:** a floating clock/Pomodoro icon is dragged over the existing Now Playing widget. The layout changes from a single Now Playing surface into two neighboring regions: timer on the left, Now Playing on the right. The timer receives its own dashed outline/remove badge and its palette icon gains the selected checkmark. The existing media controls and content remain recognizable during the animated rearrangement.
3. **Timer appearance, roughly 0.25–1.00 s:** Focus and Break pills; a horizontal ruler with vertical ticks and visible labels 15, 20, 25, 30, 35; a small upward-pointing triangular indicator under the ruler; orange `25:00`; compact play, speaker and timer-style controls. Focus is selected. The clip does not demonstrate a running countdown.
4. **Reorder, roughly 1.00–2.15 s:** the clock drag representation moves across the media region toward its far-right edge. The content animates into the reverse order: Now Playing on the left, timer on the right. It remains two widgets; this is not evidence of creating a second timer. The neighboring widget reflows to make room rather than remaining covered by the dragged representation.
5. **Finish editing, roughly 2.25–2.85 s:** the pointer selects the blue checkmark. Dashed outlines, remove badges and the bottom palette disappear. The island becomes shorter while retaining Now Playing left/timer right. Media playback remains visible.
6. **End of clip, roughly 3.25–3.94 s:** the surface retracts and an album-art image drag representation labeled `Blue Hour.png` appears below it. This is visible image/file dragging; it does not demonstrate tearing a live widget out into a detached window.

Removal affordances are visible; an actual minus-button removal is not shown. Native-feeling animated reflow is the visual target, but neither precise motion constants nor performance numbers can be inferred from this short recording.

## Explicit user requirements for DynamicIsland

### Media and Agents layouts

- Bring this direct widget editing interaction to **both Media and Agents**.
- Users can add available widgets, remove existing widgets, drag widgets out of their placement, and move/reorder them smoothly.
- The editing experience should feel native to macOS and match the reference's live rearrangement, compact picker, clear removal affordances and finished-layout cleanup.
- Timer is an available **editable widget**, not merely a fixed standalone page. It can be added to configurable surfaces, including the Media/Agents editing system.

### Navigation tabs

- Users can add/remove/reorder navigation tabs, with **Timer, Monitoring and Productivity** explicitly named as configurable examples.
- Treat configuring navigation tabs and configuring widgets inside a page as two requested capabilities. Their relationship needs to be made explicit in the upcoming plan; hiding a tab must not silently delete its underlying activity.

### Agents Chat / Terminal

- Terminal can be added or removed from the visible Agents layout and repositioned.
- Users can place Terminal **on top of the agent Chat container to form a swipe stack** containing Chat and Terminal.
- Users can swipe between the two surfaces in that shared position; only the chosen surface is presented there. This request is for stacking surfaces, not overlaying terminal text on chat text.
- Planning must preserve the existing exact selected-session identity, transcript follow/history intent, approval ownership and persistent PTY/controller. Repositioning, removing a presentation or swiping away must not restart the terminal process or duplicate controllers.

### Timer ruler and countdown

- Make the timer's vertical ruler lines **taller** than they currently are; the requested increase is height, not simply thickness or more ticks. No exact pixel height was specified.
- When countdown starts, the line/position indicator starts moving **slowly backward toward zero**, in accordance with actual remaining time.
- This is continuous time-linked motion, not a stationary selection indicator while only the numeric label decrements, and not an unrelated decorative animation.
- Pause freezes countdown and indicator together; resume continues from actual remaining time. Completion reaches zero. These are consistency requirements derived from the user's synchronization request.
- Placement changes, hiding the widget/tab, or swiping to another stacked surface must preserve the same timer activity. Hidden rendering can pause; elapsed-time accounting must remain correct.
- Timer must participate in the same add/remove/reorder editing system.

## Planning boundaries and decisions still to resolve

- **Current task:** preserve the precise visual reference and intent. Implementation has not been started by this memory request.
- The clip demonstrates adding/reordering widgets, not configurable navigation tabs, an Agents stack or countdown-to-zero motion. Those are explicit requested extensions; keep the evidence distinction.
- “Drag out” is required, but whether it means remove from the layout, move between areas/pages, or create a detached floating window is not yet specified. Do not silently commit to detached windows during planning.
- Stack gesture direction, visible stack/paging affordance, keyboard alternatives, cross-page placement rules, tab/widget independence, edit cancellation semantics, persistence format and permitted widget sizes remain planning decisions.
- Preserve current work and the single collapsed/expanded shell architecture. PR #24 stays draft/open/unmerged unless the user later changes that instruction.
- Native drag/drop, smooth reversible reflow, stable drop targets, accessibility and Reduce Motion need explicit acceptance checks in the upcoming plan. Essential countdown progress remains functional under Reduce Motion; decorative rearrangement can become minimal.

## Acceptance examples to carry into the plan

1. Add Timer beside Media; drag it from left to right; finish editing; resulting layout persists and edit chrome disappears.
2. Remove and re-add a widget without losing the underlying ongoing timer or terminal activity.
3. Add/remove/reorder Timer, Monitoring and Productivity tabs independently of destructive activity deletion.
4. Drag Terminal onto Chat to create the shared swipe stack; switch back and forth without changing exact session, PTY/PID, terminal scrollback or chat reading intent.
5. Start a timer: taller ticks remain readable and the indicator moves smoothly toward zero, synchronized with remaining time through pause/resume and visibility changes.
