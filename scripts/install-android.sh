#!/usr/bin/env bash
# Installs and launches the debug APK on the single attached device (adb devices must show it).
set -euo pipefail
cd "$(dirname "$0")/../apps/android"
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n link.tetherly/link.tetherly.MainActivity
