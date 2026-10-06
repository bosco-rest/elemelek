#!/bin/sh
# Assembles Elemelek.app from the SwiftPM product, without Xcode.
set -eu
CONFIG=${1:-release}
cd "$(dirname "$0")/.."
swift build -c "$CONFIG" --product Elemelek
APP=.build/Elemelek.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Elemelek" "$APP/Contents/MacOS/Elemelek"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj Resources/pl.lproj Resources/Icons Resources/Faces Resources/FluentSAS Resources/Emoji "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.elemelek.mac</string>
<key>CFBundleExecutable</key><string>Elemelek</string>
<key>CFBundleName</key><string>Elemelek</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>pl</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION:-0.1}</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP"
echo "$APP"
