#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_NAME="DietToken"
TMP_DIR="$(mktemp -d)"
BUILD_APP="$TMP_DIR/${APP_NAME}.app"
trap 'rm -rf "$TMP_DIR"' EXIT
INSTALL_DIR="/Applications"
if [[ ! -w "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi
TARGET_APP="$INSTALL_DIR/${APP_NAME}.app"

mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources"

cat > "$BUILD_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DietToken</string>
    <key>CFBundleIdentifier</key>
    <string>com.drtomslens.diettoken</string>
    <key>CFBundleName</key>
    <string>DietToken</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LocalShuntRoot</key>
    <string>${AI_ROOT}</string>
</dict>
</plist>
EOF

mkdir -p "$HOME/.config/local-shunt"
printf '%s\n' "$AI_ROOT" > "$HOME/.config/local-shunt/root"

echo "Compiling $APP_NAME..."
clang -O2 -fobjc-arc -framework Cocoa "$SCRIPT_DIR/main.m" -o "$BUILD_APP/Contents/MacOS/$APP_NAME"

echo "Installing to $TARGET_APP..."
rm -rf "$TARGET_APP"
cp -R "$BUILD_APP" "$TARGET_APP"

echo "Installed: $TARGET_APP"
