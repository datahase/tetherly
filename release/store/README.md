# Tetherly 0.1.0 release handoff

The public direct-download route is authorized by the owner. The final Mac DMG and Android APK are available through assets.tetherly.link. The rebuilt native artifacts use clean main `34cca4a` and distribution revision `20261010.6`. The website is deployed from `5507fa9`. See `../../docs/evidence/public-rebuild-2026-10-10.json` and `../../docs/evidence/mobile-store-submissions-2026-10-10.json` for verification records.

- Mac: `artifacts/final-main/Tetherly-0.1.0.dmg`. Developer ID signed, app and DMG notarized by Apple, tickets stapled, signature and Gatekeeper checks accepted.
- Android direct: `artifacts/final-main/Tetherly-0.1.0.apk`. Upload certificate verified, scanner registrar regression check passed, final release lint passed, version and changelog observed on the phone.
- Google Play upload: `artifacts/final-main/Tetherly-0.1.0.aab`. Internal testing is available and production changes were sent for review. Google quick checks completed and the changes are now in review. See `google-play/submission-checklist.md`.
- iOS: version 0.1.0 (1) is uploaded, the internal TestFlight tester is invited, and the production submission is Waiting for Review. Permission/startup fix and version/changelog build passed for the simulator. The owner deferred physical camera verification to a friend after release. No physical camera success is claimed.

Hosting uses private S3 bucket tetherly-release in ap-south-1 with versioning, encryption and public access blocked, served through CloudFront at assets.tetherly.link. Each build revision has immutable object paths and a checksum manifest. See `../README.md` for local build, signing, publication and release-it instructions. No signing passwords or AWS credentials are in these scripts.

The corrected privacy policy discloses Google scanner SDK diagnostics. The internal source review is recorded in `evidence/security-source-review.md`. No independent pairing/TLS review has occurred; the owner authorized public release with this limitation disclosed. Owner-reported feature testing was accepted without repeating a broad matrix.

Version stays 0.1.0 while the store-publication freeze is enabled. App build numbers can change independently. Upload-key backup and support-mailbox delivery need owner verification. Historical evidence files describe their own build; use metadata.json and the final verification report for current artifacts.

Apple and Google approval remain external pending steps. Both stores are configured to publish automatically after approval. Play signs its distribution with a different certificate from the direct APK; switching channels requires uninstall/reinstall and pairing again. Mac distribution uses the owner-selected direct download route, not the Mac App Store.
