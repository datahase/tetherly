package link.tetherly

import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder
import java.util.Base64

/** SPEC §4a QR pairing link: `tetherly://pair?v=1&n=<name>&a=<addr>[,<addr>…]&p=<port>&k=<base64url pin>&e=<expiry>`. */
class PairLink(val name: String, val addresses: List<HostAddress>, val pin: ByteArray) {
    companion object {
        /** Returns null for anything that isn't a valid v1 link; the QR is untrusted input. */
        fun parse(text: String, nowSeconds: Long = System.currentTimeMillis() / 1000): PairLink? {
            if (text.length > 1024) return null
            val uri = try { URI(text.trim()) } catch (e: URISyntaxException) { return null }
            if (!uri.scheme.equals("tetherly", ignoreCase = true) || uri.host != "pair") return null
            val params = (uri.rawQuery ?: return null).split('&').associate { part ->
                val key = part.substringBefore('=')
                val value = runCatching { URLDecoder.decode(part.substringAfter('=', ""), "UTF-8") }.getOrNull() ?: return null
                key to value
            }
            if (params["v"] != "1") return null
            // Expired pairing windows are refused; 300 s allows for clock skew between the Mac and the phone.
            val expires = params["e"]?.takeIf { it.length in 1..12 && it.all(Char::isDigit) }?.toLong() ?: return null
            if (expires < nowSeconds - 300) return null
            val port = params["p"]?.takeIf { it.length in 1..5 && it.all(Char::isDigit) }?.toInt()?.takeIf { it in 1..65535 } ?: return null
            val pin = runCatching { Base64.getUrlDecoder().decode(params["k"] ?: return null) }.getOrNull()?.takeIf { it.size == 32 } ?: return null
            val raw = params["a"]?.split(',') ?: return null
            if (raw.size !in 1..4) return null
            val addresses = raw.map { a ->
                // Each entry is a bare host; the port comes from `p`.
                val parsed = HostAddress.parse(a) ?: return null
                if (parsed.port != HostAddress.DEFAULT_PORT || a.endsWith(":${HostAddress.DEFAULT_PORT}")) return null
                parsed.copy(port = port)
            }
            return PairLink(params["n"].orEmpty().take(64), addresses, pin)
        }
    }
}
