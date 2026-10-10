package link.tetherly

import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.security.spec.ECFieldFp
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

/** SPEC §4 commitment-based SAS. Only platform primitives (SHA-256, HMAC, ECDH); this file just composes them. */
object Pairing {
    val p256: ECParameterSpec by lazy {
        AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }
            .getParameterSpec(ECParameterSpec::class.java)
    }

    class Keys(val sasBytes: ByteArray, val sas: List<Int>, val k: ByteArray)

    fun sha256(vararg parts: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").apply { parts.forEach { update(it) } }.digest()

    fun hmac(key: ByteArray, vararg parts: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")); parts.forEach { update(it) } }.doFinal()

    /** RFC 5869. An empty salt means HashLen zero bytes (SecretKeySpec refuses an empty key; HMAC treats them the same). */
    fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        require(length in 1..255 * 32)
        val prk = hmac(if (salt.isEmpty()) ByteArray(32) else salt, ikm)
        val out = java.io.ByteArrayOutputStream()
        var t = ByteArray(0)
        var i = 1
        while (out.size() < length) {
            t = hmac(prk, t, info, byteArrayOf(i++.toByte()))
            out.write(t)
        }
        return out.toByteArray().copyOf(length)
    }

    fun commitment(ephC: ByteArray) = sha256(ephC)

    fun derive(z: ByteArray, pairingId: ByteArray, pinC: ByteArray, pinS: ByteArray, cb: ByteArray, ephC: ByteArray, ephS: ByteArray): Keys {
        require(pairingId.size == 16 && pinC.size == 32 && pinS.size == 32 && cb.size == 32 && ephC.size == 65 && ephS.size == 65)
        val suffix = pairingId + pinC + pinS + cb + ephC + ephS
        val sasBytes = hkdf(z, ByteArray(0), "TETHERLY-SAS-v1".toByteArray() + suffix, 5)
        val k = hkdf(z, ByteArray(0), "TETHERLY-MAC-v1".toByteArray() + suffix, 32)
        return Keys(sasBytes, sasNumbers(sasBytes), k)
    }

    fun sasNumbers(b: ByteArray): List<Int> {
        val u = b.map { it.toInt() and 0xFF }
        return listOf(
            ((u[0] shl 5) or (u[1] shr 3)) + 1000,
            (((u[1] and 7) shl 10) or (u[2] shl 2) or (u[3] shr 6)) + 1000,
            (((u[3] and 63) shl 7) or (u[4] shr 1)) + 1000,
        )
    }

    fun clientMac(k: ByteArray, pinC: ByteArray) = hmac(k, "client".toByteArray(), pinC)
    fun serverMac(k: ByteArray, pinS: ByteArray) = hmac(k, "server".toByteArray(), pinS)

    /** Constant-time comparison. */
    fun macEquals(a: ByteArray, b: ByteArray) = MessageDigest.isEqual(a, b)

    fun ephemeral(): KeyPair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()

    /** X9.63 uncompressed: 0x04 ‖ x ‖ y, 32 bytes each. */
    fun encodePoint(key: ECPublicKey): ByteArray = byteArrayOf(4) + fixed(key.w.affineX) + fixed(key.w.affineY)

    fun decodePoint(bytes: ByteArray): ECPublicKey {
        if (bytes.size != 65 || bytes[0] != 4.toByte()) malformed("not an uncompressed P-256 point")
        val x = BigInteger(1, bytes.copyOfRange(1, 33))
        val y = BigInteger(1, bytes.copyOfRange(33, 65))
        val p = (p256.curve.field as ECFieldFp).p
        // Reject off-curve points explicitly instead of relying on each provider to do it.
        val onCurve = x < p && y < p && y.multiply(y).mod(p) == x.pow(3).add(p256.curve.a.multiply(x)).add(p256.curve.b).mod(p)
        if (!onCurve) malformed("point is not on P-256")
        return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(x, y), p256)) as ECPublicKey
    }

    fun agree(private: PrivateKey, peer: ECPublicKey): ByteArray =
        KeyAgreement.getInstance("ECDH").apply { init(private); doPhase(peer, true) }.generateSecret()

    private fun fixed(n: BigInteger): ByteArray {
        val raw = n.toByteArray()
        return when {
            raw.size == 32 -> raw
            raw.size > 32 -> raw.copyOfRange(raw.size - 32, raw.size)
            else -> ByteArray(32 - raw.size) + raw
        }
    }
}

/** Pairing ended without storing anything. [reply] is what to send the Mac before closing, if anything. */
class PairingFailed(message: String, val reply: JSONObject?) : Exception(message)

/**
 * The phone's side of SPEC §4.1, strictly: AwaitKey → AwaitConfirmations (user and server, each once) → AwaitDone.
 * Anything out of order, duplicated or unknown throws [PairingFailed]. [persist] runs exactly once, on `pair_done`
 * after both confirmations; nothing else here stores anything.
 */
class PairingMachine(
    private val pairingId: ByteArray,
    private val pinC: ByteArray,
    private val pinS: ByteArray,
    private val cb: ByteArray,
    private val persist: () -> Unit,
    private val eph: KeyPair = Pairing.ephemeral(),
) {
    enum class Step { AwaitKey, AwaitConfirmations, AwaitDone, Done, Failed }

    var step = Step.AwaitKey
        private set
    private val ephC = Pairing.encodePoint(eph.public as ECPublicKey)
    private var keys: Pairing.Keys? = null
    var userConfirmed = false
        private set
    var serverConfirmed = false
        private set
    val sas: List<Int>? get() = keys?.sas

    /** The first message, sent right after a `welcome` in pairing state. */
    fun commit(): JSONObject = msg("pair_commit", "commitment" to b64(Pairing.commitment(ephC)))

    /** Handles one message from the Mac; returns what to send back, if anything. */
    fun receive(type: String, o: JSONObject): JSONObject? {
        if (step == Step.Done || step == Step.Failed) throw PairingFailed("Pairing ended.", null)
        return when {
            type == "ping" -> msg("pong", "n" to o.opt("n"))
            type == "pong" -> null
            type == "pair_cancel" -> fail("Pairing was cancelled on the Mac.", null)
            type == "error" -> fail(SessionController.explainCode(o.opt("code") as? String ?: ""), null)
            type == "pair_key" && step == Step.AwaitKey -> {
                val ephS = try {
                    o.bytes("key", 65).also { Pairing.decodePoint(it) }
                } catch (e: ProtocolException) {
                    fail("Pairing failed: the Mac sent an invalid key. Nothing was saved.", cancel())
                }
                val z = Pairing.agree(eph.private, Pairing.decodePoint(ephS))
                keys = Pairing.derive(z, pairingId, pinC, pinS, cb, ephC, ephS)
                step = Step.AwaitConfirmations
                msg("pair_reveal", "key" to b64(ephC))
            }
            type == "pair_confirm" && step == Step.AwaitConfirmations && !serverConfirmed -> {
                val mac = runCatching { o.bytes("mac", 32) }.getOrNull()
                if (mac == null || !Pairing.macEquals(mac, Pairing.serverMac(keys!!.k, pinS))) {
                    fail("Pairing failed: the Mac's confirmation didn't match. Nothing was saved.", msg("error", "code" to "pairing_failed", "message" to "bad MAC"))
                }
                serverConfirmed = true
                advance()
                null
            }
            type == "pair_done" && step == Step.AwaitDone -> {
                persist()
                step = Step.Done
                null
            }
            else -> fail("Pairing failed: unexpected $type from the Mac. Nothing was saved.", cancel())
        }
    }

    /** The phone user confirmed the codes match; returns the client `pair_confirm`. */
    fun confirm(): JSONObject? {
        if (step != Step.AwaitConfirmations || userConfirmed) return null
        userConfirmed = true
        advance()
        return msg("pair_confirm", "mac" to b64(Pairing.clientMac(keys!!.k, pinC)))
    }

    /** The phone user cancelled; returns `pair_cancel` to send before closing. */
    fun cancel(): JSONObject {
        step = Step.Failed
        return msg("pair_cancel")
    }

    private fun advance() {
        if (userConfirmed && serverConfirmed) step = Step.AwaitDone
    }

    private fun fail(message: String, reply: JSONObject?): Nothing {
        step = Step.Failed
        throw PairingFailed(message, reply)
    }
}
