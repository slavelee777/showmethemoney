#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="dist/Show Me The Money.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun swiftc -O -swift-version 5 -module-cache-path /private/tmp/showmethemoney-swift-cache -framework Cocoa macos/IconArt.swift macos/icon-generator/main.swift -o /private/tmp/showmethemoney-icon-generator
/private/tmp/showmethemoney-icon-generator macos/assets/AppIcon.iconset
iconutil -c icns macos/assets/AppIcon.iconset -o "$bundle/Contents/Resources/AppIcon.icns"
xcrun swiftc -O -swift-version 5 -module-cache-path /private/tmp/showmethemoney-swift-cache -framework Cocoa macos/IconArt.swift macos/Localization.swift macos/Holding.swift macos/main.swift -o "$bundle/Contents/MacOS/ShowMeTheMoney"
cp macos/Info.plist "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
echo "Built: $bundle"
