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


---

# Reference lock — audited source snapshot

Audited public Droppy repository:
- repository: `1of1Adam/Droppy`
- branch: `main`
- audited HEAD: `dd2d16ccbdc6aa22b456e199442b43a07aa446af`
- source license: GPL-3.0 + Commons Clause
- README/source tree inspected through the connected GitHub integration
- video references: both user-supplied recordings from 2026-09-29 were inspected frame-by-frame at regular intervals

The implementation rule remains clean-room behavioral parity: use Droppy to understand features, interaction models, component hierarchy, and capability surfaces, but implement equivalent DynamicIsland-owned code rather than copying GPL/Commons-Clause source or assets.

---

# Complete Droppy parity checklist

This checklist is intentionally broader than the phase summaries above. A final parity audit must account for every item here.

## Core notch / shell behavior

- physical-notch mode
- notch-less floating Dynamic Island mode
- hide/exclude notch overlay from screenshots/screen recordings where technically supported
- drop-zone activation while dragging
- drag-hover shell expansion
- collapsed/expanded shell animation
- multiple compact HUD/live-activity layouts
- external-display placement
- multi-display behavior
- auto-hide/settle behavior
- per-feature enable/disable
- centralized animation language / motion constants
- accessibility and Reduce Motion
- haptic/feedback abstraction where supported
- widget placement/personalization

## File Shelf parity

- drag files
- drag folders
- drag images
- drag URLs
- file promises
- persistent shelf
- optional watched folders
- pinned/favorite entries
- folder creation/grouping
- Quick Look
- rename
- reveal/open in Finder
- copy
- move
- share
- AirDrop
- Messages share target
- Mail share target
- generic Share sheet
- remove from shelf
- delete-original action only with explicit confirmation
- ZIP
- unzip/extract
- compression
- file conversion
- OCR
- metadata/details
- Quickshare
- multi-select
- batch actions
- thumbnail cache
- temporary-file ownership cleanup
- smart export/destination rules
- drag quick-action orbit below island
- hover scaling and descriptive action label
- one-drop/one-action semantics

## Floating Basket parity

- shake-to-spawn during drag
- configurable shake sensitivity
- movable floating basket
- multiple baskets
- color-coded baskets
- list view
- grid view
- stack preview
- basket switcher
- quick action bar
- batch drag out
- shelf -> basket
- basket -> shelf
- copy/share/open/remove
- auto-hide when empty
- idle auto-hide
- drag destination awareness
- deterministic temp-file retention

## Clipboard parity

- text
- rich text where safe
- images
- files
- URLs
- colors
- source application metadata
- source application icon
- persistence across restart
- full-text search
- source filtering
- tags
- custom tag colors
- rename tags
- favorites
- stars
- flags/pins
- rename clipboard item/title
- copy-back
- paste
- open
- share
- push to shelf
- push to basket
- image preview
- PDF preview
- Office/document Quick Look preview
- inline video preview
- link preview
- per-app exclusions
- password-manager exclusion
- bounded memory/disk history
- clipboard settings shortcuts

## System HUD parity

- volume
- mute
- display brightness
- keyboard backlight when trustworthy
- battery/power
- charging state
- Caps Lock
- Do Not Disturb / Focus
- AirPods connected
- AirPods left/right/case battery when available
- AirPods charging
- now playing
- notification banner
- microphone indicator
- camera indicator
- update/status HUD
- configurable HUD enablement
- configurable timeout
- external display behavior
- central priority/arbitration queue
- no competing HUD shell thrash

## Media parity

- Apple Music
- Spotify
- browser media sources already supported by DynamicIsland
- album art
- title/artist
- play/pause
- previous/next
- scrub
- duration/progress
- source-app open
- system volume
- shuffle where supported
- repeat where supported
- love/favorite where supported
- lyrics entry point where supported
- audio spectrum/visualizer
- compact media HUD
- expanded media controls
- lock-screen style media panel only if it fits DynamicIsland architecture
- per-provider integration diagnostics/settings

## Capture parity

- area screenshot
- window screenshot
- full-screen screenshot
- screen recording
- cursor capture option
- microphone option
- system audio option only with explicit permission and supported APIs
- recording duration/live activity
- stop control
- copy screenshot to clipboard
- save
- add to shelf
- share
- editor
- crop
- arrow
- line
- rectangle
- ellipse
- text
- blur/redaction
- undo
- redo
- configurable capture shortcuts

## Quickshare / transfer parity

- upload file
- progress
- cancel
- shareable link
- copy result link
- result notification/live activity
- upload history where useful
- provider abstraction so DynamicIsland is not hard-wired to one service
- privacy disclosure and opt-in

## Conversion / smart export parity

- image format conversion
- image resize/quality
- metadata stripping
- video conversion
- audio conversion
- FFmpeg optional adapter
- target-size video compression
- progress
- cancel
- safe output naming
- collision handling
- return result to shelf/basket
- destination presets
- background operation center

## Extension / integration parity

First-party or adapter-backed entries should cover:
- Apple Music
- Spotify
- Notification HUD
- Window Snap
- High Alert / keep awake
- Terminal
- Alfred
- Finder services
- Quickshare
- Video Target Size
- Element Capture
- Voice Transcribe
- Background Removal
- Menu Bar Manager
- Reminders / To Do
- Camera / Notchface
- Messages
- Mail
- Calendar
- Clock, only through a truthful supported route
- Shortcuts
- Codex
- Claude

Every integration page must show:
- installed/detected
- permission state
- health
- supported capabilities
- unsupported capabilities omitted
- test action
- shortcut configuration
- settings
- enable/disable
- live preview when meaningful

## Productivity extensions parity

### Window Snap
- halves
- quarters
- thirds
- multi-display
- keyboard shortcuts
- live snap preview
- drag zones
- app exclusions

### Keep Awake / High Alert
- indefinite
- preset durations
- custom duration
- schedules
- visible activity
- correct power assertion teardown

### Terminal
- integrated terminal surface
- quick command mode
- command history only by opt-in
- configurable shell
- configurable external terminal
- hotkey
- process lifecycle
- working-directory context
- terminal task activity
- safe termination

### Voice Transcribe
- mic recording
- recording live indicator
- on-device transcription/model path
- model install/manage
- copy transcript
- save transcript
- share transcript
- shelf output
- configurable shortcut

### Background Removal
- local model/Vision/CoreML path
- before/after preview
- export
- shelf result
- progress/cancel

### Camera / Notchface
- camera permission
- device selector
- live notch preview
- compact open/close
- teardown capture when closed

### Menu Bar Manager
- hide/reveal organization only if a stable supported implementation is possible
- never steal system menu-bar event ownership

### Finder / Alfred / Shortcuts
- Finder services to Shelf/Basket
- Alfred workflows/deep links
- Shortcuts intents/URL scheme hooks where useful

## Notifications and actionable messaging parity

- captured notification banner
- app icon/name
- title/sender
- body
- queue/arbitration
- timeout
- click to source app
- per-app ignore list
- Focus/DND respect
- Full Disk Access onboarding only if required by chosen implementation
- reply field only when authoritative reply capability exists
- preserve draft until send confirmation
- send failure state
- exact conversation targeting
- Messages adapter first
- WhatsApp/Telegram adapters only if reliable for installed version
- Open App fallback instead of fake reply

## Reminders / calendar / clock parity

### Reminders
- natural-language quick capture if reliable
- list selection
- due date
- completion
- upcoming live activity

### Calendar
- next meeting
- starts soon
- in-progress timer
- join URL where available

### Clock
- timer creation/read/stop only through real API/automation
- alarm read/control only where trustworthy
- stopwatch only if real state can be observed
- otherwise expose a DynamicIsland-native timer rather than pretending to control Clock

## Live activity parity

- volume
- brightness
- keyboard backlight
- media
- AirPods
- battery/power
- Focus/DND
- notifications
- messages/reply
- screen recording
- mic
- camera
- timer
- alarm
- meeting
- reminder
- download
- Quickshare
- conversion
- compression
- file transfer
- keep-awake
- agent
- terminal task
- app update/status

Each live activity must define:
- source authority
- start evidence
- progress evidence
- completion evidence
- dismiss policy
- priority
- collision behavior
- compact rendering
- expanded rendering if applicable

## Agents parity / beyond Droppy

DynamicIsland should keep its stronger existing Agents architecture and extend it rather than replacing it:
- Codex exact thread identity
- Claude exact session identity
- observed vs managed distinction
- current-thread ranking
- transcript
- composer
- stop
- approvals
- session auto-approve policy
- project/repository grouping
- usage/context metrics
- attention/completion glow
- compact live activity
- provider integration settings
- future providers through capability adapters

## Settings / personalization parity

Settings should eventually contain:
- General
- Island
- Appearance
- Motion
- Tabs / navigation
- Media
- Shelf
- Basket
- Clipboard
- HUDs
- Capture
- Live Activities
- Agents
- Integrations
- Extensions
- Quickshare
- Accessibility
- Advanced
- About

Live/sandboxed production-component previews should exist for:
- notch mode
- notchless mode
- shell width/height
- corner radius
- background/material/transparency
- compact widget placement
- media compact HUD
- media expanded player
- volume HUD
- brightness HUD
- AirPods HUD
- notification banner
- file drag quick-action orbit
- basket
- clipboard card/list style
- agent compact state/glow
- screen-recording indicator
- live-activity placement

Customization controls to evaluate:
- widget ordering
- left/right/below-notch placement
- per-widget visibility
- per-display settings
- animation intensity
- duration/timeout
- hover behavior
- shell material/background
- accent style
- visualizer style
- preview/test buttons
- reset section / reset all

---

# Video-derived parity notes

## Recording 1

The first recording confirms the interaction quality target, not just feature names:
- quick-action circles physically detach below the island during drag;
- target hover is magnified and visually selected before drop;
- action explanation appears while hovering;
- shelf actions are dense but discoverable through context menus;
- settings use visual previews rather than text-only toggles;
- extension settings are presented as first-class product surfaces;
- drag/file actions avoid taking over the whole shelf unnecessarily;
- basket/shelf/clipboard form one connected workflow rather than isolated features.

DynamicIsland should copy that workflow philosophy, not the source implementation.

## Recording 2

The second recording adds product-level expectations:
- live activities are central to the product identity;
- AirPods and system HUDs are transient notch-native experiences;
- messaging notification/reply is shown as an inline activity;
- notchless Macs get equivalent floating-island treatment;
- multiple compact live activities can use different shapes/layouts;
- capture/edit flows are first-class;
- personalization is marketed as a core feature, not an advanced afterthought.

---

# Phase dependency correction

The safest implementation order after the current Agents branch is:

1. **Foundation parity inventory + feature registry**
2. **System HUD engine** — volume/brightness/backlight/battery/AirPods arbitration
3. **Shelf drag-action orbit** — Share/AirDrop/Convert/Compress/Quickshare
4. **Background operation center** — conversion/compression/upload progress
5. **Capture suite** — screenshots, recorder, editor
6. **Settings preview framework** — reusable sandboxed production component previews
7. **Settings 2.0 sidebar/integration pages**
8. **Floating Basket**
9. **Clipboard 2.0**
10. **Extension/integration registry**
11. **Notification HUD + Focus/DND**
12. **Rich live activities**
13. **Terminal / Keep Awake / Window Snap / Reminders / Voice / Camera / Background Removal**
14. **Actionable messaging**
15. **Media source-specific parity completion**
16. **Widget/layout personalization editor**
17. **Final source/video parity audit + release polish**

Do not mix all of these into one giant commit. Each phase must leave the app shippable and preserve the existing canonical shell.

---

# Definition of complete parity

Droppy parity is complete only when:
- every item in this checklist is either **Implemented**, **Intentionally Not Supported**, or **Blocked by macOS/API constraints**;
- every blocked item records the exact technical reason;
- every implemented action has truthful capability/permission state;
- the two supplied recordings can be replayed as acceptance scripts and each visible interaction has a DynamicIsland equivalent;
- DynamicIsland's existing stronger features (Agents, browser media detection, usage metrics, exact session authority, current transition work) remain intact;
- final UI/interaction quality is consistent across Media, Agents, Shelf, HUDs, Capture, Clipboard, and settings previews.

---

# Supplemental visual acceptance references — 2026-09-29

Additional user-provided screenshots and recording sharpen the required UI parity. These are acceptance references for behavior/composition only; do not copy branding, artwork, or proprietary source.

## Side-by-side compact Live Activities

Reference screenshot shows three simultaneous compact surfaces around the physical notch:
- left circular utility/activity control;
- center elongated media/activity pill integrated with the notch;
- right circular timed/progress activity;
- all three remain visually independent but share one horizontal composition and consistent black/glass treatment;
- circular activities use radial progress/outline treatment;
- the center pill can combine artwork on the left with a compact waveform/visualizer on the right;
- activities can coexist rather than forcing a single winner when width permits.

DynamicIsland requirement:
- extend live-activity layout from single-winner arbitration to primary + sidecar slots where safe;
- support leadingSidecar, primary, and trailingSidecar compact placements;
- allow circular and pill-shaped activity families;
- each activity advertises its minimum/ideal width and whether it can be a sidecar;
- priority still decides collisions, but compatible activities may coexist;
- physical-notch safe areas remain authoritative;
- notchless mode mirrors the same three-slot composition;
- dragging/reordering compact widgets in Settings eventually maps directly to these slots.

Acceptance examples:
- media primary + keep-awake sidecar;
- media primary + timer sidecar;
- agent primary + timer sidecar;
- recording primary + mic/camera status sidecar;
- volume HUD temporarily preempts a sidecar or primary according to priority without destroying the underlying activity state.

## Expanded Media — Playing Next

Reference screenshot adds an explicit richer now-playing target:
- current artwork/title/artist on the left;
- progress bar with elapsed and remaining time;
- previous / play-pause / next controls;
- favorite/star;
- shuffle;
- output/device action when supported;
- right-hand Playing Next queue;
- multiple upcoming songs with artwork/title/artist;
- queue entries can be promoted/moved when the source integration genuinely supports queue mutation;
- queue pane is visually separated but remains inside the same expanded island surface.

DynamicIsland requirement:
- preserve the current reliable media provider precedence and existing core controls;
- add provider capability flags for readQueue, moveQueueItem, shuffle, repeat, favorite, and selectOutputDevice only if a trustworthy route exists;
- Apple Music should be the first queue-capable implementation if provider APIs/automation are reliable;
- Spotify queue display/control should only be exposed where the chosen adapter can truthfully read/mutate it;
- browser providers must not show fake queue controls;
- expanded layout must degrade gracefully when queue capabilities are absent;
- queue rendering must be lazy/bounded and must not block shell transitions.

## Supplemental recording observations

The latest supplied recording confirms additional acceptance details:
- an active conversion/compression operation is represented as a compact progress activity near the notch;
- live-activity gallery demonstrates many different compact geometries rather than one universal pill;
- examples visually include timed progress, battery/power, connectivity/network-like activity, messaging, music, utility toggles, and progress bars;
- inline messaging/reply is treated as a first-class notch interaction;
- clipboard is presented as rich visual cards, not only rows of text;
- screenshot editing is shown as a dedicated editor window/surface after capture;
- completed cloud/share/upload work produces a compact success notification/activity;
- the rich media surface returns without losing its previous playback context after other transient activities dismiss;
- floating basket creation is presented as a drag-time gesture and should not interrupt the original drag session.

## Live Activity layout architecture update

Add a slot-aware presentation layer above LiveActivityStore:

LiveActivityPlacement:
- leadingSidecar
- primary
- trailingSidecar
- overlayTransient

LiveActivityPresentationDescriptor fields:
- activityID
- preferredPlacement
- allowedPlacements
- minimumWidth
- idealWidth
- compactShape
- priority
- preemptionPolicy
- coexistencePolicy

Compact shapes should at least cover:
- circle
- capsule
- notchWing
- elongatedPill
- progressPill

Rules:
- transient HUDs may overlay/preempt presentation but must not erase persistent activity state;
- sidecars disappear first under constrained width;
- primary remains centered with physical-notch geometry;
- sidecar hit targets never overlap notch/camera exclusion;
- activities restore smoothly after transient HUD dismissal;
- animation must use one shared shell/layout transaction rather than three independent window animations.

## Media layout acceptance update

Expanded Media should support two responsive modes:

### Standard
- current track only;
- existing DynamicIsland player layout;
- used when queue is unavailable or width is constrained.

### Queue-expanded
- left/current-track column;
- central divider;
- right Playing Next column;
- bounded queue preview;
- queue scroll does not steal the main island collapse gesture;
- queue mutations show immediate pending state and reconcile against provider truth;
- no optimistic permanent reorder if provider rejects mutation.

## Settings preview additions

Settings 2.0 preview framework must add production-style previews for:
- three-slot live activities around the notch;
- circular sidecar radial progress;
- primary media pill + sidecars;
- queue-expanded media player;
- transient HUD preemption/restoration;
- conversion progress activity;
- upload/share success activity.

These previews should be sandbox state only and must not start real timers, recordings, conversions, or provider mutations.

---

# Video re-review and gap mapping — 2026-09-30 (after Phase 13G)

Source: the two supplied recordings, re-reviewed frame by frame on 2026-09-30.
- `Screen Recording 2026-09-29 at 8.58.03 PM.mov` (83 s): Droppy's own README demo video played from `github.com/1of1Adam/Droppy`.
- `Screen Recording 2026-09-29 at 9.04.02 PM.mov` (75 s): Droppy's marketing/purchase page (`getdroppy.app`).

## Reference policy for these gaps (user decision, 2026-09-30)

Option 2 applies: Droppy and AgentNotch are close **behavioural/UX** references for layout logic, interactions, flows, spatial composition, hover behaviour, compact→expanded transitions, information hierarchy and notch-native interaction. Their source code, assets, icons, artwork, branding and proprietary visual styling are **not** copied; DynamicIsland keeps its own implementation and visual identity. Where DynamicIsland's architecture is stronger (exact Codex/Claude session identity, managed Codex control, repository/project metadata, approvals, provider usage telemetry, live-activity arbitration, single-shell architecture) it is preserved; references improve the UX layer only.

## Roadmap crosswalk

The execution order is the **Phase dependency correction** list above (items 1–17). Execution phase numbers used in commits map onto it as follows:

| Execution phase | Dependency-order item | Status |
|---|---|---|
| Phase 13 (13A–13F) | 13 — Terminal / Keep Awake / Window Snap / Reminders / Voice / Camera / Background Removal | Done |
| Phase 13G | Agents stabilization (not a Droppy item; Agents parity/beyond-Droppy section) | Done |
| Phase 14 | 14 — Actionable messaging | Done (provider authority limited; see Phase 14 results) |
| **Phase 15 (next)** | **15 — Media source-specific parity completion** | **Next; not started** |
| Later phases | 3, 5, 8, 9, 10, 12 (remaining), 15, 16, 17 | Pending (see gap table) |

No new phases are created. Every video-derived gap below is attached to an existing dependency-order item, and all of them are re-checked in item 17 (final source/video parity audit).

## Current DynamicIsland baseline (verified in source, 2026-09-30)

- Tray/Shelf context menu: Quick Look, Open, Reveal in Finder, Copy Path, Copy File Name, Remove.
- No floating Basket, no shake detection, no drag quick-action orbit.
- Clipboard: bounded text/URL/image history with copy-back (opt-in monitoring and persistence); no search, pinning, tags, tag filters, rename or flags.
- No OCR / Extract Text, no format conversion or compression actions, no cloud share links.
- System HUDs: volume, brightness, Caps Lock, Focus. No AirPods/Bluetooth device activity.
- Tools page (13F): Keep Awake, Window Snap, Voice, Camera, Background Removal, Reminders; embedded terminal lives in Settings.
- Menu bar menu: Settings, Show/Hide Island, Quit.
- Notchless displays: floating island (existing).

## Gap table

Status values follow the Definition of complete parity: **Pending** (tracked, not implemented), **Partial**, **Requires Approval**, **Candidate — evaluate** (may end as Intentionally Not Supported).

| # | Gap observed in recordings | Evidence | Maps to (dependency item / plan section) | Status |
|---|---|---|---|---|
| G1 | Shake-while-dragging spawns a floating Basket at the pointer; Basket has Drop / Cloud / AirDrop / Convert targets | Rec 2 "Or shake it." 0:04–0:07, 1:12; Rec 1 0:26–0:32 | 8 — Floating Basket (Phase 5 section) | Pending |
| G2 | Basket expanded panel: file count + size header, grid/list toggle, back button, per-item context menu ("Move to Shelf", "Remove from Basket"), drag-out | Rec 1 0:28–0:32 | 8 — Floating Basket | Pending |
| G3 | Drag quick-action circles detach below the notch during a drag (AirDrop, Messages, Mail, Quickshare), hover magnifies and explains the target | Rec 1 0:12–0:16, 0:34 | 3 — Shelf drag-action orbit (Phase 3 section) | Pending |
| G4 | Rich Shelf context menu: Copy, Open, Move to…, Open With…, Share, Quickshare, Save, Convert to…, Extract Text, Remove Background, Compress, Create ZIP, Rename, Remove from Shelf | Rec 1 0:21–0:23, 1:15 | 3 — Shelf orbit (actions) + 4 — Background operation center (long-running convert/compress/zip) | Partial (6 of ~14 actions) |
| G5 | Folder items on the Shelf browse into a hierarchical submenu ("Open Folder") | Rec 1 0:18 | 3 — Shelf orbit / File Shelf parity | Pending |
| G6 | In-place rename of Shelf items | Rec 1 0:24–0:25 | 3 — File Shelf parity | Pending |
| G7 | Extract Text (OCR) result window with Copy to Clipboard | Rec 1 1:17 | 3 (action entry) + 4 (operation); Vision text recognition, local only | Pending |
| G8 | Remove Background from a Shelf item's context menu | Rec 1 0:21 | 3 (entry point) → reuses item 13's BackgroundRemovalController | **Implemented** as the Remove Background circle of the Tray quick-action orbit (result returns to the Tray); a context-menu entry is still Pending |
| G9 | Convert to JPEG/PNG/etc. with progress activity ("Converting to JPEG", Cancel) | Rec 2 1:12–1:14 | 4 — Background operation center (Phase 4 conversion section) | **Partial**: Convert circle converts one image to PNG/JPEG/HEIC/TIFF with native ImageIO (runtime encoder check, collision-safe sibling, never overwrites). No progress live activity/Cancel yet (conversions are short); non-image formats Pending |
| G10 | Quickshare / cloud upload producing a share link (uploads to a third-party host) | Rec 1 0:17 ("Droppy Quickshare … 0x0.st"); Rec 2 "Droppy Cloud" | 3 (entry) + 4 (upload operation) | **Requires Approval** (sends user files to an external service; host choice and privacy policy must be approved) |
| G11 | Clipboard manager window: tag creation with colour, tag filter popover, per-item Tag submenu, Favorite, Flag as Important, Rename, Move to Shelf/Basket, preview pane with metadata | Rec 1 0:37–0:50 | 9 — Clipboard 2.0 (Phase 6 section) | Pending |
| G12 | Clipboard visual card strip in the notch (text, image, colour swatch, file cards) | Rec 2 "Every copy you make." 0:31–0:34 | 9 — Clipboard 2.0 | Pending |
| G13 | Notch terminal as an inline command bar under the notch with command suggestions list and quick buttons | Rec 1 0:36–0:38 | 13 follow-up UX within Terminal (Phase 9 Terminal section); presentation only — TerminalSessionController is done | Pending (engine done, notch presentation missing) |
| G14 | Widget/layout personalization: "Customize Shelf" mode, drag widgets into place, widget strip (Focus/Break timer 25:00, apps, weather, etc.) below media | Rec 2 "Make it yours." 1:01–1:07 | 16 — Widget/layout personalization editor (Phase 13 section) | Pending |
| G15 | Island context menu: Customize Shelf, Open Clipboard, Open Settings, Quit | Rec 2 1:03 | 16 (Customize entry) + 7 — Settings 2.0 | Pending |
| G16 | Pomodoro-style Focus/Break timer widget | Rec 2 1:05 | 16 (widget) using existing TimerController | Pending |
| G17 | AirPods "Connected" live activity with battery ring | Rec 2 0:13 | 12 — Rich live activities (AirPods section) | Pending |
| G18 | Many compact live activities: update available, charging, full battery, VPN connected + timer, backup drive capacity, caps lock, focus, message | Rec 2 0:25–0:29 | 12 — Rich live activities | Partial (battery, caps lock, focus, agents exist) |
| G19 | Message notification with inline reply field in the notch (iMessage/WhatsApp/Telegram) | Rec 2 0:14–0:21 | 14 — Actionable messaging (execution Phase 14, done) | Apple Messages: **Implemented behind explicit opt-in** (approved narrow Full Disk Access for Notification Center + chat.db reads, Automation for the send); exact-conversation-or-no-send; **requires real-device validation**. WhatsApp/Telegram: not installed, no adapter. See Phase 14 continuation below |
| G20 | Notchless Mac: island floats as a Dynamic Island with the same activities | Rec 2 0:21–0:24 | Existing floating island; verify parity in 17 | Implemented (verify in final audit) |
| G21 | Screenshot capture ("Element Capture": any window/region/screen) and annotation editor | Rec 2 0:48–0:57 | 5 — Capture suite (Phase 2 section) | Pending |
| G22 | Screen-recording video editor with cursor tracking | Rec 2 0:58–1:00 | 5 — Capture suite | Pending; may be Candidate — evaluate (large scope) |
| G23 | Spotlight-like launcher ("Thunderstorm") and select-text-anywhere action ("DropClip") | Rec 2 0:37–0:41 | 10 — Extension/integration registry (Phase 8 section) | Candidate — evaluate |
| G24 | Meetings extension (mute, camera, share controls in the notch) | Rec 2 0:41 | 12 — Rich live activities (Calendar/Meetings) + 10 | Candidate — evaluate (depends on per-app control APIs) |
| G25 | Extension store UI with Featured, All, filters (Installed / Disabled / AI / Productivity / Media), per-extension sheet with Enable/Disable, settings and shortcuts | Rec 1 0:59–1:13 | 10 — Extension/integration registry + 7 — Settings 2.0 | Pending |
| G26 | Third-party-app extensions shown in the catalog (Alfred workflow, Spotify, Apple Music, Finder Services, Menu Bar Manager, Lyrics, Calendar, LocalSend, Mac Duo, LiquidMouse, Converter, Video Target Size) | Rec 1 1:01; Rec 2 0:37 | 10 — Extension/integration registry; Finder/Alfred items already listed in Phase 9 | Candidate — evaluate individually |
| G27 | Settings sidebar grouped as General / Shelf / Basket / Clipboard / HUDs / Lock Screen / Extensions / Quickshare / Accessibility / About, with visual previews (shelf preview, basket preview) | Rec 1 0:54–0:57 | 7 — Settings 2.0 + 6 — Settings preview framework | Partial (DynamicIsland has its own sidebar and live-activity preview) |
| G28 | Lock-screen media/unlock animation settings | Rec 1 0:59 | 15 — Media parity completion | Candidate — evaluate (lock-screen overlay feasibility) |
| G29 | Voice Transcribe settings: model selection/size, language, installed models list with Delete, recording shortcuts | Rec 1 1:12 | 13 follow-up (Voice) — model management currently classified Intentionally Not Supported on the SFSpeechRecognizer path; shortcuts blocked on a global shortcut system | Intentionally Not Supported (models) / Pending (shortcuts, with 16 or 10) |
| G30 | Window Snap keyboard shortcut table (halves, quarters, thirds, displays) | Rec 1 1:08–1:09 | 13 follow-up (Window Snap) — needs a global shortcut system, see 10 | Pending (requires shortcut infrastructure decision) |
| G31 | Keep Awake ("High Alert") sheet with quick timers and an active indicator | Rec 1 1:02–1:05 | 13 — Keep Awake (done in Tools/Settings) | Implemented (visual refinement in 17) |

## Acceptance

Item 17 (final source/video parity audit) must replay both recordings as acceptance scripts and close every row above as Implemented, Intentionally Not Supported (with reason), Blocked by macOS/API constraints (with reason), or Requires Approval.

---

# Phase 14 results — Actionable Messaging (2026-09-30)

Evidence: `research/MESSAGING_PROVIDER_AUTHORITY_AUDIT_2026-09-30.md`.

| Provider | Incoming authority | Exact conversation identity | Reply authority | Send confirmation | Fallback | Classification |
|---|---|---|---|---|---|---|
| Apple Messages | None public (no message class/event handlers in the scripting dictionary; notifications and chat.db are private) | Not derivable from any incoming source | Not offered (AppleScript `send` exists but cannot be targeted from an incoming event) | None (`send` has no result) | Open Messages (NSWorkspace, no Automation permission) | Incoming and reply: **Blocked by macOS/API constraints**; **Open-App fallback** |
| WhatsApp | None | No | No (documented links only pre-fill a compose window) | No | Open app, if installed | **Not installed**; no adapter shipped |
| Telegram | None | No | No (documented links only pre-fill) | No | Open app, if installed | **Not installed**; no adapter shipped |

Implemented provider-neutrally and covered by deterministic fakes: normalized provider/conversation/
message identity, explicit capabilities, per-conversation draft book (clears only on confirmed sends;
kept on failed, uncertain, timeout), bounded deduplicating queue, `.message` live activity through
LiveActivityStore with deterministic arbitration and HUD preservation, the expanded Messages page with
reply / Open-App / read-only modes, and Messaging settings with privacy-safe diagnostics.

Would change the classification only with explicit approval (stop boundaries): Accessibility reading of
Notification Center banners (still no exact reply target), Full Disk Access to `chat.db`, or UI-scripted
sends.

---

# Phase 14 continuation and Tray quick actions (2026-09-30)

Full Disk Access was approved **only** for Phase 14 messaging: reading Notification Center data for
ingestion and reading the local Messages database for exact iMessage conversation correlation.

| Provider | Incoming | Exact conversation | Reply | Send confirmation | Classification |
|---|---|---|---|---|---|
| Apple Messages | Notification Center database, read-only, opt-in ("Read message notifications"), schema-validated at runtime, starts from the newest record (no history backfill) | `chat.db` read-only: one incoming message matching the notification body within a bounded time window → that chat's GUID; ambiguous or none → no send | Apple Events `send` to `chat id` (parameters passed as descriptors, never interpolated); chat existence checked first | Outgoing message with the same text observed in that chat in `chat.db` within 6 s → **Sent**; otherwise **Uncertain** (draft kept) | **Implemented behind opt-in; requires real-device validation** |
| WhatsApp / Telegram | None | No | No | No | Unchanged: not installed, no adapter |

Fail-closed rules: no prompt on launch; no FDA → "Full Disk Access required" with an Open System Settings
action; unknown schema → unavailable; Automation denied → reply disabled with the reason; message bodies
are never logged and history is never copied. The reply target is captured when composing starts and
never follows a newer notification.

Tray quick-action orbit (G3-adjacent, G8, G9): three circles below the expanded shell on the Tray page
only — Remove Background, Convert, Share (NSSharingServicePicker anchored to the circle). Targets are the
explicit tile selection or the single Tray file. The circles are part of hover containment, hit-testing
and mouse passthrough. The drag-time orbit of G3 (AirDrop/Messages/Mail/Quickshare during a drag) is
still Pending.
