#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p build
swiftc -module-cache-path build/module-cache Library.swift Capture.swift Checks.swift -o build/checks
build/checks
swiftc -D STASH_UI_CHECK -module-cache-path build/module-cache Library.swift Capture.swift StashSymbol.swift ReadingStash.swift WindowChecks.swift -o build/window-checks
build/window-checks
