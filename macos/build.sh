#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="dist/Show Me The Money.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun swiftc -O -swift-version 5 -module-cache-path /private/tmp/showmethemoney-swift-cache -framework Cocoa macos/IconArt.swift macos/icon-generator/main.swift -o /private/tmp/showmethemoney-icon-generator
/private/tmp/showmethemoney-icon-generator macos/assets/AppIcon.iconset
iconutil -c icns macos/assets/AppIcon.iconset -o "$bundle/Contents/Resources/AppIcon.icns"
for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" -module-cache-path /private/tmp/showmethemoney-swift-cache -framework Cocoa macos/IconArt.swift macos/Localization.swift macos/Holding.swift macos/MarketService.swift macos/AppDelegate.swift macos/main.swift -o "/private/tmp/showmethemoney-$arch"
done
xcrun lipo -create /private/tmp/showmethemoney-arm64 /private/tmp/showmethemoney-x86_64 -output "$bundle/Contents/MacOS/ShowMeTheMoney"
cp macos/Info.plist "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
echo "Built: $bundle"
