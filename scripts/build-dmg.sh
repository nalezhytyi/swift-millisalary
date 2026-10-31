#!/usr/bin/env bash
# Builds the Release app (universal: arm64 and x86_64, signed ad hoc) and
# packs it into build/Millisalary-<version>.dmg, next to a link to
# Applications to drag it onto. Prints the dmg's path last.
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Millisalary.xcodeproj -scheme Millisalary -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath build/DerivedData -quiet build

app=build/DerivedData/Build/Products/Release/Millisalary.app
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
archs="$(lipo -archs "$app/Contents/MacOS/Millisalary")"
case "$archs" in
  *arm64*x86_64* | *x86_64*arm64*) ;;
  *) echo "Expected a universal app, got: $archs" >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$app"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

dmg="build/Millisalary-${version}.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "Millisalary ${version}" -srcfolder "$staging" \
  -fs HFS+ -format UDZO -ov "$dmg"
echo "$dmg"
