# Tetherly wire protocol, version 1

Status: **development protocol.** Implementations exist for the Mac host, Android client, and iOS client. The [acceptance record](../docs/ACCEPTANCE.md) distinguishes automated checks from physical-device evidence; the [project plan](../docs/PLAN.md) tracks remaining work.

The pairing protocol (§4) is a **custom** design and has **not** been independently reviewed. That review remains pending. The owner authorized a public 0.1.0 release exception with the limitation disclosed; feature testing does not constitute independent review. See the [security design](../docs/SECURITY.md).

[Golden fixtures](fixtures/) hold the vectors used by the Swift (XCTest) and Kotlin (JUnit) suites.

## 1. Transport and connections
- TCP + TLS 1.3 only, mutual authentication, no 0-RTT, no resumption. Port **47800**. Bonjour type `_tetherly._tcp`, advertised only on the Mac.
- Mac = TLS server; Android and iOS = TLS clients. Each side has a long-term ECDSA P-256 key with a self-signed certificate. Other key types are rejected.
- **Pin** = SHA-256 over the DER `SubjectPublicKeyInfo` of the peer certificate (32 bytes).
- **Channel binding** `cb` = TLS exporter, label `EXPORTER-Channel-Binding`, empty context, 32 bytes (RFC 9266).
- There are four connection kinds. Each one is a separate TLS connection whose first frame is `hello`:
  - `control`: one per session. Carries pairing, input, clipboard, signalling and heartbeats.
  - `video`: Mac→client H.264. Needs a `video` ticket.
  - `file`: one per transfer. Needs a `file` ticket bound to that transfer.
  - `audio`: Mac sound to the phone. Needs an `audio` ticket.

## 2. Framing
```
frame   = length:u32be  type:u8  payload:(length-1 bytes)
```
- `length` counts the type byte plus the payload. `length == 0` is malformed.
- The receiver validates `length` against the limit for the connection kind **before allocating**, then checks `type` against that kind's allowlist. Any violation means: send `error` if possible, close the connection, and run the teardown in §9. There is no resync.

| type | name | allowed on | max length (incl. type byte) |
|---|---|---|---|
| `0x01` | JSON message (UTF-8 object with a string `type`) | control, video, file | 65 536 |
| `0x10` | video config | video, Mac→client only | 4 096 |
| `0x11` | video frame | video, Mac→client only | 4 194 304 |
| `0x20` | file chunk | file, sender→receiver only | 262 145 (256 KiB data) |
| `0x30` | Mac audio | audio, Mac→client only | 16 393 |

A JSON payload must be valid UTF-8 JSON whose top level is an object with a string `type` field. Anything else is `malformed`.
Unknown `type` values are `unknown_type`. That is fatal: the dispatcher is an allowlist.
Binary fields are base64 (RFC 4648, with padding). Integers are JSON numbers inside documented ranges; anything out of range is `malformed`.

### Binary payloads
- `0x10` video config: `width:u16be height:u16be spsLen:u16be sps[spsLen] ppsLen:u16be pps[ppsLen]`. SPS and PPS are raw NAL units without start codes. Width and height are 16..8192. Lengths must exactly fill the payload.
- `0x11` video frame: `ptsMicros:u64be flags:u8 data`. Bit 0 of `flags` means keyframe; the other bits must be 0. `data` is Annex-B (start code `00 00 00 01` before each NAL) and is not empty.
- `0x20` file chunk: raw bytes, 1..262 144.
- `0x30` Mac audio: `ptsMicros:u64be pcm`. PCM is signed 16-bit little-endian at 48 000 Hz, 2 channels interleaved.
  `pcm` is 4..16 384 bytes and a whole number of 4-byte frames.

## 3. Hello and version negotiation (first frame on every connection, client → Mac)
```json
{"type":"hello","versions":[1],"kind":"control","device":"Pixel 9"}
{"type":"hello","versions":[1],"kind":"video","ticket":"<b64 32 bytes>"}
{"type":"hello","versions":[1],"kind":"file","ticket":"<b64 32 bytes>"}
```
The Mac picks the highest common version. If there is none, it sends `error unsupported_version` and closes.
- control → `{"type":"welcome","version":1,"state":"paired"|"pairing","host":"<Mac name>"}`. When `state` is `pairing`, the welcome also carries `"pairingId":b64(16 random bytes)`, fresh for each exchange.
- video and file → `{"type":"welcome","version":1}` after the ticket is consumed. A bad ticket gets `error bad_ticket` and the connection closes.
- `device` is at most 64 characters and `host` at most 64 characters.

Authorization at accept time, enforced inside the TLS verify step and again after the handshake:
- The peer pin is **approved** and not revoked → `state:"paired"`. Every message type is available.
- The peer pin is unknown, **pairing mode is open**, and no other pairing exchange is pending → `state:"pairing"`. Only `pair_*`, `ping` and `pong` are allowed. Anything else gets `error not_paired` and the connection closes.
- Otherwise the TLS handshake is rejected.
- Video and file connections must come from an approved pin, and the pin must equal the pin of the session that issued the ticket.

## 4. Pairing (inside a `state:"pairing"` control connection)
This is a **custom** commitment-based SAS protocol, inspired by Matrix `m.sas.v1` but **not** `m.sas.v1`: the curve, message order and transcript are different. The client is the initiator. All values are bytes. `‖` means concatenation.
Public keys must be valid uncompressed P-256 points: 65 bytes, first byte `0x04`, on the curve, not the point at infinity. Anything else is `pairing_failed`.
`ephC` and `ephS` are ephemeral P-256 public keys in X9.63 uncompressed form (65 bytes). `pinC` and `pinS` are the TLS pins of the client and server.

1. C→S `{"type":"pair_commit","commitment":b64(SHA256(ephC))}`
2. S→C `{"type":"pair_key","key":b64(ephS)}`. This is sent only after the commitment is received.
3. C→S `{"type":"pair_reveal","key":b64(ephC)}`. S checks `SHA256(ephC) == commitment`. If it doesn't match: `error pairing_failed`.
4. Both sides compute `z = ECDH(eph priv, peer eph pub)` (32-byte x coordinate) and
   `suffix = pairingId ‖ pinC ‖ pinS ‖ cb ‖ ephC ‖ ephS`. The fields are fixed-length (16, 32, 32, 32, 65, 65), so the encoding is canonical. The version is in the HKDF label. The roles are fixed by position (client fields first) and by the MAC role strings.
   `sasBytes = HKDF-SHA256(ikm=z, salt="", info="TETHERLY-SAS-v1" ‖ suffix, L=5)`
   `k = HKDF-SHA256(ikm=z, salt="", info="TETHERLY-MAC-v1" ‖ suffix, L=32)`
   Then the SAS is three numbers, each in 1000..9191, built from the first 39 bits of `sasBytes`:
   `n1 = (b0<<5 | b1>>3) + 1000`, `n2 = ((b1&7)<<10 | b2<<2 | b3>>6) + 1000`, `n3 = ((b3&63)<<7 | b4>>1) + 1000`
5. Both screens show the three numbers. Each user confirms that the codes match:
   - Client user confirms → C→S `{"type":"pair_confirm","mac":b64(HMAC-SHA256(k, "client" ‖ pinC))}`
   - Mac user approves → S→C `{"type":"pair_confirm","mac":b64(HMAC-SHA256(k, "server" ‖ pinS))}`
   Each side compares the peer's MAC in constant time. A mismatch gets `error pairing_failed`.
6. When the Mac has both its own user's approval and a valid client MAC, it stores `pinC`, then sends `{"type":"pair_done"}` and closes.
   The client stores `pinS` only after its own user confirmed, the server MAC verified and `pair_done` arrived. It then reconnects as a paired device.
7. Either side may send `{"type":"pair_cancel"}`, or reject. Then nothing is stored.

### 4.1 State machine (strict)
Any message that is not valid in the current state is a fatal `pairing_failed`. That includes duplicates, out-of-order messages, and anything that isn't a `pair_*` message, `ping` or `pong`. Nothing is stored.

| Mac state | accepts | next |
|---|---|---|
| AwaitCommit | `pair_commit` (32-byte commitment) | sends `pair_key` → AwaitReveal |
| AwaitReveal | `pair_reveal` (valid point; SHA-256 equals the commitment) | shows the SAS → AwaitConfirmations |
| AwaitConfirmations | the client's `pair_confirm` (MAC verifies; at most once), and the Mac user's Allow (sends the server `pair_confirm`) or Reject (`pair_cancel`, close) | when both are present → Persist |
| Persist | the pin is written **durably**. On a storage error: `pairing_failed`, nothing approved. | sends `pair_done`, closes |

| Phone state | accepts | next |
|---|---|---|
| AwaitWelcome | `welcome` with state `pairing` and a `pairingId` | sends `pair_commit` → AwaitKey |
| AwaitKey | `pair_key` (valid point) | sends `pair_reveal`, shows the SAS → AwaitUser |
| AwaitUser / AwaitServer | the phone user's confirmation (sends `pair_confirm`), and the server `pair_confirm` (verify the MAC; at most once) | after both → AwaitDone |
| AwaitDone | `pair_done` | stores the Mac pin, then reconnects as paired |

The exchange expires when the pairing window closes, or after 15 s with nothing received.

### 4.2 Persistence boundaries
- **Before the Mac persists:** any cancel, reject, error or disconnect means **neither** side stores anything.
- The Mac sends `pair_done` only **after** a durable write. If the connection drops after that write but before the phone gets `pair_done`, the Mac has the phone approved but the phone has no record. On its next connection, the phone sees `state:"paired"` with no local pin and must **not** trust the Mac. Instead it shows: "This Mac already knows this phone. Revoke it on the Mac and pair again." No pin is ever installed silently.
- The phone stores the pin only after `pair_done`, and then sends nothing else. So the state where the phone has the pin but the Mac doesn't can't arise.

Limits: the pairing window is 120 s, opened explicitly on the Mac. There is at most one pending exchange. After 5 failed or aborted exchanges the window closes. The Mac never replaces an approved pin with a new pin under the same device name; the user has to revoke the old one first.

### 4a. QR pairing link (optional, recommended)
While pairing mode is open, the Mac shows a QR code that encodes:
```
tetherly://pair?v=1&n=<url-encoded Mac name, ≤64>&a=<addr>[,<addr>…]&p=47800&k=<base64url(pinS), no padding>&e=<unix seconds when pairing mode ends>
```
`a` lists IPv4 LAN and Tailscale addresses (at most 4). The client tries them in order, using the usual 5 s bound for each.
`k` is the Mac's 32-byte pin. A client that started from a QR code must abort **before showing any SAS** if the TLS server pin is not equal to `k`. The Android client does this inside its TLS trust check, so it sends nothing to an unverified server and the Mac sees a failed handshake.
The SAS comparison and the Mac approval are still required. The QR authenticates the Mac to the phone; the SAS and approval authenticate the phone to the Mac.
The QR contains no secret. Anyone who sees it learns only the Mac's public-key fingerprint and its addresses.
Clients must reject a link that:
- has an unknown `v`
- has a `k` that doesn't decode to exactly 32 bytes
- has a port outside 1..65535
- is longer than 1024 characters, or has more than 4 addresses
- has an `e` more than 300 s in the past (allowing for clock skew)

Scanned addresses are untrusted input, parsed with the strict host grammar. The link is only an invitation: it is not a credential and grants nothing without the SAS and Mac approval.
If the phone already stores a Mac with the same name but a **different** pin, it must not replace it. It shows the identity-changed error, and the user has to forget that Mac explicitly first.

## 5. Paired session messages (control)
| direction | message | rules |
|---|---|---|
| C→S | `ping {n}` → S `pong {n}` | Client sends every 5 s. Either side closes after 15 s with nothing received. |
| S→C | `host_info {addresses: [{ip, kind}]}` | Sent right after a paired `welcome`. At most 8 IPv4 addresses, `kind` ∈ {`lan`, `tailscale`}. Clients store them with the Mac's pin as candidate routes. They are hints only: every connection still requires the pinned identity. |
| S→C | `display {id, width, height, scale}` | Size in points. Re-sent when the display configuration changes. |
| S→C | `cursor {x, y}` | Normalized 0..1 over the streamed display. Sent at most 60 times per second, only while video is active and the cursor has moved. Drives the client-drawn pointer and lets a zoomed-in client keep it in view. |
| C→S | `video_start {maxDimension, fps, cursor?}` | `maxDimension` ∈ {960, 1280, 1920}, `fps` an integer in 15..240 (a protocol sanity bound, not a target): the client asks for the most its screen and decoder handle, and the Mac clamps that to its own display refresh rate, so the stream runs at the lower of the two maximums. `cursor` ∈ {`"shown"`, `"hidden"`} (default shown): hidden leaves the pointer out of the video so the client can draw its own, driven by `cursor` messages. S replies `video_ticket {ticket}`. The same message on a running stream changes the settings. |
| C→S | `audio_start {mac}` | Boolean: send the Mac's sound to the client. The Mac replies `audio_ticket {ticket}` for an `audio` connection, or changes the running one. Needs Screen Recording. Clients send nothing on the audio connection. |
| C→S | `audio_stop` | Closes the audio connection. |
| C→S | `video_stop` | Mac stops capture. Capture also stops when the video connection closes. |
| C→S | `keyframe` | Mac forces an IDR frame. |
| C→S | `pointer {dx, dy}` | Relative move in points, each in −10000..10000. Clamped to the display. |
| C→S | `pointer_abs {x, y}` | Normalized 0..1 over the streamed display. |
| C→S | `button {button:"left"\|"right", down}` | Mac tracks held buttons; a move while a button is held is a drag. |
| C→S | `click {button, count}` | `count` 1..3, at the current position. |
| C→S | `scroll {dx, dy}` | Pixels, −5000..5000. |
| C→S | `key {code, modifiers}` | `code` = macOS virtual keycode 0..127. `modifiers` ⊆ {cmd, shift, alt, ctrl, fn}. Press and release; modifiers are never held across messages. |
| C→S | `modifier {key: "fn", down}` | A bare fn press or release, posted as macOS reports a real one (flags changed, keycode 63). Dictation tools use it as push-to-talk. Released on teardown like a held button. |
| C→S | `text {text}` | 1..1000 UTF-16 units. Typed as Unicode, independent of keyboard layout. |
| C→S | `clipboard_set {text}` | At most 60 000 UTF-8 bytes. Sent only on an explicit user action. |
| C→S | `clipboard_get` → S `clipboard {text}` | Same limit. Empty text if the Mac clipboard has no text. |
| either | `file_offer {id, name, size}` | `id` is 16 hex characters, `name` at most 255 bytes, `size` 0..4 GiB. |
| either | `file_accept {id}` / `file_reject {id, reason}` | Sent by the receiver after an explicit user choice of destination. |
| S→C | `file_ticket {id, ticket}` | After acceptance in either direction. The client opens the file connection. |
| either | `file_cancel {id}` | Closes that transfer's connection and deletes partial data. |
| receiver→sender | `file_result {id, ok, error?}` | Sent after the hash check. |
| S→C | `error {code, message}`; `bye {reason}` | |

Rate limits on the Mac (exceeding any of them gets `error rate_limited` and the session closes):
- input messages: 500 per second
- all control messages: 1000 per second
- `video_start`: 20 per minute
- outbound control backlog: 256 unsent frames, which means the peer isn't reading

Permissions:
- **Missing at request time:** the Mac checks Accessibility before **every** input message and Screen Recording before starting capture. If one is missing, it sends `error permission_accessibility` or `error permission_screen_recording`. The session stays open, so the phone can explain the problem and retry.
- **Revoked during a session:** the Mac checks every second. If Screen Recording is lost, capture stops and the video connection closes. If Accessibility is lost, held buttons are released (best effort) and queued input is dropped. Either way the matching error is sent and control stays open. Revoking the **device** always runs the full §9 teardown.

## 6. Video
After `hello`/`welcome` on the video connection, the Mac sends `0x10` config before the first frame and again whenever the resolution or SPS/PPS change.
Every config is followed by a keyframe. H.264 has no B-frames. Keyframes come at least every 2 s, plus on demand.
Send queue: at most **2** frames. When it's full, pending non-key frames are dropped and the next frame is forced to be a keyframe.
The client decodes to a surface, keeps the aspect ratio, and sends `keyframe` after any decoder error or reconfigure.

## 7. File transfer
The file connection carries `hello`/`welcome`, then the sender's `0x20` chunks, then `{"type":"file_end","sha256":b64}` from the sender.
The receiver:
- writes to a temporary file in the chosen destination
- rejects data beyond the offered `size`
- on `file_end` checks the size and SHA-256, then publishes the file without overwriting
- reports `file_result` over control

On a mismatch, cancel or disconnect, the partial file is deleted.
Names are sanitized: only the last path component is used; control characters and `/ \ :` are removed; leading dots are removed; the name is truncated to 255 UTF-8 bytes; an empty name becomes `file`. A name collision gets ` (2)`, ` (3)` and so on before the extension.
There is one active transfer per direction. Chunks are paced by send completion, so control traffic is never queued behind file data.

## 8. Error codes
`unsupported_version, not_paired, pairing_closed, pairing_failed, bad_ticket, frame_too_large, malformed, unknown_type, rate_limited, busy, revoked, permission_screen_recording, permission_accessibility, file_rejected, file_failed, timeout`

## 9. Teardown
When the control connection closes, the heartbeat times out, the device is revoked, hosting is disabled, or a fatal error occurs, the Mac:
- closes that session's video and file connections and deletes partial files
- stops capture and encoding
- releases held mouse buttons
- invalidates outstanding tickets
- drops queued input

A reconnect starts a new session, with no replay. A second approved device gets `error busy` while a session is live. The **same** device reconnecting replaces its old session.

## 10. Fixtures
- `fixtures/frames.json`: hex frames with a connection kind, a direction and an expected verdict (`ok:<type>` or an error code).
- `fixtures/pairing.json`:
  - `vectors`: **KDF/SAS arithmetic vectors only.** They contain `z`, `pairingId`, the pins, `cb`, `ephC` and `ephS`, with the expected commitment, SAS, k and both MACs. `ephC` and `ephS` are arbitrary bytes, **not valid curve points**, so these vectors say nothing about ECDH or point validation.
  - `ecdh`: valid P-256 key-agreement vectors (private scalars, public points, `z`). They are computed by a self-contained P-256 implementation in the generator, which is checked against a NIST CAVS ECDH vector.
  - `invalidPoints`: encodings both apps must reject: off-curve, wrong prefix, compressed, wrong length, infinity, and coordinates ≥ p.
  - `rfc5869`: the HKDF primitive's test vector.
- `fixtures/filenames.json`: raw name → sanitized name.
