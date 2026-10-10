# Security design

[Documentation home](README.md) · [Getting started](GETTING_STARTED.md) · [Development](DEVELOPMENT.md)

Status: **implemented, not security-approved.** Both apps implement this design. An internal review found that the
first SAS idea was unsound (see Pairing). The commitment-based adaptation below is **pending independent review**.
Independent review of the pairing protocol remains the security approval gate. On 10 October 2026, the owner explicitly authorized a public 0.1.0 release before that review, with its absence disclosed. Owner-reported feature testing and the internal source review do not satisfy independent review. See `release/store/evidence/public-release-owner-decision.json`.

## Principles
- Only maintained TLS (Network.framework / Security.framework on the Mac, platform JSSE/Conscrypt on Android) and OS key stores. No custom primitives.
- Being on the same LAN or Tailscale network does **not** authorize anything. Every connection must authenticate as an approved identity.
- Logs never contain keys, tickets, clipboard text, keystrokes or file contents. Diagnostics are sanitized: event types, sizes, error codes.

## Identities
- Each device has a long-term ECDSA P-256 key wrapped in a self-signed certificate.
- **Android:** Android Keystore, alias `tetherly-identity`, `PURPOSE_SIGN`, digests `NONE` and `SHA-256`. It is hardware-backed (TEE or StrongBox) where the device offers it, and private key material never leaves the Keystore. Conscrypt calls into the Keystore to sign during the TLS handshake.
- **Mac, as implemented:** `SecKeyCreateRandomKey` creates the key with these attributes:
  - `kSecAttrKeyTypeECSECPrimeRandom`, 256 bits
  - `kSecAttrIsPermanent = true` in the **login (file-based) keychain**
  - `kSecAttrIsExtractable = false`, tag `link.tetherly.host.identity`

  The keychain ACL created with the item trusts only the creating app's designated requirement (its signing team and the identifier `link.tetherly.host`).
  The certificate is DER encoded by `Identity.swift` and signed with `SecKeyCreateSignature`, then paired to the key through `SecIdentityCreateWithCertificate` for Network.framework.
- **What that does and does not guarantee:**
  - `kSecAttrIsExtractable = false` makes the keychain refuse to export the key through its APIs.
  - The key is still **software-protected**, encrypted under the user's login keychain. Malware running as the user with keychain access, or someone with the login password, is outside this protection.
  - Apple distinguishes this from Secure Enclave keys, whose material never leaves the hardware: <https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave>, <https://developer.apple.com/documentation/cryptokit/storing-cryptokit-keys-in-the-keychain>.
- **Why not the Secure Enclave yet:**
  - A persistent Secure Enclave key needs the data-protection keychain. That needs a `keychain-access-groups` entitlement, which for a Developer ID app needs a provisioning profile. None exists yet.
  - It is also unverified whether Network.framework's TLS server accepts a `SecIdentity` built on a Secure Enclave key.
  - **Pending:** create a Developer ID provisioning profile, then prototype Secure Enclave plus `sec_identity` in a throwaway target. Every Mac that runs macOS 14 has a Secure Enclave (Apple silicon or T2), so hardware support is not the blocker.
- A peer is identified by `SHA-256(DER SubjectPublicKeyInfo)` (its "pin"). Names and addresses are only discovery hints.
- Mutual TLS 1.3 on every connection. 0-RTT is disabled, and session resumption is off at first.
- On the Mac, the server must explicitly require client certificates, because Apple's default does not. Its `sec_protocol_options_set_verify_block` accepts either a pinned approved identity or, only while pairing mode is open, an unknown candidate. It fails closed and calls completion exactly once.

## Pairing (to be specified in full in protocol/SPEC.md)
The first idea was SAS = a truncated hash of the TLS exporter plus both pins. It was **rejected**: the TLS 1.3 exporter is fixed before the client sends its certificate, so a malicious client can grind client keys offline to hit a target 6-digit SAS (about 20 bits).

Adopted direction: a commitment-based SAS exchange modelled on Matrix `m.sas.v1`, run inside the mutual-TLS pairing connection.
1. The user turns on pairing mode on the Mac. It opens a **120 s** window, allows one pending exchange, and applies a global (not per-IP) limit on failed or aborted attempts.
2. The mTLS handshake completes. The connection enters a restricted *pairing* state: key possession is proven, but trust is still pending.
3. Commitment → key exchange → SAS. Both sides authenticate a canonical payload: protocol version, roles, pairing ID, both pins, and the RFC 9266 channel binding (`EXPORTER-Channel-Binding`, empty context, 32 bytes; Apple `sec_protocol_metadata_create_secret`, Android `SSLSockets.exportKeyingMaterial`, API 31+, or bundled Conscrypt below 31).
4. Both screens show the SAS as **three 4-digit numbers** (about 39 bits). The user compares them and approves on the Mac. MACs are verified, and only then do both sides persist the pins.
5. A known name with a different pin is never silently replaced. It requires revoking the old pairing and pairing again.

This adaptation still needs an independent review for security approval. The owner authorized the public 0.1.0 release while that review remains pending, as recorded above.

Explicitly forbidden: a home-grown shortened SAS (for example a truncated exporter hash), any "accept any certificate" fallback,
and trusting a peer because of its name or address.

## Authorization gate (hard invariants for milestone 2 onwards)
1. An **unknown peer** (unpinned key, pairing mode open) may send only pairing messages. Anything else closes the connection. No display metadata, video, input, clipboard or file operations happen before comparison and Mac approval.
2. **Reconnect** requires a pinned identity on both sides. The revocation list is checked again on every handshake and before every ticket is redeemed.
3. Each control, video and file connection authenticates independently, then **binds atomically** to exactly one approved, live session and one purpose. A connection whose session has ended, or whose ticket is used, expired or for the wrong purpose, is closed.
4. All remote operations go through an **allowlisted, size-bounded dispatcher**: a fixed set of message types, each with a maximum size and a handler. There is no arbitrary shell, AppleScript, URL opening, or remote filesystem browsing or listing.
5. **Permission checks happen at dispatch.** Screen Recording is checked before capture starts, Accessibility before each input batch. If a permission is missing, the request gets an explicit error, not a silent drop.
6. **Teardown**: when the session is lost, a permission is lost, the device is revoked or hosting is disabled, all channels and transfers for that session are cancelled, capture and encoding stop, every held mouse button and modifier is released, and queued input is discarded. Input from before a reconnect is never replayed.
7. Clipboard moves only through explicit Send and Get actions. File destinations are always chosen by the user on the receiving device.

## Android platform choices
- **minSdk 31 (Android 12).** It provides `android.net.ssl.SSLSockets.exportKeyingMaterial` for the RFC 9266 channel binding, without bundling Conscrypt. Android 10 and 11 are not supported, so there is no separate exporter path to verify.
- **Name resolution:** `DnsResolver` (API 29+) with a `CancellationSignal`, so lookups honour the 5 s bound and user cancel. Literal IP addresses skip DNS. This was shown on a physical Android 14 phone: an unknown host gives "Can't find that name", and a blackhole address times out at 5 s. Fake-transport unit tests cover only the controller race logic, not real DNS or sockets.

## QR pairing (SPEC §4a)
The QR code carries the Mac's addresses and pin. A phone that starts from a QR code rejects any server whose pin is different, before any SAS is shown. The QR is not secret, and the SAS comparison plus Mac approval are still required.

## Logging
Logs may record message types, sizes, durations, error codes and pin *prefixes* (8 hex characters). They must never contain keys,
tickets, SAS values, clipboard text, key or text events, file names or contents, or full addresses.

## Session binding for video and file connections
- After the control connection is authenticated, the Mac issues random 256-bit, single-use **channel tickets** over it. Each ticket is bound to: session ID, both pins, purpose (video or file), permissions and expiry (a few seconds).
- Video and file connections must independently pass mTLS pin checks, then present a ticket. The Mac consumes the ticket atomically.

## Revocation and controls
- The Mac shows the connection state and offers Disconnect, Disable hosting and Revoke device.
- Revoking a device deletes its pin, invalidates outstanding tickets, closes its active connections and makes future handshakes fail.

## Threat model
| Threat | Mitigation |
|---|---|
| Active MITM during pairing, including SAS grinding | Commitment-based SAS, 39-bit SAS, user compares and approves on the Mac |
| User approves without comparing | Clear UI, approval only on the Mac, short window, one pending exchange |
| Pairing flood or brute force | Explicit pairing mode, 120 s expiry, at most 5 failed, dropped or timed-out exchanges per window |
| Connection-slot exhaustion | At most 8 connections and 4 per source address; the hello deadline starts at accept, so stalled TLS handshakes are dropped after 10 s |
| Malicious pairing link (deep link from another app or web page) | Android asks the user to confirm before connecting; an in-app QR scan is user-initiated |
| LAN attacker without pairing | Unknown pins are rejected outside pairing mode |
| Ticket replay or session confusion | Single-use tickets bound to pins, purpose and session, with short expiry |
| Stolen device or key | Revoke on the Mac; keys are non-exportable |
| Compromised or buggy **approved** client | Trust assumption: an approved device may use the desktop, so the screen and input are within its rights. Pairing never bypasses the protocol invariants. Even an approved client is limited by the frame-size checks before allocation, the type allowlist, field range validation, the 500 msg/s input limit, bounded queues, one transfer per direction, file-size quotas, safe file names and destinations chosen by the user, permission checks at dispatch, and revocation. Negative tests cover each of these through the shared fixtures, plus the checks listed in ACCEPTANCE.md. |
| Oversized or malformed frames | Length limits are checked before allocating (protocol/SPEC.md) |
| File path attacks (milestone 6) | Not covered by TLS. Use safe names, no traversal, temp files and integrity checks. |
| Secrets in logs | Sanitized diagnostics only |
