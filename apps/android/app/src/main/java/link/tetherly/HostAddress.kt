package link.tetherly

/**
 * A host the user typed: IPv4, DNS name (LAN, .local, Tailscale MagicDNS) or IPv6 literal, with optional port.
 * Grammar (purely syntactic, never touches DNS):
 *   input  = ipv4 [":" port] | name [":" port] | "[" ipv6 "]" [":" port] | ipv6
 *   port   = 1*5DIGIT, 1..65535
 * IPv6 zone IDs ("%en0") are rejected; they are meaningless across devices.
 */
data class HostAddress(val host: String, val port: Int) {
    override fun toString() = if (':' in host) "[$host]:$port" else "$host:$port"

    companion object {
        const val DEFAULT_PORT = 47800
        private const val MAX_INPUT = 261 // 253-char name + ":65535" with margin for brackets

        fun parse(input: String): HostAddress? {
            val text = input.trim()
            if (text.isEmpty() || text.length > MAX_INPUT || text.any { it.code !in 0x21..0x7E }) return null
            return when {
                text.startsWith("[") -> {
                    val end = text.indexOf(']')
                    if (end < 0) return null
                    val host = text.substring(1, end).takeIf(::isIpv6) ?: return null
                    when (val rest = text.substring(end + 1)) {
                        "" -> HostAddress(host, DEFAULT_PORT)
                        else -> if (rest.startsWith(":")) port(rest.substring(1))?.let { HostAddress(host, it) } else null
                    }
                }
                text.count { it == ':' } > 1 -> text.takeIf(::isIpv6)?.let { HostAddress(it, DEFAULT_PORT) }
                else -> {
                    val host = text.substringBefore(':')
                    val port = if (':' in text) port(text.substringAfter(':')) ?: return null else DEFAULT_PORT
                    if (isIpv4(host) || (!looksNumeric(host) && isHostname(host))) HostAddress(host, port) else null
                }
            }
        }

        private fun port(text: String): Int? =
            if (text.length in 1..5 && text.all { it in '0'..'9' }) text.toInt().takeIf { it in 1..65535 } else null

        private fun looksNumeric(host: String) = host.all { it.isDigit() || it == '.' }

        internal fun isIpLiteral(host: String) = isIpv4(host) || isIpv6(host)

        private fun isIpv4(host: String): Boolean {
            val parts = host.split('.')
            return parts.size == 4 && parts.all { p ->
                p.length in 1..3 && p.all { it in '0'..'9' } && (p == "0" || !p.startsWith("0")) && p.toInt() <= 255
            }
        }

        private fun isHostname(host: String): Boolean =
            host.length <= 253 && host.split('.').all { label ->
                label.length in 1..63 && label.first() != '-' && label.last() != '-' &&
                    label.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' }
            }

        private fun isIpv6(host: String): Boolean {
            if (host.length !in 2..45 || host.count { it == ':' } < 2) return false
            // RFC 4291 §2.2: a dotted IPv4 part may only occupy the final 32 bits, i.e. follow the last ':'.
            if ('.' in host && host.indexOf('.') < host.lastIndexOf(':')) return false
            val halves = host.split("::")
            if (halves.size > 2) return false
            val groups = halves.map { h -> if (h.isEmpty()) emptyList() else h.split(':') }.flatten()
            if (groups.any { it.isEmpty() }) return false
            // An embedded IPv4 tail ("::ffff:1.2.3.4") counts as two groups.
            val ipv4Tail = groups.lastOrNull()?.let { '.' in it } == true
            if (ipv4Tail && !isIpv4(groups.last())) return false
            val hex = if (ipv4Tail) groups.dropLast(1) else groups
            if (!hex.all { g -> g.length in 1..4 && g.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' } }) return false
            val count = hex.size + if (ipv4Tail) 2 else 0
            return if (halves.size == 2) count <= 7 else count == 8
        }
    }
}
