# Google Play release status

Verified in Play Console on 10 October 2026. Datahase owns the free app, package `link.tetherly`, store name `Tetherly: Remote Desktop App`, displayed version `0.1.0`, build 1, target SDK 36 and minimum SDK 31.

- The owner accepted the developer policy/export declarations and created the app.
- The signed AAB built from clean main `34cca4a51ba8bb53190e1cff04b5113602dc38f0` is uploaded. Release lint, signing checks, the QR registrar regression check and all 82 Android unit tests passed. ReTrace mapping is attached. Play reports one nonblocking warning about missing native debug symbols.
- Internal testing release `0.1.0 (1)` is available. The owner-selected tester list is saved and enabled. Tester identities and invitations remain in the console, outside public Git.
- Production release `0.1.0 (1)` and all required listing/content changes were sent for review. Google's automatic quick checks completed, and Publishing overview confirms **Your changes are now in review**. Approval is not yet confirmed. Managed publishing is off, so approved changes publish automatically.
- Production targeting includes all 177 available countries/regions plus Rest of World.
- The English listing has the icon, feature graphic, two phone screenshots, descriptions and support links. Icon and feature graphic are labeled as created or edited using AI. The screenshots are actual app captures.
- Content rating questionnaire is complete after the owner accepted IARC terms. Result: Everyone / PEGI 3. Target audience remains 16 and older.
- App access instructions explain the separate Mac host, device pairing and local permissions. No Tetherly sign-in is required. Ads, advertising ID, government, financial and health declarations are complete.
- Data safety declares Diagnostics, App interactions and Device or other IDs as collected, required, non-ephemeral, for analytics, encrypted in transit, and not shared. No developer-provided deletion facility is claimed. See `data-safety-review.md` and the published privacy policy.
- The dedicated upload key remains outside Git, with its password in macOS Keychain. A separate secure backup still needs owner verification. Key location and recovery notes are kept privately with the owner, outside this repository.
- The native QR crash fixes and all native fixes through the build source commit are included. Later main changes are website/release documentation only.
- The notarized Mac DMG and signed direct Android APK are published under revision `20261010.6` at assets.tetherly.link. Public hashes matched the local files, S3 versioning is enabled, public bucket access is blocked and CloudFront invalidation completed.

The owner reports all features tested and declined another broad device matrix. Tablet/cellular behavior has not been independently reverified. Physical iOS camera testing was deferred by the owner. The source review is documented; an independent security review has not occurred.

The displayed version remains 0.1.0 under the owner's release freeze. Store build numbers can increase if required. Play signing SHA-256 `029ca97eb0f92f53f41d5d8e0cc8d6fafd2b6eaf4c71485e6731295532d87c8e` differs from the upload-signed direct APK (`40d062878ed03c8413c0fcf79012b574197ec04f90e7a91399af6ab8c1986f14`). Switching from the website APK to Play therefore requires uninstalling the APK first, losing local pairing/preferences, and pairing again. Updates within each channel retain their respective signing identities. Do not describe store submission as approval or public availability.
