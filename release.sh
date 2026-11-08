#!/bin/bash
# iDipper release: archive -> Developer ID export -> notarize -> staple -> DMG -> notarize -> staple
# One-time setup: xcrun notarytool store-credentials IDIPPER_NOTARY --apple-id <you@example.com> --team-id KFM4CKVPL5
set -euo pipefail; cd "$(dirname "$0")"
PROFILE="${NOTARY_PROFILE:-IDIPPER_NOTARY}"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
OUT=build/release; rm -rf "$OUT"; mkdir -p "$OUT"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
xcodebuild -project iDipper.xcodeproj -scheme iDipper -configuration Release \
  -archivePath "$OUT/iDipper.xcarchive" -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "$OUT/iDipper.xcarchive" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$OUT/export" -allowProvisioningUpdates
APP="$OUT/export/iDipper.app"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$OUT/iDipper.zip"
xcrun notarytool submit "$OUT/iDipper.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -vv "$APP"
STAGE="$OUT/dmg"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG="$OUT/iDipper-$VER.dmg"
hdiutil create -volname "iDipper" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp -s "Developer ID Application: $(security find-identity -v -p codesigning | sed -n 's/.*"Developer ID Application: \(.*\)".*/\1/p' | head -1)" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"
echo "Done: $DMG"
