"""Validate local store-preparation asset formats; does not establish store approval."""
from pathlib import Path
from PIL import Image
import hashlib
import json

root = Path(__file__).resolve().parents[1]
assets = []
errors = []
apple_sizes = {(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)}
for path in sorted(root.rglob("*.png")):
    with Image.open(path) as im:
        size, mode, fmt = im.size, im.mode, im.format
        im.verify()
    rel = path.relative_to(root).as_posix()
    if "/screenshots/" in rel:
        if rel.startswith("mac-app-store/"):
            if size not in apple_sizes:
                errors.append(f"Invalid Mac screenshot dimensions: {rel}")
        elif min(size) < 320 or max(size) > 3840 or max(size) > 2 * min(size):
            errors.append(f"Invalid Play screenshot dimensions: {rel}")
    if rel == "google-play/graphics/icon-512.png" and (size != (512, 512) or path.stat().st_size > 1024 * 1024):
        errors.append("Invalid Play icon dimensions or size")
    if rel == "google-play/graphics/feature-1024x500.png" and (size != (1024, 500) or mode != "RGB"):
        errors.append("Invalid Play feature graphic dimensions or alpha")
    assets.append({"path": rel, "dimensions": size, "mode": mode, "format": fmt,
                   "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})

text_checks = []
for rel, limit in {
    "google-play/en-US/title.txt": 30,
    "google-play/en-US/short-description.txt": 80,
    "google-play/en-US/full-description.txt": 4000,
    "mac-app-store/en-US/name.txt": 30,
    "mac-app-store/en-US/subtitle.txt": 30,
    "mac-app-store/en-US/keywords.txt": 100,
    "mac-app-store/en-US/description.txt": 4000,
}.items():
    length = len((root / rel).read_text().strip())
    text_checks.append({"path": rel, "characters": length, "limit": limit})
    if length > limit:
        errors.append(f"Text too long: {rel}")

report = {"scope": "File formats, dimensions, text lengths and hashes only; listing coverage and eligibility remain open",
          "assets": assets, "text_checks": text_checks, "errors": errors}
(root / "evidence/asset-validation.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"images": len(assets), "text_checks": len(text_checks), "errors": errors}))
raise SystemExit(bool(errors))
