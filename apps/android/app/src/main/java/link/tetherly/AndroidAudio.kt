package link.tetherly

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack

/**
 * Mac sound through a low-latency AudioTrack, 48 kHz s16le stereo.
 * Playback never builds a backlog: data that doesn't fit the small buffer is dropped instead of delaying sound.
 */
class AndroidAudio : AudioIo {
    private var track: AudioTrack? = null

    @Synchronized
    override fun play(pcm: ByteArray) {
        val t = track ?: newTrack().also { track = it }
        t.write(pcm, 0, pcm.size, AudioTrack.WRITE_NON_BLOCKING)
    }

    private fun newTrack(): AudioTrack {
        val format = AudioFormat.Builder().setSampleRate(48_000).setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build()
        val min = AudioTrack.getMinBufferSize(48_000, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        return AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(min, 48_000 * 4 / 10)) // about 100 ms
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
            .also { it.play() }
    }

    @Synchronized
    override fun stop() {
        track?.let { runCatching { it.pause(); it.flush(); it.release() } }
        track = null
    }
}
