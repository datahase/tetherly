package link.tetherly

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigInteger
import java.security.KeyFactory
import java.security.interfaces.ECPublicKey
import java.security.spec.ECPrivateKeySpec

class PairingTest {
    private val fixture = JSONObject(fixture("pairing.json"))

    @Test fun hkdfMatchesRfc5869Case1() {
        val v = fixture.getJSONObject("rfc5869")
        val okm = Pairing.hkdf(v.getString("ikm").unhex(), v.getString("salt").unhex(), v.getString("info").unhex(), v.getInt("length"))
        assertEquals(v.getString("okm"), okm.hex())
    }

    @Test fun everyPairingVector() {
        val vectors = fixture.getJSONArray("vectors")
        assertTrue(vectors.length() >= 3)
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            fun b(k: String) = v.getString(k).unhex()
            val keys = Pairing.derive(b("z"), b("pairingId"), b("pinC"), b("pinS"), b("cb"), b("ephC"), b("ephS"))
            assertEquals(v.getString("commitment"), Pairing.commitment(b("ephC")).hex())
            assertEquals(v.getString("sasBytes"), keys.sasBytes.hex())
            assertEquals(List(3) { v.getJSONArray("sas").getInt(it) }, keys.sas)
            assertEquals(v.getString("k"), keys.k.hex())
            assertEquals(v.getString("clientMac"), Pairing.clientMac(keys.k, b("pinC")).hex())
            assertEquals(v.getString("serverMac"), Pairing.serverMac(keys.k, b("pinS")).hex())
            assertTrue(Pairing.macEquals(Pairing.serverMac(keys.k, b("pinS")), b("serverMac")))
            assertFalse(Pairing.macEquals(Pairing.serverMac(keys.k, b("pinC")), b("serverMac")))
        }
    }

    @Test fun sasCoversItsRange() {
        assertEquals(listOf(1000, 1000, 1000), Pairing.sasNumbers(ByteArray(5)))
        assertEquals(listOf(9191, 9191, 9191), Pairing.sasNumbers(ByteArray(5) { 0xFF.toByte() }))
    }

    @Test fun ecdhAgreesThroughX963Encoding() {
        val c = Pairing.ephemeral()
        val s = Pairing.ephemeral()
        val ephC = Pairing.encodePoint(c.public as ECPublicKey)
        val ephS = Pairing.encodePoint(s.public as ECPublicKey)
        assertEquals(65, ephC.size)
        assertEquals(4.toByte(), ephC[0])
        val z1 = Pairing.agree(c.private, Pairing.decodePoint(ephS))
        val z2 = Pairing.agree(s.private, Pairing.decodePoint(ephC))
        assertEquals(32, z1.size)
        assertArrayEquals(z1, z2)
    }

    @Test fun ecdhVectorsWithRealKeys() {
        val cases = fixture.getJSONArray("ecdh")
        assertTrue(cases.length() >= 1)
        for (i in 0 until cases.length()) {
            val v = cases.getJSONObject(i)
            fun priv(k: String) = KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, v.getString(k).unhex()), Pairing.p256))
            assertEquals(v.getString("z"), Pairing.agree(priv("privC"), Pairing.decodePoint(v.getString("ephS").unhex())).hex())
            assertEquals(v.getString("z"), Pairing.agree(priv("privS"), Pairing.decodePoint(v.getString("ephC").unhex())).hex())
        }
    }

    @Test fun everyInvalidPointIsRejected() {
        val cases = fixture.getJSONArray("invalidPoints")
        assertTrue(cases.length() >= 9)
        for (i in 0 until cases.length()) {
            val v = cases.getJSONObject(i)
            val e = runCatching { Pairing.decodePoint(v.getString("hex").unhex()) }.exceptionOrNull()
            assertEquals(v.getString("name"), "malformed", (e as? ProtocolException)?.code)
        }
    }

    @Test fun rejectsBadPoints() {
        val good = Pairing.encodePoint(Pairing.ephemeral().public as ECPublicKey)
        val bad = listOf(
            good.copyOf(64),
            good.copyOf().also { it[0] = 2 },
            good.copyOf().also { it[64] = (it[64] + 1).toByte() }, // off the curve
            byteArrayOf(4) + ByteArray(64),
            byteArrayOf(4) + ByteArray(64) { 0xFF.toByte() }, // coordinates ≥ p
        )
        bad.forEach { p -> assertEquals("malformed", (runCatching { Pairing.decodePoint(p) }.exceptionOrNull() as ProtocolException).code) }
    }
}
