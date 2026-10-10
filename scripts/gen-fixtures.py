#!/usr/bin/env python3
"""Generates protocol/fixtures/*.json from first principles (hashlib/hmac only) so Swift and Kotlin are checked
against an independent implementation. Deterministic: re-running must produce identical files."""
import hashlib, hmac, json, os, struct, base64

root = os.path.join(os.path.dirname(__file__), "..", "protocol", "fixtures")

def hkdf(ikm, info, length, salt=b""):
    prk = hmac.new(salt or b"\x00" * 32, ikm, hashlib.sha256).digest()
    out, t, i = b"", b"", 1
    while len(out) < length:
        t = hmac.new(prk, t + info + bytes([i]), hashlib.sha256).digest(); out += t; i += 1
    return out[:length]

def sas(b):
    return [((b[0] << 5) | (b[1] >> 3)) + 1000,
            (((b[1] & 7) << 10) | (b[2] << 2) | (b[3] >> 6)) + 1000,
            (((b[3] & 63) << 7) | (b[4] >> 1)) + 1000]

def h(n, seed):  # deterministic pseudo-random bytes
    return b"".join(hashlib.sha256(f"{seed}/{i}".encode()).digest() for i in range(n // 32 + 1))[:n]

# --- P-256 (SEC 2 §2.4.2), affine arithmetic for fixture generation only; never used by the apps. ---
P = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
A, B = P - 3, 0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b
N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
G = (0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296,
     0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5)

def on_curve(pt): return pt is not None and (pt[1] ** 2 - pt[0] ** 3 - A * pt[0] - B) % P == 0

def add(p1, p2):
    if p1 is None: return p2
    if p2 is None: return p1
    if p1[0] == p2[0] and (p1[1] + p2[1]) % P == 0: return None
    if p1 == p2: l = (3 * p1[0] * p1[0] + A) * pow(2 * p1[1], -1, P) % P
    else: l = (p2[1] - p1[1]) * pow(p2[0] - p1[0], -1, P) % P
    x = (l * l - p1[0] - p2[0]) % P
    return (x, (l * (p1[0] - x) - p1[1]) % P)

def mul(k, pt):
    r = None
    while k:
        if k & 1: r = add(r, pt)
        pt, k = add(pt, pt), k >> 1
    return r

def x963(pt): return b"\x04" + pt[0].to_bytes(32, "big") + pt[1].to_bytes(32, "big")

# Positive controls: base point on curve, order n, and a NIST CAVS ECDH P-256 vector (KAS ECC CDH primitive, COUNT 0).
assert on_curve(G) and mul(N, G) is None
cavs_q = (0x700c48f77f56584c5cc632ca65640db91b6bacce3a4df6b42ce7cc838833d287,
          0xdb71e509e3fd9b060ddb20ba5c51dcc5948d46fbf640dfe0441782cab85fa4ac)
cavs_d = 0x7d7dc5f71eb29ddaf80d6214632eeae03d9058af1fb6d22ed80badb62bc1a534
assert mul(cavs_d, cavs_q)[0] == 0x46fc62106420ff012e54a434fbdd2d25ccc5852060561e68040dd7778997bd7b

ecdh = []
for i in range(3):
    dC, dS = int.from_bytes(h(32, f"dC{i}"), "big") % (N - 1) + 1, int.from_bytes(h(32, f"dS{i}"), "big") % (N - 1) + 1
    QC, QS = mul(dC, G), mul(dS, G)
    z = mul(dC, QS)[0]
    assert z == mul(dS, QC)[0]
    ecdh.append(dict(privC=dC.to_bytes(32, "big").hex(), privS=dS.to_bytes(32, "big").hex(),
                     ephC=x963(QC).hex(), ephS=x963(QS).hex(), z=z.to_bytes(32, "big").hex()))

gx, gy = G
invalid = [
    dict(name="off curve (y+1)", hex=x963((gx, (gy + 1) % P)).hex()),
    dict(name="wrong prefix 0x05", hex="05" + x963(G).hex()[2:]),
    dict(name="compressed form", hex=("03" if gy & 1 else "02") + gx.to_bytes(32, "big").hex()),
    dict(name="too short", hex=x963(G).hex()[:-2]),
    dict(name="too long", hex=x963(G).hex() + "00"),
    dict(name="infinity encoding", hex="00"),
    dict(name="all zero coordinates", hex="04" + "00" * 64),
    dict(name="x >= p", hex="04" + (gx + P).to_bytes(33, "big")[1:].hex() + gy.to_bytes(32, "big").hex() if gx + P < 2 ** 256 else "04" + "ff" * 64),
    dict(name="hashed bytes (old fixture style)", hex=(b"\x04" + h(64, "ephC0")).hex()),
]
for v in invalid:
    b = bytes.fromhex(v["hex"])
    assert not (len(b) == 65 and b[0] == 4 and on_curve((int.from_bytes(b[1:33], "big"), int.from_bytes(b[33:], "big")))
                and int.from_bytes(b[1:33], "big") < P and int.from_bytes(b[33:], "big") < P), v["name"]

pairing = []
for i in range(3):
    z, pinC, pinS, cb = h(32, f"z{i}"), h(32, f"pinC{i}"), h(32, f"pinS{i}"), h(32, f"cb{i}")
    pid = h(16, f"pairingId{i}")
    ephC, ephS = b"\x04" + h(64, f"ephC{i}"), b"\x04" + h(64, f"ephS{i}")
    suffix = pid + pinC + pinS + cb + ephC + ephS
    sb = hkdf(z, b"TETHERLY-SAS-v1" + suffix, 5)
    k = hkdf(z, b"TETHERLY-MAC-v1" + suffix, 32)
    pairing.append({k2: v.hex() for k2, v in dict(z=z, pairingId=pid, pinC=pinC, pinS=pinS, cb=cb, ephC=ephC, ephS=ephS,
        commitment=hashlib.sha256(ephC).digest(), sasBytes=sb, k=k,
        clientMac=hmac.new(k, b"client" + pinC, hashlib.sha256).digest(),
        serverMac=hmac.new(k, b"server" + pinS, hashlib.sha256).digest()).items()} | {"sas": sas(sb)})
# RFC 5869 test case 1 guards the HKDF primitive itself.
rfc = dict(ikm="0b" * 22, salt="000102030405060708090a0b0c", info="f0f1f2f3f4f5f6f7f8f9", length=42,
           okm="3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865")
assert hkdf(bytes.fromhex(rfc["ikm"]), bytes.fromhex(rfc["info"]), 42, bytes.fromhex(rfc["salt"])).hex() == rfc["okm"]

def frame(t, payload):
    return (struct.pack(">IB", len(payload) + 1, t) + payload).hex()

def js(o): return json.dumps(o, separators=(",", ":")).encode()

cfg = struct.pack(">HHH", 1920, 1080, 4) + b"\x67\x42\x00\x1f" + struct.pack(">H", 2) + b"\x68\xce"
frames = [
    dict(name="hello control", kind="control", dir="c2s", hex=frame(1, js({"type": "hello", "versions": [1], "kind": "control", "device": "Test phone"})), expect="ok:1"),
    dict(name="ping", kind="control", dir="c2s", hex=frame(1, js({"type": "ping", "n": 3})), expect="ok:1"),
    dict(name="unicode text", kind="control", dir="c2s", hex=frame(1, js({"type": "text", "text": "héllo 👋 नमस्ते"})), expect="ok:1"),
    dict(name="zero length", kind="control", dir="c2s", hex="00000000", expect="malformed"),
    dict(name="oversized control (checked before allocation)", kind="control", dir="c2s", hex="0001000101", expect="frame_too_large"),
    dict(name="max-size length claim on control", kind="control", dir="c2s", hex="ffffffff01", expect="frame_too_large"),
    dict(name="video frame type on control", kind="control", dir="c2s", hex=frame(0x11, b"\x00" * 9 + b"\x01"), expect="unknown_type"),
    dict(name="unknown frame type", kind="control", dir="c2s", hex=frame(0x7f, b"x"), expect="unknown_type"),
    dict(name="json not an object", kind="control", dir="c2s", hex=frame(1, b"[1,2]"), expect="malformed"),
    dict(name="json missing type", kind="control", dir="c2s", hex=frame(1, js({"n": 1})), expect="malformed"),
    dict(name="json type not string", kind="control", dir="c2s", hex=frame(1, js({"type": 5})), expect="malformed"),
    dict(name="invalid utf8", kind="control", dir="c2s", hex=frame(1, b'{"type":"\xff"}'), expect="malformed"),
    dict(name="truncated json", kind="control", dir="c2s", hex=frame(1, b'{"type":"pi'), expect="malformed"),
    dict(name="video config", kind="video", dir="s2c", hex=frame(0x10, cfg), expect="ok:16"),
    dict(name="video config bad lengths", kind="video", dir="s2c", hex=frame(0x10, cfg + b"\x00"), expect="malformed"),
    dict(name="video config zero width", kind="video", dir="s2c", hex=frame(0x10, struct.pack(">HHH", 0, 1080, 4) + cfg[6:]), expect="malformed"),
    dict(name="video keyframe", kind="video", dir="s2c", hex=frame(0x11, struct.pack(">QB", 123456, 1) + b"\x00\x00\x00\x01\x65\x88"), expect="ok:17"),
    dict(name="video frame empty data", kind="video", dir="s2c", hex=frame(0x11, struct.pack(">QB", 1, 0)), expect="malformed"),
    dict(name="video frame reserved flag", kind="video", dir="s2c", hex=frame(0x11, struct.pack(">QB", 1, 2) + b"\x01"), expect="malformed"),
    dict(name="video frame oversized", kind="video", dir="s2c", hex="00400001" + "11", expect="frame_too_large"),
    dict(name="video frame from client", kind="video", dir="c2s", hex=frame(0x11, struct.pack(">QB", 1, 0) + b"\x01"), expect="unknown_type"),
    dict(name="file chunk", kind="file", dir="any", hex=frame(0x20, b"abc"), expect="ok:32"),
    dict(name="file chunk empty", kind="file", dir="any", hex=frame(0x20, b""), expect="malformed"),
    dict(name="file chunk oversized", kind="file", dir="any", hex="00040002" + "20", expect="frame_too_large"),
    dict(name="file chunk on control", kind="control", dir="c2s", hex=frame(0x20, b"abc"), expect="unknown_type"),
    dict(name="mac audio", kind="audio", dir="s2c", hex=frame(0x30, struct.pack(">Q", 1000) + b"\x01\x00\x02\x00"), expect="ok:48"),
    dict(name="former mic audio type", kind="audio", dir="c2s", hex=frame(0x31, struct.pack(">Q", 1000) + b"\x01\x00"), expect="unknown_type"),
    dict(name="mac audio partial frame", kind="audio", dir="s2c", hex=frame(0x30, struct.pack(">Q", 1) + b"\x01\x00"), expect="malformed"),
    dict(name="mac audio empty", kind="audio", dir="s2c", hex=frame(0x30, struct.pack(">Q", 1)), expect="malformed"),
    dict(name="mac audio oversized", kind="audio", dir="s2c", hex="0000400a30", expect="frame_too_large"),
    dict(name="mac audio from client", kind="audio", dir="c2s", hex=frame(0x30, struct.pack(">Q", 1) + b"\x01\x00\x02\x00"), expect="unknown_type"),
    dict(name="mic audio from mac", kind="audio", dir="s2c", hex=frame(0x31, struct.pack(">Q", 1) + b"\x01\x00"), expect="unknown_type"),
    dict(name="audio frame on video", kind="video", dir="s2c", hex=frame(0x30, struct.pack(">Q", 1) + b"\x01\x00\x02\x00"), expect="unknown_type"),
]

names = [
    ("report.pdf", "report.pdf"), ("../../etc/passwd", "passwd"), ("..\\..\\win.ini", "win.ini"),
    ("/abs/path/photo.jpg", "photo.jpg"), (".hidden", "hidden"), ("...", "file"), ("", "file"),
    ("a\u0000b\u001fc.txt", "abc.txt"), ("ファイル 名.txt", "ファイル 名.txt"), ("time:12.txt", "time12.txt"),
    ("x" * 300 + ".txt", "x" * 255), ("é" * 200, "é" * 127), ("dir/", "file"), (" spaced .txt", " spaced .txt"),
]
os.makedirs(root, exist_ok=True)
for fname, data in [("pairing.json", {"rfc5869": rfc, "note": "vectors = KDF/SAS arithmetic only; ephC/ephS there are arbitrary bytes, not curve points. ecdh = valid P-256 agreement. invalidPoints = must be rejected.", "vectors": pairing, "ecdh": ecdh, "invalidPoints": invalid}), ("frames.json", frames),
                    ("filenames.json", [{"raw": r, "sanitized": s} for r, s in names])]:
    with open(os.path.join(root, fname), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False); f.write("\n")
print("ok", len(pairing), len(frames), len(names))
