#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../../apps/android"
# Gradle reads TETHERLY_UPLOAD_STORE_FILE, TETHERLY_UPLOAD_STORE_PASSWORD,
# TETHERLY_UPLOAD_KEY_ALIAS, TETHERLY_UPLOAD_KEY_PASSWORD from the environment.
# All unset produces an explicitly unsigned preparation build. Partial config fails.
./gradlew testDebugUnitTest bundleRelease assembleRelease
printf '%s\n' 'Release outputs are under app/build/outputs. Check the signature before upload.'
