#!/bin/bash
# 构建 PortHawk：编译 → 组装 .app → 临时签名
set -euo pipefail
cd "$(dirname "$0")"

APP=build/PortHawk.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "swiftc 编译中…"
swiftc -O -swift-version 5 \
    Sources/main.swift \
    Sources/Core/*.swift \
    Sources/UI/*.swift \
    -o "$APP/Contents/MacOS/PortHawk"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force -s - "$APP" 2>/dev/null || true

SIZE=$(du -sh "$APP" | cut -f1 | tr -d '\t')
echo "完成 → ${APP}（${SIZE}）"
echo "运行：open ${APP}   或直接双击"
