#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

build_dir=build
app="$build_dir/Wi-Fi Icon.app"
executable="$app/Contents/MacOS/WiFiIcon"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"

for architecture in arm64 x86_64; do
    xcrun swiftc -O -target "$architecture-apple-macos14.0" \
        Sources/WiFiIcon.swift -o "$build_dir/WiFiIcon-$architecture"
done

xcrun lipo -create "$build_dir/WiFiIcon-arm64" "$build_dir/WiFiIcon-x86_64" -output "$executable"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$app" "$build_dir/Wi-Fi-Icon-macOS.zip"
printf 'Built %s\n' "$build_dir/Wi-Fi-Icon-macOS.zip"
