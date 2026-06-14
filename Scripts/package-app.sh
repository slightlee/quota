#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Quota"
APP_DIR="$ROOT_DIR/.build/package/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"
ICONSET_DIR="$ROOT_DIR/Assets/AppIcon.iconset"
ICON_FILE="$APP_DIR/Contents/Resources/AppIcon.icns"
MENU_BAR_ICON="$ROOT_DIR/Sources/Quota/Resources/MenuBarIcon.png"
RESOURCE_BUNDLE_NAME="${APP_NAME}_$APP_NAME.bundle"

# Support both universal binary paths built with --arch and default paths.
BUILD_DIR="$ROOT_DIR/.build/apple/Products/Release"
EXECUTABLE="$BUILD_DIR/$APP_NAME"
if [[ ! -f "$EXECUTABLE" ]]; then
  BUILD_DIR="$ROOT_DIR/.build/apple/Products/release"
  EXECUTABLE="$BUILD_DIR/$APP_NAME"
fi
if [[ ! -f "$EXECUTABLE" ]]; then
  BUILD_DIR="$ROOT_DIR/.build/release"
  EXECUTABLE="$BUILD_DIR/$APP_NAME"
fi

if [[ "${SKIP_SWIFT_BUILD:-0}" != "1" ]]; then
  swift build -c release
fi

if [[ ! -f "$EXECUTABLE" ]]; then
  echo "Missing release executable: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ -d "$BUILD_DIR/$RESOURCE_BUNDLE_NAME" ]]; then
  cp -R "$BUILD_DIR/$RESOURCE_BUNDLE_NAME" "$APP_DIR/Contents/Resources/$RESOURCE_BUNDLE_NAME"
else
  echo "Missing resource bundle: $BUILD_DIR/$RESOURCE_BUNDLE_NAME" >&2
  exit 1
fi

if [[ -d "$ICONSET_DIR" ]]; then
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
else
  echo "Missing iconset directory: $ICONSET_DIR" >&2
  exit 1
fi

if [[ -f "$MENU_BAR_ICON" ]]; then
  cp "$MENU_BAR_ICON" "$APP_DIR/Contents/Resources/MenuBarIcon.png"
else
  echo "Missing menu bar icon: $MENU_BAR_ICON" >&2
  exit 1
fi

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
