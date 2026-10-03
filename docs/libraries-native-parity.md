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

## Lifecycle and harness

The presentation-only roster retains at most 64 provider/native-session/generation players across shell handoff. Explicit seed changes reseed the same player; neither project nor source metadata replaces identity. StateObject retains each view's clock/render context instead of allocating a discarded material buffer on every struct reconstruction. The player deduplicates identical ticks and integrates speed with bounded substeps; invisible/resumed output never catches up a long background gap. Visibility tracks window occlusion, hidden ancestors and clipping; pointer tracking uses a stable outer region and consumes no hit tests. Frame ticks never publish into domain state, transcripts or the island root. No per-frame Task, timer, notification subscription or second capture session is introduced.

Limits: 48 material forms / 8 pending serial bakes; 24 fibre textures (under 4 MiB at 192² RGBA); 64 custom paths and accessory seats; 64 session players. The local native port uses Swift 5 mode for its synchronous Canvas support code; application and session code remain Swift 6. Its drawing caches are used by the synchronous main-thread Canvas path; material background caches are lock-protected. This is a local source target, not a downloaded runtime dependency or rendering framework.

Run `bash Scripts/validate_agent_visual_fidelity.sh parity` to generate dark/light grids for nine orbs at two sizes and three times, 18 bodies × three states × five materials, accessories, eye/mouth modes, three seeds, working/compact frames, paused poses and a fixed-clock motion GIF. Production UI contains none of this review grid. Generated evidence stays in `/tmp/dynamicisland-phase3`; tests expose only isolated presentation inputs and do not mutate real sessions. Native ImageRenderer receives a frozen-time environment that omits AppKit tracking/visibility adapters; otherwise it paints unsupported-view placeholders. Real hosted/live views keep those adapters.
