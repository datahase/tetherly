package link.tetherly

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import java.security.interfaces.ECPublicKey
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLHandshakeException

class SessionControllerTest {
    private val a = HostAddress("a.local", HostAddress.DEFAULT_PORT)
    private val b = HostAddress("b.local", HostAddress.DEFAULT_PORT)
    private val macPin = ByteArray(32) { 1 }
    private val otherPin = ByteArray(32) { 2 }

    /** Serves scripted Mac frames, then blocks until closed (or ends with EOF). Records what the phone sent. */
    private class FakeConn(script: List<JSONObject>, override val peerPin: ByteArray, eof: Boolean = false, waitForClientFramesBeforeLast: Int = 0) : Conn {
        private val closed = CountDownLatch(if (eof) 0 else 1)
        private val clientFrames = CountDownLatch(waitForClientFramesBeforeLast)
        private fun encoded(frames: List<JSONObject>) = ByteArrayInputStream(ByteArrayOutputStream().also { o -> frames.forEach { FrameWriter.writeJson(o, it) } }.toByteArray())
        private val data = encoded(if (waitForClientFramesBeforeLast > 0) script.dropLast(1) else script)
        private val lastFrame = encoded(if (waitForClientFramesBeforeLast > 0) script.takeLast(1) else emptyList())
        override val input = object : InputStream() {
            override fun read(): Int = ByteArray(1).let { if (read(it, 0, 1) < 0) -1 else it[0].toInt() and 0xFF }
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                val n = data.read(b, off, len)
                if (n > 0) return n
                check(clientFrames.await(5, TimeUnit.SECONDS)) { "Client did not finish the scripted handshake." }
                val last = lastFrame.read(b, off, len)
                if (last > 0) return last
                closed.await()
                throw EOFException()
            }
        }
        val bytes = ByteArrayOutputStream()
        override val output: OutputStream = object : OutputStream() {
            override fun write(b: Int) = bytes.write(b)
            override fun write(b: ByteArray, off: Int, len: Int) = bytes.write(b, off, len)
            override fun flush() = clientFrames.countDown()
        }
        override val localPin = ByteArray(32) { 3 }
        override val channelBinding = ByteArray(32) { 4 }
        override fun close() = closed.countDown()

        fun sent(): List<JSONObject> {
            val input = ByteArrayInputStream(bytes.toByteArray())
            val reader = FrameReader(input, ConnKind.Control, Side.Client)
            return buildList { while (input.available() > 0) add((reader.read() as Frame.Json).obj) }
        }
        fun sentTypes() = sent().map { it.getString("type") }
    }

    /** Each open waits on its own gate (a FakeConn or an exception), then runs the real pin check. */
    private class FakeTransport : Transport {
        val gates = mutableMapOf<String, CompletableDeferred<Any>>()
        val opened = mutableListOf<String>()
        val cancelled = mutableListOf<String>()
        var ignoreCancellation = false
        override suspend fun open(address: HostAddress, accept: (pin: ByteArray) -> Boolean): Conn {
            opened += address.host
            val gate = CompletableDeferred<Any>().also { gates[address.host] = it }
            val result = try {
                if (ignoreCancellation) withContext(NonCancellable) { gate.await() } else gate.await()
            } catch (e: kotlinx.coroutines.CancellationException) {
                cancelled += address.host
                throw e
            }
            if (result is Exception) throw result
            val conn = result as FakeConn
            if (!accept(conn.peerPin)) throw SSLHandshakeException("pin rejected")
            return conn
        }
    }

    private class MemoryStore(var macs: List<PairedMac> = emptyList()) : MacStore {
        override fun load() = macs
        override fun save(macs: List<PairedMac>) { this.macs = macs }
    }

    private object NoPlatform : Platform {
        override val video = object : VideoSink {
            override fun configure(config: Frame.VideoConfig) {}
            override fun decode(frame: Frame.VideoFrame) = true
            override fun stop() {}
        }
        override val audio = object : AudioIo {
            override fun play(pcm: ByteArray) {}
            override fun stop() {}
        }
        override fun setClipboard(text: String) {}
        override fun openRead(uri: String): InputStream = throw IOException()
        override fun openWrite(uri: String): OutputStream = throw IOException()
        override fun delete(uri: String) {}
    }

    private fun TestScope.controller(t: Transport, store: MacStore = MemoryStore()) =
        SessionController(backgroundScope, t, store, NoPlatform, "Test phone")

    /** The session reads on real IO threads, so poll until the state settles. */
    private fun TestScope.await(c: SessionController, what: String, pred: (SessionState) -> Boolean) {
        repeat(400) {
            runCurrent()
            if (pred(c.state.value)) return
            Thread.sleep(5)
        }
        fail("expected $what, state is ${c.state.value}")
    }

    private fun welcomePaired(host: String = "Studio") = msg("welcome", "version" to 1, "state" to "paired", "host" to host)
    private fun welcomePairing(host: String = "Studio") = msg("welcome", "version" to 1, "state" to "pairing", "host" to host, "pairingId" to b64(ByteArray(16)))
    private val studio = PairedMac("Studio", macPin.hex(), "old.local:47800")

    // ---- races (kept from the milestone-1 connection controller) ----

    @Test fun rapidSubmissionCancelsPreviousAttempt() = runTest {
        val t = FakeTransport(); val c = controller(t)
        c.connect("a.local"); runCurrent()
        c.connect("b.local"); runCurrent()
        assertEquals(listOf("a.local"), t.cancelled)
        assertEquals(SessionState.Connecting(b, false), c.state.value)
    }

    @Test fun cancelStopsAttemptAndReturnsToIdle() = runTest {
        val t = FakeTransport(); val c = controller(t)
        c.connect("a.local"); runCurrent()
        c.disconnect(); runCurrent()
        assertEquals(listOf("a.local"), t.cancelled)
        assertEquals(SessionState.Idle, c.state.value)
    }

    @Test fun staleCompletionCannotOverwriteNewerStatus() = runTest {
        val t = FakeTransport().apply { ignoreCancellation = true }; val c = controller(t)
        c.connect("a.local"); runCurrent()
        c.connect("b.local"); runCurrent()
        t.gates.getValue("a.local").complete(ConnectException()); runCurrent()
        assertEquals(SessionState.Connecting(b, false), c.state.value)

        c.disconnect()
        t.gates.getValue("b.local").complete(FakeConn(listOf(welcomePaired()), macPin)); runCurrent()
        assertEquals(SessionState.Idle, c.state.value)
    }

    @Test fun invalidInputCancelsInFlightAttemptWithoutConnecting() = runTest {
        val t = FakeTransport(); val c = controller(t)
        c.connect("a.local"); runCurrent()
        c.connect("host:"); runCurrent()
        assertEquals(listOf("a.local"), t.cancelled)
        assertEquals(listOf("a.local"), t.opened)
        assertTrue(c.state.value is SessionState.Failed)
    }

    @Test fun firstConnectFailureIsReportedNotRetried() = runTest {
        val t = FakeTransport(); val c = controller(t)
        c.connect("a.local"); runCurrent()
        t.gates.getValue("a.local").complete(ConnectException()); runCurrent()
        assertTrue((c.state.value as SessionState.Failed).message.startsWith("Connection refused"))
        advanceTimeBy(60_000); runCurrent()
        assertEquals(1, t.opened.size)
    }

    // ---- trust ----

    @Test fun unknownMacIsRefusedWithoutPair() = runTest {
        val t = FakeTransport(); val c = controller(t)
        c.connect("a.local"); runCurrent()
        t.gates.getValue("a.local").complete(FakeConn(listOf(welcomePaired()), otherPin)); runCurrent()
        assertTrue((c.state.value as SessionState.Failed).message.contains("isn't paired"))
    }

    @Test fun storedAddressAnsweringWithAnotherKeyIsAHardError() = runTest {
        val t = FakeTransport(); val c = controller(t, MemoryStore(listOf(studio.copy(address = a.toString()))))
        c.connect("a.local", pair = true); runCurrent()
        t.gates.getValue("a.local").complete(FakeConn(listOf(welcomePairing()), otherPin)); runCurrent()
        assertEquals(SessionState.Failed(a, IDENTITY_CHANGED), c.state.value)
    }

    @Test fun pairedSessionHelloVideoStartAndAddressUpdate() = runTest {
        val t = FakeTransport(); val store = MemoryStore(listOf(studio)); val c = controller(t, store)
        c.connect("a.local"); runCurrent()
        val conn = FakeConn(listOf(welcomePaired()), macPin)
        t.gates.getValue("a.local").complete(conn)
        await(c, "connected") { it is SessionState.Connected }
        assertEquals("a.local:47800", store.macs.single().address)
        repeat(400) { if (conn.sent().size < 2) { runCurrent(); Thread.sleep(5) } }
        val hello = conn.sent()[0]
        assertEquals(listOf("hello", "video_start"), conn.sentTypes().take(2))
        assertEquals("control", hello.getString("kind"))
        assertEquals(1, hello.getJSONArray("versions").getInt(0))
        assertEquals("Test phone", hello.getString("device"))
    }

    @Test fun cursorUpdatesAndOutOfRangeCursorIsMalformed() = runTest {
        val t = FakeTransport(); val c = controller(t, MemoryStore(listOf(studio)))
        c.connect("a.local"); runCurrent()
        val conn = FakeConn(listOf(welcomePaired(), msg("cursor", "x" to 0.25, "y" to 0.75), msg("cursor", "x" to 1.5, "y" to 0.5)), macPin)
        t.gates.getValue("a.local").complete(conn)
        await(c, "reconnecting after malformed cursor") { it is SessionState.Reconnecting }
        assertTrue(conn.sent().any { it.getString("type") == "error" && it.getString("code") == "malformed" })
    }

    @Test fun hostInfoStoresRoutesUnderThisMacsPin() = runTest {
        val t = FakeTransport(); val store = MemoryStore(listOf(studio)); val c = controller(t, store)
        c.connect("a.local"); runCurrent()
        val addresses = org.json.JSONArray(listOf(JSONObject().put("ip", "100.101.1.2").put("kind", "tailscale")))
        t.gates.getValue("a.local").complete(FakeConn(listOf(welcomePaired(), msg("host_info", "addresses" to addresses)), macPin))
        await(c, "connected") { it is SessionState.Connected }
        repeat(400) { if (store.macs.single().routes.isEmpty()) { runCurrent(); Thread.sleep(5) } }
        assertEquals(listOf(MacRoute("100.101.1.2", "tailscale")), store.macs.single().routes)
    }

    @Test fun validCursorIsPublished() = runTest {
        val t = FakeTransport(); val c = controller(t, MemoryStore(listOf(studio)))
        c.connect("a.local"); runCurrent()
        t.gates.getValue("a.local").complete(FakeConn(listOf(welcomePaired(), msg("cursor", "x" to 0.25, "y" to 0.75)), macPin))
        await(c, "connected") { it is SessionState.Connected }
        repeat(200) { if (c.cursor.value == null) { runCurrent(); Thread.sleep(5) } }
        assertEquals(Cursor(0.25, 0.75), c.cursor.value)
    }

    @Test fun macThatKnowsUsWithoutLocalRecordIsNotTrusted() = runTest {
        val t = FakeTransport(); val store = MemoryStore(); val c = controller(t, store)
        c.connect("a.local", pair = true); runCurrent()
        t.gates.getValue("a.local").complete(FakeConn(listOf(welcomePaired()), macPin))
        await(c, "failed") { it is SessionState.Failed }
        assertEquals(SessionState.Failed(a, ALREADY_KNOWN), c.state.value)
        assertTrue(store.macs.isEmpty())
    }

    // ---- reconnect ----

    @Test fun lossReconnectsWithBackoffAndNeverReplaysInput() = runTest {
        val t = FakeTransport(); val c = controller(t, MemoryStore(listOf(studio)))
        c.connect("a.local"); runCurrent()
        val first = FakeConn(listOf(welcomePaired()), macPin)
        t.gates.getValue("a.local").complete(first)
        await(c, "connected") { it is SessionState.Connected }
        c.send(msg("pointer", "dx" to 5, "dy" to 5))
        first.close() // network loss
        await(c, "reconnecting") { it is SessionState.Reconnecting }
        assertEquals(1, (c.state.value as SessionState.Reconnecting).attempt)
        c.send(msg("click", "button" to "left", "count" to 1)) // dropped: no live session

        advanceTimeBy(1_001); runCurrent()
        assertEquals(2, t.opened.size)
        val second = FakeConn(listOf(welcomePaired()), macPin)
        t.gates.getValue("a.local").complete(second)
        await(c, "connected again") { it is SessionState.Connected }
        repeat(400) { if (second.sent().size < 2) { runCurrent(); Thread.sleep(5) } }
        assertEquals(listOf("hello", "video_start"), second.sentTypes())
    }

    @Test fun disconnectStopsReconnecting() = runTest {
        val t = FakeTransport(); val c = controller(t, MemoryStore(listOf(studio)))
        c.connect("a.local"); runCurrent()
        t.gates.getValue("a.local").complete(FakeConn(listOf(welcomePaired()), macPin, eof = true))
        await(c, "reconnecting") { it is SessionState.Reconnecting }
        c.disconnect()
        advanceTimeBy(120_000); runCurrent()
        assertEquals(1, t.opened.size)
        assertEquals(SessionState.Idle, c.state.value)
    }

    @Test fun terminalErrorEndsWithoutReconnect() = runTest {
        val t = FakeTransport(); val c = controller(t, MemoryStore(listOf(studio)))
        c.connect("a.local"); runCurrent()
        t.gates.getValue("a.local").complete(FakeConn(listOf(welcomePaired(), msg("error", "code" to "revoked", "message" to "x")), macPin))
        await(c, "failed") { it is SessionState.Failed }
        assertTrue((c.state.value as SessionState.Failed).message.contains("revoked"))
        advanceTimeBy(120_000); runCurrent()
        assertEquals(1, t.opened.size)
    }

    // ---- pairing through the session ----

    @Test fun pairDoneBeforeConfirmationStoresNothing() = runTest {
        val t = FakeTransport(); val store = MemoryStore(); val c = controller(t, store)
        val ephS = Pairing.encodePoint(Pairing.ephemeral().public as ECPublicKey)
        c.connect("a.local", pair = true); runCurrent()
        // Deliver premature pair_done after hello/commit/reveal reach the wire,
        // so this checks rejection before confirmation without racing the writer.
        val conn = FakeConn(listOf(welcomePairing(), msg("pair_key", "key" to b64(ephS)), msg("pair_done")), macPin, waitForClientFramesBeforeLast = 3)
        t.gates.getValue("a.local").complete(conn)
        await(c, "failed") { it is SessionState.Failed }
        assertTrue(store.macs.isEmpty())
        assertEquals(listOf("hello", "pair_commit", "pair_reveal", "pair_cancel"), conn.sentTypes())
    }

    @Test fun qrLinkTriesAddressesInOrderAndRequiresItsPin() = runTest {
        val t = FakeTransport(); val c = controller(t)
        val link = PairLink("Studio", listOf(a, b), macPin)
        c.pairFromLink(link); runCurrent()
        t.gates.getValue("a.local").complete(ConnectException()); runCurrent()
        t.gates.getValue("b.local").complete(FakeConn(listOf(welcomePairing()), macPin))
        await(c, "pairing") { it is SessionState.Pairing }

        c.pairFromLink(link); runCurrent()
        t.gates.getValue("a.local").complete(FakeConn(listOf(welcomePairing()), otherPin)); runCurrent()
        t.gates.getValue("b.local").complete(FakeConn(listOf(welcomePairing()), otherPin)); runCurrent()
        assertEquals(SessionState.Failed(a, SessionController.QR_MISMATCH), c.state.value)
    }

    @Test fun qrLinkNeverReplacesAStoredNameWithAnotherKey() = runTest {
        val t = FakeTransport(); val c = controller(t, MemoryStore(listOf(studio)))
        c.pairFromLink(PairLink("Studio", listOf(a), otherPin)); runCurrent()
        assertEquals(SessionState.Failed(a, IDENTITY_CHANGED), c.state.value)
        assertTrue(t.opened.isEmpty())
    }
}
