package link.tetherly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OutQueueTest {
    private fun pointer(dx: Int, dy: Int) = msg("pointer", "dx" to dx, "dy" to dy)

    @Test fun pointerMovesMergeAndClamp() {
        val q = OutQueue()
        repeat(5000) { assertTrue(q.offer(pointer(3, -1))) }
        assertEquals(1, q.size())
        val m = q.poll(0).first!!
        assertEquals(10_000, m.getInt("dx"))
        assertEquals(-5000, m.getInt("dy"))
    }

    @Test fun mergingNeverReordersAroundOtherInput() {
        val q = OutQueue()
        q.offer(pointer(1, 0)); q.offer(msg("click", "button" to "left", "count" to 1)); q.offer(pointer(2, 0)); q.offer(pointer(3, 0))
        assertEquals(listOf("pointer" to 1, "click" to null, "pointer" to 5), List(3) { i ->
            q.poll(i * 100L).first!!.let { it.getString("type") to (it.opt("dx") as Int?) }
        })
    }

    @Test fun boundedWhenFull() {
        val q = OutQueue(capacity = 256)
        repeat(256) { assertTrue(q.offer(msg("key", "code" to 0))) }
        assertFalse(q.offer(msg("key", "code" to 1)))
        assertEquals(256, q.size())
    }

    @Test fun movesAreThrottledButOtherMessagesAreNot() {
        val q = OutQueue(moveIntervalMs = 8)
        q.offer(pointer(1, 1))
        assertEquals("pointer", q.poll(100).first!!.getString("type"))
        q.offer(pointer(1, 1))
        val (none, wait) = q.poll(103)
        assertNull(none)
        assertEquals(5, wait)
        q.offer(pointer(1, 1)) // merges while held back
        assertEquals(2, q.poll(108).first!!.getInt("dx"))
        q.offer(msg("click", "button" to "left", "count" to 1))
        assertEquals("click", q.poll(109).first!!.getString("type"))
    }

    @Test fun moveRateStaysFarBelowTheMacLimit() {
        val q = OutQueue(moveIntervalMs = 8)
        var sent = 0
        for (t in 0 until 1000L) { // one second, a move offered every millisecond
            q.offer(pointer(1, 0))
            if (q.poll(t).first != null) sent++
        }
        assertTrue("sent $sent", sent in 100..130)
    }
}
