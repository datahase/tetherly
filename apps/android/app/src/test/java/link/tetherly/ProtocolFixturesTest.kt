package link.tetherly

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

class ProtocolFixturesTest {
    private fun verdict(hex: String, kind: ConnKind, from: Side): String {
        val input = ByteArrayInputStream(hex.unhex())
        return try {
            val frame = FrameReader(input, kind, from).read()
            assertEquals("frame not fully consumed", 0, input.available())
            "ok:" + when (frame) {
                is Frame.Json -> FrameType.JSON
                is Frame.VideoConfig -> FrameType.VIDEO_CONFIG
                is Frame.VideoFrame -> FrameType.VIDEO_FRAME
                is Frame.FileChunk -> FrameType.FILE_CHUNK
                is Frame.Audio -> FrameType.MAC_AUDIO
            }
        } catch (e: ProtocolException) {
            e.code
        }
    }

    @Test fun everyFrameCaseInItsRole() {
        val cases = JSONArray(fixture("frames.json"))
        assertTrue(cases.length() >= 25)
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val kind = ConnKind.entries.single { it.wire == c.getString("kind") }
            val sides = when (c.getString("dir")) {
                "s2c" -> listOf(Side.Server)
                "c2s" -> listOf(Side.Client)
                else -> Side.entries
            }
            for (side in sides) assertEquals("${c.getString("name")} from $side", c.getString("expect"), verdict(c.getString("hex"), kind, side))
        }
    }

    @Test fun lengthIsCheckedBeforeReadingThePayload() {
        // A 4 GiB claim with nothing behind it must fail on the length alone, not by trying to read or allocate.
        assertEquals("frame_too_large", verdict("ffffffff", ConnKind.Video, Side.Server))
    }

    @Test fun messageTypesAreAllowlistedPerDirection() {
        fun json(s: String) = ByteArrayOutputStream().also { FrameWriter.writeJson(it, org.json.JSONObject(s)) }.toByteArray().hex()
        assertEquals("unknown_type", verdict(json("""{"type":"pointer","dx":1,"dy":1}"""), ConnKind.Control, Side.Server))
        assertEquals("unknown_type", verdict(json("""{"type":"shell","cmd":"rm"}"""), ConnKind.Control, Side.Server))
        assertEquals("unknown_type", verdict(json("""{"type":"display","id":1}"""), ConnKind.Video, Side.Server))
        assertEquals("ok:1", verdict(json("""{"type":"welcome","version":1}"""), ConnKind.File, Side.Server))
    }

    @Test fun writerRoundTripsThroughReader() {
        val out = ByteArrayOutputStream()
        FrameWriter.write(out, FrameType.FILE_CHUNK, ByteArray(10) { it.toByte() }, 4)
        val f = FrameReader(ByteArrayInputStream(out.toByteArray()), ConnKind.File, Side.Client).read() as Frame.FileChunk
        assertEquals(listOf<Byte>(0, 1, 2, 3), f.data.toList())
    }

    @Test fun strictFieldReaders() {
        val o = org.json.JSONObject("""{"a":"1","n":5,"f":1.5,"big":70000,"t":"AAEC","id":"0123456789abcdef"}""")
        assertEquals("malformed", runCatching { o.int("a", 0..10) }.exceptionOrNull().let { (it as ProtocolException).code })
        assertEquals(5, o.int("n", 0..10))
        assertTrue(runCatching { o.int("f", 0..10) }.isFailure)
        assertTrue(runCatching { o.int("big", 0..65535) }.isFailure)
        assertEquals(3, o.bytes("t", 3).size)
        assertTrue(runCatching { o.bytes("t", 32) }.isFailure)
        assertEquals("0123456789abcdef", o.fileId())
    }

    @Test fun everyFileNameCase() {
        val cases = JSONArray(fixture("filenames.json"))
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            assertEquals(c.getString("raw"), c.getString("sanitized"), sanitizeFileName(c.getString("raw")))
        }
    }

    @Test fun sanitizerNeverSplitsACharacter() {
        val name = sanitizeFileName("😀".repeat(100)) // 4 bytes each
        assertEquals(63, name.codePointCount(0, name.length))
        assertTrue(name.toByteArray().size <= 255)
    }

    @Test fun textChunksStayWithinLimitAndKeepSurrogatePairs() {
        val text = "a" + "😀".repeat(1000)
        val chunks = textChunks(text)
        assertEquals(text, chunks.joinToString(""))
        assertTrue(chunks.all { it.length in 1..1000 && !it.last().isHighSurrogate() && !it.first().isLowSurrogate() })
    }
}
