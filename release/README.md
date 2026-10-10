# Local release workflow

Build on the operator's Mac. AWS stores downloads and serves them through CloudFront; no AWS build service or CI credentials are required.

## Versions and release notes

`release/version.json` is the release record. All apps remain **0.1.0** until the owner records store publication and explicitly lifts `freezeUntilStoresPublished`. Distribution revisions such as `20261010.1` are separate from the app version. Store build numbers must remain valid for each store and may need an increase for subsequent uploads even while the displayed version stays 0.1.0.

Run `npm ci --ignore-scripts`, then `npm run release:check`. `npm run release` uses the pinned release-it installation. While frozen it forces no version increment; after the freeze is lifted, conventional commit messages drive its version recommendation and changelog. The bump guard still rejects a changed version while frozen. Releases require a clean Git checkout. Git pushes, npm publishing and GitHub releases are disabled. Review the resulting local commit/tag before pushing.

`CHANGELOG.md` is the history. `npm run release:sync` updates the native version numbers, build numbers, embedded latest release notes, and the web changelog snapshot. Mac/iOS show version and changelog in their home/menu panel; Android shows them on its home screen. The full history is linked at https://www.tetherly.link/changelog.

## AWS setup

`release/infra/downloads.cloudformation.json` creates a versioned, encrypted S3 bucket with all public-access blocks enabled, CloudFront origin access control, TLS-only transport, and an origin policy scoped to that distribution's read access under `releases/`. It creates no IAM user, access key, or public-write policy. The bucket is retained on stack deletion. Object versions have no automatic deletion policy.

Create an ACM certificate for assets.tetherly.link in us-east-1 and add its DNS validation CNAME. Then run:

```
scripts/provision-downloads.sh AWS_PROFILE EXPECTED_ACCOUNT_ID CERTIFICATE_ARN
```

The script checks the account and requires an issued certificate before deploying. Add the output CloudFront hostname as the DNS-only CNAME for assets.tetherly.link. Keep the validation CNAME for renewal.

## Build, notarize and upload

1. Build the Mac universal Release app using your local Developer ID identity. Submit through Xcode Direct Distribution or a named notarytool Keychain profile. Preserve the accepted exported app and staple its ticket.
2. Run `scripts/package-macos-dmg.sh /absolute/Tetherly.app /absolute/Tetherly.dmg`. Sign the DMG with Developer ID, submit it with `xcrun notarytool submit ... --keychain-profile tetherly-notary --wait`, then staple it. The script deliberately does not read or store credentials.
3. Build Android with the four documented upload-key environment variables. Keep the keystore and password outside the repo. Run lint and `scripts/check-android-qr-registrars.sh` on the final optimized APK.
4. Stage only the DMG, ZIP and APK intended for public download. Keep the AAB for Play Console, not the download bucket.
5. Preview an explicit upload plan:

```
python3 scripts/publish-download.py --profile AWS_PROFILE --expected-account EXPECTED_ACCOUNT_ID --revision 20261010.1 --artifact macos-dmg=/absolute/Tetherly.dmg --artifact android-apk=/absolute/Tetherly.apk --android-cert-sha256 EXPECTED_PUBLIC_CERTIFICATE_SHA256
```

Public filenames are `Tetherly-VERSION.dmg`, `Tetherly-VERSION.apk` and `Tetherly-VERSION.zip`, under a version/revision path.

Add `--publish` to upload. Actual publication requires valid Mac signatures, notarization tickets and Gatekeeper checks, or the expected Android signing certificate and retained QR scanner constructors. It rejects an unexpected account, disabled versioning, public bucket configuration, path traversal, symbolic-link input and reuse of an existing path for different bytes. A partial failed upload can leave immutable files; retry the same batch or use a new revision. It never deletes objects or invalidates CloudFront caches.

6. Download each public HTTPS URL anonymously, compare SHA-256 with its manifest, and update the website links only after verification.

## Credentials and access

No AWS, Apple or Android secret belongs in Git, changelogs, manifests, command arguments or public downloads. Use your AWS profile or a short-lived role, macOS Keychain and the existing private upload keystore. A future CI job should use a narrowly scoped OIDC role, not repository-stored access keys. The public bucket policy permits downloads only through CloudFront. Deployment permissions and upload permissions should be separate for routine releases. `release/infra/uploader-policy.example.json` shows the narrower routine upload policy. Local account metadata, logs and device captures are ignored by Git. The source review is in `docs/RELEASE_SOURCE_REVIEW.md`.

No claim of an independent security audit is made. The owner authorized public release with that limitation disclosed. Guard tests cover specific release failure cases; they do not prove the entire project has no vulnerabilities.
