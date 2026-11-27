#!/bin/bash
# Packs dist/Rondo.app into a drag-to-install DMG: dist/Rondo-<version>.dmg
# Run ./build.sh first. Pass --no-layout to skip the Finder window styling (e.g. on CI without a GUI session).
set -euo pipefail
cd "$(dirname "$0")"
APP=dist/Rondo.app
[ -d "$APP" ] || { echo "Run ./build.sh first"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/Rondo-$VERSION.dmg"
WORK="${TMPDIR:-/tmp}/rondo-dmg"
VOL="Rondo"
rm -rf "$WORK" "$DMG"; mkdir -p "$WORK/stage/.background"

cp -R "$APP" "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"
swift Scripts/make_dmg_background.swift "$WORK/bg1.png" 1
swift Scripts/make_dmg_background.swift "$WORK/bg2.png" 2
tiffutil -cathidpicheck "$WORK/bg1.png" "$WORK/bg2.png" -out "$WORK/stage/.background/background.tiff" >/dev/null

# Detach a stale volume with the same name, if any
[ -d "/Volumes/$VOL" ] && hdiutil detach "/Volumes/$VOL" -force >/dev/null || true

hdiutil create -volname "$VOL" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" >/dev/null
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | grep -o '/Volumes/.*$' | head -1)

if [ "${1:-}" != "--no-layout" ]; then
  if ! osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Rondo.app" of container window to {170, 200}
    set position of item "Applications" of container window to {490, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
  then
    echo "⚠︎ Finder layout skipped (no Automation permission?). The DMG still works."
  fi
fi

# Volume icon
cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns" && SetFile -a C "$MOUNT" 2>/dev/null || true
chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$WORK"
echo "✓ Creato $DMG ($(du -h "$DMG" | cut -f1))"

# Sign for in-app updates (needs the key created by Scripts/update_keygen.swift)
rm -f "$DMG.sig"
if [ "${1:-}" != "--no-layout" ]; then
  swift Scripts/sign_update.swift "$DMG" || echo "⚠︎ DMG not signed: in-app automatic install won't accept this release."
fi
