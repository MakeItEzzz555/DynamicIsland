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
  <key>NSAppleEventsUsageDescription</key>
  <string>DynamicIsland can read and control Spotify or Music playback when you use the media module, and send the Messages replies you write in the island to the exact conversation they answer.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>After you allow access, DynamicIsland reads your upcoming calendar events to show them in the island. It does not create, change or share events.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>After you allow access, DynamicIsland reads your upcoming calendar events to show them in the island. It does not create, change or share events.</string>
  <key>NSCameraUsageDescription</key>
  <string>DynamicIsland shows a live camera preview in the island only while you have the camera preview open. Frames are not recorded or saved.</string>
  <key>NSFocusStatusUsageDescription</key>
  <string>DynamicIsland can show a brief notch HUD when your Focus status changes.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>DynamicIsland records from your microphone only while you are using Voice Transcribe, to create a transcript.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>DynamicIsland transcribes your Voice Transcribe recordings on this Mac when on-device recognition is available. Apple's speech service is used only if you explicitly allow it.</string>
  <key>NSRemindersUsageDescription</key>
  <string>After you grant access, DynamicIsland reads your reminder lists and upcoming reminders to show them in the island, and creates or completes reminders only when you ask it to.</string>
</dict>
</plist>
PLIST

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$HELPERS_DIR/$RELAY_NAME"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$HELPERS_DIR/$CODEX_RELAY_NAME"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$HELPERS_DIR/$CLAUDE_RELAY_NAME"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS_FILE" --sign "$DEVELOPER_ID_APP" "$APP_DIR"
else
  codesign --force --sign - "$HELPERS_DIR/$RELAY_NAME"
  codesign --force --sign - "$HELPERS_DIR/$CODEX_RELAY_NAME"
  codesign --force --sign - "$HELPERS_DIR/$CLAUDE_RELAY_NAME"
  codesign --force --sign - "$APP_DIR"
fi

echo "$APP_DIR"
