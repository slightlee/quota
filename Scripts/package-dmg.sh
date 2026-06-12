#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Quota"
PACKAGE_SCRIPT="$ROOT_DIR/Scripts/package-app.sh"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
DMG_DIR="$ROOT_DIR/.build"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT_DIR/Packaging/Info.plist")
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"

# ── 1. 构建 .app ──
echo "▸ Building $APP_NAME.app ..."
bash "$PACKAGE_SCRIPT"

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
rm -f "$DMG_PATH"

hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname "$APP_NAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDBZ \
  -size "${DMG_SIZE_KB}k" \
  "$DMG_PATH"

# ── 5. 清理 ──
rm -rf "$STAGING_DIR"

echo ""
echo "✓ DMG created: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | awk '{print $1}')"
