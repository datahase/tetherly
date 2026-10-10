package link.tetherly

import android.net.DnsResolver
import android.net.ssl.SSLSockets
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.io.BufferedInputStream
import java.io.Closeable
import java.io.IOException
import java.math.BigInteger
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Principal
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.Date
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLException
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509ExtendedTrustManager
import javax.security.auth.x500.X500Principal
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** This phone's long-term P-256 key, non-exportable in AndroidKeyStore, wrapped in a Keystore-signed certificate. */
class Identity private constructor(val privateKey: PrivateKey, val cert: X509Certificate) {
    val pin: ByteArray = Pairing.sha256(cert.publicKey.encoded)

    companion object {
        const val ALIAS = "tetherly-identity"

        fun load(): Identity {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (!ks.containsAlias(ALIAS)) {
                KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                    initialize(
                        KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                            .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256)
                            .setCertificateSubject(X500Principal("CN=Tetherly Android"))
                            .setCertificateSerialNumber(BigInteger(63, SecureRandom()).add(BigInteger.ONE))
                            .setCertificateNotBefore(Date(System.currentTimeMillis() - 86_400_000L))
                            .setCertificateNotAfter(Date(System.currentTimeMillis() + 30L * 365 * 86_400_000L))
                            .build(),
                    )
                }.generateKeyPair()
            }
            val entry = ks.getEntry(ALIAS, null) as KeyStore.PrivateKeyEntry
            return Identity(entry.privateKey, entry.certificate as X509Certificate)
        }
    }
}

private class TlsConn(private val socket: SSLSocket, override val peerPin: ByteArray, override val localPin: ByteArray, override val channelBinding: ByteArray) : Conn {
    override val input = BufferedInputStream(socket.inputStream, 64 * 1024)
    override val output = socket.outputStream!!
    override fun close() = runCatching { socket.close() }.let {}
}

/** Presents this phone's identity for TLS client authentication. */
private class IdentityKeyManager(private val id: Identity) : X509ExtendedKeyManager() {
    override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = Identity.ALIAS
    override fun chooseEngineClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, engine: SSLEngine?) = Identity.ALIAS
    override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(Identity.ALIAS)
    override fun getCertificateChain(alias: String?) = if (alias == Identity.ALIAS) arrayOf(id.cert) else null
    override fun getPrivateKey(alias: String?) = if (alias == Identity.ALIAS) id.privateKey else null
    override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null
    override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?): String? = null
}

/** Accepts only a P-256 server key whose pin [accept] approves; records the pin. No CA trust is involved. */
private class PinTrustManager(private val accept: (ByteArray) -> Boolean) : X509ExtendedTrustManager() {
    @Volatile var pin: ByteArray? = null

    private fun check(chain: Array<out X509Certificate>?) {
        val leaf = chain?.firstOrNull() ?: throw CertificateException("no server certificate")
        val key = leaf.publicKey as? ECPublicKey ?: throw CertificateException("server key is not EC")
        if (key.params.curve != Pairing.p256.curve) throw CertificateException("server key is not P-256")
        val p = Pairing.sha256(key.encoded)
        pin = p
        if (!accept(p)) throw CertificateException("server pin not accepted")
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = check(chain)
    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = check(chain)
    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = check(chain)
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = throw CertificateException("client role only")
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = throw CertificateException("client role only")
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = throw CertificateException("client role only")
    override fun getAcceptedIssuers() = emptyArray<X509Certificate>()
}

/**
 * Mutual TLS 1.3 to the Mac. Name lookup uses DnsResolver with a CancellationSignal and the TCP connect and handshake
 * run through [blocking], so the 5 s bound and user cancel stop the attempt promptly. Literals skip DNS.
 */
class AndroidTransport : Transport {
    private val identity by lazy { Identity.load() }

    override suspend fun open(address: HostAddress, accept: (pin: ByteArray) -> Boolean): Conn =
        withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
            val id = blocking(Closeable {}) { identity }
            val candidates = if (HostAddress.isIpLiteral(address.host) || '%' in address.host) {
                listOf(InetAddress.getByName(address.host))
            } else {
                resolve(address.host)
            }
            var last: Exception = UnknownHostException(address.host)
            for (ip in candidates) {
                val socket = Socket()
                // Input frames are tiny; Nagle would hold each one back until the previous was acknowledged.
                socket.tcpNoDelay = true
                try {
                    blocking(socket) { socket.connect(InetSocketAddress(ip, address.port), CONNECT_TIMEOUT_MS.toInt()) }
                    return@withTimeoutOrNull handshake(socket, address, id, accept)
                } catch (e: IOException) {
                    socket.close()
                    currentCoroutineContext().ensureActive()
                    if (e is SSLException) throw e // a TLS answer means we reached the Mac; other addresses won't differ
                    last = e
                }
            }
            throw last
        } ?: throw SocketTimeoutException()

    private suspend fun handshake(socket: Socket, address: HostAddress, id: Identity, accept: (ByteArray) -> Boolean): Conn {
        val trust = PinTrustManager(accept)
        // A fresh context per connection: no session cache, so no resumption.
        val ctx = SSLContext.getInstance("TLSv1.3").apply { init(arrayOf(IdentityKeyManager(id)), arrayOf(trust), null) }
        val ssl = ctx.socketFactory.createSocket(socket, address.host, address.port, true) as SSLSocket
        try {
            ssl.enabledProtocols = arrayOf("TLSv1.3")
            ssl.soTimeout = READ_TIMEOUT_MS
            blocking(ssl) { ssl.startHandshake() }
            if (!SSLSockets.isSupportedSocket(ssl)) throw SSLException("TLS exporter unavailable")
            val cb = SSLSockets.exportKeyingMaterial(ssl, "EXPORTER-Channel-Binding", ByteArray(0), 32)
                ?: throw SSLException("TLS exporter unavailable")
            val pin = trust.pin ?: throw SSLException("server not verified")
            return TlsConn(ssl, pin, id.pin, cb)
        } catch (e: Throwable) {
            ssl.close()
            throw e
        }
    }

    private suspend fun resolve(host: String): List<InetAddress> = suspendCancellableCoroutine { cont ->
        val signal = CancellationSignal()
        cont.invokeOnCancellation { signal.cancel() }
        DnsResolver.getInstance().query(
            null, host, DnsResolver.FLAG_EMPTY, Runnable::run, signal,
            object : DnsResolver.Callback<List<InetAddress>> {
                override fun onAnswer(answer: List<InetAddress>, rcode: Int) {
                    if (answer.isEmpty()) cont.resumeWithException(UnknownHostException(host)) else cont.resume(answer)
                }
                override fun onError(error: DnsResolver.DnsException) {
                    cont.resumeWithException(UnknownHostException(host).apply { initCause(error) })
                }
            },
        )
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 5_000L
        const val READ_TIMEOUT_MS = 15_000 // heartbeat: nothing received for 15 s closes the connection
    }
}
