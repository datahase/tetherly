# Acceptance evidence

[Documentation home](README.md) · [Getting started](GETTING_STARTED.md) · [Development](DEVELOPMENT.md)

Builds, automated tests, and checks on real hardware are kept separate. Emulator and Simulator runs do not count as
evidence for capture, codec or network performance.

## Automated checks
| Suite | Command | Result |
|---|---|---|
| Mac and shared Swift core (XCTest) | `xcodebuild test -project apps/macos/Tetherly.xcodeproj -scheme TetherlyTests` | 33 tests pass |
| Android (JVM) | `cd apps/android && ./gradlew testDebugUnitTest` | 80 tests pass |
| Shared fixtures | `python3 -I scripts/gen-fixtures.py` | Deterministic. Its P-256 code reproduces a NIST CAVS ECDH vector. |
| Toolchain | `scripts/doctor.sh` | Pinned versions and wrapper checksums |

**What the tests cover:**
- every frame fixture, including malformed and oversized frames
- the KDF/SAS vectors, valid ECDH vectors, and invalid curve points rejected
- both pairing state machines, run against each other: duplicates, out-of-order messages, a wrong MAC, cancel at each stage, failed storage, and a MITM simulation
- connection termination over loopback: truncated frames, a stalled peer, closing inside a callback
- durable, fail-closed trust storage, exclusive temp files, and no-overwrite file publishing
- the address and QR grammar, zoom maths, trust rules and route parsing
- the session controller's races and reconnect behaviour

**Mutation checks:** removing the duplicate-confirm guard, the flush deadline, the durable-before-approve ordering, or the session generation guard each makes a test fail.

**Note on the pairing vectors:** the `vectors` fixtures test KDF and SAS arithmetic only, and their points are not on the curve. ECDH and point validation are covered by the `ecdh` and `invalidPoints` fixtures.

## Live checks on a Mac
| Check | Result |
|---|---|
| Listener on TCP 47800, Bonjour `_tetherly._tcp` | ✅ |
| TLS 1.2 refused; no client certificate refused; unknown certificate refused when pairing mode is off | ✅ (openssl probes) |
| QR link fingerprint equals SHA-256 of the presented certificate's SPKI | ✅ |
| Signing keeps privacy permission grants across rebuilds (team signature, not ad hoc) | ✅ |

## Real devices: a Mac and a physical Android 14 phone, same Wi-Fi
| Check | Result |
|---|---|
| Discovery, pairing with the same code on both screens, reconnect as paired | ✅ |
| Live desktop on the phone; the phone reconnects by itself after the host restarts | ✅ |
| Trackpad: one continuous swipe moves the pointer the whole way, in each direction | ✅ |
| Direct tap maps to the expected Mac coordinates; typing, Enter and Backspace | ✅ |
| Landscape and portrait layouts, trackpad panel, launch in light and dark themes | ✅ |
| Clipboard, files, scroll strips, physical mouse, pinch zoom, Tailscale over cellular, revoke, display change, performance baseline | ⬜ pending |

## Website redesign, 10 October 2026

- `cd apps/web && pnpm lint`: passed.
- `cd apps/web && pnpm build`: passed, including the new static `/setup` route. Production CSS contains the new feature, footer, and guide rules.
- Chromium browser acceptance: passed. Homepage and setup page have no horizontal overflow at 320, 390, 768, 1024, and 1440px. Light/dark switching, mobile navigation closing, active page state, guide jump links, support FAQ, privacy, terms, and 404 routing checked. No runtime errors or broken loaded images observed.
- Latest feature design: three static stories, three matching images, no tabs or play/pause controls. Content remains unchanged after the former timer interval. All three columns show on desktop and stack on mobile.
- Reduced-motion preference disables smooth scrolling and reduces motion durations. No automatic feature changes remain.
- Screenshots inspected and saved in `docs/evidence/web-redesign-2026-10-10/`. Design choices, exact illustration prompts, and guide source references are recorded in `docs/WEB_REDESIGN.md`.
- Local development server remains available at `http://localhost:3000`. Its stale development cache was moved to `/tmp/tetherly-next-dev-before-css-refresh-1639`; a fresh cache and browser run verified the final styles.
- The guide is documentation checked against app source and official Tailscale documentation, not new evidence of physical remote sessions. Tailscale over cellular and remaining native/device acceptance above remain pending. Public website deployment and downloadable app releases were not performed.

## Mac app installation, 10 October 2026

- `scripts/build-macos.sh`: build succeeded from the current checkout.
- Installed the signed build at `/Applications/Tetherly.app`. `codesign --verify --deep --strict` passed.
- Opened the installed app. Process path verified and listener on TCP 47800 confirmed after browser acceptance completed.
- Native UI inspection returned `Computer Use server error -10005: timeoutReached` for the exact installed app path. Menu bar presentation and permission prompts were not verified. This does not establish successful screen capture or a phone session.

## Flat 2D feature illustration update, 10 October 2026

- Replaced the three repeated phone/laptop feature scenes with distinct 2D subjects: pointer/trackpad, shortcut keys, and document/folder handoff. Updated image descriptions for accessibility. Hero and pairing artwork were outside this request.
- `pnpm lint` and `pnpm build` passed.
- Browser check passed at 1440, 390, and 320px: all three new image URLs decode successfully, images remain square, desktop has three columns, mobile has one column, and no horizontal overflow or page errors were observed.
- T3 preview semantic checks passed. Its screenshots returned a 1280x800 canvas for both requested layouts and duplicated the mobile rendering, so final visual evidence was captured with Chromium instead.
- Inspected desktop screenshot; screenshots saved as `docs/evidence/web-redesign-2026-10-10/features-2d-desktop.png` and `features-2d-mobile.png`.
- Built-in image generation mode, exact prompt set, and workspace asset paths are recorded in `docs/FEATURE_ILLUSTRATIONS_2D.md`. The local site remains running on port 3000.

## Secondary website pages and mobile footer, 10 October 2026

- Setup, Support, Privacy, Terms, 404, and the generated share image redesigned to match the homepage. Mobile footer shortened and the repeated logo/Made by DataHase row removed.
- Final `pnpm lint` and `pnpm build` passed. All 12 generated pages remain static.
- Chromium browser acceptance passed for six routes at 320, 390, 768, 1024, and 1440px, in light and dark themes (60 layout checks). One visible page heading, correct HTTP status, no horizontal overflow, no broken loaded images, and no runtime errors.
- Seven FAQ rows open with the Enter key. Mobile legal contents starts collapsed, opens with Enter, resolves every anchor, and scrolls the final section below the fixed header. Eight connection steps and three preparation items retained. Guide route anchor, mobile navigation closing, 404 recovery, reduced motion, canonical links, robots, sitemap, and PNG share image checked.
- Privacy and Terms source SHA-256 hashes match their pre-redesign values. This verifies preservation, not a legal review.
- Final footer acceptance passed at all five widths in both themes. Six direct navigation links have touch targets of at least 44px; privacy, terms, and guide links navigate correctly. Removed brand row absent. Footer height at 390px is approximately 546px.
- T3 preview snapshot failed twice with `Preview automation snapshot timed out after 15000ms.` Final screenshots and browser checks used local Chromium.
- Vercel ignore rules validated with the installed CLI's actual file collector: 51 files (731266 bytes), required website inputs included, native projects and local files excluded. Project Root Directory verified as `apps/web`. No deployment created by this acceptance pass.
- Evidence and screenshots: `docs/evidence/web-redesign-2026-10-10/secondary-pages-check.json`, `footer-check.json`, `vercel-upload-check.json`, and related PNGs. Local preview remains running on port 3000. Physical remote-app acceptance and release work remain in the earlier sections.

## Footer copyright follow-up, 10 October 2026

- Bottom footer now contains only `© 2026 Tetherly.`, centered on all screen sizes. Removed company and location/license wording from that row.
- `pnpm lint` passed. Browser checks at 390 and 1440px confirmed the exact text, one paragraph, and centered alignment.

## Community documentation, 10 October 2026

- Reworked the project README with the selected logo, a capability overview, quick build paths, and links for users and contributors. Added a documentation home and guides for first connection, local/Tailscale routes, architecture, and troubleshooting. Expanded development and contribution instructions.
- Compared setup labels, commands, toolchains, and source paths with current app code, build scripts, and CI. Corrected the protocol introduction's stale claim that no end-to-end checks had occurred; retained the independent pairing-review gate and remaining device work.
- Local links and heading anchors pass validation. All shell examples pass `bash -n` syntax checks. Exact counts and scope are recorded in [the documentation check report](evidence/community-docs-2026-10-10.json).
- This was a documentation pass. Native builds, app/device tests, website runtime checks, deployment, and release publishing were not performed. Their remaining work stays in the existing milestone and publishing records.

## QR scanner crash fix, 10 October 2026

- Confirmed the crashing signed Android APK had ML Kit registrar names in its manifest but lacked their reflected no-argument constructors. R8 removed those constructors. Added keep rules and caught synchronous scanner startup failures so manual pairing remains available.
- Built an isolated, locally signed `link.tetherly.qrprobe` release with R8 enabled. All 82 Android unit tests passed. The artifact checker fails on the original APK and passes on the fixed probe (both constructors retained). CI now checks an optimized release APK as well as the debug build.
- The probe installed and launched on the Android phone. Its UIAutomator inspection failed with exit 137, so that attempt supplies no camera-flow acceptance. The user separately reported that mobile QR scanning now works; the exact artifact was not restated. Broader user-reported device tests were not repeated.
- Hardened both iOS QR entry points with camera authorization, availability and startup errors, plus scanner cleanup on dismissal and completion. The iOS Simulator app build passed with two build jobs. Focused iOS tests passed: four test functions, nine executions, zero failures (including six invalid/expired link cases). Physical iOS camera behavior remains unverified here.
- The probe uses a separate application ID and debug signing key. The main signed Android installation was not replaced. Resource shrinking was disabled in this probe; the release owner must preserve their existing signing/shrinking configuration, add the new ProGuard file to their release rules, and run the checker and targeted QR acceptance on the final signed artifact. Nothing was published.
- Sanitized hashes, configuration and acceptance boundaries are recorded in [the QR evidence report](evidence/qr-scanner-2026-10-10.json).

## Public release reconciliation, 10 October 2026

The final upload-signed Android APK passed release lint, certificate verification and the scanner registrar check; its version/changelog was observed on the installed phone. The revised universal Mac app and DMG passed Apple notarization, stapling, signature and Gatekeeper checks. Public HTTPS downloads matched the local hashes. The published website includes corrected Google scanner disclosures. The owner reports feature testing complete and requested no repeated broad matrix. Physical iOS camera verification is deferred to a friend after release; no independent pairing/TLS review has occurred. Earlier entries above describe their own artifacts and remain historical evidence.
