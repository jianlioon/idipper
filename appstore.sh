#!/bin/bash
# Archive iDipper and upload it to App Store Connect.
# Xcode must already be signed in with an Apple ID that can upload for team KFM4CKVPL5.
# The prebuild bump script raises CFBundleVersion before the archive is created.
set -euo pipefail
cd "$(dirname "$0")"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
OUT=build/appstore
rm -rf "$OUT"
mkdir -p "$OUT"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
echo "Archiving iDipper $VER ($BUILD); the build number increments during archive."
xcodebuild -project iDipper.xcodeproj -scheme iDipper -configuration Release \
  -archivePath "$OUT/iDipper.xcarchive" -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "$OUT/iDipper.xcarchive" \
  -exportOptionsPlist ExportOptions-AppStore.plist -exportPath "$OUT/export" -allowProvisioningUpdates
echo "Uploaded iDipper $VER to App Store Connect."
echo "In App Store Connect, select this build for version $VER and submit it for review."
