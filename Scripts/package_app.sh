#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DynamicIsland"
RELAY_NAME="DynamicIslandAgentRelay"
CODEX_RELAY_NAME="DynamicIslandCodexHookRelay"
CLAUDE_RELAY_NAME="DynamicIslandClaudeHookRelay"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
ENTITLEMENTS_FILE="$ROOT_DIR/Scripts/DynamicIsland.entitlements.plist"
SPOTIFY_CLIENT_ID="${DYNAMICISLAND_SPOTIFY_CLIENT_ID:-}"

if [[ -n "$SPOTIFY_CLIENT_ID" && ! "$SPOTIFY_CLIENT_ID" =~ ^[A-Za-z0-9]{8,128}$ ]]; then
  echo "DYNAMICISLAND_SPOTIFY_CLIENT_ID must be an 8-128 character alphanumeric Spotify Client ID." >&2
  exit 64
fi

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$HELPERS_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$BUILD_DIR/$RELAY_NAME" "$HELPERS_DIR/$RELAY_NAME"
cp "$BUILD_DIR/$CODEX_RELAY_NAME" "$HELPERS_DIR/$CODEX_RELAY_NAME"
cp "$BUILD_DIR/$CLAUDE_RELAY_NAME" "$HELPERS_DIR/$CLAUDE_RELAY_NAME"
chmod 755 "$HELPERS_DIR/$RELAY_NAME"
chmod 755 "$HELPERS_DIR/$CODEX_RELAY_NAME"
chmod 755 "$HELPERS_DIR/$CLAUDE_RELAY_NAME"

while IFS= read -r resource_bundle; do
  cp -R "$resource_bundle" "$RESOURCES_DIR/"
done < <(find "$ROOT_DIR/.build" -path "*/release/*.bundle" -print)

# SwiftPM dependency resources may arrive read-only (for example SwiftTerm's
# shader). Metadata cleanup needs write permission on the generated copy only.
find "$RESOURCES_DIR" -type f -exec chmod u+w {} +
xattr -cr "$APP_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.dynamicisland</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.6</string>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>com.local.dynamicisland.spotify</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>dynamicisland</string>
      </array>
    </dict>
  </array>
  <key>NSAppleEventsUsageDescription</key>
  <string>DynamicIsland can read and control Spotify or Music playback when you use the media module, and send the Messages replies you write in the island to the exact conversation they answer.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>After you allow access, DynamicIsland reads your calendar events for the days you view in the island. It does not create, change or share events.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>After you allow access, DynamicIsland reads your calendar events for the days you view in the island. It does not create, change or share events.</string>
  <key>NSCameraUsageDescription</key>
  <string>DynamicIsland shows a live camera preview in the island only while you have the camera preview open. Frames are not recorded or saved.</string>
  <key>NSFocusStatusUsageDescription</key>
  <string>DynamicIsland can show a brief notch HUD when your Focus status changes.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>DynamicIsland uses your microphone only when you explicitly start Voice Transcribe or enable microphone audio for a screen recording.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>DynamicIsland records the display, window, or area you explicitly choose when you start Screen Record. Recordings stay on this Mac unless you share them.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>DynamicIsland transcribes your Voice Transcribe recordings on this Mac when on-device recognition is available. Apple's speech service is used only if you explicitly allow it.</string>
  <key>NSRemindersUsageDescription</key>
  <string>After you grant access, DynamicIsland reads your reminder lists and upcoming reminders to show them in the island, and creates or completes reminders only when you ask it to.</string>
  <!-- Native widget-editor drags carry this private pasteboard type. It must
       be exported, or AppKit/SwiftUI drop registration never matches it and
       the editor receives no hover updates before release. -->
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>app.dynamicisland.workspace-widget</string>
      <key>UTTypeDescription</key>
      <string>DynamicIsland Workspace Widget</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

if [[ -n "$SPOTIFY_CLIENT_ID" ]]; then
  /usr/libexec/PlistBuddy -c "Add :DynamicIslandSpotifyClientID string $SPOTIFY_CLIENT_ID" "$CONTENTS_DIR/Info.plist"
fi

# Synced folders can attach resource-fork/Finder metadata while Info.plist is
# being written. Clear it again immediately before signing so package output is
# deterministic both inside and outside iCloud-backed worktrees.
xattr -cr "$APP_DIR"

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$HELPERS_DIR/$RELAY_NAME"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$HELPERS_DIR/$CODEX_RELAY_NAME"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$HELPERS_DIR/$CLAUDE_RELAY_NAME"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS_FILE" --sign "$DEVELOPER_ID_APP" "$APP_DIR"
elif [[ -n "${LOCAL_SIGN_IDENTITY:-}" ]]; then
  # Stable local identity (e.g. a self-signed "Code Signing" certificate in
  # the login keychain). Unlike ad-hoc signing, its designated requirement
  # survives rebuilds, so macOS privacy grants (Screen Recording, Microphone,
  # Camera, Calendar...) keep matching the rebuilt app.
  codesign --force --sign "$LOCAL_SIGN_IDENTITY" "$HELPERS_DIR/$RELAY_NAME"
  codesign --force --sign "$LOCAL_SIGN_IDENTITY" "$HELPERS_DIR/$CODEX_RELAY_NAME"
  codesign --force --sign "$LOCAL_SIGN_IDENTITY" "$HELPERS_DIR/$CLAUDE_RELAY_NAME"
  codesign --force --sign "$LOCAL_SIGN_IDENTITY" "$APP_DIR"
else
  # Ad-hoc: the designated requirement is the cdhash, which changes on every
  # build. Existing privacy grants then stop matching (tccd: "Failed to match
  # existing code requirement"); Screen Recording silently stays denied until
  # the entry is removed and re-added. Prefer LOCAL_SIGN_IDENTITY for daily use.
  echo "warning: ad-hoc signing; privacy permissions must be re-granted after each rebuild" >&2
  codesign --force --sign - "$HELPERS_DIR/$RELAY_NAME"
  codesign --force --sign - "$HELPERS_DIR/$CODEX_RELAY_NAME"
  codesign --force --sign - "$HELPERS_DIR/$CLAUDE_RELAY_NAME"
  codesign --force --sign - "$APP_DIR"
fi

echo "$APP_DIR"
