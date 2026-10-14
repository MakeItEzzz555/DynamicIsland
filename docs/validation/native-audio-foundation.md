# Native audio foundation — verified backend slice, 2026-10-14

## Ownership / preservation

Development worktree: `/Users/makeiteasy3/DynamicIsland-worktrees/native-audio-foundation`, branch `feature/native-audio-foundation`, base `1cd01b4d3a90b49f497176d0c9c19f91eda904a1` (PR #32, still open). The canonical checkout's uncommitted rescue/Settings/camera sources, tests and scripts were copied as an **unstaged integration baseline**. They are not included in audio commits. No view, Agent, camera, Tray, Settings layout or SystemHUDController source was edited. The legacy checkout was read only for branch/HEAD identification.

Canonical preservation manifest: `/tmp/dynamicisland-audio-original-preservation.json`. Verification: 1,928 tracked/untracked files unchanged, none missing, canonical HEAD and index unchanged. The original running package remains PID 87449; it was not replaced, quit or relaunched. No TCC grant/reset, driver install, audio device creation, private framework activation or actual audio capture occurred.

Ordinary fetch encountered pre-existing missing commit-graph/checkpoint objects. A command-local commit-graph-disabled fetch also failed on an existing Codex checkpoint ref. No checkpoint ref/object was removed or repaired. Normal isolated-branch pushes succeeded with command-local `core.commitGraph=false`; the repository's saved configuration was not changed.

## Delivered

- `Audio/NativeAudioContract.swift`: fixed eight-band frames, energy, capture/permission/playback evidence, generation-scoped device/application identity, capabilities, publisher and write-result contracts. Revision 2 resolves the existing AudioOutputDevice collision using NativeAudioOutputDevice. The initial standalone contract check did not expose that collision; whole-app compilation did, and it was corrected without editing MediaAdvancedControls.
- `Audio/RealtimeSpectrumProcessor.swift`: original Accelerate/vDSP implementation, 2048-point Hann FFT, 512-sample hop, eight log bands from 40 Hz to min(12 kHz, 0.48 × sample rate), stereo power combination that does not cancel antiphase audio, RMS/peak, finite full-scale saturation, silence gate, time-based 25 ms attack/180 ms release, bounded 3 dB treble tilt, bounded gain normalization and transient response. High sample rates may have no FFT bins in the lowest band; those bands remain zero rather than aliasing another band.
- `AudioSpectrumMailbox`: one fixed-size immutable frame, no backlog. The IOProc writer uses try-lock/drop, never waits for a UI reader. Scratch buffers/FFT storage allocate before device start; the callback does no disk/network/UI work or audio Array construction. This is a source-path audit, not an Instruments allocation trace of a live callback.
- `Audio/CoreAudioSpectrumBackend.swift`: actor-owned public CATapDescription/process tap, **private unmuted** tap-only aggregate, Float32 format validation, direct HAL IOProc, configuration listeners, exact resource cleanup/retry and generation-scoped stop. The actual tap UID's retained CF object is released correctly. It never selects an output device or mutes/replaces ordinary playback.
- `Audio/AudioSpectrumController.swift`: inert initialization/subscription, explicit user start, generation-safe async completion, bounded approximately 30 Hz MainActor publication, two-second no-frame/stall watchdog, sleep/session-inactive/configuration suspension, immediate presentation clearing, and awaited outstanding start/teardown work on shutdown. Suspension of an off service stays off. Resume is explicit to avoid permission retry loops. No public TCC preflight is claimed; silent buffers cannot establish permission or player pause.
- `Scripts/package_app.sh`: honest NSAudioCaptureUsageDescription added to the sole production Info.plist generator. No entitlement/dependency/schema change.
- `docs/contracts/native-audio-widget-contract.md`: Claude/Codex ownership and exact composition-root handoff, including asynchronous AppKit termination sequencing. No shared integration/view file was patched.
- `docs/research/lock-screen-implementation-decision.md`: public-session signal limitations, private SkyLight/MIT/distribution/privacy distinction, supported desktop alternative and explicit approval gate. No library installed or private API enabled.

## Verification

Final focused run (`/tmp/dynamicisland-native-audio-focused.log`): **64 passed, 0 failed, 0 skipped**, 4.757 seconds. Includes 18 new audio cases plus existing System HUD arbitration, notch routing, detached navigation and gesture coordinator cases.

The audio cases cover sixteen sine-frequency points over eight bands at 44.1/48 kHz; silence/transient/release/finite bounds; antiphase/right-only stereo; planar/interleaved buffer equivalence; Nyquist/unsupported rates; invalidated mailboxes; native unmuted/private description; every startup failure stage; idempotent teardown/stale generations; failed-teardown retry; explicit start/inert subscription; permission denial/no retries; silent permission uncertainty; frame-loss watchdog; stale async start; sleep/configuration suspension; and shutdown waiting for prior teardown.

Measured Debug synthetic 512-frame processing: **851.325 µs mean / 943.667 µs p95**, 1000 blocks, versus 10,666 µs of audio time at 48 kHz. This measures CPU DSP time only, not live HAL latency, total app CPU/memory, callback allocations or perceived animation smoothness.

Broader suite (`/tmp/dynamicisland-native-audio-full.log`): **2,443 cases: 2,399 passed, 42 skipped, 2 failed cases / 4 assertion failures**, 196.733 seconds. The failures reproduce the previously recorded `IslandKeyboardAcquisitionTests.testResignKeyReleasesEngagementWithoutDestroyingDraft` and `testReturnShiftReturnDeleteAndRepeatedReopenUseExactEditor`. Their cause remains unresolved; no assertion was weakened or existing failure claimed fixed. All new audio cases passed.

Debug: passed, 4.40 seconds. Release: passed, 225.97 seconds. Relocated cloned module caches initially produced old-path PCH errors; only caches in the isolated copy were moved aside, and the actual builds were rerun successfully. No canonical build/cache was modified.

Isolated package: `/tmp/dynamicisland-native-audio-package-g5jbOi/DynamicIsland.app`. Package script passed; all three helpers strict signature and app deep/strict signature passed. Info.plist usage copy verified. Signing metadata: identifier com.local.dynamicisland, ad-hoc signature, flags 0x2; **hardened runtime is not enabled in this existing ad-hoc packaging path**. Developer ID/hardened-runtime/notarization and real capture TCC behavior are unverified. Package was not launched.

Graph query/AST refresh ran in the isolated copy only. Intended diff passes git diff --check. Ponytail review checked protocol callers, source-name collisions, opt-in/generation authority, stale cleanup, callback allocations/try-lock behavior, retained CF ownership, silent-access claims and view boundaries. Native acceptance is not replaced by these tests.

## Deferred / exact remaining gates

1. Claude must wire the app-owned AudioSpectrumController into the new widget and explicit Live Audio enable/Resume/disable actions using the final contract/backend commit. Existing visualizer views remain decorative until that integration; no live UI claim is made.
2. After that wiring, separately authorize a fresh appropriately signed packaged capture probe and any System Audio Recording permission action. Verify real samples, denied/revoked/no-signal behavior, device switching, private aggregate visibility, HAL CPU/memory/allocations, stop/sleep/session/termination cleanup and hardened-runtime behavior. No actual user/system audio was inspected for this phase.
3. System-volume external observation, echo suppression, off-main latest-value writes and Option+Shift fine steps are **not implemented in this slice**. The old verified ladder and hardware pass-through remain unchanged. The contract is ready; this is the next vertical milestone.
4. Per-app discovery, gain routing/ramping, dual playback prevention and restore-on-failure are **not implemented**. Do not enable per-app sliders; gain remains unavailable and no Natural/Linear curve is invented. Native multi-app/Bluetooth/AirPlay acceptance requires a separate safe proof.
5. Lock-screen private overlays remain unapproved/unimplemented. The decision document recommends ordinary unlocked-desktop surfaces.
6. No PR was created for the audio branch and no branch/PR was merged. Remote-head agreement is verified after pushes; CI for the backend branch is not claimed green. Ordinary fetch corruption and the two known keyboard failures remain separately documented.
