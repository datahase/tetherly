#!/usr/bin/env bash
set -euo pipefail
# Wrap an already signed, notarized and stapled app. No credentials are stored here.
if [[ $# != 2 ]]; then
  printf '%s\n' 'Usage: package-macos-dmg.sh /absolute/Tetherly.app /absolute/output.dmg' >&2
  exit 2
fi
app=$1
output=$2
[[ "$app" = /* && "$output" = /* && "$output" = *.dmg && -d "$app" && ! -L "$app" && ! -e "$output" ]] || { printf '%s\n' 'Use an existing app and a new absolute DMG path.' >&2; exit 2; }
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
staging=$(mktemp -d -t tetherly-dmg)
trap 'rm -rf -- "$staging"' EXIT
ditto "$app" "$staging/Tetherly.app"
ln -s /Applications "$staging/Applications"
printf '%s\n' 'Drag Tetherly to Applications, then open it from Applications.' > "$staging/Install.txt"
hdiutil create -volname Tetherly -srcfolder "$staging" -format UDZO -ov "$output"
hdiutil verify "$output"
printf '%s\n' 'DMG created with notarized app. Sign and notarize the DMG itself before public distribution.'
