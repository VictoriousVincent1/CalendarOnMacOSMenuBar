#!/bin/bash
# Builds a signed, notarized build/MenuCal.dmg for direct download (e.g. GitHub Releases).
#
# One-time setup (stores your notarization login in the Keychain; you type the password):
#   xcrun notarytool store-credentials MenuCal --apple-id <your Apple ID> --team-id U5482T274L
#
# Usage:
#   ./release.sh               archive, sign with Developer ID, make DMG, notarize, staple
#   ./release.sh --no-notarize same, but skip notarization (for testing the DMG)
set -euo pipefail
cd "$(dirname "$0")"

NOTARY_PROFILE=MenuCal
TEAM_ID=$(grep -m1 "DEVELOPMENT_TEAM = " MenuCal.xcodeproj/project.pbxproj | sed -E 's/.*= ([A-Z0-9]+);/\1/')
OUT=build/release
ARCHIVE=$OUT/MenuCal.xcarchive
DMG=build/MenuCal.dmg

rm -rf "$OUT" "$DMG"
mkdir -p "$OUT"

echo "==> Archiving"
xcodebuild -project MenuCal.xcodeproj -scheme MenuCal -configuration Release \
    -destination "generic/platform=macOS" -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates -quiet archive

echo "==> Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet

echo "==> Creating DMG"
mkdir -p "$OUT/dmg"
cp -R "$OUT/export/MenuCal.app" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname MenuCal -srcfolder "$OUT/dmg" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null

# Sign the DMG itself if a Developer ID certificate is in the Keychain
# (Xcode may keep it in the cloud instead; notarization still covers the app inside).
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/' || true)
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

if [[ "${1:-}" != "--no-notarize" ]]; then
    echo "==> Notarizing (usually 1-5 minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG" || true
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$OUT/export/MenuCal.app/Contents/Info.plist")
echo
echo "Done: $DMG (MenuCal $VERSION)"
echo "Upload it to a GitHub Release named v$VERSION. Keep the file name MenuCal.dmg so the README's download link works."
