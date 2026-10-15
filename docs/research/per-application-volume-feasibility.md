# Per-application volume — architecture decision (updated 2026-10-15)

## Decision

Per-app gain uses supported Core Audio process taps (macOS 14.2+) with **minimal intervention**. An app at 100% is never touched. When the user moves an app's slider below 100%, `ApplicationGainEngine` creates three objects for that one process:

1. A private `CATapDescription(stereoMixdownOfProcesses: [process])` tap, with `muteBehavior = .mutedWhenTapped` and `deviceUID` set to the current output.
2. A private aggregate device. Its main and only sub-device is that output device (the clock). It holds the tap with drift compensation and has no tap auto-start.
3. An IOProc that copies the tap's samples × a ramped gain into the device's output buffers.

Moving the slider back to 100% stops the IOProc and destroys the IOProc, aggregate and tap, in that order. The app then plays directly again.

## Alternatives considered

| Approach | Verdict |
|---|---|
| Virtual audio driver (BlackHole / HAL plug-in) | Rejected: it needs an installed driver, replaces the system default device, and needs admin rights and system-wide changes. |
| Changing a per-process volume property | Not available: no public per-process volume setter exists. `kAudioDevicePropertyProcessMute` mutes only the *calling* process. |
| One aggregate holding every tapped app | Rejected for v1: adding or removing an app would reconfigure a running device, which glitches every routed app. |
| Scaling analyzer samples or UI-only sliders | Rejected: they don't change speaker output. |
| **Per-app tap + private aggregate + IOProc (chosen)** | Uses only public APIs and no driver. One app's failure is isolated from the others, and failure returns that app to its own output. |

## Evidence

- **Proven from the SDK headers:**
  - `CATapMutedWhenTapped` sends audio to hardware "until the tap is read by another audio client", and only "for the duration of the read activity" is no audio sent (`CATapDescription.h`).
  - `stereoMixdownOfProcesses`, `isPrivate` and `deviceUID` are public.
  - The aggregate keys `master`, `subdevices` and `taps` with `drift` are public (`AudioHardware.h`).
- **Observed, behavioral only:** the earlier clean-room black-box report shows Droppy 16 builds the same pipeline (tap `stereoMixdownOfProcesses`, mixer cells with target/current gain and ramp). No Droppy code, assets or strings were used.
- **Proven in tests here:**
  - The real-time renderer, against synthetic buffer lists: gain, ramp, mute, channel mapping and zero-fill.
  - Engine call order, failure cleanup, retained objects when a destroy fails, the stall watchdog and app isolation, all with a fake HAL.
  - Provider persistence, relaunch re-apply and exited-app release.
- **Unverified (needs the gated live test and listening):**
  - Cutover glitch length.
  - Latency on Bluetooth and AirPlay.
  - Drift over long sessions.
  - Multichannel interfaces.
  - Behavior across sleep/wake on real devices.

## Safety properties

- **Fail-open by API design.** If our IOProc stops reading, through a stall or a crash, `.mutedWhenTapped` returns the app to the hardware. Private taps and aggregates belong to our process and are destroyed by the system when the process exits.
- **Watchdog.** The renderer counts render cycles. A session that doesn't advance between two checks (750 ms apart) is released, and the widget explains why.
- **Releases.** Default-output changes, sleep, disabling the feature and an app exiting all release the affected sessions. Saved levels are re-applied when the route or app returns.
- **No microphone.** Outputs that also expose input streams (headsets, AirPods) are declined before any tap, because the aggregate would include their input. DynamicIsland's own process is never listed or tapped, so there is no feedback.
- **Real-time code.**
  - The IOProc does no allocation, logging, I/O or blocking. It reads the target through a non-blocking try-lock, the same pattern as the spectrum mailbox.
  - Formats are validated as Float32 linear PCM with 1–2 tap channels.
- **Permissions.** No permission is requested at launch. The first slider move below 100%, after the user turned the feature on, may show macOS's System Audio Recording prompt. No audio is stored.

## Scope of v1

- Supported outputs have no input streams: built-in speakers, HDMI/DisplayPort, most DACs and AirPlay outputs that expose no input. Outputs with a microphone show an explicit unsupported message.
- Levels persist per bundle ID. Processes without a bundle ID always start at 100% and their levels aren't saved. Slider position *p* maps to amplitude *p²*: mid-slider is about −12 dB, closer to perceived half-loudness.
- The feature is **off by default** ("Turn On Per-App Volume (Experimental)" in the App Volume widget) until the live acceptance test below has run on real hardware.

## Live acceptance gate

Running `DYNAMIC_ISLAND_LIVE_APP_VOLUME=1 swift test --filter ApplicationGainLiveTests` routes a quiet `afplay` tone through the real engine on the current output. It checks that the real IOProc keeps rendering and that 100% releases the tap. It needs explicit approval, because it plays audio and may prompt for System Audio Recording.

The listening checks are in the PR description:
- only the chosen app gets quieter;
- 0% silences only that app;
- 100% is unchanged;
- the master volume stays independent.
