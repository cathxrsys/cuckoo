#!/bin/zsh
# Сборка и установка в ~/Applications/Cuckoo.app
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP=~/Applications/Cuckoo.app
pkill -x LimitsBar 2>/dev/null || true
rm -rf "$APP/Contents"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp assets/Cuckoo.icns "$APP/Contents/Resources/"
cp .build/release/LimitsBar "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.limitsbar</string>
  <key>CFBundleName</key><string>Cuckoo</string>
  <key>CFBundleDisplayName</key><string>Cuckoo</string>
  <key>CFBundleIconFile</key><string>Cuckoo.icns</string>
  <key>CFBundleExecutable</key><string>LimitsBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
open "$APP"
echo "OK: $APP"
