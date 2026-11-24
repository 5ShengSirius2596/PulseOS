#!/usr/bin/env bash
set -euo pipefail

# Usage: ./setup.sh com.yourname.pulseos
BUNDLE_ID="${1:-}"
if [[ -z "$BUNDLE_ID" ]]; then
  echo "请输入一个全球唯一的 Bundle ID（例如 com.sirius.pulseos），避免个人免费签名冲突："
  read -r BUNDLE_ID
fi

if [[ -z "$BUNDLE_ID" ]]; then
  echo "未输入 Bundle ID，已取消。"
  exit 1
fi

APP_GROUP="group.${BUNDLE_ID}"
echo ">> 正在将 Bundle ID 替换为: ${BUNDLE_ID}"
echo ">> 正在将 App Group 替换为: ${APP_GROUP}"

# Update all configuration and source files cleanly
python3 - "$BUNDLE_ID" "$APP_GROUP" << 'PY'
import pathlib, sys

bid, grp = sys.argv[1], sys.argv[2]
files = [
    "project.yml",
    "Shared/Engine/SharedStore.swift",
    "PulseOS_iOS/PulseOS_iOS.entitlements",
    "PulseOS_Watch/PulseOS_Watch.entitlements",
    "PulseOS_WatchWidget/PulseOS_WatchWidget.entitlements",
    "PulseOS_Watch/Info.plist",
]
for rel in files:
    p = pathlib.Path(rel)
    if p.exists():
        txt = p.read_text(encoding="utf-8")
        txt = txt.replace("group.com.personal.pulseos", grp)
        txt = txt.replace("com.personal.pulseos", bid)
        p.write_text(txt, encoding="utf-8")
print("OK: Bundle ID & App Group updated.")
PY

if ! command -v xcodegen >/dev/null 2>&1; then
  echo ">> 未检测到 xcodegen，正在尝试通过 Homebrew 安装..."
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "请先安装 Homebrew 与 xcodegen：brew install xcodegen，然后运行 xcodegen generate"
    exit 1
  fi
fi

echo ">> 正在生成 PulseOS.xcodeproj..."
xcodegen generate
echo ">> 完成！正在打开 Xcode..."
open PulseOS.xcodeproj
