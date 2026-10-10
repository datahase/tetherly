package link.tetherly

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.hardware.display.DisplayManager
import android.media.MediaCodecList
import android.os.Build
import android.view.Display
import kotlin.math.roundToInt
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.FileNotFoundException
import java.net.Inet4Address
import java.net.InetAddress

class MainViewModel(private val app: Application) : AndroidViewModel(app) {
    val decoder = VideoDecoder()
    private val resolver = app.contentResolver
    private val clipboard = app.getSystemService(ClipboardManager::class.java)
    private val prefs = app.getSharedPreferences("tetherly", Context.MODE_PRIVATE)

    private val store = object : MacStore {
        override fun load() = decodeMacs(prefs.getString(KEY_MACS, null))
        override fun save(macs: List<PairedMac>) = prefs.edit().putString(KEY_MACS, encodeMacs(macs)).apply()
    }

    private val platform = object : Platform {
        override val video = decoder
        override val audio = AndroidAudio()
        override fun setClipboard(text: String) = clipboard.setPrimaryClip(ClipData.newPlainText("Mac clipboard", text))
        override fun openRead(uri: String) = resolver.openInputStream(Uri.parse(uri)) ?: throw FileNotFoundException()
        override fun openWrite(uri: String) = resolver.openOutputStream(Uri.parse(uri), "wt") ?: throw FileNotFoundException()
        override fun delete(uri: String) { DocumentsContract.deleteDocument(resolver, Uri.parse(uri)) }
    }

    val session = SessionController(
        viewModelScope, AndroidTransport(), store, platform, "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(64),
    )

    /**
     * The fastest stream this phone can show: its highest screen refresh rate, capped by what its hardware H.264
     * decoder supports at 1080p. The Mac then caps the request at its own display's maximum.
     */
    val maxFps: Int = run {
        val screen = app.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
            ?.supportedModes?.maxOfOrNull { it.refreshRate }?.roundToInt() ?: 60
        val decoder = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { !it.isEncoder && it.isHardwareAccelerated && "video/avc" in it.supportedTypes.map(String::lowercase) }
            .mapNotNull { info ->
                runCatching { info.getCapabilitiesForType("video/avc").videoCapabilities.getSupportedFrameRatesFor(1920, 1080).upper.toInt() }.getOrNull()
            }
            .maxOrNull() ?: 60
        minOf(screen, decoder).coerceIn(15, 240)
    }

    init {
        session.setVideoSettings(session.videoSettings.value.copy(fps = maxFps))
    }

    /** Must be called from a user action while the app is in the foreground (Android blocks background clipboard reads). */
    fun sendClipboard() {
        val text = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(app)?.toString()
        session.sendClipboard(text)
    }

    fun sendFile(uri: Uri) {
        viewModelScope.launch {
            val meta = withContext(Dispatchers.IO) {
                runCatching {
                    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                        if (!c.moveToFirst() || c.isNull(1)) null else (c.getString(0) ?: "file") to c.getLong(1)
                    }
                }.getOrNull()
            }
            if (meta == null) session.showNotice("Can't read that file's size, so it can't be sent.")
            else session.sendFile(uri.toString(), meta.first, meta.second)
        }
    }

    /** A pairing link opened from outside the app, waiting for the user to confirm it. */
    var pendingLink by mutableStateOf<PairLink?>(null)

    // ---- session orientation (Auto / Landscape / Portrait), persisted ----

    enum class Orientation { Auto, Landscape, Portrait }

    /** Sessions start on the system's auto-rotate; the toolbar toggle locks the other orientation for this session. */
    var orientation by mutableStateOf(Orientation.Auto)
        private set

    fun lockOrientation(o: Orientation) { orientation = o }

    fun resetOrientation() { orientation = Orientation.Auto }

    // ---- discovery ----

    enum class Discovery { Starting, Running, Failed, Stopped }

    var discovery by mutableStateOf(Discovery.Stopped)
        private set
    var discoveryError by mutableStateOf<String?>(null)
        private set
    val devices = mutableStateListOf<String>()
    private val services = mutableMapOf<String, NsdServiceInfo>()
    private val nsd = app.getSystemService(Context.NSD_SERVICE) as NsdManager

    // NSD invokes these on a binder thread; every state change hops to the main thread.
    private val listener = object : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(type: String) = onMain { discovery = Discovery.Running; discoveryError = null }
        override fun onStartDiscoveryFailed(type: String, code: Int) = onMain {
            discovery = Discovery.Failed
            discoveryError = "Discovery unavailable (error $code). Enter the Mac's address instead."
        }
        override fun onDiscoveryStopped(type: String) = onMain {
            discovery = Discovery.Stopped
            devices.clear()
            services.clear()
            if (restartDiscovery) { restartDiscovery = false; startDiscovery() }
        }
        override fun onStopDiscoveryFailed(type: String, code: Int) = onMain { discovery = Discovery.Stopped }
        override fun onServiceFound(info: NsdServiceInfo) = onMain {
            // Bounded and deduplicated: a noisy network can't grow the list without limit.
            val name = info.serviceName.take(MAX_NAME)
            if (name !in devices && devices.size < MAX_DEVICES) devices += name
            if (name in devices) services[name] = info
        }
        override fun onServiceLost(info: NsdServiceInfo) = onMain {
            val name = info.serviceName.take(MAX_NAME)
            devices -= name
            services -= name
        }
    }

    private var restartDiscovery = false

    // ---- routes: Wi-Fi (Bonjour) and Tailscale, merged per paired Mac ----

    enum class Reach { Wifi, Tailscale, Offline }

    /** Best current route per paired Mac pin. Wi-Fi when Bonjour sees it, else Tailscale when its address answers. */
    val reach = mutableStateMapOf<String, Reach>()
    var tailscaleOn by mutableStateOf(false)
        private set
    var refreshing by mutableStateOf(false)
        private set

    fun reachOf(mac: PairedMac): Reach = when {
        mac.hostName in devices -> Reach.Wifi
        else -> reach[mac.pin] ?: Reach.Offline
    }

    /** Pull to refresh: restart the nearby search and re-check every route. */
    fun refresh() {
        if (refreshing) return
        refreshing = true
        viewModelScope.launch {
            if (discovery == Discovery.Running || discovery == Discovery.Starting) {
                restartDiscovery = true
                runCatching { nsd.stopServiceDiscovery(listener) }.onFailure { restartDiscovery = false; startDiscovery() }
            } else {
                startDiscovery()
            }
            probeRoutes()
            delay(1_200) // give Bonjour a moment to answer before the indicator goes away
            refreshing = false
        }
    }

    /** Opens a plain TCP connection to each paired Mac's Tailscale address. No TLS, nothing sent: a reachability hint. */
    private suspend fun probeRoutes() {
        val macs = session.macs.value
        if (!tailscaleOn) { macs.forEach { reach[it.pin] = Reach.Offline }; return }
        for (mac in macs) {
            val port = HostAddress.parse(mac.address)?.port ?: HostAddress.DEFAULT_PORT
            val candidates = mac.routes.filter { it.tailscale }.map { it.ip } +
                listOfNotNull(HostAddress.parse(mac.address)?.host?.takeIf(::isTailscaleHost))
            val ok = candidates.distinct().firstOrNull { ip ->
                withContext(Dispatchers.IO) {
                    runCatching { java.net.Socket().use { it.connect(java.net.InetSocketAddress(ip, port), 2_000) }; true }.getOrDefault(false)
                }
            }
            reach[mac.pin] = if (ok != null) Reach.Tailscale else Reach.Offline
            if (ok != null) tailscaleAddress[mac.pin] = HostAddress(ok, port)
        }
    }

    private val tailscaleAddress = mutableMapOf<String, HostAddress>()

    // Kotlin initializes in source order: this must stay below every property the watchers and probes touch.
    init {
        startDiscovery()
        watchTailscale()
        viewModelScope.launch {
            while (true) {
                probeRoutes()
                delay(15_000)
            }
        }
    }

    /** Connects over the best route: Wi-Fi when Bonjour sees the Mac, otherwise its Tailscale address, else the last address. */
    fun connectBest(mac: PairedMac) {
        when (reachOf(mac)) {
            Reach.Wifi -> connectDiscovered(mac.hostName, pair = false)
            Reach.Tailscale -> session.connect(tailscaleAddress[mac.pin] ?: return session.showNotice("Checking Tailscale. Try again."), pair = false)
            Reach.Offline -> HostAddress.parse(mac.address)?.let { session.connect(it, pair = false) }
                ?: session.showNotice("This saved address can't be used. Connect by address instead.")
        }
    }

    /** Tailscale shows up as a VPN network whose interface has a 100.64.0.0/10 address. */
    private fun watchTailscale() {
        val cm = app.getSystemService(ConnectivityManager::class.java)
        fun update() {
            val on = cm.allNetworks.any { n ->
                val caps = cm.getNetworkCapabilities(n)
                caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                    cm.getLinkProperties(n)?.linkAddresses?.any { isTailscaleHost(it.address.hostAddress ?: "") } == true
            }
            onMain {
                val changed = on != tailscaleOn
                tailscaleOn = on
                if (changed) viewModelScope.launch { probeRoutes() }
            }
        }
        val request = NetworkRequest.Builder().removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build()
        cm.registerNetworkCallback(request, object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = update()
            override fun onLost(network: Network) = update()
            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) = update()
        })
        update()
    }

    fun startDiscovery() {
        if (discovery == Discovery.Starting || discovery == Discovery.Running) return
        discovery = Discovery.Starting
        // The same listener can't be registered twice, so start only from Stopped/Failed.
        runCatching { nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener) }
            .onFailure { discovery = Discovery.Failed; discoveryError = "Discovery unavailable. Enter the Mac's address instead." }
    }

    var resolving by mutableStateOf<String?>(null)
        private set

    /** Resolves a discovered Mac to host:port, then connects (or pairs). Discovery is only a hint; TLS pins decide trust. */
    @Suppress("DEPRECATION") // resolveService/host still work on API 34+; the replacement callback API is 34+ only.
    fun connectDiscovered(name: String, pair: Boolean) {
        val info = services[name] ?: return
        resolving = name
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, code: Int) = onMain {
                resolving = null
                session.showNotice("Couldn't resolve $name (error $code). Try again or enter its address.")
            }
            override fun onServiceResolved(info: NsdServiceInfo) = onMain {
                resolving = null
                val ip = pickAddress(info)
                if (ip == null) session.showNotice("Couldn't resolve $name. Enter its address instead.")
                else session.connect(HostAddress(ip.hostAddress ?: return@onMain, info.port), pair)
            }
        })
    }

    @Suppress("DEPRECATION")
    private fun pickAddress(info: NsdServiceInfo): InetAddress? =
        if (Build.VERSION.SDK_INT >= 34) info.hostAddresses.let { all -> all.firstOrNull { it is Inet4Address } ?: all.firstOrNull() }
        else info.host

    override fun onCleared() {
        session.disconnect()
        decoder.stop()
        if (discovery == Discovery.Starting || discovery == Discovery.Running) runCatching { nsd.stopServiceDiscovery(listener) }
    }

    private fun onMain(block: () -> Unit) { viewModelScope.launch { block() } }

    companion object {
        const val SERVICE_TYPE = "_tetherly._tcp."
        private const val MAX_DEVICES = 32
        private const val MAX_NAME = 63
        private const val KEY_MACS = "pairedMacs"
    }
}
