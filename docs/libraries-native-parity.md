# Libraries.dev native fidelity — Phase 3

Reference revision: `Jakubantalik/Libraries.dev@d06640864eb4adc2fe240f899a44ee6210779782`.
Packages inspected: `thinking-orbs` 0.3.2 and `bot-avatars` 0.2.2, including their TypeScript engines and official Swift Canvas ports. Both packages are MIT licensed, copyright 2026 Jakub Antalik. Adapted source must retain that notice. No JavaScript rendering or runtime dependency is introduced.

## Preimplementation parity matrix

| Capability | Existing DynamicIsland | Reference / native implementation plan |
|---|---|---|
| Nine orbs | Small coloured dots with broadly similar motion | Port the nine reference engines: orbit, scanning globe, Rubik lattice, wave, network, braid, ribbon, breathing ring, morph |
| 20 / 64 scale | Mostly scaled generic drawing | Preserve the reference's independently tuned presets and validate golden geometry |
| Theme / speed / pause | Speed and static fallback; state changes replace Canvas | Reference monochrome ink, shared phase, explicit freeze, crossfade within one drawing surface |
| Avatar silhouettes | Simplified native shapes | Use all 18 exact reference body paths and body-specific face positions |
| Avatar depth/material | Gradient fills and sparse strokes | Reference projected extrusion, pillow normals and material lighting; extend native port with bounded fabric rendering |
| Faces / state rig | Generic eyes, sinusoidal hopping | Reference projected faces, deterministic gaze/blink, blended idle/working/sleeping rig and staged jump dynamics |
| Accessories / whirl | SF Symbols and simplified overlays | Attached vector accessories and reference spin ring; document mesh/shader differences |
| Pointer | Hover boolean | Stable outer hit surface, position-aware eyes/head, click jump; disable motion under Reduce Motion |
| Identity | Stable 18-shape assignment | Preserve provider/native-session/generation hash; derive deterministic motion seed from it |
| Working / visibility | Inactive app and nonselected rows pause | Visible working characters continue; pause offscreen/explicitly and avoid catch-up on resume |
| Settings | Existing persisted controls | Preserve decoding and reset behavior; map existing controls to rendering and add optional advanced native configuration |
| Lifecycle / performance | Local timelines | Canvas-local invalidation, bounded geometry/material caches, no per-frame Tasks or independent capture resources |

## Acceptance discipline

Transition guidance applied from `transitions-dev` and `transitions-polish`: retain the upstream rig's hand-tuned timing rather than substituting a generic spring; keep pointer hit geometry stable; blend state changes without replacing the character; suppress decorative transforms with Reduce Motion. Golden vectors establish geometry parity, not live visual or whole-app memory acceptance. Browser rasterisation, native fabric and accessory rendering differences require separate visual review.

## Implemented parity and deliberate differences

| Orb | Native engine / distinguishing behaviour | Evidence |
|---|---|---|
| working | Independent projected orbital dot paths | Upstream 20/64 vectors |
| searching | Scanning rotating globe | Upstream 20/64 vectors |
| solving | Turning Rubik lattice | Upstream 20/64 vectors |
| listening | Layered travelling wave | Upstream 20/64 vectors |
| connecting | Moving network with connecting strokes | Upstream 20/64 vectors |
| weaving | Braided intertwined strands | Upstream 20/64 vectors |
| composing | Twisted ribbon | Upstream 20/64 vectors |
| breathing | Expanding/contracting ring | Upstream 20/64 vectors |
| shaping | Shape interpolation and deformation | Upstream 20/64 vectors |

All nine engines preserve the upstream mathematics, z sorting, monochrome ink and independently tuned 20/64 presets. The golden comparison checks 72 cases / 70,115 values at tolerance 0.0001. This proves geometry parity at sampled instants; it is not pixel identity across browser and CoreGraphics rasterisers. Intermediate view sizes choose a legible inline or primary preset, rather than claiming upstream 32-pixel tuning. State handoff crossfades inside one Canvas for 240ms; the character rig retains upstream sine state weights and separately timed anticipation, launch, stretch, spin, landing, ground hold and recovery.

All 18 body paths match the pinned TypeScript source exactly: clover, flower, triangle, square, blob, ghost, circle, drop, star, droid, mech, alien, hexagon, cat, cloud, pill, pebble and puddle. Palette, body-specific face coordinates/scales, OKLab adjustment, deterministic Mulberry32 rig, current gaze corners/holds/eye lead, jump stages and state blend timings were compared with the actual source. The official Swift port was older than the TypeScript rig; its native engine was updated rather than treating it as automatically current.

Native rendering uses projected extrusion, pillow normals, per-texel matcap lighting and attached projected faces. Plastic, crisp, smooth and flat follow the upstream native port. Fabric adds a cached, deterministic combed fleece and fringe over the moving matte pillow. Direct review of the live `/bots` preview identified the need for a denser pile and softer outline, which the native texture now provides. **Fabric remains a perceptual approximation:** the browser's signed-distance haze/cut/core/film layers, fibre Kajiya–Kay lighting and exact edge lift are not all reproduced. Native fibres have coarser lock relief, less view-dependent sheen and different fringe rasterisation. This is not claimed as exact plush-shader parity.

Hats, glasses, headphones and bow tie are attached native vector forms with pose projection and local light gradients. **Accessory geometry remains approximate:** these are not the browser's full rounded three-dimensional meshes, and occlusion at extreme poses differs. The whirl uses the upstream native sampled band, with strength/size/width/length/tilt; the browser uses a denser split-stroke ring. Bitmap fibre orientation is explicitly tested on an asymmetric triangle; the first denser-pile review revealed an upside-down film, which was corrected before final validation. A held yaw/pitch/roll pose freezes the character for deterministic review; click/pointer tracking is disabled for held/paused poses and Reduce Motion.

Compact characters deliberately use a smaller body box, a quarter of the jump displacement, and clipping to preserve the actual island/row bounds. Full primary previews retain reference overscan. The expanded CLI stays content-first: its selected-session toolbar has the stable identity glyph, provider buttons remain recognizable, and a separate inline activity orb accompanies active console status. No larger showcase row was added to the transcript. A 64-point primary orb is available in Appearance and the review harness; the real compact/CLI placements use inline tuning.

## Phase 4 — event-driven Codex semantics

Baseline `883f2b6971a7d842435d159b4b765a4b3b95ba57`, October 3, 2026. The renderer engines, paths, rig, presets and caches are preserved. The defect was upstream of rendering: reasoning items were discarded, while presentation guessed search/connection/composition from activity text. A running turn could therefore show the wrong orb despite correct renderer geometry.

Typed provider evidence now enters the existing normalized stream/store as optional `AgentProcessingKind` metadata. Item correlation retains nested work until its exact completion; existing command/tool and approval precedence remains authoritative. Legacy payloads decode without the optional fields. No reasoning content, command arguments, search queries or paths are added to this metadata. Compact and expanded use the same presentation mapper. Transcript completion still publishes the existing transcript separately.

| Concrete normalized evidence | Native orb | Scope / qualification |
|---|---|---|
| reasoning item | solving | Active item only; reasoning text excluded |
| plan item / unfinished turn plan | shaping | Completed planning metadata is removed |
| webSearch / commandActions search or listFiles | searching | Structured provider classification, never assistant prose |
| command execution / file change / MCP or dynamic tool | working | Tool and command retain distinct text/state labels |
| thread-scoped MCP startup / spawnAgent or resumeAgent | connecting | Global startup cannot choose an arbitrary session |
| structured read command / collab wait | listening | Active external input/read evidence |
| agentMessage item | composing | Completion removes processing and retains transcript delivery |
| contextCompaction | breathing | Active low-intensity/background evidence |
| typed synthesis | weaving | Supported semantic model; this provider run supplied no genuine synthesis event |
| approval, user wait, plan ready, interrupted, failed, completed, idle | no continuous processing orb | Existing attention/avatar or static terminal treatment wins |

**PASS — automated/fixture:** raw provider notification → adapter → reducer → orb tests cover nested return to reasoning, typed search/read/tool distinctions, planning, misleading prose, exact blocking precedence, terminal cleanup, legacy decoding, bounded/idempotent tracking and provider/generation isolation. Existing deterministic phase, pause/resume, identity, accessibility, geometry and cache tests remain green.

**PASS — live:** a real Codex 0.160.0 task used repository search, file reading and Python execution; exact-session normalized evidence drove solving, searching, listening, working, connecting and composing, followed by terminal cleanup. This is live provider/controller evidence, **not packaged visual acceptance**. Shaping/weaving and a post-tool return to reasoning were not observed in that run; deterministic provider fixtures cover their supported routing without inventing live events.

**NOT VERIFIED:** final uninterrupted packaged working animation, visual semantic transitions, pointer/click and compact/expanded phase continuity. The rebuilt app launched, four real shell/section cycles completed, and a fifth aborted when navigation disappeared during concurrent desktop use. A real microphone consent dialog then required human action. These endpoints and the passing grids do not certify continuous motion. Actual Reduce Motion was checked OFF and left OFF; this phase did not complete OFF → ON → OFF.

Transition guidance was applied from `transitions-dev` (Thinking states and Avatar group hover) and `transitions-polish`: stable hit/layout geometry, local content handoff, lifecycle termination, and reduced-motion suppression. The recipe's demonstration timer/state cycling was deliberately excluded because provider events must own semantic state. Upstream rig timing was preserved; no CSS, JavaScript or new animation framework was introduced. Fabric fringe/light, accessory meshes/extreme-pose occlusion, whirl sampling and rasterisation gaps remain unchanged. See [the Phase 4 validation record](agent-presence-validation.md#phase-4--native-fidelity-release-gate-and-codex-semantic-routing) for exact release, profiling and blocker evidence.

## Lifecycle and harness

The presentation-only roster retains at most 64 provider/native-session/generation players across shell handoff. Explicit seed changes reseed the same player; neither project nor source metadata replaces identity. StateObject retains each view's clock/render context instead of allocating a discarded material buffer on every struct reconstruction. The player deduplicates identical ticks and integrates speed with bounded substeps; invisible/resumed output never catches up a long background gap. Visibility tracks window occlusion, hidden ancestors and clipping; pointer tracking uses a stable outer region and consumes no hit tests. Frame ticks never publish into domain state, transcripts or the island root. No per-frame Task, timer, notification subscription or second capture session is introduced.

Limits: 48 material forms / 8 pending serial bakes; 24 fibre textures (under 4 MiB at 192² RGBA); 64 custom paths and accessory seats; 64 session players. The local native port uses Swift 5 mode for its synchronous Canvas support code; application and session code remain Swift 6. Its drawing caches are used by the synchronous main-thread Canvas path; material background caches are lock-protected. This is a local source target, not a downloaded runtime dependency or rendering framework.

Run `bash Scripts/validate_agent_visual_fidelity.sh parity` to generate dark/light grids for nine orbs at two sizes and three times, 18 bodies × three states × five materials, accessories, eye/mouth modes, three seeds, working/compact frames, paused poses and a fixed-clock motion GIF. Production UI contains none of this review grid. Generated evidence stays in `/tmp/dynamicisland-phase3`; tests expose only isolated presentation inputs and do not mutate real sessions. Native ImageRenderer receives a frozen-time environment that omits AppKit tracking/visibility adapters; otherwise it paints unsupported-view placeholders. Real hosted/live views keep those adapters.


## Agents workspace reconstruction — BorderBeam, Orb chat and Avatar Feed

Baseline reference `883f2b6971a7d842435d159b4b765a4b3b95ba57`; the branch legitimately advanced through `32d7430369b4be6509dc50a561a7bf363023e277` while this phase was in progress because provider-event Codex orb routing was committed first. The workspace continuation preserved that work rather than resetting it.

The active selected-agent chat now uses the native Libraries.dev BorderBeam at the `md` / colorful / 0.7-strength treatment and a semantic ThinkingOrb as its activity identity. The Beam is driven from canonical session/interaction state rather than transcript text and goes inactive for terminal/blocking states. Model and reasoning-effort controls live inside the chat surface; Codex reasoning options come from the provider model catalog and are exact-generation next-turn preferences. Unsupported provider/model combinations remain unavailable rather than fabricated.

The expanded Agents content is one two-pane workspace. The right pane retains exactly two pages, **Feed** and **Terminal**, with one persistent terminal controller. Feed/Terminal page selection does not reconstruct the terminal process. The Feed uses stable BotAvatar identity and bounded semantic event history. Approval cards moved into the Feed while retaining exact provider-request acknowledgement semantics. Right-pane vertical scroll registration is independent from the transcript scroll region, preventing Feed/Terminal scrolling from collapsing the island while preserving horizontal island/workspace gesture ownership.

Usage is grouped into six compact indicators: Codex + Claude 5-hour remaining, Codex + Claude weekly remaining, and Codex + Claude selected-session context used. Unavailable provider metrics remain explicitly unavailable. Compact working-agent presence was corrected during final review to use the semantic ThinkingOrb rather than the generic avatar-capable presence glyph; BotAvatar remains the Feed identity.

Transition guidance applied from `transitions-dev` / `transitions-polish`: 250 ms smooth-out tab/content handoff, 300 ms smooth-out internal width allocation, local feed insertion movement/opacity, stable retained page identity and no spatial animation under Reduce Motion. Actual system Reduce Motion was read as OFF (`0`) and left unchanged; OFF → ON → OFF is **NOT VERIFIED** because this phase did not autonomously modify the user's system accessibility setting.

**PASS — automated/fixture:** workspace presentation **7/0/0**; Feed **11/0/0**; BorderBeam native/GPU **12/0/0**; provider/controller/client targeted set **94/0/0**; semantic/visual/workspace/Beam set **52 passed / 0 failed / 1 live-provider skip**; scroll/gesture regression **42/0/0**; deterministic 23-scenario workspace snapshot export **1/0/0**. Offscreen snapshot runs can log `CAMetalLayer nextDrawable` allocation warnings and are not treated as Beam pixel-fidelity evidence; dedicated actual-GPU Beam tests are the shader/runtime evidence.

**PASS — automated performance:** `AgentsPerformanceHarnessTests/testMeasureAgentsPage` passed. In its 200-delta streaming scenario, transcript publication remained isolated: 73 transcript publishes, 154 console evaluations, but only **6** dashboard/content/controlbar/feed/selected evaluations and **2** managed-controller publications. Typing 38 keys produced three console evaluations rather than transcript-wide rerender-per-key behavior.

**PASS — automated/fixture soak:** 110-cycle bounded lifecycle workload, fixed 32 sessions and 80 transcript entries. Physical footprint samples at cycles 10/30/50/70/90/110 were **43,879,168 / 45,058,816 / 45,337,408 / 45,370,176 / 44,419,904 / 44,469,056 bytes**; after teardown **39,914,304 bytes**. The controller released. This is bounded fixture evidence, not unrestricted whole-app live memory closure.

**PASS — regression:** full suite **1,665 passed / 0 failed / 38 skipped**. The supplied pre-workspace baseline was 1,586/0/36. No failures were converted to skips.

**PASS — Release build and strict signature after generated-metadata recovery:** production build completed. Initial bundle signing encountered the known generated Finder/resource-fork metadata issue in the iCloud-backed output directory. Only generated `dist/DynamicIsland.app` extended metadata was cleared, then the same existing ad-hoc signatures were reapplied. `codesign --verify --deep --strict` passed for the app and all three helpers. No signing policy, Keychain item, privacy setting or entitlement was changed.

**BLOCKED / NOT VERIFIED:** the final live Codex workspace sequence is blocked by the user's current Codex usage limit, so no repeated provider retry was attempted. Claude/concurrent-provider acceptance remains subject to the existing external quota gate and is not reclassified. Final packaged uninterrupted pointer/click, Beam/orb motion, actual OFF → ON → OFF Reduce Motion, and final-package UI acceptance remain human-assisted gates. The currently running packaged process predates the rebuilt artifact and is not used as final-package evidence.

See [agent-workspace-architecture.md](agent-workspace-architecture.md) for ownership and surface boundaries and [border-beam-native-source.md](border-beam-native-source.md) for upstream shader/source provenance.
