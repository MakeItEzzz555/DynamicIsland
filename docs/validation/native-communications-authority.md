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
