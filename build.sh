#!/bin/zsh
# Builds Tunebar.app (release) from the Swift package, without Xcode.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="Tunebar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tunebar "$APP/Contents/MacOS/"
cp Resources/bridge.js Resources/AppIcon.icns "$APP/Contents/Resources/"

# SwiftPM records the deployment target as the SDK version. macOS uses that field to decide whether
# an app gets the current design (Liquid Glass) or the old one, so write the real SDK version in.
vtool -set-build-version macos 26.0 "$(xcrun --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/Tunebar" "$APP/Contents/MacOS/Tunebar"

# LSUIElement: a menu bar app, no Dock icon. The bundle id predates the Tunebar name; it keys the
# saved sign-in, so it stays as it is (changing it would sign everyone out).
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.local.ytmusictray</string>
    <key>CFBundleName</key><string>Tunebar</string>
    <key>CFBundleDisplayName</key><string>Tunebar</string>
    <key>CFBundleExecutable</key><string>Tunebar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
