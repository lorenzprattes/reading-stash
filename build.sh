#!/bin/bash
set -eu
cd "$(dirname "$0")"
app="build/Reading Stash.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -module-cache-path build/module-cache StashSymbol.swift Artwork/MakeIcon.swift -o build/make-icon
build/make-icon build/Stash.iconset
iconutil -c icns build/Stash.iconset -o "$app/Contents/Resources/Stash.icns"
swiftc -target "$(uname -m)-apple-macos14.0" -module-cache-path build/module-cache -O Library.swift Capture.swift StashSymbol.swift ReadingStash.swift -o "$app/Contents/MacOS/ReadingStash"
cp Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
