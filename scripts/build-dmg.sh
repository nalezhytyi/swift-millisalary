#!/usr/bin/env bash
# Builds the Release app (universal: arm64 and x86_64, signed ad hoc),
# checks that it starts, and packs it into build/Millisalary-<version>.dmg,
# next to a link to Applications to drag it onto. Prints the dmg's path last.
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Millisalary.xcodeproj -scheme Millisalary -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath build/DerivedData -quiet build

app=build/DerivedData/Build/Products/Release/Millisalary.app
executable="$app/Contents/MacOS/Millisalary"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
archs="$(lipo -archs "$executable")"
case "$archs" in
  *arm64*x86_64* | *x86_64*arm64*) ;;
  *) echo "Expected a universal app, got: $archs" >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$app"
# An ad hoc signature has no Team ID, so the hardened runtime's library
# validation would refuse every embedded framework and the app would crash
# at launch (0.1.0 did). The start below catches that too, but this names
# the cause, and holds on a Mac whose library validation is switched off
if [ -d "$app/Contents/Frameworks" ] && codesign -dv "$app" 2>&1 | grep -q 'flags=.*runtime'; then
  echo "The app has the hardened runtime and embedded frameworks: it can't launch signed ad hoc." >&2
  exit 1
fi
# Starts the executable (this Mac's architecture), which with --smoke-test
# quits as soon as dyld has loaded it and every framework it links, before
# any of the app runs: no settings, analytics or window. Killed after 20 s
if ! perl -e 'alarm shift; exec @ARGV or die "exec $ARGV[0]: $!\n"' 20 "$executable" --smoke-test; then
  echo "The app doesn't start: dyld refused it or a framework it links (see above), or it hung." >&2
  exit 1
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

dmg="build/Millisalary-${version}.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "Millisalary ${version}" -srcfolder "$staging" \
  -fs HFS+ -format UDZO -ov "$dmg"
echo "$dmg"
