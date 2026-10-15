# Per-application volume — architecture decision (updated 2026-10-15, real-gain repair)

## Decision

Per-app gain uses supported Core Audio process taps (macOS 14.2+) with **minimal intervention**. An app at 100% is never touched. One row is one **application**, not one process (see "Why the first version did nothing"). When the user moves an app's slider below 100%, `ApplicationGainEngine` creates three objects for that application:

1. A private `CATapDescription(processes:andDeviceUID:withStream:)` tap of **every audio process the app owns** (main process and helpers) on the default output's first output stream, with `muteBehavior = .mutedWhenTapped`. It is the device stream's own format: no downmix, and audio the app plays to another device is left alone.
2. A private aggregate device. Its main sub-device is that output device (the clock). It holds the tap with drift compensation and has no tap auto-start.
3. An IOProc that copies the tap's channels × a ramped gain into the device's output channels. The tap is the aggregate's last input buffer: a virtual route's own input comes first.

Moving the slider back to 100% stops the IOProc and destroys the IOProc, aggregate and tap, in that order. The app then plays directly again.

When a helper process starts or exits, the session is rebuilt make-before-break: the new tap (same app, new process set) is created and its IOProc prepared, the old replay ramps to silence, the new one starts, then the old objects are destroyed. The app stays muted throughout (two taps may mute the same process), so there is no 100% leak and no doubled playback.

## Why the first version did nothing (root causes, measured 2026-10-15 on macOS 15.7)

1. **The route was declined.** The default output was `BoomAudio` (transport virtual, 6 channels, one input stream: a loopback). `hasInputStreams` declined it as "a microphone", so every slider move failed. The gated live test skipped itself on exactly that check (`1 test skipped`), so the suite stayed green. Virtual loopback outputs are now routable; real microphones (built-in input, USB or Bluetooth headsets, AirPods) are still declined.
2. **Rows pointed at the wrong process.** Real apps play from helpers: Discord's audio is `com.hnc.Discord.helper.Renderer` while `com.hnc.Discord` has output off; a Chromium browser's sound is a `Brave Browser Helper` utility audio process and the main browser process has no HAL audio object at all; WebKit uses a GPU XPC service. The old row targeted one process and was named by bundle ID (`com.brave.Browser.helper`) because helpers have no running-application name. Rows are now grouped under the owning app (executable path → outermost `.app`, bundle-ID prefix, WebKit service name) and the tap covers all of its processes.
3. **A stereo mixdown tap carried 1/3 of the true level on a 6-channel route.** Measured at the device: tone amplitude 0.0999 played, 0.0333 in the `stereoMixdownOfProcesses` tap, 0.0999 in the device-stream tap. The earlier acceptance only compared tap input with IOProc output, never with the direct level, so the slider would have dropped the volume by 9.5 dB the instant it left 100%. The stream tap measured unity on both 2-channel (0.049 for 0.05) and 6-channel routes.
4. The hypothesis that the aggregate or the IOProc never ran was **false**: with a measuring IOProc the aggregate output was exactly tap × gain on both routes.

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
- **No microphone.** Real outputs that also expose input streams (headsets, AirPods) are declined before any tap, because the aggregate would include their input. A virtual loopback output (Boom, BlackHole, Loopback) is accepted: its input is a loopback, not a microphone. DynamicIsland's own process is never listed or tapped, so there is no feedback.
- **Real-time code.**
  - The IOProc does no allocation, logging, I/O or blocking. It reads the target through a non-blocking try-lock, the same pattern as the spectrum mailbox.
  - Formats are validated as Float32 linear PCM with 1–2 tap channels.
- **Permissions.** No permission is requested at launch. The first slider move below 100%, after the user turned the feature on, may show macOS's System Audio Recording prompt. No audio is stored.

## Scope of v1

- Supported outputs: built-in speakers, HDMI/DisplayPort, most DACs, AirPlay outputs that expose no input, and virtual loopback outputs. Outputs with a microphone show an explicit unsupported message.
- Levels persist per application bundle ID (the owning app's, not a helper's). Standalone processes without a bundle ID always start at 100% and their levels aren't saved.
- A helper process that appears after the last refresh (the HAL list listener plus a 150 ms debounce) plays at 100% until the session is rebuilt to include it. After the rebuild it is attenuated (live test step 2).
- WebKit's GPU service has no executable path inside an app. It is attributed by the Launch Services name ("<App> Graphics and Media") when that app is running; otherwise it stays its own row. This is **unverified with Safari playing**. Slider position *p* maps to amplitude *p²*: mid-slider is about −12 dB, closer to perceived half-loudness.
- The feature is **off by default** ("Turn On Per-App Volume (Experimental)" in the App Volume widget) until the live acceptance test below has run on real hardware.

## Live acceptance gate

`DYNAMIC_ISLAND_LIVE_APP_VOLUME=1 swift test --filter ApplicationGainLiveTests` runs three real-hardware checks. All play quiet tones, so they need explicit approval and may prompt for System Audio Recording:

- Four `afplay` processes (two helpers of one app, one other app, one late helper): the grouped app is attenuated together while the other app keeps its own level, a late helper is attenuated after the tap rebuild with no doubling, 0% silences only that app, 100% releases, and no tap or aggregate is left behind. It measures inside the real IOProc (tap peak vs output peak) and, on a loopback route, the tone energy that reaches the device.
- A throwaway Brave instance (own profile) plays a tone from its audio helper; the "Brave Browser" row owns that helper and the tone follows 50% / 0% / 100%.
- A read-only grouping check of the real HAL process list.

The test no longer hides a declined route as a pass: it is still skipped for a microphone route, but the default virtual and built-in outputs run.

The listening checks (measurements are not ears) are in the PR description:
- only the chosen app gets quieter, including apps that play from helpers (Discord, a browser tab, Spotify);
- 0% silences only that app, with no duplicate or echoed audio;
- 100% is unchanged and quitting the app or DynamicIsland restores normal sound;
- the master volume stays independent;
- an app restart and an output-device change keep or restore the level.
