#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Quota"
APP_DIR="$ROOT_DIR/.build/package/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"
ICONSET_DIR="$ROOT_DIR/Assets/AppIcon.iconset"
ICON_FILE="$APP_DIR/Contents/Resources/AppIcon.icns"

# 支持 universal binary 路径（--arch 构建）和默认路径
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
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ -d "$ICONSET_DIR" ]]; then
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
else
  echo "Missing iconset directory: $ICONSET_DIR" >&2
  exit 1
fi

# 搜索 SwiftPM 资源包（.bundle 或 .resources）
RESOURCE_BUNDLE="$(find "$ROOT_DIR/.build" -type d \( -name "${APP_NAME}_*.bundle" -o -name "${APP_NAME}_*.resources" \) -path "*/release/*" | head -n 1)"
if [[ -z "$RESOURCE_BUNDLE" ]]; then
  RESOURCE_BUNDLE="$(find "$ROOT_DIR/.build" -type d \( -name "${APP_NAME}_*.bundle" -o -name "${APP_NAME}_*.resources" \) | head -n 1)"
fi
if [[ -n "$RESOURCE_BUNDLE" && -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_DIR/"
else
  echo "Warning: no SwiftPM resource bundle found" >&2
fi

# 注意：不签名整个 .app，因为 SwiftPM 资源包必须留在 .app 根目录
# 签名会因 "unsealed contents" 报错。通知功能不依赖签名。

echo "$APP_DIR"
