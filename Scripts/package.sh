#!/bin/zsh
# Builds the app and wraps it in dist/Tunebar-<version>.dmg: the app plus an Applications shortcut to
# drag it onto, with the app's icon on both the mounted disk and the .dmg file.
set -e
cd "$(dirname "$0")/.."

Scripts/build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Tunebar.app/Contents/Info.plist)
WORK=$(mktemp -d)
trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null; rm -rf "$WORK"' EXIT

# The disk's contents, and its icon (Finder uses .VolumeIcon.icns once the volume is flagged
# as having a custom icon).
mkdir "$WORK/stage"
cp -R Tunebar.app "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"
cp Resources/AppIcon.icns "$WORK/stage/.VolumeIcon.icns"

# Build it writable, flag the custom icon, then compress it.
hdiutil create -volname "Tunebar" -srcfolder "$WORK/stage" -format UDRW -ov "$WORK/rw.dmg" >/dev/null
mkdir "$WORK/mnt"
hdiutil attach "$WORK/rw.dmg" -mountpoint "$WORK/mnt" -nobrowse -quiet
xcrun SetFile -a C "$WORK/mnt"
hdiutil detach "$WORK/mnt" -quiet

mkdir -p dist
DMG="dist/Tunebar-$VERSION.dmg"
rm -f "$DMG"
hdiutil convert "$WORK/rw.dmg" -format UDZO -o "$DMG" >/dev/null

# The .dmg file's own icon in Finder. It's file metadata: AirDrop and zip keep it, some uploads drop it.
osascript -l JavaScript -e '
  ObjC.import("AppKit");
  function run(argv) {
    const icon = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
    $.NSWorkspace.sharedWorkspace.setIconForFileOptions(icon, argv[1], 0);
  }' "$PWD/Resources/AppIcon.icns" "$PWD/$DMG" >/dev/null

echo "Packaged $DMG"
