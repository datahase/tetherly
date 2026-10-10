package link.tetherly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HostAddressTest {
    private val d = HostAddress.DEFAULT_PORT

    @Test fun acceptsSupportedForms() = listOf(
        " 192.168.1.20 " to HostAddress("192.168.1.20", d),
        "0.0.0.0:1" to HostAddress("0.0.0.0", 1),
        "my-mac.local:9000" to HostAddress("my-mac.local", 9000),
        "my-mac.tail1234.ts.net" to HostAddress("my-mac.tail1234.ts.net", d),
        "MyMac" to HostAddress("MyMac", d),
        "100.101.102.103:65535" to HostAddress("100.101.102.103", 65535),
        "fd7a:115c:a1e0::1" to HostAddress("fd7a:115c:a1e0::1", d),
        "::1" to HostAddress("::1", d),
        "::" to HostAddress("::", d),
        "1:2:3:4:5:6:7:8" to HostAddress("1:2:3:4:5:6:7:8", d),
        "::ffff:192.168.1.1" to HostAddress("::ffff:192.168.1.1", d),
        "[::ffff:192.0.2.1]:80" to HostAddress("::ffff:192.0.2.1", 80),
        "1:2:3:4:5:6:192.0.2.1" to HostAddress("1:2:3:4:5:6:192.0.2.1", d),
        "[fd7a:115c:a1e0::1]:5" to HostAddress("fd7a:115c:a1e0::1", 5),
        "[::1]" to HostAddress("::1", d),
    ).forEach { (input, expected) -> assertEquals(input, expected, HostAddress.parse(input)) }

    @Test fun rejectsMalformed() = listOf(
        "", "   ", "host:0", "host:65536", "host:abc", "host:", "host:+1", "host:-1", "host:080000",
        "http://host", "host/path", "user@host", "my mac", "host\u0000", "host\t1", "mäc.local",
        ".local", "-host", "host-", "a..b", "a".repeat(64) + ".local", ("a".repeat(63) + ".").repeat(4) + "aa",
        "foo:bar:baz", "256.1.1.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "1.2.3.4:", "123",
        "[::1", "[::1]x", "[::1]:", "[::1]:0", "[host]", "[1.2.3.4]", "[]",
        "1::2::3", "1:2:3:4:5:6:7:8:9", "1:2:3:4:5:6:7", "12345::1", "::g", "fe80::1%en0", ":::",
        "::ffff:999.1.1.1", "1:2:3:4:5:6:7::1.2.3.4",
        // Dotted IPv4 must be the final 32 bits (RFC 4291 §2.2).
        "192.0.2.1::", "1:192.0.2.1::", "[192.0.2.1::]", "[1:192.0.2.1::]:80", "::192.0.2.1:1", "1.2.3.4::ffff",
    ).forEach { assertNull(it, HostAddress.parse(it)) }

    @Test fun formatsIpv6WithBrackets() {
        assertEquals("[::1]:47800", HostAddress("::1", 47800).toString())
        assertEquals("mac:1", HostAddress("mac", 1).toString())
    }
}
