# Executive Summary

**Status: partial investigation; downloaded/free target unresolved.** The public-source and DynamicIsland comparison is complete for the scoped subsystems. Shipped Droppy behavior and target-specific REA analysis are blocked because the requested app could not be identified. Two source-built Debug bundles were found and deliberately excluded. They cannot establish facts about the downloaded product.

The strongest source-supported findings are:

1. Both notification implementations combine database/WAL observation, the same Darwin wake-up hint, and backup polling. Droppy's 2-second fallback versus DynamicIsland's 4-second fallback does not establish lower latency on the event-driven path.
2. DynamicIsland distinguishes persisted permission history from current capture evidence and build identity. Droppy's permission manager can return a cached grant after current preflight returns false; its actual screenshot capture separately checks preflight, so this is a manager/UI inconsistency rather than proof that capture skips authorization.
3. DynamicIsland has more explicit camera, input-generation, exact-message, and transient-interaction authority. Droppy's inspected source instead combines preview reference counting and several imperative hover/drag/menu checks. Comparative physical UX quality is unmeasured.
4. Droppy contains an optional ScreenCaptureKit system-output audio analyzer; DynamicIsland's inspected call visualizer is decorative. A system-output meter cannot establish call-specific audio levels.
5. Droppy's inspected AirPods path substitutes 100% when battery evidence is missing. DynamicIsland's presentation preserves unknown battery state. Both apps also contain private media/brightness dependencies; neither should be described as globally public-API-only.

These are **A + E source comparisons**, not two independent forms of Droppy evidence. No conclusion about shipped behavior has public-source-plus-black-box or public-source-plus-REA corroboration yet. No production code was written or borrowed.

# Scope and Clean-Room Rules

Investigation date: 2026-10-13. Scope covers the requested notch geometry, interaction, gestures, camera, media, notifications, AirPods, clipboard/shelf, capture, permissions, settings, multi-display, and motion subsystems. Agents and Terminal were inspected only to understand DynamicIsland authority boundaries.

Evidence labels throughout:

- **A — Public source fact:** a declaration or behavior visible in the identified public Droppy checkout.
- **B — Black-box fact:** directly observed behavior of the requested downloaded/free Droppy.app. None obtained.
- **C — REA fact:** target-specific binary/runtime evidence from that app. None obtained.
- **D — Inference:** an interpretation or future specification, explicitly separated from proven behavior.
- **E — DynamicIsland fact:** implementation or test source at the recorded HEAD. Test source was inspected; tests were not rerun.

The app discovery and REA transport verification are environmental evidence, not B/C product evidence. Source constants are not measured animation durations, inference FPS, or runtime performance.

Only this report was added. No branch switching, staging, commits, pushes, merges, source/config changes, application patching, signing changes, permission changes, clipboard replacement, recording, or camera use occurred. No notification databases, personal messages, clipboard histories, Keychain material, or proprietary assets were collected. No decompiled material was produced. Existing graphify and Playwright files were left untouched; graphify commands that could update their caches were not run.

There is an important provenance qualification: current DynamicIsland already attributes portions of `WorkspaceMotion.swift` and an AirPods visual reference to public Droppy source. This investigation adds no implementation reuse and does not assert that the existing product has wholly independent origins.

# Target Versions

| Target | Recorded identity |
|---|---|
| DynamicIsland repository | `/Users/makeiteasy3/Documents/DynamicIsland-main` |
| DynamicIsland branch / HEAD | `feature/camera-hand-navigation` / `1cd01b4d3a90b49f497176d0c9c19f91eda904a1` |
| Fetched `origin/main` | `2ad101e960401202adc1ec748cfedebf6707571e` |
| Public Droppy checkout | `/Users/makeiteasy3/Documents/Droppy` |
| Public Droppy source HEAD | `dd2d16ccbdc6aa22b456e199442b43a07aa446af`; public remote HEAD matched |
| Public source repository | `https://github.com/1of1Adam/Droppy.git` |
| Public source version fields | 11.0.0 / build 4; bundle ID `iordv.Droppy` |
| Downloaded/free Droppy.app | **Not identified; path, version, build, executable SHA-256, entitlements and imports unknown** |
| macOS | 15.7.4, build `24G517` |
| REA | Package/server 6.4.0; installed skill metadata version 37 |

The public source commit is dated 2026-02-09 and titled “Initial commit: Open source version of Droppy.” That date does not establish what source produced a later shipped app.

Safe discovery covered `/Applications`, user Applications/Downloads/Desktop, mounted volumes, Spotlight name/bundle-ID results, and an exact Droppy process-name check. No running Droppy process was found. The only located bundles were:

- `/Users/makeiteasy3/Documents/Droppy/build/Build/Products/Debug/Droppy.app`
- `/Users/makeiteasy3/Library/Developer/Xcode/DerivedData/Droppy-dbvcilfoschkdfbdihwcbaqlnpov/Build/Products/Debug/Droppy.app`

Their Info.plist metadata reports 11.0.0/build 4 and `iordv.Droppy`. They were not launched, hashed, or analyzed as substitutes. Discovery cannot prove the downloaded app is absent elsewhere on disk. A question requesting its exact path remains unanswered.

REA's existing global Codex registration was verified without reinstalling or editing configuration. This session exposes no REA MCP tools directly. The installed, version-pinned CLI transport passed a target-free production-stdio doctor check: server identity 6.4.0, protocol `2025-11-25`, 170/170 tools, 6/6 prompts, and successful `binary_session` request. This verifies the transport, not a connected Droppy native-analysis session or the availability of every optional native backend.

# Architecture Comparison

| Area | A: public Droppy architecture | E: DynamicIsland architecture | Interpretation |
|---|---|---|---|
| Shell/window | Per-display transparent nonactivating panel; larger native envelope around state-sized SwiftUI shell | Overlay panel, geometry service, semantic layout/hover policy | Similar primitives; visual/interception contracts need runtime comparison |
| Interaction | Global/local mouse/scroll monitors; geometry, drag, popover and HUD dismissal checks | Explicit transient owners, physical-input arbitration, generation-scoped camera routing | DynamicIsland's ownership is more explicit in the inspected paths |
| Camera | Singleton AVFoundation session owned by preview appearance count | One session shared by independent navigation, Mirror and explicit capability owners | Different feature scope; DynamicIsland supports independent consumers |
| Notifications | Read-only DB + WAL watchers + Darwin hint + 2s fallback | Read-only DB + WAL watchers + same hint + 4s fallback, coalesced record delivery | Broad mechanism parity; both depend on undocumented notification storage/name |
| Messaging/calls | Generic Notification HUD in inspected source | Exact Messages resolution/send confirmation; conservative FaceTime evidence adapter | A generic notification is not exact-chat or call-control authority |
| Media | MediaRemote adapter stream, private commands; Spotify AppleScript timing | Private MediaRemote detection, source-specific seeking and scrub generations | Both have private compatibility dependencies; DynamicIsland more explicit about seek lifecycle |
| Capture | Element screenshot capture and optional system-output analyzer | Movie recording, permission recovery, host-clock timeline | Different products; shipped Droppy movie capability is unknown |
| Motion | Shared SwiftUI/AppKit motion helpers, refresh/energy/Reduce Motion adaptation | Existing native motion and geometry primitives, Reduce Motion | Comparable source intent; no comparative runtime smoothness claim |

# Evidence Matrix

References below resolve through the Evidence Appendix. **Blocked** means no requested shipped target, not evidence that a feature is absent.

| Feature | Droppy Public Source | Droppy Black-Box | REA Evidence | DynamicIsland | Difference | Confidence | Safe Independent Direction |
|---|---|---|---|---|---|---|---|
| Window and notch geometry | A1: fixed initial panel envelope, state-sized shell, top anchoring | Blocked | Blocked | E1: public screen geometry and overlay primitives | DIFFERENT BY DESIGN | High for source; runtime unknown | Measure rendered and interactive bounds separately |
| Hover/interception | A2: wider entry zone, delayed geometry recheck; hover alone stays click-through | Blocked | Blocked | E2: semantic hover policy and explicit protected owners | NOT PROVEN for feel | High for source | Test passive preview versus interactive ownership without changing unrelated geometry |
| Trackpad paging | A2: accumulation/dominance and event-gap reset | Blocked | Blocked | E3: existing central navigation; camera stroke lifecycle separately scoped | DIFFERENT BY DESIGN | Medium; complete physical comparison pending | Retain one physical stroke/one action contracts |
| Camera ownership | A3: preview consumer count; appearance may request permission | Blocked | Blocked | E3: independent owners sharing one session | BETTER IN DYNAMICISLAND for inspected ownership/permission contract | High for source | Preserve explicit permission intent and final-owner cleanup |
| Camera hand navigation | A3: no named hand-navigation mechanisms in bounded Swift search | Blocked | Blocked | E3: bounded Vision pipeline and app-local pointer/gesture modes | DIFFERENT BY DESIGN; shipped presence NOT PROVEN | High for positive DI fact; bounded negative only | Validate current physical palm/pinch behavior rather than infer it from tests |
| Notifications | A4: watchers, Darwin hint, 2s poll, 20ms coalescing | Blocked | Blocked | E4: watchers, same hint, 4s backup and dedup | EQUIVALENT broad mechanism | High for source; latency unknown | Fault-test missed hints, overlapping events and changed schema |
| Notification privacy/time | A4: prints content; substitutes fetch-time `Date()` | Blocked | Blocked | E4: database authority remains separate from hints | NOT PROVEN overall logging parity | High for Droppy source | Require content-free diagnostics and honest timestamp provenance |
| Messages and FaceTime | A4: generic app notification capture | Blocked | Blocked | E5: exact-chat send/confirmation; unverified FaceTime controls remain absent | BETTER IN DYNAMICISLAND for authority specificity | High for source; live acceptance unknown | Keep preview, action authority and confirmation separate |
| Screen permission | A5: cached screen grant can override false preflight; capture checks again | Blocked | Blocked | E6: current API evidence and cdhash request ledger | BETTER IN DYNAMICISLAND for recovery contract | High for source | Keep explicit request, settings/relaunch recovery and fresh evidence |
| Screenshot/movie capture | A5: element/rect screenshots; no named movie writer in scoped Swift search | Blocked | Blocked | E6: movie recorder with pause/static timeline and no-frame cleanup | DIFFERENT BY DESIGN | High for positive facts; shipped movie absence unknown | Optional independent element capture specification, if useful |
| Audio visualizer | A6: decorative bars plus opt-in system-output RMS analyzer | Blocked | Blocked | E7: decorative call animation, explicitly not audio levels | DIFFERENT BY DESIGN | High for source | Optional output meter only with permission and honest source attribution |
| Media/Spotify seek | A6: streamed metadata, Spotify timing poll, private generic seek | Blocked | Blocked | E7: one-release seek and Spotify end guard/source authority | BETTER IN DYNAMICISLAND for inspected lifecycle | High for source | Keep release/track-generation fences; verify real target behavior |
| AirPods battery | A7: IOBluetooth events, undocumented selectors, missing value → 100% | Blocked | Blocked | E8: battery optional; unknown remains unknown | BETTER IN DYNAMICISLAND for truthfulness | High for source; battery coverage differs | Use capability-tested readings; never invent charge |
| System HUDs | A7: CoreAudio events; brightness polling/private symbols | Blocked | Blocked | E8: CoreAudio events; private brightness fallbacks | EQUIVALENT broad mechanisms | High for inspected source | Public/private capability inventory and graceful degradation |
| Clipboard/file shelf | A8: polling, exclusion preferences, atomic/coalesced persistence and URL shelf | Blocked | Blocked | Corresponding full retention policy not assessed here | NOT PROVEN | High for Droppy facts only | Compare privacy and persistence contracts before proposing changes |
| Settings | A9: UserDefaults/AppStorage, conditional Settings license gate | Blocked | Blocked | Current task does not validate live native categories | NOT PROVEN | High for Droppy source | Do not bypass a gate; measure accessible free settings only |
| Fullscreen/multi-display | A1/A9: per-display windows, polling, private CGS Space metadata | Blocked | Blocked | E1: fullscreen participation and public notch metrics | NOT PROVEN functional equivalence | High for API source; behavior unknown | Explicit public compatibility limits, no private Space transplant |
| Reduce Motion | A9: alternate easing, reduced blur/scale | Blocked | Blocked | E1/E7: native motion preferences and static decorative state | EQUIVALENT intent | High for source; runtime unverified | Test preserved functionality under motion/transparency preferences |

# Detailed Findings

## Event-driven versus polling

**A/E:** Notification wake-up mechanisms are already closely aligned. The Darwin name is a wake-up hint; rows remain the data authority. Filesystem notifications and SQLite interfaces are distinct from the undocumented Notification Center database schema and Apple-specific bulletin name. Neither pipeline should promise that the name/schema is a supported, permanent notification-observation contract.

**A:** Droppy mixes event and polling approaches: normal input monitors and observation; a 50ms top-edge fallback; 1s fullscreen checks; 5s window watchdog; 2s notification backup; 500ms clipboard polling; 1s Spotify AppleScript timing; 2s Apple Music reconciliation; 500ms brightness polling; and event-driven IOBluetooth/CoreAudio callbacks. Its real-audio smoothing timer is 30Hz, while the inspected bar animation runs at 10Hz. These are source scheduling constants, not measured CPU costs.

**E:** DynamicIsland's generic media controller polls at 750ms. Camera admission is capped around 20Hz with one serial inference path and a latest-result mailbox. A configured cadence does not prove actual recognition FPS. Backup polling is not inherently a defect; measure energy and failure recovery before removing it.

## Responsive collapsed/expanded interaction

**A:** Droppy separates the visual shell from a larger native panel, preserves the top anchor when resizing, widens hover entry zones, and rechecks geometry before delayed expansion/collapse. Defaults are 250ms auto-expand, 100ms auto-collapse, and a longer populated-shelf delay. The floating default shell is 210×37pt with a 4pt margin; the initial native panel is 500×280pt. Physical-notch and content-specific dimensions differ. None of these values were measured in the shipped app.

**D:** Wider entry zones and click-through passive hover plausibly reduce frustration, but responsiveness and superiority require repeated black-box trials. Independently specify expected activation/interception boundaries rather than import exact constants or layout code.

**E:** DynamicIsland already has activity-specific height growth: static activities do not expand; Agent approval is bounded; replyable Message hover adds 128pt, nonreplyable preview 92pt; call interaction grows only for authorized controls. Current camera collapsed pinch is semantic, separate from tiny pointer hit testing, and claims a transient hold before expansion. These existing contracts should be acceptance-tested before changing geometry.

## Ownership and gesture conflicts

**A:** Droppy guards dismissal with drag state, menus/popovers, To-do interaction, notification HUD state, and window geometry. Some popover detection depends on class names. Scroll switching uses dominance/accumulation and event-gap reset; the inspected handler does not use phase/momentumPhase. That does not prove repeated visible page transitions from one physical swipe.

**E:** DynamicIsland camera injection is app-local, generation-scoped and suspended for physical-input ownership. Pinch/drag lifecycle and palm-navigation ownership are separate. Current palm code rearms after a 150ms stable open-palm dwell, ignores moving return/recenter, and hides the pointer while navigating. Current collapsed protection is based on exact approval, protected Message interaction, focus, HUD, native surfaces, file drag, and noncamera owners; passive preview alone is not protection.

**D:** Explicit owners are easier to audit than distributed exceptions. This is an architectural judgment, not proof that every physical conflict is solved. Prior user-observed camera failures and source-level repair tests are not a new physical acceptance run.

## Permissions and recovery

**A:** Droppy's screen permission getter can return cached true after false current preflight, including after a 15s startup grace. However, `captureRect` independently preflights, explicitly requests if necessary, throws on denial, and then enumerates ScreenCaptureKit content. Report the distinction; do not describe every Droppy capture path as cache-only.

**E:** DynamicIsland uses current CG/ScreenCaptureKit results, explicit request intent, and a cdhash-aware request ledger. A successful ScreenCaptureKit content query can establish current access despite a stale CG cache. That differs from trusting a persisted granted Boolean. The implementation should not be described as invariably requiring both APIs to return true simultaneously.

**A/E:** Droppy's preview appearance can request first camera access. DynamicIsland separates durable desired navigation settings from runtime activation and explicit first permission intent, and shares capture among navigation/Mirror owners. Startup permission UX should disclose actual current evidence, with no repeated request/relaunch loop.

No live permission prompt, TCC grant/denial, or relaunch recovery was exercised in this investigation.

## Media, capture and truthful presentation

**A:** Droppy's media adapter streams metadata but generic command dispatch uses private MediaRemote. Spotify position is separately polled using AppleScript. Progress UI previews during dragging and seeks on release. Optional ScreenCaptureKit analysis measures system-output RMS; bar presentation can still include decorative variation.

**E:** DynamicIsland guards scrub source/track/generation, emits one seek per release, and applies Spotify's 250ms end margin. Generic now-playing uses private MediaRemote too. Its call visualizer is a presentation animation, not a microphone or call meter.

**A/E:** Droppy's inspected capture feature makes element/rect screenshots. DynamicIsland has a movie recording engine with host-clock duration, pause exclusion, and a 5s no-frame guard. A static-frame writer test is present; no recording tests or live recording were run here. Public-source absence of named movie-writing mechanisms is not proof that the shipped app lacks recording.

**A/E:** Droppy connects via IOBluetooth callbacks but reads battery through undocumented selectors and substitutes 100% when unknown. DynamicIsland's view shows a percentage only from a supplied valid value; otherwise it preserves unknown/connected status. This establishes stricter presentation truthfulness, not broader device support.

## Privacy, persistence and motion

**A:** Notification source contains an unconditional title/subtitle/body print and uses `Date()` for the captured record rather than the database delivered timestamp. No live log collection was attempted because it could expose unrelated personal content.

**A:** Clipboard source includes exclusion preferences, change-count polling, coalesced atomic saves, backup handling, metadata-preserving deduplication and protection against unexpected empty overwrite. The corresponding complete DynamicIsland retention contract was not investigated; there is no superiority finding for this subsystem.

**A/E:** Both products have native motion adaptation. Droppy explicitly considers refresh rate, energy context and Reduce Motion; DynamicIsland already has motion/refresh primitives and existing public Droppy attribution. Future work should preserve current tokens, direct feedback, interruption continuity, semantic control sizes, and accessibility. Web styling libraries or copied timing tables are unnecessary.

# Shipped Binary vs Public Source Differences

**Not determined.** The requested downloaded app is unresolved. Matching version metadata from excluded Debug bundles does not prove source equivalence, build equivalence, feature equivalence, or provenance of a released executable.

No target imports, symbols, strings, addresses, call references, entitlements, signature identity, runtime transitions, or target-specific REA sessions were obtained. Consequently:

- Material shipped/public differences: unknown.
- Shipped behaviors absent from public source: unknown.
- Dedicated shipped hand navigation, FaceTime subsystem, or movie recorder: unknown.
- Timer/event implementation differences: unknown.

Once the exact free app is identified, begin with metadata, executable hash and signature/entitlements. Observe accessible free features normally with synthetic data. Then use REA only for discrepancies, such as notification wake-up, frame ownership, fullscreen imports or permission checks. If source, observation and binary evidence conflict, retain the conflict. Stop the relevant question if analysis needs a bypass or cannot distinguish its code path.

# Things DynamicIsland Already Does Better

The following are bounded **source-contract comparisons**, not product-wide runtime rankings:

1. Independent camera/Mirror/navigation ownership and explicit first-permission intent rather than view appearance owning all capture.
2. Exact Messages chat targeting and outgoing database confirmation; uncertain outcomes retain drafts.
3. Separate evidence versus call-control authority: current FaceTime mappings expose neither verified calls nor unsupported actions.
4. Current capture evidence, build-identity recovery, static-screen timeline and pause-aware movie duration.
5. Generation-scoped local camera input, explicit transient ownership, and protected semantic collapsed expansion.
6. Track/source-aware one-release seek and Spotify end protection.
7. Unknown battery remains unknown rather than a fabricated percentage.

Private media/brightness APIs and existing Droppy-derived motion references remain qualifications. No blanket claim of public-only APIs, superior smoothness, or fully proven physical camera gestures is justified.

# Techniques Worth Reimplementing Independently

These are **behavioral specifications**, not implementation recipes extracted from a binary:

- Distinguish rendered shell bounds, event interception bounds, and hover entry/maintenance bounds. Passive previews should not steal unrelated clicks.
- Preserve multiple independent camera consumers, truthful actual-running diagnostics, explicit permission intent, and final-owner release. DynamicIsland already implements these contracts; harden acceptance rather than duplicate them.
- Treat all notification triggers as hints to one deduplicated database fetch, with backup recovery and content-free diagnostics. Much of this already exists.
- If users need it, offer an explicitly permitted system-output level meter. Label its scope accurately and keep decorative animation independent.
- If useful, add independent AX-assisted element screenshot selection with correct display/backing-scale transforms and capture permission evidence.
- Review clipboard exclusion/retention, dedup metadata, atomic persistence and recovery as product requirements before selecting changes.
- Preserve top anchoring, interruptibility, Reduce Motion functionality and energy-aware effect budgets using existing native primitives.

These directions use platform mechanisms visible in source, but individual dependencies require an API-support inventory. ScreenCaptureKit, AVFoundation, Vision, CoreAudio, AppKit and Accessibility use should not legitimize unrelated private MediaRemote, CGS, battery-selector or brightness assumptions.

Apple's current documentation confirms ScreenCaptureKit exposes screen/audio streaming and lists macOS 12.3 framework availability. Vision's hand-pose request lists macOS 11.0 availability and a configurable maximum hand count. These establish public framework candidates, not permission grants or shipped Droppy behavior. Individual newer symbols still need deployment-target checks. [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [VNDetectHumanHandPoseRequest](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest).

# Techniques We Should Avoid

- Returning cached permission true as if it overrides a current denied/unavailable capability.
- Inventing battery values, call states, elapsed timestamps or successful send confirmation.
- Logging notification bodies or substituting observation time without labeling timestamp provenance.
- Depending on private CGS Space metadata, undocumented battery selectors or popover class names as durable contracts.
- Treating Darwin bulletin names and Notification Center database schemas as stable documented interfaces.
- Inferring physical gesture correctness, measured latency or shipped features from public source constants/tests.
- Copying proprietary decompilation/assets, transplanting exact functions, or extending existing source borrowing under a “clean-room” label.
- Adding more timers or removing backup polling without workload and recovery measurements.
- Requesting capture permission solely to decorate an animation.

DynamicIsland's existing private MediaRemote/brightness paths should be inventoried with the same rigor, not exempted from this assessment.

# Recommended Roadmap

All roadmap entries are **D: proposals**. This phase authorizes no implementation.

| Priority | Proposed independent improvement | Acceptance / dependency |
|---|---|---|
| P0 | Finish target identification and paired black-box/REA validation | Exact free-app path, version/hash, repeated controlled tests; no substitute Debug build |
| P0 | Package-level gesture/ownership acceptance ledger | Repeated palm swipes, collapsed pinch, morph survival, local pointer, physical priority, shared camera owners; numeric evidence only |
| P0 | Capability/privacy inventory | Classify public/private/undocumented paths; distinguish observation, action and confirmation; no content logs or invented readings |
| P1 | Notification resilience validation | Same record via Darwin/file/poll once; missing Darwin still works; schema/path failures and truthful timestamps; measure event latency |
| P1 | Passive-preview and interaction-frame audit | Click-through passive hover, bounded actionable growth, protected controls, fixed top anchor; native runtime measurements |
| P1 | Permission/recovery acceptance | First prompt explicit; current API authority; denied/stale/relaunch states; no loops; retain existing recording identity handling |
| P1 | Clipboard persistence/privacy comparison | Synthetic items only; exclusions, retention, dedup metadata, crash/empty-save recovery; establish current DI behavior first |
| P2 | Optional system-output meter | User value established, explicit permission, honest output-level labeling, bounded work and owner cleanup |
| P2 | Optional element screenshot capture | Public API support verified, AX unavailable fallback, display-scale correctness, no guessed private-control authority |
| P2 | Multi-display/energy/motion acceptance | Public fullscreen limits, mixed refresh, Reduce Motion/transparency, idle/active CPU and memory measured on matched scenarios |

# Unresolved Questions

1. **Does the shipped binary differ materially from public source?** Unknown until the actual app is identified and selectively inspected.
2. **Which subsystems are event-driven versus polling?** Source scheduling is mapped above; the shipped implementation remains unverified.
3. **What makes interaction responsive?** Source shows top anchoring, widened entry zones, state-sensitive interception and delayed rechecks. Actual feel/timing is unmeasured.
4. **How are conflicts prevented?** Public source uses layered geometry/drag/menu/HUD exceptions; DynamicIsland uses more explicit scoped ownership. Comparative failure rates are unknown.
5. **Which permission flows are more resilient or simpler?** DynamicIsland's current evidence/identity contracts are stronger on inspected paths. Simplicity and shipped UX are unmeasured; Droppy's actual screenshot path still preflights.
6. **Which public mechanisms can be independently used?** AppKit window/events, screen geometry, AVFoundation sharing, Vision, CoreAudio callbacks, ScreenCaptureKit capture/output analysis and AX-assisted selection are candidates. Private dependencies must be separated.
7. **Are shipped behaviors missing from public source?** Unknown; bounded source searches cannot answer this.
8. **Where is DynamicIsland more rigorous?** Exact messages, conservative call authority, owner/generation contracts, recording timeline/identity and truthful unknown battery presentation, based on A/E evidence.
9. **What should not be copied?** Cached-grant authority, synthetic battery values, content logging, private Space/battery assumptions, guessed control authority and proprietary code/assets.
10. **Highest-value improvements?** The ten roadmap items prioritize validation and existing-contract hardening before optional feature additions.

The exact downloaded/free Droppy.app path is the immediate user gate. Once supplied, normal launch may also encounter a license or physical-permission boundary; no bypass is authorized. CPU/memory, animation timing, scroll/hover/activation behavior, multi-monitor/fullscreen behavior and failure/recovery testing remain unperformed. Optional REA native-provider availability has not been established against a target.

# Evidence Appendix

Roots: **A** = `/Users/makeiteasy3/Documents/Droppy/`; **E** = `/Users/makeiteasy3/Documents/DynamicIsland-main/`. Numbers below are source line anchors at the recorded SHAs. No target binary addresses exist in this investigation.

| Reference | Concise source anchors |
|---|---|
| A1 — window/geometry | `Droppy/NotchWindowController.swift:186` setup; `:216` creation; `:1231` height envelope; `:1239` top-preserving resize; `:2270` panel; `:2823` key eligibility. `Droppy/NotchLayoutConstants.swift:26`. `Droppy/NotchShelfView.swift:158`, `:455`, `:546`, `:768`, `:813`. `Droppy/DroppyState.swift:126`, `:156`, `:171`, `:182`, `:354`. |
| A2 — interaction/gestures | `Droppy/NotchWindowController.swift:156`, `:166`, `:653`, `:1035`, `:1748`, `:1932`, `:1960`, `:2582`. `Droppy/NotchShelfView.swift:1630`. |
| A3 — camera | `Droppy/Extensions/Camera/CameraManager.swift:43`, `:48`, `:89`, `:105`, `:121`, `:163`, `:166`, `:179`. `Droppy/Extensions/Camera/SnapCameraShelfPanel.swift:33`, `:57`, `:123`, `:142`, `:173`, `:223`. Bounded Swift search for named hand-pose/navigation/pinch/global-warp mechanisms returned no matches. |
| A4 — notifications | `Droppy/Extensions/NotificationHUD/NotificationHUDManager.swift:72` fallback; `:81` coalescing; `:106` start; `:145` file events; `:229` Darwin; `:296` paths; `:323` read-only DB; `:366` fetch; `:441` content print; `:448` observation timestamp. |
| A5 — permissions/capture | `Droppy/PermissionManager.swift:41` grace; `:87` AX; `:115` cached AX fallback; `:163` polling; `:189` screen getter; `:215` cached grant; `:220` request. `Droppy/Extensions/ElementCapture/ElementCaptureManager.swift:231` pointer cadence; `:505` setup check; `:820` AX bounds; `:1161` capture; `:1164` preflight; `:1167` request; `:1178` SC enumeration. |
| A6 — media/audio | `Droppy/MusicManager.swift:964` adapter; `:1127` debounce; `:1319` reconciliation; `:1378` private commands; `:1458` seek. `Droppy/SpotifyController.swift:195`, `:369`, `:390`, `:407`. `Droppy/MediaPlayerView.swift:835`, `:845`. `Droppy/MediaPlayerComponents.swift:357`, `:360`, `:367`. `Droppy/SystemAudioAnalyzer.swift:61`, `:67`, `:79`, `:118`, `:123`, `:254`. `Droppy/AudioSpectrumView.swift:98`, `:116`. |
| A7 — devices/HUD | `Droppy/AirPodsManager.swift:59`, `:131`, `:238`, `:279`, `:291`. `Droppy/VolumeManager.swift:275`. `Droppy/BrightnessManager.swift:312`, `:337`, `:541`. `Droppy/HUDManager.swift:20`, `:39`, `:93`, `:195`, `:221`. |
| A8 — clipboard/shelf | `Droppy/ClipboardManager.swift:330`, `:337`, `:587`, `:611`, `:632`. `Droppy/ShelfView.swift:37`. `Droppy/DroppyState.swift:439`, `:451`, `:512`, `:597`. |
| A9 — settings/motion/fullscreen | `Droppy/UserPreferences.swift:16`, `:249`, `:317`. `Droppy/SettingsWindowController.swift:35`. `Droppy/DroppyAnimation.swift:20`, `:29`, `:54`, `:78`, `:92`, `:476`. `Droppy/AppKitMotion.swift:14`, `:55`, `:102`, `:155`. `Droppy/Utilities/CGSShims.swift:9`. `Droppy/NotchWindowController.swift:1127`, `:1596`, `:2746`. |
| E1 — geometry/motion | `Sources/DynamicIsland/Overlay/OverlayWindowController.swift:204`. `Sources/DynamicIsland/Geometry/NotchGeometryService.swift:6`. `Sources/DynamicIsland/Views/WorkspaceMotion.swift:1` attribution; `:24` adaptation. |
| E2 — hover/protection | `Sources/DynamicIsland/Modules/CollapsedActivityHoverPolicy.swift:4`. `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift:215`. `Sources/DynamicIsland/Overlay/OverlayWindowController.swift:367`. |
| E3 — camera/input | `Sources/DynamicIsland/Modules/CameraPreviewController.swift:145`, `:160`, `:309`, `:355`, `:647`. `Sources/DynamicIsland/Modules/HandPoseFrameProcessor.swift:6`, `:25`, `:77`, `:108`. `Sources/DynamicIsland/State/HandNavigationObservation.swift:206`, `:228`. `Sources/DynamicIsland/State/CameraNavigationController.swift:405`, `:515`. `Sources/DynamicIsland/Overlay/CameraInteractionRouter.swift:20`, `:145`, `:164`. Tests: `CameraGestureModeTests.swift:43`, `:64`, `:76`, `:86`, `:98`; `CameraPreviewControllerTests.swift:453`, `:595`, `:637`; `CameraNativeRoutingTests.swift:102`, `:128`, `:152`, `:176`, `:220`, `:257`, `:272` under `Tests/DynamicIslandTests/`. |
| E4 — notifications | `Sources/DynamicIsland/Messaging/SystemNotificationMonitor.swift:7`, `:98`, `:145`, `:205`, `:239`. `Tests/DynamicIslandTests/CommunicationsIntegrationTests.swift:145`, `:161`. |
| E5 — communication/authority | `Sources/DynamicIsland/Messaging/MessagesAppAdapter.swift:9`, `:184`, `:225`. `Sources/DynamicIsland/Messaging/MessagingController.swift:360`. `Sources/DynamicIsland/Communications/FaceTimeAccessibilityProvider.swift:5`, `:78`, `:119`, `:160`. `Sources/DynamicIsland/Views/AgentCompactPermissionView.swift:4`, `:129`. `Sources/DynamicIsland/Views/NativeTerminalHost.swift:52`. `Tests/DynamicIslandTests/MessagesReplyAuthorityTests.swift:94`, `:122`, `:143`, `:157`, `:195`. |
| E6 — recording | `Sources/DynamicIsland/Modules/ScreenRecordingController.swift:65`, `:99`, `:204`, `:283`, `:422`, `:585`. `Sources/DynamicIsland/Modules/ScreenRecordingEngine.swift:113`, `:303`, `:364`. `Tests/DynamicIslandTests/ScreenRecordingAccessTests.swift:78`, `:109`, `:147`; `ScreenRecordingWriterTests.swift:7`. |
| E7 — media/visualizer | `Sources/DynamicIsland/Modules/MediaScrubState.swift:5`, `:72`. `Sources/DynamicIsland/Modules/MediaController.swift:409`, `:738`, `:753`. `Sources/DynamicIsland/Modules/NowPlayingMediaProvider.swift:321`. `Sources/DynamicIsland/Views/ModuleViews.swift:14`. `Sources/DynamicIsland/Views/CollapsedCommunicationViews.swift:23`. `Tests/DynamicIslandTests/MediaScrubStateTests.swift:154`, `:168`, `:241`. |
| E8 — HUD/battery | `Sources/DynamicIsland/Modules/SystemHUDController.swift:990`, `:1060`. `Sources/DynamicIsland/Views/AudioDeviceModelView.swift:4`, `:29` prior attribution. |

Environment evidence retained outside the repository:

- `/tmp/droppy-investigation-rea-capability.json`: target-free REA doctor result, production stdio, identity/catalog/request verification; no Droppy binary evidence.
- `/tmp/droppy-investigation-rea-capability.stderr`: empty transport stderr.
- `/tmp/droppy-investigation-start-status.bin`: initial NUL-delimited Git status.
- `/tmp/droppy-investigation-start-hashes.json`: initial SHA-256 values for 379 individually listed pre-existing dirty/untracked files. Directory entries are excluded from that hash coverage.
- `/tmp/droppy-investigation-apple-sck-primary.md` and `/tmp/droppy-investigation-apple-hand.md`: Apple documentation Markdown for framework availability/API scope. Agent Reach's Jina web route also retrieved the ScreenCaptureKit page. A separate AX documentation URL returned 404; no new AX availability conclusion relies on it. Agent Reach 1.5.0 reported current; no tool update occurred.

Review: scoped Ponytail/Apple Design/Taste evidence review completed against DynamicIsland `1cd01b4d3a90b49f497176d0c9c19f91eda904a1` and Droppy `dd2d16ccbdc6aa22b456e199442b43a07aa446af`. Checked authority distinctions, source-versus-runtime labels, ownership comparisons, privacy boundaries and native-motion interpretation. No runtime, physical-device, build, test, package, or CI validation is claimed for this documentation-only phase. PR #31/#32 were not updated.

Preservation verification: all initial Git status entries remain present and unchanged; the only addition is the untracked report directory. All 379 recorded individual file hashes match; no staged changes exist; DynamicIsland branch/HEAD and the public Droppy tracked working tree are unchanged. Source anchor files exist and referenced line numbers are in range. The new report has no whitespace errors in the standalone diff check. Directory-only entries were not recursively hash-verified.
