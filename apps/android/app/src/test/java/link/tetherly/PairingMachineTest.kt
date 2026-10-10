package link.tetherly

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey
import java.util.Base64

class PairingMachineTest {
    private fun rnd(n: Int) = ByteArray(n).also { SecureRandom().nextBytes(it) }
    private val pairingId = rnd(16)
    private val pinC = rnd(32)
    private val pinS = rnd(32)
    private val cb = rnd(32)
    private var stored = 0
    private val phone = PairingMachine(pairingId, pinC, pinS, cb, persist = { stored++ })

    /** The Mac's side, built only from the SPEC math, with the pins and channel binding it observes. */
    private inner class Mac(val pinC: ByteArray = this@PairingMachineTest.pinC, val cb: ByteArray = this@PairingMachineTest.cb) {
        val eph = Pairing.ephemeral()
        val ephS = Pairing.encodePoint(eph.public as ECPublicKey)
        lateinit var commitment: ByteArray
        lateinit var keys: Pairing.Keys

        fun key(commit: JSONObject): JSONObject {
            commitment = b(commit, "commitment")
            return msg("pair_key", "key" to b64(ephS))
        }

        fun reveal(m: JSONObject) {
            val ephC = b(m, "key")
            assertTrue(Pairing.macEquals(Pairing.sha256(ephC), commitment))
            keys = Pairing.derive(Pairing.agree(eph.private, Pairing.decodePoint(ephC)), pairingId, pinC, pinS, cb, ephC, ephS)
        }

        fun confirm() = msg("pair_confirm", "mac" to b64(Pairing.serverMac(keys.k, pinS)))
        fun clientMacOk(m: JSONObject) = Pairing.macEquals(b(m, "mac"), Pairing.clientMac(keys.k, pinC))
    }

    private fun b(m: JSONObject, k: String) = Base64.getDecoder().decode(m.getString(k))
    private fun send(m: JSONObject) = phone.receive(m.getString("type"), m)
    private fun failure(block: () -> Unit) = runCatching(block).exceptionOrNull() as PairingFailed

    private fun toConfirmations(mac: Mac = Mac()): Mac {
        mac.reveal(send(mac.key(phone.commit()))!!)
        return mac
    }

    @Test fun happyPathWithEitherConfirmationFirst() {
        for (userFirst in listOf(true, false)) {
            stored = 0
            val p = PairingMachine(pairingId, pinC, pinS, cb, persist = { stored++ })
            val mac = Mac()
            mac.reveal(p.receive("pair_key", mac.key(p.commit()))!!)
            assertEquals(mac.keys.sas, p.sas)
            if (userFirst) {
                assertTrue(mac.clientMacOk(p.confirm()!!))
                assertNull(p.receive("pair_confirm", mac.confirm()))
            } else {
                assertNull(p.receive("pair_confirm", mac.confirm()))
                assertTrue(mac.clientMacOk(p.confirm()!!))
            }
            assertEquals(PairingMachine.Step.AwaitDone, p.step)
            assertEquals(0, stored)
            p.receive("pair_done", msg("pair_done"))
            assertEquals(PairingMachine.Step.Done, p.step)
            assertEquals(1, stored)
        }
    }

    @Test fun duplicatePairKeyFails() {
        val mac = toConfirmations()
        val e = failure { send(msg("pair_key", "key" to b64(mac.ephS))) }
        assertEquals("pair_cancel", e.reply?.getString("type"))
        assertEquals(0, stored)
    }

    @Test fun confirmBeforeKeyFails() {
        phone.commit()
        assertEquals("pair_cancel", failure { send(msg("pair_confirm", "mac" to b64(ByteArray(32)))) }.reply?.getString("type"))
        assertNull(phone.confirm())
    }

    @Test fun badServerMacFailsWithPairingFailed() {
        toConfirmations()
        val e = failure { send(msg("pair_confirm", "mac" to b64(ByteArray(32)))) }
        assertEquals("pairing_failed", e.reply?.getString("code"))
        assertEquals(PairingMachine.Step.Failed, phone.step)
        assertEquals(0, stored)
    }

    @Test fun serverConfirmAcceptedOnce() {
        val mac = toConfirmations()
        send(mac.confirm())
        failure { send(mac.confirm()) }
        assertEquals(0, stored)
    }

    @Test fun doneBeforeBothConfirmationsFails() {
        val mac = toConfirmations()
        phone.confirm()
        failure { send(msg("pair_done")) } // user confirmed, server hasn't
        val p = PairingMachine(pairingId, pinC, pinS, cb, persist = { stored++ })
        val m2 = Mac()
        m2.reveal(p.receive("pair_key", m2.key(p.commit()))!!)
        p.receive("pair_confirm", m2.confirm())
        runCatching { p.receive("pair_done", msg("pair_done")) }.also { assertTrue(it.exceptionOrNull() is PairingFailed) } // server confirmed, user hasn't
        assertEquals(0, stored)
        assertTrue(mac.keys.k.isNotEmpty())
    }

    @Test fun nonPairingMessagesAreFatalButHeartbeatsAreNot() {
        toConfirmations()
        assertEquals("pong", send(msg("ping", "n" to 4))?.getString("type"))
        assertNull(send(msg("pong", "n" to 1)))
        assertEquals("pair_cancel", failure { send(msg("display", "id" to 1)) }.reply?.getString("type"))
    }

    @Test fun invalidServerKeyFails() {
        phone.commit()
        failure { send(msg("pair_key", "key" to b64(byteArrayOf(4) + ByteArray(64)))) }
        assertEquals(0, stored)
    }

    @Test fun cancelInEveryStateStoresNothing() {
        fun fresh() = PairingMachine(pairingId, pinC, pinS, cb, persist = { stored++ })
        val states = listOf<(PairingMachine) -> Unit>(
            { it.commit() },
            { p -> Mac().also { it.reveal(p.receive("pair_key", it.key(p.commit()))!!) } },
            { p -> Mac().also { it.reveal(p.receive("pair_key", it.key(p.commit()))!!); p.confirm() } },
            { p -> Mac().also { it.reveal(p.receive("pair_key", it.key(p.commit()))!!); p.confirm(); p.receive("pair_confirm", it.confirm()) } },
        )
        for (reach in states) {
            val p = fresh()
            reach(p)
            assertEquals("pair_cancel", p.cancel().getString("type"))
            assertTrue(runCatching { p.receive("pair_done", msg("pair_done")) }.exceptionOrNull() is PairingFailed)
        }
        val macCancels = fresh().also { states[2](it) }
        assertTrue(runCatching { macCancels.receive("pair_cancel", msg("pair_cancel")) }.exceptionOrNull() is PairingFailed)
        assertEquals(0, stored)
    }

    @Test fun manInTheMiddleSeesDifferentCodes() {
        // Each side sees a different TLS session (channel binding) and a different peer pin when a relay sits between them.
        listOf(Mac(cb = rnd(32)), Mac(pinC = rnd(32))).forEach { mac ->
            val p = PairingMachine(pairingId, pinC, pinS, cb, persist = { stored++ })
            mac.reveal(p.receive("pair_key", mac.key(p.commit()))!!)
            assertFalse(mac.keys.sas == p.sas)
            assertTrue(runCatching { p.receive("pair_confirm", mac.confirm()) }.exceptionOrNull() is PairingFailed)
        }
        assertEquals(0, stored)
    }
}
