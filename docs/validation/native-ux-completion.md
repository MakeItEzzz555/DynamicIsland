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

## D — Native accepted-file drop operations

The stable 2×2 zones are Keep/Messages/Share/ZIP. Root claims one existing drop generation, materializes and accepts first, and operates only on accepted URLs. Stale callbacks cannot replace current status. Keep selects accepted items; partial acceptance reports counts. Messages uses NSSharingService.composeMessage and explicitly reports composition handoff, never send confirmation. Share retains its live NSView anchor, picker/service and an independent fileSharing(UUID) hold until cancel/completion/window close; termination cleans sessions. Conversion remains in the existing context menu. ZIP preserves originals and selects output only after background archive completion; errors and cancellation no longer leave a working status forever.

47 focused tests pass, zero failures/skips, including real ZIP archive contents/source preservation, temporary-file drops/file promises, partial/full Tray acceptance, duplicate/stale claims, unavailable anchor, native sharing ownership/idempotent dismissal, and ZIP failure. No real Messages composition/send or Finder/Share interaction was initiated. Native sharing delegate lifetime is source + deterministic callback evidence, not physical acceptance. The former failed ZIP test discarded its controller; retaining the production-equivalent owner fixes the fixture without changing assertions.

## E — Shared visualizer rendering, separate authorities

AudioVisualizerBars is the only capsule/color/size renderer for live media FFT, decorative calls and recording meters. Media preserves Claude’s eight-band interpolation, SpectrumDynamics, artwork gradients, Rev-3 consent and visibility leases. Calls remain green/yellow decorative presentation and never acquire system/microphone capture. Voice now adapts the existing authorized AVAudioRecorder normalizedLevel through the existing VoiceBeamEnvelope attack/release into spatial bar weights; these are explicitly microphone envelope levels, not frequency bands. The prior voice beam is no longer mounted in the collapsed recording activity; no second timer/FFT/capture owner is added. Reduce Motion eliminates decorative motion while meter changes remain readable. Transcription/status and stored-audio ownership are unchanged.

70 focused tests pass, zero failures/skips (6.048s): real production media mailbox-to-raster, inert previews, consent persistence/lifecycle, fake recorder meter authority, renderer rasters for all three palettes, finite bounds, silence and envelope reset. No real audio or microphone capture was started.

Follow-up: introduce a separate recording-oriented export/save workflow before renaming Voice Transcribe. Preserve its current recording retention and exact permission lifecycle; make transcription an explicit optional action after recording. This milestone does not perform that capability migration.

## F — Honest per-app capability boundary

Public Apple docs and installed SDK headers prove process taps and muting behavior. A capture/gain/replay mixer is plausible, but atomic cutover, fail-open teardown, device clocks, Bluetooth/AirPlay, permission/signing and crash recovery have not been proven. Read docs/research/per-application-volume-feasibility.md. No gain widget or risky routing is enabled. ApplicationAudioDiscovery is a manually invoked, background, read-only implementation of the existing contract: actual output-IO processes only, bounded allocation, PID reread and generation invalidation. Output IO is accurately distinct from audible measured samples. Gain=nil/controlAvailable=false and every gain request is rejected as unsupported/stale/invalid. Nothing discovers or captures audio at launch.

7 focused discovery/contract/provider tests pass, zero failures/skips. Actual HAL discovery was not run; fixtures contain only synthetic process records. Hardware replacement/muting requires a separately authorized controlled acceptance before production routing.

## G — Provider icons and preserved consent

Claude source checkpoint da7be2a was reviewed and integrated as 41e875d. Supplied PNG bytes are retained in the SwiftPM asset resource catalog. One renderer resolves the packaged bundle first; compact Agents now show the primary Thinking Orb on the left and actual provider identity on the right, with mini-orbs/overflow before it. Provider width does not inflate multi-session layout. Hover preview statuses and approvals retain their authority. 79 connected tests pass, zero failures/skips (25.627s), including 2s hover stability with the integrated layout, provider identity/resource tests and persisted Live Audio consent/mailbox rendering. Package resource/signature checks are pending the final build.

## H — System-volume observer and coalesced HUD slider

No existing stability/system-volume branch was found after refresh. The existing HUD owner now observes the default device and its supported virtual-main/main/channel volume and mute properties. Device replacement rebinds owned listeners; stop/disable removes exact registrations. Identical observations/verified-write echoes are suppressed while distinct external volume/mute changes remain eligible. The interactive volume HUD submits one background actor write plus one latest pending value, and only the latest verified reply updates presentation. Reads/writes pin one device through the existing three-stage scalar verification; device switches invalidate pending UI replies. Option+Shift media-key steps are 1/64, normal remains 1/16, and unsupported hardware still passes through. Existing Music/Spotify scripting volume is unchanged and remains distinct from system output and unavailable per-app routing.

24 focused tests pass, zero failures/skips (5.122s): 100 rapid synthetic slider requests produced exactly two backend calls and one final reply; cancellation rejects stale replies; invalid values never write; external volume/mute observations survive echo filtering; fine step is one quarter; camera local-routing/input-priority and HUD/policy fences remain green. These use fake writers, not real hardware volume changes. Core Audio listener/device/headset/Control Center acceptance remains manual. Public contract SystemVolumeProviding adoption by future widgets is not implied by this existing HUD integration. No new event tap is introduced; the existing explicitly enabled media-key interceptor is reused.

## Preservation

At the post-milestone audit, the canonical rescue (536 source/docs files), earlier integration (561), Claude post-merge (563) and audio checkout (549) retain every baseline file hash, index hash and HEAD. The separate provider-icon checkout advanced independently to da7be2a with its four expected source/test modifications and new resources; this branch imported that authored commit without writing to that checkout. Snapshot manifests: /tmp/dynamicisland-ux-completion-preservation.json and /tmp/dynamicisland-ux-completion-preservation-after.json. Generated graph files stay outside the delivery index.

## Final review corrections and full-suite evidence

The first composed full run executed 2,536 tests, 42 skipped, with four assertion failures in two cases (223.650s): IslandKeyboardAcquisitionTests.testReturnShiftReturnDeleteAndRepeatedReopenUseExactEditor (3) and SettingsWindowTests.testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy (1 activation inconclusive). The keyboard test/editor source was unchanged from main. The display was unlocked/on-console; physical app activation remained cooperative. These results are retained, not classified as new feature failures or hidden skips.

Connected Ponytail review found two small corrections: compact-control exclusions must follow the centered original base shell and its horizontal preview offset; and the existing explicit editor-click policy must reacquire key status synchronously if makeKeyAndOrderFront only orders a reopened nonactivating panel. The latter adds a direct makeKey fallback only during already-authorized editable-responder engagement, no passive or delayed activation. Assertions are unchanged. 28 focused keyboard/Settings/notch tests now pass, zero failures/skips (4.279s), including the previously failing repeated-reopen case and top control pixels after preview growth. Full validation is rerun against the corrected head. Physical user typing/menu acceptance is not implied by local synthetic events.
