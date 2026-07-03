#!/bin/bash
# Assembles the .app bundle by hand (no Xcode.app / xcodebuild needed) and ad-hoc
# signs it. Reads branding from config.json — see native/README.md.
#
# Usage: native/build-app.sh   (run from repo root, or anywhere — paths are resolved
#                                relative to this script's location)

set -euo pipefail

NATIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$NATIVE_DIR/config.json"
BUILD_DIR="$NATIVE_DIR/build"
BIN_DIR="$NATIVE_DIR/.build/release"

DISPLAY_NAME=$(swift "$NATIVE_DIR/Scripts/read-config.swift" "$CONFIG" displayName)
BUNDLE_ID=$(swift "$NATIVE_DIR/Scripts/read-config.swift" "$CONFIG" bundleIdentifier)

APP_DIR="$BUILD_DIR/$DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"

echo "==> Assembling $DISPLAY_NAME.app (bundle id: $BUNDLE_ID)"

if [ ! -f "$BIN_DIR/AgentApp" ]; then
    echo "error: $BIN_DIR/AgentApp not found — run 'swift build -c release --package-path native' first" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

# Binary — renamed to the configured display name so Activity Monitor / the Dock
# (there isn't one, but menus etc.) show the branded name, not "AgentApp".
cp "$BIN_DIR/AgentApp" "$CONTENTS_DIR/MacOS/$DISPLAY_NAME"

# Info.plist — template with the two config-driven placeholders substituted.
sed -e "s/__DISPLAY_NAME__/$DISPLAY_NAME/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    "$NATIVE_DIR/Info.plist.template" > "$CONTENTS_DIR/Info.plist"

# Bundle config.json into Resources so AppConfig can load it at runtime.
cp "$CONFIG" "$CONTENTS_DIR/Resources/config.json"

# Ad-hoc sign — sufficient for local TCC grants on the dev machine. Every rebuild
# gets a fresh cdhash (no stable Developer ID here), which can cause the OS to
# re-prompt for any future TCC-gated permission (not needed by this round's
# perception surface — see native/README.md and the plan's risk section).
codesign --sign - --force --timestamp=none "$APP_DIR"

echo "==> Built $APP_DIR"
