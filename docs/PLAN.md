# Tetherly: plan and status

[Documentation home](README.md) · [Getting started](GETTING_STARTED.md) · [Development](DEVELOPMENT.md)

Tetherly lets a phone or tablet view and control the existing desktop of a Mac: its real apps and session, not a
separate virtual desktop. It works on the same Wi-Fi, and away from home through a separately installed Tailscale.

**Platforms:** a macOS menu bar host (Swift), an Android client (Kotlin), and an iOS/iPadOS client (Swift, in progress).

**In scope:**
- screen viewing
- pointer, clicks, scrolling and dragging
- keyboard and text input
- explicit clipboard transfer in both directions
- selected-file transfer in both directions
- pairing, revocation and reconnect

**Out of scope:** Windows and Linux hosts, folder sync, remote filesystem browsing, resumable transfers, relay servers
and hosted accounts.

Status key: ✅ done and verified on real hardware · 🟡 implemented, partly verified · ⬜ not started · ⛔ release gate

## Toolchain
| Item | Choice |
|---|---|
| Mac host | macOS 14+, Swift 6 (strict concurrency), SwiftUI `MenuBarExtra`, ScreenCaptureKit, VideoToolbox, Network.framework |
| Android client | minSdk 31 (Android 12), compile/target SDK 36, Kotlin, Jetpack Compose (BOM 2026.06.01), AGP 9.4, Gradle 9.8 wrapper with a pinned SHA-256 |
| iOS client | iOS 17+, iPhone and iPad, SwiftUI, shares the Mac's protocol core |
| Build tools | Xcode 27, JDK 17+, Android SDK platform 36 |
| Signing | Mac: ad hoc by default; your own team through `apps/macos/Signing.local.xcconfig` (git-ignored). Android: debug keystore for development builds. |

## Milestones
### 1. Scaffold and onboarding ✅
Both native projects build. The Mac app detects Screen Recording and Accessibility permissions and guides you through
granting them. The Android app lists Macs, accepts manual addresses and shows connection status.

### 2. Authenticated screen viewing 🟡
- ✅ Mutual TLS 1.3 with pinned P-256 identities. Unknown or unpaired peers are rejected (checked with openssl probes).
- ✅ Commitment-based pairing code (SAS) on both screens, approved on the Mac. QR pairing link.
- ✅ ScreenCaptureKit → H.264 → phone decoder; the live desktop shows on a physical phone. Frame rate is the lower of the phone's and the Mac's display maximums.
- ✅ Bonjour discovery; Tailscale routes learned from the Mac and merged under one paired Mac.
- 🟡 Not yet measured: long-session memory, a display resolution change, recovery under packet loss.
- ⛔ Independent security review of the pairing protocol.

### 3. Mouse and keyboard 🟡
- ✅ Trackpad and direct-touch modes, tap, double-click, right-click, drag, two-finger scroll, pinch zoom of the local view, text entry, special keys and shortcuts.
- ✅ Trackpad panel with scroll strips and click buttons in the spare screen space; physical mouse capture on Android.
- 🟡 Needs a full pass: Unicode across keyboard layouts, no stuck input after interruption, physical mouse on more devices.

### 4. Clipboard and recovery 🟡
Explicit send and get in both directions, with size limits. Auto-reconnect with backoff has been seen working on a phone. Wi-Fi loss and permission loss still need a structured test pass.

### 5. Tailscale 🟡
Connect by Tailscale address or MagicDNS name, or through routes the Mac reports. Not yet tested from a cellular network.

### 6. Selected-file transfer 🟡
Implemented and unit-tested on both sides: the receiver chooses the destination, chunks are bounded, the hash is verified, nothing is overwritten, and partial files are cleaned up. Not yet tested on a device.

### 7. iOS client 🟡
In progress: shared Swift protocol core and its tests are done; the app itself is being built (Simulator first).

## Release gates
1. Independent review of the pairing protocol (`docs/SECURITY.md`).
2. Mac key non-exportability independently verified; Secure Enclave identity evaluated.
3. Full acceptance pass on physical phones and tablets (`docs/ACCEPTANCE.md`).
4. Store readiness. Everything known is in `docs/PUBLISHING.md`; publishing waits until all three apps are complete.
