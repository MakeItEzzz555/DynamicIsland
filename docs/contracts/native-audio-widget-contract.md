# Native audio widget contract — revision 2

Baseline: PR #32 HEAD `1cd01b4d3a90b49f497176d0c9c19f91eda904a1` **plus the current uncommitted DynamicIsland-main rescue/Settings/camera work**. Development branch: `feature/native-audio-foundation`, separate worktree `/Users/makeiteasy3/DynamicIsland-worktrees/native-audio-foundation`. The original checkout, index, running app and permissions are not integration targets for this phase.

## Ownership and Swift authority

Claude owns views, semantic widget sizes, animation, interaction, artwork and native icon rendering. Codex owns capture, DSP and audio routing. The compiled signatures live in `Sources/DynamicIsland/Audio/NativeAudioContract.swift`; use these types rather than defining a parallel view model.

| Surface | Interface | Authority / fallback |
| --- | --- | --- |
| Eight spectrum bands | `AudioSpectrumFrame.bands: SIMD8<Float>` | Ascending logarithmic 40 Hz–min(12 kHz, Nyquist-safe upper bound), finite 0…1. No callback Array allocation. `sequence` changes per analyzed frame; `hostTime` is monotonic mach host ticks, not wall-clock playback time. |
| Energy | `rms`, `peak`, `hasSignal` | RMS/peak linear full-scale 0…1 from actual buffers. No microphone, call-level or participant claims. |
| Capture | `LiveSpectrumProviding` / `AudioSpectrumPresentation` | Instantiation, previews and subscriptions are inert. Only `startFromUserAction()` can initiate permission-sensitive work. `.capturing` requires observed buffers, not merely successful tap creation. On disable/suspension/error clear frame; decorative fallback may continue but must be labelled non-live. |
| Permission | `AudioCapturePermission` | `.notVerified` is deliberately not “not determined”: no public TCC query is claimed. `.denied` requires an explicit access error; silence/no frames never proves denial. `.accessEstablished` requires actual non-silent captured signal in this process, not merely callbacks or a durable TCC grant; silent buffers keep permission notVerified. |
| Playback | `AudioPlaybackEvidence` | Signal/silence pertains to the captured system mix only. MediaController remains authority for playing/paused/source metadata; silence must never mark Spotify paused. |
| System volume/mute | `SystemVolumeProviding` | Observation may have nil volume/mute for unreadable hardware. Use output identity including generation in every request; only read-back establishes `.verified`. Unsupported writes leave native media keys unconsumed. |
| Output device | `NativeAudioOutputDevice` | Stable UID plus transient device ID/generation, name, transport, separate volume/mute read/write capabilities. HDMI/AirPlay/Bluetooth are not assumed writable. |
| Application output | `ApplicationVolumeProviding` | Only actual output-process activity may populate rows. PID/process object IDs/generation protect against PID reuse. Name, bundle ID and bundle URL support native app identity/icon; unresolved identities stay unresolved. |
| Per-app gain | `requestGain` | Gain is nil and controlAvailable false until a real routed path exists. No visual-only slider is a genuine volume control. `.verified` requires actual gain application; failure leaves ordinary output intact. Natural/Linear curves remain unspecified until implemented and tested. |
| Errors | `NativeAudioError` / `AudioVolumeWriteResult` | Finite input 0…1, generation-scoped requests, superseded coalesced writes, explicit unsupported/failure. OSStatus diagnostics contain operation/status only, never audio or other app content. |

All UI-facing state and Combine publication are MainActor-owned. Audio/DSP/capture work runs off MainActor. Presentation is throttled independently; old frames do not build up. An immutable fixed-size latest-frame mailbox may drop a publish when busy, never block the audio thread on UI ownership. Stop/shutdown must invalidate generations before asynchronous teardown, so late frames cannot relight a disabled widget.

## Availability by slice

The spectrum implementation is `AudioSpectrumController` + actor-owned `CoreAudioSpectrumBackend` + `RealtimeSpectrumProcessor`. Native capture acceptance is permission-gated and has not run; synthetic DSP/lifecycle evidence is separate. System-volume and per-app protocols remain **contracts, not claims of implemented services**. Existing SystemHUDController keeps its verified three-stage native volume write ladder and key pass-through; external-change/coalescing changes are a separate follow-up. Per-app gain remains unavailable until a safe replacement-output path is tested. No private lock-screen surface is enabled.

## Exact integration handoff (do not edit shared views concurrently)

1. Add an app/controller-owned `AudioSpectrumController` after this backend is delivered. Keep it out of SwiftUI onAppear. Supply it to Claude's widgets as `LiveSpectrumProviding` (concrete ObservableObject or `presentationPublisher`).
2. The explicit **Live Audio** enable action calls `startFromUserAction()`. Disable calls `stop()`. Do not start it during preview, app launch or media detection. Do not persist a second runtime “enabled” truth.
3. Paint `frame.bands` only while availability is capturing. Use `hasSignal` for silence; use MediaController for media playback. Never claim decorative fallback measures audio.
4. Connect app termination to awaited `shutdown()` using the existing termination policy: if asynchronous cleanup is needed, return AppKit `.terminateLater` and reply only after cleanup; merely launching a Task from `applicationWillTerminate` cannot guarantee completion. Sleep/session suspension stops capture. Resume requires explicit user action to avoid permission retry loops. Host teardown must await shutdown before dropping its service.
5. Adopt the isolated `Scripts/package_app.sh` usage-description patch; standalone `swift run` is not a permission-acceptance package. Stable signing identity is recommended for later TCC acceptance; this work does not change signing identities/permissions.
6. System volume and application volume protocols require their respective production implementation milestones before enabled sliders are connected. Keep unavailable controls disabled with an explanation.

No patch to IslandRootView, ModuleViews, camera, Tray or Agent views is part of this branch. Rescue/Settings files are present only as **uncommitted test-baseline overlays**, never staged or published by Codex.

## Research boundaries / primary authority

The supplied Droppy reports label 16.0.1 binary observations **O**, inference **I**, February-source-only **S**, and unknown **U**. Process tap/FFT imports are observed; inferred smoothing semantics, exact volume curves and private-lock behaviors are not API authority. No proprietary implementation/constants/assets are transplanted.

Apple APIs: [system audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), installed CoreAudio `AudioHardwareTapping.h` (macOS 14.2 availability), `CATapDescription.h` (mute/privacy), `AudioHardware.h` (aggregate/IOProc ownership). No new package dependency is required; use native Accelerate, CoreAudio, Combine and AppKit lifecycle signals.

Revision 2 resolves the existing MediaAdvancedControls.AudioOutputDevice name collision without modifying that module; use NativeAudioOutputDevice for capability/generation-aware observations. The initial contract SHA a063866 is superseded for integration by the verified revision-2 commit.
