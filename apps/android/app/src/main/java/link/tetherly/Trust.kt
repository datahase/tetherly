package link.tetherly

import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStream
import java.security.MessageDigest

/** A Mac this phone has paired with. [pin] is lowercase hex; [address] is the last address that worked (host:port). */
data class PairedMac(val hostName: String, val pin: String, val address: String, val routes: List<MacRoute> = emptyList())

/** An address the Mac reported for itself (SPEC §5 host_info). A hint for reaching it; identity is still the pin. */
data class MacRoute(val ip: String, val kind: String) {
    val tailscale get() = kind == "tailscale"
}

/** Tailscale addresses (100.64.0.0/10) and MagicDNS names. */
fun isTailscaleHost(host: String): Boolean {
    if (host.endsWith(".ts.net", ignoreCase = true)) return true
    val p = host.split('.').mapNotNull { it.toIntOrNull() }
    return p.size == 4 && p[0] == 100 && p[1] in 64..127
}

interface MacStore {
    fun load(): List<PairedMac>
    fun save(macs: List<PairedMac>)
}

fun encodeMacs(macs: List<PairedMac>): String = JSONArray(macs.map { m ->
    JSONObject().put("hostName", m.hostName).put("pin", m.pin).put("address", m.address)
        .put("routes", JSONArray(m.routes.map { JSONObject().put("ip", it.ip).put("kind", it.kind) }))
}).toString()

fun decodeMacs(text: String?): List<PairedMac> = runCatching {
    val a = JSONArray(text ?: return emptyList())
    List(a.length()) { i ->
        a.getJSONObject(i).run {
            val r = optJSONArray("routes") // absent in data saved before routes existed
            val routes = if (r == null) emptyList() else List(r.length()) { r.getJSONObject(it).let { o -> MacRoute(o.getString("ip"), o.getString("kind")) } }
            PairedMac(getString("hostName"), getString("pin"), getString("address"), routes)
        }
    }
}.getOrDefault(emptyList())

/** Validates a host_info payload: at most 8 IPv4 literals, kinds lan or tailscale. Throws malformed otherwise. */
fun parseRoutes(o: JSONObject): List<MacRoute> {
    val a = o.optJSONArray("addresses") ?: malformed("addresses missing")
    if (a.length() > 8) malformed("too many addresses")
    return List(a.length()) { i ->
        val e = a.optJSONObject(i) ?: malformed("bad address")
        val ip = e.str("ip", 15)
        val kind = e.str("kind", 16)
        if (kind != "lan" && kind != "tailscale") malformed("bad address kind")
        val parsed = HostAddress.parse(ip)
        if (parsed == null || parsed.host != ip || ':' in ip || !HostAddress.isIpLiteral(ip)) malformed("bad address")
        MacRoute(ip, kind)
    }
}

sealed interface Trust {
    data class Known(val mac: PairedMac) : Trust
    data object NewPairing : Trust
    data class Rejected(val message: String) : Trust
}

const val ALREADY_KNOWN = "This Mac already knows this phone. Revoke it on the Mac and pair again."
const val IDENTITY_CHANGED = "This Mac's identity changed. Forget it and pair again."

/** Decided inside the TLS verify step from the server pin alone. Names and addresses are hints, never trust. */
fun decideTrust(pin: String, address: String, macs: List<PairedMac>, pairIntent: Boolean): Trust {
    macs.find { it.pin == pin }?.let { return Trust.Known(it) }
    // A stored Mac's address answering with another key is never silently re-paired, even when the user tapped Pair.
    if (macs.any { it.address == address }) return Trust.Rejected(IDENTITY_CHANGED)
    if (pairIntent) return Trust.NewPairing
    return Trust.Rejected("This Mac isn't paired with this phone. Turn on pairing on the Mac, then tap Pair.")
}

sealed interface WelcomeOutcome {
    data class Session(val mac: PairedMac) : WelcomeOutcome
    data object Pair : WelcomeOutcome
    data class Rejected(val message: String) : WelcomeOutcome
}

/** Combines the handshake decision with what the Mac says about us in `welcome`. */
fun checkWelcome(trust: Trust, state: String, host: String, macs: List<PairedMac>, pairIntent: Boolean): WelcomeOutcome = when {
    trust is Trust.Known && state == "paired" -> WelcomeOutcome.Session(trust.mac)
    trust is Trust.Known && pairIntent -> WelcomeOutcome.Pair
    trust is Trust.Known -> WelcomeOutcome.Rejected("This Mac no longer recognizes this phone. Turn on pairing on the Mac, then tap Pair.")
    // SPEC §4.2: the Mac persisted but pair_done never arrived. Never install a pin silently.
    state == "paired" -> WelcomeOutcome.Rejected(ALREADY_KNOWN)
    macs.any { it.hostName == host } -> WelcomeOutcome.Rejected(IDENTITY_CHANGED)
    else -> WelcomeOutcome.Pair
}

/** Writes received file data to [sink], refusing more than [size] bytes, and verifies size and SHA-256 at the end. */
class FileReceiver(private val sink: OutputStream, val size: Long) {
    private val digest = MessageDigest.getInstance("SHA-256")
    var received = 0L
        private set

    fun write(chunk: ByteArray) {
        if (received + chunk.size > size) throw ProtocolException("file_failed", "More data than the offered size")
        sink.write(chunk)
        digest.update(chunk)
        received += chunk.size
    }

    fun finish(sha256: ByteArray) {
        if (received != size) throw ProtocolException("file_failed", "File is incomplete")
        if (!MessageDigest.isEqual(digest.digest(), sha256)) throw ProtocolException("file_failed", "File is corrupted (hash mismatch)")
        sink.flush()
    }
}
