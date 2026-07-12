# DynamicIsland Project Context

Last updated: 2026-07-06

## Purpose

DynamicIsland is a native macOS SwiftUI/AppKit prototype that turns the MacBook notch area into a Dynamic Island / NotchNook-style utility overlay. It is a direct-download macOS app, not a Mac App Store app.

The app targets macOS 14.6+ and uses Swift Package Manager, SwiftUI views hosted in AppKit overlay panels, and a menu bar accessory app model.

## Current Stable Baseline

- Active baseline: **Phase 8C15 stable final**.
- Active Git state after merging the fixed zip back into the original repo:
  - Branch: `phase-5h2-shoulder-tuning`
  - Commit: `de337d3`
  - Tag: `phase-8c15-stable-final`
- Validation on macOS passed after the merge:
  - `swift build`
  - `swift test` with 57 tests and 0 failures
  - `Scripts/package_app.sh`
  - Packaged app path: `dist/DynamicIsland.app`
- Current known non-blocking warning:
  - `FileThumbnailCache` emits a Swift concurrency warning about capturing a non-Sendable `self` inside a `@Sendable` closure.
  - This warning does not currently block build, test, package, or launch.
- Current user-confirmed stable behavior:
  - Collapsed swipe left/right changes exactly one song per physical swipe.
  - Album artwork flips correctly and uses the real new cover.
  - Visualizer accent color follows the real displayed artwork, not stale previous artwork.
  - Collapsed swipe down expands fully.
  - Expanded swipe up collapses when `Expanded Island Gestures -> Swipe Up -> Collapse` is set.
  - Media module next/previous and natural media changes also trigger album-cover flip.
- Current responsiveness tuning:
  - `mediaSwipeQuietPeriod = 0.045`
  - `mediaSwipePostCommandLockoutSeconds = 0.05`
  - These values were user-tested as responsive and currently stable. Increase the lockout if aggressive trackpad swipes ever double-skip.

## Non-Negotiable Behavior To Preserve

- The stable **single host panel / shape-aware hit-testing** architecture must remain intact.
- Do not return to the old split-panel architecture unless there is a proven, isolated reason and a migration plan.
- The island panel must not block clicks outside the visible collapsed/expanded island surface.
- Collapsed pill click-through outside the visible pill must remain fixed.
- Collapsed pill itself remains hoverable/clickable and can expand.
- Expanded island internal buttons, sliders, tabs, shortcuts, timer controls, stats, Tray file tiles, AirDrop zone, and settings controls remain clickable.
- Expanded island must collapse on the intended outside-hover/leave behavior and through the configured expanded swipe-up gesture.
- Collapsed swipe down must expand without immediately collapsing from trackpad momentum/tail events.
- Collapsed swipe left/right must remain one physical swipe = exactly one media next/previous command.
- Album artwork flips must wait for the real new artwork image/revision before midpoint swap.
- Visualizer accent color must be keyed from the actual displayed artwork image key/revision, not the early selected artwork key.
- Expanded tray shell/background keeps its bouncy/elastic shell behavior.
- Inner expanded components use clean blur/scale/opacity animation without spring bounce.
- `IslandStateStore` must remain limited to `.collapsed` and `.expanded`.
- Do not rewrite `OverlayWindowController` unless a specific feature requires it; it is the most fragile file.
- Do not remove or bypass the artwork-image/revision guards that prevent stale covers and stale visualizer colors.

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
  - Current stable architecture is the **Phase 6B single host panel with shape-aware hit testing**:
    - One stable island panel hosts the SwiftUI island surface.
    - The panel does not physically resize between collapsed and expanded during the normal morph.
    - SwiftUI owns the visual collapsed/expanded surface morph.
    - `IslandLayoutStore.updateLocal(...)` converts screen-space frames into panel-local frames.
    - Click-through is handled by setting window-level mouse event behavior from the currently visible island rect.
  - Preserve the stable shell/content sequencing:
    - Expansion: shell establishes first; inner content mounts hidden and reveals after the shell is ready.
    - Collapse: inner content exits first; shell collapses after.
  - Collapse and hover containment must use the current visible/target frames and should not regress to top-left origin bugs.
  - Trackpad scroll gestures are handled here:
    - Collapsed horizontal media gestures use end-of-swipe resolution.
    - Collapsed swipe down expansion remains immediate and separate.
    - Expanded swipe up collapse must not consume the momentum tail from collapsed swipe-down expansion.
  - Do not bring back hidden click-blocking transparent areas.
  - Do not reintroduce separate presentation states into `IslandStateStore`.

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
  - Stores overlay enablement, launch-at-login, animation intensity, module flags, gesture mappings, tab/module visibility, sizing inputs, timer presets, stats settings, and media/tray controls.
  - Expanded gesture mappings include `expandedSwipeUpAction`; the UI exposes this under `Settings -> Gestures -> Expanded Island Gestures`.
  - Size settings are wired into the current stable geometry path where supported; avoid bypassing `NotchGeometryService` and `IslandLayoutStore`.

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
  - Media detection/arbitration supports System Now Playing/MediaRemote, Spotify, Apple Music, and browser/YouTube fallbacks.
  - Publishes selected media identity, artwork keys, actual displayed artwork image key/revision, transport control availability, and flip requests.
  - Album-cover flip and visualizer color depend on the actual displayed image/revision path; avoid broad changes without testing Spotify, Apple Music, YouTube/browser, paused/playing arbitration, artwork download timing, and natural track changes.

- `Sources/DynamicIsland/Modules/FileShelfStore.swift`
  - Temporary in-memory file shelf.

- `Sources/DynamicIsland/Modules/ShortcutsStore.swift`
  - App/file/URL shortcut launcher.

- `Sources/DynamicIsland/Modules/TimerController.swift`
  - Timer module state and controls.

## Current UI/Interaction Requirements

### Collapsed

- Small top-attached pill around the notch.
- Album art on the left when a displayable media session exists.
- Native-style compact 12-bar simulated visualizer on the right.
- Hovering the collapsed pill can reveal the compact media preview.
- Only the visible pill/hover surface should receive interaction.
- Hidden expanded/canvas areas must not intercept clicks.
- Trackpad gestures:
  - Swipe left over collapsed media pill: next track.
  - Swipe right over collapsed media pill: previous track.
  - Swipe down over collapsed pill: expand island.
  - One continuous left/right swipe must fire exactly one media command.

### Expanded

- Centered top-attached tray/island surface.
- Internal controls are clickable.
- Tabs/pages currently include Island, Tray, Timer, and Stats.
- Expanded swipe up can collapse the island when configured in Settings.
- Tray collapses on outside hover/leave using the current stable containment behavior.
- Escape can be used as a diagnostic fallback when present.
- The shell keeps bouncy/elastic expansion/collapse behavior.
- Inner modules animate with clean blur/scale/opacity and subtle stagger.

## Validation Commands

Run after each phase:

```sh
swift build
swift test
Scripts/package_app.sh
```


When `Scripts/package_app.sh` is not executable after unzipping/copying a project, run:

```sh
chmod +x Scripts/package_app.sh
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

### 2026-07-04 - Phase 5H Asset-Backed Shoulder Blend

- Replaced procedural shoulder rendering with asset-backed rendering:
  - Main collapsed and expanded shells remain the normal rounded `UnevenRoundedRectangle`.
  - Added `NotchShoulderBlend` as a visual-only background layer that renders:
    - `notch_shoulder_collapsed`
    - `notch_shoulder_expanded`
  - Shoulder layer is centered at the top of the shell with fixed sizing/offset constants and `.allowsHitTesting(false)`.
  - `notchShoulderBlendEnabled` still disables the entire shoulder layer and restores the plain shell immediately.
- Added SwiftPM resource wiring:
  - Added `Sources/DynamicIsland/Assets.xcassets`.
  - Added placeholder image sets for `notch_shoulder_collapsed` and `notch_shoulder_expanded`.
  - Updated `Package.swift` to process `Assets.xcassets`.
  - Updated `Scripts/package_app.sh` to copy the generated SwiftPM resource bundle into the packaged app and clear xattrs before signing.
- Important current limitation:
  - The image sets are present but currently empty placeholders in this workspace.
  - Until actual image files are added to those two image sets, no shoulder artwork will appear even though the rendering and packaging path is now correct.
- Changed files:
  - `Package.swift`
  - `Scripts/package_app.sh`
  - `Sources/DynamicIsland/Assets.xcassets/Contents.json`
  - `Sources/DynamicIsland/Assets.xcassets/notch_shoulder_collapsed.imageset/Contents.json`
  - `Sources/DynamicIsland/Assets.xcassets/notch_shoulder_expanded.imageset/Contents.json`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/NotchShoulderBlend.swift`
  - `context.md`
- Preserved:
  - OverlayWindowController architecture, hit panel frames, click-through behavior, collapse timer logic, NotchGeometryService geometry, media, tray, timer, stats, shortcuts, settings, and gestures were not changed.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5H.1 Collapsed Outward Ellipse Shoulder Tuning

- Disabled asset-backed shoulder rendering for the active path:
  - `notchShoulderUseAssets = false`
  - Procedural ellipses are now the active rendering path.
  - Asset-backed shoulder support remains inactive and is not used for the current visual.
- Tuned collapsed shoulder rendering to procedural outward ellipses only:
  - Main shell remains the normal rounded `UnevenRoundedRectangle`.
  - Added two visual-only black ellipses behind the shell for collapsed mode.
  - Collapsed tuning constants are centralized:
    - `collapsedShoulderWidth = 34`
    - `collapsedShoulderHeight = 28`
    - `collapsedShoulderSideInset = 10`
    - `collapsedShoulderYOffset = -9`
    - `collapsedShoulderOpacity = 1.0`
  - `notchShoulderDebugTint = false` was added for visual placement checks.
- Expanded shoulder intentionally remains disabled:
  - `expandedShoulderEnabled = false`
  - Expanded shell stays normal/unchanged until collapsed tuning is visually correct.
- Preserved:
  - No custom inward-cut shape path is used.
  - OverlayWindowController, hit panel frames, click-through behavior, collapse timer logic, NotchGeometryService geometry, media, visualizer, timer, stats, tray/AirDrop/files, shortcuts, settings, and gestures were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/NotchShoulderBlend.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5H.2 Shoulder Tuning And Expanded Ellipse Blend

- Tuned collapsed shoulder constants to make the shoulder subtler:
  - `collapsedShoulderWidth = 32`
  - `collapsedShoulderHeight = 25`
  - `collapsedShoulderSideInset = 8`
  - `collapsedShoulderYOffset = -10`
  - `collapsedShoulderOpacity = 0.92`
- Kept the same safe ellipse-layer approach:
  - Main shell remains the normal rounded `UnevenRoundedRectangle`.
  - No custom path, masking, subtraction, or clipping was introduced.
  - `notchShoulderDebugTint = false` remains the default, with red/blue tint available for manual tuning only.
- Enabled expanded shoulders using the same procedural ellipse layer:
  - `expandedShoulderEnabled = true`
  - `expandedShoulderWidth = 48`
  - `expandedShoulderHeight = 30`
  - `expandedShoulderSideInset = 18`
  - `expandedShoulderYOffset = -10`
  - `expandedShoulderOpacity = 0.94`
- Preserved:
  - Asset-backed rendering remains disabled for the active path: `notchShoulderUseAssets = false`.
  - OverlayWindowController, hit panel frames, click-through behavior, collapse timer logic, NotchGeometryService geometry, IslandStateStore, media, visualizer, timer, stats, tray/AirDrop/files, shortcuts, settings, and gestures were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/NotchShoulderBlend.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5H Paused For Later Visual Polish

- Parked notch shoulder merge work for now:
  - `notchShoulderBlendEnabled = false`
  - The normal clean rounded shell is now the default active shell again for both collapsed and expanded states.
  - Existing shoulder code remains in the codebase for later visual polish and is currently inactive by default.
- Parked related visual refinement work:
  - Expansion morph transition polish is also parked for later visual work.
- Preserved:
  - OverlayWindowController, hit panels, click-through behavior, collapse logic, media, tray, timer, stats, and visualizer were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/NotchShoulderBlend.swift`
  - `context.md`

### 2026-07-04 - Phase 5I Unified Expansion Morph Transition

- Improved the expanded visual handoff so expansion reads as one continuous component:
  - The expanded shell now starts from collapsed-like width and height scale anchored at the top.
  - The expanded shell no longer starts from the previous oversized blurred pop-in state.
  - Shell opacity now stays nearly solid during the first expansion frames so there is no obvious full-size flash.
- Added a visual-only collapsed ghost during early expansion:
  - The expanded panel briefly renders a compact ghost pill centered at the top while the expanded shell grows underneath it.
  - The ghost is removed shortly after the shell begins expanding.
  - This is visual-only and does not affect layout, hit testing, or panel frames.
- Preserved the clean inner-content timing:
  - Expanded inner content still uses the existing clean blur/scale/opacity treatment.
  - Inner content reveal is delayed slightly longer so the shell establishes itself before pages and controls appear.
- Preserved existing behavior:
  - OverlayWindowController split-panel architecture was not rewritten.
  - Collapsed hit panel frame, expanded panel frame, click-through behavior, collapse timer logic, mouse containment logic, drag/drop behavior, Island/Tray/Timer/Stats tabs, media, tray, timer, stats, settings, gestures, and notch shoulder disablement were not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Known limitations:
  - True `matchedGeometryEffect` across separate `NSPanel` windows is not possible here, so the collapsed-to-expanded morph is simulated with shell scaling and a short-lived compact ghost.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5I.1 Expansion Collapse Motion Polish

- Polished shell motion curves:
  - Expansion shell animation now uses a more damped spring so the end-of-expansion wobble is removed.
  - Collapse shell animation now uses a tighter critically damped spring so the shell shrinks cleanly toward the top-center anchor instead of feeling detached first.
  - Inner content reveal was delayed slightly more so the shell morph establishes first and the page content still arrives cleanly without bounce.
- Adjusted collapse panel handoff timing:
  - `OverlayWindowController` now keeps the expanded visual panel alive briefly during collapse before ordering it out.
  - The collapsed visual panel and collapsed hit panel still return immediately.
  - This gives the expanded shell time to visually shrink back into the notch area instead of disappearing too early during the split-panel handoff.
- Performance/scope:
  - No per-frame logging, extra timers, geometry rewrites, or page-content rewrites were added.
  - Only the active tab content is still rendered.
- Preserved:
  - OverlayWindowController architecture was not rewritten.
  - Panel frames, hit testing, click-through behavior, collapse timer logic, drag/drop behavior, Island/Tray/Timer/Stats tabs, last-active-tab restore, media, tray AirDrop/files, timer, stats, settings, gestures, and parked notch shoulder disablement were not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Known limitations:
  - The collapsed-to-expanded and expanded-to-collapsed morph remains a simulated handoff across separate `NSPanel` windows, so tuning is timing-based rather than true matched geometry.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5I.2 Animation Performance Polish

- Added a transient shell-morph performance flag:
  - `IslandLayoutStore` now carries `isShellMorphing`.
  - This remains view-local/transient behavior only; `IslandStateStore` still only has `collapsed` and `expanded`.
  - The flag turns on at shell morph start and clears shortly after the shell animation window ends.
- Deferred heavy inner content until the shell is established:
  - Expanded active page content is no longer built during the earliest shell-morph frames while it is still fully hidden.
  - Inner content reveal is delayed slightly more so the shell morph gets priority before Island/Tray/Timer/Stats page content is created.
- Simplified expensive visuals during shell morph only:
  - Audio visualizer pauses its `TimelineView` animation and shows static bars temporarily.
  - Stats charts temporarily render a lighter path set and skip the secondary line while the shell is morphing.
  - Tray file thumbnail loading is deferred until the shell morph completes instead of starting immediately on tile appearance.
  - Shell shadow is temporarily reduced during shell morph to cut rendering cost without changing the final look.
- Tightened debug logging defaults:
  - `FileShelfActions` DEBUG logging is now gated behind `DYNAMIC_ISLAND_VERBOSE_UI_LOGS=1`.
- Preserved:
  - Phase 5I / 5I.1 visual result was kept intact.
  - OverlayWindowController architecture, panel frames, click-through behavior, collapse timer logic, collapse behavior, tabs/pages/features, media/tray/timer/stats logic, artwork extraction/caching, file drop handoff, AirDrop behavior, settings, gestures, and parked notch shoulder disablement were not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `context.md`
- Known limitations:
  - Performance smoothing remains timing-based within the existing split-panel simulated morph; it does not turn separate panels into true matched geometry.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5I.3 Collapse Shell-Only Performance Fix

- Added collapse-specific transient shell state:
  - `IslandLayoutStore` now also carries `isCollapseShellOnly`.
  - This remains visual/transient only; `IslandStateStore` still only has `collapsed` and `expanded`.
  - Collapse sets shell-only mode immediately when the shrink starts and clears it after the collapse morph window ends.
- Collapse now removes heavy expanded content while the shell shrinks:
  - The expanded page switcher is not rendered during collapse shell-only mode.
  - Island/Tray/Timer/Stats active page content is not built during collapse shell-only mode.
  - This means the shrinking expanded shell no longer carries media controls, tray files, timer ring, stats charts, or other active tab content through the collapse animation.
- Preserved the current visual handoff:
  - The expanded shell still stays alive briefly so it can shrink toward the top-center/notch area.
  - The collapse direction and simulated morph behavior from Phase 5I / 5I.1 were preserved.
  - Expansion behavior was not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Known limitations:
  - The morph remains a simulated handoff across separate `NSPanel` windows rather than true matched geometry.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5I.4 Symmetric Reverse Morph

- Made collapse use the same shell morph as expansion in reverse:
  - Expanded shell and collapsed shell now use the same shell animation curve for both directions.
  - Collapse no longer uses a separate tighter curve; it now follows the same smooth morph timing as expansion.
- Added reverse compact-pill ghost timing for collapse:
  - Expansion still starts with the compact ghost visible and fades it out after the shell grows.
  - Collapse now does the inverse: the compact ghost fades back in during the later part of the shrink.
  - This makes the expanded-to-collapsed transition read more like the exact reverse of the collapsed-to-expanded morph.
- Preserved:
  - Collapse still uses shell-only mode for performance while shrinking.
  - Expanded panel handoff timing, split-panel architecture, click-through behavior, collapse logic, tabs/pages, media/tray/timer/stats logic, and parked notch shoulder disablement were not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Known limitations:
  - The morph remains a simulated handoff across separate `NSPanel` windows rather than true matched geometry.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Atoll Reference-Guided Morph Cleanup

- Reference notes only, no GPL code copied:
  - Reviewed Atoll only for architectural lessons.
  - No GPL source was copied or ported into this project.
  - Key lesson: visually, the island should read like one top-centered shell surface changing size and shape in place.
- Future notch-hugging direction clarified:
  - Notch shoulder ellipses remain parked/disabled: `notchShoulderBlendEnabled = false`.
  - Shoulder debug tint was also returned to its normal disabled state.
  - Future physical-notch polish should prefer an Atoll-like top-attached asymmetric shell:
    - small top corner radius
    - larger bottom corner radius
    - top edge flush to the top/notch area
  - Future notch polish should not use ellipse wings, inward bites, masks, or subtractions.
- Collapse handoff adjusted to better mimic a single-surface morph:
  - The compact ghost layer now stays mounted from the start of collapse instead of appearing only near the final frame.
  - Its opacity ramps in during the later part of collapse while the expanded shell shrinks out.
  - This keeps collapsed compact media content warmed ahead of the final handoff and avoids a last-frame album art / visualizer spawn hitch.
  - Because shell morph mode is already active, the compact visualizer stays static during the morph and does not start `TimelineView` animation during the critical collapse frame.
- Preserved:
  - OverlayWindowController split-panel architecture was not rewritten.
  - Click-through behavior, collapse logic, media arbitration, artwork publishing stability, timer/stats/tray logic, settings, gestures, and the current expansion behavior were not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/NotchShoulderBlend.swift`
  - `context.md`
- Known limitations:
  - The morph is still a simulated handoff across separate `NSPanel` windows rather than a true one-window Atoll-style surface.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5I.5 Collapse Handoff Debug And Isolation

- Added temporary collapse handoff debug/isolation flags, defaulting off:
  - `collapseHandoffDebug = false`
  - `disableCollapsedArtworkDuringHandoff = false`
  - `disableCollapsedVisualizerDuringHandoff = false`
  - These are temporary local SwiftUI debug controls for visually proving the compact handoff layer and isolating whether artwork or the visualizer is responsible for a hitch.
- Moved the collapse compact handoff layer into the real expanded SwiftUI render path:
  - The collapse shell-only path in `ExpandedIslandView` now renders a `CompactHandoffGhostView` instead of an empty clear placeholder.
  - This handoff view uses the actual compact media path ingredients:
    - current already-published artwork
    - compact layout
    - compact visualizer path
  - During shell morph, the compact visualizer remains static because shell-morph mode is still active.
- Removed the old collapse-only ghost dependency from `OverlayWindowController`:
  - The overlay-controller ghost is no longer relied on for collapse.
  - Collapse handoff now comes from the same SwiftUI visual tree that renders the shrinking expanded shell.
- What real fix was applied:
  - The collapse compact content is now created inside the expanded shell-only collapse path early enough to be warmed before final panel handoff.
  - This directly addresses the previous issue where compact album art/visualizer could still appear like a late final-frame spawn.
- Preserved:
  - Split-panel click-through architecture was not rewritten.
  - OverlayWindowController collapse timing, panel frames, media arbitration, artwork stability, timer/stats/tray logic, settings, gestures, and parked notch shoulder disablement were not changed beyond removing the obsolete collapse ghost dependency.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Known limitations:
  - The morph remains a simulated handoff across separate `NSPanel` windows rather than true matched geometry.
  - The debug flags are implemented for local visual proof and isolation, but remain disabled by default.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5J Single Visual Surface Morph

- Used Atoll only as architectural reference, with no GPL code copied:
  - The lesson applied here is one visual shell surface changing state in place, while input/hit areas can remain separate.
  - No GPL source was copied or ported.
- Visual shell ownership moved to one visual-only panel:
  - The existing visual `panel` now remains active for both collapsed and expanded states.
  - `IslandRootView` in that visual-only panel now renders:
    - full collapsed pill visuals when collapsed
    - expanded shell-only visuals when expanded
  - The visual shell/morph no longer hands off between a collapsed-only visual panel and an expanded visual panel.
- `expandedPanel` is now a transparent interactive overlay:
  - `expandedPanel` no longer owns/draws the black shell background.
  - It now hosts only `ExpandedIslandView` content/controls as an overlay aligned over the visual shell underneath.
  - During collapse it can disappear without taking the shell/morph with it.
- `collapsedHitPanel` remains the small collapsed click target:
  - Collapsed click-through safety was preserved.
  - The visual panel still ignores mouse events.
  - `expandedPanel` remains the interactive layer for expanded controls.
- Morph timing is now driven centrally from `OverlayWindowController`:
  - `isShellMorphing` and `isCollapseShellOnly` are now driven by state changes in the controller again.
  - This keeps the single visual surface and the interactive overlay in sync without giving shell ownership back to `expandedPanel`.
- Preserved:
  - Split-panel click-through architecture still exists.
  - No giant interactive transparent panel was introduced.
  - `collapsedHitPanel` was not removed.
  - Expanded controls, sliders, tabs, timer controls, tray interactions, drag-hover Tray behavior, media logic, timer logic, stats logic, settings, gestures, and parked notch shoulder disablement were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Known limitations:
  - This is still a simulated one-surface morph across separate AppKit panels, not a literal one-window design.
  - Future notch hugging should still prefer a top-attached asymmetric shell shape, not ellipse shoulder blobs.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5J.1 Visual Surface Layout Refactor

- Added shared expanded layout metrics in `IslandRootView.swift`:
  - Centralized shell content paddings for collapsed and expanded states.
  - Added `ExpandedIslandLayoutMetrics` to define:
    - expanded horizontal/top/bottom padding
    - tab switcher height
    - spacing between tabs and page content
    - page height
    - adaptive Island/Tray/Timer/Stats sizing values
  - `IslandSurface` and the expanded interactive overlay now use the same layout contract instead of separate magic numbers.
- Aligned `expandedPanel` interactive content to the visual shell content rect:
  - `ExpandedIslandView` now wraps its content in the same expanded padding box as the visual shell.
  - Page content is clipped to the available content region so controls do not draw outside the shell.
  - This keeps the transparent interactive overlay aligned to the visible black shell underneath.
- Retuned expanded page layouts for the real shell height:
  - Island page:
    - adaptive media/shortcuts widths
    - reduced column spacing
    - divider height now scales from available page height instead of fixed `220`
  - Tray page:
    - AirDrop width now uses adaptive metrics
    - file area stays within the shell content region
  - Timer page:
    - timer ring size is now adaptive to available height
  - Stats page:
    - compact adaptive card widths/heights now derive from available content size
    - card spacing remains compact for the real expanded shell height
- Delayed inner content until the shell is ready:
  - Expanded content reveal delay was increased so tabs and page content appear near the end of shell expansion instead of floating early.
- Removed remaining broad bounce sources:
  - Root shell/content animation now uses a shared `easeInOut` timing instead of the previous broad spring.
  - The old aggressive `blurBounce` transition was reduced to subtle blur/scale values instead of `blur 100 / scale 0.1`.
- Preserved:
  - Split-panel click-through architecture remains intact.
  - The visual panel still owns the shell.
  - `expandedPanel` remains the transparent interactive overlay.
  - `collapsedHitPanel` remains the small collapsed click target.
  - Media logic, artwork stability, YouTube/native provider logic, timer engine, stats polling, tray logic, AirDrop, settings, gestures, and parked notch shoulder disablement were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Known limitations:
  - This still relies on the simulated one-surface morph architecture from Phase 5J rather than a literal one-window shell.

### 2026-07-04 - Phase 5J.2 Expanded Page Fit And Internal Component Scaling

- Fixed expanded page fit for the smaller shared shell content rect:
  - Kept page clipping in place, but reduced internal component sizing so important controls fit before reaching the clip boundary.
- Updated expanded layout metrics in `IslandRootView.swift`:
  - Added explicit timer space reservation values:
    - `timerHeaderHeight`
    - `timerControlsHeight`
    - `timerVerticalSpacingTotal`
    - `timerReservedHeight`
  - Retuned `timerRingSize` to reserve real title/control space before sizing the ring.
  - Added explicit `mediaMaxHeight` and `shortcutsMaxHeight` derived from `pageHeight`.
  - Reduced `dividerHeight` so it cannot overrun the actual page region.
- Fixed Island page child sizing:
  - `MediaModuleView` now receives `availableHeight: metrics.pageHeight`.
  - Media and Shortcuts columns now both receive explicit `height: metrics.pageHeight` frames and remain top-aligned/clipped inside the page region.
- Fixed Timer page clipping:
  - Timer ring now scales from reserved space instead of using nearly the full page height.
  - Timer controls were compacted with smaller spacing/font sizing.
  - Added a `ViewThatFits` fallback so controls can split into two rows on tighter widths without hiding controls.
  - Ring stroke/text scale down slightly on smaller ring sizes.
  - Timer page no longer clips its bottom controls in the intended compact shell layout.
- Fixed Media module vertical fit in `ModuleViews.swift`:
  - Added a constrained expanded layout path activated when `availableHeight` is supplied.
  - Reduced artwork size, metadata fonts, vertical spacing, transport button size, and slider/time spacing for the constrained expanded layout.
  - Kept media logic, source-open artwork behavior, playback controls, progress, and volume slider intact.
  - Media player no longer relies on clipping to hide bottom controls in the intended compact shell layout.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
- Validation passed:
  - `swift build`

### 2026-07-04 - Phase 5J.3 Center Constrained Expanded Media Layout

- Centered constrained expanded media content inside the allocated Island-page media column:
  - `MediaModuleView` now vertically centers its constrained expanded content when `availableHeight` is supplied.
  - The media group uses flexible top and bottom spacers so artwork, metadata, transport controls, progress, and volume stay grouped together while sitting inside the actual available height.
  - The constrained content is fixed to its intrinsic vertical size before centering so clipping remains a safety net instead of the visible layout solution.
- Slightly tightened constrained media spacing:
  - Reduced constrained artwork size and a few internal spacing values by small amounts so the bottom controls no longer graze the clipping boundary.
  - No controls were removed.
- Preserved:
  - Island page column frames and top-level HStack alignment remain unchanged.
  - Timer, Stats, Tray, shell morph animation, collapse behavior, media logic, artwork/source-open behavior, click-through architecture, and parked notch shoulder behavior were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5J.4 Final Media Fit And Mouse Leave Rect Fix

- Made constrained expanded media layout structurally shorter in `ModuleViews.swift`:
  - The constrained Island media path now uses a dedicated compact layout instead of only shrinking the old expanded stack.
  - Visualizer moved into the header metadata row using the compact visualizer variant.
  - Transport controls, progress/time section, and volume row were tightened into a smaller vertical budget.
  - Added a compact volume row with a small speaker icon and minimal slider padding.
  - Added `minimumScaleFactor` to constrained title/artist/source labels.
  - Added `ViewThatFits(in: .vertical)` so an even tighter compact variant is used automatically if the first compact layout would still exceed the available height.
  - Volume slider no longer depends on clipping and remains inside the constrained media column.
- Fixed expanded mouse-leave collapse containment in `OverlayWindowController.swift`:
  - Collapse hover detection no longer uses the full expanded overlay/canvas panel frame.
  - Added `visibleExpandedShellScreenFrame()` to derive the actual visible expanded shell rect from:
    - visual canvas panel frame
    - `layoutStore.expandedSurfaceFrame`
  - Mouse-leave containment and the far-below-top fallback now use the visible expanded shell rect with the existing hover tolerance.
  - This restores expected collapse when the mouse leaves the visible black expanded island.
- Preserved:
  - Visual surface architecture, split-panel click-through behavior, collapse smoothness, expansion morph behavior, media logic, timer, stats, tray, app launch logic, and parked notch shoulder behavior were not redesigned.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5J.5 Final Expanded Hover Tolerance Tightening

- Tightened the final expanded mouse-leave tolerance in `OverlayWindowController.swift`:
  - Added `expandedHoverTolerance`.
  - Reduced the visible expanded shell hover margin from `10` px to `2` px.
  - Collapse containment still uses `visibleExpandedShellScreenFrame()`, but now only adds a minimal safety margin around the visible shell.
  - Existing collapse grace timing and far-below-top fallback behavior were preserved.
- DEBUG boundary logging now includes:
  - `expandedHoverTolerance`
- Preserved:
  - Expanded layout, media fit, panel frames, split-panel architecture, morph timing, collapse grace logic, click-through behavior, and all module logic were not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5J.6 Premium Motion Re-Polish

- Retuned shell/container timing in `IslandRootView.swift`:
  - Normal shell/content timing was slowed from `0.26s` to `0.38s` ease-in-out.
  - Reduce Motion still uses the simpler `0.24s` ease-in-out path.
  - This restores a more visible grow/shrink without reintroducing end wobble or collapse detachment.
- Made shell scale/blur transitions more visible so the morph reads less like a fade:
  - `blurBounce` insertion now uses:
    - blur `7`
    - scale `0.95`
  - `blurBounce` removal now uses:
    - blur `6`
    - scale `0.955`
  - This keeps the shell visibly growing/shrinking while staying conservative enough to avoid jumpiness.
- Retuned inner content materialization timing:
  - Expanded inner-content reveal delay was reduced from `240ms` to `170ms`.
  - `InnerBlurScaleCleanModifier` insertion/removal timing was tightened to:
    - insertion duration `0.38s`
    - removal duration `0.28s`
  - Inner inactive scales/blur are now more moderate:
    - insertion scale `0.90`
    - removal scale `0.92`
    - insertion blur `10`
    - removal blur `8`
  - This keeps shell-first staging while avoiding the overly late empty-tray feel.
- Retuned page and compact-content transitions:
  - Expanded page transition now uses moderate blur and scale:
    - insertion blur `8`, scale `0.96`
    - removal blur `6`, scale `0.97`
  - Page animation duration increased from `0.16s` to `0.20s`.
  - Compact collapsed content animation increased from `0.24s` to `0.28s`.
- Preserved:
  - Phase 5I.1 fixes remain preserved:
    - no final expansion wobble
    - no collapse detachment
    - shrink still reads toward the top-center/notch
  - Phase 5I.2 performance protections remain preserved:
    - shell-morph performance gating
    - only active page rendered
    - reduced shell shadow during morph
    - lightweight visualizer/stats behavior during morph
  - Media fit/layout refactors from Phase 5J.4 were not undone.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - Packaging required the documented xattr cleanup recovery once:
    - `xattr -cr dist/DynamicIsland.app`
    - `Scripts/package_app.sh`

### 2026-07-04 - Phase 5J.7 Ghost Border Removal And Staged Motion Fix

- Removed the visible expanded ghost border/canvas artifact:
  - `IslandSurface` now applies fill, stroke, and shadow to the actual shell shape only.
  - The larger visual canvas no longer carries the shell shadow as a parent-group effect.
  - This removes the inappropriate semi-transparent outer rounded corners around the expanded island while preserving the intended shell shadow.
- Restored actual staged inner-content sequencing in `ExpandedIslandView`:
  - Active expanded page content now stays mounted in the real expanded render path instead of being skipped until the last visibility flip.
  - `showInnerContent` now genuinely controls staged inner reveal after shell expansion starts.
  - Collapse keeps real inner content alive briefly for its removal animation before handing off to the compact ghost.
  - Fixed delayed collapse-ghost generation tracking so stale delayed work cannot re-show the handoff ghost incorrectly.
- Kept parked notch shoulder work visually inactive:
  - `notchShoulderBlendEnabled = false`
  - `collapsedShoulderEnabled = false`
  - `expandedShoulderEnabled = false`
  - No shoulder blend/debug layer renders by default in collapsed or expanded mode.
- Preserved:
  - OverlayWindowController architecture, split-panel click-through behavior, expanded hover tolerance, collapse grace logic, morph architecture, media/tray/timer/stats feature logic, and parked notch shoulder work were not redesigned.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/NotchShoulderBlend.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 6A Single Adaptive Island Panel

- Replaced the split visual/hit/expanded overlay ownership with one adaptive `islandPanel`:
  - `OverlayWindowController.swift` now uses a single transparent borderless `NSPanel`.
  - The panel hosts one `IslandRootView` with `rendersExpandedVisualContent: true`.
  - Old separate collapsed-hit and expanded interactive panel ownership was removed from the active path.
- Final panel sizing now matches the visible island state:
  - Final collapsed `islandPanel` frame matches the collapsed pill.
  - Final expanded `islandPanel` frame matches the expanded island tray.
  - During collapse morph only, the panel temporarily stays expanded-sized so the shell can shrink without clipping.
- Added panel-local adaptive layout conversion in `IslandLayoutStore.swift`:
  - Added `updateLocal(panelFrame:collapsedScreenFrame:expandedScreenFrame:hasHardwareNotch:)`.
  - The layout store now converts screen-space collapsed/expanded geometry into panel-local surface frames for one-surface morphing.
- Collapsed click and file drag are now handled by the single hosting root:
  - `IslandRootView.swift` handles collapsed tap-to-expand on the compact content directly.
  - Root file-drag targeting now expands to Tray through the existing navigation/state stores instead of a separate AppKit collapsed-hit view.
  - Expanded Tray drop behavior remains intact.
- Main shell transition no longer depends on separate collapsed/expanded shell transitions:
  - The shell stays as one `IslandSurface`.
  - Compact and expanded content branches no longer apply the old shell-scale transition.
  - Collapse keeps the expanded branch alive during shell-only morph long enough for staged inner removal instead of switching to the compact branch too early.
- Motion sequencing was aligned to the one-panel model:
  - Expansion now uses one panel prepared at expanded size while the shell grows from the collapsed local frame.
  - Collapse now keeps the panel expanded-sized briefly, lets inner content stage out, then shrinks the shell into the collapsed local frame before the panel returns to collapsed size.
  - Main shell transition still avoids opacity fade; inner content keeps blur/scale/opacity staging.
- Hover and visual cleanup:
  - Expanded mouse-leave containment still uses the visible expanded shell rect with the existing `2` px tolerance.
  - The prior outer ghost border/layer remains removed because only `IslandSurface` draws shell fill, stroke, and shadow.
  - Parked notch shoulder work remains visually disabled by default.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`

### 2026-07-04 - Phase 7A Comprehensive Settings Foundation

- Added comprehensive persisted settings groups in `AppSettings.swift`:
  - General / Island
  - Appearance
  - Motion
  - Modules / Tabs
  - Media
  - File Shelf / Tray
  - Timer
  - Stats / Activities
  - Live Activities
  - Gestures
  - Advanced / Debug
- Added island/layout/motion settings:
  - Added persisted collapsed/expanded width and height with clamping.
  - Added adaptive sizing and hardware-notch respect toggles.
  - Added animation preset, shell speed, content animation, stagger, blur, scale, and opacity-transition settings.
  - Existing Phase 6B single-panel host, one-surface shell morph, click-through behavior, and content sequencing were preserved.
- Added tab/module visibility settings:
  - Added persisted visibility fields for Island/Tray/Timer/Stats and placeholder future tabs.
  - `IslandNavigationStore` now filters visible implemented tabs from settings and safely falls back when the selected tab becomes disabled.
  - Drag-hover Tray routing now respects Tray/file-shelf enablement before forcing the Tray page.
- Added media settings including safe UI visibility wiring:
  - Media module and compact island now respect existing safe settings such as:
    - album artwork visibility
    - title/artist/source visibility
    - playback controls visibility
    - progress slider visibility
    - volume slider visibility
    - visualizer visibility
    - launcher button visibility
    - source-open artwork click enablement
    - collapse-after-launch / collapse-after-open behavior
  - Provider preference settings were added as persisted future-facing fields only and were not wired into arbitration in this phase.
- Added tray/file shelf settings:
  - Added tray, file shelf, AirDrop zone, drop-allowance, thumbnail, file-extension, and action visibility settings.
  - `FileShelfStore` now uses the persisted max-file cap.
  - Expanded Tray drop and collapsed drag-expansion now respect enablement settings.
  - File tile context-menu actions and thumbnail/file-name presentation now respect settings where safely supported.
  - Persistent shelf storage remains a stored placeholder and was not implemented.
- Added timer settings:
  - Added persisted timer presets and timer visibility/settings fields.
  - Dedicated Timer tab now uses the stored preset minute values.
  - Timer ring visibility and ring animation visibility are wired.
  - Collapse-after-starting-timer is wired through the existing collapse request path.
  - Timer sound/notification/collapsed timer settings remain placeholders only.
- Added stats/activities settings:
  - Added persisted stats card visibility and refresh interval settings.
  - Stats refresh interval is now wired into `SystemStatsController`.
  - Stats page card visibility respects CPU/Memory/GPU/Network/Disk/Battery/Uptime settings.
  - Activities settings were added as future-facing placeholders only.
- Added future Live Activities and Gesture settings:
  - Added persisted fields and settings UI sections for both categories.
  - Both sections are clearly marked coming soon and remain unwired by design in Phase 7A.
- Added advanced/debug settings:
  - Added reset helpers for all settings, layout settings, and module settings.
  - Added stored advanced/debug flags for later work.
  - Only safe existing behavior remains active by default; noisy debug behavior was not enabled.
- Added settings UI foundation:
  - Replaced the previous minimal settings form with a larger categorized settings UI using `NavigationSplitView`.
  - Wired implemented settings directly where safe.
  - Placeholder settings are shown disabled with short explanatory help text.
- Geometry compatibility note:
  - `NotchGeometryService` now supports adaptive-size and notch-respect flags while preserving existing default geometry behavior when those flags stay at their defaults.
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
- Changed files:
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - `Sources/DynamicIsland/App/SettingsWindowController.swift`
  - `Sources/DynamicIsland/Geometry/NotchGeometryService.swift`
  - `Sources/DynamicIsland/Modules/FileShelfStore.swift`
  - `Sources/DynamicIsland/Modules/SystemStatsController.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/State/IslandNavigationStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `context.md`

### 2026-07-04 - Phase 6B Stable Host Panel And Shape-Aware Hit Testing

- Kept one stable expanded-sized host panel:
  - `OverlayWindowController.swift` now keeps `islandPanel` on the expanded host frame for both collapsed and expanded states.
  - The panel no longer swaps down to the collapsed frame after collapse.
  - Geometry refreshes still update collapsed and expanded surface targets, but panel sizing now stays stable during expand/collapse morphs.
- Restored stable local surface coordinates:
  - `IslandLayoutStore.updateLocal(...)` continues to receive the expanded host frame, so collapsed and expanded local surface frames stay in the same coordinate space.
  - This keeps the collapsed pill centered inside the host panel and removes state-change coordinate rebasing.
- Added shape-aware hit gating on the hosting view:
  - `IslandHostingView` now accepts an `interactiveRegionProvider`.
  - `hitTest(_:)` returns `nil` outside the visible local island region so invisible host-panel areas click through.
  - Collapsed mode uses the collapsed surface rect with a `4` px tolerance.
  - Expanded mode uses the expanded surface rect with a `2` px tolerance.
- Simplified resize-era panel logic:
  - Removed the previous expansion-preparation/final collapsed frame swap path used to avoid panel rebase while resizing.
  - Expand requests still flow through `onRequestExpand()` and controller-owned state changes.
- Preserved:
  - One always-mounted SwiftUI shell surface remains in `IslandRootView`.
  - Expanded mouse-leave containment still uses the visible expanded shell frame with the existing `2` px hover tolerance.
  - Media, tray, timer, stats, settings, gestures, click-through expectations, and parked notch shoulder disablement were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 6A.2 Single-Panel Native Morph Correction

- Kept the one-panel architecture and corrected the shell morph path instead of reintroducing split panels:
  - `OverlayWindowController.swift` still uses one transparent adaptive `islandPanel`.
  - `IslandLayoutStore.updateLocal(...)` remains the source of truth for panel-local collapsed and expanded shell frames.
- Preserved centered local-frame invariants and added DEBUG-only diagnostics:
  - `collapsedSurfaceFrame` and `expandedSurfaceFrame` continue to be derived from screen-space frames relative to the current panel frame.
  - Added verbose DEBUG logging for panel frame, local frames, and their midpoints so top-left-origin regressions can be verified without production log spam.
- Switched the shell shape to animatable radius morphing in `IslandRootView.swift`:
  - Replaced the hard `isExpanded ? 22/36` shell-corner switch with `IslandShellShape(bottomRadius:)`.
  - `bottomRadius` now interpolates from current shell height progress between collapsed and expanded sizes.
  - This removes the visible final corner/border snap at the end of collapse.
- Kept the shell as one continuously animated surface:
  - `IslandSurface` remains alive as the only shell.
  - The shell is still positioned by `surfaceFrame.midX` / converted `surfaceFrame.midY`, so expansion starts from the collapsed pill midpoint under the notch instead of top-left.
  - Compact/expanded content branches do not own shell transitions.
- Updated shell animation style to native SwiftUI frame/radius morphing:
  - Shell frame/position/radius now animate with `.smooth(duration: 0.40)` by default.
  - Reduce Motion still uses a simpler `.easeInOut(duration: 0.24)` path.
  - Main shell still does not use opacity fade.
- Preserved inner-content staging:
  - Inner expanded content continues to use blur/scale/opacity staging only.
  - Expanded content still stays alive during collapse shell-only mode long enough for staged removal before the compact branch returns.
- Changed files:
  - `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 6A.3 Pre-Expansion Geometry And Shell Style Continuity

- `IslandRootView` no longer directly mutates `islandState` to expand from the collapsed state:
  - Added `onRequestExpand`.
  - Collapsed tap expansion now requests expansion through the controller.
  - Collapsed file-drag expansion now also requests controller-owned expansion after switching to Tray.
- `OverlayWindowController` now owns pre-expansion geometry preparation:
  - Added `expandFromCollapsedPreparingGeometry()`.
  - Before `islandState.expand()`, the controller now:
    - computes current collapsed/expanded geometry
    - sets `targetCollapsedFrame` and `targetExpandedFrame`
    - updates `layoutStore` using `panelFrame: expandedFrame`
    - applies the expanded panel frame
    - orders the panel front and invalidates layout
  - This ensures SwiftUI starts expansion from a collapsed local frame centered inside the already-expanded panel.
- Prevented the first expanded state sink from undoing prepared geometry:
  - Added `didPrepareExpansionGeometry`.
  - When expansion was controller-prepared and the panel is already at `targetExpandedFrame`, the first expanded-state sink now skips the redundant initial `reposition(animated: true)` pass.
  - This removes the layout bounce that could still make expansion read like a top-left-origin start.
- Improved shell style continuity at collapse end:
  - `IslandSurface` now interpolates shell stroke opacity and shadow radius/y by morph progress instead of switching those values by `isExpanded`.
  - This removes the visible last-frame border/shadow style snap when the shell finishes collapsing.
- Kept DEBUG-only local-frame invariant verification:
  - Existing `updateLocal(...)` diagnostics remain behind `DYNAMIC_ISLAND_VERBOSE_UI_LOGS=1`.
  - Added a DEBUG warning when collapsed and expanded local `midX` differ by more than 1pt.
- Preserved:
  - Single adaptive one-panel architecture.
  - No reintroduction of split panels or extra hit panels.
  - No main shell opacity fade.
  - Existing inner blur/scale/opacity staging remains intact.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 6A.4 Stop Animating Panel-Local Coordinate Rebases

- Removed shell animation triggers from panel-local frame rebases in `IslandRootView.swift`:
  - Deleted direct shell animation bindings on:
    - `layoutStore.expandedSurfaceFrame`
    - `layoutStore.collapsedSurfaceFrame`
  - The shell now morphs primarily from `islandState.state`, with `layoutStore.isShellMorphing` available for the broader morph window.
- Added controller-owned non-animated layout rebasing in `OverlayWindowController.swift`:
  - Added `updateLayoutWithoutAnimation(panelFrame:collapsedFrame:expandedFrame:hasHardwareNotch:)`.
  - This wraps `layoutStore.updateLocal(...)` in a `Transaction(animation: nil)` with animations disabled.
  - Panel-local coordinate rebases are now applied instantly instead of being animated by SwiftUI.
- Applied non-animated rebasing in the required places:
  - Pre-expansion geometry preparation now rebases local frames without animation before `islandState.expand()`.
  - `reposition(animated: false)` paths now use the no-animation layout update helper.
  - Final collapsed-panel restore now uses `finalizeCollapsedPanelFrameWithoutAnimation()` so the end-of-collapse panel/frame rebase is silent.
- Preserved the intended morph order:
  - Controller expands panel and rebases layout first.
  - Then `islandState.expand()` drives the visible shell morph.
  - Final collapse panel resize/rebase happens without shell-position animation.
- Preserved prior shell-style continuity fixes:
  - Animatable bottom radius remains progress-based.
  - Stroke/shadow remain interpolated by morph progress.
  - No shell opacity fade was added.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 6B.2 Window-Level Click-Through And Expanded Padding Ownership

- Fixed the stable-host invisible click blocker in `OverlayWindowController.swift`:
  - Kept the one stable expanded-sized `islandPanel`.
  - Added screen-space visible-island helpers derived from `layoutStore` local surface frames and `islandPanel.frame`.
  - Added `updateMousePassthrough(...)`, which toggles `islandPanel.ignoresMouseEvents` from the currently visible island rect instead of the full stable panel frame.
  - Collapsed mode now uses only the visible pill plus `4` px tolerance for interaction.
  - Expanded mode now uses only the visible expanded island plus `2` px tolerance for interaction.
  - Mouse passthrough updates now run after reposition/layout updates, window-visibility updates, expansion preparation, mouse-move monitors, and the expanded containment timer.
  - `NSHostingView.hitTest` remains only a secondary safeguard; the primary click-through fix is now window-level passthrough because the NSPanel itself can still block clicks.
- Preserved collapse behavior while removing invisible blocking:
  - Expanded containment still uses the visible expanded shell rect, not the stable panel frame.
  - When the mouse leaves the visible expanded island, collapse still runs after the existing grace logic and the panel is allowed to become click-through outside the visible surface.
- Fixed expanded content clipping from the stable-host refactor in `IslandRootView.swift`:
  - `IslandSurface` no longer adds expanded-state content padding on top of `ExpandedIslandView` metrics padding.
  - Collapsed compact padding remains owned by `IslandSurface`.
  - Expanded and collapse-shell-only content now use zero shell padding so the existing expanded metrics own the content inset budget.
- Preserved:
  - One-panel Atoll-style morph architecture.
  - No split panels, no collapsed hit panel, no expanded panel, and no panel resize on every expand/collapse.
  - Media, tray, timer, stats, settings, gestures, and parked notch shoulder behavior were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`

### 2026-07-04 - Phase 6B.3 Remove Expansion Fade Perception

- Found the remaining expansion-fade perception in direct opacity modifiers inside `IslandRootView.swift`, not in the shell itself:
  - `InnerBlurScaleCleanModifier` was still driving hidden expanded content to `.opacity(0)`.
  - The expanded tab switcher was still using `.opacity(showInnerContent ? 1 : 0)`.
  - The Island-page divider was also fading from `0`.
  - Page insertion transition still used insertion `opacity: 0`.
- Kept the shell fully opaque:
  - `IslandSurface` shell fill/stroke/shadow rendering was left unchanged.
  - No shell opacity fade or shell blur was added.
- Removed expansion opacity staging from inner reveal:
  - `InnerBlurScaleCleanModifier` now keeps insertion opacity at `1` and uses blur/scale only for expansion staging.
  - Collapse removal can still fade out to `0`, preserving the current collapse feel.
- Removed expansion fade from the expanded top bar and page insertion:
  - `ExpandedIslandPageSwitcher` no longer fades in from `0` during expansion; it only fades out during removal.
  - The Island-page divider follows the same removal-only opacity behavior.
  - Expanded page transition insertion now keeps `opacity: 1`, so initial expansion reads as blur/scale settling rather than a whole-page fade-in.
- Preserved:
  - Stable single-panel host architecture.
  - Window-level click-through behavior from Phase 6B.2.
  - One-surface morph path, shell no-fade rule, and all media/tray/timer/stats logic.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`

### 2026-07-04 - Phase 6B.4 Strict Shell/Content Sequencing

- Added explicit shell/content sequencing state in `IslandRootView.swift`:
  - Added local rendered-content sequencing state so the expanded visual tree no longer mounts directly from `islandState.state`.
  - Expansion now immediately switches the rendered branch to expanded shell mode, keeps inner content unmounted, and delays visible expanded modules until the shell morph is mostly complete.
  - Expansion reveal delay was increased to `310ms` by default, with a shorter Reduce Motion delay.
- Prevented expanded modules from rendering during early shell expansion:
  - `ExpandedIslandView` now receives explicit content-rendering inputs from `IslandRootView` instead of running its own ad-hoc on-appear timing.
  - The tab switcher renders only after content is actually visible.
  - Early expansion no longer mounts the expanded page content behind blur/opacity while the shell is still growing.
- Added strict collapse sequencing through the controller:
  - `OverlayWindowController.swift` now owns `requestCollapseWithSequencing()`.
  - Mouse-leave collapse, timer collapse, Escape, shortcut launch collapse, and media launcher/source-open collapse now route through the same controller-owned sequenced collapse path.
  - The controller sets a transient `isExpandedContentExiting` flag first, waits about `180ms`, and only then commits `islandState.collapse()` so content exits before the shell shrinks.
- Clipped content to the shell shape without clipping the shell shadow:
  - `IslandSurface` now renders shell fill/stroke/shadow separately from content.
  - The content layer is clipped with the same shell shape, preventing modules from appearing outside the island during morphs.
- Removed remaining expansion fade behavior from the active staging path:
  - Expansion content is now unmounted until the delayed reveal point instead of being shown through early opacity staging.
  - Reduce Motion page insertion no longer uses `.opacity`.
- Disabled the compact handoff ghost from the active collapse path:
  - `CompactHandoffGhostView` remains in the file, but the active collapse path no longer mounts it during the shell/content sequence.
- Changed files:
  - `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`

### 2026-07-04 - Phase 6B.5 Stable Inner Content Staging

- Fixed the mounted-and-visible same-frame bug in `IslandRootView.swift`:
  - Expansion content no longer mounts and becomes visible in the same async block.
  - Expansion now uses a two-step reveal:
    - after the shell is mostly expanded, content mounts in its hidden blurred/scaled state
    - on the next short delayed tick, `contentVisible` flips to `true`, which gives the inner reveal animation a real state transition to animate
- Reduced expansion reveal latency:
  - Expansion content delay was reduced from the prior longer delay to about `240ms`.
  - A short follow-up reveal delay of about `20ms` is then used so the mounted content can animate into place instead of spawning already settled.
- Stabilized the expanded layout during collapse:
  - The tab switcher now sits inside a fixed-height reserved slot while `ExpandedIslandView` is mounted.
  - The page content area also stays inside a stable `ZStack` frame.
  - `contentVisible` now drives only visual state, not layout insertion/removal of those containers.
  - This prevents the previous upward reflow/jump during collapse.
- Tightened inner staging timing and motion:
  - `InnerBlurScaleCleanModifier` now uses a lighter expansion hidden state and a tighter removal state:
    - expansion hidden scale about `0.955`
    - expansion hidden blur about `8`
    - removal scale about `0.97`
    - removal blur about `6`
  - Stagger spacing was reduced by lowering the delay multiplier from `0.035` to `0.025`.
  - Tab switcher now uses stagger index `0`, first content block `1`, second content block `2`.
- Aligned controller collapse timing with the inner exit animation:
  - `collapseContentExitDelay` in `OverlayWindowController.swift` was increased to about `205ms` so shell collapse starts just after inner removal finishes.
- Removed remaining page-transition fade from the active expansion path:
  - Page transition insertion remains opacity-free.
  - Removal also no longer uses opacity fade in the page transition, so navigation/collapse page staging relies on blur/scale only in this path.
- Preserved:
  - Stable host panel architecture.
  - Window-level click-through.
  - One-surface shell morph.
  - `IslandLayoutStore.updateLocal(...)`.
  - Media/tray/timer/stats business logic and notch shoulder state.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`

### 2026-07-04 - Phase 7A.1 AppSettings Normalization Crash Fix

- Fixed the Phase 7A launch crash in `AppSettings.swift`:
  - Removed the recursive `didSet` normalization path where clamped numeric values reassigned through `inout` helpers and could re-enter the same property observer indefinitely.
  - Added guarded normalization suppression with `isNormalizingSettings`.
  - Replaced unsafe `inout` numeric normalization helpers with guarded key-path normalization helpers for `Double` and `Int` settings.
  - `normalizeAll()` now runs under the suppression guard, clamps values directly, and explicitly saves normalized values instead of relying on `didSet`.
- Covered all normalized numeric settings:
  - Auto-collapse grace, collapsed/expanded dimensions, shell opacity, shell animation speed, content stagger, shelf limit, timer presets, stats/activity refresh intervals, live activity dismiss time, and gesture sensitivity/cooldown.
- Confirmed enum raw-value reads remain safe:
  - Enum settings still use `Self.enumValue(..., fallback:)`.
- Preserved:
  - No new settings UI or unrelated settings behavior was added.
  - Overlay architecture, shell morphing, media, tray, timer, stats, gestures, and notch shoulder state were not changed.
- Changed files:
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `.build/debug/DynamicIsland`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-04 - Phase 7A.2 Expanded Island Settings Entry

- Added a Settings entry point to the expanded island:
  - Added a small top-right gear button in the expanded island header row.
  - The gear uses the existing dark translucent island button style and exposes hover help plus an `Open Settings` accessibility label.
  - The header row keeps a stable reserved height so the tab switcher/page content layout does not reflow during content staging or collapse.
- Wired Settings through the existing app-owned controller:
  - `AppDelegate` passes an `onOpenSettings` callback into `OverlayWindowController`.
  - `OverlayWindowController` passes the callback into `IslandRootView`.
  - `IslandRootView` passes it into `ExpandedIslandView`, where the gear invokes it.
  - The existing `SettingsWindowController` is reused, so the Settings window edits the same shared `AppSettings` instance used by the overlay.
- Settings window behavior:
  - Repeated gear clicks reuse/raise the existing settings window instead of creating duplicate windows.
  - The window recenters only when first shown after being hidden.
- Preserved:
  - Phase 6B stable host panel architecture, shell morph/click-through behavior, media/tray/timer/stats logic, file drag behavior, and notch shoulder state were not changed.
  - No new settings were added.
- Changed files:
  - `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - `Sources/DynamicIsland/App/SettingsWindowController.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 7A.4 Island Size Settings Wiring

- Wired island width/height settings into active overlay geometry:
  - `AppSettings.collapsedSize` and `expandedSize` now return normalized/clamped setting values instead of raw stored values.
  - `NotchGeometryService` now uses the user-selected expanded width/height as the preferred expanded geometry instead of replacing it with hardcoded adaptive `760x260` sizing.
  - Notched collapsed geometry now uses the user-selected collapsed width/height as the preferred size, with adaptive notch sizing only raising the size to notch-safe minimums when needed.
  - Notchless/floating geometry continues to use the user-selected collapsed and expanded sizes.
- Live updates:
  - Existing shared `AppSettings` wiring and overlay settings observation now cause `OverlayWindowController.reposition(animated: false)` to apply size changes live.
  - Reposition still updates `IslandLayoutStore.updateLocal(...)` and mouse passthrough/hit regions after geometry changes.
  - Added DEBUG-only verbose geometry refresh logging behind `DYNAMIC_ISLAND_VERBOSE_UI_LOGS=1`.
- Settings window:
  - The size controls continue binding to the same shared `AppSettings` instance used by the overlay.
  - No second settings instance or new settings UI structure was added.
- Tests:
  - Updated notch geometry tests to assert that user-provided collapsed and expanded sizes affect the final frames while preserving notch/screen safety behavior.
- Preserved:
  - Phase 6B stable single-panel host architecture, window-level click-through logic, shell/content sequencing, media/tray/timer/stats logic, and settings UI structure were not changed.
- Changed files:
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/Geometry/NotchGeometryService.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Tests/DynamicIslandTests/NotchGeometryServiceTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8A File Shelf Tray Polish

- Added persistent File Shelf behavior:
  - `FileShelfStore` now supports bookmark-backed persistence through `UserDefaults` when `persistFileShelfAcrossLaunches` is enabled.
  - Persistence remains off when the setting is disabled, preserving runtime-only shelf behavior.
  - Restores only file URLs that still exist and silently drops missing/corrupt entries.
  - Add/remove/clear/max-file trimming now update persisted storage when enabled.
  - Duplicate files from the same drop are de-duplicated and `maxShelfFiles` is respected.
- Polished File Shelf UI:
  - Added a subtle file-count badge in the shelf header when `showFileCountBadge` is enabled.
  - Added clear-shelf confirmation when `confirmBeforeClearShelf` is enabled.
  - Empty state now explains whether files are temporary, saved across launches, or drops are disabled in Settings.
  - Existing thumbnail behavior now continues to respect `showFileThumbnails` and `deferThumbnailsDuringMorph`.
- File tile actions:
  - Context menu and hover remove continue respecting:
    - `openFileActionEnabled`
    - `revealInFinderActionEnabled`
    - `copyPathActionEnabled`
    - `removeFileActionEnabled`
  - Added a Preview/Quick Look entry and double-click behavior using the safe system-open fallback for this phase because direct `QLPreviewPanel` integration was not available cleanly under the current SDK/import surface.
  - Remove actions only remove files from the shelf and do not delete disk files.
- AirDrop polish:
  - `AirDropService.share` now respects `airDropFallbackRevealInFinder`.
  - When the fallback is disabled and AirDrop service is unavailable, the app no longer reveals files in Finder automatically.
  - AirDrop zone copy reflects the fallback behavior.
- Drag/drop settings:
  - Existing collapsed and expanded drop gates remain in place for `allowFileDropsOnCollapsedIsland`, `allowFileDropsOnExpandedTray`, `trayEnabled`, `fileShelfEnabled`, and `airDropZoneEnabled`.
  - Drop-state highlights remain view-local and do not change shell sequencing.
- Added tests:
  - File shelf de-duplicates and respects `maxShelfFiles`.
  - Persistence restores existing files when enabled.
  - Persistence-disabled shelves do not restore on relaunch.
  - Missing persisted files are silently removed.
- Preserved:
  - OverlayWindowController stable host panel architecture, IslandLayoutStore local-frame model, shell/content sequencing, click-through passthrough behavior, media/timer/stats logic, and settings architecture were not changed.
- Changed files:
  - `Sources/DynamicIsland/Modules/FileShelfStore.swift`
  - `Sources/DynamicIsland/Modules/AirDropService.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Tests/DynamicIslandTests/FileShelfStoreTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - Packaging required the documented xattr cleanup recovery once:
    - `xattr -cr dist/DynamicIsland.app`
    - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Settings Window Activation Fix

- Fixed the Settings window appearing inactive/greyed out:
  - DynamicIsland runs as an accessory app by default.
  - `SettingsWindowController.show()` now temporarily switches the app activation policy to `.regular`, activates the app, and makes the Settings window key.
  - Closing the Settings window restores the app to `.accessory`.
- Re-enabled Tray settings that now have Phase 8A behavior:
  - `Confirm before clearing shelf`
  - `Persist shelf across launches`
  - `AirDrop fallback reveal in Finder`
- Preserved:
  - Overlay architecture, click-through behavior, shell morphing, media, timer, stats, tray logic, file shelf behavior, and notch shoulder state were not changed.
- Changed files:
  - `Sources/DynamicIsland/App/SettingsWindowController.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8A Collapsed Hover Preview Foundation

- Added a generic collapsed hover preview model:
  - `CollapsedPreviewContent`
  - `CollapsedPreviewKind`
  - Media is the only real content provider in this phase.
  - The model is intentionally generic so a future Live Activities provider can reuse the same collapsed preview surface.
- Added collapsed-only hover preview behavior:
  - Hovering the collapsed pill can expand the visible shell downward after a short configurable delay.
  - The normal collapsed frame remains unchanged; the preview uses a SwiftUI-only visual frame derived from `layoutStore.collapsedSurfaceFrame`.
  - The panel is not resized for hover preview.
  - Preview is disabled while expanded, during shell morph/collapse handoff, or while file drag targeting is active.
- Added media preview content:
  - Active media can show the current title and artist/source in the taller collapsed pill.
  - Preview respects existing media visibility settings such as media enablement, paused-media visibility, title/artist/source toggles, album artwork visibility, and visualizer visibility.
  - No fake preview content is shown when there is no active media session.
- Added click-through safety for the taller preview:
  - `IslandLayoutStore` now publishes `collapsedPreviewActive` and `collapsedPreviewSurfaceFrame`.
  - `OverlayWindowController` includes the preview frame in the collapsed interactive region only while the preview is active.
  - Outside the visible collapsed/preview shape remains click-through.
- Added settings:
  - `collapsedHoverPreviewEnabled`
  - `collapsedHoverPreviewMediaEnabled`
  - `collapsedHoverPreviewHeight`
  - `collapsedHoverPreviewDelay`
  - `collapsedHoverPreviewShowsArtist`
  - `collapsedHoverPreviewShowsSource`
  - Height and delay are normalized using the existing guarded settings pattern.
- Preserved:
  - Stable single-panel host architecture, `IslandLayoutStore` local-frame model, expanded shell/content sequencing, media controller internals, file shelf behavior, timer/stats behavior, drag/drop expansion, settings architecture, and parked notch shoulder behavior were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Sources/DynamicIsland/Overlay/IslandLayoutStore.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8A.1 Collapsed Hover Preview Layout Polish

- Refined collapsed hover preview layout:
  - The hover preview row now sits along the bottom of the expanded collapsed pill.
  - Song title and artist/source are rendered as separate horizontal groups.
  - When both are visible, the title group aligns toward the center from the left side and the artist group aligns toward the center from the right side.
  - When only one field is enabled/available, that field is centered along the bottom row.
- Added preview icons:
  - Title uses `collapsedHoverPreviewTitleIconName`, defaulting to `music.mic`.
  - Artist/source uses `collapsedHoverPreviewArtistIconName`, defaulting to `person.fill`.
  - Invalid/unavailable SF Symbols fall back safely to `music.note` or `person.fill`.
- Removed blur from hover preview text/icons:
  - The bottom row now uses clean opacity and small vertical offset animation only.
  - The expanded island content staging and shell morph transitions were not changed.
- Added/updated settings:
  - Added `collapsedHoverPreviewShowTitle`.
  - Added internal icon-name settings for title and artist defaults.
  - Reused `collapsedHoverPreviewShowsArtist` for artist visibility.
  - Reused `collapsedHoverPreviewShowsSource` as "Use source name if artist missing".
  - Increased normalized hover preview height range to `44...96`.
  - Settings UI now includes song name, artist, and source-fallback controls with dependent disabling.
- Preserved:
  - Stable single-panel host architecture, `OverlayWindowController` panel model, `IslandLayoutStore` local-frame model, hover-preview hit region behavior, expanded shell/content sequencing, click-through architecture, media controller internals, file shelf behavior, timer/stats behavior, and notch shoulder state were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8B.1 Visualizer Smoothness Fix

- Fixed visualizer rhythm stutter without redesigning the visualizer:
  - Kept the existing premium visualizer design, colors, and layout.
  - Follow-up tuning keeps 12 bars in expanded mode and uses 7 bars in the collapsed pill / compact handoff path.
  - No new visualizer settings or UI layout changes were added.
- Decoupled visual rhythm from brief media polling flickers:
  - `AudioVisualizerView` now keeps a local visual playback state.
  - Brief `isPlaying` / active-media false ticks are held for about `0.34s` before the visualizer settles to paused.
  - This prevents split-second stops when media polling or metadata updates briefly report a non-playing state.
- Preserved phase continuity:
  - The visualizer stays mounted in a paused-capable `TimelineView` instead of switching between animated and static view trees.
  - Bar heights continue deriving from timeline date rather than metadata, title, artwork, progress, or volume updates.
  - No `.id(...)` or metadata-tied identity reset was added.
- Settings behavior:
  - Existing `disableVisualizerDuringMorph` is now passed into the visualizer call sites.
  - Reduce Motion still stops continuous animation.
- Preserved:
  - Phase 6B stable host panel architecture, `IslandRootView` shell/content sequencing, collapsed hover preview layout, media source arbitration, file shelf, timer/stats, settings architecture, click-through behavior, and visualizer style were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8C Gesture Infrastructure Foundation

- Added safe gesture infrastructure without implementing camera or full custom gesture behavior:
  - Added `IslandGestureAction` for future action targets.
  - Added `IslandPointerGesture` for pointer/trackpad gesture types.
  - Added `IslandGestureContext` and `IslandGestureCallbacks` so gesture handling can use existing safe app paths.
  - Added `IslandGestureCoordinator` with settings gates, pointer-source filtering, cooldown handling, morph/drop guards, and conservative default mapping.
- Default gesture behavior remains conservative:
  - Double-click maps to `toggleExpanded`, but only works when gestures are enabled, input source is pointer/trackpad, and the relevant expand/collapse gesture toggle is enabled.
  - Swipe left/right/up/down and long press are modeled but map to `none` for now.
  - Require-confirmation mode blocks gesture actions because no confirmation UI exists yet.
- Added visible-surface pointer detection in `IslandRootView.swift`:
  - Gesture detection is attached only to the visible island surface, not the whole stable host panel.
  - Disabled/non-pointer gesture settings do not attach the high-priority double-click handler.
  - Swipe detection uses final drag translation and the persisted sensitivity threshold.
  - Gesture actions use existing `onRequestExpand` and sequenced `onRequestCollapse` callbacks.
  - Next/previous tab callbacks use `IslandNavigationStore` helpers that respect disabled tabs.
- Updated gesture settings:
  - Pointer/trackpad controls are now active.
  - Camera gestures remain clearly marked Coming Soon.
  - No camera permission, capture session, AVCapture usage, or hand recognition was added.
- Added tests:
  - Disabled gestures do nothing.
  - Cooldown blocks repeated actions.
  - Low sensitivity requires a larger swipe.
  - Next/previous page helpers skip disabled tabs.
- Preserved:
  - Stable single-panel host architecture, OverlayWindowController click-through behavior, IslandLayoutStore local-frame model, shell/content sequencing, collapsed hover preview layout, visualizer style, media controller internals, file shelf behavior, timer/stats logic, and camera/privacy behavior were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/State/IslandGestureCoordinator.swift`
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/State/IslandNavigationStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Tests/DynamicIslandTests/IslandGestureCoordinatorTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8C.1 Exact Gesture Actions

- Wired configurable collapsed and expanded gesture mappings:
  - Added persisted action settings for collapsed double-click, swipes, and long press.
  - Added persisted action settings for expanded double-click, swipes, and long press.
  - Gesture action raw values are loaded safely; invalid stored values fall back to defaults.
- Default mappings:
  - Collapsed double-click: media play/pause, falling back to toggle expanded when media transport is unavailable.
  - Collapsed swipe down: expand.
  - Collapsed swipe up/left/right: none.
  - Collapsed long press: open Settings.
  - Expanded swipe up: collapse through the existing sequenced collapse callback.
  - Expanded swipe left/right: next/previous enabled tab.
  - Expanded double-click/down swipe: none.
  - Expanded long press: open Settings.
- Updated safe action execution:
  - Expand uses the existing safe expand callback.
  - Collapse and toggle collapse use the existing sequenced collapse callback.
  - Next/previous tab actions use `IslandNavigationStore` helpers and skip disabled tabs.
  - Media play/pause requires media to be enabled and transport controls to be available.
  - Timer start/stop requires timer settings to be enabled and an active/resumable timer.
  - Open Settings uses the existing Settings window callback.
- Added Gesture settings UI polish:
  - Added compact action pickers for Collapsed Island Gestures.
  - Added compact action pickers for Expanded Island Gestures.
  - Camera gestures remain clearly marked Coming Soon.
- Preserved interaction safety:
  - Gesture detection remains attached to the visible island surface only.
  - Parent double-click handling no longer uses high-priority gesture priority.
  - Existing shell/content sequencing, click-through/passthrough behavior, hover preview, visualizer design, media arbitration, file shelf behavior, timer engine, and stable host panel architecture were not rewritten.
- Added tests:
  - Configured collapsed gestures return the configured action.
  - Configured expanded gestures return the configured action.
  - Collapsed double-click falls back from media play/pause to toggle when media transport is unavailable.
  - Disabled gestures still do nothing.
  - Cooldown still blocks repeated gestures.
  - Next/previous tab helpers skip disabled tabs.
  - Invalid stored gesture action raw values fall back safely.
- Changed files:
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/State/IslandGestureCoordinator.swift`
  - `Sources/DynamicIsland/State/IslandNavigationStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Tests/DynamicIslandTests/IslandGestureCoordinatorTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8C.2 Collapsed Media Pill Gestures

- Corrected the intended collapsed media pill gesture behavior:
  - Two-finger swipe left maps to next track.
  - Two-finger swipe right maps to previous track.
  - Two-finger swipe down maps to expand island, matching collapsed click expansion.
  - Swipe up remains configurable and defaults to no-op.
- Added AppKit-level two-finger swipe detection:
  - `IslandHostingView` now forwards precise `scrollWheel` events only when the pointer is inside the collapsed visible pill or collapsed hover-preview frame.
  - The scroll gesture path is collapsed-only and does not run while expanded.
  - Gesture handling is ignored while shell morphing, collapse handoff, expanded content exit, or file drag/drop targeting is active.
  - Trackpad scroll deltas are accumulated per gesture, thresholded using `gestureSensitivity`, and gated by `gestureCooldownSeconds`.
- Updated media gesture actions:
  - Added `mediaNextTrack`.
  - Added `mediaPreviousTrack`.
  - Media next/previous no-op safely when media is disabled or transport controls are unavailable.
  - Swipe down expansion still works without active media.
- Updated gesture defaults and settings UI:
  - Collapsed swipe-left default is now next track.
  - Collapsed swipe-right default is now previous track.
  - The settings section is now labeled `Collapsed Media Pill Gestures`.
  - Collapsed media pill pickers show media-relevant actions instead of tab-focused actions.
  - Expanded gesture settings remain separate and unchanged.
- Preserved:
  - Stable single-panel host architecture, click-through architecture, IslandLayoutStore local-frame model, expanded content sequencing, collapsed hover preview layout, visualizer style, file shelf behavior, timer/stats behavior, media source arbitration, and camera gesture behavior were not rewritten.
- Added tests:
  - Default collapsed media pill swipe mappings use next/previous track and expand.
  - Media next/previous gesture callbacks fire only when media transport is available.
  - Media next/previous gestures no-op safely when media is unavailable.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/State/IslandGestureCoordinator.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Tests/DynamicIslandTests/IslandGestureCoordinatorTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8C.3 Trackpad Scroll Gesture Capture

- Fixed collapsed media pill two-finger gestures not firing reliably:
  - The existing view-level `scrollWheel` handler could be bypassed when the single host panel was still in click-through mode.
  - Added a global AppKit scroll-wheel monitor that observes real two-finger trackpad scroll/swipe events when the cursor is over the visible collapsed pill or collapsed hover-preview pill.
  - The monitor converts the current mouse screen location into island-panel local coordinates and uses the same collapsed/preview gesture region as the hosting view.
- Kept gesture handling narrowly scoped:
  - Scroll gestures only run while the island is collapsed.
  - Gestures are ignored while shell morphing, collapse handoff, expanded content exit, or file drag/drop targeting is active.
  - Expanded island controls, sliders, settings windows, and areas outside the visible island are not intercepted.
  - The existing view-level `scrollWheel` path remains for events already delivered to the island panel.
- Preserved configured mappings:
  - Two-finger swipe left uses the configured collapsed left action, defaulting to next track.
  - Two-finger swipe right uses the configured collapsed right action, defaulting to previous track.
  - Two-finger swipe down uses the configured collapsed down action, defaulting to expand.
  - Media next/previous no-op safely when media is disabled or transport controls are unavailable.
- Tightened action routing:
  - Added the missing media next/previous callbacks to the SwiftUI gesture callback path.
  - Removed the extra expand-gesture toggle gate from the collapsed scroll-wheel action path so swipe-down expand follows the configured collapsed media pill action.
- Added verbose DEBUG-only gesture diagnostics behind `DYNAMIC_ISLAND_VERBOSE_UI_LOGS=1`:
  - scroll-wheel source
  - screen/local point
  - collapsed gesture region
  - accumulated deltas
  - resolved direction/action
  - cooldown blocks
- Preserved:
  - Stable single-panel host architecture, click-through behavior, IslandLayoutStore local-frame model, expanded shell/content sequencing, collapsed hover preview layout, visualizer style, media arbitration, file shelf behavior, timer/stats behavior, and settings design were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open -n dist/DynamicIsland.app`
  - `pgrep -fl DynamicIsland`

### 2026-07-05 - Phase 8C.4 Trackpad Gesture Diagnostics And Fix

- Added unavoidable DEBUG diagnostics for the collapsed media pill trackpad gesture path:
  - `scrollWheel` receipt now logs directly with delta, phase, momentum phase, and precise-delta state.
  - The custom `IslandHostingView.scrollWheel` override logs before any filtering.
  - Overlay setup logs `Island hosting view installed` so the active content view can be verified during direct debug launch.
  - Region logs include raw local point, resolved point, flipped-y fallback usage, collapsed frame, preview frame, active frame, panel frame, and inside/outside result.
  - Settings/state logs include `gesturesEnabled`, input source, collapsed left/right/down mappings, island state, morph flags, preview state, and file-drop targeting.
  - Direction/action logs include accumulated deltas, threshold, resolved gesture, executed action, and explicit block reasons.
- Fixed likely event-delivery and threshold failure points:
  - Added a local `.scrollWheel` monitor for diagnostic coverage of app-local scroll events.
  - The local monitor does not process events already delivered to the island panel, avoiding double-counting with the hosting view override.
  - Kept the global `.scrollWheel` monitor for the click-through case where the panel is still ignoring mouse events and the event goes to another app.
  - Lowered `collapsedScrollBaseThreshold` from `24` to `12`; at sensitivity `0.5`, the effective threshold is now about `24` instead of `48`, which is more realistic for precise trackpad deltas.
- Added coordinate verification:
  - The handler now checks the raw local point first.
  - If that misses, it checks a flipped-y local point and logs whether the fallback was used.
  - This keeps screen/local coordinate mismatches visible during manual testing without changing the stable panel architecture.
- Preserved:
  - Stable single-panel host architecture, click-through behavior, expanded shell/content sequencing, collapsed hover preview layout, visualizer, media arbitration, settings UI design, file shelf, timer, and stats were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `.build/debug/DynamicIsland`

### 2026-07-05 - Phase 8C.6 Scroll Gesture Resolution Fix

- Fixed the diagnosed collapsed media pill scroll pipeline failure:
  - Trackpad `scrollWheel` events were being received, but real events arrived as `phase=0` with `momentumPhase=4`.
  - The handler rejected non-empty momentum phases before hit-testing, accumulation, direction resolution, or action execution.
  - The handler now treats any precise scroll-wheel event with meaningful `scrollingDeltaX` or `scrollingDeltaY` as usable input when collapsed and inside the visible pill/preview region.
- Removed silent pre-filtering:
  - `IslandHostingView.scrollWheel` now forwards every scroll event to the shared handler instead of checking the local region first.
  - The shared handler logs entry, settings, state, screen hit-test, delta accumulation, resolved direction, action execution, and explicit block reasons.
  - Momentum/phase-zero events are no longer silently dropped.
- Switched collapsed scroll hit-testing to screen space:
  - Uses `NSEvent.mouseLocation`.
  - Converts `layoutStore.collapsedSurfaceFrame` and `collapsedPreviewSurfaceFrame` to screen-space frames.
  - Adds an 8 px tolerance around the active collapsed/hover-preview frame.
  - Logs collapsed screen frame, preview screen frame, active hit frame, screen point, local point, and inside result.
- Retuned resolution threshold:
  - `collapsedScrollBaseThreshold` is now `8`.
  - At sensitivity `0.5`, the effective threshold is about `16`, so uploaded deltas like `deltaY=-48` resolve immediately.
  - Direction resolution uses raw dominant-axis deltas; negative Y resolves to swipe down, so collapsed swipe down can expand the island.
- Preserved action behavior:
  - Swipe down expand does not require active or playing media.
  - Swipe left/right use the configured collapsed media pill actions and call media next/previous only when transport controls are available.
  - Cooldown still prevents repeated momentum events from firing multiple actions after the first action executes.
- Preserved:
  - Stable host panel architecture, click-through behavior, expanded shell/content sequencing, collapsed hover preview layout, visualizer, file shelf, timer/stats, media arbitration, and gesture settings UI were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `.build/debug/DynamicIsland`

### 2026-07-05 - Phase 8C.7 Collapsed Media Gesture Polish

- Fixed one physical swipe causing multiple track skips:
  - Collapsed media scroll gestures now keep a per-swipe one-shot lockout after an action fires.
  - Remaining duration/momentum events in the same physical swipe are ignored with a DEBUG log instead of executing another action.
  - The lockout resets only after a `0.28s` quiet period with no scroll-wheel events.
  - Accumulated deltas are cleared after execution, but the fired flag remains set until the quiet reset.
- Corrected physical swipe-down mapping:
  - Vertical direction resolution now treats positive accumulated Y as `.swipeDown`.
  - Physical top-to-bottom swipe is intended to expand the island.
  - DEBUG logs include `vertical rawY` and interpreted physical direction for validation.
- Preserved horizontal gesture behavior:
  - Physical swipe left/right continue to use the configured collapsed media pill left/right actions.
  - Media next/previous still require media to be enabled and transport controls to be available.
  - Paused Spotify/Music can still receive next/previous as long as transport is available.
- Improved media refresh after track gestures:
  - Gesture-triggered next/previous now schedules immediate, `0.35s`, and `0.90s` media refreshes.
  - This gives Spotify/Music time to publish new metadata/artwork and prevents the collapsed artwork from staying stale after a skip.
  - DEBUG logs record refresh scheduling and delayed refresh firing.
- Preserved:
  - Stable host panel architecture, click-through behavior, expanded shell/content sequencing, collapsed hover preview layout, visualizer, file shelf, timer/stats, media arbitration rules, and gesture settings UI were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `.build/debug/DynamicIsland`

### 2026-07-05 - Phase 8C.8 Media Gesture One-Shot Lockout

- Added a hard collapsed media next/previous gesture lockout:
  - Media track gestures now use a dedicated lockout separate from the scroll quiet reset.
  - The lockout duration is `max(0.85, settings.gestureCooldownSeconds)` so user settings cannot reduce track gestures below the one-shot safety window.
  - After next/previous fires, horizontal scroll events and momentum tails are consumed until the media lockout expires.
- Separated scroll session reset from media transport lockout:
  - The existing `0.28s` quiet reset can still clear accumulated scroll deltas.
  - It no longer unlocks media next/previous early enough for a long physical swipe to skip multiple songs.
- Hardened duplicate event-path behavior:
  - Local/global monitor and hosting-view duplicate scroll paths now see the same media lockout state.
  - Duplicate/momentum events after a track action clear stale accumulated deltas and no-op with DEBUG logs.
- Preserved:
  - Swipe-down expansion remains outside the media-track lockout path unless a media action has already fired.
  - Stable host panel architecture, click-through behavior, expanded shell/content sequencing, collapsed hover preview layout, visualizer, media arbitration, file shelf, timer/stats, settings UI, and app launch behavior were not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`; it was not introduced or changed by this phase.

### 2026-07-05 - Phase 8C.9 End-of-Swipe Media Gesture Resolution

- Changed collapsed horizontal media gestures from threshold-immediate execution to end-of-swipe resolution:
  - Scroll-wheel events inside the collapsed media pill now update one shared media swipe session.
  - The session accumulates the full physical swipe stream and reschedules a finish callback after each event.
  - Next/previous is resolved only after a `0.22s` quiet period with no new scroll events.
- Enforced one media command per continuous physical swipe:
  - `finishCollapsedMediaSwipeSession()` copies the final accumulated deltas, resets the session immediately, resolves the final dominant horizontal direction once, then sends exactly one media command.
  - Long/strong swipes and momentum tails remain part of the same swipe stream instead of triggering at the first threshold crossing.
  - A short `0.60s` post-command lockout remains only as duplicate-path/tail protection.
- Preserved:
  - Physical swipe left still maps to next track.
  - Physical swipe right still maps to previous track.
  - Swipe-down expansion remains immediate and separate from the horizontal media finish path.
  - Album artwork/media refresh after next/previous remains scheduled at immediate, `0.35s`, and `0.90s`.
  - Stable host panel architecture, click-through behavior, expanded shell/content sequencing, collapsed hover preview layout, visualizer, settings UI, media arbitration, file shelf, timer/stats, and app launch behavior were not changed.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`; it was not introduced or changed by this phase.

### 2026-07-05 - Phase 8C.10 Gesture Responsiveness And Artwork Flip

- Improved collapsed horizontal media gesture responsiveness:
  - Reduced the end-of-swipe quiet period from `0.22s` to `0.12s`.
  - Preserved end-of-swipe resolution so horizontal media commands still execute only from `finishCollapsedMediaSwipeSession()`.
  - Kept the `0.60s` post-command lockout as duplicate-path/momentum-tail protection.
- Preserved one-swipe-one-song behavior and settings consistency:
  - Long/strong left/right swipes still collect into one session and resolve once after the scroll stream goes quiet.
  - The final action still uses the configured collapsed left/right gesture mapping.
  - Gestures remain gated by `gesturesEnabled`, trackpad input source, collapsed state, visible pill/preview hit testing, shell morph state, and file drag/drop state.
  - Swipe-down expansion remains immediate and separate.
- Restored stronger media refresh sequencing after gesture next/previous:
  - Gesture transport now schedules refreshes immediately, at `0.25s`, at `0.75s`, and at `1.20s`.
  - Added DEBUG logs for gesture refresh sequencing and artwork refresh requests.
- Added directional album artwork flip support:
  - `MediaController` now publishes a short-lived gesture artwork flip request with direction `.next` or `.previous`.
  - Gesture next requests a leftward flip; gesture previous requests a rightward flip.
  - `FlippingAlbumArtworkView` preserves the existing artwork shape/size and swaps from old artwork to new artwork at the midpoint of a two-phase 3D horizontal flip.
  - The flip waits for a real new artwork image and skips placeholder/old-image flashes when the new artwork has not arrived yet.
  - Reduce Motion displays the new artwork without the 3D flip.
- Preserved:
  - Stable host panel architecture, click-through behavior, expanded shell/content sequencing, collapsed hover preview layout, visualizer style, settings UI layout, media source arbitration, file shelf, timer/stats, and app launch behavior were not rewritten.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Modules/MediaController.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `.build/debug/DynamicIsland`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`; the line number shifted because this phase added artwork view code above it.


### 2026-07-05 - Phase 8C.12 Final Gesture And Artwork Repair

- Repaired latest manual-patch state without rewriting the stable overlay architecture.
- Preserved collapsed media-pill end-of-swipe resolution so one continuous left/right swipe still sends exactly one track command.
- Fixed the album-cover stale-image bug by separating the selected artwork key from the actual displayed image key in `MediaController`.
- Added `artworkImageRevision` so SwiftUI can detect when the real new `NSImage` has been assigned.
- Updated `FlippingAlbumArtworkView` to wait for the real new artwork image/revision before starting the directional flip.
- Preserved next = left flip and previous = right flip with midpoint image swap.
- Added expanded swipe-up fallback collapse for stale saved settings where `expandedSwipeUpAction` may still be `.none`.
- Preserved gesture settings gates for enabled/input/action mappings and media/collapse availability.

### 2026-07-06 - Phase 8C.13 Expanded Swipe Fix Reverted

- Attempted a focused `OverlayWindowController.swift` replacement for expanded swipe-up collapse.
- The attempt was rejected because it introduced a regression:
  - Collapsed swipe down began expanding the island but then immediately collapsed again before inner content appeared.
  - Root cause: the momentum/tail from the collapsed swipe-down expansion could be interpreted as an expanded swipe-up collapse during the same scroll stream.
- Do not reuse the 8C13 overlay replacement.
- This phase is documented only as a reverted/invalid intermediate state.

### 2026-07-06 - Phase 8C.14 Expanded Swipe Repair

- Repaired expanded swipe-up collapse without breaking collapsed swipe-down expansion.
- Fixed the scroll-tail handoff problem:
  - Collapsed swipe down expansion no longer immediately triggers expanded collapse from the same gesture momentum.
  - Expanded swipe-up collapse works only once the expanded island is actually active and the gesture is inside the expanded island region.
- Preserved:
  - Collapsed swipe down expands fully and content appears.
  - Expanded swipe up collapses when `Settings -> Gestures -> Expanded Island Gestures -> Swipe Up` is set to `Collapse`.
  - Collapsed swipe left/right remain one physical swipe = one media command.
  - Album cover flip and visualizer behavior were not touched.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation on macOS:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - Manual launch and gesture testing.

### 2026-07-06 - Phase 8C.15 Visualizer Artwork Color Sync And Universal Album Flip

- Fixed visualizer accent-color staleness:
  - The visualizer no longer keys accent color from an early selected `artworkKey` that can update before the new image is loaded.
  - Color extraction now follows the actual displayed artwork image key/revision so it cannot cache `new artwork key -> old artwork image color`.
  - This fixed the visualizer keeping the previous song/album color during both gesture skips and natural track changes.
- Generalized album-cover flip behavior:
  - Gesture next/previous still trigger directional flips.
  - Expanded media module next/previous buttons also trigger flips.
  - Internal `nextTrack()` / `previousTrack()` calls trigger flips.
  - Natural detected media identity/artwork changes also trigger a forward/default flip when a true previous direction cannot be inferred.
- Preserved artwork correctness guards:
  - Flip waits for the real new `NSImage` / displayed image revision before starting.
  - Midpoint swap uses the actual new cover.
  - Placeholder/old-cover flashes are still avoided.
  - Reduce Motion still bypasses the 3D flip.
- Preserved:
  - Expanded swipe-up collapse from Phase 8C.14.
  - Collapsed swipe-down expansion.
  - One-swipe-one-song media gestures.
  - Media arbitration and async artwork guards.
  - Timer, Stats, Tray, AirDrop, File Shelf, settings, and app launch behavior.
- Changed files:
  - `Sources/DynamicIsland/Modules/MediaController.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation on macOS:
  - `swift build`
  - `swift test`
  - `Scripts/package_app.sh`
  - Manual launch and media testing.

### 2026-07-06 - Phase 8C.15 Responsiveness Tuning

- User-tuned collapsed media swipe timing after Phase 8C.15:
  - `mediaSwipeQuietPeriod = 0.045`
  - `mediaSwipePostCommandLockoutSeconds = 0.05`
- Result:
  - Swipe left/right feels close to instant.
  - Album flip starts as soon as the external player publishes the song change and the real artwork path updates.
  - Spotify was manually tested and behaved correctly.
- Stability note:
  - If future testing on Apple Music or YouTube/browser shows double-skips from aggressive trackpad momentum, increase `mediaSwipePostCommandLockoutSeconds` first, e.g. to `0.15`.
  - Do not remove end-of-swipe resolution or artwork revision guards to make the animation feel faster.

### 2026-07-06 - Git Repo Restoration And Stable Final Tag

- Restored the stable fixed zip code into the original Git repository while preserving history.
- Active repo after merge:
  - Path: `~/Documents/DynamicIsland`
  - Branch: `phase-5h2-shoulder-tuning`
  - Commit: `de337d3`
  - Tag: `phase-8c15-stable-final`
- The previous zipped working copy was renamed to a backup folder.
- A full backup of the original Git repo before the merge was also created.
- Final verification on macOS passed:
  - `git status` clean
  - `swift build`
  - `swift test` with 57 tests and 0 failures
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - Packaged app produced at `dist/DynamicIsland.app`
- Current non-blocking warning:
  - `FileThumbnailCache` still emits the Swift concurrency non-Sendable capture warning in `ModuleViews.swift`.
  - This warning is known and did not block build/test/package.

### 2026-07-11 - Phase 9A/9B Island Theme System And Hybrid Glass Shell

- Created branch:
  - `phase-9ab-island-theme-system`
- Added island shell theme setting:
  - `IslandThemeStyle.classicBlack`
  - `IslandThemeStyle.liquidGlass`
  - Classic Black is the default and invalid stored raw values fall back to Classic Black.
- Updated Settings:
  - Added an Appearance/Shell picker labeled `Island Theme`.
  - Phase 9D later simplified the active options to Classic Black and Liquid Glass only.
  - Added helper text explaining that Liquid Glass uses native glass when available and falls back to macOS material on older systems.
- Added theme-aware shell rendering:
  - `IslandSurfaceBackground` owns Classic Black and Liquid Glass fallback shell backgrounds after Phase 9D.
  - Classic Black preserves the stable black shell style.
  - Liquid Glass uses a macOS material fallback with dark readability tint and subtle highlight layering.
  - Hybrid Black + Glass was prototyped here and removed from the active product in Phase 9D.
- Native Liquid Glass handling:
  - No direct `glassEffect(_:in:)` call was added because older local SDKs can fail compilation even behind `#available`.
  - A TODO is isolated in `IslandThemeBackground.swift` for adding the native SwiftUI Liquid Glass path when building with an SDK that exposes the API.
- Preserved:
  - Theme changes are visual-only.
  - Overlay frames, hit testing, gestures, media logic, album flip, visualizer color/timing, Tray, AirDrop, Timer, Stats, shell morph sequencing, and parked notch shoulder behavior were not changed.
  - Existing shell shadow, stroke, shape, content clipping, and shell-morph performance protections remain in place.
- Added tests:
  - Invalid island theme raw value falls back to Classic Black.
  - Theme selection persists by raw value.
- Changed files:
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/IslandThemeBackground.swift`
  - `Tests/DynamicIslandTests/AppSettingsTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Known limitation:
  - Native Liquid Glass depends on building with an SDK that exposes SwiftUI `glassEffect`; older SDKs use the macOS material fallback path.

### 2026-07-11 - Phase 9C Liquid Glass Visual Repair

- Reworked fallback Liquid Glass rendering:
  - Replaced the blur-heavy material-dominant look with a layered glossy smoked-glass shell.
  - Reduced dominant material opacity so the glass reads sharper and darker instead of frosted/cloudy.
  - Added dark smoked tint, top gloss, diagonal specular sheen, bottom depth gradient, and rim highlight strokes.
  - All decorative glass layers remain clipped to the existing island shell shape and opt out of hit testing.
- Note:
  - Hybrid Black + Liquid Glass rendering from this phase was removed from the active product in Phase 9D.
- Updated Settings helper text:
  - Clarifies that older macOS versions use a custom glossy material fallback.
- Preserved:
  - Classic Black remains the stable black shell path.
  - No changes were made to `OverlayWindowController`, hit testing, panel architecture, gestures, media controller, album flip, visualizer logic, artwork color sync, Tray, Timer, Stats, Island navigation, or shell morph timing.
  - Native `glassEffect` remains documented as a future SDK-gated path and is not referenced directly in compiled code.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandThemeBackground.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
- Known limitation:
  - Native Liquid Glass still depends on building with an SDK that exposes SwiftUI `glassEffect`; the current fallback is custom SwiftUI layering over macOS material.

### 2026-07-11 - Phase 9C.1 Liquid Glass Guidance Alignment

- Rechecked native SwiftUI Liquid Glass availability:
  - Local SDK path: `MacOSX26.2.sdk`.
  - Searched SwiftUI SDK interfaces/framework contents for `glassEffect`, `GlassEffectContainer`, and `glassEffectTransition`.
  - Those symbols were not exposed in the readable local SwiftUI interfaces, so no direct native `glassEffect` calls were added.
  - The helper keeps a clear TODO for adding `glassEffect(_:in:)`, `GlassEffectContainer`, and `glassEffectTransition` when the active SDK exposes them safely.
- Tightened the fallback Liquid Glass visual implementation:
  - Material is now only a low-opacity substrate, not the dominant visible effect.
  - Increased smoked-glass darkness and contrast.
  - Added stronger top gloss, top-edge glow, diagonal specular sheen, bottom depth, and brighter rim lighting.
  - No blur is applied to island content, album art, visualizer, controls, sliders, text, tabs, Tray, Timer, or Stats.
- Note:
  - Hybrid Black + Liquid Glass rendering was removed from the active product in Phase 9D.
- Preserved:
  - Classic Black default/stable shell.
  - `OverlayWindowController`, panel architecture, hit testing, gestures, media, album flip, visualizer logic, artwork color sync, Tray, Timer, Stats, Island navigation, and shell morph timing were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandThemeBackground.swift`
  - `context.md`
- Validation passed:
  - `git status`
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`

### 2026-07-11 - Phase 9D Theme Simplification

- Removed Black + Liquid Glass hybrid theme option.
- Theme picker now exposes only:
  - Classic Black
  - Liquid Glass
- Updated `IslandThemeStyle`:
  - Removed the active `hybridBlackGlass` case.
  - Classic Black remains the default.
  - Old saved hybrid-style raw values such as `hybridBlackGlass` and `blackLiquidGlass` safely migrate/fallback to Liquid Glass without resetting unrelated settings.
- Simplified theme rendering:
  - Removed the hybrid split background renderer and split-ratio code.
  - Classic Black remains the stable black shell path.
  - Liquid Glass/fallback renderer remains available.
- Preserved:
  - No changes were made to `OverlayWindowController`, panel architecture, hit testing, gestures, media controller, album flip, visualizer logic, artwork color sync, Tray, AirDrop, Timer, Stats, Island navigation, or shell morph timing.
- Changed files:
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Sources/DynamicIsland/Views/IslandThemeBackground.swift`
  - `Tests/DynamicIslandTests/AppSettingsTests.swift`
  - `context.md`

### 2026-07-11 - Phase 10A Mac-Style Live Activities Foundation

- Added an internal macOS overlay live activity foundation:
  - This does not integrate Apple ActivityKit.
  - `DynamicIslandLiveActivityKind`
  - `DynamicIslandLiveActivity`
  - `LiveActivityStore`
- Added shared `LiveActivityStore` ownership:
  - Created once in `AppDelegate`.
  - Passed through `IslandModules`.
  - Store supports deterministic sorting by priority, updated date, and title.
  - Store supports primary activity selection, update-by-id replacement, removal, remove-all, and clamped progress.
- Added activity sources:
  - Timer activity when the timer is running or paused with partially elapsed remaining time.
  - Media activity when a displayable media source exists.
  - File Tray activity when new files are added to the tray.
- Added Island tab UI:
  - Lightweight Live Activities section appears only when activities exist and live activities are enabled.
  - Shows up to three compact cards.
  - Timer card can switch to the Timer tab.
  - File Tray card can switch to the Tray tab.
  - Media card remains on the Island tab.
- Updated Live Activities settings:
  - Existing persisted Live Activities controls now enable/disable the Phase 10A sources.
  - Music, Timer, and File Tray source toggles are active.
  - Battery, Calendar, Downloads, style, auto-dismiss, and animation controls remain reserved for later phases.
- Preserved:
  - Existing Media module, Timer tab, Tray tab, Stats tab, collapsed pill layout, album flip, visualizer color sync, tray actions, AirDrop, OverlayWindowController, hit testing, gestures, panel architecture, stats polling, timer engine, theme renderer, and shell morph timing were not rewritten.
  - Collapsed live activity priority behavior is not implemented yet; that remains Phase 10B.
- Added tests:
  - Live activity sorting by priority/date/title.
  - Primary activity selection.
  - Updating the same id replaces the previous activity.
  - Removing activity works.
  - Progress clamping covers nil, invalid, low, in-range, and high values.
- Changed files:
  - `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - `Sources/DynamicIsland/Modules/IslandModule.swift`
  - `Sources/DynamicIsland/Modules/LiveActivityStore.swift`
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Tests/DynamicIslandTests/LiveActivityStoreTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Validation note:
  - First `open dist/DynamicIsland.app` returned LaunchServices `-600` immediately after `pkill`; retrying with the absolute app path succeeded.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-11 - Phase 10B Collapsed Live Activity Priority Settings

- Added collapsed live activity priority selection:
  - Running Timer, Playing Media, Paused Timer, Recent Files, and Paused Media are now modeled as selectable collapsed priority sources.
  - Default order is Running Timer, Playing Media, Paused Timer, Recent Files, then Paused Media.
  - Higher user priority wins; ties fall back to the default order, then update time/title for deterministic selection.
- Added persisted priority settings:
  - Settings now exposes a `Collapsed Live Activity Priority` group with steppers for each source.
  - Priorities are clamped to `0...200`.
  - Restore Defaults resets the source priorities without touching unrelated settings.
- Updated collapsed pill rendering:
  - Media-selected collapsed content keeps the existing compact artwork/visualizer path.
  - Timer/file live activity selections render compact icon/text/progress status inside the existing pill.
  - Inactive mode remains the empty compact pill.
- Preserved gesture behavior:
  - Collapsed swipe down still expands.
  - Media left/right gestures remain active only when the collapsed content mode is media.
  - Timer/file collapsed content does not route horizontal swipes to media controls.
- Updated live activity metadata:
  - Paused timer activities now publish `isActive = false`, allowing the selector to distinguish running and paused timers.
- Added tests:
  - Default source ordering.
  - Disabled source eligibility.
  - Custom priorities overriding defaults.
  - Tie fallback ordering.
  - Priority clamping and settings reset.
- Preserved:
  - No changes were made to `OverlayWindowController`, panel architecture, hit testing, album flip, visualizer color logic, media arbitration, Tray, AirDrop, Timer engine, Stats polling, theme rendering, or shell morph timing.
- Changed files:
  - `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - `Sources/DynamicIsland/Modules/LiveActivityStore.swift`
  - `Sources/DynamicIsland/State/AppSettings.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Tests/DynamicIslandTests/AppSettingsTests.swift`
  - `Tests/DynamicIslandTests/CollapsedLiveActivitySelectorTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-11 - Phase 10B.1 Collapsed Live Activity Rendering Repair

- Fixed collapsed priority mode rendering:
  - Replaced the generic collapsed live activity mode with explicit collapsed modes for media, timer, file tray, and inactive.
  - Timer and file tray live activities now render dedicated compact collapsed content instead of hiding media and showing an empty pill.
- Added compact collapsed activity views:
  - Timer mode shows a small timer/pause icon and monospaced remaining time.
  - File tray mode shows a tray icon and compact file count text.
  - Media mode continues to use the existing compact artwork/visualizer path.
- Fixed collapsed active sizing:
  - `OverlayWindowController` now computes collapsed active sizing from the selected collapsed content mode, not only `media.hasActiveMediaSource`.
  - The overlay observes the shared `LiveActivityStore` so timer/file activity changes can update collapsed geometry.
- Updated compact observation:
  - `CompactIslandView` observes the shared `LiveActivityStore` and animates when collapsed live activity content changes.
- Preserved gesture behavior:
  - Horizontal media gestures remain gated to visible media compact mode.
  - Timer/file collapsed modes do not route left/right gestures to media controls.
  - Collapsed swipe down expansion, expanded swipe up collapse, album flip, visualizer color sync, and click-through behavior were preserved.
- Added tests:
  - Custom priority can make paused media beat a running timer.
  - Selected timer and file tray modes are not inactive.
- Preserved:
  - No changes were made to media source arbitration, album flip logic, visualizer color logic, tray file actions, AirDrop logic, timer engine internals, stats polling, shell morph timing, or panel architecture beyond collapsed active sizing input.
- Changed files:
  - `Sources/DynamicIsland/Modules/LiveActivityStore.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Tests/DynamicIslandTests/CollapsedLiveActivitySelectorTests.swift`
  - `context.md`
- Validation passed:
  - `git status`
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Validation note:
  - `open dist/DynamicIsland.app` returned LaunchServices `-600` immediately after `pkill`; retrying with the absolute app path succeeded.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-11 - Phase 10B.4 Compact Timer Pill Final Fix

- Repaired the base compact timer pill without changing collapsed geometry:
  - No timer/live-activity-specific base collapsed height override was added.
  - Timer active collapsed mode continues to use the same base row height as the normal compact media pill.
- Changed the compact timer base layout to a notch-safe side-slot layout:
  - Timer icon stays in a fixed left slot.
  - A fixed center spacer keeps content away from the physical notch.
  - Remaining time stays in a fixed right slot.
  - Timer text uses smaller monospaced digits with tightening and scaling before clipping.
- Kept compact timer content minimal:
  - Base compact timer shows only icon plus remaining time.
  - Timer status/details remain in the hover-expanded live activity preview.
- Preserved:
  - Hover-expanded live activity preview layout and height were not changed.
  - Media compact UI, album flip, visualizer color sync, collapsed swipe down, expanded swipe up, media gesture gating, click-through behavior, Live Activity priority logic, Tray, AirDrop, Timer engine internals, Stats polling, theme rendering, and shell morph timing were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `git status`
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-11 - Phase 10B.5 Regular Collapsed Timer Pill Final Repair

- Fixed only the non-hovered regular collapsed timer pill:
  - Targeted `CollapsedTimerActivityCompactView`, the base collapsed timer view used when timer live activity wins priority and the pill is not hovered.
  - Did not change hover-expanded Live Activities preview rows, hover height, or the expanded Live Activities section.
- Preserved normal collapsed height behavior:
  - Timer base pill continues to use the same `CompactIslandView` row height as normal media active collapsed mode.
  - No timer/live-activity-specific collapsed geometry, frame height, minimum height, or vertical padding was added.
- Repositioned timer base content with notch-safe absolute side slots:
  - Timer icon is pinned to the left safe side.
  - The center/notch area is left empty.
  - Full remaining time is pinned to the right safe side with a wider adaptive text slot for minutes and hour-format values.
  - Base timer pill shows only icon plus compact monospaced remaining time.
- Preserved:
  - Media compact UI, gestures, album flip, visualizer color sync, collapsed swipe down, expanded swipe up, media gesture gating, click-through behavior, Live Activity priority logic, Tray, AirDrop, Timer engine internals, Stats polling, theme rendering, and shell morph timing were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `git status`
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Validation note:
  - `open dist/DynamicIsland.app` returned LaunchServices `-600` immediately after `pkill`; retrying with the absolute app path succeeded.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-11 - Phase 10B.6 Regular Collapsed Timer Pill Source-of-Truth Layout Fix

- Repaired only the regular non-hovered collapsed timer pill:
  - Targeted the timer base compact path used when Timer live activity wins collapsed priority.
  - Hover-expanded live activity preview and expanded Live Activities section were left unchanged.
- Reused the existing media compact pill layout model:
  - Added `CompactCollapsedSideSlotLayout` as the shared left-slot/spacer/right-slot row used by the media compact pill and timer compact pill.
  - Timer base compact layout now uses the same base collapsed row height and side-slot placement as the existing media compact pill.
  - Removed the timer-specific `GeometryReader`/absolute positioning path from Phase 10B.5.
- Fixed timer content placement:
  - Timer icon uses the media left-slot placement with a constrained 14 pt visual size.
  - Timer remaining time uses the media right-slot/visualizer-safe placement.
  - Timer time uses a smaller bold monospaced full-time string with tightening and scaling so minutes and seconds remain visible.
  - Base timer pill shows only icon plus compact remaining time.
- Height/geometry verification:
  - `NotchGeometryService.swift` has no diff from `phase-8c15-stable-final`, so collapsed geometry height remains the stable source of truth.
  - No timer/live-activity-specific collapsed geometry, frame height, minimum height, or vertical padding was added.
- Preserved:
  - Media compact UI, album flip, visualizer color sync, collapsed swipe down, expanded swipe up, media gesture gating, click-through behavior, Live Activity priority logic, Tray, AirDrop, Timer engine internals, Stats polling, theme rendering, and shell morph timing were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `git status`
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Validation note:
  - `open dist/DynamicIsland.app` returned LaunchServices `-600` immediately after `pkill`; retrying with the absolute app path succeeded.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-12 - Phase 10C - Collapsed Live Activity Stability Lock

- Locked the collapsed live activity selection invariants with focused tests:
  - Running Timer beats paused media by default.
  - Paused Timer beats paused media by default.
  - Running Timer beats playing media by default unless custom priority explicitly raises playing media above it.
  - Preview activities can include Timer + Media rows when both are eligible.
  - Selected collapsed activity returns only the primary winner.
- Added a lightweight preview mounting regression guard:
  - Non-hovered collapsed preview content resolves to `nil`, so stacked preview rows are not mounted in the regular collapsed layout.
  - Hovered collapsed preview content resolves to the stacked preview rows.
- Preserved the SwiftUI mount behavior:
  - `CompactIslandView` receives preview content only through `CollapsedPreviewContent.mounted(..., previewActive:)`.
  - `CollapsedPreviewRow` is only created with `if previewActive, let previewContent`.
  - Hidden live activity rows are not allowed to exist with `opacity(0)` in the base collapsed layout.
- Preserved collapsed geometry:
  - No timer-specific collapsed height was added.
  - No live-activity-specific collapsed height was added.
  - Timer compact, media compact, and file compact continue to share the same base collapsed shell height source.
  - Timer + paused media no longer participates in base collapsed layout height; secondary media is preview-only while hovering.
- Do not alter this path unless explicitly fixing collapsed/live-activity bugs.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Tests/DynamicIslandTests/CollapsedLiveActivitySelectorTests.swift`
  - `context.md`
- Validation passed:
  - `git status`
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-11 - Phase 10B.3 Collapsed Timer Pill Layout Repair

- Restored normal base collapsed pill height behavior for live activity modes:
  - Reverted the compact collapsed content row height back to the stable `16` pt row used by the media pill.
  - Did not change collapsed geometry, expanded geometry, hover-expanded preview height, or shell morph timing.
- Kept hover-expanded live activity preview unchanged:
  - Existing Timer/Media/File hover rows and multi-activity preview behavior remain intact.
- Fixed compact timer base layout:
  - Base timer pill now uses only a compact icon plus monospaced remaining time.
  - Removed extra base paused indicator text/icon; pause/running detail remains in the hover preview.
  - Reduced icon footprint, reduced timer font slightly, added layout priority, bounded trailing time width, and allowed tighter scaling before clipping.
- Preserved:
  - Media compact UI, album flip, visualizer color sync, collapsed swipe down, expanded swipe up, click-through behavior, media gesture gating, Live Activity priority logic, Tray, AirDrop, Timer engine internals, Stats polling, theme rendering, and expanded Live Activities section were not changed.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `context.md`
- Validation passed:
  - `git status`
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-11 - Phase 10B.2 Collapsed Live Activity Hover Preview

- Fixed compact timer collapsed layout:
  - Timer text now reserves trailing width, uses monospaced digits, allows tightening, and scales down before clipping.
  - Timer formatting now uses `m:ss` under one hour and `h:mm:ss` at one hour or more.
- Reused collapsed hover expansion for live activity previews:
  - Hover preview now supports up to three eligible live activity rows.
  - Preview ordering follows the same user-configurable collapsed live activity priorities.
  - The primary collapsed activity appears first, followed by secondary activities such as Now Playing or recent files.
- Preserved existing media hover behavior:
  - Media-only collapsed hover still shows song/artist details.
  - Media rows are not duplicated when live activity preview rows are available.
- Added compact hover preview rows:
  - Timer row shows title/status and trailing remaining time.
  - Media row shows song and artist/source.
  - File row shows file activity title/details.
- Preserved gesture behavior:
  - Horizontal media gestures remain active only when media is the visible collapsed content mode.
  - Collapsed swipe down still expands from media, timer, file, and inactive modes.
- Added tests:
  - Timer formatting for under and over one hour.
  - Hover preview includes primary timer and secondary media.
  - Hover preview respects max row count.
  - Hover preview ordering follows custom priority.
  - Disabled sources are excluded from hover preview.
- Preserved:
  - No changes were made to `OverlayWindowController`, panel architecture, click-through behavior, shell morph timing, media arbitration, album flip logic, visualizer artwork color sync, tray file actions, AirDrop logic, timer engine internals, stats polling, or theme rendering.
- Changed files:
  - `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - `Sources/DynamicIsland/Modules/LiveActivityStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Tests/DynamicIslandTests/CollapsedLiveActivitySelectorTests.swift`
  - `context.md`
- Validation passed:
  - `git status`
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Validation note:
  - `open dist/DynamicIsland.app` returned LaunchServices `-600` immediately after `pkill`; retrying with the absolute app path succeeded.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.
