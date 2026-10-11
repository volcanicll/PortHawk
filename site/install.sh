#!/bin/bash
# PortHawk 一键安装脚本
#
# 为什么需要它：应用是临时签名（无 Developer ID 证书、未公证），
# 浏览器下载的 DMG 带 quarantine 标记，Gatekeeper 会报「已损坏」或「无法验证开发者」。
# 而 curl 下载的文件天生不带 quarantine，装完即开。
#
# 用法：curl -fsSL https://volcanicll.github.io/PortHawk/install.sh | bash
#
# 下载走 releases/latest/download 的固定名直链，不依赖 GitHub API（匿名 API 有每小时限流）；
# 每次发布工作流都会同时上传带版本号与固定名两份产物。
set -euo pipefail

REPO="volcanicll/PortHawk"
URL="https://github.com/$REPO/releases/latest/download/PortHawk-arm64.dmg"

echo "==> 下载最新版 $URL"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fL --retry 3 -o "$TMP/PortHawk.dmg" "$URL"

echo "==> 挂载镜像…"
# 不用 -quiet：解析本次挂载的精确卷路径。不能按 /Volumes/PortHawk* 通配——
# 用户之前挂载过的旧卷会排在前面，导致装到旧版本。
MOUNT=$(hdiutil attach "$TMP/PortHawk.dmg" -nobrowse | sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | tail -1)
if [ -z "$MOUNT" ] || [ ! -d "$MOUNT/PortHawk.app" ]; then
  echo "!! 挂载失败，请手动打开 DMG 并把 PortHawk.app 拖入「应用程序」"
  exit 1
fi
echo "==> 挂载于 $MOUNT"

echo "==> 安装到 /Applications/PortHawk.app …"
rm -rf /Applications/PortHawk.app
ditto "$MOUNT/PortHawk.app" /Applications/PortHawk.app
hdiutil detach "$MOUNT" -quiet

# 双保险：清掉可能存在的 quarantine（curl 下载一般没有）
xattr -cr /Applications/PortHawk.app 2>/dev/null || true

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  /Applications/PortHawk.app/Contents/Info.plist 2>/dev/null || echo "?")
echo "==> 完成！PortHawk $VERSION 已装入 /Applications"
echo "==> 启动：open /Applications/PortHawk.app，菜单栏见书本图标"
