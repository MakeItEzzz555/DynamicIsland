# DynamicIsland

DynamicIsland is a native macOS SwiftUI/AppKit app that turns the MacBook notch area into a Dynamic Island-style utility overlay.

It is inspired by the interaction model of Apple Dynamic Island and third-party Mac notch utilities like NotchNook, while using original UI implementation and branding. macOS does not expose a public Dynamic Island API, so this app uses a native floating `NSPanel` positioned around the notch or, on external/notchless displays, a compact floating island.

## Summary

- Platform: macOS 14.6+
- Language: Swift 6
- UI: SwiftUI hosted inside AppKit overlay windows
- Distribution target: direct download, Developer ID signing, notarization-ready packaging
- Current status: working v0.1 prototype with overlay, modules, settings, tests, and packaging script

## Features

- Borderless floating overlay aligned to the hardware notch when `NSScreen` exposes notch safe-area data.
- Floating centered island fallback for external or notchless displays.
- Collapsed, peek, expanded, drag-receiving, and pinned presentation states.
- Click-to-expand interaction model.
- Spotify-first media detection with Apple Music fallback through permission-gated Apple Events.
- Temporary file shelf with drag-in and drag-out support.
- Configurable launcher shortcuts for apps, files, and URLs.
- Menu bar controls for settings, show/hide, and quit.
- Settings window for size, auto-collapse delay, animation feel, startup behavior, and enabled modules.
- Launch-at-login toggle through `ServiceManagement`.
- Reduce Motion-aware animations.
- VoiceOver labels for core controls.
- Unit tests for notch geometry and island state transitions.

## Design Principles

- Keep compact state glanceable and narrow.
- Use expanded state for essential controls only.
- Keep content visually nested inside the rounded island shape.
- Avoid fake system UI claims; this is a user-installed macOS overlay.
- Avoid ads, promotions, and unrelated persistent notifications.
- Use a floating island on notchless displays instead of forcing a fake notch.

## Project Structure

```text
Sources/DynamicIsland
├── App
│   ├── DynamicIslandApp.swift
│   ├── LaunchAtLoginController.swift
│   ├── MenuBarController.swift
│   └── SettingsWindowController.swift
├── Geometry
│   └── NotchGeometryService.swift
├── Modules
│   ├── FileShelfStore.swift
│   ├── IslandModule.swift
│   ├── MediaController.swift
│   └── ShortcutsStore.swift
├── Overlay
│   └── OverlayWindowController.swift
├── State
│   ├── AppSettings.swift
│   └── IslandStateStore.swift
└── Views
    ├── IslandRootView.swift
    ├── ModuleViews.swift
    └── SettingsView.swift
```

## Requirements

- macOS 14.6 or newer
- Xcode 26.2 or compatible Swift 6 toolchain
- Swift Package Manager
- Optional: Apple Developer ID certificate for release signing

## Run

```sh
swift run DynamicIsland
```

The app runs as an accessory/menu bar app. Use the menu bar capsule icon to open settings or quit.

## Build

```sh
swift build
```

## Test

```sh
swift test
```

## Package as `.app`

```sh
chmod +x Scripts/package_app.sh
Scripts/package_app.sh
```

For Developer ID signing:

```sh
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" Scripts/package_app.sh
```

The script writes `dist/DynamicIsland.app`. Notarization can be run after packaging with `xcrun notarytool submit`.

## GitHub Repository Description

Native macOS SwiftUI/AppKit Dynamic Island-style notch overlay with media controls, temporary file shelf, launcher shortcuts, settings, tests, and direct-download packaging.

## Roadmap

- Calendar widget.
- Camera mirror widget.
- Better now-playing integration beyond Apple Music.
- AirDrop action from the file shelf.
- Custom theme presets.
- More robust multi-display placement controls.
- Signed and notarized release artifacts.

## Current Limitations

- macOS has no official Dynamic Island API, so the app uses an overlay window.
- Media controls currently use Apple Events for Spotify and Apple Music, so macOS may ask for automation permission the first time controls or track detection run.
- The packaged app is ad-hoc signed unless `DEVELOPER_ID_APP` is supplied to the packaging script.
- Notarization is documented but not automated in v0.1.
