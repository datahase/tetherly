package link.tetherly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

class TrustTest {
    private val mac = PairedMac("Studio", "aa".repeat(32), "10.0.0.2:47800")
    private val macs = listOf(mac)

    @Test fun knownPinIsTrustedAtAnyAddress() {
        assertEquals(Trust.Known(mac), decideTrust(mac.pin, "100.64.0.9:47800", macs, pairIntent = false))
    }

    @Test fun storedAddressWithAnotherKeyIsNeverRepaired() {
        assertEquals(Trust.Rejected(IDENTITY_CHANGED), decideTrust("bb".repeat(32), mac.address, macs, pairIntent = false))
        assertEquals(Trust.Rejected(IDENTITY_CHANGED), decideTrust("bb".repeat(32), mac.address, macs, pairIntent = true))
    }

    @Test fun unknownMacNeedsAnExplicitPair() {
        assertTrue(decideTrust("bb".repeat(32), "10.0.0.3:47800", macs, pairIntent = false) is Trust.Rejected)
        assertEquals(Trust.NewPairing, decideTrust("bb".repeat(32), "10.0.0.3:47800", macs, pairIntent = true))
    }

    @Test fun welcomeRules() {
        val known = Trust.Known(mac)
        assertEquals(WelcomeOutcome.Session(mac), checkWelcome(known, "paired", "Studio", macs, false))
        assertTrue(checkWelcome(known, "pairing", "Studio", macs, false) is WelcomeOutcome.Rejected)
        assertEquals(WelcomeOutcome.Pair, checkWelcome(known, "pairing", "Studio", macs, true))
        val paired = checkWelcome(Trust.NewPairing, "paired", "Other", macs, true)
        assertEquals(WelcomeOutcome.Rejected(ALREADY_KNOWN), paired)
        // A known name with a new key is not silently replaced.
        assertEquals(WelcomeOutcome.Rejected(IDENTITY_CHANGED), checkWelcome(Trust.NewPairing, "pairing", "Studio", macs, true))
        assertEquals(WelcomeOutcome.Pair, checkWelcome(Trust.NewPairing, "pairing", "Other", macs, true))
    }

    @Test fun storeEncodingRoundTripsAndToleratesGarbage() {
        assertEquals(macs, decodeMacs(encodeMacs(macs)))
        assertEquals(emptyList<PairedMac>(), decodeMacs("{not json"))
        assertEquals(emptyList<PairedMac>(), decodeMacs(null))
    }

    @Test fun backoffDoublesToThirtySeconds() {
        assertEquals(listOf(1, 2, 4, 8, 16, 30, 30), (1..7).map(::backoffSeconds))
    }
}

class FileReceiverTest {
    private val data = ByteArray(1000) { it.toByte() }
    private val hash = MessageDigest.getInstance("SHA-256").digest(data)

    @Test fun acceptsExactSizeAndHash() {
        val sink = ByteArrayOutputStream()
        FileReceiver(sink, 1000).apply { write(data.copyOf(600)); write(data.copyOfRange(600, 1000)); finish(hash) }
        assertTrue(sink.toByteArray().contentEquals(data))
    }

    @Test fun rejectsDataBeyondTheOfferedSizeWithoutWritingIt() {
        val sink = ByteArrayOutputStream()
        val r = FileReceiver(sink, 999)
        val e = runCatching { r.write(data) }.exceptionOrNull() as ProtocolException
        assertEquals("file_failed", e.code)
        assertEquals(0, sink.size())
    }

    @Test fun rejectsHashMismatchAndShortFiles() {
        val r = FileReceiver(ByteArrayOutputStream(), 1000)
        r.write(data.copyOf().also { it[5] = 0x7F })
        assertTrue(runCatching { r.finish(hash) }.isFailure)
        val short = FileReceiver(ByteArrayOutputStream(), 1000)
        short.write(data.copyOf(10))
        assertTrue(runCatching { short.finish(hash) }.isFailure)
    }
}
