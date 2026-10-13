#!/bin/bash
# Builds build/Flipside.app from the Swift package. Needs only the Command Line Tools.
#
# Release builds stamp the bundle:  VERSION=0.1.0 BUILD_NUMBER=7 ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Flipside.app

swift build -c release --product Flipside >&2

if [ ! -f Resources/AppIcon.icns ]; then
    swift scripts/make-icon.swift Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Flipside" "$APP/Contents/MacOS/Flipside"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature: enough to run without a developer account. Pinning the requirement to the
# bundle identifier keeps one build recognisable as the next, so the login item survives updates.
codesign --force --sign - \
    --requirements '=designated => identifier "com.flipside.Flipside"' \
    "$APP" >&2
codesign --verify --deep --strict "$APP"

echo "$APP"
