#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Clipboard Typer"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICON_FILE="$ROOT_DIR/.build/AppIcon.icns"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

rm -rf "$ICON_DIR" "$ICON_FILE"
swift "$ROOT_DIR/Scripts/generate-icon.swift" "$ICON_DIR"
iconutil -c icns "$ICON_DIR" -o "$ICON_FILE"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/.build/release/ClipboardQueueMenuBar" "$MACOS_DIR/ClipboardQueueMenuBar"
cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"

echo "Built $APP_DIR"
