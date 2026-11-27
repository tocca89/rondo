#!/bin/bash
# Builds Rondo.app (release, ad-hoc signed) in ./dist
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${TMPDIR:-/tmp}/rondo-build"
swift build -c release --scratch-path "$BUILD_DIR"
APP=dist/Rondo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/Rondo" "$APP/Contents/MacOS/Rondo"

if [ ! -f Resources/AppIcon.icns ]; then
  mkdir -p Resources
  ICONSET="$BUILD_DIR/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  swift Scripts/make_icon.swift "$BUILD_DIR/icon.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD_DIR/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$BUILD_DIR/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Rondo</string>
  <key>CFBundleDisplayName</key><string>Rondo</string>
  <key>CFBundleIdentifier</key><string>app.rondo.Rondo</string>
  <key>CFBundleExecutable</key><string>Rondo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>it</string><string>es</string><string>fr</string><string>de</string><string>pt</string></array>
  <key>NSAppleEventsUsageDescription</key><string>Rondo reads the files selected in Finder when you press ⌃⌥R.</string>
</dict></plist>
PLIST

# Localized system texts (permission prompt) + makes macOS treat the app as localized
loc() { mkdir -p "$APP/Contents/Resources/$1.lproj"; printf '"NSAppleEventsUsageDescription" = "%s";\n' "$2" > "$APP/Contents/Resources/$1.lproj/InfoPlist.strings"; }
loc en "Rondo reads the files selected in Finder when you press ⌃⌥R."
loc it "Rondo legge i file selezionati nel Finder quando premi ⌃⌥R."
loc es "Rondo lee los archivos seleccionados en el Finder cuando pulsas ⌃⌥R."
loc fr "Rondo lit les fichiers sélectionnés dans le Finder lorsque vous appuyez sur ⌃⌥R."
loc de "Rondo liest die im Finder ausgewählten Dateien, wenn du ⌃⌥R drückst."
loc pt "O Rondo lê os arquivos selecionados no Finder quando você pressiona ⌃⌥R."

codesign --force --deep --sign - "$APP"
echo "✓ Creato $APP"
