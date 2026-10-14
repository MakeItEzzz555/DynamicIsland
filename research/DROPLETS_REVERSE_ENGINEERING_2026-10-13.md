# Droppy Droplets — reverse-engineering report and 1:1 implementation plan (2026-10-13)

Observation / readability / research phase. No production code was changed. This document is the input for the implementation phases; it extends (does not replace) `DROPPY_PARITY_MASTER_PLAN_2026-09-29.md` and `SOURCE_PARITY_MANIFEST.md`.

## 0. Evidence, method, and limits

| Tag | Source | What it proves |
|---|---|---|
| **[D]** | Official docs, 258 pages of `getdroppy.app/docs/*` incl. one page per droplet, fetched 2026-10-13 (raw copies in `/tmp/droppy-research/docs/`, not committed — third-party text) | User-visible behavior, settings, surfaces, permissions |
| **[S]** | Installed **Droppy 16.0.1** (`/Applications/Droppy.app`, arm64, stripped, 51.6 MB) — Swift type names, source-file names, log strings, SQL, AppleScript/JS payloads, imported symbols (`strings`, `nm -u`), entitlements, Info.plist | *How* a feature is built (mechanism, data source, API) |
| **[REA]** | REA 6.4.0 `inspect-artifact` on Droppy.app → evidence `ev_228671bc…`, artifact graph `agm_3a9b62cd…` (230 nodes, sha256 `3bd33fd2…`) | Bundle identity/integrity; engine-free static graph |
| **[V11]** | Local GPL-3.0+Commons-Clause source `~/Documents/Droppy` (11.0.0, `dd2d16c`) | Older implementations of the original 16 extensions |
| **[P]** | Public droplet source `gitlab.com/droppyformac1/droplets` @ `9e92693` (dropclip, sales, teleprompter, thaw) | Full source for 4 store droplets |
| **[I]** | Inference from the above | Marked explicitly; verify before relying on it |

**REA limits (be honest about coverage):** Droppy 16 is stripped and no native analysis engine is installed (`rea doctor`: Ghidra `GHIDRA_INSTALL_DIR` unset, IDA unregistered, Hopper absent). Native decompilation/pseudocode was therefore **not** performed; all [S] mechanism claims come from string/symbol evidence, which shows *what* is called and *which* data sources are read but not exact control flow, thresholds, or timing constants. Where a plan item needs those, it is listed under §6 *Runtime gates & unknowns*. To unlock decompilation later: install Ghidra 12.1.x + a JDK 21 and set `GHIDRA_INSTALL_DIR`, or run `npx rea-agents@6.4.0 setup --client claude_code --install-hopper --yes`.

**Licensing boundary (unchanged from the 2026-09-29 plan, plus new facts):**
- Droppy 16 binary: closed/proprietary. Study behavior and mechanism only; never copy code, strings, assets, icons, or the name. Upstream GitHub repo `iordv/Droppy` is DMCA-blocked (HTTP 451).
- Droplet Store repo is "source-available, not open source"; **each droplet carries its own licence**: **DropClip = MIT** (OpenClip fork), **Teleprompter = MIT** → these two may be ported with their MIT notice. **Sales = proprietary, all rights reserved** → behavior only. Thaw = third-party app (Toni Förster) → integrate as external app, not code.
- v11 GPL+Commons Clause code: existing private-build provenance-header policy in `SOURCE_PARITY_MANIFEST.md` still applies; prefer clean-room.

## 1. How a droplet works inside Droppy 16 (architecture to mirror)

[S] Droplets are `.droplet` bundles (`Contents/Resources/droplet.json` manifest, principal class conforming to `DroppyKit.DropletPrincipal`, `kit.minAPI`, capability list such as `network-client`, `hud`, `shelf-write`, `microphone`, `accessibility`, `apple-events`, `clipboard-read/write`, `global-shortcuts`, `downloads`). First-party droplets are compiled into the app; store droplets are loaded at runtime (`DropletLoader`, `com.apple.security.cs.disable-library-validation` entitlement, `DropletCrashLedger`, `DropletRepositoryUpdater`, sha256-pinned zip downloads from a workers.dev CDN).

[S] The host exposes services to droplets — this list is effectively the **surface inventory** a 1:1 port needs:

| Droppy host service [S] | DynamicIsland equivalent today | Gap |
|---|---|---|
| `DropletNotchSurfaceHostService`, `DropletExpandedSurfacePresenter`, `ShelfWidgetContext(availableSize, isPaired, placement, isCompact, surface, usesIslandCurvature…)` | `WorkspaceConfiguration` / `WidgetPlacement` / `WidgetPresentationSize` / `WidgetGridMetrics` (`State/IslandWidgetLayout.swift`), `IslandWidget` enum | Have (semantic grid is stronger). New droplets = new `IslandWidget` cases + semantic-size layouts. |
| `DropletLiveActivityHostService`, `DropletLiveActivityPresenter`, `DropletLiveActivitySeat`, `…YieldReason`, `CompactLiveActivityPresentationMetadata` | `LiveActivityStore`, `DynamicIslandLiveActivityKind`, `LiveActivityLayoutResolver` (`LiveActivityCoexistencePolicy`) | Have. Add kinds: `notification`, `meeting`, `calendarCountdown`, `weather`? (no), `teleprompter` (hold-open), `pomodoro` (exists as timer). |
| `DropletHUDHostService` / `DropletHUDPresenter` (`DropletHUDPriority`, `DropletHUDRequest`) | `SystemHUDController` transient HUD profile | Have for system HUDs; needs a generic request API so notification cards / sale cards / meeting HUD share arbitration. |
| `DropletLockScreenPresenter`, `DropletLockScreenBox` + `SkyLightWindow` package (`SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSSpaceAddWindowsAndRemoveFromSpaces`, `CGSMainConnectionID`) | **None** | **Missing cross-cutting surface** (12 droplets put a chip/card on the lock screen). See §4.3. |
| `DropletLauncherHostService` (Thunderstorm items), `DropletShortcutsHostService`, `DropletKeyboardFocusPresenter` | Shortcuts are per-feature; `IslandKeyboardFocusPolicy` | Partial; needs a central hotkey registry (Action Ring/Thunderstorm/Meetings shortcuts). |
| `DropletPermissionsHostService`, `DropletPreferencesHostService`, `DropletInstallStateHostService`, `DropletEnvironmentHostService`, `DropletFeedbackHostService`, `DropletLogHostService` | `IslandCapabilityRegistry` (enabled/permission/availability/health/actions) | Have. Every new feature registers an `IslandCapabilityID`. |
| `DropletShelfHostService` / `DropletShelfHoldPresenter` | `FileShelfStore`, `BasketManager`, `ExpandedHoverContainment` holds | Have. |
| `DropletMenuBarExtras` | `MenuBarController` | Partial. |
| `DropletMCPTool` (droplets expose MCP tools; docs `docs/mcp`) | Agent bridge (different direction) | Optional; out of scope for parity. |

**Design rule for the port:** do *not* build a third-party plugin loader (it requires `disable-library-validation` and a signing/review pipeline). Implement each droplet as a first-party module registered in `IslandCapabilityRegistry`, toggled off by default, costing nothing when off — that matches Droppy's user-visible contract ("A Droplet that is off costs nothing… its shortcuts stop answering, permissions stop being used") [D].

## 2. Gap matrix — all 42 droplets

Status: ✅ have (parity-close) · 🟡 partial · ❌ missing · ⛔ deliberately not ported (policy). "DI" = DynamicIsland file evidence.

| # | Droplet | Status | DI evidence / what is missing | Priority |
|---|---|---|---|---|
| 1 | **Notifications** | 🟡 | `Messaging/SystemNotificationMonitor.swift` reads only the legacy usernoted SQLite and feeds Messages replies. Missing: all-app notification HUD + history widget, per-app filter, Biome source, banner suppression, Focus policy, burst/stacking, auto-dismiss, swipe-up dismiss, Mail live alerts, WhatsApp/Telegram reply, Discord jump-to-chat, contact photos, lock-screen chip | **P0** |
| 2 | **Meetings** | ❌ | Only `Communications/FaceTimeAccessibilityProvider.swift` (FaceTime). No Zoom/Meet/Teams/WhatsApp/Telegram detection, controls, call HUD, timer, share-hide, media pause | **P0** |
| 3 | Calendar (Tasks & Notes) | 🟡 | `CalendarEventsController`, `RemindersController` exist. Missing NL capture (`@list`, multilingual dates), event-approach progress ring live activity, week-start, lock chip | P1 |
| 4 | Agents | ✅ | DI is deeper (approvals, managed sessions). Missing providers: Cursor, Antigravity, OpenCode; lock chip | P3 |
| 5 | Weather | ❌ | none | P1 |
| 6 | System Stats | 🟡 | `SystemStatsController` has CPU/RAM/disk/net/battery + rolling history. Verify GPU sampler, "pick two / swap", Superstats (6), sample-only-while-visible | P2 |
| 7 | Pomodoro | 🟡 | `TimerController`, `FocusTimerMode {focus, rest}`, ruler. Missing per-mode remembered lengths, focus title, ambient sound, Clock-timer mirroring, auto-Focus, start-instantly, stopwatch | P1 |
| 8 | Apple Music Controls | 🟡 | `MediaAdvancedControls` (shuffle/repeat/favorite). Missing audio-quality badge (Lossless/Atmos), Playing Next queue for Music (mechanism unknown, §6) | P2 |
| 9 | Camera | ✅ | `CameraPreviewController`, mirror. Missing camera picker (Auto incl. Continuity), full-preview mode | P3 |
| 10 | **Lyrics** | ❌ | none | P1 |
| 11 | **Audio Control** (per-app volume) | ❌ | none | P1 |
| 12 | Spotify | ✅ | `SpotifyLibraryController` | — |
| 13 | Element Capture | 🟡 | Screen recording exists; screenshot capture modes, pause-screen, annotation editor, pinned shots missing | P2 |
| 14 | Thunderstorm (launcher) | ❌ | none — product-sized (§5.9) | P3 (own program) |
| 15 | Lid Fold | ❌ | none — novelty, needs hinge sensor | P4 |
| 16 | **Notes** | ❌ | none | P1 |
| 17 | Thaw | ⛔/❌ | Third-party app installer; offer "Open Thaw / install link" only | P4 |
| 18 | Termi-Notch | ✅ | `TerminalSessionController` + SwiftTerm. Missing quick-command HUD mode, command timeout, hand-off to Terminal/iTerm/Warp/Ghostty/WezTerm/kitty/Alacritty, lock chip | P2 |
| 19 | Stay Awake | 🟡 | `KeepAwakeController` presets. Missing mode split (Display / System-only / Lid-closed), lock card, menu-bar entry | P2 |
| 20 | **Text Capture (OCR)** | ❌ | none | P1 |
| 21 | Mechey | ❌ | none | P3 |
| 22 | LocalSend | ❌ | none | P3 |
| 23 | Video Compress | 🟡 | `FileTrayQuickAction.compress` exists; no FFmpeg two-pass target-size | P3 |
| 24 | Obsidian | ❌ | none (reuses Notes editor) | P2 |
| 25 | LiquidMouse | ❌ | none | P3 |
| 26 | Window Snap | ✅ | `WindowSnapController`. Verify modifier-drag move/resize, title-bar snap, padding, per-edge reserve | P3 |
| 27 | Droppy Cloud | ⛔ | Hosted upload service; already intentionally omitted (privacy/host policy) | — |
| 28 | Remove Background | ✅ | Vision `VNGenerateForegroundInstanceMaskRequest` (Droppy uses BiRefNet ~1 GB). Quality delta only | P4 |
| 29 | Finder Services | ❌ | needs `NSServices` + ingest | P2 |
| 30 | Voice Transcribe | ✅ | `VoiceTranscriptionController`. Verify custom vocabulary, type-into-field | P3 |
| 31 | **Teleprompter** | ❌ | none — **MIT source available** | P1 |
| 32 | Kaset | ❌ | none (AppleScript to Kaset) | P3 |
| 33 | PDF Compress | ❌ | none | P3 |
| 34 | Emoji Picker | ❌ | none | P2 |
| 35 | Action Ring | ❌ | none | P2 |
| 36 | Converter | 🟡 | `FileTrayQuickAction.convert` / `FileConversionController`. Verify video→audio set (M4A/WAV/FLAC/AIFF/ALAC), PDF→JPEG/PNG/WebP per page | P2 |
| 37 | Alfred Workflow | ❌ | needs URL-scheme ingest + `.alfredworkflow` | P4 |
| 38 | Sales | ❌ | none (proprietary — behavior only) | P4 |
| 39 | Window Switcher | ❌ | none | P2 |
| 40 | Cleaner | ❌ | none | P3 |
| 41 | DropClip | ❌ | none — **MIT source available** | P2 |
| 42 | (core) Lock screen + Floating player | ❌ | not droplets, but 12 droplets depend on the lock-screen surface | **P0 infra** |

## 3. P0 deep dive — Notifications (1:1)

### 3.1 Observed behavior [D]
- Captures macOS notifications for **chosen apps only**; everything else keeps the native banner.
- Two delivery modes: **Instant** (needs Screen Recording + Accessibility, native banners stay *on* in macOS, Droppy hides them) and **Standard** (no extra permission beyond store access; user turns banners off per app; arrives "a few seconds later"). Instant falls back to Standard until both permissions exist. Persistent alerts and undisplayable notifications keep native banners.
- Card: app icon, title, preview body (toggle "Display body text"), click = open source, **swipe up = dismiss**, auto-dismiss delay (paused while pointer inside or composer in use), island max width setting.
- **Inline reply** for iMessage, WhatsApp, Telegram; "Auto-hide after replying" clears it from notch *and* history on confirmed send; failures stay visible.
- **Discord**: "Reply in Discord" jumps to the exact chat via Accessibility while Discord's own banner is still up (~5 s); otherwise "Open Discord".
- **Focus**: hold banners during any/selected Focus modes; optional "let WhatsApp/Telegram through"; everything still lands in the Notifications widget.
- **Apple Mail live alerts** (separate switch): reads new inbox mail from Mail's store; click opens that email.
- Notifications **widget** = history; apps list "every app that has sent a notification", per-app "stop recording and delete history".
- Surfaces: notch widget, live activity, lock-screen chip (count + latest), global shortcut.

### 3.2 Mechanism [S]
| Concern | Evidence | Meaning |
|---|---|---|
| Primary capture | `BiomeNotificationStore`, `BiomeNotificationEvent`; `dlopen` of private `BiomeStorage/BiomeStreams/BiomeLibrary/BiomeFoundation`; `BMStreamDatastoreReader initWithStream:config:eventDataClass:useCase:`, `BMNotificationDelivery`, `newEnumeratorFromStartTime:`, `setEndTime:maxEvents:lastN:reverse:`; path `Library/Biome/streams/restricted/Notification.Delivery/local`; log `notification CAPTURE Biome count=` / `MAIN Biome live=` | Reads the Biome **Notification.Delivery** stream via private ObjC classes resolved at runtime |
| Fallback capture | usernoted SQLite at 10 candidate paths (`group.com.apple.usernoted/db2/db`, `…/db/db`, `group.com.apple.UserNotifications/…`, `Application Support/NotificationCenter/…`); `SELECT r.rec_id, r.app_id, r.data, r.delivered_date, r.uuid FROM record r JOIN app a … WHERE r.rec_id > ? ORDER BY r.rec_id ASC LIMIT ?`; WAL-file + directory + file monitoring; "rebuilding wedged DB connection after N prepare failures"; "cursor stranded above file frontier" | Same source DI uses, but hardened: WAL watch, dir watch, wedge recovery, frontier reset |
| Dedup / hygiene | "Skipping re-delivered…", "stale…", "wake-replayed…", "duplicate payload…", "duplicate content…", "identical re-delivery storm … within", "flood protection (oldest from queue)", own-message filters (multilingual "you:" prefixes; WhatsApp `ChatStorage.sqlite` `fromMe`) | Required for 1:1 feel — macOS re-delivers on wake/unlock |
| Lock/unlock | "notification(s) from live HUD (screen locked or post-unlock); kept in history", `postUnlockSuppressionInterval` | While locked or just after unlock: history only, no live banner |
| Presentation queue | `NotificationHUDManager`: "Queueing… surface busy (HUD or expanded shelf)", "Stacking notification … onto live banner (count N)", "Filling stacked row from queue", "Draining queued…", `notification-hud.burst.notification-count` ("N new notifications" burst summary), unread-count regexes (`^\d+\s+(unread messages?|new messages?…)$`) | Live banner accepts stacked rows from same app; bursts collapse; banners of counter-only text are filtered |
| Banner suppression (Instant) | `NativeNotificationBannerSuppressor` (+`PreferenceSnapshot`), `com.apple.notificationcenterui`, `NotificationCenterAlert`; imports `AXObserverCreate/AddNotification`, `AXUIElementPerformAction`, `AXUIElementCopyActionNames`; `bannerCapture{Window,Gaps,SteadyGap,MaxPending,Deadline,Step}` | AX observer on the NotificationCenter UI process; matching alert element is dismissed by an AX action **[I: exact action name not recovered — §6]** |
| Focus | `Library/DoNotDisturb/DB/Assertions.json`, `ModeConfigurations.json` (Full Disk Access), `_hasEverReceivedFocusFilter` + copy "Add Droppy under System Settings › Focus › Focus Filters" | Two paths: App-Intents **Focus Filter** (`SetFocusFilterIntent`, public) or FDA JSON read |
| Messages reply | AppleScript `tell application "Messages" … send` with 12 s timeout; `Library/Messages/chat.db` correlation query by time window (`ORDER BY ABS(m.date - ?)`) | DI already has a **stronger** path (descriptor Apple Events + exact chat resolution + `.confirmed/.uncertain`). Keep DI's. |
| WhatsApp/Telegram reply | WKWebView sessions: "Not connected. Click Connect, then scan the QR", "Replies send through WhatsApp Web / Telegram Web", `isWhatsAppLoginWindowPresented`, DOM scripts against `#pane-side`, `cell-frame-container`, avatar fetch to data-URL; "the Web session is live and owns WhatsApp banners" | Embedded web clients drive replies via injected JS (fragile, ToS-sensitive) |
| Mail live alerts | `app.getdroppy.mail-inbox-watcher`; SQL over Mail's `messages/mailboxes/addresses/subjects/summaries/message_global_data` with `LOWER(RTRIM(mb.url,'/')) LIKE '%/inbox'` | Reads Mail's Envelope Index SQLite (FDA) |
| Contact photos | `IMessageContactPhotoService`, Contacts entitlement | CNContactStore lookup by handle |
| Source app list | messaging/email bundle IDs (Messages, FaceTime, Messenger, WorkChat, Gmail, Spark, Airmail, Outlook, Mailspring, Canary, Skype, Webex, Beeper, Twitter, LinkedIn, Mastodon…) | Used for classification (messaging vs mail vs other) |

### 3.3 DynamicIsland implementation plan (1:1)
Reuse: `SystemNotificationMonitor`, `NotificationCenterDatabaseSource`, `ReadOnlySQLite`, `MessagingController` / `MessagingProviderAdapter`, `MessagesAppAdapter`, `LiveActivityStore`, `IslandCapabilityRegistry`.

1. **Source layer** (`Messaging/SystemNotificationMonitor.swift`, new `Messaging/NotificationSources/`):
   - Generalize `SystemNotificationRecord` (add `uuid`, `threadID?`, `categoryID?`, `appDisplayName`), keep bodies memory-only (existing invariant).
   - Harden `NotificationCenterDatabaseSource`: WAL + directory `DispatchSource` watch (DI already watches `path`/`-wal`), wedge recovery after N prepare failures, frontier reset when `MAX(rec_id)` < cursor, all 10 candidate paths.
   - **Biome source — decision required (§6 D1).** It is a *private framework* read. Options: (a) skip, rely on usernoted DB + Darwin hint (current DI); (b) add behind a capability flag with runtime `NSClassFromString` checks and fail-closed to (a). Recommend (b) only if the runtime gate shows the usernoted DB is stale on macOS 15.7/26.
   - `NotificationDeduplicator` (pure, unit-tested): re-delivery by `(bundle, rec uuid)`, payload hash, content hash within window, storm detector, wake/unlock replay window, counter-only body regex, own-message filter.
2. **Policy layer** (pure): `NotificationCapturePolicy` — per-app allow list (default empty = capture nothing, Droppy's "capture the two apps you care about"), Focus scope (all / selected modes / let messaging through), lock state (history-only while locked + post-unlock interval), persistent-alert passthrough.
3. **Focus**: implement an **App Intents Focus Filter** (`SetFocusFilterIntent`, public API, macOS 13+) as primary; FDA read of `~/Library/DoNotDisturb/DB/Assertions.json` + `ModeConfigurations.json` as optional fallback (read-only, schema-validated).
4. **Presentation**: new `DynamicIslandLiveActivityKind.notification`; `NotificationPresentationQueue` (pure state machine: current, stacked rows ≤N from same app, queue, burst collapse "N new notifications", auto-dismiss timer paused on hover/composer, swipe-up dismiss, click → `NSWorkspace.open` source app / deep link). Compact collapsed: app icon left, sender/title right (width profile via `LiveActivityLayoutResolver`). Expanded: card with body + reply composer (reuse `MessagingReplyComposer`).
5. **History widget**: `IslandWidget.notifications` (Compact = count + latest; Standard = list; Large = list grouped by app), per-app delete, "Every app that has sent a notification" settings list.
6. **Instant mode (banner suppression)**: `NativeBannerSuppressor` — `AXObserver` on `com.apple.notificationcenterui` for window-created; match by title/body to a just-captured record; dismiss via the alert's AX close/"Close" action. Gated on Accessibility **and** Screen Recording (per [D]); falls back to Standard. ⚠ Must never dismiss a banner DI did not present (exact match only).
7. **Replies**:
   - iMessage: keep DI's existing descriptor-based Apple Events path (stronger than Droppy's interpolated AppleScript).
   - WhatsApp/Telegram: **decision required (§6 D2)** — Droppy's embedded-web-client approach injects JS into WhatsApp Web/Telegram Web. Alternatives: Telegram has a public URL scheme only for opening chats; WhatsApp has none for sending. Recommend phase 1 = "Open chat" deep links (`whatsapp://`, `tg://`) + AX-free; phase 2 = web-session adapter behind explicit opt-in as a new `MessagingProviderAdapter` (must honor `.confirmed/.uncertain`).
   - Discord: AX press on Discord's own banner within its lifetime → "Reply in Discord"; else open app.
8. **Mail live alerts**: `MailEnvelopeSource` read-only over `~/Library/Mail/V10/MailData/Envelope Index` (FDA), inbox-only filter, open via `message://<message-id-header>`.
9. **Contact photos**: `CNContactStore` lookup by handle; add `NSContactsUsageDescription` in `Scripts/package_app.sh`.
10. **Settings tabs** mirroring Droppy: Display (preview, auto-dismiss, island width), Replies, Sounds, Filters (Focus), System integration (Instant/Standard, Mail), Apps.
11. **Tests**: dedup, policy, queue/stack/burst state machine, Focus JSON parser, Mail SQL against fixture DB, payload parser for flat/`req`-nested plists (exists).
12. **Permissions** to add/verify in `package_app.sh`: `NSContactsUsageDescription`, (Accessibility/Screen Recording/FDA are TCC prompts without plist keys).

Acceptance: real notification from 3 allowed apps shows within ≤1 s in Instant, banner hidden; disallowed app keeps native banner; Focus on → history only; lock → history only; wake re-delivery produces no duplicate; reply confirmed for iMessage; Reduce Motion = opacity only.

## 4. P0 deep dive — Meetings & calls (1:1)

### 4.1 Observed behavior [D]
- Watches Zoom, Google Meet, Microsoft Teams, WhatsApp, Telegram Web. A **compact call HUD takes the notch for the call's length** (timer + live mic activity visualizer + mute state).
- One-click **Mute, Camera, Screen share, End call**; reorder/hide buttons; **per-meeting-app global shortcuts** that work from any app while the meeting is live (warns about double-firing with the app's own global shortcut).
- **Notch hidden from viewers while screen sharing.**
- "Allow media while muted" / pause media during meeting and **resume when it ends**.
- Meeting **notes panel** when Notes droplet is on; lock screen: meeting timer + mute state + open meeting tasks.
- Thunderstorm side: join card N minutes (default 5) before a calendar meeting; link detection for Zoom, Meet, Teams, Webex, Jitsi, Whereby, Chime, GoTo, BlueJeans, Skype, FaceTime, Slack huddles; auto-join / camera check (off by default).

### 4.2 Mechanism [S]
| Concern | Evidence |
|---|---|
| Adapters | `MeetingAppAdapter` with `ZoomAdapter` (`us.zoom.xos`), `GoogleMeetAdapter`, `MicrosoftTeamsAdapter` (`com.microsoft.teams2`, `com.microsoft.teams`), `WhatsAppAdapter` (`net.whatsapp.WhatsApp*`), Telegram (`web.telegram.org/`, `ru.keepcoder.Telegram`, `org.telegram.desktop`); state types `MeetingState`, `MeetingAction` (`toggleMute`, `toggleCamera`, `endCall`, share), `MeetingLiveFields`, `MeetingElapsedCandidate`, `MeetingAXScanCache`, `MeetAXWindowScanResult`, `MeetTabState`, `CachedMeetSession` |
| Native apps (Zoom/Teams/WhatsApp) | **Accessibility tree scan** for multilingual button labels (EN/NL/DE/FR/ES/IT/PT): "unmute audio", "join audio", "leave meeting", "end call", "hang up", "share screen", "stop sharing", "call duration", "meeting time"…; window-title regex `^(meeting\s+compact\s+view|meeting\s+view|call\s+in\s+progress|microsoft\s+teams|zoom|google\s+meet|webex)$`; elapsed-time regex `(?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)` from AX text → meeting timer; Screen Recording "improves Zoom and Meet detection by reading window names" |
| Actions on native apps | AX press on the matched control; fallback **keyboard shortcut posted to the app's process** ("the shortcut was posted to its process instead", "Droppy's notch held keyboard focus; the shortcut was posted to …", `CGEventTapPostEvent`, source `com.droppy.meeting.keystrokes`) |
| Google Meet (browser) | AppleScript over Chromium-family browsers (Chrome/Beta/Dev/Canary, Brave, Edge, Arc `company.thebrowser.browser`, Dia, Vivaldi, Opera, Orion) + PWAs (`com.google.chrome.app.*` …): enumerate `URL of every tab`, match `meet.google.com/` (code regex `^[a-z]{3}-[a-z]{4}-[a-z]{3}$`, `g.co/meet`, `goo.gl/meet`); `execute t javascript` with DOM scripts that (1) detect in-call by finding a "leave call" control (searches iframes), (2) read mute/camera from `[data-is-muted]` + aria-labels, (3) click the control by dispatching mousedown/mouseup/click; result protocol `active|url|m|c|readable`, `present|…<<<DROPPY_ENDED>>>…`, `inconclusive`, `uninspectable`, `absent`; focus tab (`set active tab index`), close tab for End (`close t`). "Screen sharing not available in Google Meet" in Safari path |
| Detection loop | "Detection armed; no supported app running, sleeping until one launches", "Polling started (AX=…)", "Polling stalled past its deadline, restarting detection", transient-miss hysteresis ("Detection miss…, keeping current meeting", grace duration), notifications `droppy.meetingDidStart/DidEnd/ScreenShareDidChange` |
| Share-hide | `sharingType` (NSWindow) — set `.none` on Droppy windows while sharing |
| Mic visualizer | `MicrophoneLevelAnalyzer`, Microphone permission "live call speaking levels" |
| Media | `meetingControls_resumeMedia`, `meetingControls_concurrentMedia`: "Media paused for meeting", "Meeting ended, media resuming", "Media blocked during meeting" |
| Settings keys | `meetingControls_actionOrder`, `_hiddenActions`, `_shortcutsJSON` |

There is **no CallKit/incoming-phone-call handler** in Droppy 16 (no `CXCall`/`TUCall`/"incoming call" strings) [S]. "Calls" in Droppy = Meetings + Notifications. DI's `FaceTimeAccessibilityProvider` already covers FaceTime beyond Droppy.

### 4.3 DynamicIsland implementation plan (1:1)
New folder `Sources/DynamicIsland/Communications/Meetings/`:
1. `MeetingProvider` protocol: `bundleIdentifiers`, `scan() async -> MeetingSnapshot?` (`isInCall`, `isMuted?`, `isCameraOn?`, `isSharing?`, `elapsed?`, `title?`, `readable` flags), `perform(_ action: MeetingAction) async -> MeetingActionResult`. Unknown state stays `nil` — never invent mute state (mirrors DI's "never fake a capability").
2. Providers:
   - `ZoomMeetingProvider`, `TeamsMeetingProvider`, `WhatsAppCallProvider` — AX tree scans with a **label table** (`MeetingControlLabels`, multilingual, data not code), title regexes, elapsed regex; actions = AX press, fallback = app's own shortcut posted via `CGEvent.postToPid` (Zoom ⌘⇧A mute, ⌘⇧V video, ⌘⇧S share; Teams ⌘⇧M / ⌘⇧O / ⌘⇧E — verify per app version, §6).
   - `GoogleMeetBrowserProvider` — Apple Events to Chromium browsers using **descriptor parameters, not string interpolation** (DI messaging invariant); JS payloads are static constants; requires the browser's "Allow JavaScript from Apple Events" (Chrome: View › Developer) — surface that requirement in Settings.
   - `TelegramWebCallProvider` — same browser path on `web.telegram.org`.
   - Reuse/extend `FaceTimeAccessibilityProvider` as a provider.
3. `MeetingDetectionCoordinator`: `NSWorkspace` launch/terminate observation (sleep when no candidate app), poll cadence + stall watchdog, miss hysteresis/grace, start/end events → `LiveActivityStore` kind `.meeting`.
4. **Call HUD**: collapsed = app glyph + timer left, mic level bars right (`MicrophoneLevelMeter` via `AVAudioEngine` input tap, only while in a call and Microphone granted); expanded = control row (Mute, Camera, Share, End; order/hidden from settings), optional notes panel (Notes widget §5.3).
5. **Share-hide**: on `isSharing == true` set `panel.sharingType = .none` (DI currently `.readOnly` at `OverlayWindowController.swift:1085` — that line is the one change needed there; restore on share end). Respect the "only change OverlayWindowController when required" rule — this is required.
6. **Media pause/resume**: on start, if playing and setting on, pause via `MediaController`, remember token; resume on end only if DI paused it.
7. **Per-app global shortcuts** active only while that meeting is live (central `HotkeyRegistry`, §5.10).
8. **Join card** (Thunderstorm subset worth porting now): extend `CalendarEventsController` with `MeetingLinkExtractor` (Zoom/Meet/Teams/Webex/Jitsi/Whereby/Chime/GoTo/BlueJeans/Skype/FaceTime/Slack huddle URL patterns from location/URL/notes), live activity N minutes before (default 5) until end; Return-equivalent click joins (native app when installed else browser). Declined/cancelled/all-day/finished excluded.
9. Permissions: Accessibility (required), Automation per browser/app (`NSAppleEventsUsageDescription` exists — extend text), Microphone (`NSMicrophoneUsageDescription`), Screen Recording optional.
10. Tests: label-table matcher (multilingual), elapsed regex, Meet result-protocol parser, detection hysteresis state machine, share-hide toggling, media pause ownership.

Acceptance: real Zoom + Meet (Chrome) + Teams call each detected ≤2 s, mute/camera/end work from collapsed HUD and from shortcut while another app is frontmost, notch invisible in shared-screen capture, media resumes only if DI paused it.

## 5. Remaining droplets — mechanism and plan

### 5.1 Lock-screen surface (infra for 12 droplets) — P0 infra
- [D] Cards above login area (Now Playing, Timer, Stay Awake stack order), status chip row (battery, headphones, sunrise/sunset, air quality + 12 droplet chips: Calendar, Weather, Notifications, Stay Awake, Pomodoro, Agents, Voice Transcribe, Termi-Notch, Droppy Cloud, Meetings, Notes, Obsidian), iOS-style volume/brightness sliders, lock/unlock sounds, screensaver behavior.
- [S] `SkyLightWindow` Swift package (`SkyLightOperator`, `TopmostWindow`, `NSWindowReadingView`, `SKL_CGSSpaceLevel`) using private `SLSSpaceCreate` + `SLSSpaceSetAbsoluteLevel` + `SLSSpaceAddWindowsAndRemoveFromSpaces`, `CGSMainConnectionID`, `kCGSSpaceAbsoluteLevelSetupAssistant`; `CGSessionCopyCurrentDictionary` for lock state; `CGShieldingWindowLevel`.
- Plan: **decision required (§6 D3)** — private SkyLight API, not App Store-safe, can break per macOS release. If accepted: `Overlay/LockScreenSurfaceController.swift` owning one separate window on a private space (never the island panel), lock detection via `com.apple.screenIsLocked/Unlocked` distributed notifications + `CGSessionCopyCurrentDictionary`, chip model `LockScreenChip` fed by each module only while it "has something to say". Strict privacy: no paths/prompts/bodies unless setting allows.

### 5.2 Weather — P1
- [D] current conditions + hourly, fixed city or auto location, °C/°F/locale, refresh interval, styles (dynamic/dark/Liquid Glass), lock chip, IP fallback when Location unavailable.
- [S] `https://api.open-meteo.com/v1/forecast` (no key); Location usage strings; no geocoding provider string recovered → Open-Meteo geocoding API is the natural pair **[I]**.
- Plan: `Modules/WeatherController.swift` (CoreLocation `CLLocationManager` when-in-use, reduced accuracy OK; Open-Meteo forecast with `current`, `hourly=temperature_2m,weather_code`, `timezone=auto`; WMO code→SF Symbol table; refresh timer only while enabled; cache last forecast). `IslandWidget.weather` (Compact = temp+symbol, Standard = + 6-hour strip, Large = + daily). Add `NSLocationWhenInUseUsageDescription` (+ `NSLocationUsageDescription`). Optional IP fallback behind a setting (network disclosure). Tests: WMO mapping, unit conversion, decoder fixtures.

### 5.3 Notes (+ Obsidian) — P1/P2
- [D] Notes: one-click capture, live Markdown (lists, headings, tables), autosave ~0.3 s, sort by last edit, pin, reopen at caret, grow-canvas option, shortcut focuses field, lock chip. Obsidian: point at vault (folder with `.obsidian`), sync only a Droppy folder or whole vault, same editor, never touch hidden folders, security-scoped bookmark re-pick.
- [S] `MarkdownTextEditor`, `MarkdownEditingTextView`, `MarkdownTableLayoutManager`, `MarkdownFormatter`, toolbar (bullet, number, checklist, indent, highlighter), regexes for `*em*` / `~~strike~~`, Apple Notes sync mention in `NSAppleEventsUsageDescription`.
- Plan: `Modules/NotesStore.swift` (plain `.md` files in `~/Library/Application Support/DynamicIsland/Notes`, debounced atomic writes, `NSFilePresenter`/`DispatchSource` for external edits), `Views/MarkdownNoteEditor.swift` (NSTextView-backed with `NSTextStorage` attribute pass — must follow `IslandKeyboardFocusPolicy`/`AgentPromptTextView.publishEngagement` focus rules), `IslandWidget.notes`. Obsidian = second root with security-scoped bookmark + `.obsidian`/hidden exclusion. Meeting notes panel hooks into §4.3.

### 5.4 Lyrics — P1
- [D] "L" badge beside title when timed lyrics exist; tap replaces companion widget with synced lyrics panel tinted from artwork; auto-expand option; lock screen lines under Now Playing.
- [S] `https://lrclib.net/api/get` and `/api/search` (logs `GET lrclib … track=… queryChars=`), `syncedLyrics` field.
- Plan: `Modules/LyricsController.swift` — LRCLIB `get` by `track_name, artist_name, album_name, duration` then `search` fallback; LRC parser (`[mm:ss.xx]`), cache per track identity; follow `MediaController` elapsed time; tint from existing `ArtworkAccentColorExtractor`. Badge in `MediaStandardLayout`; panel replaces sibling widget transiently (no saved-layout rewrite, per workspace invariants). Set an identifying `User-Agent` (LRCLIB request). Tests: LRC parser, line index at time, decoder.

### 5.5 Audio Control (per-app volume) — P1
- [D] slider per app playing audio, remember per-app levels, zipper-free ramps, Natural vs Linear curve, show paused apps, include system sounds, macOS 14.2+.
- [S] imports `AudioHardwareCreateProcessTap`, `AudioHardwareDestroyProcessTap`, `AudioHardwareCreateAggregateDevice`, `…DestroyAggregateDevice`; `NSAudioCaptureUsageDescription` ("processes app audio so Audio Control can give each app its own volume").
- Plan: `Modules/PerAppAudioController.swift` — enumerate `kAudioHardwarePropertyProcessObjectList`, per process `CATapDescription(stereoMixdownOfProcesses:)` with `muteBehavior = .mutedWhenTapped`, private aggregate device (tap + default output), IOProc applies smoothed gain (one-pole ramp) and writes to output; Natural curve = perceptual (e.g. gain = pos²–pos³ style) — exact curve unknown (§6). Persist levels by bundle ID. Add `NSAudioCaptureUsageDescription`. Risks: latency, device switches, CPU; strict teardown on disable. Tests: curve math, persistence, process list diffing.

### 5.6 Text Capture (OCR) — P1
- [D] system area-capture tool, images/PDFs, Markdown lists/tables on macOS 26, completion action (window vs copy), language auto, recent results widget, OCR text indexed in clipboard history.
- Plan: area via `screencapture -i -c` / ScreenCaptureKit picker (Screen Recording already handled by `ScreenCaptureRequestLedger`), `VNRecognizeTextRequest(.accurate, automaticallyDetectsLanguage)`; on macOS 26 `RecognizeDocumentsRequest` (Vision) for tables → Markdown (availability-gated). PDFs via PDFKit page text first, OCR fallback per page. `IslandWidget.textCapture` recent list; push result into `ClipboardHistoryStore` with OCR text searchable.

### 5.7 Teleprompter — P1 (MIT source available [P])
- [D]/[P] script under the camera, WPM pace or voice-following (Speech), import PDF/Word/text, notch stays open even over full-screen call, display stays awake, shared pace/type settings.
- Plan: port from `droplets/teleprompter` **with MIT notice** into `Modules/Teleprompter/` adapting DroppyKit calls to DI: hold-open via a new owner-scoped `ExpandedHoverContainment` hold (same mechanism as popovers), keep-awake via `KeepAwakeController` assertion, voice mode via `SFSpeechRecognizer` (`NSSpeechRecognitionUsageDescription`, `NSMicrophoneUsageDescription`). Read its `PROVENANCE`/`README` before porting.

### 5.8 Calendar NL capture + Pomodoro upgrades — P1
- Calendar [D]: parse "Email Sam tomorrow", "Pay invoice next Friday @Work", multilingual; default list; event progress ring as meeting approaches; week start; real-time sync. Plan: `NSDataDetector(.date)` + per-locale relative-day table + `@list` token resolver over `EKCalendar` titles (pure, unit-tested); `LiveActivityKind.calendarCountdown` ring (reuses join card §4.3.8).
- Pomodoro [D]/[S]: per-mode remembered length 1 min–8 h, focus title, start-instantly, ambient sound (brown/pink noise, fireplace, airplane), mirror Apple Clock timers (`~/Library/Preferences/com.apple.mobiletimerd.plist`, `MTTimerTimeInterval`), enable macOS Focus on start. Plan: extend `TimerController`/`FocusTimerMode`; noise via `AVAudioSourceNode` generators (brown/pink synthesized; fireplace/airplane need licensed loops — skip or synthesize); Clock mirroring = read-only plist watch (verify container path/sandbox on 15.7, §6); Focus enable via Shortcuts "Set Focus" run (`/usr/bin/shortcuts run`) — no public API.

### 5.9 Thunderstorm — P3 (separate program)
Product-sized launcher (apps/files/settings search with fuzzy + learned ranking, calculator/units/currency/time zones, quicklinks/snippets with placeholders, shell/script commands, window layouts/workspaces, window switcher, menu-item search, AI chat with providers/CLI/MCP, Raycast import, extensions on Node.js). Recommendation: do not attempt 1:1 in the island program; extract the island-relevant pieces (meeting join card §4.3.8, window commands into `WindowSnapController`, uninstall into Cleaner §5.13) and treat the launcher as its own roadmap.

### 5.10 Action Ring + central hotkeys — P2
- [D] hold shortcut → ring at pointer, release over button to run; tap → click mode; presets (capture, snap, dictation, media, meetings, stay-awake durations, pomodoro, notes, tasks, terminal, clipboard…); up to 3 concentric rings; per-app overrides; custom macros/Shortcuts/apps. [S] `RingManager`, `RingMenuController`, `RingMenuPanel`, `RingMenuState`.
- Plan: `HotkeyRegistry` (Carbon `RegisterEventHotKey` for combos; `CGEventTap` only when hold/release detection is needed — Input Monitoring) + `ActionCatalog` where every capability exposes typed actions (`IslandCapabilityAction` already exists — extend). Ring = borderless non-activating panel, radial hit-test by angle/radius, release-to-commit. Reduce Motion: no scale-in.

### 5.11 Emoji Picker, Window Switcher, DropClip — P2
- Emoji [D]: shortcut or text trigger (default `;`), 6–10 columns, skin tone, custom search labels, paste vs copy, open near pointer/centered; needs Accessibility. Plan: Unicode emoji data + `CFStringTransform` names, floating panel, paste via pasteboard + synthesized ⌘V to previous app.
- Window Switcher [D]: ⌥Tab (optional ⌘Tab takeover), live previews (ScreenCaptureKit one-shot `SCScreenshotManager` per open), MRU order, minimized/hidden/other-Spaces labelled, type-to-filter, close/minimize/quit/snap, Dock hover previews. Plan: AX window enumeration + `CGWindowListCopyWindowInfo`; previews only on open (never background capture).
- DropClip [P] MIT: port from `droplets/dropclip` with its LICENSE/NOTICE/PROVENANCE (AX selected-text read, pill near selection, actions incl. AI with user keys). Large; scope to core actions first.

### 5.12 System-level droplets — P3
- **Mechey** [D]/[S]: soundpacks (Mechvibes JSON format, manifest at Droppy CDN — use the upstream mechvibes community packs, MIT, with credits), low-latency playback (<10 ms: preloaded `AVAudioPlayerNode` buffers / AudioUnit), per-output-device volume, auto-enable on headphones, auto-mute when Music/Spotify/VLC plays, ignore <10 ms repeats, modifier silence, mouse clicks; needs Accessibility + Input Monitoring (`CGEventTapCreate` listen-only).
- **LiquidMouse** [D]: smooth discrete wheel events (detect via `scrollWheelEventIsContinuous == 0`), synthesize continuous phase/momentum events with easing curve, per-axis config, reverse for mouse only, per-app exclusion. `CGEventTap` (active) + Accessibility.
- **Stay Awake modes** [D]/[S]: Display (`kIOPMAssertionTypePreventUserIdleDisplaySleep`), System-only (`PreventUserIdleSystemSleep`), **Lid Closed** (`CaffeineClosedLidController` + watchdog PID ⇒ `pmset -a disablesleep 1` via authorized helper, restored by watchdog on crash — needs admin auth, high risk; gate behind explicit consent).
- **Lid Fold** [D]/[S]: `MacDuoLidAngleSensor` over `IOHIDManager` (hinge angle HID device on recent MacBooks), Screen Recording to snapshot the display, full-screen overlay animating fold. P4 novelty.
- **Cleaner** [D]: app + Library leftovers by bundle-ID (checked) vs name-only (unchecked), sizes, Trash-only with Put Back, cache/log/Xcode/DerivedData/device-support cleanup, scheduled clean (caches/logs unused 3 days, skip open apps), never Apple apps/Droppy/user folders, FDA optional.

### 5.13 File droplets — P2/P3
- **Converter** [D]: video→M4A/WAV/FLAC/AIFF/ALAC, audio↔audio, PDF page→JPEG/PNG/WebP, MP3 only with FFmpeg. Plan: `AVAssetExportSession`/`AVAssetWriter` + `AudioToolbox` (`ExtAudioFile`) for audio; PDFKit rasterize; WebP via ImageIO (`UTType.webP` write supported macOS 14+ — verify, §6).
- **Video Compress** [D]: FFmpeg two-pass H.264/AAC to exact size (bitrate = target bits / duration − audio). Plan: detect `ffmpeg` in Homebrew paths; never auto-install without consent; run in `BackgroundOperationCenter`.
- **PDF Compress** [D]: Ghostscript (`gs -sDEVICE=pdfwrite -dPDFSETTINGS=/ebook …`) via Homebrew. Native alternative: Quartz filter "Reduce File Size" (lower quality). Same consent rule.
- **LocalSend** [D]: LocalSend protocol v2 (multicast UDP discovery 224.0.0.167:53317, HTTPS REST `/api/localsend/v2/register|prepare-upload|upload|cancel`, self-signed cert, optional PIN, accept prompt, receive folder → file tray). `NSLocalNetworkUsageDescription` + `NSBonjourServices` not needed (multicast) but Local Network prompt yes. Protocol spec is open — implement natively.
- **Finder Services** [D]: `NSServices` entries ("Add to DynamicIsland tray/basket") in generated Info.plist + `NSApplication.servicesProvider`.
- **Alfred** [D]: URL-scheme ingest (`dynamicisland://add?path=` with path validation) + shipped `.alfredworkflow`; Powerpack required. P4.

### 5.14 Media droplets — P2/P3
- **Kaset** [D]: AppleScript transport/queue/like/dislike to the Kaset app (YouTube Music); must be running; Discord Rich Presence. Plan: new provider in `MediaAutomationExecutor` + `MediaControlCapabilities.resolve` entries (queue/like/dislike capabilities only when Kaset's dictionary exposes them — read its `.sdef`).
- **Apple Music queue/quality** [D]: Playing Next for Apple Music + Lossless/Atmos badge — Music's AppleScript has no queue/quality API; mechanism not recovered (§6). Do not fake.

### 5.15 Business/hosted — P4 / ⛔
- **Sales** (proprietary): behavior only — Stripe/Shopify/Lemon Squeezy/Gumroad/Dodo/Polar/Paddle revenue total beside notch, per-sale card, shelf day view vs yesterday, currency conversion, refunds. Requires per-provider API keys in Keychain + polling. Low value for this project.
- **Droppy Cloud**: hosted share service ⛔ (existing decision).
- **Thaw**: link out / install-from-GitHub helper only.

## 6. Decisions and runtime gates (must resolve before/while implementing)

**Decisions for the user**
- **D1 Biome notification source** — private `BiomeStreams` read via runtime class lookup. Accept as optional capability, or stay on usernoted DB only?
- **D2 WhatsApp/Telegram reply** — embedded WhatsApp Web/Telegram Web session with injected JS (Droppy's method; fragile, possible ToS issues) vs open-chat deep links only.
- **D3 Lock-screen surface** — private SkyLight space APIs (Droppy's method) or skip the lock-screen chips/cards.
- **D4 Lid-closed Stay Awake** — needs an admin-authorized `pmset disablesleep` path + watchdog. Accept or omit.
- **D5 Ports of MIT droplets** (Teleprompter, DropClip) — accept MIT notices in `ThirdPartyNotices`.

**Runtime gates (cannot be answered statically; verify on this Mac)**
- G1 Is `group.com.apple.usernoted/db2/db` still updated live on macOS 15.7.4 (terminal TCC blocked the check; DB file mtime was 2026-10-02)? Check from the FDA-granted DynamicIsland build. If stale → D1 becomes necessary.
- G2 Exact AX action/element used to dismiss native banners (`NotificationCenterAlert` subrole, action name) — inspect with Accessibility Inspector while a banner is up.
- G3 Zoom/Teams current AX labels and shortcut defaults on installed versions.
- G4 Chrome "Allow JavaScript from Apple Events" requirement for Meet control; Arc/Dia support for `execute javascript`.
- G5 Mail Envelope Index path/version on 15.7 (`~/Library/Mail/V10/…`).
- G6 `com.apple.mobiletimerd.plist` presence/readability on macOS 15.7.
- G7 Audio Control Natural-curve constants and ramp time (not recoverable without decompilation).
- G8 Apple Music Playing Next / quality badge source.
- G9 Lid angle HID device presence on this MacBook.

To close G2/G3/G7/G8 statically instead of at runtime: install Ghidra 12.1.x + JDK 21 (`GHIDRA_INSTALL_DIR`) and run REA `open_binary` + `analyze_function` on `NativeNotificationBannerSuppressor`, `ZoomAdapter`, `MicrosoftTeamsAdapter`, Audio Control and `MusicManager` code paths.

## 7. Recommended implementation order (vertical slices, per project workflow)

1. **Notifications core** (§3.3 steps 1–5, 10–11): hardened DB source, dedup, policy, queue, live activity, history widget. *No private APIs.*
2. **Meetings** (§4.3): Zoom/Teams/WhatsApp AX providers, Meet browser provider, call HUD, share-hide, media pause, join card.
3. **Notifications advanced**: Instant mode banner suppression (G2), Focus Filter, Mail alerts, contact photos, Discord jump; then D2.
4. **Lock-screen surface** (if D3 approved) + chips for Notifications/Meetings/Timer/Stay Awake.
5. **Daily-glance widgets**: Weather, Lyrics, Notes (+Obsidian), Calendar NL capture + countdown ring, Pomodoro upgrades.
6. **Audio Control**, **Text Capture**, **Teleprompter** (MIT port).
7. **Input/system**: HotkeyRegistry → Action Ring, Emoji Picker, Window Switcher, DropClip.
8. **Files**: Converter completion, Finder Services, LocalSend, Video/PDF compress (consented tool install), Cleaner.
9. **Long tail**: Mechey, LiquidMouse, Stay Awake modes (D4), Kaset, Lid Fold, Thunderstorm program, Sales.

Each slice: `graphify query` first → focused implementation → focused tests → `swift build && swift test` → package (`Scripts/package_app.sh`, new usage strings) → real-device acceptance → `graphify update .` → dated `context.md` entry. Apply apple-design / existing motion tokens (`WorkspaceMotion`, Reduce Motion paths) to every new surface.
