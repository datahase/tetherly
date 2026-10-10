#!/usr/bin/env bash
# Check the reflection entry points required by ML Kit in a packaged APK.
set -euo pipefail
apk="${1:?Usage: scripts/check-android-qr-registrars.sh path/to/app.apk}"
analyzer="${APKANALYZER:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/cmdline-tools/latest/bin/apkanalyzer}"
if [[ ! -x "$analyzer" ]]; then
  echo "Set APKANALYZER to the Android SDK apkanalyzer executable." >&2
  exit 1
fi
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
"$analyzer" manifest print "$apk" > "$check_dir/manifest.xml"
"$analyzer" dex packages --defined-only "$apk" > "$check_dir/classes.txt"
python3 - "$check_dir" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

folder = Path(sys.argv[1])
manifest = ET.parse(folder / "manifest.xml")
android_name = "{http://schemas.android.com/apk/res/android}name"
prefix = "com.google.firebase.components:"
registrars = [
    node.attrib[android_name][len(prefix):]
    for node in manifest.findall(".//meta-data")
    if node.attrib.get(android_name, "").startswith(prefix + "com.google.mlkit.")
]
if not registrars:
    sys.exit("FAIL: no ML Kit component registrars in the APK manifest")
classes = (folder / "classes.txt").read_text()
missing = [name for name in registrars if f"{name} <init>()" not in classes]
if missing:
    sys.exit("FAIL: missing reflected constructors: " + ", ".join(missing))
print(f"PASS: {len(registrars)} ML Kit registrar constructors retained")
PY
