#!/bin/bash
# Auto-increment CFBundleVersion (build number) in Info.plist
cd "$(dirname "$0")/.."; PB=/usr/libexec/PlistBuddy
N=$(( $($PB -c "Print :CFBundleVersion" Info.plist) + 1 ))
$PB -c "Set :CFBundleVersion $N" Info.plist
echo "$($PB -c 'Print :CFBundleShortVersionString' Info.plist) ($N)"
