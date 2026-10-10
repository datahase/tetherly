package link.tetherly

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import org.json.JSONObject

/**
 * Bounded outgoing control queue for one connection. Consecutive pointer/scroll moves merge into the queued tail and
 * moves are sent at most every [moveIntervalMs] (~120 Hz), so input stays far below the Mac's 500 msgs/s limit.
 * A new connection gets a new queue, so input queued before a loss is never replayed.
 */
class OutQueue(
    private val capacity: Int = 256,
    private val moveIntervalMs: Long = 8,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
) {
    private val items = ArrayDeque<JSONObject>()
    private var lastMoveAt = Long.MIN_VALUE / 2
    private val signal = Channel<Unit>(Channel.CONFLATED)

    /** Returns false if the queue is full; the message is dropped. */
    @Synchronized
    fun offer(m: JSONObject): Boolean {
        val type = m.getString("type")
        val tail = items.lastOrNull()
        if (tail != null && tail.getString("type") == type) {
            when (type) {
                "pointer" -> return merge(tail, m, 10_000).let { true }
                "scroll" -> return merge(tail, m, 5_000).let { true }
                "pointer_abs" -> { tail.put("x", m.get("x")).put("y", m.get("y")); return true }
            }
        }
        if (items.size >= capacity) return false
        items.addLast(m)
        signal.trySend(Unit)
        return true
    }

    @Synchronized
    fun size() = items.size

    /** Next message to send at [now], or null plus how long to wait (0 = until something is offered). */
    @Synchronized
    internal fun poll(now: Long): Pair<JSONObject?, Long> {
        val head = items.firstOrNull() ?: return null to 0L
        if (head.getString("type") in MOVES) {
            val wait = lastMoveAt + moveIntervalMs - now
            if (wait > 0) return null to wait
            lastMoveAt = now
        }
        return items.removeFirst() to 0L
    }

    suspend fun take(): JSONObject {
        while (true) {
            val (m, wait) = poll(clock())
            if (m != null) return m
            if (wait > 0) delay(wait) else signal.receive()
        }
    }

    private fun merge(tail: JSONObject, m: JSONObject, limit: Int) {
        for (k in listOf("dx", "dy")) tail.put(k, (tail.getInt(k) + m.getInt(k)).coerceIn(-limit, limit))
    }

    private companion object {
        val MOVES = setOf("pointer", "pointer_abs", "scroll")
    }
}
