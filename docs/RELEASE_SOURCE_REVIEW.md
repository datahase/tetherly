# Source review, 10 October 2026

This is an internal source review by the implementation assistant. The owner confirmed no independent review exists. It does not satisfy the independent review required by docs/SECURITY.md and protocol/SPEC.md, prove the custom SAS protocol secure, or establish physical-device acceptance.

## Scope and evidence

Read Mac TLS admission, hello routing, pairing state machine, ticket consumption, trust persistence/revocation, frame bounds, input permission dispatch, file destination and integrity checks, session teardown and capture callbacks. Read Android TLS pin verification/exporter handling, pairing persistence, trust decisions and channel/file lifecycle. Existing tests cover pairing order, commitment validation, confirmation MACs, failed persistence, pin-change rejection, framing and controller races. Peer loopback tests explicitly disable TLS; they do not test real mutual TLS. No independent cryptographic proof, fuzzing, external penetration test or real network attacker test was performed.

Observed protections include TLS 1.3 with client authentication, P-256 pin decisions, pairing-window-only admission for unknown identities, SAS comparison and host confirmation before durable trust, atomic single-use tickets bound to session/pin/purpose/expiry, length checks before frame allocation, allowlisted input with dispatch-time Accessibility checks, user-chosen incoming file destinations, exclusive temporary files, size/hash checks, and session teardown. These source observations are not a security approval.

## Corrections

1. Mac BridgeHost.applyAudio routed queued PCM through whichever session was current when the host queue ran. It now captures the originating session and audio peer weakly and verifies both identities plus wantsMacAudio before sending. This prevents stale queued audio from being forwarded to a replacement session or channel.
2. Mac BridgeHost.tick stopped only video when Screen Recording permission disappeared. Audio has a separate SCStream and can run without video. The check now stops audio capture, clears audio intent/channel, invalidates outstanding video/audio tickets and reports the permission error for either active channel.
3. SystemAudioCapture.start checked its generation and installed its stream in separate critical sections. It now performs that operation atomically and stops a stream whose asynchronous start completed after cancellation, following the existing video-capture pattern.
4. Android release lint found a missing super.onPointerCaptureChange call. Added the required framework call before forwarding the callback. Release lint subsequently reports zero errors and 14 warnings.

## Release validation and limits

The revised universal Mac app and DMG were notarized by Apple and passed ticket, signature and Gatekeeper checks. The final signed Android package passed release lint, certificate verification and the scanner registrar regression check. Version and changelog were observed on the installed Android phone. The iOS simulator build passed with the camera permission/startup fix.

The owner reports feature testing complete and requested no repeated broad matrix. Physical iOS camera verification is deferred to a friend after release. Audio revocation/reconnect races, clean-Mac first launch and cellular routing were not newly independently verified by this source review. No independent pairing/TLS review has occurred. The owner authorized the public 0.1.0 release with that limitation disclosed; this is not an independent security approval.

Local operational evidence, device captures, notarization logs and account metadata remain outside Git. This review does not authorize changing repository visibility.
