package link.tetherly

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.asExecutor
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import javax.net.ssl.SSLException

/** One authenticated TLS connection. */
interface Conn : Closeable {
    val input: InputStream
    val output: OutputStream
    val peerPin: ByteArray
    val localPin: ByteArray
    val channelBinding: ByteArray
}

fun interface Transport {
    /** Opens mutual TLS to [address]. [accept] runs inside certificate verification with the server pin; false aborts. */
    suspend fun open(address: HostAddress, accept: (pin: ByteArray) -> Boolean): Conn
}

interface VideoSink {
    fun configure(config: Frame.VideoConfig)

    /** Decodes or drops [frame]. Returns false when the decoder needs a keyframe (after a drop, error or reconfigure). */
    fun decode(frame: Frame.VideoFrame): Boolean
    fun stop()
}

/** Android services the session needs; faked in tests. Document URIs are passed as strings. */
/** Plays Mac sound (48 kHz s16le stereo). */
interface AudioIo {
    fun play(pcm: ByteArray)
    fun stop()
}

interface Platform {
    val video: VideoSink
    val audio: AudioIo
    fun setClipboard(text: String)
    fun openRead(uri: String): InputStream
    fun openWrite(uri: String): OutputStream
    fun delete(uri: String)
}

/** Runs a blocking socket call off the caller's thread. Cancellation closes [c], which unblocks the call. */
suspend fun <T> blocking(c: Closeable, block: () -> T): T = suspendCancellableCoroutine { cont ->
    cont.invokeOnCancellation { runCatching { c.close() } }
    Dispatchers.IO.asExecutor().execute { cont.resumeWith(runCatching(block)) }
}

data class Display(val id: Long, val width: Double, val height: Double, val scale: Double)

/** Mac pointer position, normalized over the streamed display (SPEC §5 `cursor`). */
data class Cursor(val x: Double, val y: Double)
/** [localCursor] false: the video carries the Mac's native pointer (all its shapes); the phone draws none. */
data class VideoSettings(val maxDimension: Int = 1920, val fps: Int = 60, val localCursor: Boolean = false)
data class FileOffer(val id: String, val name: String, val size: Long)
data class TransferUi(val name: String, val size: Long, val done: Long, val status: String, val active: Boolean)

sealed interface SessionState {
    data object Idle : SessionState
    data class Connecting(val address: HostAddress, val pairing: Boolean) : SessionState
    data class Pairing(val address: HostAddress, val host: String, val sas: List<Int>?, val confirmed: Boolean, val macApproved: Boolean) : SessionState
    data class Connected(val address: HostAddress, val host: String) : SessionState
    data class Reconnecting(val address: HostAddress, val host: String, val attempt: Int, val reason: String) : SessionState
    data class Failed(val address: HostAddress?, val message: String) : SessionState
}

fun backoffSeconds(attempt: Int) = minOf(30, 1 shl (attempt - 1).coerceIn(0, 5))

/**
 * Owns at most one Mac session: connect, pairing, the paired control loop, video and file connections, and
 * auto-reconnect. Public methods and all protocol state run on [scope]'s thread; only blocking IO hops to IO threads.
 * A generation counter stops a superseded attempt from publishing over a newer one.
 */
class SessionController(
    private val scope: CoroutineScope,
    private val transport: Transport,
    private val store: MacStore,
    private val platform: Platform,
    private val deviceName: String,
) {
    private val _state = MutableStateFlow<SessionState>(SessionState.Idle)
    val state: StateFlow<SessionState> = _state
    private val _macs = MutableStateFlow(store.load())
    val macs: StateFlow<List<PairedMac>> = _macs
    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice
    private val _display = MutableStateFlow<Display?>(null)
    val display: StateFlow<Display?> = _display
    private val _cursor = MutableStateFlow<Cursor?>(null)
    val cursor: StateFlow<Cursor?> = _cursor
    private val _videoSize = MutableStateFlow<Pair<Int, Int>?>(null)
    val videoSize: StateFlow<Pair<Int, Int>?> = _videoSize
    private val _macSound = MutableStateFlow(false)
    /** Whether Mac sound is wanted; kept across reconnects. */
    val macSound: StateFlow<Boolean> = _macSound
    private val _videoStopped = MutableStateFlow<String?>(null)
    /** Set when video stopped and won't restart by itself; the UI offers "Retry video". */
    val videoStopped: StateFlow<String?> = _videoStopped
    private val _videoSettings = MutableStateFlow(VideoSettings())
    val videoSettings: StateFlow<VideoSettings> = _videoSettings
    private val _offer = MutableStateFlow<FileOffer?>(null)
    val offer: StateFlow<FileOffer?> = _offer
    private val _outgoing = MutableStateFlow<TransferUi?>(null)
    val outgoing: StateFlow<TransferUi?> = _outgoing
    private val _incoming = MutableStateFlow<TransferUi?>(null)
    val incoming: StateFlow<TransferUi?> = _incoming

    private var job: Job? = null
    private var generation = 0L
    private var link: Link? = null

    private class Link(val conn: Conn, val queue: OutQueue, val scope: CoroutineScope) {
        val lock = ReentrantLock()
        var paired = false
        var pairing: PairingMachine? = null
        var videoBlocked = false
        var videoJob: Job? = null
        var audioJob: Job? = null
        @Volatile var videoRetries = 0
        var out: Outgoing? = null
        var inc: Incoming? = null

        fun write(m: JSONObject) {
            lock.lock()
            try { FrameWriter.writeJson(conn.output, m) } finally { lock.unlock() }
        }

        /** Best effort, used just before closing: a stalled writer must not hold up teardown. */
        fun tryWrite(m: JSONObject) {
            if (!lock.tryLock(500, TimeUnit.MILLISECONDS)) return
            try { runCatching { FrameWriter.writeJson(conn.output, m) } } finally { lock.unlock() }
        }
    }

    private class Outgoing(val id: String, val uri: String, val name: String, val size: Long) {
        var accepted = false
        var job: Job? = null
        var conn: Conn? = null
    }

    private class Incoming(val id: String, val uri: String, val name: String, val size: Long, val sink: OutputStream) {
        var job: Job? = null
        var conn: Conn? = null
    }

    private sealed interface End {
        class Fatal(val message: String) : End
        class Lost(val message: String) : End
        class Repaired(val host: String) : End
    }

    fun connect(input: String, pair: Boolean = false) {
        val address = HostAddress.parse(input) ?: run {
            stop()
            _state.value = SessionState.Failed(null, "Enter an address like 192.168.1.20, my-mac.local or a Tailscale name, optionally with :port.")
            return
        }
        connect(address, pair)
    }

    fun connect(address: HostAddress, pair: Boolean) = start(listOf(address), pair, null)

    /** SPEC §4a: pairs with the Mac from a QR link. Only a server whose pin equals the link's `k` is accepted. */
    fun pairFromLink(link: PairLink) {
        val pin = link.pin.hex()
        if (link.name.isNotEmpty() && store.load().any { it.hostName == link.name && it.pin != pin }) {
            stop()
            _state.value = SessionState.Failed(link.addresses.first(), IDENTITY_CHANGED)
            return
        }
        start(link.addresses, true, link.pin)
    }

    private fun start(candidates: List<HostAddress>, pair: Boolean, expectedPin: ByteArray?) {
        stop()
        val gen = generation
        _state.value = SessionState.Connecting(candidates.first(), pair)
        job = scope.launch { run(gen, candidates, pair, expectedPin) }
    }

    /** User-initiated: stops the session and any reconnecting. */
    fun disconnect() {
        stop()
        _state.value = SessionState.Idle
    }

    private fun stop() {
        generation++
        link?.conn?.close()
        link = null
        job?.cancel()
        job = null
        _notice.value = null
        _display.value = null
        _cursor.value = null
        _videoSize.value = null
        _videoStopped.value = null
        _offer.value = null
        platform.audio.stop()
        _outgoing.value = null
        _incoming.value = null
    }

    private fun publish(gen: Long, s: SessionState) {
        if (gen == generation) _state.value = s
    }

    fun forget(pin: String) = saveMacs(store.load().filter { it.pin != pin })

    private fun saveMacs(macs: List<PairedMac>) {
        store.save(macs)
        _macs.value = macs
    }

    fun showNotice(text: String) { _notice.value = text }
    fun dismissNotice() { _notice.value = null }

    // ---- connection lifecycle ----

    private suspend fun run(gen: Long, candidates: List<HostAddress>, pair: Boolean, qrPin: ByteArray?) {
        var pairIntent = pair
        var expectedPin = qrPin
        var tryAddresses = candidates
        var address = candidates.first()
        var host: String? = null // set once a session was (or is about to be) established: losses then reconnect
        var attempt = 0
        while (true) {
            val end = connectOnce(gen, tryAddresses, pairIntent, expectedPin, { address = it }) { host = it; attempt = 0 }
            when (end) {
                is End.Repaired -> {
                    // Reconnect as paired at the address that worked; the pin is now stored, so the QR pin is no longer needed.
                    pairIntent = false
                    expectedPin = null
                    tryAddresses = listOf(address)
                    host = end.host
                    publish(gen, SessionState.Connecting(address, false))
                }
                is End.Fatal -> { publish(gen, SessionState.Failed(address, end.message)); return }
                is End.Lost -> {
                    val h = host ?: run { publish(gen, SessionState.Failed(address, end.message)); return }
                    attempt++
                    publish(gen, SessionState.Reconnecting(address, h, attempt, end.message))
                    delay(backoffSeconds(attempt) * 1000L)
                }
            }
        }
    }

    private suspend fun connectOnce(
        gen: Long, candidates: List<HostAddress>, pairIntent: Boolean, expectedPin: ByteArray?,
        onAddress: (HostAddress) -> Unit, onSession: (String) -> Unit,
    ): End {
        val macs = store.load()
        var trust: Trust? = null
        var opened: Conn? = null
        var address = candidates.first()
        var qrMismatch = false
        var failure: End = End.Lost("No address to try.")
        for (a in candidates) {
            trust = null
            try {
                opened = transport.open(a) { pin ->
                    // A QR link names the Mac's key: anything else is refused inside the handshake, before any SAS exists.
                    if (expectedPin != null && !Pairing.macEquals(pin, expectedPin)) { qrMismatch = true; false }
                    else decideTrust(pin.hex(), a.toString(), macs, pairIntent).also { trust = it } !is Trust.Rejected
                }
                address = a
                break
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                (trust as? Trust.Rejected)?.let { return End.Fatal(it.message) }
                failure = End.Lost(explain(e))
            }
        }
        val conn = opened ?: return if (qrMismatch) End.Fatal(QR_MISMATCH) else failure
        onAddress(address)
        val t = trust
        if (gen != generation || t == null) {
            conn.close()
            if (t == null) return End.Fatal("The secure connection was not verified.")
            throw CancellationException()
        }
        var l: Link? = null
        try {
            return coroutineScope {
                val link = Link(conn, OutQueue(), this).also { l = it; this@SessionController.link = it }
                launch {
                    while (true) {
                        val m = link.queue.take()
                        blocking(conn) { link.write(m) }
                    }
                }
                launch {
                    var n = 0
                    while (true) {
                        delay(5_000)
                        if (!link.queue.offer(msg("ping", "n" to n++))) throw IOException("Connection stalled.")
                    }
                }
                val end = try {
                    control(gen, address, link, t, macs, pairIntent, onSession)
                } catch (e: ProtocolException) {
                    withContext(Dispatchers.IO) { link.tryWrite(msg("error", "code" to e.code, "message" to e.code)) }
                    if (e.code == "pairing_failed") End.Fatal(e.message ?: "Pairing failed.")
                    else End.Lost("The Mac sent an invalid message (${e.code}).")
                }
                coroutineContext.cancelChildren()
                end
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return End.Lost(explain(e))
        } finally {
            conn.close()
            if (link === l && l != null) link = null
            l?.let { withContext(NonCancellable) { endTransfers(it, "Connection lost. Transfer stopped.") } }
            platform.video.stop()
        }
    }

    private suspend fun control(
        gen: Long, address: HostAddress, l: Link, trust: Trust, macs: List<PairedMac>, pairIntent: Boolean, onSession: (String) -> Unit,
    ): End {
        val reader = FrameReader(l.conn.input, ConnKind.Control, Side.Server)
        val next: suspend () -> Frame.Json = { blocking(l.conn) { reader.read() } as Frame.Json }
        l.queue.offer(msg("hello", "versions" to JSONArray(listOf(PROTOCOL_VERSION)), "kind" to "control", "device" to deviceName.take(64)))
        val w = next()
        if (w.type == "error") return errorEnd(w.obj)
        if (w.type != "welcome") malformed("expected welcome")
        w.obj.int("version", PROTOCOL_VERSION..PROTOCOL_VERSION)
        val state = w.obj.str("state")
        if (state != "paired" && state != "pairing") malformed("bad welcome state")
        val host = w.obj.str("host", 64)
        val pairingId = if (state == "pairing") w.obj.bytes("pairingId", 16) else null
        return when (val o = checkWelcome(trust, state, host, macs, pairIntent)) {
            is WelcomeOutcome.Rejected -> End.Fatal(o.message)
            is WelcomeOutcome.Pair -> pair(gen, address, l, host, pairingId ?: malformed("pairing welcome without pairingId"), next)
            is WelcomeOutcome.Session -> {
                onSession(host)
                paired(gen, address, l, o.mac, host, next)
            }
        }
    }

    private fun errorEnd(o: JSONObject): End {
        val code = o.opt("code") as? String ?: "unknown"
        return if (code in TERMINAL) End.Fatal(explainCode(code)) else End.Lost(explainCode(code))
    }

    // ---- pairing (SPEC §4) ----

    private suspend fun pair(gen: Long, address: HostAddress, l: Link, host: String, pairingId: ByteArray, next: suspend () -> Frame.Json): End {
        val pin = l.conn.peerPin.hex()
        val m = PairingMachine(pairingId, l.conn.localPin, l.conn.peerPin, l.conn.channelBinding, persist = {
            saveMacs(store.load().filter { it.pin != pin } + PairedMac(host, pin, address.toString()))
        })
        l.pairing = m
        fun show() = publish(gen, SessionState.Pairing(address, host, m.sas, m.userConfirmed, m.serverConfirmed))
        show()
        l.queue.offer(m.commit())
        try {
            while (true) {
                val f = next()
                m.receive(f.type, f.obj)?.let { l.queue.offer(it) }
                if (m.step == PairingMachine.Step.Done) return End.Repaired(host)
                show()
            }
        } catch (e: PairingFailed) {
            e.reply?.let { r -> withContext(Dispatchers.IO) { l.tryWrite(r) } }
            return End.Fatal(e.message ?: "Pairing failed. Nothing was saved.")
        }
    }

    /** The user compared the codes and they match. */
    fun confirmPairing() {
        val l = link ?: return
        val m = l.pairing ?: return
        val reply = m.confirm() ?: return
        l.queue.offer(reply)
        val s = _state.value
        if (s is SessionState.Pairing) _state.value = s.copy(confirmed = true)
    }

    fun cancelPairing() {
        val l = link
        val m = l?.pairing ?: return disconnect()
        val gen = generation
        val reply = m.cancel()
        scope.launch {
            withContext(Dispatchers.IO) { l.tryWrite(reply) }
            if (gen == generation) disconnect()
        }
    }

    // ---- paired session (SPEC §5) ----

    private suspend fun paired(gen: Long, address: HostAddress, l: Link, mac: PairedMac, host: String, next: suspend () -> Frame.Json): End {
        saveMacs(store.load().map { if (it.pin == mac.pin) it.copy(hostName = host, address = address.toString()) else it })
        l.paired = true
        publish(gen, SessionState.Connected(address, host))
        l.queue.offer(videoStart())
        if (_macSound.value) l.queue.offer(msg("audio_start", "mac" to true))
        while (true) {
            val m = next()
            val o = m.obj
            when (m.type) {
                "ping" -> l.queue.offer(msg("pong", "n" to o.opt("n")))
                "pong" -> {}
                "display" -> {
                    val d = Display(o.long("id", 0L..0xFFFF_FFFFL), o.number("width"), o.number("height"), o.number("scale"))
                    if (d.width !in 1.0..100_000.0 || d.height !in 1.0..100_000.0 || d.scale !in 0.1..16.0) malformed("bad display")
                    _display.value = d
                }
                "host_info" -> {
                    val routes = parseRoutes(o)
                    saveMacs(store.load().map { if (it.pin == mac.pin) it.copy(routes = routes) else it })
                }
                "cursor" -> {
                    val x = o.number("x")
                    val y = o.number("y")
                    if (x !in 0.0..1.0 || y !in 0.0..1.0) malformed("bad cursor")
                    _cursor.value = Cursor(x, y)
                }
                "video_ticket" -> startVideo(address, l, o.bytes("ticket", 32))
                "audio_ticket" -> startAudio(address, l, o.bytes("ticket", 32))
                "clipboard" -> {
                    val text = o.str("text")
                    if (text.toByteArray(Charsets.UTF_8).size > MAX_CLIPBOARD_BYTES) malformed("clipboard too large")
                    platform.setClipboard(text)
                    _notice.value = if (text.isEmpty()) "The Mac clipboard has no text." else "Copied the Mac's clipboard to this phone."
                }
                "error" -> {
                    val code = o.opt("code") as? String ?: "unknown"
                    if (code in TERMINAL) return End.Fatal(explainCode(code))
                    if (code == "permission_screen_recording") {
                        // The Mac closes only the video connection; control stays up until the user retries.
                        l.videoBlocked = true
                        _videoStopped.value = explainCode(code)
                    } else {
                        _notice.value = explainCode(code)
                    }
                }
                "bye" -> return End.Fatal("The Mac ended the session.")
                "file_offer" -> onFileOffer(l, o)
                "file_accept" -> l.out?.takeIf { it.id == o.fileId() }?.let {
                    it.accepted = true
                    _outgoing.value = _outgoing.value?.copy(status = "Accepted. Starting…")
                }
                "file_reject" -> l.out?.takeIf { it.id == o.fileId() }?.let { abortOut(l, it, "The Mac declined the file.", null) }
                "file_ticket" -> onFileTicket(address, l, o.fileId(), o.bytes("ticket", 32))
                "file_cancel" -> {
                    val id = o.fileId()
                    l.out?.takeIf { it.id == id }?.let { abortOut(l, it, "Cancelled on the Mac.", null) }
                    l.inc?.takeIf { it.id == id }?.let { abortIn(l, it, "Cancelled on the Mac.", null) }
                    if (_offer.value?.id == id) _offer.value = null
                }
                "file_result" -> l.out?.takeIf { it.id == o.fileId() }?.let {
                    if (o.bool("ok")) finishOut(l, it, "Sent.")
                    else abortOut(l, it, "The Mac couldn't save the file.", null)
                }
                else -> malformed("${m.type} in a paired session")
            }
        }
    }

    private fun videoStart() = _videoSettings.value.let {
        msg("video_start", "maxDimension" to it.maxDimension, "fps" to it.fps, "cursor" to if (it.localCursor) "hidden" else "shown")
    }

    fun setVideoSettings(s: VideoSettings) {
        if (s == _videoSettings.value) return
        _videoSettings.value = s
        retryVideo()
    }

    /** Re-sends video_start, e.g. after the user granted Screen Recording on the Mac. */
    fun retryVideo() {
        val l = link?.takeIf { it.paired } ?: return
        l.videoBlocked = false
        l.videoRetries = 0
        _videoStopped.value = null
        l.queue.offer(videoStart())
    }

    private fun startVideo(address: HostAddress, l: Link, ticket: ByteArray) {
        l.videoJob?.cancel()
        l.videoJob = l.scope.launch {
            try {
                runVideo(address, l, ticket)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Fall through: the control session is still up, so ask for a fresh stream.
            }
            delay(1_000) // lets a permission error that explains the close arrive first
            val n = ++l.videoRetries
            if (l.videoBlocked) return@launch
            if (n > MAX_VIDEO_RETRIES) {
                _videoStopped.value = "Video stopped."
                return@launch
            }
            delay(backoffSeconds(n) * 1000L)
            if (!l.videoBlocked) l.queue.offer(videoStart())
        }
    }

    private suspend fun runVideo(address: HostAddress, l: Link, ticket: ByteArray) {
        val sessionPin = l.conn.peerPin
        val conn = transport.open(address) { it.contentEquals(sessionPin) }
        try {
            withContext(Dispatchers.IO) {
                val reader = FrameReader(conn.input, ConnKind.Video, Side.Server)
                openChannel(conn, reader, "video", ticket)
                while (true) {
                    when (val f = blocking(conn) { reader.read() }) {
                        is Frame.VideoConfig -> {
                            _videoSize.value = f.width to f.height
                            platform.video.configure(f)
                            l.videoRetries = 0
                            _videoStopped.value = null
                        }
                        is Frame.VideoFrame -> if (!platform.video.decode(f)) l.queue.offer(msg("keyframe"))
                        is Frame.Json -> if (f.type == "error") throw ProtocolException("video", explainCode(f.obj.opt("code") as? String ?: "")) else return@withContext
                        is Frame.FileChunk, is Frame.Audio -> malformed("unexpected frame on video")
                    }
                }
            }
        } finally {
            conn.close()
        }
    }

    /** hello/welcome on a ticketed video or file connection. */
    private suspend fun openChannel(conn: Conn, reader: FrameReader, kind: String, ticket: ByteArray) {
        blocking(conn) {
            FrameWriter.writeJson(conn.output, msg("hello", "versions" to JSONArray(listOf(PROTOCOL_VERSION)), "kind" to kind, "ticket" to b64(ticket)))
        }
        val w = blocking(conn) { reader.read() } as? Frame.Json ?: malformed("expected welcome")
        if (w.type == "error") throw IOException(explainCode(w.obj.opt("code") as? String ?: ""))
        if (w.type != "welcome") malformed("expected welcome")
        w.obj.int("version", PROTOCOL_VERSION..PROTOCOL_VERSION)
    }

    // ---- audio (SPEC §5) ----

    /** Turns Mac sound on or off. Remembered across reconnects. */
    fun setMacSound(on: Boolean) {
        _macSound.value = on
        requestAudio()
    }

    private fun requestAudio() {
        val l = link?.takeIf { it.paired } ?: return
        val mac = _macSound.value
        l.queue.offer(if (mac) msg("audio_start", "mac" to true) else msg("audio_stop"))
    }

    private fun startAudio(address: HostAddress, l: Link, ticket: ByteArray) {
        l.audioJob?.cancel()
        l.audioJob = l.scope.launch {
            val sessionPin = l.conn.peerPin
            val conn = try { transport.open(address) { it.contentEquals(sessionPin) } } catch (e: CancellationException) { throw e } catch (e: Exception) { return@launch }
            try {
                withContext(Dispatchers.IO) {
                    val reader = FrameReader(conn.input, ConnKind.Audio, Side.Server)
                    openChannel(conn, reader, "audio", ticket)
                    while (true) {
                        when (val f = blocking(conn) { reader.read() }) {
                            is Frame.Audio -> if (_macSound.value) platform.audio.play(f.pcm)
                            is Frame.Json -> return@withContext
                            else -> malformed("unexpected frame on audio")
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // The control session decides about reconnecting; audio just stops here.
            } finally {
                platform.audio.stop()
                conn.close()
            }
        }
    }

    // ---- input and clipboard ----

    /** Queues an input message if a paired session is live. Dropped if not connected or the queue is full. */
    fun send(m: JSONObject) {
        link?.takeIf { it.paired }?.queue?.offer(m)
    }

    fun typeText(text: String) = textChunks(text).forEach { send(msg("text", "text" to it)) }

    fun key(code: Int, modifiers: Set<KeyModifier> = emptySet()) =
        send(msg("key", "code" to code, "modifiers" to JSONArray(modifiers.map { it.wire })))

    fun sendClipboard(text: String?) {
        when {
            link?.paired != true -> _notice.value = "Not connected."
            text.isNullOrEmpty() -> _notice.value = "The phone's clipboard has no text."
            text.toByteArray(Charsets.UTF_8).size > MAX_CLIPBOARD_BYTES -> _notice.value = "Clipboard text is too large to send (limit 60 KB)."
            else -> { send(msg("clipboard_set", "text" to text)); _notice.value = "Sent the clipboard to the Mac." }
        }
    }

    fun requestClipboard() = send(msg("clipboard_get"))

    // ---- file transfer (SPEC §7) ----

    fun sendFile(uri: String, rawName: String, size: Long) {
        val l = link?.takeIf { it.paired } ?: return showNotice("Not connected.")
        if (l.out != null) return showNotice("A file is already being sent.")
        if (size !in 0..MAX_FILE_SIZE) return showNotice("Files over 4 GB can't be sent.")
        val o = Outgoing(newId(), uri, sanitizeFileName(rawName), size)
        l.out = o
        _outgoing.value = TransferUi(o.name, size, 0, "Waiting for the Mac to accept…", true)
        l.queue.offer(msg("file_offer", "id" to o.id, "name" to o.name, "size" to size))
    }

    fun cancelOutgoing() {
        val l = link ?: return
        val o = l.out ?: return
        abortOut(l, o, "Cancelled.", msg("file_cancel", "id" to o.id))
    }

    fun cancelIncoming() {
        val l = link ?: return
        val i = l.inc ?: return
        scope.launch { abortIn(l, i, "Cancelled.", msg("file_cancel", "id" to i.id)) }
    }

    fun dismissTransfers() {
        if (_outgoing.value?.active == false) _outgoing.value = null
        if (_incoming.value?.active == false) _incoming.value = null
    }

    /** The user answered a Mac file offer: [uri] is the document they created, or null if they declined. */
    fun answerOffer(uri: String?) {
        val o = _offer.value
        _offer.value = null
        val l = link?.takeIf { it.paired }
        if (o == null || l == null) {
            if (uri != null) scope.launch(Dispatchers.IO) { runCatching { platform.delete(uri) } }
            return
        }
        if (uri == null) {
            l.queue.offer(msg("file_reject", "id" to o.id, "reason" to "declined"))
            return
        }
        scope.launch {
            val sink = try {
                withContext(Dispatchers.IO) { platform.openWrite(uri) }
            } catch (e: Exception) {
                null
            }
            if (sink == null || link !== l) {
                withContext(Dispatchers.IO) { runCatching { sink?.close() }; runCatching { platform.delete(uri) } }
                l.queue.offer(msg("file_reject", "id" to o.id, "reason" to "failed"))
                if (sink == null) _notice.value = "Couldn't create the file on this phone."
                return@launch
            }
            l.inc = Incoming(o.id, uri, o.name, o.size, sink)
            _incoming.value = TransferUi(o.name, o.size, 0, "Waiting for the Mac…", true)
            l.queue.offer(msg("file_accept", "id" to o.id))
        }
    }

    private fun onFileOffer(l: Link, o: JSONObject) {
        val id = o.fileId()
        val name = o.str("name")
        if (name.toByteArray(Charsets.UTF_8).size > MAX_FILE_NAME_BYTES) malformed("file name too long")
        val size = o.long("size", 0..MAX_FILE_SIZE)
        if (l.inc != null || _offer.value != null) {
            l.queue.offer(msg("file_reject", "id" to id, "reason" to "busy"))
            return
        }
        _offer.value = FileOffer(id, sanitizeFileName(name), size)
    }

    private fun onFileTicket(address: HostAddress, l: Link, id: String, ticket: ByteArray) {
        l.out?.takeIf { it.id == id && it.accepted && it.job == null }?.let { o ->
            o.job = l.scope.launch {
                try {
                    sendData(address, l, o, ticket)
                    _outgoing.value = _outgoing.value?.copy(status = "Waiting for the Mac to verify…")
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    abortOut(l, o, failure(e), msg("file_cancel", "id" to o.id))
                }
            }
        }
        l.inc?.takeIf { it.id == id && it.job == null }?.let { i ->
            i.job = l.scope.launch {
                try {
                    receiveData(address, l, i, ticket)
                    if (l.inc !== i) return@launch
                    l.inc = null
                    i.conn?.close()
                    l.queue.offer(msg("file_result", "id" to i.id, "ok" to true))
                    _incoming.value = _incoming.value?.copy(status = "Saved.", active = false)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    abortIn(l, i, failure(e), msg("file_result", "id" to i.id, "ok" to false, "error" to "file_failed"))
                }
            }
        }
    }

    private suspend fun sendData(address: HostAddress, l: Link, o: Outgoing, ticket: ByteArray) {
        val sessionPin = l.conn.peerPin
        val conn = transport.open(address) { it.contentEquals(sessionPin) }
        o.conn = conn
        withContext(Dispatchers.IO) {
            openChannel(conn, FrameReader(conn.input, ConnKind.File, Side.Server), "file", ticket)
            val digest = MessageDigest.getInstance("SHA-256")
            val buf = ByteArray(FrameType.MAX_FILE_CHUNK)
            var sent = 0L
            platform.openRead(o.uri).use { input ->
                while (true) {
                    val n = readChunk(input, buf)
                    if (n == 0) break
                    sent += n
                    if (sent > o.size) throw IOException("The file changed while sending.")
                    digest.update(buf, 0, n)
                    // Blocking writes pace the file by send completion; control uses its own connection.
                    blocking(conn) { FrameWriter.write(conn.output, FrameType.FILE_CHUNK, buf, n) }
                    _outgoing.value = TransferUi(o.name, o.size, sent, "Sending…", true)
                }
            }
            if (sent != o.size) throw IOException("The file changed while sending.")
            blocking(conn) { FrameWriter.writeJson(conn.output, msg("file_end", "sha256" to b64(digest.digest()))) }
        }
    }

    private suspend fun receiveData(address: HostAddress, l: Link, i: Incoming, ticket: ByteArray) {
        val sessionPin = l.conn.peerPin
        val conn = transport.open(address) { it.contentEquals(sessionPin) }
        i.conn = conn
        val receiver = FileReceiver(i.sink, i.size)
        withContext(Dispatchers.IO) {
            val reader = FrameReader(conn.input, ConnKind.File, Side.Server)
            openChannel(conn, reader, "file", ticket)
            while (true) {
                when (val f = blocking(conn) { reader.read() }) {
                    is Frame.FileChunk -> {
                        receiver.write(f.data)
                        _incoming.value = TransferUi(i.name, i.size, receiver.received, "Receiving…", true)
                    }
                    is Frame.Json -> if (f.type == "file_end") {
                        receiver.finish(f.obj.bytes("sha256", 32))
                        break
                    } else throw IOException("The Mac stopped the transfer.")
                    else -> malformed("unexpected frame on file connection")
                }
            }
            i.sink.close()
        }
    }

    private fun finishOut(l: Link, o: Outgoing, status: String) {
        if (l.out !== o) return
        l.out = null
        o.conn?.close()
        _outgoing.value = _outgoing.value?.copy(status = status, active = false)
    }

    private fun abortOut(l: Link, o: Outgoing, status: String, tell: JSONObject?) {
        if (l.out !== o) return
        l.out = null
        o.job?.cancel()
        o.conn?.close()
        tell?.let { l.queue.offer(it) }
        _outgoing.value = _outgoing.value?.copy(status = status, active = false)
    }

    private suspend fun abortIn(l: Link, i: Incoming, status: String, tell: JSONObject?) {
        if (l.inc !== i) return
        l.inc = null
        i.job?.cancel()
        i.conn?.close()
        tell?.let { l.queue.offer(it) }
        _incoming.value = _incoming.value?.copy(status = status, active = false)
        // Partial data never survives: the document the user created is deleted.
        withContext(NonCancellable + Dispatchers.IO) {
            runCatching { i.sink.close() }
            runCatching { platform.delete(i.uri) }
        }
    }

    private suspend fun endTransfers(l: Link, status: String) {
        l.out?.let { abortOut(l, it, status, null) }
        l.inc?.let { abortIn(l, it, status, null) }
        if (link == null) _offer.value = null
    }

    private fun failure(e: Exception) = when (e) {
        is ProtocolException -> e.message ?: "Transfer failed."
        is IOException -> e.message?.takeIf { it.endsWith(".") } ?: "Transfer failed: connection problem."
        else -> "Transfer failed."
    }

    /** Fills [buf] unless the stream ends first, so chunks are full-size except the last. */
    private fun readChunk(input: InputStream, buf: ByteArray): Int {
        var n = 0
        while (n < buf.size) {
            val r = input.read(buf, n, buf.size - n)
            if (r < 0) break
            n += r
        }
        return n
    }

    private fun newId() = ByteArray(8).also { SecureRandom().nextBytes(it) }.hex()

    companion object {
        const val QR_MISMATCH = "This isn't the Mac from the QR code. Nothing was paired."

        /** Error codes after which reconnecting can't help. */
        val TERMINAL = setOf("unsupported_version", "not_paired", "pairing_closed", "pairing_failed", "busy", "revoked", "rate_limited")
        private const val MAX_VIDEO_RETRIES = 3

        fun explainCode(code: String): String = when (code) {
            "unsupported_version" -> "This app and the Mac app speak different protocol versions. Update both."
            "not_paired" -> "The Mac doesn't recognize this phone. Pair again."
            "pairing_closed" -> "Pairing isn't open on the Mac. Turn on pairing in Tetherly on the Mac, then tap Pair."
            "pairing_failed" -> "Pairing failed. Nothing was saved."
            "bad_ticket" -> "The Mac rejected a stream request."
            "frame_too_large", "malformed", "unknown_type" -> "The Mac rejected a message ($code). Make sure both apps are up to date."
            "rate_limited" -> "Too much input too fast; the Mac closed the session."
            "busy" -> "Another device is already connected to this Mac."
            "revoked" -> "This phone was revoked on the Mac. Forget the Mac here, then pair again."
            "permission_screen_recording" -> "Grant Screen Recording to Tetherly on the Mac (System Settings › Privacy & Security)."
            "permission_accessibility" -> "Grant Accessibility to Tetherly on the Mac (System Settings › Privacy & Security) to control it."
            "file_rejected" -> "The Mac rejected the file."
            "file_failed" -> "File transfer failed."
            "timeout" -> "The Mac timed out waiting for this phone."
            else -> "The Mac reported an error (${code.filter { it.isLetterOrDigit() || it == '_' }.take(32)})."
        }

        fun explain(e: Exception): String = when (e) {
            is UnknownHostException -> "Can't find that name. Check the spelling, or use the Mac's IP or Tailscale address."
            is ConnectException -> "Connection refused. Make sure Tetherly is running and hosting on that port."
            is SocketTimeoutException, is NoRouteToHostException -> "No response. Check both devices are on the same Wi-Fi or connected to Tailscale."
            is SecurityException -> "Network access is blocked for Tetherly in Android settings."
            is SSLException -> "The Mac refused the secure connection. If this phone isn't paired yet, turn on pairing on the Mac and tap Pair."
            is EOFException -> "The Mac closed the connection."
            is IOException -> "Connection lost."
            else -> "Couldn't connect (${e.javaClass.simpleName})."
        }
    }
}
