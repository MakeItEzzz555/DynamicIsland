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
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `open dist/DynamicIsland.app`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.
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

### Phase 13A - Expanded Visibility Controls

- Added persisted `showExpandedLiveActivitiesSection`, defaulting to `true`, with initialization, reload, full-reset, module-reset, and complete persisted-key bookkeeping.
- Kept `liveActivitiesEnabled` as the master Live Activity engine switch. The new setting controls only whether the Live Activities module is mounted in the expanded Island page.
- Added the Live Activities settings group `Expanded Island` with the toggle `Show Live Activities section`. The control is disabled when the master engine switch is off and explains that collapsed activities and priorities remain active.
- Added internal, testable `ExpandedIslandRightStackVisibility`. It shows expanded Live Activities only when both the master engine and display setting are enabled, tracks Shortcuts independently, and reports whether either right-stack section is available.
- Updated only the expanded Island-page right stack to use the resolver. When the Live Activities section is hidden and Shortcuts are enabled, the Live Activities view is not mounted, no empty placeholder or inter-card spacing remains, and Shortcuts receives `metrics.pageHeight`. Right-stack width, media width, divider placement, and responsive geometry remain unchanged.
- The new display setting is not used by collapsed activity generation, selection, priority, hover-preview selection, or content-aware wing geometry.
- Hardened the existing `collapsedHoverPreviewEnabled` setting with an explicit `IslandRootView` observer. Disabling it calls the existing `deactivateCollapsedPreview()`, which clears hover/visibility state, increments `collapsedPreviewGeneration` to invalidate delayed reveals, and updates the preview interaction frame to zero.
- Re-enabling preview does not synthesize hover state; `expandOnHover` remains intentionally unwired.
- Added AppSettings tests for the true default, persistence through a new instance, and full-reset restoration. Added five focused resolver cases covering split visibility, display-only hiding, master-off behavior, Live-Activities-only behavior, and a fully unavailable right stack.
- Did not modify Clipboard functionality, `NotchGeometryService`, `IslandLayoutStore`, `OverlayWindowController`, shell geometry/radii/shadows, collapsed activity wings or height, panel behavior, providers, priority logic, transitions, Stats polling, gestures, or `ModuleViews.swift`.
- Validation on 2026-07-24:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 122 tests, 0 failures.
  - `chmod +x Scripts/package_app.sh`: completed.
  - `Scripts/package_app.sh`: passed on the first attempt and produced `dist/DynamicIsland.app`; no resource-fork cleanup was needed.
- Manual validation remains required for the expanded split/full-height matrix, live toggling while expanded, collapsed activity independence, master-off/restore behavior, active and delayed hover-preview cancellation, stationary-pointer re-enable behavior, and the listed expansion/tab/gesture/geometry regressions.

### Phase 13A.1 - Deterministic Artwork Flip Midpoint Handoff

- Separated raw `MediaController.artworkImage` publication from the artwork allowed to appear on screen. `MediaController` now owns one `ArtworkPresentationCoordinator` backed by the pure `ArtworkFlipPresentationState` reducer.
- `FlippingAlbumArtworkView` no longer owns independent displayed/pending/generation state, observes raw metadata/artwork, or renders `displayedArtwork ?? media.artworkImage`. Every collapsed, expanded, remounted, and `ViewThatFits` artwork instance renders only the shared presented snapshot and shared rotation.
- Raw artwork mutations synchronously feed the coordinator. Initial/no-request artwork is presented directly before an artwork view is mounted, avoiding an `onAppear`-dependent blank first frame.
- For valid next/previous requests, the old presented artwork is frozen through the complete first `0.19s` half. At exactly `-90°` for next or `+90°` for previous, a non-animated transaction commits the pending snapshot and resets rotation to the mirrored `+90°`/`-90°` second-half start. The incoming artwork remains presented through the full second half and completion.
- Removed the active-flip force-assignment path. Updates received during either half retain only the latest queued transition, do not alter presented artwork, and begin after the active transition completes.
- Flip request consumption moved from individual view startup to the shared midpoint. Direct non-animated, same-fingerprint, placeholder-only, Reduce Motion, and expired-request handoffs consume idempotently at their safe direct boundary.
- Generation checks reject stale midpoint/completion callbacks. Existing media publication-generation guards continue to reject stale asynchronous source artwork before it can reach presentation.
- Nil artwork is treated as the existing placeholder visual: nil-to-image and image-to-nil transitions swap only at midpoint when animated, while two placeholder states do not run a meaningless flip. Same visual fingerprints do not animate.
- Artwork-derived visualizer colors in collapsed and expanded media layouts now use the same presented fingerprint/image as the artwork, preventing incoming-cover color leakage before midpoint. No visualizer architecture was rewritten.
- Retained concise DEBUG-only `[ArtworkFlip]` logs for raw receipt, staging, first-half start, midpoint commit, second-half start, completion, queued updates, and stale callback rejection.
- Added 15 focused reducer tests covering next and previous direction, first/second-half ownership, active queues, stale generations, identical fingerprints, synchronous initial display, nil/image boundaries, placeholder-only behavior, no-request and expired-request updates, and Reduce Motion.
- `IslandRootView.swift` changed only at the compact visualizer accent source because midpoint-consistent collapsed accent color requires observing the shared presented artwork. Phase 13A visibility controls were not changed.
- Did not modify Clipboard, Live Activities, geometry, panels, Spaces, source arbitration/selection, transport timing, hover preview, gestures, file shelf, timer, battery, Stats, shell themes/shadows, or expansion/tab timing.
- Validation on 2026-07-24:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 137 tests, 0 failures.
  - `chmod +x Scripts/package_app.sh`: completed.
  - `Scripts/package_app.sh`: passed on the first attempt and produced `dist/DynamicIsland.app`.
- Manual validation remains required for collapsed and expanded next/previous midpoint timing, cached and delayed artwork, rapid input, expand/collapse during a transition, Reduce Motion appearance, artwork click-to-open, metadata, visualizer, gestures, hover preview, shell transitions, and both expanded `ViewThatFits` candidates.

### Phase 13B.1 - Clipboard History Engine

- Inspected Atoll's public `dev` branch at commit `503606ca34aece08d30d3c86bce50eb5e07a3139` as an architectural reference. Relevant files included its Clipboard manager/model, content helpers, panel/popover/window views and managers, notch header/history/notes integration, tabs, settings, app lifecycle, coordinator, view model, constants, and shortcut wiring.
- Adopted only native architectural ideas that fit DynamicIsland: `NSPasteboard.general`, `changeCount` polling, typed extraction, native pasteboard writing, bounded retention, observable shared state, and content-specific copy-back.
- Rejected Atoll's default-on monitoring, payload storage in UserDefaults, persistence without a separate opt-in, missing concealed/transient/autogenerated filtering, several view-owned monitor start paths, separate Clipboard panels/windows, expanded Clipboard tab, unbounded image ingestion, and Documents-directory storage.
- Added one `@MainActor` `ClipboardHistoryStore`, owned once by `AppDelegate` and transported through `IslandModules`. No SwiftUI view, overlay controller, panel, popover, or tab creates or polls a store.
- Monitoring is off by default and uses one 0.5-second repeating `Timer` added to the main run loop in `.common` mode. Starting or re-enabling first baselines `NSPasteboard.changeCount`, so clipboard content that existed before monitoring began is not imported.
- Supported logical payloads are text with required plain text and optional bounded RTF/HTML, normal non-file URLs, one or more file URLs, and PNG-normalized PNG/TIFF/JPEG images. Selection precedence is files, image, URL, then text; one pasteboard change creates at most one entry.
- Central limits are 2 MB plain text, 1 MB per rich-text representation, 8 MB normalized PNG, 100 files per entry, 16 KB URL strings, and 64 MB total history payload. Item count defaults to 50 and normalizes to `10...200`. Both item and byte retention prune oldest entries after capture, promotion, loading, and maximum changes.
- Known concealed, transient, and autogenerated marker types are checked before payload extraction, fingerprinting, or content logging. This remains a best-effort marker defence and does not claim universal password-manager coverage.
- Stable fingerprints use CryptoKit SHA256 over an explicit payload discriminator and length-prefixed canonical bytes. File URLs are standardized in preserved order, images use normalized PNG bytes, and text includes optional-representation digests/nil markers.
- Duplicate captures move the existing entry to the front, preserve its UUID, replace it with the current validated payload, and update its timestamp without increasing history count.
- Copy-back restores native text/RTF/HTML, URL, multiple file URL, or PNG representations. A successful write synchronously baselines the resulting change count, promotes once, and prevents the next poll from recapturing the app's own write; failed writes do not promote or alter the baseline.
- Optional persistence defaults off and uses versioned schema `1` at `~/Library/Application Support/DynamicIsland/clipboard-history.json`. Payloads are never placed in UserDefaults. Atomic serialized background writes use generation checks so stale queued saves cannot become the final archive. Corrupt/unknown archives load safely as empty; loaded payloads are revalidated, refingerprinted, deduplicated, and pruned.
- Settings added:
  - `clipboardHistoryEnabled = false`
  - `clipboardHistoryMaximumItems = 50`
  - `clipboardHistoryPersistenceEnabled = false`
  - `clipboardHistoryCaptureImagesEnabled = true`
- Added a Settings sidebar section named Clipboard with monitoring, maximum-items, image capture, persistence, and privacy explanations. No history rows, clear action, header button, overlay, expanded tab, panel, or window was added.
- Added focused AppSettings, native named-pasteboard client, fingerprint, archive, persistence, monitoring, filtering, deduplication, retention, copy-back, self-write, lifecycle, and generation-ordering coverage. Tests never access `NSPasteboard.general`.
- Validation on 2026-07-24:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 168 tests, 0 failures.
  - `chmod +x Scripts/package_app.sh`: completed.
  - `Scripts/package_app.sh`: passed on the first attempt and produced `dist/DynamicIsland.app`.
  - Direct `.build/debug/DynamicIsland` launch smoke succeeded with Clipboard History disabled and emitted no `[ClipboardHistory] monitoring started` or capture log.
- Full cross-application manual capture/copy-back/persistence validation remains required because Phase 13B.1 intentionally exposes no history UI. Sensitive-marker behavior is covered deterministically without placing real password-manager contents on the clipboard.
- `IslandRootView.swift`, `OverlayWindowController.swift`, geometry, panels, Spaces behavior, click-through behavior, shell/radii, transitions, gestures, Live Activities, artwork synchronization, media arbitration, Timer, Battery, File Shelf, Stats, themes, and shell-shadow removal were not modified.
- Atoll remained reference-only; no substantial GPL source was copied verbatim.

### Phase 13B.2 - Native In-Island Clipboard Interface

- Reused the already inspected Atoll `dev` reference at commit `503606ca34aece08d30d3c86bce50eb5e07a3139` for native visual hierarchy, compact row, icon, action, empty-state, scrolling, and header-button patterns.
- Added a native Clipboard History button directly left of the expanded header Settings button. It appears only while `clipboardHistoryEnabled` is enabled.
- Added `ClipboardHistoryView` as an in-island overlay inside the existing expanded page-area `ZStack`; no new panel, window, popover, sheet, tab, or geometry path was introduced.
- `ExpandedIslandView` owns only the local Clipboard presentation lifecycle. The existing shared `ClipboardHistoryStore` remains the sole owner of entries, copy-back, delete, clear, ordering, monitoring, and persistence.
- The overlay uses a page-only backdrop and a top-trailing native-material card. The card has a subtle stroke, continuous 17pt corners, no shadow, full page height, and a responsive width derived from `metrics.innerWidth * 0.46` with the requested `320...410pt` bound when space permits.
- Added header count, in-card Clear All confirmation, close button, empty state, lazy scrolling rows, text/URL/file/image presentation, timestamps, per-row copy and delete actions, and short generation-guarded copied feedback.
- Clipboard rows now use an explicit native vertical `ScrollView` containing a `LazyVStack`. The card header and inline Clear All confirmation remain outside the scroll region and fixed while only the remaining row area scrolls with native macOS momentum and indicators.
- Removed the duplicate copied-success indicator that previously appeared as a separate trailing row label. The fixed 24×24 copy button is now the sole feedback location, smoothly replacing its copy symbol with one green `Color.green.opacity(0.92)` checkmark without moving row content.
- Existing `copiedEntryID` and generation checks remain authoritative: both row-click and copy-button paths produce the same feedback, failed copy-back shows none, and an older delayed reset cannot clear a newer entry's checkmark.
- Added a bounded main-actor image thumbnail cache keyed by the existing entry fingerprint. Image data is decoded once per cached fingerprint, remains memory-only, and is not persisted by the view.
- Added the pure internal `ClipboardHistoryRowPresentation` resolver. File rows expose only last path components/counts and do not reveal parent paths.
- Clipboard presentation closes on feature disablement, expanded-content exit/unmount, collapse shell-only mode, page changes, Settings open, Escape, backdrop click, close-button click, and view disappearance.
- Replaced the previous approximate asymmetric `AnyTransition` and Clipboard-specific blur/scale modifier with the existing `innerBlurScaleClean` modifier directly. Its implementation and values were not changed; the Clipboard now shares the Island content modifier's center anchor, scale, blur, opacity, easing, and duration resolution.
- Clipboard presentation uses independent requested, mounted, visible, removing, and generation state. Opening mounts hidden, then reveals only after the exact `IslandContentTransitionTiming.expansionContentDelay(...)`; reveal uses the exact `expansionContentDuration(...)`.
- Animated close clears logical presentation and marks removal while keeping the card mounted for the exact `collapseContentDuration(...)`. Unmount occurs only after that exit duration plus the established `0.025s` completion buffer.
- Generation checks invalidate delayed reveal and delayed unmount callbacks. Rapid open-close-open therefore cannot reveal a closed card or unmount a reopened one.
- The page-area backdrop shares the requested/mounted/visible lifecycle but animates opacity only with the same expansion/collapse duration direction. It stops hit testing as soon as logical presentation closes.
- Reduce Motion and existing content/blur/scale settings continue flowing through `innerBlurScaleClean`; reduced/disabled/instant sequencing uses the established short or effectively immediate path.
- User-triggered header, internal-close, backdrop, Escape, and Settings actions use staged removal. Content exit/unmount, shell-only collapse, setting disablement, view disappearance, and page changes invalidate callbacks and unmount immediately so Clipboard dismissal cannot compete with outer shell or tab transitions.
- Removed the failed Clipboard-specific `GestureMask` and mounted-state global-lock approach. Native scrolling still failed because the Clipboard remained beneath the ancestor view carrying the Island `DragGesture`, allowing that recognizer to compete before its guarded action callback ran.
- Expanded content now uses sibling interaction layers: the normal header/page base receives `IslandPointerGestureModifier`, while the page-area Clipboard overlay is composed afterward above it and is not part of that gesture-enabled subtree. Compact content independently retains the same Island gesture modifier and existing behavior.
- The sibling overlay retains the exact page-area position and size from `ExpandedIslandLayoutMetrics`, covers only the area below the header, remains mounted and hit-testable through reveal and removal, and prevents interaction from reaching the gesture-enabled base until the existing delayed unmount completes.
- The Clipboard card receives the concrete `metrics.pageHeight` constraint from its parent. Its header and Clear All confirmation remain fixed while an explicitly bounded native vertical `ScrollView` and `LazyVStack` consume the finite remaining height for rows, with normal macOS indicators and momentum.
- The structural SwiftUI sibling-layer isolation remains correct but was insufficient by itself. The actual remaining blocker was the existing `OverlayWindowController` local scroll monitor returning `nil` after expanded handling, which consumed the event before SwiftUI, followed by `IslandHostingView.scrollWheel(with:)` being able to return before `super.scrollWheel`.
- Added transient, non-persisted `IslandLayoutStore.isExpandedScrollGestureSuppressed` state. It follows the Clipboard's mounted lifecycle immediately through hidden reveal, visible presentation, animated removal, and the completion buffer, then clears at actual unmount or immediately during defensive closure/disappearance.
- Both expanded AppKit scroll entry paths now return `false` while suppression is active. The local monitor therefore returns the original event, the global monitor performs no Island action, and `IslandHostingView` falls through to `super.scrollWheel(with:)` so the native Clipboard `ScrollView` can receive the event.
- `OverlayWindowController` subscribes to suppression boundaries and calls the existing `resetExpandedScrollTracking()`, cancelling the pending reset work item and clearing accumulated delta/handled state. This prevents partial pre-Clipboard deltas from firing after close.
- Collapsed scroll routing and gesture behavior are unchanged. Atoll's non-consuming local-monitor and scrollable-content suppression pattern was used only as an architectural reference; no substantial source was copied.
- No additional event monitor, custom `NSScrollView`, event reposting, manual scroll offsets, or momentum calculation was added. Existing Clipboard animation and the single green copied tick were unchanged.
- Added accessibility labels and hover help for the header entry, close, clear, copy, and delete controls.
- Added `ClipboardHistoryRowPresentationTests` covering text normalization, URL presentation, file path privacy, image metadata, and empty text fallback. Added `ClipboardHistoryPresentationStateTests` covering hidden mount, reveal, mounted removal, completion unmount, stale reveal/unmount rejection, immediate teardown, and rapid reopen. Added `ExpandedScrollEventRoutingPolicyTests` covering suppressed pass-through, eligible expanded routing, collapsed non-regression, routing restoration, non-consumption, disabled/non-trackpad pass-through, and `IslandLayoutStore` suppression defaults/idempotent toggling. Removed the failed global-lock-only coordinator tests; established gesture coordinator coverage remains unchanged.
- No changes were made to the Phase 13B.1 clipboard capture client, persistence format, monitoring lifecycle, settings definitions, Settings UI, Phase 13A visibility controls, Phase 13A.1 artwork synchronization, geometry, panel behavior, tabs, gestures, Live Activities, or shell transitions.
- Rejected Atoll's separate Clipboard panel/window/popover, dedicated expanded Clipboard tab, multiple monitoring owners, and view-created store. No substantial Atoll source was copied verbatim.
- AppKit scroll-routing correction validation on 2026-07-24:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 188 tests, 0 failures.
  - `chmod +x Scripts/package_app.sh`: completed.
  - `Scripts/package_app.sh`: passed on the first attempt and produced `dist/DynamicIsland.app`.
- Manual validation remains required for all text/URL/file/image rows, copy/delete/clear behavior, empty state, long-history scrolling, feature-disable dismissal, Settings/tab/Escape/backdrop/close dismissal, collapse/expand behavior, Reduce Motion, narrow expanded sizes, both themes, and accessibility.

### Phase 13C.1 - Clipboard Escape And Long-Text Correctness Hotfix

- Fixed Escape ownership without adding another event monitor. The existing `OverlayWindowController` AppKit local key monitor receives Escape before SwiftUI's `.onExitCommand`; it previously consumed the event and immediately requested the sequenced shell collapse, so Clipboard History never received its SwiftUI fallback.
- Added one `@MainActor` `IslandEscapeRouter`, owned by `OverlayWindowController` and passed through `IslandRootView` into `ExpandedIslandView`. It mirrors only the current topmost in-Island presentation and publishes deterministic dismissal-request generations; it does not mutate `ClipboardHistoryStore` or own Clipboard presentation state.
- Clipboard registers as `.clipboardHistory` whenever its existing presentation state is mounted. Registration therefore spans the hidden reveal delay, visible state, animated removal, and the existing `0.025s` completion buffer. It clears only after actual unmount, or defensively during immediate lifecycle shutdown and `onDisappear`.
- The AppKit key monitor now passes through non-Escape events and all Escape events while collapsed. While expanded, it consumes Escape to request topmost dismissal when Clipboard is registered; only when no presentation handles Escape does it call the unchanged `requestCollapseWithSequencing()` path.
- Repeated Escape requests remain consumed during mounted removal. The router increments each handled request deterministically, while the existing Clipboard close state now treats a repeated animated-close request during removal as idempotent, so no second close schedule restarts or extends the established animation.
- Fixed pasteboard URL classification order. The former `readURL` path applied the 16 KB URL size limit after only `URL(string:) != nil`; Foundation can construct relative URLs from scheme-less plain strings, so a 20,000-character word was incorrectly returned as `.oversized` before reaching text extraction.
- `readURL` now first requires a non-empty scheme, a non-file URL, and a non-empty absolute string. Only a candidate that passes that classification receives the unchanged 16 KB URL limit. Invalid, relative, and scheme-less candidates fall through to the unchanged 2 MB text path. Extraction precedence remains files, images, URLs, then text.
- Added deterministic `IslandEscapeRouterTests` for empty/registered/cleared/idempotent state, dismissal generations, expanded dismiss/collapse routing, collapsed pass-through, and full mounted-removal ownership. Added a presentation-state idempotence regression test and named-`NSPasteboard` coverage for 20,000-character text, relative paths, short HTTPS URLs, oversized valid HTTPS URLs, text over 2 MB, file precedence, whitespace-only text, and punctuation without a scheme. No test uses `NSPasteboard.general`, `NSEvent` monitors, or sleeps.
- Validation on 2026-07-25:
  - `git diff --check`: passed.
  - Focused regression run: 34 tests, 0 failures.
  - `swift build`: passed with no warnings. The initial managed-sandbox invocation could not write Swift's user module cache; the required build passed after granting compiler-cache access.
  - `swift test`: 205 tests, 0 failures.
  - `swift build -c release`: passed with no warnings.
  - `chmod +x Scripts/package_app.sh`: completed.
  - `Scripts/package_app.sh`: exited successfully on the first packaging attempt and produced `dist/DynamicIsland.app`.
  - Follow-up `codesign --verify --deep` passed. Strict verification found the known Finder/resource metadata on the generated bundle; `xattr -cr dist/DynamicIsland.app` made strict verification pass immediately, but the Documents file provider subsequently reapplied that metadata, so a later strict check reproduced the warning.
- Manual UI validation was not executed by Codex. The actual key-monitor sequence, rapid double-Escape behavior, Clipboard scrolling/copy/delete/Clear All, 20,000-character cross-application capture, normal HTTPS capture, collapsed/expanded gestures, and outside click-through still require the requested local checks.
- Clipboard timing/modifiers/generation delays, native scrolling, scroll suppression/pass-through, copied feedback, persistence, fingerprints, sensitive filtering, media, artwork, shell/tab timing, gestures, panels, Spaces, geometry, click-through, Live Activities, Shortcuts, Timer, Battery, File Shelf, Stats, themes, and shadows were intentionally left unchanged.

### Phase 12A - Final Island Content Transition Sequencing

- Fixed the brief fully-expanded empty-black content gap:
  - Root cause was `IslandRootView.startExpansionSequence()` setting `expandedContentMounted = false` and delaying the mount by `240ms` for normal animations and `300ms` for slow animations, then adding a nested `20ms` reveal delay.
  - The expanded shell could therefore finish or nearly finish morphing while no expanded content hierarchy existed.
  - Expanded content is now mounted immediately at expansion start with `contentVisible = false`.
  - Visibility begins after `IslandContentTransitionTiming.expansionContentDelay = 0.05s`, while the shell morph is still active.
  - `InnerBlurScaleCleanModifier` now makes non-visible expanded content opacity `0` when opacity transitions are enabled, instead of leaving newly mounted hidden content visibly blurred.
- Added centralized content transition timing:
  - `expansionContentDelay = 0.05s`.
  - `collapseShellDelay = 0.05s`.
  - `tabFadeOutDuration = 0.12s`.
  - `tabHandoffDelay = 0.01s`.
  - `tabFadeInDuration = 0.14s`.
- Changed collapse staging to the inverse timing:
  - `OverlayWindowController` now waits `0.05s` after marking expanded content as exiting before committing the collapsed state.
  - This lets expanded content begin fading/blurring out before the shell follows closed.
  - Existing mounted-content exit handling remains in place so expanded content is not removed immediately on collapse.
- Replaced overlapping tab crossfades with strict outgoing-then-incoming sequencing:
  - Root cause was `ExpandedIslandView` rendering directly from `navigation.selectedPage` inside a `ZStack` with `.transition(pageTransition)` and `.animation(..., value: navigation.selectedPage)`, which allowed the old and new tab pages to be visible during the same animation.
  - Added explicit tab presentation state: `displayedPage`, `pendingPage`, `tabTransitionPhase`, `tabContentVisible`, and `tabTransitionGeneration`.
  - The tab bar still updates immediately through `navigation.selectedPage`.
  - The page content now keeps the old `displayedPage`, fades/blurs it out completely, switches `displayedPage` while invisible, then fades/blurs the new page in.
  - Removed the old `pageTransition` and `pageAnimation` helpers so there is no second tab animation system.
- Added rapid-change safety:
  - New tab requests during `fadingOut` only replace `pendingPage`; the latest requested destination wins.
  - New tab requests during `fadingIn` cancel the stale generation and start a clean fade-out from the current displayed page.
  - Collapse/content exit calls reset tab presentation and increment the generation so stale delayed callbacks cannot reveal content after collapse.
- Preserved:
  - No changes to native macOS Space behavior, window level, collection behavior, overlay persistence, NotchGeometryService, media detection, Live Activities, battery, timer, gestures, hover preview, or responsive expanded layout.
- Validation passed:
  - `swift build`
  - `swift test` with `124` tests and `0` failures
  - `Scripts/package_app.sh`
  - Short debug launch smoke using `.build/debug/DynamicIsland`
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.
- Manual transition matrix:
  - Collapsed to expanded: not manually executed by Codex; requires local visual check for no fully expanded empty-black flash.
  - Expanded to collapsed: not manually executed by Codex; requires local visual check that content exits before shell contraction.
  - Rapid repeated expand/collapse: not manually executed by Codex; requires local UI check for stale delayed content.
  - Tab A to Tab B: not manually executed by Codex; requires local visual check that A disappears before B appears.
  - Rapid A to B to C clicks: not manually executed by Codex; requires local UI check for no ghost layers.
  - Change tab then immediately collapse: not manually executed by Codex; requires local UI check for no delayed incoming tab during/after collapse.
  - Re-expand: not manually executed by Codex; requires local UI check that the selected tab appears with normal expansion staging.
  - Existing shell morph: not manually executed by Codex; code path preserved except relative content timing.

### Phase 12A.1 - Balanced Shell And Content Staging

- Fine-tuned only the top-level expanded content staging from Phase 12A:
  - Phase 12A fixed tab overlap and removed the fully expanded empty-black gap.
  - The initial `0.05s` expansion staging made expanded content appear too early relative to shell geometry.
  - Content entrance now derives from the real active shell duration instead of a generic fixed delay.
- Centralized shell-derived content timing:
  - Actual shell duration is `settings.animationPreset.shellDuration / max(settings.shellAnimationSpeed, 0.25)`.
  - Reduced motion / extra reduced motion uses `0.24s`.
  - Instant preset uses `0.01s`.
  - Default `.normal` at `1.0x` shell speed remains `0.40s`.
  - Expansion content delay is `shellDuration * 0.62`, so default normal starts at `0.248s`.
  - Expansion content duration is `shellDuration * 0.45`, so default normal runs `0.18s` and finishes at about `0.428s`.
  - Collapse shell delay is `shellDuration * 0.06`, so default normal starts shell collapse after `0.024s`.
  - Collapse content duration is `shellDuration * 0.75`, so default normal reaches zero in `0.30s`.
- Preserved Phase 12A mounting and stale-task safety:
  - Expanded content still mounts immediately at expansion start with opacity/blur/scale hidden.
  - The single expansion sequence still owns delayed content visibility.
  - Delayed reveal still checks generation, expanded state, and expanded-content-exit state before showing content.
  - Shell morph cleanup now also follows the active shell duration instead of fixed `340/380ms` values, preventing slow/custom shell speeds from ending collapse staging before the content fade is complete.
- Collapse now feels more coupled:
  - Content exit starts immediately when collapse is requested.
  - Shell collapse follows after the derived tiny delay instead of the Phase 12A fixed `0.05s` hold.
  - Content reaches zero before the shell becomes too small, avoiding visible compression into collapsed geometry.
- Tab transition timing remains unchanged:
  - `tabFadeOutDuration = 0.12s`.
  - `tabHandoffDelay = 0.01s`.
  - `tabFadeInDuration = 0.14s`.
  - The `displayedPage` / `pendingPage` / generation-based tab architecture from Phase 12A was not retuned.
- Validation passed:
  - `swift build`
  - `swift test` with `124` tests and `0` failures
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.
- Manual transition matrix:
  - Collapsed to expanded: not manually executed by Codex; requires local visual check that content begins near the final shell morph portion and no empty black pause returns.
  - Expanded to collapsed: not manually executed by Codex; requires local visual check that content fades gradually and is gone before the shell is too small.
  - Rapid expand -> collapse before completion: not manually executed by Codex; requires local visual check for no stale delayed content.
  - Rapid collapse -> expand: not manually executed by Codex; requires local visual check for clean sequence reversal.
  - Tab switching: not manually executed by Codex; requires local visual check that Phase 12A sequential tab transition remains unchanged.

### Phase 12A.2 - Single Authoritative Shell/Content Timeline

- Consolidated the active expanded-content timing path:
  - `IslandRootView` remains the single owner of overall expanded content visibility through `contentVisible`.
  - Expanded content mounts immediately at expansion start with `contentVisible = false`.
  - The parent flips `contentVisible = true` after the shared expansion delay.
  - `ExpandedIslandView` no longer owns any overall presentation timer; it retains only the Phase 12A tab sequencing state.
- Replaced the Phase 12A.1 timing ratios with the requested single timeline:
  - Default shell duration remains `0.40s`.
  - Final manually approved expansion content delay is `shellDuration * 0.40`, so normal default starts at `0.16s`.
  - Final manually approved expansion content duration is `shellDuration * 0.40`, so normal default resolves at about `0.32s`.
  - Final manually approved collapse shell delay is `shellDuration * 0.15`, so normal default shell collapse starts after `0.06s`.
  - Final manually approved collapse content duration is `shellDuration * 0.40`, so normal default content exit lasts about `0.16s`.
- Removed hidden secondary timing ownership:
  - Deleted the old nested expansion mount/reveal delay from the active path.
  - Removed the old controller `collapseContentExitDelay` property; controller collapse now uses `IslandContentTransitionTiming.collapseShellDelay(...)`.
  - Reduced component stagger from the previous `0.035s * index` multiplier to a tiny `0.01s * index` multiplier, capped under `0.04s`.
  - Collapse modifier delay is capped at `0.015s`.
  - The Island-page divider now animates from the same `contentVisible` signal and shared content duration instead of trailing on an implicit/unowned timeline.
- Preserved tab transitions:
  - `tabFadeOutDuration = 0.12s`.
  - `tabHandoffDelay = 0.01s`.
  - `tabFadeInDuration = 0.14s`.
  - The displayed/pending page and generation-based tab handoff architecture was not changed.
- Added DEBUG-only transition timestamps:
  - Expansion logs: `expandRequested`, `expandedTreeMountedHidden`, `contentRevealStarted`, `shellMorphExpectedComplete`.
  - Collapse logs: `collapseRequested`, `contentExitStarted`, `shellCollapseStarted`, `contentExitExpectedComplete`, `shellCollapseExpectedComplete`.
  - Logs use `ProcessInfo.processInfo.systemUptime` and are not per-frame.
- Ownership validation:
  - Temporarily changed `expansionContentDelayRatio` to `2.50`, which makes the default normal expansion delay `1.0s`, and verified the variant compiles.
  - The subsequent manually approved final value is `expansionContentDelayRatio = 0.40`.
  - Visual 1-second ownership verification was not manually executed by Codex; it still requires local UI/trackpad testing.
- Validation passed:
  - `swift build`
  - `swift test` with `124` tests and `0` failures
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 12B - Native Overlay Cleanup And Runtime Optimization

- Permanently removed the `.canJoinAllApplications` A/B experiment, its environment override, conditional behavior mutation, and experiment-only logging.
- Final native overlay configuration is `.statusBar` with `[.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]`; `.stationary`, `.canJoinAllApplications`, and `.screenSaver` are absent.
- Deleted the obsolete Phase 11C.3–11C.9 manual Space compensation system:
  - Removed the motion probe panel, transition render panel, display-link tracking, WindowServer polling, prediction/recovery logic, compositor translations, reassertion loops, and compensation diagnostics.
  - Removed `SpaceTransitionCompensationMath.swift` and its compensation-only tests while retaining `OverlayGeometrySignature` with the active native geometry path.
- Removed the duplicate transition-render `IslandRootView`; `OverlayWindowController` now creates one production root hosted in one real `IslandOverlayPanel`.
- Native behavior remains one stable maximum-size transparent panel, ordered while enabled and ordered out only when the overlay is disabled. Screen-parameter changes may refresh genuine geometry; active app/Space and app activation changes no longer reassert the panel.
- Removed the unused `CompactHandoffGhostView` and its three temporary debug/isolation flags.
- Preserved final manually approved transition timing:
  - `expansionContentDelayRatio = 0.40`
  - `expansionContentDurationRatio = 0.40`
  - `collapseShellDelayRatio = 0.15`
  - `collapseContentDurationRatio = 0.40`
  - `tabFadeOutDuration = 0.12`
  - `tabHandoffDelay = 0.01`
  - `tabFadeInDuration = 0.14`
  - The collapse shell-clear handoff retains its approximately `+0.025s` padding.
- Removed temporary `[IslandMorph]` instrumentation. Hidden expanded content remains opacity `0` as a correctness invariant.
- Removed the obsolete user-facing Opacity transitions setting and persisted setting bookkeeping. Blur and scale transition settings remain configurable; opacity remains the mandatory visibility gate.
- Made `FileThumbnailCache` explicitly `@MainActor`; it records load state on the main actor, performs image-file data I/O in a detached utility task without capturing the cache, then creates/finalizes the image and publishes cache state on the main actor.
- Made system stats polling demand-driven:
  - Initialization takes one snapshot but does not start a timer.
  - Polling starts idempotently only when the real displayed Stats page is mounted and visible, and stops when leaving Stats or beginning collapse.
  - Refresh-interval changes preserve whether polling was already active, and history is retained across stops.
- Added focused stats polling lifecycle and refresh-interval tests. Removed compensation-only tests.
- Automated validation on 2026-07-20:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 107 tests, 0 failures.
  - `Scripts/package_app.sh`: initial signing attempt hit the documented resource-fork/Finder metadata error; after `xattr -cr dist/DynamicIsland.app`, packaging passed and produced `dist/DynamicIsland.app`.
  - Explicit dead-symbol searches found no probe panel, transition render panel, display link, compensation environment flag, join-all-applications experiment, collapse ghost, WindowServer polling, CVDisplayLink, or `[IslandMorph]` references.
- Manual validation remains required for the transition, tab, Stats lifecycle, native Spaces/Mission Control/Cmd+Tab, and transparent rounded-corner test matrices. The panel remains `hasShadow = false`; the 36 pt expanded corner radius was not changed.

### Phase 12B.1 - Shell Shadow Removal

- Permanently removed the main island shell-shadow feature after manual confirmation that the shell is correct without it.
- Removed `AppSettings.shellShadowEnabled`, its persistence/default/reset bookkeeping, and the Settings `Shell shadow` toggle. Any old persisted preference is now ignored.
- Removed all exterior and clipped-inner shadow rendering from `IslandSurface`; no island-shell `.shadow(...)`, blurred shadow layer, or shadow-specific `visualProgress` interpolation remains.
- The native `NSPanel` remains shadowless with `panel.hasShadow = false`.
- The existing shell stroke remains unchanged, along with shell shape, fill, opacity, themes, geometry, corner radii, and transition behavior.

### Phase 12C - Integrated Atoll-Style Notch Shell Geometry

- Removed the old decorative shoulder-blend architecture completely:
  - Deleted `NotchShoulderBlend.swift`.
  - Deleted the ellipse/blob rendering, manual tuning constants, debug tinting, enable flags, opacity/offset positioning, and unused shoulder asset image sets.
  - Removed the obsolete `Notch shoulder blend` Settings toggle, help text, `AppSettings` property, UserDefaults key, loading, saving, and reset bookkeeping. Old persisted values are ignored.
- Preserved the physical-notch integration environment by moving `NotchIntegratedShellEnvironmentKey`, `EnvironmentValues.isNotchIntegratedShell`, and `View.notchIntegrated(_:)` into `IslandRootView.swift`; the root still wires it from `layoutStore.hasHardwareNotch`.
- Replaced the old one-radius shell with one continuous `IslandShellShape` containing independently animatable `topCornerRadius` and `bottomCornerRadius` values through `AnimatablePair<CGFloat, CGFloat>`.
- Implemented the integrated path as one symmetric silhouette: outer top-left to inset top-left shoulder, inset left wall, bottom-left curve, flat bottom, bottom-right curve, inset right wall, outward top-right shoulder, then closed top edge.
- Exact initial physical-notch endpoints are:
  - Collapsed: top `6`, bottom `14`.
  - Expanded: top `19`, bottom `24`.
  - Both interpolate linearly from the existing `shellMorphProgress`/`shellVisualProgress`; no secondary animation or timing was added.
- Non-notch/floating shells keep `topCornerRadius = 0` while using the same bottom-radius interpolation.
- The same single shape instance drives `IslandSurfaceBackground`, the optional shell stroke, and content clipping for Classic Black and Liquid Glass.
- Added geometry safety clamping for non-finite, negative, and impossibly small temporary frames without changing production endpoint values.
- Added `IslandShellRadiiTests` for collapsed/midpoint/expanded endpoints, non-notch behavior, out-of-range clamping, and non-finite progress fallback.
- Preserved Phase 12B.1 shadow removal: no shell shadow or panel shadow was introduced, and `panel.hasShadow = false` remains.
- `OverlayWindowController.swift`, `NotchGeometryService.swift`, panel geometry, Space behavior, layout, gestures, and transition timing were not changed for Phase 12C.
- Validation on 2026-07-20:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 110 tests, 0 failures.
  - `Scripts/package_app.sh`: passed and produced `dist/DynamicIsland.app`.
  - Active-source searches found no decorative shoulder symbols, settings, assets, ellipse rendering, or shoulder-specific layer; notch integration definitions exist once and remain wired.
- Manual visual validation remains required for physical-notch collapsed/expanding/expanded/collapsing states, non-notch behavior if available, symmetry, content clearance, and both themes. The exact 6/14 and 19/24 radii were not tuned beyond the requested first A/B values.

### Phase 12C.1 - Integrated Notch Content Safe Areas

- Retained the visually validated integrated notch shell geometry unchanged. The new shoulders reduce the usable horizontal body width compared with the old straight-sided shell.
- Increased the shared collapsed horizontal content padding from `8pt` to `14pt`: the `6pt` collapsed shoulder inset plus approximately `8pt` of interior clearance.
- Increased `ExpandedIslandLayoutMetrics` horizontal padding from `22pt` to `24pt`: the `19pt` expanded shoulder inset plus approximately `5pt` of interior clearance.
- The single shared compact inset continues to wrap media artwork and visualizer, Timer icon/countdown, Battery icon/percentage, File activity icon/text, inactive content, hover preview rows, and future compact Live Activities.
- Added no per-activity padding, offsets, width changes, font changes, or trailing-slot changes.
- Panel/shell widths, `NotchGeometryService`, expanded responsive column metrics, and content hierarchy remain unchanged; responsive metrics naturally consume the two-point-smaller expanded inner width.
- Shoulder radii remain exactly collapsed `6/14` and expanded `19/24`, driven by the existing shell morph progress. Shape topology, detection, background, stroke, and clipping were not changed.
- No shell or panel shadows were restored; `panel.hasShadow = false` remains.
- Validation on 2026-07-20:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 110 tests, 0 failures.
  - Initial `Scripts/package_app.sh` signing failed with the known resource-fork/Finder metadata error. After `xattr -cr dist/DynamicIsland.app`, packaging passed and produced `dist/DynamicIsland.app`.
- Manual visual validation remains required for all collapsed activity modes, hover preview, all expanded pages, both themes, and slow expansion/collapse content clearance.

### Phase 12C.2 - Notch-Aware Body-Relative Content Insets

- Phase 12C.1's integrated-shell `14pt` collapsed and `24pt` expanded padding values were manually tested and found insufficient.
- The expanded `24pt` frame-relative inset left only `5pt` of actual interior clearance after the integrated shell's `19pt` side inset. The collapsed `14pt` value preserved `8pt` of interior clearance but remained visually too tight for edge-anchored compact content.
- Replaced the global padding values with notch-aware resolution through the existing `isNotchIntegratedShell` environment:
  - Physical-notch collapsed: `18pt` total inset.
  - Floating/non-notch collapsed: original `8pt` inset.
  - Physical-notch expanded: `41pt` total inset, preserving the former `22pt` body-relative clearance after the `19pt` shell inset.
  - Floating/non-notch expanded: original `22pt` inset.
- `IslandSurface` resolves and applies the collapsed value once at the shared outer compact-content boundary. Media, Timer, Battery, File, hover preview, and future compact activities inherit it without individual offsets or padding.
- `ExpandedIslandView` consumes the same notch-integration environment and supplies the resolved expanded value to `ExpandedIslandLayoutMetrics`; `innerWidth` continues to derive naturally from that single value.
- Added focused resolver assertions for integrated/floating collapsed and expanded values. No visualizer, activity width, font, trailing slot, or per-activity layout was changed.
- Integrated shell shape topology and exact `6/14 → 19/24` radii remain unchanged. `NotchGeometryService`, panel/surface frames, widths, hit testing, Space behavior, and transitions were not modified.
- No shell shadow was restored; `panel.hasShadow = false` remains.
- Validation on 2026-07-20:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 111 tests, 0 failures.
  - Initial `Scripts/package_app.sh` signing failed with the known resource-fork/Finder metadata error. After `xattr -cr dist/DynamicIsland.app`, packaging passed and produced `dist/DynamicIsland.app`.
- Manual visual validation remains required for all physical-notch collapsed activity modes, all expanded pages, and floating/non-notch displays if available.

### Phase 12C.3 - Hardware Notch Center Exclusion

- Confirmed that collapsed outer-padding-only fixes were conceptually incorrect: increasing the inset moved both side contents inward toward the physical center notch instead of keeping that obstruction empty.
- Modeled the physical notch as a non-usable central exclusion zone for the top compact primary row. The actual notch width comes from `NotchGeometryService`'s inferred notch rectangle and is propagated as `IslandGeometry.hardwareNotchWidth` through `OverlayWindowController` and `IslandLayoutStore` to `CompactIslandView`; SwiftUI performs no independent screen query.
- `CompactCollapsedSideSlotLayout` now divides integrated compact content into symmetric left and right flexible wings separated by layout-only space. Center safety clearance is `4pt` on each side, so exclusion width is `hardwareNotchWidth + 8pt`.
- The minimum usable side-wing width is `38pt`. For active integrated collapsed content, the adaptive minimum surface width is derived as `hardwareNotchWidth + 2×4pt clearance + 2×38pt wings + 2×8pt outer padding`, or `hardwareNotchWidth + 100pt`. A larger configured collapsed width continues to win.
- Restored collapsed outer horizontal padding to `8pt` for both integrated and floating shells. The manually validated integrated expanded padding remains `41pt`; floating expanded padding remains `22pt`.
- Media artwork/visualizer, Timer icon/countdown, Battery icon/percentage, and File icon/text now share the same side-wing container. No activity-specific offsets, fake notch mask, visible center view, or preview-row split was added.
- Floating/non-notch compact layout retains the original ordinary `HStack` behavior with no center exclusion. `IslandLayoutStore.hardwareNotchWidth` resolves to `0` on displays without a hardware notch.
- Integrated shell geometry, the exact `6/14 → 19/24` radii, shell morphing, background, stroke, clipping, transitions, expanded metrics, positioning, and panel architecture remain unchanged. No shell shadow was restored and `panel.hasShadow = false` remains.
- Added focused pure-geometry coverage for `150 → 250pt` and `160 → 260pt` required widths, `notchWidth + 8pt` exclusion, zero non-notch exclusion, configured-width precedence, and symmetric `38pt` wings. Updated the existing notch geometry expectation for the derived active width and the collapsed-padding assertion.
- Validation on 2026-07-21:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings.
  - `swift test`: 112 tests, 0 failures.
  - Initial `Scripts/package_app.sh` signing failed with the known resource-fork/Finder metadata error. After `xattr -cr dist/DynamicIsland.app`, packaging passed and produced `dist/DynamicIsland.app`.
- Manual validation remains required for physical-notch media, Timer, Battery, File activity, rapid winner switching, hover preview, unchanged expanded `41pt` spacing, and the absence of a center gap on a non-notch display.

### Phase 12C.4 - Compact Below-Notch Content Rail

- Experimentally restored the pre-12C.3 compact width and moved active content below the hardware notch using its propagated height.
- This approach was rejected: it avoided horizontal notch overlap but forced an unwanted non-hover active height of `hardwareNotchHeight + 22pt` (`60pt` for the 38pt fixture), producing a visibly dropped-down/taller pill.
- Phase 12C.5 removes the below-notch rail, hardware-notch height propagation, active-height growth, and rail-specific tests. Phase 12C.4 is retained here only as rejected experimental history, not as the final architecture.

### Phase 12C.5 - Content-Aware Physical-Notch Activity Wings

- Retained the Atoll-style integrated shell and identified the root mismatch: the new shell geometry had not been paired with a content-aware left-wing/physical-notch-core/right-wing collapsed activity layout.
- Removed the rejected Phase 12C.4 below-notch rail, hardware-notch height propagation, `hardwareNotchHeight + 22pt` sizing, 60pt active height, and integrated 2pt bottom-padding override. Compact content is back on the original vertically centered 16pt band and collapsed height again uses the normal configured/resolved value.
- Preserved `hardwareNotchWidth` from `NotchGeometryService` through `IslandGeometry`, `OverlayWindowController`, and `IslandLayoutStore`. The physical notch remains an empty central layout core; SwiftUI does not independently rediscover screen geometry.
- Added shared `CollapsedActivityLayoutProfile` values consumed by both geometry and rendering: media `14/30pt` (respecting artwork/visualizer visibility), Timer `13/38pt`, Battery `17/34pt`, File `17/44pt`. The File trailing text now has a deterministic 44pt frame without changing its font or scaling behavior.
- Uses existing 8pt shell-edge padding and 4pt of notch-side safety per visible region. For the 242pt fixture, exact minimum widths are media `310pt`, Timer `317pt`, Battery `317pt`, and File `327pt`; the universal `hardwareNotchWidth + 100pt`/symmetric 38pt rule is gone.
- Geometry anchors the core exactly to `notchRect.minX...notchRect.maxX`. Asymmetric content intentionally shifts the shell extent; any configured width beyond the activity requirement is divided equally outside the minimum left/right geometry. Propagated region widths are reconciled with the final integral panel frame to prevent sub-point alignment drift.
- `CompactCollapsedSideSlotLayout` renders explicit left, transparent center-core, and right regions for active integrated layouts. Media, Timer, Battery, and File all share it. Floating/non-notch layouts retain the original left/`Spacer`/right `HStack` with no fake core or activity-driven notch expansion.
- `OverlayGeometrySignature` now includes the current `CollapsedActivityLayoutProfile`, and live-activity observation deduplicates on that profile instead of only active/inactive presence. Activity winner changes therefore trigger one legitimate geometry refresh without adding another animation system.
- Expanded integrated padding remains `41pt` and floating expanded padding remains `22pt`. Shell path, exact `6/14 → 19/24` radii, morphing, background, stroke, clipping, hover preview, transitions, interaction geometry, and `panel.hasShadow = false` remain unchanged.
- Removed obsolete Phase 12C.3 universal-wing and Phase 12C.4 height/rail assertions. Added exact profile-width, core-alignment, larger-configured-width distribution, restored-height, inactive-sizing, non-notch fallback, and expanded-geometry coverage.
- Validation on 2026-07-21:
  - `git diff --check`: passed.
  - `swift build`: passed with no warnings after correcting public-profile visibility and immutable `Sendable` conformance.
  - `swift test`: 113 tests, 0 failures.
  - Initial `Scripts/package_app.sh` signing failed with the known resource-fork/Finder metadata error. After `xattr -cr dist/DynamicIsland.app`, packaging passed and produced `dist/DynamicIsland.app`.
- Manual validation remains required for media, Timer, Battery, File, activity switching, hover preview, expand/collapse, unchanged expanded spacing, and floating/non-notch behavior.

### Phase 12C.6 - Symmetric Collapsed Compact Wings

- Fixed only the integrated, non-hovered collapsed compact wing layout. The physical hardware notch remains the centered empty core.
- Replaced asymmetric per-side region sizing with one activity-specific symmetric wing width shared by geometry and SwiftUI rendering. Each wing uses the larger of the leading content plus `5pt` breathing room or trailing content, then retains the existing `4pt` notch-side safety clearance.
- Added `5pt` leading padding inside the left wing so artwork and leading Timer, Battery, and File content no longer hug the shell edge. Left content remains leading-aligned and right content remains trailing-aligned.
- Tightened only the compact media visualizer width from `30pt` to `27pt`; its outer right wing remains exactly equal to the left wing. Timer, Battery, and File trailing content widths remain unchanged.
- For the 242pt hardware-notch fixture, media now resolves to two equal `31pt` outer content regions and a `320pt` shell. Timer resolves to equal `42pt` regions, Battery to equal `38pt` regions, and File to equal `48pt` regions. Larger configured widths continue to divide surplus space equally outside the notch.
- Preserved collapsed height, expanded layout, notch inference and safety clearance, shell shape/radii, hover preview, gestures, transitions, Live Activity priority, single-row layout, and the existing non-notch fallback.
- Added geometry coverage proving all media, Timer, Battery, and File profiles resolve equal left/right wing widths, while retaining exact physical-notch boundary alignment.
- Validation on 2026-07-21:
  - `git diff --check`: passed.
  - `swift build`: passed.
  - `swift test`: 114 tests, 0 failures.
  - Initial `Scripts/package_app.sh` signing hit the known resource-fork/Finder metadata error. After `xattr -cr dist/DynamicIsland.app`, packaging passed and produced `dist/DynamicIsland.app`.
- Manual visual validation remains required for media, Timer, Battery, File, hover preview, and expansion/collapse.

### Phase 11C.11 - Native canJoinAllApplications A/B Test

- Added the isolated native Space membership A/B variable on top of the stable 11C.10 configuration:
  - Default native collection behavior is now `[.fullScreenAuxiliary, .canJoinAllSpaces, .canJoinAllApplications, .ignoresCycle]`.
  - DEBUG override `DYNAMIC_ISLAND_DISABLE_JOIN_ALL_APPLICATIONS=1` restores the 11C.10 variant `[.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]`.
  - `panel.level` remains `.statusBar`.
  - No `.stationary`, `.auxiliary`, `.transient`, `.fullScreenPrimary`, `.primary`, or `.screenSaver` was added.
- Preserved native parity mode:
  - Manual Space compensation remains disabled by default.
  - `SpaceMotionProbePanel`, `SpaceTransitionRenderPanel`, `CGWindowListCopyWindowInfo` Space correction, `CVDisplayLink` Space correction, prediction, per-frame `NSWindow` movement, and per-frame layer counter-translation remain inactive unless `DYNAMIC_ISLAND_ENABLE_SPACE_COMPENSATION=1` is set.
  - App/Space lifecycle notifications were not changed and still do not reconfigure, reorder, reposition, or retry in parity mode.
- Added startup DEBUG A/B logging:
  - Default startup: `[SpaceNativeAB] canJoinAllApplications=true level=25 collectionBehavior=262465`.
  - Override startup: `[SpaceNativeAB] canJoinAllApplications=false level=25 collectionBehavior=321`.
  - Both startup smokes confirmed `spaceDisplayLinkRunning=false`, `probeVisible=false`, and `transitionRenderVisible=false`.
- Runtime collection behavior variants:
  - Default with `.canJoinAllApplications`: raw `262465`.
  - Override without `.canJoinAllApplications`: raw `321`.
- Validation passed:
  - `swift build`
  - `swift test` with `124` tests and `0` failures
  - `Scripts/package_app.sh`
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.
- Manual A/B transition matrix:
  - Desktop Space A to Desktop Space B: not manually executed by Codex; requires local trackpad test.
  - Fullscreen to Desktop Space: not manually executed by Codex; requires local fullscreen test.
  - Desktop Space to Fullscreen: not manually executed by Codex; requires local fullscreen test.
  - Fullscreen to Fullscreen: not manually executed by Codex; requires local fullscreen test.
  - Mission Control behavior: not manually executed by Codex; requires local Mission Control test.
  - Slow, normal, fast, and cancel/reverse partial Space swipes: not manually executed by Codex; require local trackpad testing.
- A/B winner:
  - Not determined by Codex because the required visual Space/Mission Control transition matrix needs local interaction.
  - The default is set to the `.canJoinAllApplications` variant for the requested experiment.
  - Keep it only if local testing shows desktop/windowed Space transitions improve without fullscreen, Mission Control, interactivity, flicker, duplication, or disappearance regressions.

### Phase 11C.10 - Exact Atoll Native Window Parity Experiment

- Added the Atoll parity experiment switch:
  - `OverlayWindowController.useExperimentalSpaceCompensation` is `false` by default.
  - DEBUG override `DYNAMIC_ISLAND_ENABLE_SPACE_COMPENSATION=1` restores the Phase 11C.9 probe/render/display-link compensation stack for A/B testing.
  - Default parity mode stops and orders out the `SpaceMotionProbePanel` and `SpaceTransitionRenderPanel`.
  - Default parity mode does not start the `SpaceLockDisplayLink`, does not poll `CGWindowListCopyWindowInfo` for Space tracking, does not apply Space layer counter-translation, and does not run Space prediction or recovery.
- Matched the inspected Atoll notch-panel configuration for the effective island panel:
  - Style mask is `[.borderless, .nonactivatingPanel]`.
  - `isFloatingPanel = true`.
  - `becomesKeyOnlyIfNeeded = false`.
  - `level = .statusBar`.
  - `sharingType = .readOnly`.
  - `backgroundColor = .clear`.
  - `isOpaque = false`.
  - `hasShadow = false`.
  - `isMovable = false`.
  - `hidesOnDeactivate = false`.
  - `canHide = false`.
  - `isReleasedWhenClosed = false`.
  - Collection behavior is exactly `[.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]`.
  - `.stationary`, `.canJoinAllApplications`, `.auxiliary`, `.transient`, `.fullScreenPrimary`, and `.primary` are not in the effective collection behavior.
- Stopped parity-mode panel manipulation on app/Space lifecycle events:
  - `activeSpaceDidChange`, `didActivateApplication`, `didBecomeActive`, and `didResignActive` now only keep DEBUG logging in parity mode.
  - They do not reposition, reorder, reconfigure, restore frames, schedule recovery verification, or start Space monitoring in parity mode.
  - Screen-parameter changes still reposition through the existing geometry path, but probe/render/reassertion work remains disabled unless the A/B override is enabled.
- Kept the island panel permanently ordered while overlay is enabled:
  - Initial show positions the canonical frame and orders the island once.
  - Collapsed/expanded state changes no longer re-order an already visible panel in parity mode.
  - Overlay disable still orders out the island and any experimental panels.
  - Mouse behavior remains controlled by `ignoresMouseEvents`.
- Preserved the fixed-canvas island architecture:
  - The canonical panel frame remains the existing NotchGeometryService expanded/canvas-sized frame at the top-center notch position.
  - Collapsed/expanded morphing remains SwiftUI-owned.
  - No collapsed UI, expanded UI, Live Activities, gestures, media, timer, battery, hover preview, click-through calculations, or NotchGeometryService behavior was intentionally changed.
- Runtime parity startup result:
  - `[AtollParity] level=25 collectionBehavior=321 frame=(246.0, 592.0, 860.0, 286.0)`.
  - `containsFullScreenAuxiliary=true`.
  - `containsCanJoinAllSpaces=true`.
  - `containsIgnoresCycle=true`.
  - `containsStationary=false`.
  - `containsCanJoinAllApplications=false`.
  - `spaceDisplayLinkRunning=false`.
  - `probeVisible=false`.
  - `transitionRenderVisible=false`.
  - `islandVisible=true`.
- A/B startup result:
  - `DYNAMIC_ISLAND_ENABLE_SPACE_COMPENSATION=1 .build/debug/DynamicIsland` starts the Phase 11C.9 machinery.
  - Startup log showed `SpaceRender canvasSetFrame`, `SpaceProbe displayLinkStarted nominalFPS=120.0`, and `SpaceProbe BASELINE_CAPTURED offset=0.0`.
  - A/B mode still uses the Atoll-level/statusBar window configuration from this phase.
- Validation passed:
  - `swift build`
  - `swift test` with `124` tests and `0` failures
  - `Scripts/package_app.sh`
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.
  - No-trace parity smoke: `pkill -9 DynamicIsland`; `.build/debug/DynamicIsland`; no `SpaceProbe` or `SpaceRender` runtime activity appeared, and `[AtollParity]` confirmed display link/probe/render were inactive.
- Manual transition matrix:
  - Slow 3-finger Space transition: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Normal Space transition: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Fast Space transition: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Fullscreen to desktop: not manually executed by Codex; requires local fullscreen test.
  - Desktop to fullscreen: not manually executed by Codex; requires local fullscreen test.
  - Fullscreen app to fullscreen app: not manually executed by Codex; requires local fullscreen test.
  - Cmd+Tab into/out of fullscreen: not manually executed by Codex; requires local fullscreen test.
  - Visual comparison against `DYNAMIC_ISLAND_ENABLE_SPACE_COMPENSATION=1`: startup behavior verified; actual transition comparison requires local trackpad/fullscreen testing.

### Phase 11C.9 - Predictive Space Motion Resampling

- Preserved the Phase 11C.8 render-canvas architecture:
  - The real interactive `islandPanel` remains physically canonical during normal Space transitions.
  - `SpaceMotionProbePanel` remains the independent uncompensated sensor.
  - `SpaceTransitionRenderPanel` remains the fixed wide render canvas.
  - The duplicate visual-only `IslandRootView` remains continuously mounted.
  - The normal display-frequency visual mutation remains only `transitionIslandHostingView.layer` affine transform.
- Addressed the remaining temporal jitter:
  - 11C.8 manual testing improved tracking by roughly an order of magnitude, but visible lag/stair-stepping could remain because display-link cadence and fresh WindowServer probe samples are not the same thing.
  - Added timestamped raw probe samples and distinct probe samples.
  - A sample is distinct only when translation changes by more than `0.1` pt.
  - Maintains `lastRawProbeSample`, `previousRawProbeSample`, `lastDistinctProbeSample`, `previousDistinctProbeSample`, and an EMA of distinct sensor intervals.
- Added bounded motion prediction:
  - Velocity is estimated only from distinct samples, never repeated identical samples.
  - Velocity is clamped by `screenWidth * 6.0` points/second; larger jumps are treated as discontinuities and prediction velocity becomes zero.
  - Prediction lead uses `distinctProbeSampleIntervalEMA * 0.6`, clamped to `8...24ms`.
  - Prediction distance is capped at `min(screenWidth * 0.04, 60)`, which is about `54` pt on the `1352` pt test display.
  - Prediction is disabled near rest when raw translation is under `8` pt or velocity is under `20` pt/second.
- Added reversal handling:
  - Consecutive distinct sample deltas with opposite signs are treated as a direction reversal.
  - On reversal, previous velocity prediction is discarded, the latest raw sample is used directly, and velocity is rebuilt from subsequent distinct samples.
- Added render coalescing and hot-path cleanup:
  - MainActor render updates remain strictly coalesced; queued closures consume the newest sample state instead of capturing stale translation values.
  - The hot path reads the newest probe sample, updates numeric motion state, predicts the current translation, dedupes tiny transform changes under `0.1` pt, and writes one disabled-actions layer transform.
  - No normal-path per-frame real island `NSWindow.setFrame`, geometry recalculation, SwiftUI observable update, visible-island CG query, window ordering, or mouse-passthrough update was added.
- Added activation/completion hysteresis:
  - Activation threshold is now `2.0` pt.
  - Completion threshold is now `0.5` pt.
  - Completion requires `9` stable display frames.
  - This keeps the duplicate renderer active through tiny endpoint bounces instead of flickering the handoff.
- Added one-frame overlapping visual handoff:
  - On completion, the real island is forced canonical and main content opacity is restored first.
  - The duplicate renderer remains visible at approximately zero translation for one frame.
  - On the next frame, the duplicate is hidden, its layer transform resets to identity, and normal mouse passthrough is restored.
- Preserved baseline safety:
  - Stable baseline capture still requires `10` consecutive samples within `±2` pt.
  - Recovery only requests baseline recapture; it does not establish a new baseline while motion is active.
  - Startup trace captured `BASELINE_CAPTURED offset=0.0`; no invalid nonzero baseline appeared.
- Added diagnostics and A/B switch:
  - `DYNAMIC_ISLAND_DISABLE_SPACE_PREDICTION=1` uses raw probe translation directly for 11C.8-style comparison.
  - `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1` logs approximately every `0.25s`: display FPS, distinct probe sample Hz, raw translation, predicted translation, prediction lead, velocity, layer compensation, main-queue render delay, p95 visual error, and max visual error.
  - Visible island CG position is sampled only at low frequency for diagnostics, not at display frequency.
  - Normal DEBUG runs without trace logging no longer print per-frame `SpaceProbe` or `SpaceRender` tracking lines.
- Updated pure math tests:
  - Bounded prediction uses short adaptive lead.
  - Prediction distance clamps to the configured maximum.
  - Prediction disables near rest and in raw A/B mode.
  - Direction reversal detection ignores tiny noise.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Overlay/SpaceTransitionCompensationMath.swift`
  - `Tests/DynamicIslandTests/SpaceTransitionCompensationMathTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test` with `124` tests and `0` failures
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - Packaging first hit the known resource-fork signing issue, then passed after `xattr -cr dist/DynamicIsland.app`.
  - Normal no-trace smoke: `pkill -9 DynamicIsland`; `.build/debug/DynamicIsland`; no `SpaceProbe`/`SpaceRender` per-frame lines appeared.
  - Predictive trace: `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1 .build/debug/DynamicIsland`.
  - Raw A/B trace: `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1 DYNAMIC_ISLAND_DISABLE_SPACE_PREDICTION=1 .build/debug/DynamicIsland`.
- Trace result:
  - Predictive idle startup captured `displayFPS` settling around `111.1`, `distinctProbeSampleHz=0.0`, `rawTranslationX=0.0`, `predictedTranslationX=0.0`, `predictionLeadMilliseconds=0.00`, `p95VisualErrorX=0.0`, and `maxVisualErrorX=0.0`.
  - Raw A/B idle startup showed predicted translation equal to raw translation and prediction lead `0.00ms`.
  - No `PROBE_RECOVERY` or `correctionRejected` appeared during startup smoke traces.
- Manual transition matrix:
  - Very slow swipe: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Normal swipe: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Fast swipe: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Halfway hold: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Halfway reverse/cancel: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Repeated rapid Space switches: not manually executed by Codex; requires local trackpad test with trace logging disabled.
  - Raw A/B visual result: not manually executed by Codex; requires local trackpad test with `DYNAMIC_ISLAND_DISABLE_SPACE_PREDICTION=1`.
  - Predictive A/B visual result: not manually executed by Codex; requires local trackpad test without the disable flag.

### Phase 11C.8 - Core Animation Space Transition Render Canvas

- Replaced Phase 11C.7's remaining per-frame real island `NSPanel` movement:
  - The 11C.7 trace proved the independent probe and inverse feed-forward math were correct.
  - Clean transition traces reached approximately `-1415` probe translation on a `1352` pt screen, which is a valid one-Space movement.
  - Moving the real island `NSPanel` every display frame kept it near the notch but still produced visible lag/staggering because AppKit window movement remained in the hot path.
- Kept the Space Motion Probe:
  - `SpaceMotionProbePanel` is still the independent, uncompensated WindowServer motion sensor.
  - The probe is still never used for hover detection, click-through, collapsed gestures, expanded hover boundaries, or user interaction.
- Added a render-only transition canvas:
  - `SpaceTransitionRenderPanel` is a wide transparent non-interactive `NSPanel`.
  - It uses the same `OverlayPersistence.level` and `OverlayPersistence.collectionBehavior` as the island panel.
  - It keeps clear background/content, no shadow, `alphaValue = 1`, `ignoresMouseEvents = true`, `canBecomeKey = false`, and `canBecomeMain = false`.
  - The startup trace on the test display created canvas frame `x=-2704`, `y=592`, `width=6760`, `height=286`.
  - Canvas width is `screenWidth + (screenWidth * 2.0 * 2)`, giving two screen widths of horizontal margin on each side.
- Mounted a duplicate visual island renderer:
  - A second `NSHostingView<IslandRootView>` is mounted once inside `SpaceTransitionRenderPanel`.
  - It shares the existing `settings`, `islandState`, `layoutStore`, and `modules`.
  - Its callbacks are inert: no expand, collapse, or settings actions are routed through the duplicate renderer.
  - The duplicate host is laid out at the canonical island position inside the wide transition canvas.
- Replaced hot-path window movement with layer movement:
  - The real `islandPanel` remains at `canonicalPanelFrame`.
  - During an active Space transition, the main island content layer is hidden and the real panel is forced click-through.
  - The duplicate renderer is shown, and only `transitionIslandHostingView.layer` receives a disabled-actions affine translation.
  - The applied layer compensation is `-probeTranslationX`.
  - No normal-path `spaceLockOffsetX += error`, proportional gain, island CG acknowledgement wait, or per-frame real island `NSPanel.setFrame` remains.
- Fixed probe baseline poisoning:
  - Baseline capture is now explicitly pending after probe setup, recovery, screen changes, and active app/Space events.
  - A baseline is captured only after `10` consecutive display-link samples with raw probe offset within `±2` pt.
  - The startup trace showed `BASELINE_STABLE_SAMPLE` counts `1...10`, then `BASELINE_CAPTURED offset=0.0 probeCGX=4.0 probeCanonicalX=4.0`.
  - No invalid nonzero baseline such as `offset=2156` was captured in the 11C.8 startup trace.
- Added transition activation/completion policy:
  - Render mode activates when `abs(probeTranslationX) > 1.5`.
  - Render mode completes after `4` stable samples back within the activation threshold.
  - Normal probe translation range is `screenWidth * 1.75`; on the test display this is `2366` pt.
  - Absolute probe anomaly range is `screenWidth * 2.5`; on the test display this is `3380` pt.
  - Samples between the normal and absolute ranges hold the last valid layer transform instead of moving the island thousands of pixels.
  - Repeated samples beyond the absolute range still trigger recovery.
- Preserved hard recovery as a fallback:
  - Physical real-island stale/runaway bound remains `screenWidth * 1.25`; on the test display this is `1690` pt.
  - Recovery still resets `spaceLockOffsetX = 0`, restores `canonicalPanelFrame`, calls `orderFrontRegardless()` once, restores mouse passthrough, enters a `0.15s` cooldown, and requests a fresh stable probe baseline.
  - Recovery triggers for real island physical offset beyond `screenWidth * 1.25`, repeated missing/offscreen probe snapshots, repeated invalid probe translations beyond the absolute range, nonfinite probe translations, and post-Space verification finding an out-of-bounds physical island frame.
- Preserved canonical visual hit testing:
  - `screenRect(for:)` and collapsed gesture local-point conversion still use `canonicalPanelFrame`, not the transition renderer or any temporary layer transform.
- Updated pure math tests:
  - Valid observed `-1415` one-Space probe translation stays inside the normal `screenWidth * 1.75` range.
  - Probe translations between normal and absolute bounds are held rather than immediately recovered.
  - Large probe anomalies beyond `screenWidth * 2.5` remain invalid before moving the island thousands of pixels.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Overlay/SpaceTransitionCompensationMath.swift`
  - `Tests/DynamicIslandTests/SpaceTransitionCompensationMathTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test` with `120` tests and `0` failures
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1 .build/debug/DynamicIsland 2>&1 | tee /tmp/dynamicisland-11c8.log`
- Trace result:
  - `SpaceRender canvasSetFrame` reported `frame=(-2704.0, 592.0, 6760.0, 286.0)`.
  - `SpaceProbe BASELINE_CAPTURED` reported `offset=0.0`.
  - Idle render trace showed `probeTranslationX=0.0`, `layerCompensationX=-0.0`, `transitionActive=false`, `mainPanelFrameX=246.0`, `mainContentVisible=true`, and `transitionContentVisible=false`.
  - Observed display-link cadence reported `nominalFPS=120.0`, then observed debug samples around `98.6` to `111.2 FPS` during startup/media polling.
  - No `PROBE_RECOVERY`, `correctionRejected`, `physicalX=-2584`, `physicalX=-3999`, or invalid nonzero baseline appeared during the startup trace.
- Manual transition matrix:
  - Extremely slow three-finger Space swipe: not manually executed by Codex; requires local trackpad test.
  - Normal-speed Space swipe: not manually executed by Codex; requires local trackpad test.
  - Very fast Space swipe: not manually executed by Codex; requires local trackpad test.
  - Slow halfway drag and hold: not manually executed by Codex; requires local trackpad test.
  - Reverse/cancel halfway gesture: not manually executed by Codex; requires local trackpad test.
  - Rapid consecutive Space changes: not manually executed by Codex; requires local trackpad test.
  - Expand/collapse after switching: not manually executed by Codex; requires local UI test.
  - Hover/click-through: not manually executed by Codex; requires local UI test.

### Phase 11C.7 - Decoupled Space Motion Probe

- Replaced the laggy Phase 11C.6 self-referential Space Lock normal path:
  - Slow gesture testing proved the compensation direction was correct.
  - The sample-and-hold safety controller was intentionally stable but too low-bandwidth for normal-speed macOS Space transitions.
  - The old normal path measured the visible island window while also moving that same window, creating WindowServer feedback latency.
- Added an independent Space Motion Probe:
  - `SpaceMotionProbePanel` is a tiny `2x2` transparent non-interactive `NSPanel`.
  - It uses the same `OverlayPersistence.level` and `OverlayPersistence.collectionBehavior` as the island panel.
  - It keeps `alphaValue = 1`, clear content/background, no shadow, `ignoresMouseEvents = true`, `canBecomeKey = false`, and `canBecomeMain = false`.
  - Its canonical frame is anchored on the island's target screen at `x = screen.minX + 4`, `y = screen.maxY - 4 - 2`, `width = 2`, `height = 2`.
  - It is never counter-translated and exists only as a WindowServer motion sensor.
- Replaced normal tracking with absolute feed-forward:
  - Probe baseline is captured once after setup/screen changes as `probeWindowServerXOffset = probeCGX - probeCanonicalX`.
  - Raw Space translation is `probeTranslationX = actualProbeCGX - (probeCanonicalX + probeWindowServerXOffset)`.
  - Visible island offset is `spaceLockOffsetX = -probeTranslationX`.
  - Effective island frame is `canonicalPanelFrame.offsetBy(dx: spaceLockOffsetX, dy: 0)`.
  - No normal-path `spaceLockOffsetX += error`, no proportional gain, no island CG acknowledgement waiting, and no 20 Hz sample-and-hold write interval remain.
- Added display-synchronized probe tracking:
  - `SpaceLockDisplayLink` uses `CVDisplayLinkCreateWithActiveCGDisplays`.
  - The display-link callback coalesces pending updates before dispatching to the main queue, then `performProbeDrivenSpaceLockTick(reason:)` runs on the main actor.
  - Startup trace on this Mac reported `nominalFPS=120.0`; observed debug cadence stabilized near `114.0 FPS` after startup.
- Preserved hard recovery as a fallback:
  - Recovery still resets `spaceLockOffsetX = 0`, restores `canonicalPanelFrame`, calls `orderFrontRegardless()` once, restores mouse passthrough, enters a `0.15s` cooldown, and re-establishes the probe baseline.
  - Recovery now triggers for physical island offset beyond `screenWidth * 1.25`, repeated missing/offscreen probe snapshots, repeated invalid probe translations, desired probe offset beyond `screenWidth * 1.25`, and post-Space verification finding an out-of-bounds physical island frame.
  - Probe translation samples beyond `screenWidth * 2` are held first and only recover after repeated invalid samples.
- Preserved canonical visual hit testing:
  - `screenRect(for:)` and collapsed gesture local-point conversion still use `canonicalPanelFrame`, not the physically counter-shifted island frame.
  - The probe is never used for hover detection, click-through, collapsed gestures, expanded hover boundaries, or any user interaction.
- Updated pure math tests:
  - Probe raw translation.
  - Probe WindowServer coordinate offset handling.
  - Inverse feed-forward island offset.
  - Stable probe returning canonical island position.
  - Repeated probe samples not accumulating offset.
  - Transition end returning the island to canonical X.
  - Real `x=-2584` physical runaway bound.
  - Large probe anomaly held before moving the island thousands of pixels.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Overlay/SpaceTransitionCompensationMath.swift`
  - `Tests/DynamicIslandTests/SpaceTransitionCompensationMathTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test` with 118 tests and 0 failures
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1 .build/debug/DynamicIsland 2>&1 | tee /tmp/dynamicisland-11c7.log`
- Trace result:
  - Probe ordered and captured baseline: `probeCanonicalX=4`, `probeCGX=4`, `offset=0`.
  - Idle feed-forward trace showed `translationX=0`, `desiredIslandOffsetX=0`, `canonicalIslandX=246`, `physicalIslandX=246`, and `islandActualCGX=246`.
  - No `PROBE_RECOVERY`, `correctionRejected`, `physicalX=-2584`, `physicalX=-3999`, or offscreen frame entries appeared during the startup trace.
- Manual transition matrix:
  - Extremely slow three-finger Space swipe: not manually executed by Codex; requires local trackpad test.
  - Normal-speed Space swipe: not manually executed by Codex; requires local trackpad test.
  - Very fast Space swipe: not manually executed by Codex; requires local trackpad test.
  - Slow halfway drag and hold: not manually executed by Codex; requires local trackpad test.
  - Reverse/cancel halfway gesture: not manually executed by Codex; requires local trackpad test.
  - Rapid consecutive Space changes: not manually executed by Codex; requires local trackpad test.
  - Expand/collapse after switching: not manually executed by Codex; requires local UI test.
  - Hover/click-through: not manually executed by Codex; requires local UI test.
  - Probe invisibility: startup trace confirms transparent ordered probe configuration; visual confirmation requires local UI test.
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 11C.6 - Stable Sample-And-Hold Space Lock

- Fixed the proven Phase 11C.5 Space Lock runaway failure:
  - Runtime trace showed the continuous integrator physically pushed the `NSPanel` offscreen.
  - Real failed physical position reached `x=-2584`, with earlier samples around `x=-3998/-3999`.
  - The previous large-error rejection only logged `correctionRejected` and left the panel permanently stranded.
- Replaced uncontrolled per-frame accumulation with sample-and-hold correction:
  - Removed the Space Lock control path equivalent to `spaceLockOffsetX += errorX`.
  - WindowServer observation still runs at `1/60s`.
  - Physical frame corrections are independently rate-limited by `minimumWriteInterval = 0.05s`, so maximum correction cadence is 20 Hz.
  - During the write hold period, observed errors are discarded and no pending corrections are queued.
  - Each accepted sample computes an absolute target from current physical X plus current visual error, then assigns the resulting bounded offset once.
- Added hard safety bounds:
  - Total physical offset limit is `screenWidth * 1.25`.
  - Maximum single physical write step is `screenWidth * 0.75`.
  - The real failing state `canonicalX=246`, `physicalX=-2584`, `screenWidth=1352` produces `physicalOffset=-2830`, exceeding the `1690` total-offset limit and now triggers immediate recovery.
- Added guaranteed runaway recovery:
  - `recoverSpaceLockFromRunaway(reason:actualCGX:)` logs `[SpaceLock] RUNAWAY_RECOVERY`, resets `spaceLockOffsetX` to `0`, restores `canonicalPanelFrame` through the centralized physical writer, calls `orderFrontRegardless()` once, restores mouse passthrough, and enters a `0.15s` recovery cooldown.
  - Recovery now runs for:
    - nonfinite physical frame values
    - current physical offset beyond `screenWidth * 1.25`
    - desired offset beyond `screenWidth * 1.25`
    - repeated invalid/offscreen WindowServer samples after 8 samples
    - large visual error while physical offset is already out of bounds
    - persistent large visual error after 3 accepted samples
    - delayed active-Space verification finding physical offset beyond the limit
  - Active-Space verification also restores the canonical frame when CG X has settled near expected X but the physical panel still has a large residual offset.
- Replaced large-error behavior:
  - Large visual errors no longer move the panel multiple screen widths.
  - If the physical frame is still near canonical, large CG anomalies are held and rechecked instead of applied.
  - Repeated large anomalies recover safely to the canonical frame.
- Added post-Space transition recovery verification:
  - `activeSpaceDidChange` still runs one immediate `performSpaceLockTick(reason:)`.
  - It also schedules `verifySpaceLockRecovery(reason:)` after `0.15s` and `0.35s`.
  - This is a Space Lock recovery verifier, not a new visibility reassertion path.
- Preserved:
  - Canonical visual hit testing from Phase 11C.5 remains intact.
  - `screenRect(for:)` and collapsed scroll local-point conversion still use the canonical visual reference frame.
  - No changes to `NSPanel` collection behavior, window level, overlay architecture, NotchGeometryService, collapsed UI, expanded UI, Live Activities, gestures, media, timer, battery, tray, stats, or shell morph timing.
- Updated pure control-policy tests:
  - normal left-moving transform computes desired physical X
  - WindowServer catch-up does not apply a second accumulated correction
  - write hold suppresses immediate second physical writes
  - transition end computes canonical physical X
  - real `x=-2584` runaway state exceeds total bound
  - large CG anomaly near canonical exceeds visual bound but not physical bound
  - single-step write bounding
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Overlay/SpaceTransitionCompensationMath.swift`
  - `Tests/DynamicIslandTests/SpaceTransitionCompensationMathTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1 .build/debug/DynamicIsland 2>&1 | tee /tmp/dynamicisland-11c6.log`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Trace result:
  - `/tmp/dynamicisland-11c6.log` startup trace shows `[SpaceLock] watchdogStarted`, coordinate offset capture at canonical X `246`, and settled samples at expected/actual CG X `246`.
  - No `correctionRejected`, `physicalX=-2584`, `physicalX=-3999`, or offscreen frame entries appeared in the startup trace.
- Manual fullscreen transition matrix:
  - Desktop -> fullscreen Space: not manually executed by Codex; requires local UI/trackpad test.
  - fullscreen -> Desktop: not manually executed by Codex; requires local UI/trackpad test.
  - fullscreen -> fullscreen: not manually executed by Codex; requires local UI/trackpad test.
  - Cmd+Tab into fullscreen: not manually executed by Codex; requires local UI test.
  - Cmd+Tab out of fullscreen: not manually executed by Codex; requires local UI test.
  - slow half-Space drag: not manually executed by Codex; requires local trackpad test.
  - reverse/cancel Space drag: not manually executed by Codex; requires local trackpad test.
  - rapid repeated switches: not manually executed by Codex; requires local UI/trackpad test.
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 11C.5 - Continuous Horizontal Space Lock

- Replaced the Phase 11C.4 event-triggered Space compensation session with a continuous X-only space lock:
  - Removed the transition-session state machine based on monitoring deadlines, active/settled samples, saved mouse-ignore state, forced finish on active Space changes, and session generation.
  - Removed horizontal-scroll-triggered compensation startup.
  - Active app and active Space notifications now request an immediate space-lock tick, trace/reassert as before, and do not start or finish compensation sessions.
- Added canonical-vs-physical panel frame ownership:
  - `canonicalPanelFrame` is the stable intended AppKit frame used for geometry, hit testing, and local coordinate conversion.
  - `spaceLockOffsetX` is the transient horizontal physical counter-translation.
  - Physical frame application is `canonicalPanelFrame.offsetBy(dx: spaceLockOffsetX, dy: 0)`.
  - Only `applyPhysicalPanelFrame(...)` calls raw `islandPanel.setFrame(...)`; no `setFrameOrigin(...)` path remains.
- Added a continuous watchdog:
  - Runs while the overlay is shown/enabled at `1/60s` in `.common` run-loop mode.
  - Captures the stable WindowServer/AppKit X coordinate offset only after initial show and screen-parameter changes.
  - Each tick compares expected CG X against the current WindowServer CG X, applies X-only incremental correction inside a `1pt` deadzone, and rejects corrections larger than `screenWidth * 2`.
  - Y position, panel size, shell geometry, and IslandLayoutStore local coordinates are not compensated.
  - Mouse input is temporarily ignored while the active X offset is above the safety threshold, then normal passthrough is restored when settled.
- Updated hit testing and gesture coordinate conversion:
  - `screenRect(for:)` now uses the canonical visual reference frame instead of the transient physical panel frame.
  - Collapsed scroll hit-test local points subtract the canonical visual reference frame, so gestures continue to map to the visible island geometry while the physical panel is counter-translated.
- Refactored the compensation math helper to X-only public math:
  - `horizontalCorrection(expectedX:actualX:)`
  - `clampedHorizontalCorrection(...)`
  - `updatedOffset(currentOffset:correction:)`
  - `isHorizontallySettled(errorX:offsetX:threshold:)`
  - Tests cover no displacement, negative/positive X displacement, nonfinite rejection, clamping, incremental convergence, transition-end offset return to zero, and geometry signature equality.
- Preserved:
  - No changes to OverlayWindowController panel architecture, window level, collection behavior, NotchGeometryService, IslandRootView, IslandLayoutStore local surface semantics, responsive expanded layout, Live Activities UI, collapsed media/timer/battery views, gesture actions, media transport, timer, battery provider, album artwork, visualizer, tray, stats, or shell morph timing.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Overlay/SpaceTransitionCompensationMath.swift`
  - `Tests/DynamicIslandTests/SpaceTransitionCompensationMathTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - Short debug smoke launch with `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1`
  - `pkill -9 DynamicIsland`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Smoke launch result:
  - `/tmp/dynamicisland-space-lock-smoke.log` shows `[SpaceLock] watchdogStarted`, `[SpaceLock] coordinateOffsetCaptured`, and repeated settled samples at expected/actual CG X `246.0`.
- Manual fullscreen transition matrix:
  - Not manually executed by Codex; requires local UI/trackpad testing with the trace command from Phase 11C.3.
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 11C.4 - WindowServer Space-Transition Counter-Translation

- Implemented the evidence-based Space-transition compensation path from the captured WindowServer trace:
  - The trace proved AppKit still reported the overlay visible/on-active-Space while WindowServer moved the actual CG bounds horizontally offscreen.
  - Preserved the canonical panel membership configuration:
    - `.screenSaver` level
    - `.canJoinAllSpaces`
    - `.canJoinAllApplications`
    - `.stationary`
    - `.ignoresCycle`
    - borderless non-activating `IslandOverlayPanel`
  - No additional window-level or collection-behavior experiments were added.
- Added canonical WindowServer bounds capture:
  - `currentWindowServerSnapshot()` now safely parses the overlay window through `CGWindowListCopyWindowInfo(.optionIncludingWindow, windowNumber)`.
  - Captures `bounds`, `isOnscreen`, `layer`, `alpha`, `ownerName`, and `windowNumber`.
  - `canonicalWindowServerBounds` is refreshed only while not actively compensating and only from a visible, onscreen, valid-size overlay window.
  - The Phase 11C.3 diagnostic trace now reuses this single snapshot parser.
- Added public-API counter-translation:
  - Starts monitoring on active app changes and horizontal precise trackpad scroll/swipe events outside the visible island.
  - Samples WindowServer bounds at `1/60s` for up to `3.5s`.
  - Activates only when actual CG bounds diverge from canonical bounds by more than `3pt`.
  - Temporarily sets `ignoresMouseEvents = true`, stops expanded mouse containment checks, and does not alter island state.
  - Applies only AppKit panel-origin corrections through `setFrameOrigin`, without changing panel size, IslandLayoutStore coordinates, target frames, geometry, or ordering.
  - Finishes on active Space change, deadline, or settled CG bounds, then restores the canonical panel frame once and orders front once.
- Compensation math:
  - `dx = canonicalCGBounds.minX - actualCGBounds.minX`
  - `dy = actualCGBounds.minY - canonicalCGBounds.minY`
  - Example from the failing trace:
    - canonical `x=246`
    - actual `x=-175`
    - AppKit correction `dx=421`
  - Corrections are clamped to `screenSize * 1.5` and invalid/nonfinite input is rejected.
- Reduced repeated canonical geometry work:
  - Added `OverlayGeometrySignature` for collapsed size, expanded size, collapsed active-content presence, adaptive notch sizing, and hardware-notch respect.
  - `reposition(...)` now skips duplicate signatures unless forced.
  - Live activity updates now trigger geometry work only when collapsed active-content presence changes, not for every title/progress/timestamp/battery update.
  - Settings changes now only call `setVisible(...)` when `overlayEnabled` actually changes; otherwise geometry dedupe handles relevant layout settings.
  - While Space compensation is monitoring/active, canonical repositioning, reassertion, and visibility ordering are deferred so they do not fight the counter-translation.
  - Added DEBUG warning for excessive canonical frame applications.
  - Added visibility-order dedupe so repeated collapsed/expanded visibility updates skip redundant `orderFrontRegardless()`.
- Diagnostics:
  - Detailed Phase 11C.3 transition trace now runs only when `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1`.
  - Normal DEBUG logs keep monitoring start, compensation activation, throttled corrections, completion, and snapshot failures.
- Pure math tests added:
  - no displacement
  - negative and positive CG X displacement
  - downward and upward CG Y displacement
  - invalid rect rejection
  - correction clamping
  - settled-threshold logic
  - geometry signature equality
- Smoke launch observations without manual Space transition:
  - Canonical bounds captured as `(246.0, 0.0, 860.0, 286.0)` on the current machine.
  - Startup operation counts over a 3-second trace-enabled debug launch:
    - `setFrame`: `3`
    - `orderFrontRegardless`: `3`
    - `orderFrontRegardlessSkipped`: `4`
    - duplicate reposition skips: `3`
  - This is reduced from the previous diagnostic behavior where repeated live activity updates could produce many frame/order operations.
- Preserved:
  - No changes to NotchGeometryService, IslandRootView, responsive expanded layout, Live Activities UI, Shortcuts UI, collapsed preview mounting, collapsed media/timer/battery views, gesture actions, media transport, timer, battery provider, album artwork, visualizer, shell morph, or IslandLayoutStore coordinate semantics.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Overlay/SpaceTransitionCompensationMath.swift`
  - `Tests/DynamicIslandTests/SpaceTransitionCompensationMathTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - Short debug smoke launch with `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1`
- Manual fullscreen transition matrix:
  - Desktop Space -> fullscreen Space: not manually executed by Codex; requires local trackpad/UI test.
  - Fullscreen Space -> Desktop Space: not manually executed by Codex; requires local trackpad/UI test.
  - Fullscreen app A -> fullscreen app B: not manually executed by Codex; requires local trackpad/UI test.
  - Desktop app -> fullscreen app via Cmd+Tab/AltTab: not manually executed by Codex; requires local UI test.
  - Fullscreen app -> desktop app via Cmd+Tab/AltTab: not manually executed by Codex; requires local UI test.
  - Begin/cancel Space swipe: not manually executed by Codex; requires local trackpad/UI test.
- Known measurement gap:
  - Maximum observed pre-fix CG X displacement from the provided trace was `246 -> -1169`.
  - Maximum residual CGWindow displacement after correction was not measured by Codex because it requires manual fullscreen Space transitions.
  - Run with `DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS=1` and inspect `[SpaceCompensation] corrected/finished` plus `[OverlayTransitionTrace] cgBounds=...` to measure residual displacement.
- Known limitation:
  - If CG bounds remain pinned after compensation but the overlay is still visually absent, the remaining issue is compositor suppression despite corrected public WindowServer bounds.

### Phase 11C.3 - Diagnostic WindowServer Transition Trace

- Added DEBUG-only overlay transition tracing for fullscreen Space diagnostics:
  - Samples the `IslandOverlayPanel` every `0.04s` for about `2.5s`.
  - Trace is observation-only and does not reorder, reposition, reconfigure, or resize the overlay.
  - Logs AppKit state:
    - elapsed time
    - reason
    - `windowNumber`
    - `isVisible`
    - `isOnActiveSpace`
    - `occlusionState`
    - window level
    - collection behavior
    - frame
    - alpha
    - `ignoresMouseEvents`
  - Logs WindowServer state through `CGWindowListCopyWindowInfo(.optionIncludingWindow, windowNumber)`:
    - `kCGWindowIsOnscreen`
    - `kCGWindowLayer`
    - `kCGWindowAlpha`
    - `kCGWindowBounds`
    - `kCGWindowOwnerName`
    - `kCGWindowNumber`
- Starts diagnostic traces from:
  - active app changes
  - active Space changes
  - app became active
  - app resigned active
  - DEBUG-only `.swipe` / `.gesture` monitors
  - first relevant `.scrollWheel` event outside the visible island region as a fallback
- Added DEBUG-only operation logs before every overlay `orderFrontRegardless()`, `orderOut(nil)`, and `setFrame(...)` call.
- Added controlled diagnostic environment flag:
  - `DYNAMIC_ISLAND_DISABLE_PERSISTENCE_REASSERT=1`
  - When set in DEBUG, `reassertOverlayPresence(reason:)` logs a skip and returns without calling `orderFrontRegardless()`.
- Preserved:
  - No changes to window level, collection behavior, panel style mask, panel architecture, island geometry, responsive UI, gestures, live activities, mouse passthrough behavior, shell morph, media, timer, battery, tray, or stats.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
- Diagnostic run commands:
  - Normal:
    - `pkill -9 DynamicIsland`
    - `.build/debug/DynamicIsland 2>&1 | tee /tmp/dynamicisland-transition-trace.log`
    - `grep -E "OverlayTransitionTrace|OverlayWindowOperation|OverlayPersistence" /tmp/dynamicisland-transition-trace.log > /tmp/dynamicisland-transition-filtered.log`
  - Reassertion disabled:
    - `pkill -9 DynamicIsland`
    - `DYNAMIC_ISLAND_DISABLE_PERSISTENCE_REASSERT=1 .build/debug/DynamicIsland 2>&1 | tee /tmp/dynamicisland-transition-no-reassert.log`
- Notes:
  - This is diagnostic instrumentation only; no new persistence fix was attempted.
  - Manual fullscreen Space transition capture must be performed locally with the provided commands.

### Phase 11C.2 - canJoinAllApplications Fullscreen Overlay Membership

- Replaced the auxiliary fullscreen overlay role with true cross-application fullscreen membership:
  - Removed `.fullScreenAuxiliary`.
  - Removed `.auxiliary`.
  - Added `.canJoinAllApplications`.
  - Canonical overlay collection behavior is now:
    - `.canJoinAllSpaces`
    - `.canJoinAllApplications`
    - `.stationary`
    - `.ignoresCycle`
- Kept the controlled window-level variable unchanged:
  - Overlay level remains `.screenSaver`.
  - DEBUG startup log confirms `level=1000`.
- Simplified persistence reassertion for controlled testing:
  - Removed the delayed reassertion burst path from the active code.
  - App/Space/application activation notifications now perform one immediate reassertion only.
  - Reassertion reapplies the canonical panel configuration, calls `orderFrontRegardless()`, and refreshes mouse passthrough.
  - Reassertion does not alter island state, content phase, frame, geometry, collapse/expand state, or shell morph.
- Avoided unnecessary geometry rebuilds during app/Space changes:
  - Active app changes, active Space changes, app became active, and app resigned active no longer trigger any geometry repositioning.
  - Screen parameter changes and wake still reposition because those can invalidate screen/notch geometry.
- Added explicit DEBUG behavior flags:
  - `behavior.canJoinAllApplications=true`
  - `behavior.canJoinAllSpaces=true`
  - `behavior.fullScreenAuxiliary=false`
  - `behavior.auxiliary=false`
- Verified configuration search:
  - No `.transient` remains in overlay configuration.
  - No `.auxiliary` or `.fullScreenAuxiliary` remains in overlay configuration.
  - No delayed reassertion burst helper remains.
  - `orderFrontRegardless()` remains the overlay ordering path.
- Preserved:
  - No changes to NotchGeometryService, IslandRootView responsive layout, main Island tab flex layout, Live Activities layout, Shortcuts layout, collapsed preview mounting, collapsed media/timer/battery UI, gesture routing, media swipe handling, timer, battery, live activity selector, album artwork, visualizer, or shell morph.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `.build/debug/DynamicIsland`
- Debug log result:
  - `/tmp/dynamicisland-phase11c2.log` contains `[OverlayPersistence] configure level=1000 collectionBehavior=262225 behavior.canJoinAllApplications=true behavior.canJoinAllSpaces=true behavior.fullScreenAuxiliary=false behavior.auxiliary=false`.
- Fullscreen transition test matrix:
  - Normal desktop Space -> fullscreen app via three-finger swipe: not manually executed by Codex; requires local UI test.
  - Fullscreen app -> normal desktop Space via three-finger swipe: not manually executed by Codex; requires local UI test.
  - Fullscreen app A -> fullscreen app B via three-finger swipe: not manually executed by Codex; requires local UI test.
  - Normal app -> fullscreen app via Cmd+Tab: not manually executed by Codex; requires local UI test.
  - Fullscreen app -> normal app via Cmd+Tab: not manually executed by Codex; requires local UI test.
- Failure diagnosis guidance:
  - If visual disappearance remains while logs show `visible=true` and `onActiveSpace=true`, the remaining issue is likely system compositor behavior during interactive fullscreen Space animation rather than AppKit Space membership.
  - If logs show `visible=false`, investigate AppKit/window-server membership or an unexpected hide path.
- Known limitations:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 11C.1 - Fullscreen Space Overlay Persistence Fix

- Fixed the conflicting fullscreen/Mission Control collection behavior from Phase 11C:
  - Removed `.transient` because transient windows hide during Mission Control and conflict with persistent overlay behavior.
  - Canonical overlay collection behavior is now:
    - `.canJoinAllSpaces`
    - `.fullScreenAuxiliary`
    - `.stationary`
    - `.ignoresCycle`
    - `.auxiliary`
  - There is still one canonical overlay panel configuration path in `OverlayWindowController.configure(_:)`.
- Raised the persistent overlay window level for fullscreen Space transition testing:
  - Overlay level is now `.screenSaver`.
  - DEBUG startup log confirms `level=1000`.
  - Reassertion bursts remain as fallback protection only; they were not expanded or turned into polling.
- Added stronger DEBUG diagnostics:
  - Logs `isVisible`, `isOnActiveSpace`, `occlusionState`, level, collection behavior, frame, `ignoresMouseEvents`, and island state before and after each reassertion.
  - Added explicit `[OverlayPersistence] ORDERING OUT reason=overlayDisabled ...` logging around the only overlay `orderOut(nil)` path.
  - This should distinguish app-side hiding from macOS compositor/window-level suppression during fullscreen transitions.
- Verified configuration search:
  - No `.transient` remains in the overlay configuration.
  - No `.statusBar` overlay level remains.
  - `orderFrontRegardless()` remains the overlay ordering path.
  - No `makeKeyAndOrderFront(nil)` remains in `OverlayWindowController`.
- Preserved:
  - No changes to NotchGeometryService, IslandRootView responsive layout, main Island tab flex layout, Live Activities cards, Shortcuts layout, collapsed preview mounting, collapsed media/timer/battery UI, gesture routing, media swipe handling, timer, battery, live activity selector, album artwork, visualizer, or shell morph.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `.build/debug/DynamicIsland`
- Debug log result:
  - `/tmp/dynamicisland-phase11c1.log` contains `[OverlayPersistence] configure level=1000 collectionBehavior=131409`.
  - No `ORDERING OUT` lines appeared in the sampled startup log.
- Fullscreen transition test matrix:
  - Desktop app -> Desktop app: not manually executed by Codex; requires local UI test.
  - Desktop app -> fullscreen app: not manually executed by Codex; requires local UI test.
  - Fullscreen app -> Desktop app: not manually executed by Codex; requires local UI test.
  - Fullscreen app -> fullscreen app: not manually executed by Codex; requires local UI test.
  - Three-finger Desktop Space -> fullscreen Space: not manually executed by Codex; requires local trackpad/UI test.
  - Three-finger fullscreen Space -> Desktop Space: not manually executed by Codex; requires local trackpad/UI test.
  - Mission Control select another Space: not manually executed by Codex; requires local UI test.
- Known limitations:
  - If the overlay still visually disappears while logs show `visible=true` and `onActiveSpace=true`, the remaining cause is likely macOS compositor suppression during that specific fullscreen transition.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 11C - Persistent Overlay During App And Window Switching

- Improved overlay persistence during app/window/Space transitions:
  - `IslandOverlayPanel` is now created/configured as a non-activating panel.
  - Overlay panel level was changed to `.statusBar` for a stronger persistent overlay level without jumping to `.screenSaver`.
  - Collection behavior now includes `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, `.ignoresCycle`, and `.transient`.
  - Panel remains `hidesOnDeactivate = false`, `canHide = false`, transparent, shadowless, and floating.
- Added event-driven persistence reassertion:
  - Reasserts panel configuration and `orderFrontRegardless()` on active app changes, active Space changes, app became/resigned active, wake, and screen parameter changes.
  - Uses a short delayed burst at `0.05s`, `0.18s`, and `0.35s` to cover system transition windows without adding a polling timer.
  - Reassertion preserves island state, content phase, shell morph, geometry, and mouse passthrough.
- Reduced focus-stealing risk:
  - Expanded visibility now uses `orderFrontRegardless()` instead of `makeKeyAndOrderFront(nil)`.
  - Overlay remains non-activating and click-through outside the current visible island region.
- Added DEBUG event logs:
  - `[OverlayPersistence] configure level=...`
  - `[OverlayPersistence] reassert reason=...`
  - active app, active Space, app active/resign, wake, and screen parameter events.
- Preserved:
  - No changes to NotchGeometryService, collapsed geometry, compact media/timer/battery pills, collapsed preview mounting, gestures, click-through region logic, shell morphing, album flip, visualizer behavior, battery provider, timer logic, media arbitration, live activity priority, or responsive expanded UI.
- Changed files:
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `pkill -9 DynamicIsland`
  - `.build/debug/DynamicIsland`
- Debug log result:
  - `/tmp/dynamicisland-phase11c.log` contains `[OverlayPersistence] configure level=25 collectionBehavior=345`.
- Known limitations:
  - Some Mission Control/Space animations may still temporarily suppress third-party panels at the system compositor level; the app now reasserts immediately and shortly after transition events.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 11B.1.3 - True Responsive Flex-Like Island Layout

- Rebuilt the main expanded Island tab right side as a non-scrolling responsive layout:
  - Main Island tab right-side cards no longer use internal `ScrollView`.
  - Live Activities preview now uses parent-derived item sizing in a responsive 1- or 2-column grid.
  - Live Activities overflow is represented with a compact `+N` tile instead of scrolling or clipping.
  - Shortcuts preview now uses one-row parent-derived button sizing with no horizontal scroll and no second row.
  - Shortcut overflow is shown as a compact header `+N` badge.
- Retuned expanded layout metrics:
  - Added an explicit responsive scale derived from expanded width/height.
  - Right column and media column use explicit flex-like width ratios.
  - Right-column card heights are derived from available page height instead of fixed card heights.
  - Expanded content scales from user-selected expanded width/height.
- Preserved:
  - No changes to NotchGeometryService, OverlayWindowController, collapsed geometry, collapsed compact media/timer/battery views, Phase 10C collapsed preview mounting, gestures, click-through behavior, shell morphing, album flip, visualizer behavior, battery provider, timer logic, media arbitration, or live activity priority.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
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

### Phase 11B.1.2 - Right Column And One-Row Shortcuts Fix

- Rebalanced the main expanded Island tab again:
  - Main Island tab split moved closer to center with a stronger right-column width target.
  - Right-side Live Activities/Shortcuts column is wider and can claim roughly the intended right-side share before media expands.
  - Media column is explicitly constrained so it no longer dominates the page width or pushes the divider too far right.
- Fixed right-side Shortcuts wrapping/clipping:
  - Right-side Shortcuts card now uses a one-row horizontal shortcut strip instead of a two-column grid.
  - Safari, Finder, and Settings stay on one row at the intended size.
  - If more than three shortcuts exist, the same one-row strip scrolls horizontally instead of wrapping to a second row.
  - Shortcut row height is derived from the card height so buttons and the card bottom border are not clipped.
- Preserved right-column card behavior:
  - Live Activities and Shortcuts cards fill the right column width.
  - Live Activities still uses internal vertical scrolling for multiple rows.
- Preserved:
  - No changes to NotchGeometryService, OverlayWindowController, collapsed geometry, collapsed compact media/timer/battery views, Phase 10C collapsed preview mounting, gestures, click-through behavior, shell morphing, album flip, visualizer behavior, battery provider, timer logic, media arbitration, or live activity priority.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
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

### Phase 11B.1.1 - Main Island Right Column Balance Fix

- Rebalanced the main expanded Island tab:
  - Main Island tab divider moved closer to center.
  - Right-side stacked Live Activities/Shortcuts column widened from the narrow sidebar cap used in Phase 11B.1.
  - Right column now targets roughly 40% of inner width with adaptive min/max bounds.
  - Media column is constrained by the widened right column so it no longer dominates horizontal space.
- Improved right-column card fit:
  - Live Activities and Shortcuts cards fill the right column width.
  - Live Activities height remains proportional while reserving room for Shortcuts.
  - Shortcuts card keeps an internal scroll area with safe bottom padding.
  - Shortcut buttons now use fixed adaptive tile heights so buttons remain readable and are scrollable instead of clipped.
- Preserved:
  - No changes to NotchGeometryService, OverlayWindowController, collapsed geometry, collapsed compact media/timer/battery views, Phase 10C collapsed preview mounting, gestures, click-through behavior, shell morphing, album flip, visualizer behavior, battery provider, timer logic, media arbitration, or live activity priority.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Validation note:
  - `open dist/DynamicIsland.app` returned LaunchServices `-600` immediately after `pkill`; the absolute app path fallback succeeded.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 11B.1 - Responsive Expanded Island Layout Repolish

- Repolished the expanded Island tab layout:
  - Main Island tab right side changed from side-by-side Shortcuts/Live Activities columns to one stacked right column.
  - Live Activities now sits above Shortcuts.
  - Media remains on the left with the divider between media and the right stack.
- Added responsive expanded layout metrics:
  - Expanded component sizing now derives from the user-selected expanded width/height through shared inner width, inner height, page height, and compact scale values.
  - Media/right-stack widths, right-stack section heights, card spacing, timer sizing inputs, and stats sizing are derived from the current expanded container.
- Fixed Stats tab clipping:
  - Stats cards now use adaptive card heights based on available page height.
  - Stats card internals scale icon/text/chart/padding with the expanded compact scale.
  - Stats grid uses an internal vertical scroll when the configured expanded height is too small for two rows without clipping.
  - Added bottom padding inside the scroll/grid path so bottom card borders are not cut off.
- Improved expanded right-side fit:
  - Live Activities card supports a compact empty state, scaled rows, and internal scrolling.
  - Shortcuts card scales title/button/icon/text sizes and uses internal scrolling when needed.
- Preserved:
  - No changes to NotchGeometryService, OverlayWindowController, collapsed geometry, collapsed compact media/timer/battery views, Phase 10C collapsed preview mounting, gestures, click-through behavior, shell morphing, album flip, visualizer behavior, battery provider, timer logic, media arbitration, or live activity priority.
- Changed files:
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/ModuleViews.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `open /Users/makeiteasy3/Documents/DynamicIsland/dist/DynamicIsland.app`
- Validation note:
  - `open dist/DynamicIsland.app` returned LaunchServices `-600` immediately after `pkill`; retrying with the absolute app path succeeded.
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### 2026-07-12 - Phase 11A.1 Battery Live Activity Publish Repair

- Fixed Battery Live Activity eligibility for plugged-in MacBooks:
  - Battery activity now treats `kIOPSPowerSourceStateKey == kIOPSACPowerValue` as plugged in, even when `kIOPSIsChargingKey` is `false`.
  - Plugged-in but not actively charging state now publishes a Battery activity titled `Plugged In` with the current percentage.
  - Charging, full, and low-unplugged battery states still publish as eligible activities.
  - Normal unplugged battery above 20% remains ineligible and does not become a collapsed candidate.
- Added DEBUG battery diagnostics:
  - Startup log: `[BatteryActivity] started`
  - Snapshot log includes percent, power source state, plugged-in state, charging state, charged state, low state, and eligibility.
  - Publish/remove logs identify the battery activity and reason.
- Preserved:
  - Phase 10C collapsed preview stability, hover-preview mount gating, collapsed pill height, NotchGeometryService, gestures, shell morphing, click-through behavior, media/timer/file behavior, album flip, visualizer, and theme rendering were not redesigned.
- Changed files:
  - `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - `Sources/DynamicIsland/Modules/BatteryActivityProvider.swift`
  - `Sources/DynamicIsland/Modules/LiveActivityStore.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Tests/DynamicIslandTests/BatteryActivityProviderTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`
  - `chmod +x Scripts/package_app.sh`
  - `Scripts/package_app.sh`
  - `.build/debug/DynamicIsland`
- Debug verification on this machine:
  - `[BatteryActivity] started`
  - `[BatteryActivity] percent=80% source=AC Power pluggedIn=true charging=false charged=false low=false eligible=true`
  - `[BatteryActivity] publishing id=battery title=Plugged In subtitle=80%`
- Validation note:
  - Packaging still reports the existing `FileThumbnailCache` non-Sendable capture warning in `ModuleViews.swift`.

### Phase 11A - Battery Live Activity

- Added a Battery Live Activity source:
  - Added a lightweight `BatteryActivityProvider` that reads macOS power-source state through IOKit.
  - Battery activity publishes only eligible states: low battery, charging, or full.
  - Normal battery state does not become a collapsed winner or preview row.
- Added battery activity selection support:
  - Added `.battery` live activity kind and battery-specific collapsed priority sources.
  - Running Timer still beats low battery by default.
  - Low battery beats paused media and recent files by default.
  - Playing media beats charging/full battery by default.
  - Disabling `showBatteryLiveActivity` removes battery eligibility.
- Added collapsed and hover rendering:
  - Base collapsed battery mode uses the same compact two-slot side layout and base height as media/timer/file modes.
  - Base compact battery shows only a battery icon and percentage.
  - Hover preview can include battery rows alongside timer/media/file rows, but preview rows remain mounted only while hover preview is active.
  - Expanded Live Activities can show the battery card.
- Preserved:
  - Overlay panel architecture, click-through behavior, gestures, media arbitration, album flip, visualizer artwork color sync, Tray/AirDrop/files, Timer, Stats, theme rendering, shell morph timing, and Phase 10C hidden-preview invariants were not redesigned.
- Changed files:
  - `Sources/DynamicIsland/App/DynamicIslandApp.swift`
  - `Sources/DynamicIsland/Modules/BatteryActivityProvider.swift`
  - `Sources/DynamicIsland/Modules/LiveActivityStore.swift`
  - `Sources/DynamicIsland/Overlay/OverlayWindowController.swift`
  - `Sources/DynamicIsland/Views/IslandRootView.swift`
  - `Sources/DynamicIsland/Views/SettingsView.swift`
  - `Tests/DynamicIslandTests/BatteryActivityProviderTests.swift`
  - `Tests/DynamicIslandTests/CollapsedLiveActivitySelectorTests.swift`
  - `context.md`
- Validation passed:
  - `swift build`
  - `swift test`

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
