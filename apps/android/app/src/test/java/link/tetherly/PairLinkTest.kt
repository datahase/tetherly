package link.tetherly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Base64

class PairLinkTest {
    private val pin = ByteArray(32) { (it * 7).toByte() }
    private val k = Base64.getUrlEncoder().withoutPadding().encodeToString(pin)
    private val now = 1_800_000_000L
    private fun parse(link: String) = PairLink.parse(link, now)

    @Test fun parsesAValidLink() {
        val link = parse("tetherly://pair?v=1&n=Studio%20MacBook&a=192.168.1.20,100.101.102.103,my-mac.tail1.ts.net&p=47801&k=$k&e=${now + 120}")!!
        assertEquals("Studio MacBook", link.name)
        assertEquals(
            listOf(HostAddress("192.168.1.20", 47801), HostAddress("100.101.102.103", 47801), HostAddress("my-mac.tail1.ts.net", 47801)),
            link.addresses,
        )
        assertEquals(pin.toList(), link.pin.toList())
    }

    @Test fun expiryAllowsClockSkewOnly() {
        val base = "tetherly://pair?v=1&n=M&a=10.0.0.1&p=47800&k=$k&e="
        assertEquals(1, parse(base + (now - 300))?.addresses?.size)
        assertNull(parse(base + (now - 301)))
        assertNull(parse(base))
        assertNull(parse(base.replace("&e=", "")))
    }

    @Test fun rejectsOverlongLinks() {
        assertNull(parse("tetherly://pair?v=1&n=${"M".repeat(1000)}&a=10.0.0.1&p=47800&k=$k&e=$now"))
    }

    @Test fun rejectsInvalidLinks() = listOf(
        "tetherly://pair?v=2&n=M&a=10.0.0.1&p=47800&k=$k",
        "tetherly://pair?n=M&a=10.0.0.1&p=47800&k=$k",
        "tetherly://pair?v=1&n=M&a=10.0.0.1&p=47800&k=${k.dropLast(2)}",
        "tetherly://pair?v=1&n=M&a=10.0.0.1&p=47800&k=${Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(33))}",
        "tetherly://pair?v=1&n=M&a=10.0.0.1&p=47800&k=!!!",
        "tetherly://pair?v=1&n=M&a=10.0.0.1&p=0&k=$k",
        "tetherly://pair?v=1&n=M&a=10.0.0.1&p=65536&k=$k",
        "tetherly://pair?v=1&n=M&a=10.0.0.1&p=x&k=$k",
        "tetherly://pair?v=1&n=M&a=10.0.0.1&k=$k",
        "tetherly://pair?v=1&n=M&a=999.0.0.1&p=47800&k=$k",
        "tetherly://pair?v=1&n=M&a=10.0.0.1:22&p=47800&k=$k",
        "tetherly://pair?v=1&n=M&a=&p=47800&k=$k",
        "tetherly://pair?v=1&n=M&a=a.local,b.local,c.local,d.local,e.local&p=47800&k=$k",
        "tetherly://pair?v=1&n=M&p=47800&k=$k",
        "https://pair?v=1&n=M&a=10.0.0.1&p=47800&k=$k",
        "tetherly://other?v=1&n=M&a=10.0.0.1&p=47800&k=$k",
        "not a link",
    ).map { if (it.startsWith("tetherly")) "$it&e=$now" else it }.forEach { assertNull(it, parse(it)) }
}
