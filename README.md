# DynamicIsland

DynamicIsland is a native macOS SwiftUI/AppKit utility that turns the MacBook notch area into an adaptive Dynamic Island-style workspace for media, Live Activities, files, shortcuts, timers, and system information.

The app uses a native borderless `NSPanel` positioned around the physical notch when macOS exposes notch geometry. On external or notchless displays, it falls back to a compact floating island instead of drawing a fake hardware notch.

## Overview

- **Platform:** macOS 14+
- **Language:** Swift 6
- **UI:** SwiftUI hosted inside AppKit
- **Architecture:** one stable transparent overlay panel with SwiftUI-driven collapsed/expanded morphing
- **Distribution:** direct-download `.app` packaging with optional Developer ID signing
- **Current status:** active working prototype with the Phase 12 overlay, notch geometry, Live Activities, media, file shelf, settings, tests, and packaging architecture completed

## Highlights

### Adaptive notch-aware island

- Aligns to the real MacBook notch using `NSScreen` geometry and safe-area information.
- Uses a single continuous notch-integrated shell shape on supported MacBook displays.
- The shell morphs between collapsed and expanded geometry with independently animated top and bottom corner radii.
- Uses the same shell shape for the background, border, and content clipping.
- Keeps a floating, non-notch variant for external and notchless displays.
- Uses content-aware collapsed activity wings so left and right Live Activity content stays clear of the physical notch without forcing every activity to use the same oversized pill width.
- Preserves normal compact height while media, timer, battery, and file activity widths adapt to their real content requirements.

### Stable native overlay architecture

- One production `NSPanel` and one `IslandRootView`.
- Fixed transparent overlay canvas; SwiftUI owns the visual morph instead of resizing or swapping windows during normal expansion.
- Native Space/fullscreen configuration using a `.statusBar` panel with `.fullScreenAuxiliary`, `.canJoinAllSpaces`, and `.ignoresCycle`.
- No legacy per-frame WindowServer compensation, probe panels, duplicate transition panels, or compositor counter-translation system.
- Click-through behavior is constrained to the visible interactive island region.
- The panel and island shell are intentionally shadowless to avoid translucent ghost-corner artifacts.

## Features

### Media

- Multi-source media detection and arbitration.
- System Now Playing integration when available.
- Spotify and Apple Music support.
- Supported browser/YouTube detection paths.
- Playing sources take priority over paused sources while preserving useful paused media state.
- Play/pause, next, and previous controls when supported by the active source.
- Seek and volume controls when the source exposes those capabilities.
- Clickable artwork that opens the active media source.
- Animated compact and expanded audio visualizer.
- Artwork-derived accent color support.
- Directional album-art flip animation for previous/next actions.
- Compact media gestures:
  - two-finger swipe left: next track
  - two-finger swipe right: previous track
  - swipe down: expand the island
  - swipe up while expanded: collapse

### Internal Live Activities

DynamicIsland includes its own macOS Live Activity model. It does **not** use Apple ActivityKit.

Current activity sources include:

- Media playback
- Timer state
- Battery / charging state
- Recent file additions

The collapsed island uses deterministic priority selection so the most relevant current activity wins. Priority can distinguish states such as running timer, playing media, paused timer, recent files, and paused media.

On physical-notch displays, active compact activities use a content-aware three-region layout:

```text
left activity content | physical notch core | right activity content
```

Each activity receives only the horizontal space it actually requires, while the real notch remains an empty central layout region.

### Expanded island

The main expanded page uses a responsive two-column layout:

- Media controls on the left.
- Live Activities on the upper-right.
- Launcher shortcuts on the lower-right.

Additional tabs provide:

- **Island** — media, Live Activities, and shortcuts
- **Tray** — AirDrop and temporary file shelf
- **Timer** — timer controls
- **Stats** — live system statistics

Tab transitions are explicitly sequenced so the outgoing page disappears before the incoming page is revealed.

### Collapsed hover preview

- Optional compact hover preview for secondary information.
- Preview content is mounted only while the preview is active, preventing hidden secondary rows from changing the normal pill geometry.
- Collapsed primary content remains governed by the active Live Activity winner.

### File shelf and AirDrop

- Temporary in-app file shelf.
- Drag files into and out of the Tray.
- File thumbnails and file actions.
- AirDrop integration from the Tray workflow.
- Thumbnail loading is isolated from the main actor where appropriate while published cache state remains main-actor safe.

### Timer

- Dedicated Timer tab.
- Running and paused timer Live Activity states.
- Compact collapsed countdown when selected by Live Activity priority.

### System stats

- Dedicated Stats tab.
- CPU, memory, GPU, network, disk, battery, and uptime presentation where available.
- Demand-driven polling: the controller takes an initial snapshot but only runs continuous polling while the real Stats page is visible.
- Polling stops when leaving Stats or collapsing the island while retaining history.

### Themes and appearance

Current shell themes:

- **Classic Black**
- **Liquid Glass** fallback rendering

The app also exposes extensive settings for modules, animation behavior, media behavior, Live Activities, shortcuts, startup behavior, sizing, and accessibility-related motion preferences.

### App integration

- Menu bar controls for opening settings, showing/hiding the overlay, and quitting.
- Launch-at-login support through `ServiceManagement`.
- App/file/URL launcher shortcuts.
- Reduce Motion-aware animation behavior.
- VoiceOver labels for core controls.

## Interaction model

### Collapsed

- Click the island to expand.
- Swipe down to expand.
- Media-only horizontal gestures control track navigation when media is the visible collapsed mode.
- Timer, battery, and file activity modes do not incorrectly route horizontal swipes to media controls.

### Expanded

- Use the top navigation to switch between Island, Tray, Timer, and Stats.
- Swipe up to collapse.
- Leaving the island collapses it through the existing grace-period containment logic.

## Architecture

The overlay intentionally separates responsibilities:

- **App layer** owns application lifecycle, settings window, launch-at-login, menu bar integration, and Live Activity source wiring.
- **Geometry layer** resolves physical-notch-aware collapsed and expanded frames.
- **Overlay layer** owns the native `NSPanel`, local coordinate conversion, hit testing, and presentation geometry.
- **State layer** owns settings, presentation state, navigation, and gesture coordination.
- **Modules layer** owns media, Live Activities, files, battery, timer, shortcuts, AirDrop, and system stats.
- **Views layer** owns the single shell, compact/expanded rendering, responsive modules, themes, and settings UI.

The core rule is that the native panel remains stable while SwiftUI performs the visible morph.

## Project Structure

```text
Sources/DynamicIsland
├── App
│   ├── AppLaunchService.swift
│   ├── DynamicIslandApp.swift
│   ├── LaunchAtLoginController.swift
│   ├── MenuBarController.swift
│   └── SettingsWindowController.swift
├── Geometry
│   └── NotchGeometryService.swift
├── Modules
│   ├── AirDropService.swift
│   ├── ArtworkAccentColorExtractor.swift
│   ├── BatteryActivityProvider.swift
│   ├── FileShelfStore.swift
│   ├── IslandModule.swift
│   ├── LiveActivityStore.swift
│   ├── MediaController.swift
│   ├── ShortcutsStore.swift
│   ├── SystemStatsController.swift
│   └── TimerController.swift
├── Overlay
│   ├── IslandLayoutStore.swift
│   └── OverlayWindowController.swift
├── State
│   ├── AppSettings.swift
│   ├── IslandGestureCoordinator.swift
│   ├── IslandNavigationStore.swift
│   └── IslandStateStore.swift
└── Views
    ├── IslandRootView.swift
    ├── IslandThemeBackground.swift
    ├── ModuleViews.swift
    └── SettingsView.swift

Tests/DynamicIslandTests
├── AppSettingsTests.swift
├── BatteryActivityProviderTests.swift
├── CollapsedLiveActivitySelectorTests.swift
├── FileShelfStoreTests.swift
├── IslandGestureCoordinatorTests.swift
├── IslandShellRadiiTests.swift
├── LiveActivityStoreTests.swift
├── NotchGeometryServiceTests.swift
└── SystemStatsFormattingTests.swift
```

`context.md` contains the detailed implementation history, phase notes, experiments, rejected approaches, validation records, and architectural decisions.

## Key implementation decisions

### Single-panel morph

The app does not swap separate collapsed and expanded windows. A single maximum-size transparent panel stays in place and the visible shell morphs inside it.

### Integrated physical-notch shell

On hardware-notch displays, the shell is one continuous shape with animated top-shoulder and bottom-corner geometry. The old decorative shoulder ellipse/blob implementation and related assets/settings were removed.

### Content-aware collapsed geometry

The physical notch is modeled as a real central layout core. Media, Timer, Battery, and File activities provide different left/right width profiles so compact width follows the visible content instead of reserving one universal worst-case width.

### Internal Live Activities

Live Activities are modeled inside the application and rendered by the overlay. They are not system ActivityKit Live Activities.

### Native Spaces behavior

The current overlay relies on native AppKit Space behavior rather than manual WindowServer motion tracking or per-frame compensation.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Swift Package Manager
- Optional Developer ID Application certificate for release signing

## Run

```sh
swift run DynamicIsland
```

The app runs as an accessory/menu bar application.

## Build

```sh
swift build
```

## Test

```sh
swift test
```

The current Phase 12 baseline passes the repository test suite with more than 100 focused tests covering geometry, settings, gestures, Live Activity selection, battery behavior, files, stats formatting, shell radii, and related state logic.

## Package as `.app`

```sh
chmod +x Scripts/package_app.sh
Scripts/package_app.sh
```

The packaged application is written to:

```text
dist/DynamicIsland.app
```

For Developer ID signing:

```sh
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" Scripts/package_app.sh
```

The packaging flow supports direct-download distribution. Notarization can be performed afterward with Apple's notarization tooling.

If macOS Finder/resource-fork metadata causes a signing error during local development, clearing extended attributes from the generated app bundle before retrying packaging may be necessary.

## Permissions and platform notes

- macOS does not expose an official Dynamic Island API; this application is a user-installed overlay.
- Some media providers and controls use Apple Events and may require Automation permission.
- Browser media detection may depend on the browser and its Apple Events / scripting configuration.
- The internal Live Activity system is application-specific and is not ActivityKit.
- External/notchless displays use a floating island instead of pretending that a hardware notch exists.
- The packaged app is ad-hoc signed unless a Developer ID identity is supplied.

## Current development status

Phase 12 is complete and provides the current stable architecture baseline:

- final content and tab transition sequencing
- native overlay cleanup and removal of legacy Space-compensation experiments
- shell-shadow removal
- integrated physical-notch shell geometry
- notch-aware expanded spacing
- content-aware collapsed activity wings aligned around the real hardware notch

The current architecture is ready for the next feature phase rather than further fundamental overlay/notch restructuring.

## Roadmap

### Next

- Calendar / upcoming-event Live Activities

### Later

- Additional native-style Live Activity providers
- Continued UI polish and accessibility refinement
- Broader media-provider capability coverage
- Multi-display edge-case testing and tuning
- Signed and notarized release automation

## Suggested GitHub Repository Description

Native macOS SwiftUI/AppKit Dynamic Island-style notch overlay with adaptive media controls, Live Activities, file shelf/AirDrop, timer, system stats, gestures, themes, and notch-aware multi-display support.
