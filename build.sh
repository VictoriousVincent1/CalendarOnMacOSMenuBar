#!/bin/bash
# Builds a universal (Apple Silicon + Intel) MenuCal.app into ./build.
#   ./build.sh            build only
#   ./build.sh --install  build and copy to /Applications
#   ./build.sh --zip      build and create build/MenuCal.zip for sharing
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MenuCal.app
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -parse-as-library \
        -target "$arch-apple-macos14.0" \
        Sources/*.swift \
        -o "build/obj/MenuCal-$arch"
done
lipo -create build/obj/MenuCal-arm64 build/obj/MenuCal-x86_64 -output "$APP/Contents/MacOS/MenuCal"
rm -rf build/obj

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"

case "${1:-}" in
    --install)
        pkill -x MenuCal || true
        rm -rf /Applications/MenuCal.app
        cp -R "$APP" /Applications/
        echo "Installed to /Applications/MenuCal.app"
        ;;
    --zip)
        rm -f build/MenuCal.zip
        ditto -c -k --keepParent "$APP" build/MenuCal.zip
        echo "Created build/MenuCal.zip"
        ;;
esac
