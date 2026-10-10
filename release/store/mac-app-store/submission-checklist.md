# Mac App Store preparation

Status: inactive release route. On 10 October 2026 the owner chose signed, notarized direct Mac distribution. Nothing submitted; no server-side Tetherly Mac App Store record exists. See `../mac-direct/README.md`.

Confirmed owner: DATAHASE DEV PRIVATE LIMITED. Confirmed price: free. Bundle ID in source: `link.tetherly.host`. Prepared SKU: `tetherly-macos-host`; name: Tetherly; locale: en-US; category: Utilities; version: 0.1.0 (1); minimum system: macOS 14.

## Eligibility

Review guideline 2.4.5(i) requires Mac App Store sandboxing. Apple's current sandbox article lists assistive accessibility APIs as incompatible functionality. Tetherly checks `AXIsProcessTrusted` and injects pointer/keyboard events with `CGEvent.post(tap: .cghidEventTap)`. Its project deliberately sets `ENABLE_APP_SANDBOX=NO`. Enabling the checkbox would remove core host behavior; no compatible implementation or Apple-approved exception has been established.

References verified 2026-10-10:
- https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility
- https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
- https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Accessibility/cocoaAXIntro/cocoaAXintro.html

A Developer ID signature and notarization are for direct distribution. They do not establish Mac App Store eligibility. A separate controller or materially redesigned sandbox-compatible app is a different product scope. Do not silently remove remote control, install an unsandboxed helper, use private entitlements, or claim store compatibility.

## Account and application form

The signed-in App Store Connect organization is DATAHASE DEV PRIVATE LIMITED. The New App modal is prepared for macOS, Tetherly, English (U.S.), and SKU `tetherly-macos-host`. The Bundle ID menu has no `link.tetherly.host`; it would need registration before a record could be created. Access choice remains unset. The account displays an EU trader-status notice; status/territories require an authorized account representative's review.

Locally available signing identities: Apple Development and Datahase Developer ID Application. No Mac App Store distribution identity/profile was available in the inspected signing identities. No private keys or passwords were exported. Web sign-in does not provide a local notarization authentication profile.

## Prepared items

- Existing approved Mac icon sizes (16, 32, 128, 256 and 512 points at 1x and 2x), plus 1024px master.
- One 2880x1800 RGB composition using the user-supplied current connected UI. The local address is redacted; surrounding personal widgets are excluded. This image is a draft for the requested listing, not evidence of eligibility.
- Listing copy, review notes, and an Apple inquiry draft.
- Universal arm64/x86_64 Release build signed with Developer ID Application; hardened runtime on; no get-task-allow debugging entitlement; signature verified. All 33 Mac unit tests pass.
- An explicitly NOT-NOTARIZED review ZIP under artifacts. Nothing uploaded or released.

## Remaining submission fields if a compatible route is established

- Registered bundle ID, distribution certificate/profile, sandbox entitlements and demonstrated behavior under sandbox.
- App Privacy and required-reason API/PrivacyInfo.xcprivacy review. Source uses UserDefaults; evaluate the applicable approved reason against actual usage before adding a declaration.
- Age/content rating, export compliance (TLS plus pairing CryptoKit operations), availability and EU trader obligations, review contact, copyright, support mailbox delivery.
- Final companion Android release, host/controller setup instructions, clean demo video, independent pairing security review, and physical acceptance.
- App Store archive validation/upload through Xcode or supported tooling, build processing, review submission, manual release selection. No automatic production release.

Direct-distribution fallback, if approved: notarize the signed build with authorized credentials, staple the ticket, test Gatekeeper on a clean Mac, create the download package, choose an update mechanism, and validate initial permissions plus real phone/tablet sessions. Current artifacts have not passed those gates.
