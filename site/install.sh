#!/bin/bash
# PortHawk 一键安装脚本
#
# 为什么需要它：应用是临时签名（无 Developer ID 证书、未公证），
# 浏览器下载的 DMG 带 quarantine 标记，Gatekeeper 会报「已损坏」或「无法验证开发者」。
# 而 curl 下载的文件天生不带 quarantine，装完即开。
#
# 用法：curl -fsSL https://volcanicll.github.io/PortHawk/install.sh | bash
set -euo pipefail

REPO="volcanicll/PortHawk"

echo "==> 查询最新版本…"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | sed -n 's/.*"browser_download_url": *"\([^"]*arm64\.dmg\)".*/\1/p' | head -1)
if [ -z "$URL" ]; then
  echo "!! 未能获取下载地址（可能触发 GitHub API 限流）。"
  echo "!! 请到 https://github.com/$REPO/releases/latest 手动下载，"
  echo "!! 若打开时提示「已损坏」，执行：xattr -cr /Applications/PortHawk.app"
  exit 1
fi
echo "==> 下载 $URL"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fL -o "$TMP/PortHawk.dmg" "$URL"

echo "==> 挂载镜像…"
hdiutil attach "$TMP/PortHawk.dmg" -nobrowse -quiet
MOUNT=$(ls -d /Volumes/PortHawk* 2>/dev/null | head -1)
if [ -z "$MOUNT" ] || [ ! -d "$MOUNT/PortHawk.app" ]; then
  echo "!! 挂载失败，请手动打开 DMG 并把 PortHawk.app 拖入「应用程序」"
  exit 1
fi

echo "==> 安装到 /Applications/PortHawk.app …"
rm -rf /Applications/PortHawk.app
ditto "$MOUNT/PortHawk.app" /Applications/PortHawk.app
hdiutil detach "$MOUNT" -quiet

# 双保险：清掉可能存在的 quarantine（curl 下载一般没有）
xattr -cr /Applications/PortHawk.app 2>/dev/null || true

echo "==> 完成！启动：open /Applications/PortHawk.app，菜单栏见书本图标"
