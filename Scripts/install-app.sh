#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Clipboard Typer"
SOURCE_APP="$ROOT_DIR/.build/$APP_NAME.app"
DEST_DIR="${INSTALL_DIR:-/Applications}"
DEST_APP="$DEST_DIR/$APP_NAME.app"

"$ROOT_DIR/Scripts/build-app.sh"

if [ ! -d "$SOURCE_APP" ]; then
    echo "error: build did not produce $SOURCE_APP" >&2
    exit 1
fi

if [ ! -d "$DEST_DIR" ]; then
    echo "error: install dir $DEST_DIR does not exist" >&2
    exit 1
fi

# Stop any running instance so we can replace the bundle in place.
pkill -f ClipboardQueueMenuBar >/dev/null 2>&1 || true

if [ -w "$DEST_DIR" ]; then
    SUDO=""
else
    echo "note: $DEST_DIR is not writable by $(whoami); using sudo"
    SUDO="sudo"
fi

$SUDO rm -rf "$DEST_APP"
$SUDO cp -R "$SOURCE_APP" "$DEST_APP"

# Ad-hoc codesign the installed bundle so macOS sees the same code identity
# across reinstalls; otherwise the Accessibility (TCC) grant is wiped each time.
echo "note: ad-hoc codesigning $DEST_APP"
$SUDO codesign --sign - --force --deep --timestamp=none "$DEST_APP" 2>/dev/null \
    || echo "warning: ad-hoc codesign failed; Accessibility grant may not persist"

# Register with LaunchServices and ask Spotlight to index it so it shows up in
# Spotlight, Launchpad, and `open -a "Clipboard Typer"` immediately.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true
fi
mdimport "$DEST_APP" >/dev/null 2>&1 || true

echo "Installed $DEST_APP"
echo "Launch it from Spotlight (Cmd-Space -> 'Clipboard Typer') or run:"
echo "  open \"$DEST_APP\""
