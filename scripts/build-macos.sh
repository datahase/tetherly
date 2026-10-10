#!/usr/bin/env bash
# Builds the Mac host. Signing comes from apps/macos/Signing.xcconfig: ad hoc by default, or your team if you created
# apps/macos/Signing.local.xcconfig (see the .example file). A stable team signature keeps macOS privacy grants
# (Screen Recording, Accessibility) across rebuilds; ad hoc builds lose them each time.
set -euo pipefail
cd "$(dirname "$0")/../apps/macos"
xcodebuild -project Tetherly.xcodeproj -scheme Tetherly -configuration "${CONFIGURATION:-Debug}" \
  -derivedDataPath build/DerivedData build
echo "Built: $PWD/build/DerivedData/Build/Products/${CONFIGURATION:-Debug}/Tetherly.app"
