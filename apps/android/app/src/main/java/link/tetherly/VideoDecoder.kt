package link.tetherly

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue

/**
 * H.264 to a Surface with MediaCodec in async mode. Output buffers render as soon as they arrive; input is never
 * queued here: if the codec has no free input buffer the frame is dropped and the stream waits for a keyframe.
 * All methods are synchronized; codec callbacks run on a private HandlerThread.
 */
class VideoDecoder : VideoSink {
    private var surface: Surface? = null
    private var config: Frame.VideoConfig? = null
    @Volatile private var codec: MediaCodec? = null
    private var thread: HandlerThread? = null
    private val freeInputs = LinkedBlockingQueue<Int>()
    private var waitingForKey = true
    private var requestKey = false
    @Volatile private var failed = false

    @Synchronized
    fun setSurface(s: Surface?) {
        release()
        surface = s
        start()
    }

    @Synchronized
    override fun configure(config: Frame.VideoConfig) {
        if (codec != null && this.config?.sameAs(config) == true) return
        this.config = config
        release()
        start()
    }

    @Synchronized
    override fun decode(frame: Frame.VideoFrame): Boolean {
        if (failed) { release(); start() }
        val c = codec
        if (c == null) {
            waitingForKey = true
            return true // no surface yet; start() requests a keyframe once there is one
        }
        if (waitingForKey && !frame.keyframe) return takeRequest()
        val index = freeInputs.poll()
        if (index == null) {
            waitingForKey = true
            requestKey = true
            return takeRequest()
        }
        try {
            val buf = c.getInputBuffer(index) ?: error("no input buffer")
            if (frame.data.size > buf.capacity()) error("frame larger than input buffer")
            buf.clear()
            buf.put(frame.data)
            c.queueInputBuffer(index, 0, frame.data.size, frame.ptsMicros, if (frame.keyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
            waitingForKey = false
        } catch (e: Exception) {
            failed = true
            waitingForKey = true
            requestKey = true
        }
        return takeRequest()
    }

    @Synchronized
    override fun stop() {
        config = null
        release()
    }

    private fun takeRequest(): Boolean = !requestKey.also { requestKey = false }

    private fun start() {
        val cfg = config ?: return
        val s = surface ?: return
        failed = false
        waitingForKey = true
        requestKey = true
        val t = HandlerThread("video-decoder").apply { start() }
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, cfg.width, cfg.height).apply {
            setByteBuffer("csd-0", ByteBuffer.wrap(START_CODE + cfg.sps))
            setByteBuffer("csd-1", ByteBuffer.wrap(START_CODE + cfg.pps))
            setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, maxOf(cfg.width * cfg.height * 3 / 2, 256 * 1024))
        }
        try {
            val c = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            c.setCallback(object : MediaCodec.Callback() {
                override fun onInputBufferAvailable(mc: MediaCodec, index: Int) {
                    if (mc === codec) freeInputs.offer(index)
                }
                override fun onOutputBufferAvailable(mc: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                    runCatching { mc.releaseOutputBuffer(index, true) }
                }
                override fun onError(mc: MediaCodec, e: MediaCodec.CodecException) {
                    if (mc === codec) failed = true
                }
                override fun onOutputFormatChanged(mc: MediaCodec, format: MediaFormat) {}
            }, Handler(t.looper))
            codec = c // set before start() so the first input callbacks are accepted
            thread = t
            c.configure(format, s, null, 0)
            c.start()
        } catch (e: Exception) {
            release()
            t.quitSafely()
        }
    }

    private fun release() {
        val c = codec
        codec = null
        freeInputs.clear()
        if (c != null) {
            runCatching { c.stop() }
            runCatching { c.release() }
        }
        thread?.quitSafely()
        thread = null
    }

    private companion object {
        val START_CODE = byteArrayOf(0, 0, 0, 1)
    }
}
