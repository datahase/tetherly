package link.tetherly

import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.Base64

/** Wire protocol v1 (protocol/SPEC.md). Pure JVM code: no android.* imports, so it runs in unit tests. */
const val PROTOCOL_VERSION = 1

enum class ConnKind(val wire: String, val maxLength: Int) {
    Control("control", 65_536), Video("video", 4_194_304), File("file", 262_145), Audio("audio", 65_536)
}

/** Who sent a frame. Android receives from [Server]; the fixtures' "c2s" cases model the Mac receiving from [Client]. */
enum class Side { Client, Server }

/** A SPEC §8 error code plus a local description. Fatal for the connection that raised it. */
class ProtocolException(val code: String, message: String = code) : IOException(message)

fun malformed(why: String): Nothing = throw ProtocolException("malformed", why)

object FrameType {
    const val JSON = 0x01
    const val VIDEO_CONFIG = 0x10
    const val VIDEO_FRAME = 0x11
    const val FILE_CHUNK = 0x20
    const val MAC_AUDIO = 0x30
    const val MAX_FILE_CHUNK = 262_144
    const val MAX_AUDIO_PCM = 16_384

    fun maxLength(type: Int) = when (type) {
        JSON -> 65_536
        VIDEO_CONFIG -> 4_096
        VIDEO_FRAME -> 4_194_304
        MAC_AUDIO -> 16_393
        else -> 262_145
    }
}

sealed interface Frame {
    class Json(val type: String, val obj: JSONObject) : Frame
    class VideoConfig(val width: Int, val height: Int, val sps: ByteArray, val pps: ByteArray) : Frame {
        fun sameAs(o: VideoConfig) = width == o.width && height == o.height && sps.contentEquals(o.sps) && pps.contentEquals(o.pps)
    }
    class VideoFrame(val ptsMicros: Long, val keyframe: Boolean, val data: ByteArray) : Frame
    class FileChunk(val data: ByteArray) : Frame
    /** Mac sound: 48 kHz s16le stereo PCM. */
    class Audio(val ptsMicros: Long, val pcm: ByteArray) : Frame
}

/** The dispatcher allowlist: which frame types and JSON message types each kind accepts from each side. */
object Allowlist {
    private val controlFromClient = setOf(
        "hello", "ping", "pong", "pair_commit", "pair_reveal", "pair_confirm", "pair_cancel",
        "video_start", "video_stop", "keyframe", "pointer", "pointer_abs", "button", "click", "scroll", "key", "text",
        "modifier", "audio_start", "audio_stop",
        "clipboard_set", "clipboard_get", "file_offer", "file_accept", "file_reject", "file_cancel", "file_result", "error",
    )
    // "ping" from the Mac is not in the SPEC table; it is accepted (and answered) because rejecting it would be fatal.
    private val controlFromServer = setOf(
        "welcome", "ping", "pong", "pair_key", "pair_confirm", "pair_done", "pair_cancel", "display", "cursor", "host_info", "video_ticket", "audio_ticket", "clipboard",
        "file_offer", "file_accept", "file_reject", "file_ticket", "file_cancel", "file_result", "error", "bye",
    )

    fun binaryTypes(kind: ConnKind, from: Side): Set<Int> = when (kind) {
        ConnKind.Control -> emptySet()
        ConnKind.Video -> if (from == Side.Server) setOf(FrameType.VIDEO_CONFIG, FrameType.VIDEO_FRAME) else emptySet()
        ConnKind.File -> setOf(FrameType.FILE_CHUNK)
        ConnKind.Audio -> if (from == Side.Server) setOf(FrameType.MAC_AUDIO) else emptySet()
    }

    fun messages(kind: ConnKind, from: Side): Set<String> = when (kind) {
        ConnKind.Control -> if (from == Side.Client) controlFromClient else controlFromServer
        ConnKind.Video -> if (from == Side.Client) setOf("hello", "error") else setOf("welcome", "error", "bye")
        ConnKind.File -> if (from == Side.Client) setOf("hello", "file_end", "error") else setOf("welcome", "file_end", "error", "bye")
        ConnKind.Audio -> if (from == Side.Client) setOf("hello", "error") else setOf("welcome", "error", "bye")
    }
}

/** Reads frames for one connection kind, validating length before allocating and type against the allowlist. */
class FrameReader(private val input: InputStream, private val kind: ConnKind, private val from: Side) {
    private val binary = Allowlist.binaryTypes(kind, from)
    private val messages = Allowlist.messages(kind, from)

    fun read(): Frame {
        val header = ByteArray(5)
        readFully(header, 0, 4)
        val length = ByteBuffer.wrap(header, 0, 4).int.toLong() and 0xFFFF_FFFFL
        if (length == 0L) malformed("zero-length frame")
        if (length > kind.maxLength) throw ProtocolException("frame_too_large", "frame of $length bytes on ${kind.wire}")
        readFully(header, 4, 1)
        val type = header[4].toInt() and 0xFF
        if (type != FrameType.JSON && type !in binary) throw ProtocolException("unknown_type", "frame type $type on ${kind.wire}")
        if (length > FrameType.maxLength(type)) throw ProtocolException("frame_too_large", "type $type of $length bytes")
        val payload = ByteArray((length - 1).toInt())
        readFully(payload, 0, payload.size)
        return when (type) {
            FrameType.JSON -> parseJson(payload, messages)
            FrameType.VIDEO_CONFIG -> parseVideoConfig(payload)
            FrameType.VIDEO_FRAME -> parseVideoFrame(payload)
            FrameType.MAC_AUDIO -> parseAudio(payload)
            else -> if (payload.isEmpty()) malformed("empty file chunk") else Frame.FileChunk(payload)
        }
    }

    private fun readFully(b: ByteArray, off: Int, len: Int) {
        var n = 0
        while (n < len) {
            val r = input.read(b, off + n, len - n)
            if (r < 0) throw EOFException()
            n += r
        }
    }

    companion object {
        /** `ptsMicros:u64be pcm`, where pcm is whole 4-byte stereo frames. */
        fun parseAudio(payload: ByteArray): Frame.Audio {
            if (payload.size < 8) malformed("short audio frame")
            val pcm = payload.copyOfRange(8, payload.size)
            if (pcm.isEmpty() || pcm.size % 4 != 0) malformed("partial audio frame")
            return Frame.Audio(ByteBuffer.wrap(payload, 0, 8).long, pcm)
        }

        fun parseJson(payload: ByteArray, allowed: Set<String>): Frame.Json {
            val text = try {
                Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(payload)).toString()
            } catch (e: CharacterCodingException) {
                malformed("invalid UTF-8")
            }
            val obj = try {
                val tokener = JSONTokener(text)
                val value = tokener.nextValue()
                if (tokener.nextClean() != 0.toChar()) malformed("trailing data after JSON")
                value as? JSONObject ?: malformed("JSON is not an object")
            } catch (e: JSONException) {
                malformed("invalid JSON")
            }
            val type = obj.opt("type") as? String ?: malformed("missing string type")
            if (type !in allowed) throw ProtocolException("unknown_type", "message type $type")
            return Frame.Json(type, obj)
        }

        fun parseVideoConfig(p: ByteArray): Frame.VideoConfig {
            val b = ByteBuffer.wrap(p)
            if (b.remaining() < 6) malformed("short video config")
            val width = b.short.toInt() and 0xFFFF
            val height = b.short.toInt() and 0xFFFF
            if (width !in 16..8192 || height !in 16..8192) malformed("video size out of range")
            val sps = lengthPrefixed(b)
            val pps = lengthPrefixed(b)
            if (b.hasRemaining()) malformed("video config lengths don't fill the payload")
            return Frame.VideoConfig(width, height, sps, pps)
        }

        private fun lengthPrefixed(b: ByteBuffer): ByteArray {
            if (b.remaining() < 2) malformed("short video config")
            val len = b.short.toInt() and 0xFFFF
            if (len == 0 || len > b.remaining()) malformed("bad SPS/PPS length")
            return ByteArray(len).also { b.get(it) }
        }

        fun parseVideoFrame(p: ByteArray): Frame.VideoFrame {
            if (p.size < 10) malformed("video frame without data")
            val b = ByteBuffer.wrap(p)
            val pts = b.long
            val flags = b.get().toInt() and 0xFF
            if (flags and 0xFE != 0) malformed("reserved video flags set")
            return Frame.VideoFrame(pts, flags == 1, p.copyOfRange(9, p.size))
        }
    }
}

object FrameWriter {
    fun write(out: OutputStream, type: Int, payload: ByteArray, size: Int = payload.size) {
        val length = size + 1
        require(length <= FrameType.maxLength(type)) { "outgoing frame too large" }
        // One write per frame: on TLS each write becomes a record, so header and payload go out together.
        val buf = ByteBuffer.allocate(4 + length).putInt(length).put(type.toByte()).put(payload, 0, size)
        out.write(buf.array())
        out.flush()
    }

    fun writeJson(out: OutputStream, msg: JSONObject) = write(out, FrameType.JSON, msg.toString().toByteArray(Charsets.UTF_8))
}

fun msg(type: String, vararg fields: Pair<String, Any?>): JSONObject =
    JSONObject().put("type", type).apply { fields.forEach { (k, v) -> put(k, v) } }

// Strict field readers for received messages; anything off-spec is `malformed`.
fun JSONObject.str(key: String, maxLength: Int = Int.MAX_VALUE): String {
    val v = opt(key) as? String ?: malformed("$key is not a string")
    if (v.length > maxLength) malformed("$key too long")
    return v
}

fun JSONObject.long(key: String, range: LongRange): Long {
    val v = when (val n = opt(key)) {
        is Int -> n.toLong()
        is Long -> n
        is Double -> if (n == Math.rint(n) && kotlin.math.abs(n) < 9.0e15) n.toLong() else malformed("$key is not an integer")
        else -> malformed("$key is not a number")
    }
    if (v !in range) malformed("$key out of range")
    return v
}

fun JSONObject.int(key: String, range: IntRange): Int = long(key, range.first.toLong()..range.last.toLong()).toInt()

fun JSONObject.number(key: String): Double {
    val v = (opt(key) as? Number)?.toDouble() ?: malformed("$key is not a number")
    if (!v.isFinite()) malformed("$key is not finite")
    return v
}

fun JSONObject.bool(key: String): Boolean = opt(key) as? Boolean ?: malformed("$key is not a boolean")

fun JSONObject.bytes(key: String, size: Int): ByteArray {
    val v = try { Base64.getDecoder().decode(str(key)) } catch (e: IllegalArgumentException) { malformed("$key is not base64") }
    if (v.size != size) malformed("$key has the wrong length")
    return v
}

fun JSONObject.fileId(): String {
    val id = str("id")
    if (id.length != 16 || !id.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) malformed("bad file id")
    return id
}

fun b64(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }
fun String.unhex(): ByteArray = chunked(2).map { it.toInt(16).toByte() }.toByteArray()

const val MAX_CLIPBOARD_BYTES = 60_000
const val MAX_FILE_SIZE = 4L * 1024 * 1024 * 1024
const val MAX_FILE_NAME_BYTES = 255

/** SPEC §7: last path component, no control chars or `/ \ :`, no leading dots, ≤255 UTF-8 bytes, never empty. */
fun sanitizeFileName(raw: String): String {
    val last = raw.substringAfterLast('/').substringAfterLast('\\')
    val cleaned = last.filter { it.code >= 0x20 && it.code != 0x7F && it != ':' }.trimStart('.')
    val out = StringBuilder()
    var bytes = 0
    var i = 0
    while (i < cleaned.length) {
        val cp = cleaned.codePointAt(i)
        val n = String(Character.toChars(cp)).toByteArray(Charsets.UTF_8).size
        if (bytes + n > MAX_FILE_NAME_BYTES) break
        out.appendCodePoint(cp)
        bytes += n
        i += Character.charCount(cp)
    }
    return out.ifEmpty { "file" }.toString()
}

/** Splits text into SPEC `text` messages of at most 1000 UTF-16 units without breaking surrogate pairs. */
fun textChunks(text: String, max: Int = 1000): List<String> {
    val chunks = mutableListOf<String>()
    var start = 0
    while (start < text.length) {
        var end = minOf(start + max, text.length)
        if (end < text.length && Character.isHighSurrogate(text[end - 1])) end--
        chunks += text.substring(start, end)
        start = end
    }
    return chunks
}
