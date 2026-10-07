# Phase 17 stabilization / release-readiness status — 2026-09-30

Starting branch: `feature/agents-ui-overhaul-continuation` at `d263631cafd1222bfb57b22dabf342924cf6af8b`.

## Spotify distribution architecture

DynamicIsland now follows the intended Droppy-style ownership model: the app distributor owns one Spotify developer application and packages its public Client ID. Release users never create a Spotify developer app and never enter developer credentials. No Client Secret exists in the desktop client.

The normal release flow remains Connect Spotify → browser Authorization Code + PKCE → `dynamicisland://spotify-callback` → Keychain credentials → account-backed queue/playlists/library features. The optional DEBUG Client-ID override is contributor-only. Local Spotify.app playback/detection stays independent of Web API configuration.

Live Spotify Web API acceptance remains **IMPLEMENTED BUT REAL VALIDATION BLOCKED** because no legitimate DynamicIsland distributor Client ID is currently available. The final package intentionally contains no dummy Client ID.

## Spotify 2026 hardening

Implemented and deterministically tested:

- original authorization timestamp is stored with Spotify credentials;
- the known six-month refresh-token lifetime is measured from original authorization and is not extended by access-token refresh;
- a known expired authorization clears stale credentials and enters `reconnectRequired`;
- token refresh `invalid_grant` clears stale credentials and requires explicit Reconnect Spotify;
- token refresh is bounded and cannot retry-storm;
- one access-token refresh + one API retry remains the maximum 401 recovery path;
- HTTP 429 with structured `QUOTA_EXCEEDED` is distinguished from ordinary rate limiting;
- `Retry-After` is retained for user-facing diagnostics;
- 429 responses are never automatically retried;
- current generic `PUT/DELETE /me/library` mutation remains in use;
- queue, playlist and saved-library reads preserve independent failure behavior;
- existing credentials created before authorization-date tracking are not invalidated speculatively; provider `invalid_grant` remains authoritative.

Focused Spotify suite after the change: 19 tests, 0 failures.

## Motion contract

Production motion code was not redesigned in this phase. Protected behavior remains:

- physical shell top-pinned to the screen/notch;
- shell width/height animate through geometry and are never uniformly scaled;
- outgoing internal page content may shrink/blur/fade;
- incoming internal page content intentionally uses the source-backed compressed spring/materialization choreography;
- Reduce Motion removes content spring/scale/blur.

The obsolete `context.md` rule forbidding all inner spring bounce was corrected so future agents do not remove the intended content animation.

Focused validation:
- ExpandedIslandMotionTests: 20 / 0 failures
- NotchGeometryServiceTests: 20 / 0 failures

Physical on-screen tab feel still requires manual visual acceptance.

## Agents

No authority model was changed.

Protected:
- real managed Claude Allow/Deny E2E from the prior integrated checkpoint;
- exact-session/request one-shot approval semantics;
- observed Claude remains non-actionable;
- AgentNotch parity remains silent; the old guessed beep is not present.

Regression validation:
- AgentApprovalControllerTests: 6 / 0 failures
- ClaudeLaunchSpecTests: 3 / 0 failures
- ClaudeProviderProtocolTests: 9 / 0 failures
- ClaudeSessionCatalogTests: 1 / 0 failures
- ClaudeStreamingClientProcessTests: 1 / 0 failures
- ClaudeInteractiveProviderTests: 8 / 0 failures
- AgentNotificationFeedbackTests: 7 / 0 failures

Codex real provider acceptance remains **IMPLEMENTED BUT REAL VALIDATION BLOCKED BY CODEX QUOTA** until the provider reset window previously reported for 2026-10-03 around 20:37.

## Camera / gestures

Regression validation:
- CameraPreviewControllerTests: 25 / 0 failures
- CameraMirrorScrollRoutingPolicyTests: 3 / 0 failures
- RightWorkspaceTests: 13 / 0 failures

The opt-in live camera suite was attempted again in this phase but both cases skipped because Camera permission for the test process is currently `notDetermined`. Previous real-camera acceptance remains historical evidence, not a new live pass for this checkpoint.

Physical trackpad acceptance remains manual.

## Settings / personalization

Current generated audit:
- total settings: 203
- visual: 93
- visual without preview: 0
- no production reader: 0
- deprecated/hidden: 34

SettingsAuditTests: 9 executed, 1 opt-in audit-writer skip, 0 failures.

## Calendar

The hardened-runtime Calendar entitlement `com.apple.security.personal-information.calendars` has not been added.

Status: **BLOCKED — CALENDAR HARDENED-RUNTIME ENTITLEMENT REQUIRES USER APPROVAL**.

## Phase 17 release audit

Confirmed:
- no release Client-ID editor;
- no Client Secret;
- no fake Spotify content;
- no fake Agent approvals;
- no AgentNotch beep fallback;
- local Spotify controls remain independent from Web API configuration;
- top-pinned motion and workspace gesture tests remain green;
- user-facing dead-setting count remains zero;
- all visual settings have production-component previews.

Small release-polish cleanup removed an impossible no-op sound-switch warning and modernized Darwin-directory UTF-8 conversion without changing authority or behavior. Messages `attributedBody` still intentionally uses deprecated `NSUnarchiver` because that path reads Apple's legacy typedstream representation; replacing it with keyed unarchiving without evidence would risk breaking real Messages correlation.

## Validation

Final validation after the Spotify changes and release-polish cleanup:
- `git diff --check`: pass
- `swift build`: pass
- `swift test`: **1332 tests, 14 opt-in skips, 0 failures**
- `swift build -c release`: pass
- `Scripts/package_app.sh`: pass
- generated Info.plist: pass
- packaged Spotify Client ID: absent, as expected
- callback URL scheme: `dynamicisland`
- clean-copy ad-hoc signature verification: pass

Two non-blocking compiler warnings remain and are documented rather than papered over: Messages `attributedBody` decoding intentionally uses deprecated `NSUnarchiver` for Apple's legacy typedstream representation, and `ProductivitySettingsView.enabledToggle` triggers a Swift 6 sendability warning when forwarding its setter into `Binding`. An attempted actor/sendable annotation exposed a Swift 6.2.3 compiler IRGen crash and was fully reverted; production behavior remains on the previously passing implementation.

## Remaining external/manual blockers

1. Legitimate distributor-owned Spotify Client ID from an eligible Spotify developer account.
2. Codex provider quota reset for real approval/workflow E2E.
3. User approval before adding the Calendar hardened-runtime entitlement.
4. Physical trackpad acceptance.
5. Real on-screen visual acceptance of Agents ↔ other-tab motion.
6. Current test process Camera permission if a fresh live camera acceptance run is required.

No push, merge, rebase, PR-state change or publication is part of this phase.
