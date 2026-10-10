package link.tetherly

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class RoutesTest {
    @Test fun tailscaleHostsAreRecognized() {
        assertTrue(isTailscaleHost("100.64.0.1"))
        assertTrue(isTailscaleHost("100.127.255.254"))
        assertTrue(isTailscaleHost("my-mac.tail1234.ts.net"))
        assertFalse(isTailscaleHost("100.63.0.1"))
        assertFalse(isTailscaleHost("100.128.0.1"))
        assertFalse(isTailscaleHost("192.0.2.10"))
        assertFalse(isTailscaleHost("my-mac.local"))
    }

    @Test fun routesRoundTripAndOldDataStillLoads() {
        val mac = PairedMac("Studio", "ab", "192.0.2.10:47800", listOf(MacRoute("192.0.2.10", "lan"), MacRoute("100.101.1.2", "tailscale")))
        assertEquals(listOf(mac), decodeMacs(encodeMacs(listOf(mac))))
        val old = """[{"hostName":"Studio","pin":"ab","address":"192.0.2.10:47800"}]"""
        assertEquals(listOf(PairedMac("Studio", "ab", "192.0.2.10:47800")), decodeMacs(old))
    }

    private fun info(vararg entries: Pair<String, String>) =
        JSONObject().put("addresses", JSONArray(entries.map { JSONObject().put("ip", it.first).put("kind", it.second) }))

    @Test fun hostInfoIsValidated() {
        assertEquals(listOf(MacRoute("100.101.1.2", "tailscale")), parseRoutes(info("100.101.1.2" to "tailscale")))
        for (bad in listOf(
            info("my-mac.local" to "lan"), // names are not accepted, only IP literals
            info("1.2.3.4:99" to "lan"),
            info("1.2.3.4" to "cellular"),
            info("::1" to "lan"),
            info(*Array(9) { "10.0.0.$it" to "lan" }),
            JSONObject(),
        )) {
            try { parseRoutes(bad); fail("accepted $bad") } catch (_: ProtocolException) {}
        }
    }
}
