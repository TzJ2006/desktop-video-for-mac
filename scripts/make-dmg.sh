#!/bin/bash
# 制作发布用的 .dmg 安装包：带背景图、左侧 App 图标、右侧「应用程序」快捷方式
# 用法: ./scripts/make-dmg.sh "<App.app 路径>" [输出 dmg 路径]
set -euo pipefail

APP_PATH="${1:?用法: make-dmg.sh <App.app 路径> [输出 dmg] [卷名]}"
APP_NAME="$(basename "$APP_PATH" .app)"
# 卷名可用第 3 个参数覆盖；避免与已挂载的同名卷冲突
VOL_NAME="${3:-$APP_NAME}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BG="$REPO_DIR/statics/background.png"
ICON="$REPO_DIR/statics/icon.icns"
OUT_DMG="${2:-$REPO_DIR/releases/$APP_NAME.dmg}"

# 窗口尺寸（背景图 1920x1080 在 Retina @2x 下显示为 960x540pt）
# 窗口高度需额外预留标题栏，才能完整显示 540pt 高的背景
WIN_W=960
WIN_H=568
ICON_SIZE=128
APP_X=255; APP_Y=270      # 左侧 App 图标，对准背景左虚线框中心
LINK_X=703; LINK_Y=270    # 右侧「应用程序」，对准背景右虚线框中心

[ -d "$APP_PATH" ] || { echo "找不到 App: $APP_PATH"; exit 1; }

TMP_DIR="$(mktemp -d)"
STAGE="$TMP_DIR/stage"
mkdir -p "$STAGE/.background"
echo "==> 拷贝 App 到暂存目录"
cp -R "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cp "$BG" "$STAGE/.background/background.png"
[ -f "$ICON" ] && cp "$ICON" "$STAGE/.VolumeIcon.icns" && SetFile -a C "$STAGE" 2>/dev/null || true

RW_DMG="$TMP_DIR/rw.dmg"
echo "==> 创建可写 DMG"
hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ \
  -format UDRW -ov "$RW_DMG" >/dev/null

echo "==> 挂载并布局"
# Finder 需要卷挂在 /Volumes 下才能按名字布局；卷名应唯一以免与已挂载卷冲突
MOUNT_DIR="/Volumes/$VOL_NAME"
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse >/dev/null

osascript <<EOF
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 200 + $WIN_W, 120 + $WIN_H}
    set theView to icon view options of container window
    set arrangement of theView to not arranged
    set icon size of theView to $ICON_SIZE
    set background picture of theView to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$LINK_X, $LINK_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
# Finder / QuickLook 可能仍占用挂载点，重试几次，最后回退到 diskutil 强制卸载
DEV="$(hdiutil info | awk -v mp="$MOUNT_DIR" '$0 ~ mp {print prev} {prev=$1}' | grep -o '/dev/disk[0-9]*' | head -1)"
for i in 1 2 3 4 5; do
  hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 && break
  sleep 1
  if [ "$i" = 5 ]; then
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 \
      || diskutil unmountDisk force "$DEV" >/dev/null 2>&1
  fi
done

echo "==> 压缩为只读 DMG"
mkdir -p "$(dirname "$OUT_DMG")"
rm -f "$OUT_DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" >/dev/null

rm -rf "$TMP_DIR"
echo "==> 完成: $OUT_DMG"
du -h "$OUT_DMG"
