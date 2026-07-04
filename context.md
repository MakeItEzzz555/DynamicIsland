# DynamicIsland Project Context

Last updated: 2026-07-04

## Purpose

DynamicIsland is a native macOS SwiftUI/AppKit prototype that turns the MacBook notch area into a Dynamic Island / NotchNook-style utility overlay. It is a direct-download macOS app, not a Mac App Store app.

The app targets macOS 14.6+ and uses Swift Package Manager, SwiftUI views hosted in AppKit overlay panels, and a menu bar accessory app model.

## Non-Negotiable Behavior To Preserve

- Collapsed pill click-through behavior must remain fixed.
- Collapsed pill itself remains clickable to expand.
- Expanded tray internal buttons, sliders, shortcuts, timer controls, and file shelf controls remain clickable.
- Areas outside the visible pill/tray must not block other macOS apps or menu bar clicks.
- Expanded tray must collapse on mouse leave.
- Expanded tray shell/background keeps its bouncy/elastic spring behavior.
- Inner expanded components use clean blur/scale/opacity animation without spring bounce.
- Do not rewrite `OverlayWindowController` unless a specific feature requires it.
- Do not change the split-panel click-through architecture unless a specific feature requires it.

## Current Architecture

### App Entry

- `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - Creates `NSApplication` in accessory mode.
  - Owns shared singletons/stores:
    - `AppSettings`
    - `IslandStateStore`
    - `FileShelfStore`
    - `ShortcutsStore`
    - `MediaController`
    - `TimerController`
    - `NotchGeometryService`
  - Creates `OverlayWindowController`.
  - Creates menu bar controller and settings controller.

- `Sources/DynamicIsland/App/AppLaunchService.swift`
  - Centralized resolver/launcher for supported built-in/common apps.
  - Supported common apps are opened/focused automatically by bundle identifier, LaunchServices lookup, or known fallback path.
  - Do not add manual app selection or `NSOpenPanel` flows for Apple Music, Spotify, Safari, Brave, Chrome, Arc, Edge, Finder, or System Settings.

### Overlay Windows

- `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - This is the most fragile file in the project.
  - Current architecture uses split panels:
    - `panel`: visual-only canvas for collapsed rendering. It must ignore mouse events.
    - `collapsedHitPanel`: small click target over the collapsed pill.
    - `expandedPanel`: interactive expanded tray panel that owns SwiftUI controls.
  - This split exists because a single large transparent `NSPanel` caused hidden click-blocking areas, while physically resizing one panel caused positioning regressions.
  - Collapse checks are centralized through `collapseIfExpandedMouseOutsideAfterGrace(...)`.
  - A repeating timer while expanded is intended to be the source of truth for collapse detection.
  - Mouse-exit and mouse-move monitors are fast paths only.
  - Escape fallback currently exists in DEBUG/diagnostic work to prove state/window visibility behavior.

### Geometry

- `Sources/DynamicIsland/Geometry/NotchGeometryService.swift`
  - Infers notch geometry from:
    - `NSScreen.safeAreaInsets`
    - `NSScreen.auxiliaryTopLeftArea`
    - `NSScreen.auxiliaryTopRightArea`
  - Produces:
    - `collapsedFrame`
    - `expandedFrame`
    - `canvas`
  - Notched displays use hardware notch geometry.
  - Notchless/external displays use a floating top-centered fallback.

### State

- `Sources/DynamicIsland/State/IslandStateStore.swift`
  - Only two states should exist:
    - `collapsed`
    - `expanded`
  - Avoid reintroducing peek/pinned/drag-receiving states.

- `Sources/DynamicIsland/State/AppSettings.swift`
  - Stores overlay enablement, launch-at-login, animation intensity, and module flags.
  - Current size properties are mostly legacy inputs; notched geometry should own actual notch sizing.

### Views

- `Sources/DynamicIsland/Views/IslandRootView.swift`
  - Owns the visual island surface, compact view, expanded view, and animation transitions.
  - `IslandSurface` is the black rounded shell/background.
  - `blurBounce` is the tray/container transition and should keep spring behavior.
  - `innerBlurScaleClean` is for inner expanded modules only.

- `Sources/DynamicIsland/Views/ModuleViews.swift`
  - Contains media, visualizer, timer, shortcuts, shelf, and supporting views.
  - Media controls must remain clickable from the expanded panel.

- `Sources/DynamicIsland/Views/SettingsView.swift`
  - Settings UI.

### Modules

- `Sources/DynamicIsland/Modules/MediaController.swift`
  - Spotify-first media detection and control.
  - Apple Music fallback.
  - Avoid broad changes without testing permissions and playback state.

- `Sources/DynamicIsland/Modules/FileShelfStore.swift`
  - Temporary in-memory file shelf.

- `Sources/DynamicIsland/Modules/ShortcutsStore.swift`
  - App/file/URL shortcut launcher.

- `Sources/DynamicIsland/Modules/TimerController.swift`
  - Timer module state and controls.

## Current UI/Interaction Requirements

### Collapsed

- Small top-attached pill around the notch.
- Album art on the left.
- Native-style compact 3-bar visualizer on the right.
- Only the visible pill should be clickable.
- Hidden expanded tray/canvas areas must not intercept clicks.

### Expanded

- Centered top-attached tray.
- Internal controls are clickable.
- Tray collapses on first mouse leave after a small grace period.
- Escape can be used as a diagnostic fallback.
- The tray itself keeps bouncy/elastic shell expansion.
- Inner modules animate with clean blur/scale/opacity and subtle stagger.

## Validation Commands

Run after each phase:

```sh
swift build
swift test
Scripts/package_app.sh
```

When packaging fails because of resource forks or Finder metadata:

```sh
xattr -cr dist/DynamicIsland.app
Scripts/package_app.sh
```

Manual launch:

```sh
pkill -9 DynamicIsland
open dist/DynamicIsland.app
```

Direct debug launch:

```sh
pkill -9 DynamicIsland
.build/debug/DynamicIsland
```

## Debugging Notes

- DEBUG collapse logs are written to `/tmp/dynamicisland-debug.log`.
- Current collapse diagnostics include:
  - state changes
  - timer start/stop/fire
  - collapse-check entry
  - grace period pass/fail
  - hover rect contains result
  - actual collapse calls
  - `updateWindowVisibility()` collapsed handling
- If the tray does not collapse:
  - First check whether the timer is firing while state is expanded.
  - Then check whether `targetExpandedFrame` matches the visible tray.
  - Then check whether `islandState.state` is stale inside state sink handling.

## Known Fragile Areas

- `@Published` can fire before consumers reading `islandState.state` observe the committed value. State-sink work in `OverlayWindowController` currently defers via `DispatchQueue.main.async` to read committed state.
- A single large transparent interactive `NSPanel` causes hidden click-blocking areas.
- A single physically resizing panel can cause positioning/pivot regressions.
- `mouseExited` is not reliable enough to be the only collapse signal.
- Local/global mouse monitors are not reliable enough to be the only collapse signal.
- The expanded polling timer should remain the source of truth for collapse while expanded.

## Change Log

### 2026-07-03 - Context File Added

- Added this `context.md` file to preserve project architecture and current invariants.
- Documented the split-panel overlay architecture and the behavior that must not regress.
- Documented validation commands and current diagnostic log path.

### 2026-07-03 - Current Uncommitted Overlay/Animation Work

- `OverlayWindowController.swift` has uncommitted changes for:
  - split visual/collapsed-hit/expanded-interactive panels
  - centralized collapse checks
  - expanded polling timer
  - DEBUG collapse diagnostics
  - Escape diagnostic fallback
- `IslandRootView.swift` has uncommitted changes for:
  - clean inner blur/scale/opacity animation
  - subtle stagger for expanded modules
  - preserving existing tray shell spring transition

### 2026-07-03 - Phase 1 Volume Slider And Shortcut Collapse

- Added media volume state and control abstraction in `MediaController.swift`:
  - `volume` uses the `0.0...1.0` range.
  - `isVolumeControlAvailable` marks whether the current source can be controlled.
  - Spotify and Music report and set app volume through existing AppleScript media control.
  - Browser/future non-scriptable sources keep the volume slider disabled safely.
- Added a volume slider below the expanded media progress/duration controls in `ModuleViews.swift`.
- Added `ShortcutsModuleView.onShortcutLaunched` so shortcut buttons can launch first, then collapse the island.
- Wired shortcut-collapse callbacks through `IslandRootView.swift` and the interactive expanded panel in `OverlayWindowController.swift`.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-03 - Phase 2 Empty Media Launcher State

- Added `hasActiveMediaSource` to `MediaController.swift` so SwiftUI can branch without process/media detection logic in views.
- Added launcher methods to `MediaController.swift`:
  - `openMusicApp()` opens/focuses Music via `com.apple.Music` with a system app path fallback.
  - `openSpotifyApp()` opens/focuses Spotify via `com.spotify.client` with `/Applications/Spotify.app` fallback.
  - `openYouTube()` opens `https://www.youtube.com` in the default browser.
- Updated `MediaModuleView` in `ModuleViews.swift`:
  - Active media still shows artwork/title/artist, playback buttons, progress slider, and Phase 1 volume slider.
  - Empty media state shows:
    - "No app seems to be running"
    - "Wanna open one?"
    - Apple Music, Spotify, and YouTube launcher buttons.
  - Launcher buttons launch first, then call the existing collapse callback.
- Wired media launcher collapse through `ExpandedIslandView` using the same `IslandStateStore.collapse()` path as Phase 1 shortcut collapse.
- Did not modify overlay panel geometry, click-through routing, hover/timer collapse logic, shell animation, inner animation, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-03 - Phase 2.1 Collapsed Inactive Media And Browser Detection

- Updated `MediaController.swift`:
  - `hasActiveMediaSource` is cleared when no supported player/browser media is detected, removing stale artwork and visualizer state.
  - Added `isTransportControlAvailable` and `isSeekControlAvailable` so browser media can show safely without sending unsupported commands.
  - Improved browser media detection through the existing AppleScript path for Safari, Chrome, Brave, Arc, and Edge.
  - Browser detection now requires an actively playing, unmuted `<video>` or `<audio>` element and captures title/source/progress when available.
  - YouTube browser media is labeled as `YouTube`; other browser media uses host/source metadata when available.
- Updated `NotchGeometryService.swift`:
  - Added `collapsedMediaActive` input, defaulting to active behavior for compatibility.
  - Inactive collapsed geometry uses a smaller top-attached frame while keeping the same center and height.
- Updated `OverlayWindowController.swift`:
  - Observes `media.hasActiveMediaSource` and reuses existing `reposition(animated:)` so visual panel, collapsed hit panel, and canvas stay aligned.
  - Did not change collapse timer logic, click-through panel architecture, or hover behavior.
- Updated `IslandRootView.swift`:
  - Collapsed active media content transitions in/out with blur/scale/opacity.
  - Collapsed shell size animates using the existing bouncy container animation when media becomes active/inactive.
- Updated `ModuleViews.swift`:
  - Compact media UI is removed entirely when media is inactive.
  - Browser media disables unsupported transport/seek controls while still showing active media UI with placeholder artwork.
- Added geometry regression coverage in `NotchGeometryServiceTests.swift` for the smaller inactive collapsed frame.
- Known limitations:
  - Browser/YouTube playback is detected and displayed, but play/pause/previous/next/seek/volume controls are intentionally disabled for browser sessions in this phase.
  - Browser artwork/thumbnail extraction is not implemented; active browser media uses the existing safe placeholder artwork.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-03 - Phase 2.2 Media Session Vs Playback State Fix

- Fixed `MediaController.swift` state semantics:
  - `hasActiveMediaSource` now means a displayable media session exists.
  - `isPlaying` now only reflects active playback and drives visualizer animation/play-pause state.
- Spotify and Music:
  - Paused/stopped tracks with current track metadata keep `hasActiveMediaSource = true`.
  - Paused tracks keep collapsed artwork visible and show the visualizer in its static paused state.
  - `isPlaying` is no longer inferred from recent position movement when the player reports paused/stopped.
- Browser/YouTube:
  - Browser detection now returns a `media` session for loaded media elements, including paused or muted videos.
  - Playback state is returned separately as `playing` or `paused`.
  - YouTube/browser media switches expanded media from launcher state to active player UI when metadata/session exists.
  - Browser controls remain disabled for unsupported transport/seek/volume behavior.
- Added DEBUG media detection logs in `MediaController.swift` for:
  - source
  - title
  - artist/host
  - `hasActiveMediaSource`
  - `isPlaying`
  - artwork/placeholder availability
  - transport/seek availability
- Known limitations:
  - Browser/YouTube media still uses placeholder artwork unless browser thumbnail extraction is added later.
  - Browser transport/seek/volume controls remain intentionally disabled.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-03 - Phase 2.3 Media UI Observation Diagnostic Fix

- Verified there is a single shared `MediaController` instance:
  - Created once in `AppDelegate`.
  - Passed through `IslandModules` to `OverlayWindowController`, `IslandRootView`, `CompactIslandView`, `ExpandedIslandPanelView`, and `MediaModuleView`.
- Fixed compact media observation in `IslandRootView.swift`:
  - `CompactIslandView` now owns `modules.media` as an `@ObservedObject`.
  - The compact branch now reliably re-renders when `hasActiveMediaSource`, `isPlaying`, title, source, or artwork changes.
- Confirmed `MediaModuleView` already used `@ObservedObject` and branches on `media.hasActiveMediaSource`.
- Added DEBUG logs for:
  - `AppDelegate` media instance id.
  - `OverlayWindowController` media instance id.
  - Overlay media active-state changes.
  - `CompactIslandView` active/inactive branch renders.
  - `MediaModuleView` active-player/empty-launcher branch renders.
- Debug launch sample proved:
  - `MediaController` set `hasActiveMediaSource=true`.
  - `CompactIslandView` received `hasActiveMediaSource=true` and rendered `active compact`.
  - `MediaModuleView` received `hasActiveMediaSource=true` and rendered `active player`.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-03 - Phase 2.4 Browser/YouTube Detection Fix

- Updated `MediaController.swift` browser detection only.
- Brave is now checked first with:
  - AppleScript name `Brave Browser`
  - bundle identifier `com.brave.Browser`
- Added bundle identifiers and running-state diagnostics for:
  - Brave
  - Safari
  - Chrome
  - Arc
  - Edge
- Fixed Chromium JavaScript AppleScript syntax:
  - Uses Brave/Chrome-style `execute browserTab javascript ...` for JS media probing.
- Added a URL/title fallback before JavaScript probing:
  - If a tab URL contains `youtube.com/watch` or `youtu.be/`, it returns a displayable `media` session using tab title and URL.
  - This allows the expanded media module and collapsed media pill to switch to active media UI even when JavaScript probing is blocked.
  - Playback state is `paused` in fallback mode because playback state cannot be read without JavaScript permission.
- Improved browser media JavaScript:
  - Does not require unmuted media.
  - Does not require currently playing media.
  - Treats YouTube watch pages as displayable sessions even if duration/currentTime are delayed.
- Added detailed DEBUG browser detection logs for:
  - browser name
  - bundle identifier
  - running state
  - AppleScript raw result
  - AppleScript error
  - parsed media assignment state
- Debug findings:
  - Brave was running.
  - Brave URL/title AppleScript works.
  - Brave JavaScript probing was blocked because `Allow JavaScript from Apple Events` is disabled, producing error `-1723`.
  - Safari was running but Automation permission was denied, producing error `-1743`.
- Known limitations:
  - To detect actual Brave play/pause state from JavaScript, the user must enable Brave menu bar `View > Developer > Allow JavaScript from Apple Events`.
  - Without that Brave setting, YouTube watch pages can still become displayable sessions through URL/title fallback, but playback state is treated as paused.
  - Safari requires macOS Automation permission for DynamicIsland before browser tab inspection works.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-03 - Phase 2.5 Now Playing Provider Architecture

- Added media provider abstraction files:
  - `MediaDetectionProvider.swift` defines `MediaDetectionProvider`, `MediaSnapshot`, and `MediaSourceKind`.
  - `NowPlayingMediaProvider.swift` implements a System Now Playing provider using dynamically loaded MediaRemote symbols.
- Updated `MediaController.swift` provider priority:
  - System Now Playing / MediaRemote is attempted first.
  - If the system snapshot points to Spotify or Music, existing AppleScript readers are still preferred so play/pause, next/previous, seek, volume, and artwork behavior remain functional.
  - Spotify AppleScript, Music AppleScript, then browser AppleScript remain fallbacks when System Now Playing is unavailable or returns no displayable session.
- Added `sourceBundleIdentifier` tracking for selected media sessions.
- Added DEBUG provider logs for:
  - provider attempts
  - success/failure
  - selected provider
  - title/source/bundle/source kind
  - active playback/artwork/duration/progress availability
- MediaRemote compatibility:
  - MediaRemote is a private macOS framework and is loaded only at runtime with `dlopen`/`dlsym`.
  - If the framework or symbols are unavailable, the provider returns `nil` and the app gracefully falls back to existing Spotify/Music/browser detection.
  - Browser/YouTube thumbnail extraction is still not implemented; browser controls remain disabled unless a supported controllable app provider is selected.
- Did not modify overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-03 - Common App Launch Resolver

- Added `AppLaunchService.swift`:
  - Resolves supported apps automatically without file pickers/manual app selection.
  - Launch/focus order is running app by bundle identifier, LaunchServices app URL lookup, then known fallback paths.
  - Supported apps include Apple Music, Spotify, Safari, Brave, Google Chrome, Arc, Microsoft Edge, Finder, and System Settings.
  - Missing apps fail gracefully with DEBUG logs.
- Updated `MediaController.swift`:
  - Apple Music, Spotify, and YouTube launcher actions use `AppLaunchService`.
  - YouTube opens `https://www.youtube.com` in the default browser, with optional focus of a detected supported source browser first.
- Updated `ShortcutsStore.swift`:
  - Default/common app shortcuts route through `AppLaunchService`.
  - Arbitrary URL and file shortcuts still open through `NSWorkspace` without prompting the user to browse.
- Did not modify overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 2.6 YouTube Metadata Enrichment

- Added `YouTubeMetadataProvider.swift`:
  - Extracts YouTube video IDs from `youtube.com/watch`, `music.youtube.com/watch`, and `youtu.be` URLs.
  - Fetches YouTube oEmbed metadata without an API key.
  - Caches metadata by video ID to avoid refetching on every media poll.
  - Downloads thumbnail data asynchronously and logs cache hits/misses, request success/failure, title, author, and thumbnail availability in DEBUG.
- Updated `MediaController.swift` browser media handling:
  - YouTube URL/title fallback keeps `hasActiveMediaSource = true` but marks playback state as `unknown`.
  - Browser JavaScript probing now runs before URL/title fallback for Chromium browsers, so playback state/progress can be detected when browser permissions allow it.
  - Muted playing browser media counts as playing when JavaScript can read `paused`/`ended`.
  - Added stale-result protection so oEmbed responses for old videos are discarded after the user switches videos.
  - Applies oEmbed title, creator/channel (`author_name`), and thumbnail artwork to the active media state when available.
  - Added `hasPlaybackProgress` so fallback YouTube detection no longer shows fake `0:00 / 0:01` progress.
- Updated `ModuleViews.swift`:
  - Progress slider/time values show only when real duration/currentTime are available.
  - Unknown progress shows a disabled neutral rail with `--:--` timing instead of fake progress.
- Playback-state behavior:
  - MediaRemote/System Now Playing remains first priority and can provide playback state/progress/artwork when available.
  - Browser JavaScript is the fallback for real YouTube/browser playback state and progress.
  - URL/title fallback keeps the media UI active but leaves the visualizer static and progress unknown.
- Known limitations:
  - Browser transport, seek, and volume controls remain disabled for browser/YouTube sessions.
  - If MediaRemote is unavailable and browser JavaScript is blocked by browser/macOS permissions, playback state remains unknown/static by design.
- Did not modify overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, shortcuts, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 2.7 Media Source Arbitration

- Updated `MediaController.swift` source selection:
  - Provider polling no longer stops at the first displayable media session.
  - System Now Playing, Spotify AppleScript, Music AppleScript, and browser/YouTube AppleScript candidates are collected in each poll.
  - A scoring selector chooses the active displayed source, with currently playing media outranking paused displayable media.
  - Paused Spotify/Music remains displayable when nothing else is playing, but cannot block a playing YouTube/browser source.
  - Paused YouTube/browser remains displayable when nothing else is playing, but cannot block a playing Spotify/Music source.
- Added `MediaCandidate` arbitration metadata:
  - provider name
  - normalized `MediaSnapshot`
  - playback progress availability
  - optional Spotify artwork URL
  - optional YouTube URL/video ID
  - active controllable player
- Added DEBUG arbitration logs for:
  - every candidate provider/source/title/playback state/progress/artwork availability/score
  - selected provider/source/title/playback state/reason
  - source switches from previous source/title/playback state to new source/title/playback state
- Preserved YouTube stale-result protection:
  - oEmbed enrichment only applies when the selected YouTube video ID still matches.
  - Same-video enrichment is kept across polls instead of being cleared by fallback browser metadata.
- Known limitations:
  - If both MediaRemote and browser JavaScript cannot confirm YouTube playback, browser fallback remains an unknown paused/displayable candidate and will not outrank a known paused source solely by URL/title.
  - Browser transport, seek, and volume controls remain disabled for browser/YouTube sessions.
- Did not modify overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, shortcuts, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 3 Album Artwork Source Open

- Updated `MediaController.swift`:
  - Added `openActiveMediaSource()` using the currently selected/arbitrated media state without re-running detection.
  - Added `sourceKind` as published selected-source state.
  - Added `MediaSourceOpenTarget` pure resolver for mapping selected media to an open/focus target.
  - Supported targets include Spotify, Apple Music, detected browser bundle identifiers, unknown app bundle identifiers, and YouTube/default-browser fallback when browser media has no bundle identifier.
  - Added DEBUG logs for source open request, target, fallback usage, success/failure, and collapse request.
- Updated `ModuleViews.swift`:
  - Expanded media artwork is now a clickable album/thumbnail button.
  - The button opens/focuses the selected media source first, then triggers the existing collapse callback.
  - Added subtle non-spring hover feedback and accessibility label/hint.
- Updated `IslandRootView.swift`:
  - Wired artwork source-open collapse through the same callback path used by shortcut and empty media launcher actions.
- Updated `AppLaunchService.swift`:
  - `SupportedApp` is equatable for source mapping tests.
  - `openYouTube` now reports success/failure while preserving existing behavior.
- Added `MediaSourceOpenTargetTests.swift`:
  - Spotify maps to Spotify.
  - Apple Music maps to Music.
  - Brave YouTube maps to Brave bundle identifier.
  - YouTube without a bundle falls back to YouTube/default browser.
  - Unknown source without a bundle fails safely.
- Known limitations:
  - Browser media opens/focuses the owning browser app; it does not focus a specific tab.
- Did not modify media provider scoring/arbitration, MediaRemote, YouTube oEmbed enrichment, overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, shortcuts, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 3.1 Paused Media Arbitration Stability

- Updated `MediaController.swift` media arbitration:
  - Added stable `MediaSourceIdentity` usage for candidates.
  - Added pure `MediaArbitrator` selection rules.
  - Playing candidates still win immediately.
  - When no candidate is playing, the current selected paused/displayable identity is preserved if still present.
  - Async YouTube metadata enrichment no longer steals selection from a paused Spotify/Music source by itself.
  - Deterministic paused fallback remains available when there is no current selection or the current source disappears.
- Added DEBUG arbitration logs for:
  - candidate identity/source/provider/playback/progress/artwork/score/current-match state
  - selected candidate and reason
  - blocked paused-source switches when current paused media remains valid
  - source switches with previous/new identity and playback state
- Added `MediaArbitratorTests.swift`:
  - paused Spotify + paused YouTube keeps current Spotify
  - paused YouTube + paused Spotify keeps current YouTube
  - playing YouTube beats paused Spotify
  - playing Spotify beats paused YouTube
  - selected Spotify disappearing falls back to paused YouTube
  - YouTube metadata enrichment does not steal paused selection from Spotify
  - no current selected source uses deterministic paused fallback
- Did not modify media provider collection, MediaRemote, YouTube oEmbed fetching, album artwork click behavior, overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, shortcuts, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 3.2 Atomic Media Publishing And Async Guard

- Updated `MediaController.swift` media publishing:
  - Replaced the final candidate publish path with `publishSelectedCandidate(_:reason:)`.
  - UI-facing media state is now published from the selected winning candidate path only.
  - Added `selectedPublishGeneration` so async updates can prove they still belong to the current selected publish.
  - Added `MediaPublishGuard` to gate delayed artwork and YouTube oEmbed callbacks by selected identity and generation.
  - Spotify/Music artwork downloads are discarded if their source is no longer selected before the network response returns.
  - YouTube oEmbed title/creator/thumbnail results are discarded if YouTube is no longer the selected source or the publish generation is stale.
- Updated DEBUG logs:
  - selected candidate publishing now logs provider, identity, title, playback state, reason, identity-change status, and generation.
  - discarded async artwork logs request identity/generation and current selected identity/generation.
  - discarded YouTube metadata uses the `discarded-not-selected` phase when identity/generation no longer match.
- Updated `MediaArbitratorTests.swift`:
  - Added Spotify-playing versus paused-YouTube no-current-selection coverage.
  - Added publish-guard tests proving YouTube enrichment cannot publish over selected Spotify.
  - Added stale-generation guard coverage for same-identity async updates.
- Did not modify overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, album artwork button layout, AppLaunchService, shortcuts, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 3.3 Paused Switch Debounce And Native Playback Priority

- Updated `MediaController.swift` media selection/publishing:
  - Added a stateful paused/unknown switch confirmation gate between arbitration and UI publishing.
  - Playing source switches still publish immediately.
  - Same selected identity updates still publish immediately.
  - New paused/unknown identities must appear across consecutive polls for at least the confirmation interval before they can publish.
  - This prevents a single missed Spotify AppleScript poll from briefly publishing a paused YouTube fallback.
  - Pending paused switches are cancelled when the current selected identity remains valid or a playing candidate wins.
- Updated `MediaArbitrator` scoring:
  - Removed the extra browser-playing bonus so native Spotify/Music AppleScript playback is not outranked by browser/MediaRemote noise.
  - Real YouTube/browser playback still beats paused Spotify/Music.
- Added `MediaPausedSwitchGate` pure helper for testable paused-switch confirmation behavior.
- Updated DEBUG logs:
  - Pending paused switches log current identity, candidate identity, candidate title, candidate playback state, previous playing state, and pending count.
  - Existing atomic publish/enrichment logs remain in place.
- Updated `MediaArbitratorTests.swift`:
  - Added coverage for native Spotify playing beating browser playing noise.
  - Added paused-switch gate tests for first-poll block, second confirmed poll allow, and initial paused selection allow.
- Did not modify overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, album artwork button layout, AppLaunchService, shortcuts, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 3.4 Album Artwork Stability

- Updated `MediaController.swift` artwork publishing:
  - Added stable artwork key tracking with `currentArtworkKey` and `currentArtworkSourceIdentity`.
  - Added in-memory `artworkCache` keyed by artwork URL, YouTube video/thumbnail identity, or embedded artwork identity.
  - `publishSelectedCandidate` no longer clears `artworkImage` just because a poll snapshot has no embedded artwork.
  - Same selected media item plus same artwork key skips reassignment, avoiding repeated SwiftUI image refreshes.
  - Spotify artwork URL repeats reuse the existing visible image or cached image instead of redownloading/reassigning every poll.
  - Temporary missing Spotify artwork URL keeps the previous artwork visible for the same selected media identity.
  - Async artwork downloads capture source identity, artwork key, and generation; stale completions are discarded.
  - YouTube oEmbed thumbnails now publish through the same artwork-key assignment path and remain guarded by selected identity/generation.
  - Placeholder artwork is only published when there is no retained artwork for the current selected media item.
- Added DEBUG artwork logs for:
  - assignment, skip, clear, placeholder, cached artwork, downloaded artwork, and stale async discard decisions
  - selected/source identity, title, artist, old key, new key, current key, and whether visible artwork exists
- Updated `MediaArbitratorTests.swift`:
  - Added stable Spotify artwork URL key coverage.
  - Added coverage that missing Spotify artwork URL preserves the same media identity.
  - Added YouTube artwork key fallback coverage using video ID.
- Did not modify overlay panel geometry, split-panel click-through behavior, hover/timer collapse logic, shell animation, inner animation, album artwork button layout, AppLaunchService, shortcuts, file shelf, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 4A Island/Tray Page Navigation

- Updated `IslandRootView.swift` expanded tray UI:
  - Added local `ExpandedIslandPage` state with Island and Tray pages.
  - Added `ExpandedIslandPageSwitcher`, a small dark capsule tab control for Island and Tray.
  - Expanded island opens on the Island page by default each time it is presented.
  - Page switching uses a subtle blur/scale/opacity transition and respects Reduce Motion.
  - Added minimal DEBUG logging when the expanded page changes.
- Island page:
  - Preserves the existing main expanded modules:
    - media module
    - shortcuts module
    - timer module
  - Preserves existing media launcher collapse, album artwork source-open collapse, shortcut collapse, timer, sliders, and media callbacks.
  - Removed `FileShelfModuleView` from the main Island layout.
- Tray page:
  - Shows a simple Tray header and helper text.
  - Reuses the existing `FileShelfModuleView` and `FileShelfStore`.
  - Existing file shelf clear/remove/drag-out behavior remains unchanged.
- Known limitations:
  - Drag-hover expansion is not implemented yet.
  - Automatic switch to Tray during drag is not implemented yet.
  - File context menu actions, AirDrop, rename, copy, reveal in Finder, persistent shelf storage, notes, settings page, and gestures are not implemented yet.
- Did not modify OverlayWindowController, split-panel click-through behavior, collapse timer logic, collapsedHitPanel behavior, expandedPanel behavior, NotchGeometryService geometry, media provider arbitration, YouTube metadata enrichment, artwork cache/stability logic, AppLaunchService, shortcut launch logic, shell expansion animation, settings window, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 4B Island Rename And Drag-Hover Tray Drop

- Renamed previous main-page labels to Island:
  - Expanded tabs now show `Island` and `Tray`.
  - Accessibility label now says `Show Island page`.
  - README and Phase 4A context wording now use Island/Tray terminology.
- Added `IslandNavigationStore.swift`:
  - Owns expanded page selection with `.island` and `.tray`.
  - Owns transient `isFileDropTargeted` UI state.
  - Provides `showIsland()`, `showTray()`, `showTrayForFileDrag()`, and drop-target setters.
  - `IslandStateStore` remains limited to `.collapsed` and `.expanded`; no drag/peek/pinned state was added.
- Updated `IslandModules` and `DynamicIslandApp.swift`:
  - AppDelegate owns the shared navigation store.
  - `IslandModules` passes navigation to SwiftUI views and overlay callbacks.
- Updated `IslandRootView.swift`:
  - Expanded view observes `IslandNavigationStore` instead of local page state.
  - Normal expansion defaults to the Island page.
  - File-drag expansion preserves the Tray page instead of resetting to Island.
  - Existing SwiftUI `.onDrop` now drives transient Tray drop highlighting and still adds files through `FileShelfStore.add`.
  - Tray page shows a subtle highlighted drop target with `Drop files here`.
- Updated `OverlayWindowController.swift`:
  - Added minimal drag destination support to the existing collapsed pill `CollapsedHitView`.
  - Collapsed drag detection accepts file URL/Finder file drags only.
  - Dragging files over the collapsed pill calls `navigation.showTrayForFileDrag()` and `islandState.expand()`.
  - The collapsed hit area remains the existing pill-sized panel; no large invisible drop panel was added.
  - Direct drops on the collapsed hit view add files to `FileShelfStore` and clear the transient highlight.
- Updated `IslandStateStore.swift`:
  - Added `expand()` convenience while preserving the two-state model.
- Updated `IslandStateStoreTests.swift`:
  - Added coverage that `expand()` sets the existing `.expanded` state.
- Known limitations:
  - File context menu actions are not implemented.
  - AirDrop is not implemented.
  - Persistent tray storage is not implemented.
  - Notes replacement is not implemented.
  - Automatic drag-hover behavior is limited to file URL/Finder file drags over the visible collapsed pill area.
- Did not modify media provider arbitration, YouTube metadata enrichment, artwork cache/stability logic, NotchGeometryService geometry, shell animation constants, inner animation constants, AppLaunchService, shortcuts, settings, or gestures.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 4C Tray File Actions Context Menu

- Updated `ModuleViews.swift` Tray file chips:
  - Added right-click/context menu actions for each file item:
    - Open
    - Reveal in Finder
    - Copy Path
    - Copy File Name
    - Remove from Tray
  - Added `FileShelfActions` helper for macOS-native file operations:
    - `NSWorkspace.shared.open(url)` for Open
    - `NSWorkspace.shared.activateFileViewerSelecting([url])` for Reveal in Finder
    - `NSPasteboard.general` for Copy Path and Copy File Name
  - Missing files fail gracefully for Open and Reveal in Finder instead of crashing.
  - Added subtle file-chip hover styling while preserving existing chip layout.
  - Preserved existing file shelf remove button and drag-out behavior.
  - FileShelfStore duplicate handling and 12-file cap remain unchanged.
- Known limitations:
  - Rename is not implemented.
  - AirDrop is not implemented.
  - Persistent tray storage is not implemented.
  - File previews are not implemented.
  - Notes replacement is not implemented.
- Did not modify OverlayWindowController, split-panel click-through behavior, collapse timer logic, collapsedHitPanel behavior, expandedPanel behavior, IslandStateStore presentation cases, IslandNavigationStore, NotchGeometryService geometry, media provider arbitration, YouTube metadata enrichment, artwork cache/stability logic, AppLaunchService, shortcuts, timer, settings, shell animation, inner animation constants, or gestures.
- Validation status:
  - Not run in this Linux sandbox because the project imports macOS-only `AppKit`.
  - Run on macOS before shipping:
    - `swift build`
    - `swift test`
    - `Scripts/package_app.sh`

## Phase Workflow For Future Work

For every requested feature phase:

1. Inspect the relevant files first.
2. Keep changes scoped to the smallest necessary files.
3. Preserve the non-negotiable behavior listed above.
4. Build with `swift build`.
5. Run `swift test`.
6. Run `Scripts/package_app.sh` if packaging is affected or requested.
7. Update this `context.md` change log.
8. Summarize changed files and manual test steps before moving on.

### 2026-07-04 - Phase 4B.1 Expanded Tray Drop Handoff Fix

- Fixed drag-hover Tray drop regression introduced around Phase 4B/4C:
  - Dragging files over the collapsed pill expanded the island, but the Tray drop UX could disappear and the dropped files were not added.
- Root cause:
  - The collapsed AppKit drag destination expanded the island and was then ordered out.
  - AppKit could send `draggingExited` / `draggingEnded` to the collapsed drag view during that handoff.
  - That immediately cleared `IslandNavigationStore.isFileDropTargeted`, so the expanded Tray lost its drop highlight.
  - The expanded panel did not have its own SwiftUI drop destination, so after the collapsed view handed off to the expanded panel, the final drop could be lost.
- Updated `OverlayWindowController.swift`:
  - Collapsed drag exit/end no longer clears the Tray drop highlight after the island has already expanded.
  - The expanded SwiftUI drop destination now owns target-state cleanup after handoff.
- Updated `IslandRootView.swift`:
  - Added an `.onDrop(of: [.fileURL])` destination to the expanded island content.
  - Dragging files over the expanded island switches to Tray via `navigation.showTrayForFileDrag()`.
  - Dropping files in the expanded Tray adds them through the existing `FileShelfStore.add` path.
  - Unsupported drops clear the transient highlight without crashing.
- Preserved:
  - `IslandStateStore` still only has `.collapsed` and `.expanded`.
  - No new invisible drag panel was added.
  - Collapsed click-through and expanded controls are unchanged.
  - FileShelf duplicate prevention and 12-file cap are unchanged.
  - Phase 4C file context menu actions are unchanged.
- Validation status:
  - Not run in this Linux sandbox because the project imports macOS-only `AppKit`.
  - Run on macOS before shipping:
    - `swift build`
    - `swift test`
    - `Scripts/package_app.sh`

### 2026-07-04 - Phase 4D Finder-Style Tray Tiles And UI Performance Cleanup

- Updated `ModuleViews.swift` Tray file presentation:
  - Replaced small filename chips with Finder-style file tiles.
  - Each Tray item now shows a large icon/thumbnail area with the file name underneath.
  - Images can display lightweight thumbnails after loading.
  - Folders and other files fall back to native macOS file icons via `NSWorkspace.shared.icon(forFile:)`.
  - Filenames are centered under the icon and limited to two lines with middle truncation.
  - The Tray now uses a compact adaptive grid suitable for the expanded island size.
  - Existing context menu actions remain available: Open, Reveal in Finder, Copy Path, Copy File Name, and Remove from Tray.
  - Existing drag-out behavior is preserved.
- Added `FileThumbnailCache`:
  - Caches icon/thumbnail images by file path, modification date, and file size.
  - Avoids regenerating icons/thumbnails every SwiftUI render.
  - Loads image file data off the main thread, then publishes the resulting thumbnail/icon on the main thread.
  - Shows a lightweight SF Symbol placeholder while the cached icon/thumbnail is not ready.
- Updated Tray empty/drop UX:
  - Empty Tray now uses a clearer "Drop files here" Finder-shelf style empty state.
  - Drop highlight behavior from Phase 4B.1 remains unchanged.
- Updated `IslandRootView.swift` performance behavior:
  - Removed the `.id(navigation.selectedPage)` page recreation trigger.
  - Kept only the active Island or Tray page in the view tree.
  - Simplified page switching to opacity with a very small scale transition.
  - Removed heavy page-level blur from the Island/Tray transition while preserving the shell expansion animation.
- Updated `IslandNavigationStore.swift`:
  - Page and drop-target setters now no-op when the requested state is already current.
  - Drag targeting no longer repeatedly invalidates the expanded UI when the Tray is already targeted.
  - DEBUG page-change logging is now gated behind `DYNAMIC_ISLAND_VERBOSE_UI_LOGS=1`.
- Reduced noisy DEBUG UI render logs:
  - `CompactIslandView` and `MediaModuleView` render logs are now gated behind `DYNAMIC_ISLAND_VERBOSE_UI_LOGS=1`.
- Preserved drag-hover expansion, expanded Tray drop handoff, FileShelfStore duplicate prevention and 12-file cap, Tray file actions, Island/Tray navigation, media controls/source arbitration/artwork stability, split-panel click-through behavior, and `IslandStateStore` `.collapsed` / `.expanded` only.
- Known limitations:
  - AirDrop is not implemented.
  - Rename is not implemented.
  - Persistent shelf storage is not implemented.
  - Full QuickLook preview is not implemented.
  - Notes replacement is not implemented.
- Validation status:
  - Not run in this Linux sandbox because the project imports macOS-only `AppKit`.
  - Run on macOS before shipping:
    - `swift build`
    - `swift test`
    - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5A Scalable Tabs And Dedicated Timer Tab

- Updated expanded page navigation:
  - Tabs now include Island, Tray, and Timer.
  - Reused the existing `IslandNavigationStore`; no competing navigation store was added.
  - `IslandStateStore` still only has `collapsed` and `expanded`.
  - Normal click expansion still opens on the Island tab by default.
  - Drag-hover file behavior still switches directly to Tray through `showTrayForFileDrag()`.
- Updated expanded tab rendering:
  - Only the selected tab content is rendered.
  - Island tab now contains media and shortcuts only.
  - Timer was moved out of the Island tab into a dedicated Timer tab.
  - Tray tab remains unchanged and still uses the existing `FileShelfModuleView` and `FileShelfStore`.
  - Tab transition remains lightweight with opacity and tiny scale, preserving the shell expansion animation.
- Updated Timer page:
  - Dedicated Timer page shows a larger timer display.
  - Uses the existing single `TimerController` instance and one-timer model.
  - Added minimal pause, resume, and reset controller methods for the dedicated timer controls.
- Preserved:
  - Media launcher collapse.
  - Album artwork source-open collapse.
  - Shortcut launch collapse.
  - Tray drag/drop behavior.
  - Tray file context menu actions.
  - OverlayWindowController, split-panel click-through behavior, collapse timer logic, collapsedHitPanel behavior, expandedPanel behavior, NotchGeometryService geometry, media provider arbitration, YouTube metadata enrichment, artwork cache/stability logic, AppLaunchService, shortcut launch behavior, settings, and gestures.
- Known limitations:
  - AirDrop field is not implemented.
  - Stats tab is not implemented.
  - Visualizer upgrade is not implemented.
  - Full live activities are not implemented.
  - Notes are not implemented.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Corrected Phase 5B Last Active Tab And Top-Aligned Layout

- Updated expanded tab behavior:
  - Normal expansion now restores the last selected in-memory tab.
  - Drag-hover file expansion still overrides the remembered tab and opens Tray.
  - App relaunch still defaults to Island because tab persistence across launches was not added.
- Updated expanded layout:
  - Tab switcher moved closer to the top-left by reducing only excessive expanded top padding.
  - Spacing between the tab switcher and active page content was reduced.
  - Island page content now aligns top-leading instead of vertically centering.
  - Timer page top inset was removed so controls sit closer under the tab bar.
- Size correction:
  - Aggressive 35% expanded island size reduction was avoided/reverted.
  - `NotchGeometryService` expanded dimensions remain unchanged at the comfortable adaptive size.
  - Media controls, sliders, Shortcuts, Tray tiles, and Timer controls remain at their existing usable sizes.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `context.md`
- Preserved:
  - `IslandNavigationStore` remains the only expanded tab navigation store.
  - `IslandStateStore` still only has `collapsed` and `expanded`.
  - Only the active tab content is rendered.
  - OverlayWindowController, split-panel click-through behavior, collapse timer logic, collapsedHitPanel behavior, expandedPanel behavior, NotchGeometryService geometry, media stack, artwork cache/stability logic, AppLaunchService, file drop handoff, file context menu actions, file thumbnail cache logic, shortcuts launch behavior, timer engine, settings, and gestures were not rewritten.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5C Tray Split AirDrop And Files Layout

- Updated Tray tab layout:
  - Tray now uses a horizontal split layout.
  - AirDrop zone sits on the left and takes about one third of the Tray width.
  - Files zone sits on the right and takes about two thirds of the Tray width.
  - Existing Finder-style file tiles remain in the Files zone.
- Added AirDrop drop behavior:
  - Added `AirDropService.share(urls:)`.
  - AirDrop drops use `NSSharingService(named: .sendViaAirDrop)` when available.
  - If AirDrop sharing service is unavailable, dropped files are revealed in Finder as a safe fallback.
  - AirDrop-dropped files are not added to `FileShelfStore`.
- Preserved Files behavior:
  - Dropping files on the Files zone still adds them through `FileShelfStore`.
  - Duplicate prevention and 12-file cap remain unchanged.
  - Existing file context menu actions remain unchanged: Open, Reveal in Finder, Copy Path, Copy File Name, and Remove from Tray.
  - Existing drag-out behavior remains unchanged.
- Preserved drag and tab behavior:
  - Drag-hover over the collapsed island still forces Tray.
  - Last-active-tab restore for normal click expansion remains unchanged.
  - AirDrop is a zone inside Tray, not a new top-level tab.
  - Only active tab content is rendered.
- Changed files:
  - `Sources/DynamicIsland/Modules/AirDropService.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Known limitations:
  - AirDrop depends on macOS `NSSharingService` availability.
  - Stats tab is not implemented.
  - Visualizer upgrade is not implemented.
  - Full live activities are not implemented.
  - Persistent tray storage is not implemented.
  - Rename is not implemented.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5D Stats Tab

- Added expanded Stats tab:
  - Expanded navigation now includes Island, Tray, Timer, and Stats.
  - Reused the existing `IslandNavigationStore` and `ExpandedIslandPage` enum.
  - Stats is a tab/page only; `IslandStateStore` still only has `collapsed` and `expanded`.
  - Normal expansion still restores the last active tab.
  - Drag-hover file expansion still forces Tray.
- Added `SystemStatsController`:
  - App owns one shared stats controller through `IslandModules`.
  - Polls every 2 seconds.
  - Uses lightweight macOS APIs without shelling out to `top`.
  - Publishes CPU, memory, disk, network, battery, and uptime/system summary values when available.
- Added Stats UI:
  - Stats page shows compact cards for CPU, Memory, Disk, Network, Battery, and Uptime.
  - Cards use simple text and progress bars with the existing dark translucent island style.
  - Stats content is rendered only when the Stats tab is selected.
- Added tests:
  - `SystemStatsFormattingTests` covers byte formatting and percent/fraction clamping.
- Changed files:
  - `Sources/DynamicIsland/Modules/SystemStatsController.swift`
  - `Sources/DynamicIsland/Modules/IslandModule.swift`
  - `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - `Sources/DynamicIsland/State/IslandNavigationStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Tests/DynamicIslandTests/SystemStatsFormattingTests.swift`
  - `context.md`
- Known limitations:
  - Visualizer upgrade is not implemented.
  - Full live activities are not implemented.
  - Network and battery values may be unavailable on some systems.
  - Persistent tray storage is not implemented.
  - Rename is not implemented.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5E Stats Visual Redesign And Memory Fix

- Updated expanded navigation:
  - Top tab switcher now uses compact icon-only buttons.
  - Accessibility labels and hover help still expose Island, Tray, Timer, and Stats names.
  - Compact navigation keeps the Stats tab away from the notch without changing expanded island size or collapsed geometry.
- Redesigned Stats page:
  - Stats now uses a compact dashboard layout with dark translucent cards.
  - Cards use colored SF Symbol icons, large values, compact detail text, and lightweight line charts.
  - Cards shown: CPU, Memory, GPU, Network, Disk, and Battery.
  - GPU card is graceful unavailable state because no reliable lightweight GPU API is implemented.
  - Network shows download and upload rates with separate mini chart lines.
  - Battery card includes uptime as secondary detail when battery data is available.
- Corrected memory display:
  - Memory "used" now uses active + wired + compressed memory.
  - Reclaimable inactive/speculative pages are no longer counted as hard used.
  - Cached/reclaimable memory is shown separately in the Memory card detail.
  - Added code comment documenting the macOS memory formula.
- Added stats history:
  - Stats controller keeps short capped history buffers for CPU, memory, disk, network download, and network upload.
  - Histories update at the existing 2 second polling interval.
  - Charts are simple SwiftUI `Path` lines with no heavy animation.
- Added tests:
  - Memory used helper excludes cache inputs.
  - Stats history caps samples and clamps values.
- Changed files:
  - `Sources/DynamicIsland/Modules/SystemStatsController.swift`
  - `Sources/DynamicIsland/State/IslandNavigationStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Tests/DynamicIslandTests/SystemStatsFormattingTests.swift`
  - `context.md`
- Known limitations:
  - GPU usage may be unavailable because no reliable lightweight GPU metric API is implemented.
  - Full live activities are not implemented.
  - Visualizer upgrade is not implemented.
  - Network and battery values may be unavailable on some systems.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5F Timer Ring And Stats Layout Polish

- Redesigned Timer tab:
  - Timer now uses a centered animated circular countdown ring.
  - Ring starts full for a new timer and depletes as remaining time decreases.
  - Ring starts at the top and uses smooth trim animation unless Reduce Motion is enabled.
  - Ring color transitions from green toward orange/red as remaining progress approaches zero.
  - Large monospaced timer text is centered inside the ring.
  - Existing timer controls remain available: 5m, 10m, 15m, Pause/Resume, and Reset.
- Added minimal timer visual state:
  - `TimerController` now publishes `totalSeconds` so progress can be derived as remaining/total.
  - Reset returns the current timer back to its starting duration and stops it.
  - Countdown task behavior was not rewritten.
- Polished Stats card layout:
  - Increased spacing between Stats cards.
  - Moved card detail/secondary text into an internal footer row.
  - Reduced internal chart/text sizing slightly so subtitles stay inside rounded card bounds.
  - CPU, Memory, GPU, Network, Disk, and Battery cards use the same internal structure.
- Added tests:
  - Timer progress clamps below 0 and above 1.
  - Timer progress defaults to full when no total duration is available.
  - Timer progress color stages cover high, mid, and low progress.
- Changed files:
  - `Sources/DynamicIsland/Modules/TimerController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Tests/DynamicIslandTests/TimerProgressFormattingTests.swift`
  - `context.md`
- Preserved:
  - Expanded island size was not changed.
  - Tab navigation position and last-active-tab behavior were not changed.
  - Only active tab content is rendered.
  - OverlayWindowController, split-panel click-through behavior, collapse timer logic, collapsedHitPanel behavior, expandedPanel behavior, NotchGeometryService geometry, media provider arbitration, YouTube metadata enrichment, artwork cache/stability logic, AppLaunchService, file drop handoff, Tray AirDrop/files logic, shortcut launch logic, settings, and gestures were not touched.
- Known limitations:
  - Visualizer upgrade is not implemented.
  - Full live activities are not implemented.
  - Persistent tray storage is not implemented.
  - Rename is not implemented.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5G Native Visualizer And Artwork Color

- Upgraded media visualizer:
  - Replaced the simple 3-bar visualizer with a compact 12-bar native-style spectrum.
  - Bars animate smoothly while media is playing using a lightweight SwiftUI timeline.
  - Paused media, inactive media, and Reduce Motion use static/dimmed bars.
  - Collapsed island uses the compact visualizer.
  - Expanded media module also shows the upgraded visualizer in the active media layout.
- Added artwork accent color extraction:
  - Added `ArtworkAccentColorExtractor` to downsample artwork and choose a visually usable accent color.
  - Extraction ignores transparent, near-black, near-white, and low-saturation pixels when better candidates exist.
  - Added `ArtworkAccentColorCache` so extraction is cached by artwork key and not repeated every media poll.
  - Color extraction runs off the main actor from image data and falls back to white/gray if unavailable.
- Integrated with media state:
  - `MediaController` now exposes the current artwork key read-only for visual color caching.
  - Color extraction is read-only with respect to artwork and media selection.
  - Existing artwork assignment, provider arbitration, and artwork flicker safeguards were not rewritten.
- Added tests:
  - Dominant color extraction ignores black/white/transparent samples.
  - Extraction returns nil for unusable samples.
  - Accent color cache stores a color for an artwork key.
- Changed files:
  - `Sources/DynamicIsland/Modules/ArtworkAccentColorExtractor.swift`
  - `Sources/DynamicIsland/Modules/MediaController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `Tests/DynamicIslandTests/ArtworkAccentColorExtractorTests.swift`
  - `context.md`
- Preserved:
  - Visualizer remains simulated and does not use audio capture, microphone input, screen recording, or real audio analysis.
  - OverlayWindowController, split-panel click-through behavior, collapse timer logic, collapsedHitPanel behavior, expandedPanel behavior, NotchGeometryService geometry, IslandStateStore presentation cases, AppLaunchService, file context menu actions, file thumbnail cache, file drop handoff, Tray AirDrop/files logic, TimerController engine, SystemStatsController polling, shortcut launch logic, settings, gestures, and shell animation were not touched.
- Known limitations:
  - Visualizer is simulated, not real audio analysis.
  - Full live activities are not implemented.
  - Persistent tray storage is not implemented.
  - Rename is not implemented.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5H Notch-Integrated Island Shape

- Added notch-integrated shell shape:
  - Added `NotchMergedIslandShape` as a lightweight SwiftUI `Shape`.
  - Shape adds subtle curved top shoulders so the shell visually blends toward the physical notch.
  - Collapsed and expanded shells both use the same shape with different conservative shoulder constants.
  - Existing bottom rounded shell treatment is preserved.
- Added notchless fallback:
  - `IslandLayoutStore` now carries the existing `NotchGeometryService` hardware-notch signal.
  - Notched displays use the shoulder shape.
  - Notchless/external displays fall back to the normal top-attached rounded shell.
- Kept behavior visual-only:
  - Surface frames, collapsed hit panel frame, expanded panel frame, and click-through architecture were not resized or rewritten.
  - Existing bouncy shell animation and inner blur/scale/opacity transitions remain unchanged.
  - Content layout was not changed for this phase.
  - The only `OverlayWindowController` change passes the existing notch flag into the expanded SwiftUI shell host; panel architecture, collapse logic, and hit testing were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/NotchMergedIslandShape.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Preserved:
  - Media, tray, AirDrop/files, timer, stats, shortcuts, settings, gestures, app launch, media providers, artwork stability, file thumbnail cache, and system stats polling were not changed.
  - `IslandStateStore` still only has `collapsed` and `expanded`.
- Known limitations:
  - Curve constants may need tuning per Mac model.
  - This is visual-only shell integration, not a full hardware notch mask.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5H Correction Remove Inward Cut

- Removed the broken inward-cut shell path:
  - Removed the custom shell path from the final rendering path.
  - Main collapsed and expanded shells use the normal `UnevenRoundedRectangle` top-attached rounded shape again.
  - No inward scoop/bite remains in the shell path.
- Replaced with safer outward shoulder layering:
  - Added `NotchShoulderBlend`, which draws subtle outward ellipses behind the main shell.
  - Collapsed shoulder starting size is 28x22 with side inset/offset of 14 and y offset -8.
  - Expanded shoulder starting size is 44x28 with side inset/offset of 24 and y offset -10.
  - Shoulders are decorative only and do not alter hit testing, panel frames, layout, or content clipping.
  - Shoulder layer uses `.allowsHitTesting(false)`.
  - Added `notchShoulderBlendEnabled`; setting it to `false` restores the plain rounded shell immediately.
  - Shoulder size/offset/opacity constants are isolated for quick tuning.
- Preserved:
  - Collapsed hit panel frame, expanded panel frame, click-through architecture, collapse timer logic, NotchGeometryService geometry, media, visualizer, timer, stats, tray/AirDrop/files, shortcuts, settings, and gestures were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/NotchShoulderBlend.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Known limitations:
  - Shoulder constants may still need visual tuning per Mac model.
  - This remains visual-only shell blending, not a hardware notch mask.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
