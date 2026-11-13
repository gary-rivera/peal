#!/bin/zsh
# Builds Peal.swift into Peal.app and installs it to /Applications
# (falls back to ~/Applications if /Applications isn't writable).
set -e
cd "$(dirname "$0")"

APP=Peal.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O Peal.swift -o "$APP/Contents/MacOS/Peal"

mkdir -p "$APP/Contents/Resources"
cp assets/Peal.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Peal</string>
    <key>CFBundleDisplayName</key>     <string>Peal</string>
    <key>CFBundleIdentifier</key>      <string>com.garyrivera.peal</string>
    <key>CFBundleExecutable</key>      <string>Peal</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>CFBundleIconFile</key>        <string>Peal</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/$APP"
cp -R "$APP" "$DEST/"
echo "Installed $DEST/$APP"
