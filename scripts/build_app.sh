#!/usr/bin/env bash
set -euo pipefail

APP_NAME="RingoDrop"
DISPLAY_NAME="RingoDrop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> 🍎 正在编译 RingoDrop (りんご雫) 原生 SwiftUI Liquid Glass 客户端..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

swiftc -parse-as-library -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework Security \
  -framework Foundation \
  "${ROOT_DIR}/Sources/RingoDrop/RingoDropApp.swift" \
  -o "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>moe.haruka.ringodrop</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>RingoDrop りんご雫</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

chmod +x "${MACOS_DIR}/${APP_NAME}"
echo "✅ 编译完成: ${APP_BUNDLE}"

if [[ "${1:-}" != "--no-install" ]]; then
  if [[ -d "/Applications" && -w "/Applications" ]]; then
    rm -rf "/Applications/IPAGlass.app" "/Applications/${APP_NAME}.app"
    cp -R "${APP_BUNDLE}" "/Applications/${APP_NAME}.app"
    echo "✅ 已安装至 /Applications/${APP_NAME}.app (并已清理旧版 IPAGlass.app)"
    open "/Applications/${APP_NAME}.app"
  else
    open "${APP_BUNDLE}"
  fi
fi
