#!/bin/sh
# Build Microscope.app into ./build. Pass "install" to also copy it to ~/Applications.
set -eu
cd "$(dirname "$0")"
swift build -c release
APP=build/Microscope.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Microscope "$APP/Contents/MacOS/Microscope"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
if [ "${1:-}" = "install" ]; then
    rm -rf ~/Applications/Microscope.app
    mkdir -p ~/Applications
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Microscope.app"
fi
