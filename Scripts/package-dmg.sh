#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Quota"
PACKAGE_SCRIPT="$ROOT_DIR/Scripts/package-app.sh"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
DMG_DIR="$ROOT_DIR/.build"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT_DIR/Packaging/Info.plist")
DMG_SUFFIX="${DMG_SUFFIX:-}"
if [[ -n "$DMG_SUFFIX" ]]; then
  DMG_NAME="$APP_NAME-$VERSION-$DMG_SUFFIX.dmg"
  TMP_DMG_PATH="$DMG_DIR/$APP_NAME-$VERSION-$DMG_SUFFIX.tmp.dmg"
else
  DMG_NAME="$APP_NAME-$VERSION.dmg"
  TMP_DMG_PATH="$DMG_DIR/$APP_NAME-$VERSION.tmp.dmg"
fi
DMG_PATH="$DMG_DIR/$DMG_NAME"
MOUNT_DIR="$ROOT_DIR/.build/dmg-mount"

cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  rm -rf "$STAGING_DIR"
  rm -rf "$MOUNT_DIR"
  rm -f "$TMP_DMG_PATH"
}
trap cleanup EXIT

# ── 1. 构建 .app ──
echo "▸ Building $APP_NAME.app ..."
SKIP_SWIFT_BUILD=1 bash "$PACKAGE_SCRIPT"

APP_DIR="$ROOT_DIR/.build/package/$APP_NAME.app"
if [[ ! -d "$APP_DIR" ]]; then
  echo "Error: $APP_DIR not found" >&2
  exit 1
fi

# ── 2. 准备 DMG 内容 ──
echo "▸ Preparing DMG contents ..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

# ── 3. 计算 DMG 大小 ──
APP_SIZE_KB=$(du -sk "$STAGING_DIR" | awk '{print $1}')
DMG_SIZE_KB=$((APP_SIZE_KB + 2048))  # 额外空间

# ── 4. 生成 DMG ──
echo "▸ Creating $DMG_NAME ..."
rm -f "$DMG_PATH" "$TMP_DMG_PATH"

hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname "$APP_NAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size "${DMG_SIZE_KB}k" \
  "$TMP_DMG_PATH"

# ── 5. 设置 Finder 窗口布局 ──
echo "▸ Customizing Finder window ..."
rm -rf "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR"
hdiutil attach "$TMP_DMG_PATH" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" -quiet

if osascript <<APPLESCRIPT
tell application "Finder"
  with timeout of 30 seconds
    set dmgFolder to POSIX file "$MOUNT_DIR" as alias
    open dmgFolder
    delay 1
    set dmgWindow to Finder window 1
    set current view of dmgWindow to icon view
    try
      set toolbar visible of dmgWindow to false
    end try
    try
      set statusbar visible of dmgWindow to false
    end try
    set bounds of dmgWindow to {200, 120, 720, 440}
    set theViewOptions to the icon view options of dmgWindow
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set position of item "$APP_NAME.app" of dmgFolder to {150, 160}
    set position of item "Applications" of dmgFolder to {370, 160}
    delay 1
    close dmgWindow
  end timeout
end tell
APPLESCRIPT
then
  echo "  Finder window layout saved"
else
  echo "Warning: failed to customize Finder window; continuing with default DMG layout" >&2
fi

rm -rf "$MOUNT_DIR/.fseventsd"
sync
hdiutil detach "$MOUNT_DIR" -quiet
rm -rf "$MOUNT_DIR"

# ── 6. 转换为压缩只读 DMG ──
hdiutil convert "$TMP_DMG_PATH" \
  -format UDBZ \
  -o "$DMG_PATH" \
  -quiet

# ── 7. 清理 ──
rm -rf "$STAGING_DIR"
rm -f "$TMP_DMG_PATH"

echo ""
echo "✓ DMG created: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | awk '{print $1}')"
