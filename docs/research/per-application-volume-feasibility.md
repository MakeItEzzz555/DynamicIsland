# Per-application volume — public API decision (2026-10-14)

## Evidence and decision

Apple documents process-specific output capture and process muting in [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps). The installed Xcode SDK's `CATapDescription.h` explains that `.mutedWhenTapped` leaves direct playback enabled until a client reads the tap, then suppresses direct hardware output for that reading period. [CATapMuteBehavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior) is capture/playback routing behavior, not a per-process scalar volume setter.

A supported capture → gain → replay path is technically possible; this is an architecture inference from those APIs, not a proven DynamicIsland mixer. The current spectrum aggregate is input-only and its unmuted tap cannot attenuate another app. Rendering independent sliders or multiplying analyzer samples would not alter speaker output. No genuine per-app gain widget is enabled.

`ApplicationAudioDiscovery` supplies manual, background, read-only HAL process discovery through the existing contract. It filters running output IO, bounds allocation, checks PID identity across reads, invalidates generations and leaves gain unavailable. HAL output IO can contain silence; `outputIOActive` is explicitly distinct from measured `outputActive`. It does not run at launch, poll, create devices/taps, request permissions, mute output or store samples. Tests use synthetic process records only. No microphone activity or personal audio is inspected.

## Safe routing acceptance gate

Before enabling gain, separately authorize process-specific tap reading with mutedWhenTapped and output replay on controlled hardware. Implementation must first prepare an unmuted tap plus replacement renderer (gain zero), validate channel/sample-rate format and actual renderer callbacks, then enable replacement/muting together. Whether changing tap descriptions can establish a truly atomic cutover remains UNVERIFIED and must be measured. Fail-open teardown must unmute/destroy the tap before removing output and retain ownership if destroy fails. Self-output must be excluded to prevent feedback.

Use a private aggregate sharing the selected hardware clock where supported; bounded buffers and sample-rate conversion may be necessary across clocks. Bluetooth/AirPlay latency, channel layouts, disconnects and drift are UNKNOWN until tested; initially decline incompatible devices rather than claim support. Verify multiple simultaneous apps, PID/object replacement, gain ramps, silence/transients, device changes, sleep/wake, crash recovery, repeated teardown, permissions and ad-hoc/Developer ID packaging. Persist no audio. Avoid a virtual driver, private API or unsupported macOS volume setter.

## Reference grades

- OBSERVED reference: user's desired independent app sliders; shipped Droppy report observations are behavioral comparisons only.
- PROVEN Apple/SDK: process-specific taps, mutable playback behavior, output-IO process properties.
- INFERRED: independent gain could use process capture with verified replacement replay.
- UNKNOWN: real cutover safety, crash fail-open behavior, latency/drift and supported-device matrix in this application.

Approval is needed for hardware mute/replacement acceptance. This gate does not block completed hover/menu/Tray/visualizer work. No restricted source, proprietary binary logic or assets were transplanted.
