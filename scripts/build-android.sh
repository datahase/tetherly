#!/usr/bin/env bash
# Runs JVM unit tests and assembles the debug APK. Needs JDK 17+ and ANDROID_HOME (or apps/android/local.properties).
set -euo pipefail
cd "$(dirname "$0")/../apps/android"
./gradlew testDebugUnitTest assembleDebug
echo "Built: $PWD/app/build/outputs/apk/debug/app-debug.apk"
