#!/bin/bash
# Builds a universal (Apple Silicon + Intel) MenuCal.app into ./build without opening Xcode.
# Settings (bundle ID, version) are read from MenuCal.xcodeproj so both builds match.
#   ./build.sh            build only
#   ./build.sh --install  build and copy to /Applications
#   ./build.sh --zip      build and create build/MenuCal.zip for sharing
set -euo pipefail
cd "$(dirname "$0")"

setting() {
    grep -m1 "$1 = " MenuCal.xcodeproj/project.pbxproj | sed -E "s/.*$1 = \"?([^\";]*)\"?;/\1/"
}
BUNDLE_ID=$(setting PRODUCT_BUNDLE_IDENTIFIER)
VERSION=$(setting MARKETING_VERSION)
BUILD=$(setting CURRENT_PROJECT_VERSION)
MIN_OS=$(setting MACOSX_DEPLOYMENT_TARGET)

APP=build/MenuCal.app
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -parse-as-library \
        -target "$arch-apple-macos$MIN_OS" \
        Sources/*.swift \
        -o "build/obj/MenuCal-$arch"
done
lipo -create build/obj/MenuCal-arm64 build/obj/MenuCal-x86_64 -output "$APP/Contents/MacOS/MenuCal"

sed -e "s/\$(PRODUCT_NAME)/MenuCal/" \
    -e "s/\$(EXECUTABLE_NAME)/MenuCal/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD/" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$MIN_OS/" \
    Info.plist > "$APP/Contents/Info.plist"

cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"

# The app icon needs actool, which ships with Xcode (not the Command Line Tools alone).
if xcrun --find actool >/dev/null 2>&1; then
    xcrun actool Resources/Assets.xcassets \
        --compile "$APP/Contents/Resources" \
        --platform macosx --minimum-deployment-target "$MIN_OS" \
        --app-icon AppIcon --output-partial-info-plist build/obj/assets.plist >/dev/null
    plutil -replace CFBundleIconName -string AppIcon "$APP/Contents/Info.plist"
    plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
else
    echo "Note: Xcode not found, building without the app icon."
fi
rm -rf build/obj

codesign --force --sign - --options runtime --entitlements MenuCal.entitlements "$APP"

echo "Built $APP ($BUNDLE_ID $VERSION)"

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
