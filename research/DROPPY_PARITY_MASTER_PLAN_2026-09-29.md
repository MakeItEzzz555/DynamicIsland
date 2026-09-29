# DynamicIsland — Droppy-Parity Master Plan

Date: 2026-09-29
Branch baseline: `feature/agents-ui-overhaul-continuation`
Reference: public `1of1Adam/Droppy` repository + the two user-provided screen recordings captured on 2026-09-29.

## Purpose

Expand DynamicIsland from a media/files/timer/stats/agents island into a complete notch-native productivity and live-activity layer with feature parity for the useful behaviors demonstrated by Droppy, while preserving DynamicIsland's existing architecture, Agents work, media correctness, gesture ownership, and truthful authority model.

This is a behavioral/UI parity plan. Do not copy Droppy source code, bundled assets, icons, screenshots, branding, or prose into DynamicIsland unless the project intentionally adopts Droppy's GPL-3.0 + Commons Clause license and all downstream obligations. The current reference repo explicitly prohibits closed-source reuse and commercial derivatives. Implement equivalent behavior independently using Apple/public APIs, DynamicIsland-owned code, SF Symbols, and original assets.

## Reference evidence

### Public source supports

Droppy's public repository currently exposes:
- File Shelf with folders/pins/watched directories, selection, context actions, ZIP/unzip, OCR, conversion, AirDrop/share, Quickshare.
- Floating Basket with shake-to-spawn, multi-basket workflows, list/grid view, batch drag, quick actions, auto-hide.
- Clipboard manager with persistent text/image/file/link/color history, search, source filtering, tags, favorites, document/video previews, shelf/basket handoff.
- HUD system for volume, brightness, keyboard backlight, battery/power, caps lock, media/now playing, AirPods, notifications, mic/camera indicators.
- Extension registry and settings UI.
- Apple Music and Spotify integrations.
- Notify Me notification HUD.
- Window Snap.
- High Alert / caffeine.
- Termi-Notch.
- Alfred integration.
- Finder Services.
- Quickshare.
- FFmpeg target-size video compression.
- Element Capture + screenshot annotation.
- Voice Transcribe.
- AI background removal.
- Menu Bar Manager.
- Reminders / To Do.
- Notchface camera.
- Settings visualizer previews and per-feature customization.

### Screen recording 1 observations

Observed behaviors include:
- notch brightness HUD;
- richer now-playing control surface;
- drag files/folders onto the notch;
- circular quick-action targets below the notch during drag;
- hover-target scaling and action explanation;
- share/upload behavior;
- shelf context menu with copy/open/move/share/Quickshare/save/convert/extract/compress/rename/remove;
- floating basket and basket context actions;
- clipboard browser with tags, tag filters, preview pane, copy/paste/open/share/metadata actions;
- clipboard rename/edit flow;
- settings sidebar split into General / Shelf / Basket / Clipboard / HUDs / Extensions / Quickshare / Accessibility / About;
- extension store;
- High Alert settings sheet;
- Window Snap settings/preview;
- Voice Transcribe model + shortcut/settings UI;
- shelf drag/action behavior.

### Screen recording 2 observations

Observed behaviors include:
- shake gesture spawning a basket while dragging;
- AirPods connection live activity with battery;
- message notification/reply surface;
- notch-less Dynamic Island mode;
- multiple compact live-activity layouts;
- configurable widget/live-activity placement around the notch;
- richer clipboard visual cards;
- extension catalog;
- Element Capture;
- screenshot editor/annotation flow;
- global customization emphasis.

### User-requested parity beyond what is currently present in the public source

The user also wants:
- Clock/alarms/timers integration;
- agent live activities;
- integrated terminal;
- actionable message replies for supported messaging apps;
- every useful live activity shown in the supplied videos and discussed for DynamicIsland previously.

Public Droppy code search did not expose a Codex/Claude agent implementation, a Clock integration, or direct iMessage/WhatsApp/Telegram reply code. Treat these as video/user requirements, not as source-derived Droppy behavior. Implement them with DynamicIsland-native adapters and truthful per-app capability detection.

---

# Product rules

1. One canonical island shell.
2. One canonical navigation model; modules/extensions plug into it.
3. No fake authority or fake interactivity.
4. No heavy work on the critical animation path.
5. Every drag target has deterministic hover/drop ownership.
6. Every integration exposes permissions, health, and supported actions.
7. Every feature can be disabled independently.
8. Settings previews use the same production components/state reducers where practical.
9. Respect Reduce Motion and accessibility.
10. Preserve current Agents exact identity model and media precedence.
11. Avoid private APIs unless already isolated behind a compatibility adapter with a safe fallback.
12. Feature parity means behavior and UX quality, not copying Droppy assets/source.

---

# Architecture additions

## A. Island Feature Registry

Introduce a DynamicIsland-owned registry:

```swift
IslandFeatureDefinition
- id
- title
- category
- icon
- isEnabled
- requiredPermissions
- settingsDestination
- liveActivityCapabilities
- shelfActions
- commands
```

Categories:
- Core
- Files
- Clipboard
- System HUDs
- Media
- Capture
- Productivity
- Integrations
- Live Activities
- Agents

This replaces ad-hoc feature discovery without forcing existing modules to be rewritten immediately.

## B. Integration Capability Registry

Per integration:

```swift
IntegrationAdapter
- bundleIdentifier
- displayName
- detected
- permissionState
- capabilities
- health
- actions
```

Capabilities may include:
- readNowPlaying
- controlPlayback
- openSource
- sendMessage
- replyToNotification
- createReminder
- createTimer
- createEvent
- exposeLiveActivity
- acceptFiles
- shareFiles
- terminalLaunch

Unsupported actions remain absent, not disabled fake controls.

## C. Unified Live Activity model

Extend `LiveActivityStore` into a typed multi-source projection.

Candidate activity kinds:
- media
- volume
- brightness
- keyboardBacklight
- battery
- powerCharging
- AirPods
- timer
- alarm
- calendarMeeting
- reminder
- download
- screenRecording
- microphone
- camera
- notification
- messageReply
- fileTransfer
- fileConversion
- shareUpload
- agent
- terminalTask
- keepAwake

Priority arbitration must be deterministic and duration-bounded.

## D. Background task/operation center

Long-running operations use a common task model:
- conversion
- compression
- upload
- OCR
- background removal
- transcription
- screenshot export
- video export

Never block SwiftUI views.

---

# Phase roadmap

## Phase 0 — Reference lock + parity inventory

Deliverables:
- keep this document as the parity checklist;
- map each Droppy behavior to Existing / Partial / Missing / Not source-supported;
- preserve links and commit SHA of the reference repo used for research;
- add deterministic UI screenshots for current DynamicIsland before large UI changes.

Gate:
- no feature begins without an owner module, permission model, and rollback path.

## Phase 1 — System HUD foundation

Implement notch HUDs with the same quality bar as the media tab:
- volume up/down;
- mute state;
- display brightness up/down;
- keyboard backlight when available;
- configurable duration;
- compact/expanded style;
- animation priority arbitration;
- external display support where macOS APIs/tools permit reliable control;
- original DynamicIsland visual design using existing shell/morph language.

Settings:
- HUD master toggle;
- per-HUD toggles;
- live sandboxed preview;
- HUD size/position/duration choices where safe.

Gate:
- repeated key presses update a single smooth HUD without shell thrash.

## Phase 2 — Capture suite

Implement:
- screen region screenshot;
- window screenshot;
- full-screen screenshot;
- screen recording start/stop live activity;
- optional system audio/mic capture only with explicit permission;
- capture countdown option;
- cursor inclusion;
- save destination;
- copy-to-clipboard;
- add-to-shelf;
- share/export.

Then add Element Capture-like editing:
- crop;
- arrow;
- line;
- rectangle;
- ellipse;
- text;
- blur/redaction;
- undo/redo;
- copy/save/share.

Do not copy Droppy's editor assets.

Gate:
- recording HUD accurately reflects the real capture session and stops only after the recorder confirms termination.

## Phase 3 — File Shelf 2.0 + drag quick-action orbit

Evolve existing FileShelfStore/UI instead of replacing it.

Add:
- multi-select;
- keyboard selection;
- folders;
- pinned entries;
- optional watched folders;
- Quick Look;
- rename;
- reveal in Finder;
- copy/move;
- ZIP/unzip;
- OCR where supported;
- metadata;
- remove-from-shelf vs delete-file distinction.

Below-island circular drag targets:
- AirDrop;
- Messages share;
- Mail;
- generic Share;
- Convert;
- Compress;
- Quickshare when enabled;
- Add to Basket once Basket exists.

Behavior:
- appear only during relevant drag;
- staggered scale/opacity entrance;
- hover target scales;
- active target displays short explanation;
- drag remains alive between circles;
- drop performs exactly one action;
- no accidental island collapse while dragging.

Gate:
- Photos/Finder/Desktop drags and file promises work reliably.

## Phase 4 — Conversion + compression pipeline

Create typed conversion capabilities rather than a monolithic menu.

Images:
- PNG/JPEG/HEIC/WebP where platform support exists;
- resize;
- quality;
- remove metadata.

Audio/video:
- FFmpeg-backed optional adapter;
- format conversion;
- codec presets;
- target-size compression;
- progress/cancel;
- resulting file returns to shelf.

Archives:
- ZIP/unzip initially;
- safe extraction checks;
- collision handling.

Documents:
- expose only formats for which a reliable converter is installed/available;
- no misleading options.

Gate:
- all conversions are background operations with progress live activities.

## Phase 5 — Floating Basket

Implement DynamicIsland-native basket:
- shake while dragging to spawn;
- configurable shake threshold;
- movable floating basket;
- multiple baskets;
- color labels;
- list/grid;
- selected item batch drag;
- transfer shelf <-> basket;
- quick-action circles;
- auto-hide on empty/idle;
- Cmd+Tab-style basket switcher if it does not conflict with system shortcuts.

Gate:
- no lost file URLs or accidental temporary-file cleanup during transfers.

## Phase 6 — Clipboard 2.0

Build on existing hardened ClipboardHistoryStore.

Add:
- source app metadata/icon;
- search;
- source-app filters;
- custom tags/colors;
- favorites/star/flag;
- rename/title;
- URLs/colors/files as first-class payloads;
- richer image preview;
- PDF preview;
- Office Quick Look preview where system-supported;
- inline video preview;
- push to shelf;
- push to basket;
- share;
- paste/copy-back;
- per-app exclusion/password-manager exclusion.

Settings:
- history limit;
- persistence;
- ignored apps;
- ignored content types;
- tag management;
- shortcuts.

Gate:
- bounded memory/disk retention and no password-manager leakage.

## Phase 7 — Settings 2.0 + live preview tweakers

Redesign Settings into a scalable sidebar:
- General
- Island
- Appearance
- Motion
- Media
- Files/Shelf
- Basket
- Clipboard
- HUDs
- Capture
- Live Activities
- Agents
- Integrations
- Extensions
- Accessibility
- Advanced
- About

Every visual setting with meaningful output should have an inline sandboxed preview driven by production components:
- collapsed island dimensions;
- corner radius;
- transparency/material;
- hover expansion;
- navigation;
- media player layout;
- audio visualizer style;
- HUD volume/brightness;
- notification banner;
- AirPods HUD;
- activity glow;
- file quick-action circles;
- basket style;
- Agents compact status.

Changing a preview must not mutate unrelated runtime state.

Gate:
- previews animate at full quality without launching real operations.

## Phase 8 — Extension/integration center

Create an internal extension catalog with install/enable/disable/manage states.

First-party integrations:
- Apple Music;
- Spotify;
- Finder;
- Messages;
- Mail;
- Calendar;
- Reminders;
- Clock where accessible;
- Terminal;
- Shortcuts;
- Alfred when installed;
- Codex;
- Claude;
- browser media providers already supported.

Each integration page includes:
- app detection;
- permission state;
- supported capabilities;
- shortcuts;
- live preview;
- test action;
- health/diagnostics;
- disable/remove.

Gate:
- settings never show an action the adapter cannot execute.

## Phase 9 — Productivity extensions

Implement independently:

### Window Snap
- halves/quarters/thirds;
- multi-monitor;
- customizable shortcuts;
- pointer-drag snap zones;
- live placement preview;
- excluded apps.

### High Alert / Keep Awake
- indefinite mode;
- presets;
- custom duration;
- schedules;
- visible live activity;
- power assertion lifecycle cleanup.

### Terminal
- embedded PTY terminal surface;
- quick command mode;
- configurable shell;
- configurable external terminal app;
- hotkey;
- safe process lifecycle;
- terminal task live activity;
- no shell command persistence unless user opts in.

### Voice Transcribe
- microphone recording;
- on-device transcription when model available;
- model manager;
- copy/save/share transcript;
- optional shelf result;
- explicit mic permission.

### Background Removal
- Vision/CoreML/local model path;
- preview before replace/export;
- background operation progress.

### Camera / Notchface
- camera permission;
- compact toggle;
- expanded preview;
- correct device selection;
- no capture when preview is closed.

### Menu Bar Manager
- only if a stable macOS implementation can be shipped without breaking system interaction.

### Finder + Alfred
- Finder service to send items to shelf/basket;
- Alfred workflow/deep link integration.

Gate:
- every extension is independently removable/disableable.

## Phase 10 — Rich live activities

Add activity adapters one at a time.

### AirPods
- connected/disconnected;
- case/left/right battery when trustworthy;
- charging state;
- compact connection animation.

### Power
- charging;
- low battery;
- full battery;
- power source changes.

### Calendar / Meetings
- next meeting;
- starts soon;
- in-progress duration;
- join link where available.

### Reminders / To Do
- quick capture;
- upcoming reminder;
- completion.

### Clock
- timers/alarms only through an actually supported API or user-authorized automation;
- never fabricate state from UI text if no reliable source exists.

### Downloads
- native download sources only where observable with stable APIs;
- progress/cancel only when control is real.

### Camera/microphone indicators
- display privacy-sensitive indicators without collecting unnecessary content.

### Screen recording
- current recorder state + duration + stop.

### File operations
- conversion/compression/upload progress.

### Agents
- preserve the current authoritative Codex/Claude session architecture;
- compact active/approval/completion states;
- exact project/thread identity.

Gate:
- LiveActivityStore priority tests cover collisions between simultaneous activities.

## Phase 11 — Actionable notifications and messaging

Create notification projection separate from reply authority.

Notification HUD:
- app icon;
- sender/title;
- short body;
- timeout;
- click to source.

Replies:
- Messages first if a reliable user-authorized route is available;
- WhatsApp/Telegram only when the installed app/version exposes a trustworthy action path;
- otherwise Open App, never fake a successful reply.

Potential control mechanisms must be isolated:
- official app URL/API;
- Shortcuts;
- AppleScript;
- Accessibility automation as explicit opt-in fallback.

Every reply must:
- identify target app + conversation;
- retain user's typed draft until confirmed sent;
- report send failure;
- never silently target the wrong thread.

Gate:
- no app gets a Reply field unless the adapter reports real reply capability.

## Phase 12 — Media parity completion

Preserve current robust detection/arbitration.

Add where supported:
- shuffle/repeat;
- favorite/love;
- lyrics entry point;
- richer artwork treatment;
- optional real audio visualizer;
- per-source integration settings;
- AirPods/media coexistence rules;
- source-app open button;
- custom compact widget placement.

Gate:
- no regression in current Spotify/Apple Music/browser precedence.

## Phase 13 — Personalization / widget layout

Add a notch layout editor:
- drag supported compact widgets left/right/below notch;
- choose which compact activity appears by default;
- per-widget enable/disable;
- per-display rules;
- physical-notch vs notchless mode;
- preview inside Settings;
- reset defaults.

Widgets can include:
- media;
- timer;
- battery;
- date/time;
- agent;
- clipboard shortcut;
- shelf shortcut;
- screen recorder;
- quick capture;
- terminal;
- current meeting.

Gate:
- placement never breaks hit-testing or shell collapse.

## Phase 14 — Release polish

- animation/motion audit;
- Reduce Motion;
- keyboard navigation;
- VoiceOver labels;
- real trackpad;
- multi-monitor;
- Spaces/full-screen apps;
- permission onboarding;
- CPU/memory profiling;
- background activity budget;
- package/sign/notarize;
- deterministic screenshots;
- regression matrix.

---

# Gap matrix against current DynamicIsland

## Already strong / preserve
- canonical notch shell and morphing;
- Media player and multi-provider media detection;
- media controls/progress/volume;
- file shelf basic drag/drop;
- AirDrop service;
- clipboard history + persistence foundation;
- timer;
- system stats;
- live-activity store foundation;
- Agents: Codex/Claude observation, managed control, approvals, usage, exact session identity, transcript/composer;
- gestures and two-finger scrolling;
- extensive tests/package/sign flow.

## Partial
- File Shelf: needs selection, actions, folders, conversions, action orbit.
- Clipboard: needs organization/search/tags/previews/app filters.
- Settings: needs scalable sidebar + live visual previews + integration center.
- Live Activities: foundation exists but needs many more adapters/HUD arbitration.
- Media: needs richer source-specific controls/visualizer/personalization.

## Missing
- system volume/brightness/backlight HUD;
- screen capture/recording;
- screenshot editor;
- floating basket;
- conversion/compression operation center;
- Quickshare;
- extension registry/store UX;
- Window Snap;
- Keep Awake;
- embedded general terminal;
- voice transcription;
- AI background removal;
- camera preview;
- menu bar manager;
- Finder/Alfred integrations;
- AirPods HUD;
- notification HUD;
- messaging reply adapters;
- Calendar/meeting activities;
- Reminders/To Do;
- Clock integration;
- download activities;
- widget/layout personalization.

---

# Implementation ordering rule

Do not attempt a giant source copy or one-shot rewrite.

Ship vertical slices in this order:
1. System HUD foundation.
2. Shelf action orbit.
3. Conversion operation center.
4. Capture suite.
5. Settings live-preview architecture.
6. Basket.
7. Clipboard 2.0.
8. Extension/integration registry.
9. Productivity extensions.
10. Rich live activities.
11. Messaging/notification actions.
12. Personalization editor.
13. final parity/polish audit.

Each slice:
- graph query before coding;
- focused implementation;
- focused tests;
- manual real-device validation;
- full suite only when shared behavior changes;
- `graphify update .`;
- commit/push;
- never merge unless explicitly requested.

---

# Licensing boundary

Reference repository license at the audited commit is GPL-3.0 + Commons Clause.

Therefore:
- studying behavior and APIs is acceptable;
- do not paste or port Droppy implementation code into DynamicIsland by default;
- do not reuse its original icons/images/marketing assets;
- reproduce behavior independently;
- if the user later explicitly wants literal source reuse, first decide whether DynamicIsland will be relicensed and distributed under the required compatible terms.

This plan intentionally targets parity without contaminating DynamicIsland's codebase with incompatible source.

