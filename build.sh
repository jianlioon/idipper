#!/bin/bash
set -e; cd "$(dirname "$0")"
tools/bump.sh
python3 -c "exec(open('l10n/gen.py').read())"
swiftc -swift-version 5 -O -parse-as-library Sources/*.swift -o idipper-bin -target arm64-apple-macos14.0
A=/Applications/iDipper.app; rm -rf /Applications/Dipper.app "$A"; mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources"
cp idipper-bin "$A/Contents/MacOS/iDipper"; cp Info.plist "$A/Contents/"; cp AppIcon.icns "$A/Contents/Resources/"; cp -R Resources/*.lproj Resources/7zip-License.txt Resources/unrar-License.txt "$A/Contents/Resources/"; cp Vendor/7zz "$A/Contents/MacOS/7zz"; cp Vendor/unrar "$A/Contents/MacOS/unrar"; chmod +x "$A/Contents/MacOS/7zz" "$A/Contents/MacOS/unrar"
codesign -s - --force -o runtime --entitlements tools/7zz.entitlements "$A/Contents/MacOS/7zz"; codesign -s - --force -o runtime --entitlements tools/7zz.entitlements "$A/Contents/MacOS/unrar"; codesign -s - --force -o runtime --entitlements iDipper.entitlements "$A"; xattr -cr "$A"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$A"
/System/Library/CoreServices/pbs -update 2>/dev/null || true
rm -f idipper-bin
