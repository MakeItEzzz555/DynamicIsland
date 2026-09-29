# System Presence HUD Phase — 2026-09-29

## Implemented scope

- One bounded transient HUD arbiter for volume, brightness, Caps Lock, battery transitions, and output-device changes.
- Same-kind events coalesce in place.
- Higher-priority transient events preempt lower-priority events without deleting persistent Media/Timer/Agent activities.
- Stale dismissal generations cannot remove newer transient HUDs.
- Caps Lock is observed through modifier-flag changes and never intercepts normal typing.
- Battery HUDs reuse BatteryActivityProvider and publish only meaningful state/threshold transitions.
- Default output changes are observed through CoreAudio; only the actual CoreAudio device name is shown.
- No AirPods/earbud battery values are displayed because this phase has no reliable public battery source.
- Settings previews are sandbox-only and reuse the production compact HUD renderer.

## Focus / Do Not Disturb

Focus observation uses Apple's public INFocusStatusCenter API from Intents. The app requests Focus Status permission only when the Focus HUD setting is enabled and observes the authorized focusStatus value.

The public status provides generic focused/unfocused state, not the user's named Focus mode. DynamicIsland therefore renders only Focus — On / Focus — Off and does not scrape Control Center or private databases.

NSFocusStatusUsageDescription is included in the packaged app Info.plist.

## Manual validation still required

Automated tests can validate arbitration and pure transition logic, but actual hardware/device behavior still needs a real-device pass:
- Caps Lock on/off on the MacBook keyboard.
- Charger connect/disconnect.
- Default audio output switch, ideally to/from AirPods or another headset.
- Existing Accessibility-gated volume/brightness OSD replacement.
