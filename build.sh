#!/bin/zsh
# Builds Tickle.swift into Tickle.app and installs it to /Applications
# (falls back to ~/Applications if /Applications isn't writable).
set -e
cd "$(dirname "$0")"

APP=Tickle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O Tickle.swift -o "$APP/Contents/MacOS/Tickle"

mkdir -p "$APP/Contents/Resources"
cp assets/Tickle.icns assets/MenuIcon.png assets/MenuIcon@2x.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Tickle</string>
    <key>CFBundleDisplayName</key>     <string>Tickle</string>
    <key>CFBundleIdentifier</key>      <string>com.garyrivera.tickle</string>
    <key>CFBundleExecutable</key>      <string>Tickle</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>CFBundleIconFile</key>        <string>Tickle</string>
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
