# Mac direct distribution

Final artifact: `../artifacts/Tetherly-0.1.0-macOS-universal.dmg`.

Public download: https://assets.tetherly.link/releases/0.1.0/20261010.4/Tetherly-0.1.0.dmg

Version 0.1.0, build 1, universal Intel/Apple silicon, macOS 14 or later. Includes version and changelog in the menu bar panel. Signed by DATAHASE DEV PRIVATE LIMITED. App notarization A11555B6-F5F1-4631-AB54-B567A19448FF; DMG notarization 968b1dcb-692b-4e12-a966-32d6d2b5ba7c. Both accepted by Apple. Final DMG ticket, signature and Gatekeeper checks passed. See `../evidence/macos-dmg-final-checks.log` and `../evidence/cloudfront-dmg-verification.json`.

Create the container with scripts/package-macos-dmg.sh, then sign, notarize and staple it before publishing. Keychain profile tetherly-notary holds local notarization credentials. Passwords must stay out of chat, source and logs. See release/README.md for the full workflow.

The Mac App Store route is inactive because the current remote-input host does not meet its sandbox requirement. Independent security review remains pending and publicly disclosed under the owner's release decision.
