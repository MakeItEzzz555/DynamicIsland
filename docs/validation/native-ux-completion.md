# Native UX completion — 2026-10-14

Baseline origin/main: 320825dea9858ae7369d89222d4a554cfca79bc4; PRs #32/#33 are already merged. Work is isolated at ~/DynamicIsland-worktrees/native-ux-completion, branch codex/native-ux-completion. The former integration checkout had independently advanced to bb278f2; it is untouched. Source/index/HEAD preservation manifest for five existing worktrees: /tmp/dynamicisland-ux-completion-preservation.json.

Claude's completed post-merge checkpoint a15a9fa was carried forward as seven distinct commits after patch/ancestry inspection proved those changes were absent from main. This preserves its Live Audio rev-3 consent/lifecycle and rendering changes. The latest instruction to preserve left-click notch Settings access takes precedence over the older right-click-only patch; that route is reconciled in B. Claude’s focused provider-icon checkpoint da7be2a is now available and will be reviewed after the interaction changes. No local/remote codex/native-stability-system-volume-v2 branch was found in either relevant repository at initial inspection.

## A — Collapsed hover ownership

The compact view identity fix alone did not prevent SwiftUI child hover exits during icon/layout changes. Root no longer consumes that child's onHover. The existing AppKit local/global pointer monitors publish idempotent containment over the actual compact shell, rendered sidecars and grown preview. Geometry updates recheck the last observed point, so remounting a child cannot fabricate pointer movement. Genuine exits still clear previews; existing delayed-generation guards, visualizer Pause/Play suppression, native-menu holds, focused/sending reply protection and approval ownership are retained. No new global hook, timer or invisible hit surface was added.

Three new tests passed (21.415s): production IslandRootView hosted in an ordered NSPanel, synthetic AppKit mouseMoved events across the orb/provider/mini-orb band and preview body, each held for at least two seconds; normal and Reduce Motion settings; and pure union/idempotence checks. Each hosted sequence produced one entry, zero repeat exits/entries and one genuine exit. Fixtures contain validated synthetic Agent events, empty clipboard persistence, offline Spotify credentials and unstarted camera/audio services. No system cursor movement, permission request, personal history or real agent transport was used. This is hosted AppKit acceptance, not physical user-hover acceptance in the installed app.

Initial test failures were invalid fixture payload/timestamps and are not treated as production evidence. Sessions now include required metadata and recent validated Thinking events; production validation/freshness rules remain unchanged.

External evidence: the user's reported hover oscillation is OBSERVED product behavior. The child-remount explanation is source/hosted-test evidence. Exact Droppy hover implementation/timing is UNKNOWN and is not needed for this independent correction.

Connected focused result: 31 tests, zero failures/skips, 26.359s. Debug compilation passed. Release/full/package/signatures are reserved for the final composed checkpoint. Log: /tmp/dynamicisland-ux-a-focused.log.

## Pending milestones

B top-edge routing and preserved left click; C shared Media/Tray geometry and accessory removal; D accepted-file Messages/Share/ZIP operations; E common visualizer renderer with separate media/call/microphone authorities; F public per-app audio feasibility and safe non-routing work, with live output replacement gated; G supplied provider icons; H system-volume branch reconciliation/follow-up. No risky capture, output muting, private lock-screen helper or running-app replacement is authorized here.

## B — Top-edge routing / left-click preservation

A checkpoint: 70edb29. B focused tests: 55 passed, zero failures/skips (3.099s), including native top rows at y=0/.25/.5/1/2, multiple widths and notched/notchless fixtures; cutout and outside-shell rejection; exact menu dispatch/file priority; menu Escape; and unchanged absolute collapsed/expanded anchors. The expanded-notch left-click menu route is restored through its existing Settings callback; collapsed single click/hold behavior remains separate.

Important evidence limit: the simple AppKit top-edge baseline already passed. The physical reported narrow-strip defect is therefore not proven to be a shape-path error. Source inspection shows the shell's reachable top formerly coincided with the native panel event boundary; the panel now has a 2pt guard ABOVE the shell without moving either shell in screen coordinates. This removes that boundary coincidence and introduces no desktop hit surface. WindowServer/physical top-edge delivery remains UNVERIFIED until the packaged build is authorized for a user exercise. OS boundary clipping is an INFERENCE, not a claimed observed internal mechanism.

Compact row and preview exclusions preserve media/Agent/native control authority. Registered native controls still win. The physical camera cutout is excluded; no claim is made that clicks can be delivered inside it. No global hook or input injection was added.

## C — Shared Tray footprint and retired accessories

Tray uses the same Media semantic footprint for Compact/Standard/Large and display scaling, without rewriting saved widget placements. File collections scroll inside this footprint. The obsolete four-circle row and external drag orbit are removed, including their height reservations and Settings preview. Shared native sharing-anchor helpers remain for Basket/Tray. Root clears retired accessory registrations and mounts navigation at the existing 3pt gap. Conversion, background operations, Basket and drag transactions remain intact.

Hosted production Tray mounts only navigation and verifies its reachable corridor; saved size/display projection tests verify Media equality. Focused native/unit result and commit are recorded in the delivery checkpoint. Synthetic/hosted tests do not establish physical Finder drag or display pacing. The shared layout projection measured 0.0823ms average over 300 projections (CPU calculation, not animation smoothness).
