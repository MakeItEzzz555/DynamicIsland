# PR #31: native communications authority follow-up

Starting head: `1a10f5db2fa091a22aa199125e1d7908238d02c7`.
Base: `2ad101e960401202adc1ec748cfedebf6707571e`.

## Bounded research and live evidence

- Local Droppy `Extensions/NotificationHUD/NotificationHUDManager.swift` reads generic Notification Center records, watches DB/WAL, registers `com.apple.notificationcenterui.bulletin_added`, and uses a two-second backup poll. No dedicated FaceTime / CallKit call subsystem was found in the Swift sources. DynamicIsland keeps its four-second backup poll and schema-validated read-only database authority.
- Droppy enumerates Group Containers and legacy Notification Center database paths. DynamicIsland already handles those locations. Its recording permission cache shortcut is not copied; PR #31's preflight, successful ScreenCaptureKit access and cdhash ledger are unchanged.
- `sdef /System/Applications/Messages.app` exposes chat GUID IDs, participants and `send` to a chat. Existing exact `chat id` sending already uses this. `sdef /System/Applications/FaceTime.app` returns error -192 (no scripting dictionary).
- Native CallKit remains outside this phase. No private frameworks, binary reverse engineering, window-title call guessing or coordinate clicking were used.
- macOS 15.7.4 / 24G517, FaceTime 36: a live read-only Swift AX probe had trust and successfully created an observer. Window-created, focused-window-changed, UI-element-destroyed and layout-changed registrations returned success. The ordinary interface contains many generic enabled `AXPress` elements. That is not proof of Answer / Decline / End / Mute.
- The final production debug probe read 22 structural elements, status 0, without truncation. This FaceTime version exposes its Catalyst window under `AXChildren` when `AXWindows` is empty; the reader handles both, with matching-process checks. No active call was arranged or any call action performed.

Primary API sources: [Apple AXUIElement reference](https://developer.apple.com/documentation/applicationservices/axuielement_h), [AXObserverCreate](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate), and the installed SDK's `HIServices/AXUIElement.h` / `AXRoleConstants.h` / `AXActionConstants.h`. AX supports observation and a Press action; it does not document FaceTime's call-specific control identities. The Darwin bulletin name is undocumented and optional, even though its notification-center transport is public.

## Delivered behavior and limits

- FaceTime observation is opt-in, off by default. Launch never requests Accessibility. Settings → Island → Activities → Communications Integration has explicit Request Accessibility, Open Accessibility Settings, Check Again and Open FaceTime actions.
- The provider observes only `com.apple.FaceTime`, attaches to that process, and rescans on relevant AX, process or FaceTime notification events. Events coalesce for 100 ms. Scans run off the UI thread, bounded by one second, 128 elements, depth 12 and eight windows. Stopped / replaced generations cannot publish a late result.
- Diagnostics only serialize allowlisted roles/subroles/actions, enabled state, depth, numeric status and SHA-256 identifiers. Titles, descriptions, values, caller text and message content are never read by the AX probe. The read-only packaged entry point is `DynamicIsland --probe-facetime`; it never requests permission or starts normal app services.
- **No active-call AX identity was verified.** Call states, elapsed time and call controls therefore remain unavailable in production. Guessed incoming / connected button trees and stale elements cannot authorize controls. No speculative action executor or guessed English-label mapping is shipped. Synthetic green/yellow call samples remain samples, with the existing Reduce Motion behavior.
- A real FaceTime Notification Center record can prime AX inspection and publish an eight-second **FaceTime notification** preview. It carries no caller/body, is inactive, has no visualizer, controls or hover growth, and expiry means preview expiry, not call end. Disabling integration removes it. Notification evidence never becomes connected / held / ended state.
- The Darwin signal wakes a database fetch only. DB record IDs deduplicate Darwin/file/poll overlap. An in-flight hint schedules one follow-up; full batches drain without another hint. Watchers and the four-second poll keep working if the name ceases to exist. No live notification latency measurement is claimed.
- Communications capability rows distinguish notification access, Accessibility observation, each call action, Messages observation, exact matching, send and confirmation. They observe their actual controllers; internal details are inside a disclosure. Preview dependencies remain inert.
- Messages' PR #31 pipeline and shared native hover composer are unchanged. FDA denial still requires user-granted access. AX labels / participant names cannot prove one exact chat GUID or independently confirm delivery; no fallback sender or second composer is added. Apple Events returning is never confirmed success.
- Recording sources, filters, timeline, first-frame timeout and permission recovery are unchanged. This phase uses focused recording regression tests, including the actual single-frame three-second writer/AVAsset test. The earlier live display/window/area/audio/cursor/exclusion proof remains in [final-live-activities.md](final-live-activities.md); it is historical evidence, not a new live matrix run.

## Validation

Final Debug build and diff hygiene passed. Full suite: 2,174 tests, 42 skips, 0 failures. Release/package/signature results and final-head CI are recorded in the PR and handoff. Focused run: 144 tests, 5 opt-in recording tests skipped, 0 failures. Ten new deterministic tests cover opt-in / permission / absent or wrong process, unverified call trees / stale elements, notification-only preview and removal, private-text-free serialization, inert native diagnostics geometry, disabled-vs-permission diagnostics classification, Darwin/file deduplication, in-flight hint retention and batch draining / stop.

Recording subset: 40 tests, 5 opt-in live tests skipped, 0 failures.

The native NSHostingView diagnostics fixture fits the Settings content width. It exercises the actual production view without requests or real messages; it is not physical keyboard, VoiceOver or call evidence. The unchanged message hover tests exercise native Enter/Escape and scoped window resignation, not a user-operated call or reply. Final Apple Design/Taste/Ponytail review covered the intended diff and connected app/Settings callers, monitor lifecycle, exact message targeting, hover geometry, native controls and permission boundaries. No unresolved code finding remained; the live gates below remain explicit.

## Remaining live gates

- A user-arranged ringing and connected FaceTime call is needed to establish stable AX call-state/control identities for this UI version. The agent did not place, answer, decline, end or mute calls. No control is currently exposed.
- The exact packaged build may need Accessibility access; use its explicit Request Accessibility / Open Accessibility Settings actions. Notification reading also needs Full Disk Access and Check Again. No TCC reset or installed-app replacement was performed.
- Real incoming Messages plus an explicitly authorized exact recipient and text are still needed for a live reply test; Automation → Messages is requested only by explicit send. No recipient/text authorization was supplied during this phase.
- Mic recording, physical keyboard/focus/trackpad and VoiceOver remain unchecked from PR #31. Permission grants and physical acceptance cannot be inferred from deterministic tests.


## v5 checkpoint — 2026-10-14 (uncommitted)

### Ownership and scope

Settings v3.4 and Camera v4 were idle before editing. Branch remains `feature/camera-hand-navigation` at `1cd01b4d3a90b49f497176d0c9c19f91eda904a1`. A preservation manifest recorded 475 pre-existing dirty/untracked file hashes outside the repository. No branch switch, staging, commit, push, merge, preference changes, TCC changes or installed-app replacement occurred.

Production repairs:

- `Messaging/SystemNotificationMonitor.swift`: optional original delivery time, independent observation time, bounded UUID validation, atomic read-only snapshots, device/inode identity, conservative epoch rebasing, UUID continuity, bounded identity-only deduplication, token-scoped vnode rearming, late-WAL discovery on the existing 4-second poll, descriptor cancellation counters, mid-run error propagation, and owner-scoped event subscriptions. All SQLite work and path stat checks execute on the existing serial queue; cursor/publication authority remains MainActor. Startup retains its synchronous contract, dispatching the initial snapshot to that queue. Poll/watcher snapshots are asynchronous; the legacy startup API remains synchronous and can block its caller during the bounded SQLite read. No startup responsiveness claim is made.
- `Messaging/MessagesAppAdapter.swift`: monitor-state subscription, independent observation lease, explicit observation-time fallback, epoch-qualified incoming identities. Exact chat resolution, Apple Events sends and outgoing DB confirmation are unchanged.
- `Messaging/MessagingController.swift`: optional adapter state-change relay invalidates the existing UI immediately when observation/reply capability changes; existing provider fixtures retain their default behavior.
- `Messaging/MessagesConversationResolver.swift`: explicit observation-time fallback for the existing exact-match window.
- `Communications/FaceTimeAccessibilityProvider.swift`: notification-state propagation and independent observation lease. Notification evidence still cannot establish call state or actions.

Independently testable additions, **not connected to normal application services yet**:

- `Messaging/GeneralNotificationQueue.swift`: opt-in/allowlist eligibility, provider-specific exclusions, source/identity/timestamp provenance, optional transient content, identity deduplication, 10-item/8-second queue, dismissal, and conservative Focus/protected-owner/source/deactivation gates. No notification content is logged, hashed or persisted. No native banner suppression exists. The integration must clear/redact queued content immediately when privacy preferences change.
- `Communications/MeetingPresence.swift`: pure confidence reducer. App presence alone cannot establish a meeting. Sustained input IO in a recognized app advances possible → likely after two seconds; only direct provider evidence can establish confirmed. Stale evidence expires after eight seconds. No microphone-derived meeting start time or camera/mute status is invented.
- `Communications/MeetingPresenceProvider.swift`: supported CoreAudio process-list/input-IO property listeners on a serial queue, exact bundle/PID presence checks, allowlisted meeting applications, generation cancellation, sleep/wake cleanup, bounded evidence validation and explicit unavailable state. Read-completion timestamps survive the actor hop, delayed/out-of-order results cannot refresh authority, validation precedes expiry to avoid artificial presence flicker, and an unresponsive reader cannot keep stale presence indefinitely. Confidence values are evidence tiers, not calibrated probabilities. Off by default; no audio samples, taps, recordings, permission prompts, keystrokes or controls. Input IO indicates an active input stream, including possible virtual inputs; it is not proof of physical microphone capture or a live call.

The installed Apple SDK `CoreAudio/AudioHardware.h` documents `kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID` and `kAudioProcessPropertyIsRunningInput`. Runtime support is checked with `AudioObjectHasProperty`; property/listener failures produce unavailable evidence. Current FaceTime AX identities remain unverified, so no production direct-provider meeting confirmation exists.

### P0 acceptance and focused evidence

`SystemNotificationMonitorResilienceTests`: 21 tests, all passing. A1 inode replacement and next watcher delivery within two seconds; A2 late WAL and WAL wake; A3 record-ID regression/no history; A4 renumbered replacement/no replay; A4b UUID continuity; A5 permission loss; A6 schema failure at start/mid-run; A7 identical-content distinct records; A8 unknown delivery time plus exact Messages resolution using observation time; A9 vanished DB/unavailable/restart; A10 cancelled watcher and old-generation/epoch delivery rejection; A11 Messages/FaceTime state propagation; A12 100 re-arms with exact cancellation accounting, bounded 512-ID history and no preferences/files written. Additional coverage proves independent subscription ownership, malformed rows cannot block batch draining, superseded re-arm tasks cannot block subsequent replacements, real relocation prefers an existing DB over an obsolete parent, FaceTime Check Again retries notification access independently of AX, and Messages UI capability invalidation follows permission loss immediately. Empty/oversized UUIDs are not accepted as stable identities.

Focused total: **74 tests, 0 failures**, 9.055 seconds (`/tmp/dynamicisland-v5-focused-final.log`). General queue: 6; meeting: 7; resilience: 21; inherited ingestion/wake-up/Messages/FaceTime/controller tests: 40. Existing test intent and assertions were preserved.

Measured synthetic source read: 100 snapshots × 50 rows, mean **0.607 ms**, p95 **0.678 ms**. This measures the fixture reader, not production notification latency, idle CPU or packaged-app UI performance. Watcher counters verify resource disposal; no live notification database or personal content was read.

### Approval and native gates

Two explicit approval requests remain pending: (1) additive preferences for general notifications, per-app filtering and preview privacy, default off/hidden; (2) minimal shared-monitor app wiring, new notification/meeting activity routing and controls in the existing Communications section. No persistence or dependent integration edits were made. The current app still constructs separate default Messages and FaceTime monitors; the shared-owner contract is tested but not yet selected by the composition root. P1 production presentation and P2 production meeting activities are therefore **incomplete**, not claimed working. P3 native visual/accessibility/performance acceptance awaits that integration.

The display reports `active=0 asleep=1`. Real Notification Center replacement, FDA revoke/re-grant, authorized incoming notifications, live meeting telemetry and visible packaged-app/VoiceOver acceptance remain unverified. No privacy grant/revocation or live calls/messages were initiated.


### Final validation, reviewed checkpoint and preservation

- `git diff --check`: exit 0.
- Focused command: `swift test --filter 'SystemNotificationMonitorResilienceTests|NotificationWakeupTests|NotificationCenterIngestionTests|MessagesAppAdapterAuthorityTests|FaceTimeAccessibilityTests|MeetingPresenceTests|GeneralNotificationQueueTests|MessagingControllerTests'`: exit 0, **74/0**, 9.055 s. `/tmp/dynamicisland-v5-focused-final.log`.
- `swift build`: exit 0, 0.96 s. `/tmp/dynamicisland-v5-debug-final.log`.
- Final `swift test`: exit 1, **2,397 total, 42 skipped, 2 failures, 2,353 passed**, 182.291 s. `/tmp/dynamicisland-v5-full-suite-final.log`. Failures remain `MetalSendInteractionTests.testEnabledNativeHostUnpausesClockAndUnmountPausesIt` (line 69, app inactive/host occluded) and `SettingsWindowTests.testSettingsWindowAcceptsLocalPointerEventsThroughItsNativeHierarchy` (line 70, no native action). Both match the existing asleep-display Camera v4 checkpoint. Assertions were neither weakened nor skipped. The 2,275/35/0 baseline is historical; this run adds earlier Settings/camera tests plus 34 new v5 tests and retains their opt-in skips.
- `swift build -c release`: exit 0, 157.75 s. `/tmp/dynamicisland-v5-release-final.log`.
- Isolated `Scripts/package_app.sh`: exit 0. `/tmp/dynamicisland-v5-package.log`. Package: `/var/folders/7r/6kmfjt993f543jhm9vvq49nc0000gn/T/dynamicisland-v5-package-bu1pelip/DynamicIsland.app`. New ad-hoc package only; installed builds and TCC identity were not replaced.
- All three helper `codesign --verify --strict` checks and app `codesign --verify --deep --strict`: exit 0. `/tmp/dynamicisland-v5-package-validation.json`.
- Live API capability check: `processListPropertySupported=true`, `listenerAddStatus=0`, `listenerRemoveStatus=0`, **telemetryRead=false**. `/tmp/dynamicisland-v5-coreaudio-capability.log`. This proves transport availability only; input telemetry permission, app/helper attribution and meeting detection remain unverified.
- Isolated graph update: exit 0, 16,536 nodes / 49,234 edges. Original `graphify-out/` and `.playwright-cli/` were not edited. The existing MediaAdvancedControls parser limitation remains separate from passing native compilation.
- Review: intended 8 production files and 3 new tests plus connected monitor, Messaging UI/controller, FaceTime and SQLite callers. Fixed watcher task supersession, notification recovery, obsolete-path preference, timestamp/stale-evidence handling and observable capability propagation. No unresolved blocking P0 source finding; P1/P2 normal-app wiring and native/performance acceptance remain gated. Reviewed HEAD is unchanged; exact source/test hashes are in `/tmp/dynamicisland-v5-review-manifest.json`.

Only intended source/tests and appended engineering documentation changed. The original 475 dirty/untracked hashes are verified unchanged apart from the intended append to `context.md`; its original contents remain byte-for-byte intact. The existing communications report prefix is also intact. Git index remains unchanged, and no commit/push/merge occurred. Final manifest: `/tmp/dynamicisland-v5-final-manifest.json`.

### Next unfinished milestone

After explicit approval, connect the existing single monitor to Messages, FaceTime and the opt-in general surface, add truthful notification/meeting Live Activity cases with current priority/protected-owner rules, and put functional controls in the existing Communications section. Proposed additive notification keys: `generalNotificationPresentationEnabled=false`, `generalNotificationAllowedApplications=[]`, `generalNotificationContentPreviewsEnabled=false`. Meeting observation remains explicit/off until separately enabled; no new persistent meeting schema is authorized. Production integration must clear queued content immediately when preview/filter/enable preferences change.

Then validate real queues/dismissal, unknown/authorized Focus, UI ownership, VoiceOver/keyboard/Reduce Motion, display scaling and process/sleep cleanup in an unlocked packaged app. Observe authorized, controlled notification/meeting scenarios before claiming live coverage. Browser and vendor-helper attribution, AX meeting evidence and direct provider confirmations/controls are deferred until independently proven. Idle/active CPU, process memory, redraw cost and real telemetry latency were not measured; fixture timings are not substitutes.
