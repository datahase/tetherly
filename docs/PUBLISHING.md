# Publishing checklist

[Documentation home](README.md) · [Getting started](GETTING_STARTED.md) · [Development](DEVELOPMENT.md)

The owner authorized public Mac and Android direct downloads for version 0.1.0. App Store and Google Play submissions are in review. No independent security review has occurred; the public release exception is documented in [SECURITY.md](SECURITY.md). This checklist tracks preparation; a checked-in policy, website page, or CI workflow does not establish an operational mailbox, a deployed page, or a passing workflow run.

## Before any store submission
- [x] **Product name: Tetherly; domain `tetherly.link`.** Display names, Bonjour type (`_tetherly._tcp`), pairing link
      scheme (`tetherly://`) and IDs are set: `link.tetherly.host` (Mac), `link.tetherly.client` (iOS), `link.tetherly`
      (Android application ID). Store bundle IDs are permanent after the first submission.
- [ ] Rebrand the icon and menu bar assets if the mark changes.
- [ ] **Independent security review** of the pairing protocol and TLS identity handling (`docs/SECURITY.md`, release gate).
- [ ] **Full acceptance pass** on physical devices: phones and tablets, Android and iOS, Wi-Fi and Tailscale (`docs/ACCEPTANCE.md`).
- [ ] **Privacy policy** at a public URL on `tetherly.link`. Android retains Google's scanner SDK. Disclose its diagnostics and usage collection; do not claim no data is collected. The corrected policy is live at https://www.tetherly.link/privacy.
- [ ] **Support URL and contact email** on `tetherly.link`.
- [ ] **License and attribution:** `LICENSE` (Apache 2.0) and `NOTICE` (DataHase). List third-party components in the
      apps' about screens if required.
- [ ] **Versioning:** set marketing versions and build numbers, and tag the release in git.

## Mac host: direct distribution, not the Mac App Store
The Mac App Store requires App Sandbox. A sandboxed app cannot get Accessibility trust or post input events to other
apps, which the host needs to move the pointer and type. Remote-desktop hosts are therefore distributed directly:
- [ ] Release build signed with **Developer ID Application** (DataHase), with the hardened runtime.
- [ ] **Notarize** with `notarytool`, then **staple** the ticket.
- [ ] Package as a **DMG** (or a notarized ZIP), with a drag-to-Applications layout.
- [ ] **Updates:** decide on a mechanism (for example Sparkle with EdDSA-signed appcasts) or manual downloads.
- [ ] **First-run guidance** for Screen Recording, Accessibility, Local Network and the firewall prompt.
- [ ] Optional: Secure Enclave identity. It needs a Developer ID provisioning profile with `keychain-access-groups`
      (see `docs/SECURITY.md`).

## iOS and iPadOS: App Store
- [ ] DataHase **Apple Distribution** certificate and an App Store provisioning profile; App ID with the final bundle ID.
- [ ] **App Store Connect** record: name, subtitle, keywords, category (Utilities or Productivity), age rating.
- [ ] **Privacy "nutrition" labels:** data not collected.
- [ ] **Permission strings:** Local Network, Bonjour services, and Camera (for the QR scanner).
- [ ] **Export compliance:** the app uses standard encryption (TLS) only. Answer the encryption questions accordingly
      and set `ITSAppUsesNonExemptEncryption` to match.
- [ ] **Screenshots** for the required iPhone and iPad sizes, and an optional preview video.
- [ ] **Review notes:** reviewers need a Mac running the host. Provide setup steps and a demo video showing pairing and control.
- [ ] TestFlight beta before release.

## Android: Google Play
- [ ] **Release keystore** (kept secret, backed up) and **Play App Signing** enrolment; a release build type with R8.
- [ ] **Target API level** that meets Play's current requirement at submission time. This likely means installing SDK
      platform 37 and updating `compileSdk`/`targetSdk` and the AndroidX/Compose versions pinned for SDK 36.
- [ ] **Play Console listing:** short and full description, feature graphic, screenshots for phones and tablets, and the icon.
- [ ] **Data safety form:** review and disclose the Google scanner SDK's collection, purposes, sharing treatment and optionality against the final build. Content rating questionnaire.
- [ ] **Permissions declaration:** network and multicast only. No camera permission is needed, since the code scanner runs in Play services.
- [ ] Review notes or demo video (a Mac host is required), and an internal or closed testing track before production.

## Repository (open source)
- [x] `CONTRIBUTING.md` (DCO sign-off), `SECURITY.md` disclosure policy, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1),
      issue and pull request templates.
- [x] Automatic GitHub CI and Dependabot are disabled at the owner's request. Contributors and releases run the local checks in `docs/DEVELOPMENT.md`.
- [x] Repository `datahase/tetherly` published with a single initial commit for 0.1.0.
- [ ] After it is public: turn on private vulnerability reporting, branch protection on `main`, and the DCO app.
- [ ] Set up the mailboxes used publicly: `support@`, `privacy@`, `security@` and `conduct@tetherly.link`.
- [ ] Release signing secrets stay out of the repo (CI secrets or local, git-ignored config such as `Signing.local.xcconfig`).

## Public direct downloads, 10 October 2026

The signed, notarized universal Mac DMG and signed Android APK are published through assets.tetherly.link using a private, versioned S3 bucket and CloudFront. Their anonymous downloads matched the verified local SHA-256 values. The signed AAB is prepared locally; Play account declarations, app creation and submission remain pending. Physical iOS camera verification is deferred by the owner until after release. See [release workflow](../release/README.md) and [submission checklist](../release/store/google-play/submission-checklist.md). Support mailbox delivery and upload-key backup remain unverified.
