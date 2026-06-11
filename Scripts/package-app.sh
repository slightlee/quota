#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Quota"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/.build/package/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"
ICONSET_DIR="$ROOT_DIR/Assets/AppIcon.iconset"
ICON_FILE="$APP_DIR/Contents/Resources/AppIcon.icns"
EXECUTABLE="$BUILD_DIR/$APP_NAME"

swift build -c release

if [[ ! -f "$EXECUTABLE" ]]; then
  echo "Missing release executable: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ -d "$ICONSET_DIR" ]]; then
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
else
  echo "Missing iconset directory: $ICONSET_DIR" >&2
  exit 1
fi

for resource_bundle in "$BUILD_DIR"/*.resources; do
  [[ -d "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$APP_DIR/Contents/Resources/"
done

echo "$APP_DIR"
